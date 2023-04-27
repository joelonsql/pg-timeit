--
-- Returns measured execution_time in human-readable output,
-- using time unit suffixes, i.e. "ns", "us", "ms".
--
CREATE OR REPLACE FUNCTION timeit.h(
    function_name text,
    input_values text[] DEFAULT ARRAY[]::text[],
    significant_figures integer DEFAULT 1,
    timeout interval DEFAULT NULL,
    attempts integer DEFAULT 1,
    min_time interval DEFAULT '10 ms'::interval
)
RETURNS text
LANGUAGE sql
AS $$
SELECT timeit.pretty_time(timeit.s($1,$2,$3,$4,$5,$6))
$$;
