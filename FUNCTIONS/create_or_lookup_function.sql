CREATE OR REPLACE FUNCTION timeit.create_or_lookup_function(
    argtypes text[],
    function_definition text,
    rettype text
)
RETURNS text
LANGUAGE plpgsql
AS $$
declare

    function_name text;

begin

    function_name := encode(sha224(convert_to(format(
        '%L%L%L',
        argtypes::text,
        function_definition,
        rettype
    ),'utf8')),'hex');

    if not exists (
        select 1 from pg_proc
        join pg_namespace on pg_namespace.oid = pg_proc.pronamespace
        where pg_proc.proname = function_name
        and pg_namespace.nspname = 'timeit_hash_functions'
    ) then
        execute format(
            $_$
                CREATE OR REPLACE FUNCTION timeit_hash_functions."%1$s"(%2$s)
                RETURNS %3$s
                LANGUAGE plpgsql
                AS
                $_%1$s_$
                    %4$s
                $_%1$s_$;
            $_$,
            function_name,
            array_to_string(argtypes,','),
            rettype,
            function_definition
        );
    end if;

    return function_name;

end
$$;
