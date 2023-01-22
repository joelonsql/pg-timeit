CREATE OR REPLACE FUNCTION timeit.async(
    test_expression text,
    input_types text[] DEFAULT ARRAY[]::text[],
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

    if num_nulls(test_expression,input_types,input_values,significant_figures) <> 0
    then
        raise exception 'no arguments must be null';
    end if;

    if cardinality(input_types) <> cardinality(input_values)
    then
        raise exception 'different number of input types and input values';
    end if;

    INSERT INTO timeit.tests
        (test_state)
    VALUES
        ('init')
    RETURNING tests.id INTO id;

    INSERT INTO timeit.test_params
        (id, test_expression, input_types, input_values, significant_figures)
    VALUES
        (id, test_expression, input_types, input_values, significant_figures);

    return id;

end
$$;

CREATE OR REPLACE FUNCTION timeit.async(
    test_expression text,
    significant_figures integer
)
RETURNS numeric
LANGUAGE sql
AS $$
SELECT timeit.async($1,ARRAY[]::text[],ARRAY[]::text[],$2);
$$;
