--
-- Returns measured execution_time in seconds for both functions.
--
CREATE OR REPLACE FUNCTION timeit.cmp(
    OUT execution_time_a numeric,
    OUT execution_time_b numeric,
    OUT total_time_a numeric,
    OUT total_time_b numeric,
    OUT executions bigint,
    function_name_a text,
    function_name_b text,
    input_values_a text[] DEFAULT ARRAY[]::text[],
    input_values_b text[] DEFAULT ARRAY[]::text[],
    min_time interval DEFAULT '10 ms',
    timeout interval DEFAULT '1 second'
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
    avg_overhead_time bigint;
    total_time_a_1 bigint;
    total_time_a_2 bigint;
    total_time_b_1 bigint;
    total_time_b_2 bigint;
    execution_time_a_1 numeric;
    execution_time_a_2 numeric;
    execution_time_b_1 numeric;
    execution_time_b_2 numeric;
    t_a_1 numeric;
    t_a_2 numeric;
    t_b_1 numeric;
    t_b_2 numeric;
    significant_figures int;
begin

    if num_nulls(function_name_a,function_name_b,input_values_a,input_values_b) <> 0
    then
        raise exception 'no arguments must be null';
    end if;

    executions := GREATEST(
        timeit.min_executions(function_name_a, input_values_a, min_time),
        timeit.min_executions(function_name_b, input_values_b, min_time)
    );

    significant_figures := 1;

    loop

        test_time_a_1 := timeit.measure(function_name_a, input_values_a, executions);
        overhead_time_a_1 := timeit.overhead(executions);
        test_time_b_1 := timeit.measure(function_name_b, input_values_b, executions);
        overhead_time_b_1 := timeit.overhead(executions);
        test_time_a_2 := timeit.measure(function_name_a, input_values_a, executions);
        overhead_time_a_2 := timeit.overhead(executions);
        test_time_b_2 := timeit.measure(function_name_b, input_values_b, executions);
        overhead_time_b_2 := timeit.overhead(executions);

        avg_overhead_time := (overhead_time_a_1 + overhead_time_b_1 + overhead_time_a_2 + overhead_time_b_2) / 4;

        total_time_a_1 := test_time_a_1 - avg_overhead_time;
        total_time_b_1 := test_time_b_1 - avg_overhead_time;
        total_time_a_2 := test_time_a_2 - avg_overhead_time;
        total_time_b_2 := test_time_b_2 - avg_overhead_time;

        t_a_1 := timeit.round_to_sig_figs(total_time_a_1, significant_figures);
        t_a_2 := timeit.round_to_sig_figs(total_time_a_2, significant_figures);
        t_b_1 := timeit.round_to_sig_figs(total_time_b_1, significant_figures);
        t_b_2 := timeit.round_to_sig_figs(total_time_b_2, significant_figures);

        execution_time_a := timeit.round_to_sig_figs(
            (total_time_a_1 + total_time_a_2)::numeric / (2 * executions * 1e6)::numeric,
            significant_figures
        );
        execution_time_b := timeit.round_to_sig_figs(
            (total_time_b_1 + total_time_b_2)::numeric / (2 * executions * 1e6)::numeric,
            significant_figures
        );

        total_time_a := (total_time_a_1 + total_time_a_2) / 2;
        total_time_b := (total_time_b_1 + total_time_b_2) / 2;

        raise notice '% vs % (% executions) [%,%] vs [%,%]',
            timeit.pretty_time(execution_time_a),
            timeit.pretty_time(execution_time_b),
            executions,
            t_a_1,
            t_a_2,
            t_b_1,
            t_b_2;

        -- Return anyway if we're near timeout.
        if
            least(total_time_a_1,total_time_a_2,total_time_b_1,total_time_b_2) * 2
            >
            extract(epoch from timeout) * 1e6
        then
            return;
        end if;

        -- Double the number of executions until measurements
        -- are non-zero and converge.
        if  t_a_1 > 0
        and t_b_1 > 0
        and t_a_1 = t_a_2
        and t_b_1 = t_b_2
        then
            -- Increase sig. figs until we can tell a difference.
            if t_a_1 = t_b_1 then
                significant_figures := significant_figures + 1;
            else
                return;
            end if;
        else
            executions := executions * 2;
        end if;

    end loop;

end
$$;
