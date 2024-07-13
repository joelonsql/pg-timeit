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
    min_time interval DEFAULT '10 ms'::interval
)
RETURNS numeric
LANGUAGE SQL
BEGIN ATOMIC
    SELECT timeit.round_to_sig_figs(
        timeit.f($1,$2,$3,$4,$5,$6)::numeric,
        $3
    );
END;
