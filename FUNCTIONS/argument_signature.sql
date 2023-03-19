CREATE OR REPLACE FUNCTION pit.argument_signature(text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
SELECT CASE WHEN length($1) > 40 THEN
    format('%s chars (%s)', length($1), md5($1))
ELSE
    $1
END
$$;
