--
-- Returns measured execution_time in human-readable output,
-- using time unit suffixes, i.e. "ns", "us", "ms".
--
CREATE OR REPLACE FUNCTION timeit.pretty_time(numeric)
RETURNS text
LANGUAGE sql
SET search_path = timeit, public, pg_temp
AS $$
SELECT
    CASE
        WHEN $1 IS NULL THEN 'NULL'
        WHEN log10(nullif(abs($1),0)) >= 0 THEN format('%s s', $1)
        WHEN log10(nullif(abs($1),0)) >= -3 THEN format('%s ms', trim_scale($1 * 1e3))
        WHEN log10(nullif(abs($1),0)) >= -6 THEN format('%s µs', trim_scale($1 * 1e6))
        WHEN log10(nullif(abs($1),0)) >= -9 THEN format('%s ns', trim_scale($1 * 1e9))
        ELSE format('%s s', $1::float8::text)
    END
$$;

CREATE OR REPLACE FUNCTION timeit.pretty_time(numeric, significant_figures integer)
RETURNS text
LANGUAGE sql
AS $$
SELECT timeit.pretty_time(timeit.round_to_sig_figs($1, $2))
$$;
