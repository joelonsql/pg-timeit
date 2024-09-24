CREATE OR REPLACE FUNCTION timeit.time_query(sql_query text)
RETURNS TABLE (
    planning_time double precision,
    execution_time double precision,
    cpu_cycles bigint,
    instructions bigint,
    cache_references bigint,
    cache_misses bigint
)
LANGUAGE c
AS '$libdir/timeit', 'time_query';
