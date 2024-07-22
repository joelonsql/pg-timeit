CREATE OR REPLACE FUNCTION timeit.measure_cycles
(
    internal_function text,
    input_values text[],
    iterations bigint,
    core_id integer
)
RETURNS bigint
LANGUAGE c
AS '$libdir/timeit', 'measure_cycles';
