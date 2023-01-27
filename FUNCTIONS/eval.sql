CREATE OR REPLACE FUNCTION pit.eval(
    internal_function text,
    input_values text[]
)
RETURNS text
LANGUAGE c
AS '$libdir/pit', 'measure_or_eval';
