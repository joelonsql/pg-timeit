CREATE OR REPLACE FUNCTION timeit.overhead_rdtsc(
    executions bigint,
    core_id int
)
RETURNS bigint
LANGUAGE c
AS '$libdir/timeit', 'overhead_rdtsc';
