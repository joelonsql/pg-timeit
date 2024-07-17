CREATE OR REPLACE FUNCTION timeit.async(
    function_name text,
    input_values text[] DEFAULT ARRAY[]::text[],
    significant_figures integer DEFAULT 1,
    timeout interval DEFAULT NULL,
    attempts integer DEFAULT 1,
    min_time interval DEFAULT '10 ms'::interval,
    core_id integer DEFAULT -1
)
RETURNS bigint
LANGUAGE plpgsql
AS $$
<<fn>>
declare
    id bigint;
begin

    if num_nulls(function_name,input_values,significant_figures,attempts) <> 0
    then
        raise exception 'no arguments must be null';
    end if;

    INSERT INTO timeit.tests
        (test_state, remaining_attempts)
    VALUES
        ('init', attempts)
    RETURNING tests.id INTO id;

    INSERT INTO timeit.test_params
        (id, function_name, input_values, significant_figures, timeout, attempts, min_time, core_id)
    VALUES
        (id, function_name, input_values, significant_figures, timeout, attempts, min_time, core_id);

    return id;

end
$$;

CREATE OR REPLACE FUNCTION timeit.async(
    function_name text,
    significant_figures integer
)
RETURNS bigint
LANGUAGE sql
AS $$
SELECT timeit.async($1,ARRAY[]::text[],$2);
$$;
