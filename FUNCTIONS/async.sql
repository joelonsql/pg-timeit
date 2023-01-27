CREATE OR REPLACE FUNCTION pit.async(
    function_name text,
    input_values text[] DEFAULT ARRAY[]::text[],
    significant_figures integer DEFAULT 1
)
RETURNS bigint
LANGUAGE plpgsql
AS $$
<<fn>>
declare
    id bigint;
begin

    if num_nulls(function_name,input_values,significant_figures) <> 0
    then
        raise exception 'no arguments must be null';
    end if;

    INSERT INTO pit.tests
        (test_state)
    VALUES
        ('init')
    RETURNING tests.id INTO id;

    INSERT INTO pit.test_params
        (id, function_name, input_values, significant_figures)
    VALUES
        (id, function_name, input_values, significant_figures);

    return id;

end
$$;

CREATE OR REPLACE FUNCTION pit.async(
    function_name text,
    significant_figures integer
)
RETURNS numeric
LANGUAGE sql
AS $$
SELECT pit.async($1,ARRAY[]::text[],$2);
$$;
