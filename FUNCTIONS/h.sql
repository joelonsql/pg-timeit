--
-- Returns measured execution_time in human-readable output,
-- using time unit suffixes, i.e. "ns", "us", "ms".
--
CREATE OR REPLACE FUNCTION pit.h(
    function_name text,
    input_values text[] DEFAULT ARRAY[]::text[],
    significant_figures integer DEFAULT 1
)
RETURNS text
LANGUAGE sql
AS $$
WITH t(s) AS MATERIALIZED (VALUES(pit.s($1,$2,$3)))
SELECT
    CASE
        WHEN log10(s) >= 0 THEN format('%s s', s)
        WHEN log10(s) >= -3 THEN format('%s ms', trim_scale(s * 1e3))
        WHEN log10(s) >= -6 THEN format('%s µs', trim_scale(s * 1e6))
        ELSE format('%s ns', trim_scale(s * 1e9))
    END
FROM t
$$;
