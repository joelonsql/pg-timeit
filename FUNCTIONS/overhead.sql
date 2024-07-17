CREATE OR REPLACE FUNCTION timeit.overhead(
    executions bigint,
    core_id int
)
RETURNS bigint
LANGUAGE c
AS '$libdir/timeit', 'overhead';
