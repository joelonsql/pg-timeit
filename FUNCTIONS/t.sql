--
-- Returns measured execution time in human-readable output,
-- using time unit suffixes, i.e. "ns", "us", "ms".
--
CREATE OR REPLACE FUNCTION timeit.t
(
    function_name text,
    input_values text[],
    significant_figures integer DEFAULT 1,
    r_squared_threshold float8 DEFAULT 0.99,
    sample_size integer DEFAULT 10,
    timeout interval DEFAULT '1 second'::interval,
    core_id integer DEFAULT -1 /* -1 means let the OS schedule CPU core */
)
RETURNS text
LANGUAGE SQL AS
$$
    -- slope value is in microseconds for measure_type 'time'
    SELECT timeit.pretty_time((measure.slope/1e6)::numeric, significant_figures)
    FROM timeit.measure(function_name, input_values, r_squared_threshold,
                        sample_size, timeout, 'time', core_id);
$$;
