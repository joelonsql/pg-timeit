CREATE EXTENSION timeit;

SELECT timeit.async('pg_sleep(0.1)');

SELECT
    id,
    test_state,
    executions,
    final_result
FROM timeit.tests;

CALL timeit.work();

SELECT
    id,
    test_state,
    executions,
    final_result
FROM timeit.tests;

CALL timeit.work();

SELECT
    id,
    test_state,
    executions,
    final_result
FROM timeit.tests;

CALL timeit.work();

SELECT
    id,
    test_state,
    executions,
    final_result
FROM timeit.tests;
