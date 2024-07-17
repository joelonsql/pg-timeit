CREATE OR REPLACE FUNCTION timeit.measure(
    internal_function text,
    input_values text[],
    executions bigint,
    core_id integer
)
RETURNS bigint
LANGUAGE c
AS '$libdir/timeit', 'measure_or_eval';
