CREATE OR REPLACE PROCEDURE timeit.work()
LANGUAGE plpgsql
AS $$
<<fn>>
declare
-- input:
    id bigint;
    test_state timeit.test_state;
    test_expression text;
    input_types text[];
    input_values text[];
    significant_figures integer;
-- state data:
    base_overhead_time numeric;
    base_test_time numeric;
    executions bigint;
    test_time_1 numeric;
    overhead_time_1 numeric;
    test_time_2 numeric;
    overhead_time_2 numeric;
    net_time_1 numeric;
    net_time_2 numeric;
    final_result numeric;
    last_run timestamptz;
    overhead_expression text;
begin

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
    input_types,
    input_values,
    significant_figures,
    base_overhead_time,
    base_test_time,
    executions,
    test_time_1,
    overhead_time_1,
    test_time_2,
    overhead_time_2
in
    SELECT
        tests.id,
        tests.test_state,
        tests.test_expression,
        tests.input_types,
        tests.input_values,
        tests.significant_figures,
        tests.base_overhead_time,
        tests.base_test_time,
        tests.executions,
        tests.test_time_1,
        tests.overhead_time_1,
        tests.test_time_2,
        tests.overhead_time_2
    FROM timeit.tests
    WHERE tests.test_state <> 'final'
    ORDER BY tests.last_run NULLS FIRST
loop

    begin

        if test_state = 'init' then

            RAISE NOTICE 'test id % initialized', id;

            base_overhead_time := timeit.measure(overhead_expression, input_types, input_values, 1);
            base_test_time := timeit.measure(test_expression, input_types, input_values, 1);
            executions := greatest(
                1,
                (10 ^ significant_figures) * (base_overhead_time / base_test_time)
            );

            UPDATE timeit.tests SET
                test_state = 'run_test_1',
                base_overhead_time = fn.base_overhead_time,
                base_test_time = fn.base_test_time,
                executions = fn.executions,
                last_run = clock_timestamp()
            WHERE tests.id = fn.id;

        elsif test_state = 'run_test_1' then

            test_time_1 := timeit.measure(test_expression, input_types, input_values, executions);
            overhead_time_1 := timeit.measure(overhead_expression, input_types, input_values, executions);

            UPDATE timeit.tests SET
                test_state = 'run_test_2',
                test_time_1 = fn.test_time_1,
                overhead_time_1 = fn.overhead_time_1,
                last_run = clock_timestamp()
            WHERE tests.id = fn.id;

        elsif test_state = 'run_test_2' then

            test_time_2 := timeit.measure(test_expression, input_types, input_values, executions);
            overhead_time_2 := timeit.measure(overhead_expression, input_types, input_values, executions);

            net_time_1 := test_time_1 - overhead_time_1;
            net_time_2 := test_time_2 - overhead_time_2;

            if
                least(net_time_1,net_time_2)
                >
                base_overhead_time * (10 ^ significant_figures)
            and
                timeit.round_to_sig_figs(net_time_1, significant_figures)
                =
                timeit.round_to_sig_figs(net_time_2, significant_figures)
            then
                final_result := timeit.round_to_sig_figs(
                    (net_time_1 + net_time_2) / (2 * executions)::numeric,
                    significant_figures
                );

                UPDATE timeit.tests SET
                    test_state = 'final',
                    test_time_2 = fn.test_time_2,
                    overhead_time_2 = fn.overhead_time_2,
                    final_result = fn.final_result,
                    last_run = clock_timestamp()
                WHERE tests.id = fn.id;

                RAISE NOTICE 'test id % finalized', id;

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

end
$$;
