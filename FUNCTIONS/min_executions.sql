CREATE OR REPLACE FUNCTION timeit.min_executions(
    function_name text,
    input_values text[],
    significant_figures int
)
RETURNS bigint
LANGUAGE plpgsql
AS $$
declare
    test_time bigint;
    executions bigint := 1;
    min_t bigint := 10^significant_figures;
begin

    loop

        test_time := timeit.measure(function_name, input_values, executions);

        if test_time >= min_t then
            return executions;
        end if;

        executions := executions * 2 * (min_t / GREATEST(test_time,1));

    end loop;

end
$$;
