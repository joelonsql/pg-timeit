CREATE OR REPLACE FUNCTION timeit.time_query(sql_query text)
RETURNS TABLE (planning_time double precision, execution_time double precision)
LANGUAGE c
AS '$libdir/timeit', 'time_query';
