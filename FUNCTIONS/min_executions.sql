CREATE OR REPLACE FUNCTION pit.min_executions(
    function_name text,
    input_values text[],
    min_time interval
)
RETURNS bigint
LANGUAGE plpgsql
AS $$
declare
    test_time bigint;
    executions bigint := 1;
    min_t bigint := extract(epoch from min_time) * 1e6;
begin

    if min_time is null then
        return executions;
    end if;

    loop

        test_time := pit.measure(function_name, input_values, executions);

        if test_time >= min_t then
            return executions;
        end if;

        executions := executions * 2 * (min_t / GREATEST(test_time,1));

    end loop;

end
$$;
