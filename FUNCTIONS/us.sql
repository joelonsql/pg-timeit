--
-- Returns measured execution_time in microseconds.
--
CREATE OR REPLACE FUNCTION pit.us(
    function_name text,
    input_values text[] DEFAULT ARRAY[]::text[],
    significant_figures integer DEFAULT 1
)
RETURNS numeric
LANGUAGE sql
AS $$
SELECT trim_scale(pit.s($1,$2,$3) * 1e6)
$$;
