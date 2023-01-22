CREATE OR REPLACE FUNCTION timeit.eval(
    test_expression text,
    input_types text[],
    input_values text[]
)
RETURNS text
LANGUAGE plpgsql
AS $$
declare
    test_function text;
    args text;
    return_value text;
begin

    test_function := timeit.create_or_lookup_function(
        input_types,
        format(
            $_$
                begin
                    return (%1$s)::text;
                end
            $_$,
            test_expression
        ),
        'text'
    );

    SELECT string_agg(quote_literal(unnest),',')
    INTO args
    FROM unnest(input_values);

    execute format('SELECT timeit_hash_functions."%s"(%s)', test_function, args)
    into return_value;

    return return_value;

end
$$;
