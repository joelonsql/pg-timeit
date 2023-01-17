CREATE EXTENSION timeit;

--
-- Enqueue new test.
--
SELECT timeit.async('pg_sleep(0.1)');

--
-- Work until there is no more work.
--
CALL timeit.work(return_when_idle := true);

--
-- Have a look at test results.
--
SELECT
    id,
    test_state,
    executions,
    final_result
FROM timeit.tests;
