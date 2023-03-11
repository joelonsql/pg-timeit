--
-- Returns measured execution_time in human-readable output,
-- using time unit suffixes, i.e. "ns", "us", "ms".
--
CREATE OR REPLACE FUNCTION pit.h(
    function_name text,
    input_values text[] DEFAULT ARRAY[]::text[],
    significant_figures integer DEFAULT 1,
    timeout interval DEFAULT NULL
)
RETURNS text
LANGUAGE sql
AS $$
SELECT pit.pretty_time(pit.s($1,$2,$3,$4))
$$;
