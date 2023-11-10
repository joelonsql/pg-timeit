--
-- Returns measured execution_time in seconds for both functions.
--
CREATE OR REPLACE FUNCTION timeit.cmp(
    function_name_a text,
    function_name_b text,
    input_values_a text[] DEFAULT ARRAY[]::text[],
    input_values_b text[] DEFAULT ARRAY[]::text[],
    timeout interval DEFAULT '1 ms'::interval,
    INOUT executions bigint DEFAULT 1,
    OUT total_time_a numeric,
    OUT total_time_b numeric
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
    total_time_a_1 bigint;
    total_time_a_2 bigint;
    total_time_b_1 bigint;
    total_time_b_2 bigint;
    overhead_time bigint;
    t0 timestamptz;
begin

    if num_nulls(function_name_a,function_name_b,input_values_a,input_values_b) <> 0
    then
        raise exception 'no arguments must be null';
    end if;

    t0 := clock_timestamp();
    loop

        test_time_a_1 := timeit.measure(function_name_a, input_values_a, executions);
        test_time_b_1 := timeit.measure(function_name_b, input_values_b, executions);
        overhead_time := timeit.overhead(executions);
        test_time_a_2 := timeit.measure(function_name_a, input_values_a, executions);
        test_time_b_2 := timeit.measure(function_name_b, input_values_b, executions);

        total_time_a_1 := test_time_a_1 - overhead_time;
        total_time_b_1 := test_time_b_1 - overhead_time;
        total_time_a_2 := test_time_a_2 - overhead_time;
        total_time_b_2 := test_time_b_2 - overhead_time;

        total_time_a := (total_time_a_1 + total_time_a_2);
        total_time_b := (total_time_b_1 + total_time_b_2);

        if least(total_time_a_1,total_time_a_2) > 0
        and least(total_time_b_1,total_time_b_2) > 0
        and (greatest(total_time_a_1,total_time_a_2) < least(total_time_b_1,total_time_b_2)
            or least(total_time_a_1,total_time_a_2) > greatest(total_time_b_1,total_time_b_2)
            or clock_timestamp()-t0 > timeout)
        then
            executions := executions * 4;
            return;
        else
            executions := executions * 2;
        end if;

    end loop;

end
$$;
