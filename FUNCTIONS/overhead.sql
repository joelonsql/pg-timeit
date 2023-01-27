CREATE OR REPLACE FUNCTION pit.overhead(
    executions bigint
)
RETURNS bigint
LANGUAGE c
AS '$libdir/pit', 'overhead';
