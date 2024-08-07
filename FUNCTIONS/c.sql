--
-- Returns measured clock cycles as a bigint,
-- rounded to significant_figures
--
CREATE OR REPLACE FUNCTION timeit.c
(
    function_name text,
    input_values text[],
    significant_figures integer DEFAULT 1,
    r_squared_threshold float8 DEFAULT 0.99,
    sample_size integer DEFAULT 10,
    timeout interval DEFAULT '1 second'::interval,
    core_id integer DEFAULT -1 /* -1 means let the OS schedule CPU core */
)
RETURNS bigint
LANGUAGE SQL AS
$$
    SELECT timeit.round_to_sig_figs(measure.slope::bigint, significant_figures)
    FROM timeit.measure(function_name, input_values, r_squared_threshold,
                        sample_size, timeout, 'cycles', core_id);
$$;
