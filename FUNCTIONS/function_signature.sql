CREATE OR REPLACE FUNCTION pit.function_signature(text,text[])
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
SELECT
    format('%s(%s)',$1,string_agg(pit.argument_signature(unnest),',' ORDER BY ORDINALITY))
FROM unnest($2) WITH ORDINALITY
$$;
