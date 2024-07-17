CREATE OR REPLACE PROCEDURE timeit.work(return_when_idle boolean DEFAULT false)
LANGUAGE plpgsql
AS $$
<<fn>>
declare
-- input:
    id bigint;
    test_state timeit.test_state;
    function_name text;
    input_values text[];
    significant_figures integer;
-- state data:
    executions bigint;
    test_time_1 bigint;
    overhead_time_1 bigint;
    test_time_2 bigint;
    overhead_time_2 bigint;
    net_time_1 bigint;
    net_time_2 bigint;
    final_result numeric;
    last_run timestamptz;
    idle boolean := true;
    queue_count bigint;
    return_value text;
    timeout interval;
    attempts integer;
    min_time interval;
    remaining_attempts integer;
    core_id integer;
begin

loop

    SELECT count(*)
    INTO queue_count
    FROM timeit.tests
    WHERE tests.test_state <> 'final';

    if queue_count <> 0 then
        if idle then
            raise notice '% working', clock_timestamp()::timestamptz(0);
            idle := false;
        end if;
        raise notice '% % in queue', clock_timestamp()::timestamptz(0), queue_count;
    else
        if not idle then
            raise notice '% idle', clock_timestamp()::timestamptz(0);
            idle := true;
        end if;
        if return_when_idle then
            return;
        end if;
        perform pg_sleep(1);
        continue;
    end if;

    for
        id,
        test_state,
        function_name,
        input_values,
        significant_figures,
        executions,
        test_time_1,
        overhead_time_1,
        test_time_2,
        overhead_time_2,
        timeout,
        attempts,
        min_time,
        remaining_attempts,
        core_id
    in
        SELECT
            tests.id,
            tests.test_state,
            test_params.function_name,
            test_params.input_values,
            test_params.significant_figures,
            tests.executions,
            tests.test_time_1,
            tests.overhead_time_1,
            tests.test_time_2,
            tests.overhead_time_2,
            test_params.timeout,
            test_params.attempts,
            test_params.min_time,
            tests.remaining_attempts,
            test_params.core_id
        FROM timeit.tests
        JOIN timeit.test_params ON test_params.id = tests.id
        WHERE tests.test_state <> 'final'
        ORDER BY RANDOM()
    loop

        begin

            if test_state = 'init' then

                executions := timeit.min_executions(function_name, input_values, min_time, core_id);

                UPDATE timeit.tests SET
                    test_state = 'run_test_1',
                    executions = fn.executions,
                    last_run = clock_timestamp()
                WHERE tests.id = fn.id;

                return_value := timeit.eval(function_name, input_values);

                UPDATE timeit.test_params SET
                    return_value = fn.return_value
                WHERE test_params.id = fn.id;

            elsif test_state = 'run_test_1' then

                /* Warm-up two times with identical calls. */
                test_time_1 := timeit.measure(function_name, input_values, executions, core_id);
                test_time_1 := timeit.measure(function_name, input_values, executions, core_id);
                /* Measure. */
                test_time_1 := timeit.measure(function_name, input_values, executions, core_id);

                overhead_time_1 := timeit.overhead(executions, core_id);

                UPDATE timeit.tests SET
                    test_state = 'run_test_2',
                    test_time_1 = fn.test_time_1,
                    overhead_time_1 = fn.overhead_time_1,
                    last_run = clock_timestamp()
                WHERE tests.id = fn.id;

            elsif test_state = 'run_test_2' then

                /* Warm-up two times with identical calls. */
                test_time_2 := timeit.measure(function_name, input_values, executions, core_id);
                test_time_2 := timeit.measure(function_name, input_values, executions, core_id);
                /* Measure. */
                test_time_2 := timeit.measure(function_name, input_values, executions, core_id);

                overhead_time_2 := timeit.overhead(executions, core_id);

                net_time_1 := test_time_1 - overhead_time_1;
                net_time_2 := test_time_2 - overhead_time_2;

                if
                    LEAST(net_time_1,net_time_2)
                    >
                    extract(epoch from min_time) * 1e6
                and
                    timeit.round_to_sig_figs(net_time_1, significant_figures)
                    =
                    timeit.round_to_sig_figs(net_time_2, significant_figures)
                then

                    final_result := timeit.round_to_sig_figs(
                        (net_time_1 + net_time_2)::numeric / (2 * executions * 1e6)::numeric,
                        significant_figures
                    );

                    UPDATE timeit.tests SET
                        test_state = 'final',
                        test_time_2 = fn.test_time_2,
                        overhead_time_2 = fn.overhead_time_2,
                        final_result = fn.final_result,
                        last_run = clock_timestamp()
                    WHERE tests.id = fn.id;

                else

                    if
                        least(net_time_1,net_time_2) * 2
                        >
                        extract(epoch from timeout) * 1e6
                    then

                        if remaining_attempts = 0 then

                            significant_figures := significant_figures - 1;
                            remaining_attempts := attempts;

                            if significant_figures < 1 then
                                raise exception 'timeout, unable to produce result';
                            end if;

                            raise notice 'timeout test id %, will try significant_figures %', id, significant_figures;

                            UPDATE timeit.test_params SET
                                significant_figures = fn.significant_figures
                            WHERE test_params.id = fn.id;

                            UPDATE timeit.tests SET
                                test_state = 'init',
                                executions = NULL,
                                test_time_1 = NULL,
                                overhead_time_1 = NULL,
                                test_time_2 = NULL,
                                overhead_time_2 = NULL,
                                remaining_attempts = fn.remaining_attempts,
                                final_result = NULL,
                                last_run = NULL,
                                error = NULL
                            WHERE tests.id = fn.id;

                        else

                            remaining_attempts := remaining_attempts - 1;
                            executions := 1;

                            raise notice 'timeout test id %, % remaining attempts at same precision', id, remaining_attempts;

                            UPDATE timeit.tests SET
                                test_state = 'run_test_1',
                                executions = fn.executions,
                                remaining_attempts = fn.remaining_attempts,
                                test_time_2 = fn.test_time_2,
                                overhead_time_2 = fn.overhead_time_2,
                                last_run = clock_timestamp()
                            WHERE tests.id = fn.id;

                        end if;

                        continue;

                    end if;

                    executions := executions * 2;

                    UPDATE timeit.tests SET
                        test_state = 'run_test_1',
                        executions = fn.executions,
                        test_time_2 = fn.test_time_2,
                        overhead_time_2 = fn.overhead_time_2,
                        last_run = clock_timestamp()
                    WHERE tests.id = fn.id;

                end if;

            else

                continue;

            end if;

        exception when others then

            UPDATE timeit.tests SET
                test_state = 'final',
                error = SQLERRM
            WHERE tests.id = fn.id;

        end;

        COMMIT;

    end loop;

end loop;

end
$$;
