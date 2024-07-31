CREATE OR REPLACE FUNCTION timeit.overhead_cycles
(
    internal_function text,
    input_values text[],
    iterations bigint,
    core_id integer
)
RETURNS bigint
LANGUAGE c
AS '$libdir/timeit', 'overhead_cycles';
