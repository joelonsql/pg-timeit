--
-- Returns measured execution_time in seconds,
-- rounded to significant_figures.
--
CREATE OR REPLACE FUNCTION timeit.s(
    function_name text,
    input_values text[] DEFAULT ARRAY[]::text[],
    significant_figures integer DEFAULT 1,
    timeout interval DEFAULT NULL,
    attempts integer DEFAULT 1,
    min_time interval DEFAULT '10 ms'::interval,
    core_id integer DEFAULT -1
)
RETURNS numeric
LANGUAGE sql
AS $$
    SELECT timeit.round_to_sig_figs(
        timeit.f($1,$2,$3,$4,$5,$6,$7)::numeric,
        $3
    );
$$;
