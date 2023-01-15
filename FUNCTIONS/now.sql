CREATE OR REPLACE FUNCTION timeit.now(
    test_expression text,
    input_types text[] DEFAULT ARRAY[]::text[],
    input_values text[] DEFAULT ARRAY[]::text[],
    significant_figures integer DEFAULT 1
)
RETURNS numeric
LANGUAGE plpgsql
AS $$
<<fn>>
declare
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
    overhead_expression text;
begin

    if num_nulls(test_expression,input_types,input_values,significant_figures) <> 0
    then
        raise exception 'no arguments must be null';
    end if;

    if cardinality(input_types) <> cardinality(input_values)
    then
        raise exception 'different number of input types and input values';
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

    --
    -- We first want to get a rough idea of how long time a single overhead
    -- operation and a single test expression takes. This will help us
    -- scale up the initial number of executions to something reasonable,
    -- instead of starting at 1.
    --

    base_overhead_time := timeit.measure('1', input_types, input_values, 1);
    base_test_time := timeit.measure(test_expression, input_types, input_values, 1);

    executions := greatest(
        1,
        (10 ^ significant_figures) * (base_overhead_time / base_test_time)
    );

    loop

        test_time_1 := timeit.measure(test_expression, input_types, input_values, executions);
        overhead_time_1 := timeit.measure('1', input_types, input_values, executions);

        test_time_2 := timeit.measure(test_expression, input_types, input_values, executions);
        overhead_time_2 := timeit.measure('1', input_types, input_values, executions);

        net_time_1 := test_time_1 - overhead_time_1;
        net_time_2 := test_time_2 - overhead_time_2;

        if
            least(net_time_1,net_time_2)
            >
            base_overhead_time * (10 ^ significant_figures)
        then

            if timeit.round_to_sig_figs(net_time_1, significant_figures)
             = timeit.round_to_sig_figs(net_time_2, significant_figures)
            then

                final_result := timeit.round_to_sig_figs(
                    (net_time_1 + net_time_2) / (2 * executions)::numeric,
                    significant_figures
                );

                return final_result;

            end if;

        end if;

        executions := executions * 2;

    end loop;

end
$$;

CREATE OR REPLACE FUNCTION timeit.now(
    test_expression text,
    significant_figures integer
)
RETURNS numeric
LANGUAGE sql
AS $$
SELECT timeit.now($1,ARRAY[]::text[],ARRAY[]::text[],$2);
$$;
