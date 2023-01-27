CREATE OR REPLACE FUNCTION pit.measure(
    internal_function text,
    input_values text[],
    executions bigint
)
RETURNS bigint
LANGUAGE c
AS '$libdir/pit', 'measure_or_eval';
