--
-- Returns measured execution_time in seconds.
--
CREATE OR REPLACE FUNCTION pit.s(
    function_name text,
    input_values text[] DEFAULT ARRAY[]::text[],
    significant_figures integer DEFAULT 1,
    timeout interval DEFAULT NULL,
    attempts integer DEFAULT 1,
    min_time interval DEFAULT '10 ms'::interval
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
    remaining_attempts integer;
    min_t bigint := extract(epoch from min_time) * 1e6;
begin

    if num_nulls(function_name,input_values,significant_figures) <> 0
    then
        raise exception 'no arguments must be null';
    end if;
    if significant_figures < 1 then
        raise exception 'significant_figures must be positive';
    end if;

    if not timeout > min_time * 2 then
        raise exception 'timeout must be larger than at least twice the min_time';
    end if;

    executions := pit.min_executions(function_name, input_values, min_time);

    remaining_attempts := attempts;

    loop

        test_time_1 := pit.measure(function_name, input_values, executions);
        overhead_time_1 := pit.overhead(executions);

        test_time_2 := pit.measure(function_name, input_values, executions);
        overhead_time_2 := pit.overhead(executions);

        net_time_1 := test_time_1 - overhead_time_1;
        net_time_2 := test_time_2 - overhead_time_2;

        if
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

        if
            least(net_time_1,net_time_2) * 2
            >
            extract(epoch from timeout) * 1e6
        then

            executions := pit.min_executions(function_name, input_values, min_time);
            if remaining_attempts = 0 then
                remaining_attempts := attempts;
                significant_figures := significant_figures - 1;
                if significant_figures < 1 then
                    raise notice 'timeout, unable to produce result';
                    return null;
                end if;
                raise notice 'timeout, will try significant_figures %', significant_figures;
            else
                remaining_attempts := remaining_attempts - 1;
                raise notice 'timeout, % remaining attempts at same precision', remaining_attempts;
            end if;

            continue;

        end if;

        executions := executions * 2;

    end loop;

end
$$;
