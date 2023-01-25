CREATE OR REPLACE FUNCTION timeit.now(
    test_expression text,
    input_values text[] DEFAULT ARRAY[]::text[],
    significant_figures integer DEFAULT 1
)
RETURNS numeric
LANGUAGE plpgsql
AS $$
<<fn>>
declare
    executions bigint;
    test_time_1 bigint;
    overhead_time_1 bigint;
    test_time_2 bigint;
    overhead_time_2 bigint;
    net_time_1 bigint;
    net_time_2 bigint;
    final_result numeric;
    overhead_expression text;
begin

    if num_nulls(test_expression,input_values,significant_figures) <> 0
    then
        raise exception 'no arguments must be null';
    end if;

    executions := 1;

    loop

        test_time_1 := timeit.measure(test_expression, input_values, executions);
        overhead_time_1 := timeit.overhead(executions);

        test_time_2 := timeit.measure(test_expression, input_values, executions);
        overhead_time_2 := timeit.overhead(executions);

        net_time_1 := test_time_1 - overhead_time_1;
        net_time_2 := test_time_2 - overhead_time_2;

        if
            least(net_time_1,net_time_2)
            >
            (10 ^ significant_figures)
        then

            if timeit.round_to_sig_figs(net_time_1, significant_figures)
             = timeit.round_to_sig_figs(net_time_2, significant_figures)
            then

                final_result := timeit.round_to_sig_figs(
                    (net_time_1 + net_time_2)::numeric / (2 * executions * 1e6)::numeric,
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
