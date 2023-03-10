--
-- Returns measured execution_time in seconds.
--
CREATE OR REPLACE FUNCTION pit.s(
    function_name text,
    input_values text[] DEFAULT ARRAY[]::text[],
    significant_figures integer DEFAULT 1,
    timeout interval DEFAULT NULL
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

    if num_nulls(function_name,input_values,significant_figures) <> 0
    then
        raise exception 'no arguments must be null';
    end if;
    if significant_figures < 1 then
        raise exception 'significant_figures must be positive';
    end if;

    executions := 1;

    loop

        test_time_1 := pit.measure(function_name, input_values, executions);
        overhead_time_1 := pit.overhead(executions);

        test_time_2 := pit.measure(function_name, input_values, executions);
        overhead_time_2 := pit.overhead(executions);

        net_time_1 := test_time_1 - overhead_time_1;
        net_time_2 := test_time_2 - overhead_time_2;

        if
            least(net_time_1,net_time_2) * 2
            >
            extract(epoch from timeout) * 1e6
        then

            significant_figures := significant_figures - 1;
            executions := 1;
            if significant_figures < 1 then
                raise notice 'timeout, unable to produce result';
                return null;
            end if;
            raise notice 'timeout, will try significant_figures %', significant_figures;
            continue;

        end if;

        if
            least(net_time_1,net_time_2)
            >
            (10 ^ significant_figures) * 2
        and
            pit.round_to_sig_figs(net_time_1, significant_figures)
            =
            pit.round_to_sig_figs(net_time_2, significant_figures)
        then

            final_result := pit.round_to_sig_figs(
                (net_time_1 + net_time_2)::numeric / (2 * executions * 1e6)::numeric,
                significant_figures
            );

            return final_result;

        else

            raise notice '% (% executions)', pit.pretty_time(pit.round_to_sig_figs(
                (net_time_1 + net_time_2)::numeric / (2 * executions * 1e6)::numeric,
                significant_figures
            )), executions;

        end if;

        executions := executions * 2;

    end loop;

end
$$;
