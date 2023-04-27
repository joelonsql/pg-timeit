CREATE OR REPLACE FUNCTION timeit.overhead(
    executions bigint
)
RETURNS bigint
LANGUAGE c
AS '$libdir/timeit', 'overhead';
