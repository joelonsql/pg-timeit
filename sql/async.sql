CREATE EXTENSION timeit;

--
-- Enqueue new test.
--
SELECT timeit.async('pg_sleep',ARRAY['0.1']);

--
-- Work until there is no more work.
--
-- Ignore notice messages since we can't know how
-- many iterations that will be necessary.
--
SET client_min_messages TO 'warning';
CALL timeit.work(return_when_idle := true);

--
-- Have a look at test result.
--
SELECT
    id,
    test_state,
    executions,
    final_result
FROM timeit.tests;

DROP EXTENSION timeit;
