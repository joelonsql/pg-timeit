DO $$
BEGIN
    -- Check if the 'trim_scale' function exists in the 'pg_catalog' schema
    IF NOT EXISTS (
        SELECT 1
        FROM pg_proc
        WHERE proname = 'trim_scale'
        AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'pg_catalog')
    ) THEN
        -- Create the 'trim_scale' function if it doesn't exist
        EXECUTE
        $_$
            CREATE OR REPLACE FUNCTION timeit.trim_scale(numeric) RETURNS numeric AS
            $__$
                DECLARE
                    trimmed numeric;
                BEGIN
                    -- Convert the numeric to text, trim trailing zeros and then convert back to numeric
                    SELECT regexp_replace($1::text, '\.?0+$', '')::numeric INTO trimmed;
                    RETURN trimmed;
                END;
            $__$ LANGUAGE plpgsql IMMUTABLE;
        $_$;
    END IF;
END $$;
