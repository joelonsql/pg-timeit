--
-- Returns measured execution_time in human-readable output,
-- using time unit suffixes, i.e. "ns", "us", "ms".
--
CREATE OR REPLACE FUNCTION pit.pretty_time(numeric)
RETURNS text
LANGUAGE sql
AS $$
SELECT
    CASE
        WHEN log10($1) >= 0 THEN format('%s s', $1)
        WHEN log10($1) >= -3 THEN format('%s ms', trim_scale($1 * 1e3))
        WHEN log10($1) >= -6 THEN format('%s µs', trim_scale($1 * 1e6))
        ELSE format('%s ns', trim_scale($1 * 1e9))
    END
$$;
