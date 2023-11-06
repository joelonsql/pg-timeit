--
-- Returns measured execution_time in seconds for both functions.
--
CREATE OR REPLACE FUNCTION timeit.cmp(
    OUT execution_time_a numeric,
    OUT execution_time_b numeric,
    OUT executions bigint,
    function_name_a text,
    function_name_b text,
    input_values_a text[] DEFAULT ARRAY[]::text[],
    input_values_b text[] DEFAULT ARRAY[]::text[],
    significant_figures integer DEFAULT 1,
    timeout interval DEFAULT NULL,
    attempts integer DEFAULT 1,
    min_time interval DEFAULT '10 ms'::interval
)
RETURNS RECORD
LANGUAGE plpgsql
AS $$
<<fn>>
declare
    test_time_a_1 bigint;
    test_time_a_2 bigint;
    test_time_b_1 bigint;
    test_time_b_2 bigint;
    overhead_time_a_1 bigint;
    overhead_time_a_2 bigint;
    overhead_time_b_1 bigint;
    overhead_time_b_2 bigint;
    net_time_a_1 bigint;
    net_time_a_2 bigint;
    net_time_b_1 bigint;
    net_time_b_2 bigint;
    execution_time_a_1 numeric;
    execution_time_a_2 numeric;
    execution_time_b_1 numeric;
    execution_time_b_2 numeric;
    overhead_expression text;
    remaining_attempts integer;
    min_t bigint := extract(epoch from min_time) * 1e6;
begin

    if num_nulls(function_name_a,function_name_b,input_values_a,input_values_b,significant_figures) <> 0
    then
        raise exception 'no arguments must be null';
    end if;
    if significant_figures < 1 then
        raise exception 'significant_figures must be positive';
    end if;

    if not timeout > min_time * 2 then
        raise exception 'timeout must be larger than at least twice the min_time';
    end if;

    executions := GREATEST(
        timeit.min_executions(function_name_a, input_values_a, min_time),
        timeit.min_executions(function_name_b, input_values_b, min_time)
    );

    remaining_attempts := attempts;

    loop

        test_time_a_1 := timeit.measure(function_name_a, input_values_a, executions);
        overhead_time_a_1 := timeit.overhead(executions);
        test_time_b_1 := timeit.measure(function_name_b, input_values_b, executions);
        overhead_time_b_1 := timeit.overhead(executions);

        test_time_a_2 := timeit.measure(function_name_a, input_values_a, executions);
        overhead_time_a_2 := timeit.overhead(executions);
        test_time_b_2 := timeit.measure(function_name_b, input_values_b, executions);
        overhead_time_b_2 := timeit.overhead(executions);

        net_time_a_1 := test_time_a_1 - overhead_time_a_1;
        net_time_b_1 := test_time_b_1 - overhead_time_b_1;
        net_time_a_2 := test_time_a_2 - overhead_time_a_2;
        net_time_b_2 := test_time_b_2 - overhead_time_b_2;

        execution_time_a_1 := timeit.round_to_sig_figs(net_time_a_1::numeric / (executions * 1e6)::numeric, significant_figures);
        execution_time_b_1 := timeit.round_to_sig_figs(net_time_b_1::numeric / (executions * 1e6)::numeric, significant_figures);
        execution_time_a_2 := timeit.round_to_sig_figs(net_time_a_2::numeric / (executions * 1e6)::numeric, significant_figures);
        execution_time_b_2 := timeit.round_to_sig_figs(net_time_b_2::numeric / (executions * 1e6)::numeric, significant_figures);

        execution_time_a := timeit.round_to_sig_figs(
            (net_time_a_1 + net_time_a_2)::numeric / (2 * executions * 1e6)::numeric,
            significant_figures
        );
        execution_time_b := timeit.round_to_sig_figs(
            (net_time_b_1 + net_time_b_2)::numeric / (2 * executions * 1e6)::numeric,
            significant_figures
        );

        raise notice '% vs % (% executions) [%,%] vs [%,%]',
            timeit.pretty_time(execution_time_a),
            timeit.pretty_time(execution_time_b),
            executions,
            timeit.pretty_time(execution_time_a_1),
            timeit.pretty_time(execution_time_a_2),
            timeit.pretty_time(execution_time_b_1),
            timeit.pretty_time(execution_time_b_2);


        if  execution_time_a_1 = execution_time_a_2
        and execution_time_b_1 = execution_time_b_2
        then
            return;
        end if;

        if
            least(net_time_a_1,net_time_a_2,net_time_b_1,net_time_b_2) * 2
            >
            extract(epoch from timeout) * 1e6
        then

            executions := GREATEST(
                timeit.min_executions(function_name_a, input_values_a, min_time),
                timeit.min_executions(function_name_b, input_values_b, min_time)
            );
            if remaining_attempts = 0 then
                remaining_attempts := attempts;
                significant_figures := significant_figures - 1;
                if significant_figures < 1 then
                    raise notice 'timeout, returning final result anyway';
                    return;
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
