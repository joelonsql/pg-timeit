BEGIN;

CREATE EXTENSION IF NOT EXISTS timeit;

SELECT timeit.now('pg_sleep(0.05)');

SELECT timeit.now('pg_sleep(0.1)', 2);

SELECT timeit.now('pg_sleep($1)', '{numeric}', '{0.13}');

SELECT timeit.now('pg_sleep($1)', '{numeric}', '{0.13}', 2);

ROLLBACK;
