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
    test_hash bytea;
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

    test_hash := sha256(
        convert_to(
            format(
                '%L%L%L%L',
                test_expression,
                input_types::text,
                input_values::text,
                significant_figures
            ),
            'utf8'
        )
    );

    SELECT
        tests.id
    INTO
        id
    FROM timeit.tests
    WHERE tests.test_hash = fn.test_hash;

    if found then
        return id;
    end if;

    INSERT INTO timeit.tests
        (test_hash, test_expression, input_types, input_values, significant_figures)
    VALUES
        (test_hash, test_expression, input_types, input_values, significant_figures)
    RETURNING tests.id INTO id;

    return id;

end
$$;
