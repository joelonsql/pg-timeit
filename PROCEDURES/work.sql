CREATE OR REPLACE PROCEDURE timeit.work(return_when_idle boolean DEFAULT false)
LANGUAGE plpgsql
AS $$
<<fn>>
declare
-- input:
    id bigint;
    test_state timeit.test_state;
    test_expression text;
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
    overhead_expression text;
    idle boolean := true;
    queue_count bigint;
    return_value text;
begin

loop

    SELECT count(*)
    INTO queue_count
    FROM timeit.tests
    WHERE tests.test_state <> 'final';

    if queue_count <> 0 then
        if idle then
            raise notice 'working';
            idle := false;
        end if;
        raise notice '% in queue', queue_count;
    else
        if not idle then
            raise notice 'idle';
            idle := true;
        end if;
        if return_when_idle then
            return;
        end if;
        perform pg_sleep(1);
        continue;
    end if;

    --
    -- Use '1' as `test_expression` for the overhead measurement,
    -- which inside timeit.measure() will expand to `count(1)`.
    -- The value `1` is just picked arbitrary.
    -- It might be tempting to use `null` instead, since `count(null)` is
    -- cheaper than `count(1)`, but since the actual test measurement
    -- will also do a `count()`, it should be more accurate to include
    -- the operation in the overhead time, so that it's included in
    -- what is subtracted from the test time.
    --
    overhead_expression := '1';

    for
        id,
        test_state,
        test_expression,
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
            test_params.test_expression,
            test_params.input_values,
            test_params.significant_figures,
            tests.executions,
            tests.test_time_1,
            tests.overhead_time_1,
            tests.test_time_2,
            tests.overhead_time_2
        FROM timeit.tests
        JOIN timeit.test_params ON test_params.id = tests.id
        WHERE tests.test_state <> 'final'
        ORDER BY random()
    loop

        begin

            if test_state = 'init' then

                executions := 1;

                UPDATE timeit.tests SET
                    test_state = 'run_test_1',
                    executions = fn.executions,
                    last_run = clock_timestamp()
                WHERE tests.id = fn.id;

-- TODO: Implement timeit.eval() in C that returns result in text.
--                return_value := timeit.eval(test_expression, input_types, input_values);

                UPDATE timeit.test_params SET
                    return_value = fn.return_value
                WHERE test_params.id = fn.id;

            elsif test_state = 'run_test_1' then

                test_time_1 := timeit.measure(test_expression, input_values, executions);
                overhead_time_1 := timeit.overhead(executions);

                UPDATE timeit.tests SET
                    test_state = 'run_test_2',
                    test_time_1 = fn.test_time_1,
                    overhead_time_1 = fn.overhead_time_1,
                    last_run = clock_timestamp()
                WHERE tests.id = fn.id;

            elsif test_state = 'run_test_2' then

                test_time_2 := timeit.measure(test_expression, input_values, executions);
                overhead_time_2 := timeit.overhead(executions);

                net_time_1 := test_time_1 - overhead_time_1;
                net_time_2 := test_time_2 - overhead_time_2;

                if
                    least(net_time_1,net_time_2)
                    >
                    (10 ^ significant_figures)
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
