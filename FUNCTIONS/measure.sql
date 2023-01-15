CREATE OR REPLACE FUNCTION timeit.measure(
    test_expression text,
    input_types text[],
    input_values text[],
    executions bigint
)
RETURNS numeric
LANGUAGE plpgsql
AS $$
declare
    test_function text;
    args text;
    test_time numeric;
begin

    test_function := timeit.create_or_lookup_function(
        array_append(input_types,'bigint'),
        format(
            $_$
                declare
                    start_time timestamptz;
                    end_time timestamptz;
                    elapsed_time numeric;
                begin
                    start_time := clock_timestamp();
                    perform count(%1$s) from generate_series(1,%2$s);
                    end_time := clock_timestamp();
                    elapsed_time := extract(seconds from end_time - start_time);
                    return elapsed_time;
                end
            $_$,
            test_expression,
            '$'||(cardinality(input_types)+1)
        ),
        'numeric'
    );

    SELECT string_agg(quote_literal(unnest),',')
    INTO args
    FROM unnest(array_append(input_values,executions::text));

    execute format('SELECT pg_temp."%s"(%s)', test_function, args)
    into test_time;

    return test_time;

end
$$;
