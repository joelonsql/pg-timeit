--
-- Returns measured clock cycles as a float8
--
CREATE OR REPLACE FUNCTION timeit.c(
    function_name text,
    input_values text[] DEFAULT ARRAY[]::text[],
    significant_figures integer DEFAULT 1,
    timeout bigint DEFAULT NULL,
    attempts integer DEFAULT 1,
    core_id integer DEFAULT -1,
    r2_threshold float8 DEFAULT 0.99
)
RETURNS float8
LANGUAGE plpgsql
AS $$
<<fn>>
declare
    executions bigint;
    test_cycles_1 bigint;
    overhead_cycles_1 bigint;
    test_cycles_2 bigint;
    overhead_cycles_2 bigint;
    net_cycles_1 bigint;
    net_cycles_2 bigint;
    final_result float8;
    overhead_expression text;
    remaining_attempts integer;
begin

    if num_nulls(function_name,input_values,significant_figures,r2_threshold) <> 0
    then
        raise exception 'no arguments must be null';
    end if;
    if significant_figures < 1 then
        raise exception 'significant_figures must be positive';
    end if;

    executions := timeit.min_executions_r2(function_name, input_values, r2_threshold, core_id, 'clock_cycles');

    remaining_attempts := attempts;

    loop

        test_cycles_1 := timeit.measure_rdtsc(function_name, input_values, executions, core_id);
        overhead_cycles_1 := timeit.overhead_rdtsc(executions, core_id);

        test_cycles_2 := timeit.measure_rdtsc(function_name, input_values, executions, core_id);
        overhead_cycles_2 := timeit.overhead_rdtsc(executions, core_id);

        net_cycles_1 := test_cycles_1 - overhead_cycles_1;
        net_cycles_2 := test_cycles_2 - overhead_cycles_2;

        final_result := (net_cycles_1 + net_cycles_2)::float8 / (2 * executions)::float8;

        if
            timeit.round_to_sig_figs(net_cycles_1, significant_figures)
            =
            timeit.round_to_sig_figs(net_cycles_2, significant_figures)
        then
            return final_result;
        else

            raise notice '% clock cycles (% executions)', timeit.round_to_sig_figs(
                (net_cycles_1 + net_cycles_2)::numeric / (2 * executions)::numeric,
                significant_figures
            ), executions;

        end if;

        if
            least(net_cycles_1,net_cycles_2) * 2
            >
            timeout
        then

            executions := timeit.min_executions_r2(function_name, input_values, r2_threshold, core_id, 'clock_cycles');
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
