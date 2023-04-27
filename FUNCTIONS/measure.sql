CREATE OR REPLACE FUNCTION timeit.measure(
    internal_function text,
    input_values text[],
    executions bigint
)
RETURNS bigint
LANGUAGE c
AS '$libdir/timeit', 'measure_or_eval';
