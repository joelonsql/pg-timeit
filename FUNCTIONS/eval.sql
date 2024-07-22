CREATE OR REPLACE FUNCTION timeit.eval
(
    internal_function text,
    input_values text[]
)
RETURNS text
LANGUAGE c
AS '$libdir/timeit', 'eval';
