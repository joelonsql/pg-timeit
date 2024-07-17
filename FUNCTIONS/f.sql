--
-- Returns measured execution_time in seconds,
-- as a float8, without rounding to significant_figures.
--
CREATE OR REPLACE FUNCTION timeit.f(
    function_name text,
    input_values text[] DEFAULT ARRAY[]::text[],
    significant_figures integer DEFAULT 1,
    timeout interval DEFAULT NULL,
    attempts integer DEFAULT 1,
    min_time interval DEFAULT '10 ms'::interval,
    core_id integer DEFAULT -1
)
RETURNS float8
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
    final_result float8;
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

    executions := timeit.min_executions(function_name, input_values, min_time, core_id);

    remaining_attempts := attempts;

    loop

        test_time_1 := timeit.measure(function_name, input_values, executions, core_id);
        overhead_time_1 := timeit.overhead(executions, core_id);

        test_time_2 := timeit.measure(function_name, input_values, executions, core_id);
        overhead_time_2 := timeit.overhead(executions, core_id);

        net_time_1 := test_time_1 - overhead_time_1;
        net_time_2 := test_time_2 - overhead_time_2;

        final_result := (net_time_1 + net_time_2)::float8 / (2 * executions * 1e6)::float8;

        if
            timeit.round_to_sig_figs(net_time_1, significant_figures)
            =
            timeit.round_to_sig_figs(net_time_2, significant_figures)
        then
            return final_result;
        else

            raise notice '% (% executions)', timeit.pretty_time(timeit.round_to_sig_figs(
                (net_time_1 + net_time_2)::numeric / (2 * executions * 1e6)::numeric,
                significant_figures
            )), executions;

        end if;

        if
            least(net_time_1,net_time_2) * 2
            >
            extract(epoch from timeout) * 1e6
        then

            executions := timeit.min_executions(function_name, input_values, min_time, core_id);
            if remaining_attempts = 0 then
                remaining_attempts := attempts;
                significant_figures := significant_figures - 1;
                if significant_figures < 1 then
                    raise notice 'timeout, returning final_result anyway';
                    return final_result;
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
