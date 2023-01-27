CREATE OR REPLACE PROCEDURE pit.work(return_when_idle boolean DEFAULT false)
LANGUAGE plpgsql
AS $$
<<fn>>
declare
-- input:
    id bigint;
    test_state pit.test_state;
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
begin

loop

    SELECT count(*)
    INTO queue_count
    FROM pit.tests
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
        overhead_time_2
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
            tests.overhead_time_2
        FROM pit.tests
        JOIN pit.test_params ON test_params.id = tests.id
        WHERE tests.test_state <> 'final'
        ORDER BY random()
    loop

        begin

            if test_state = 'init' then

                executions := 1;

                UPDATE pit.tests SET
                    test_state = 'run_test_1',
                    executions = fn.executions,
                    last_run = clock_timestamp()
                WHERE tests.id = fn.id;

                return_value := pit.eval(function_name, input_values);

                UPDATE pit.test_params SET
                    return_value = fn.return_value
                WHERE test_params.id = fn.id;

            elsif test_state = 'run_test_1' then

                test_time_1 := pit.measure(function_name, input_values, executions);
                overhead_time_1 := pit.overhead(executions);

                UPDATE pit.tests SET
                    test_state = 'run_test_2',
                    test_time_1 = fn.test_time_1,
                    overhead_time_1 = fn.overhead_time_1,
                    last_run = clock_timestamp()
                WHERE tests.id = fn.id;

            elsif test_state = 'run_test_2' then

                test_time_2 := pit.measure(function_name, input_values, executions);
                overhead_time_2 := pit.overhead(executions);

                net_time_1 := test_time_1 - overhead_time_1;
                net_time_2 := test_time_2 - overhead_time_2;

                if
                    least(net_time_1,net_time_2)
                    >
                    (10 ^ significant_figures)
                and
                    pit.round_to_sig_figs(net_time_1, significant_figures)
                    =
                    pit.round_to_sig_figs(net_time_2, significant_figures)
                then

                    final_result := pit.round_to_sig_figs(
                        (net_time_1 + net_time_2)::numeric / (2 * executions * 1e6)::numeric,
                        significant_figures
                    );

                    UPDATE pit.tests SET
                        test_state = 'final',
                        test_time_2 = fn.test_time_2,
                        overhead_time_2 = fn.overhead_time_2,
                        final_result = fn.final_result,
                        last_run = clock_timestamp()
                    WHERE tests.id = fn.id;

                else

                    executions := executions * 2;

                    UPDATE pit.tests SET
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

            UPDATE pit.tests SET
                test_state = 'final',
                error = SQLERRM
            WHERE tests.id = fn.id;

        end;

        COMMIT;

    end loop;

end loop;

end
$$;
