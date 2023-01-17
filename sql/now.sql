BEGIN;

CREATE EXTENSION IF NOT EXISTS timeit;

SELECT timeit.now('pg_sleep(0.1)');

--
-- Request two significant figures in result.
--
SELECT timeit.now('pg_sleep(0.1)', 2);

--
-- Pass argument types/values separately.
--
SELECT timeit.now('pg_sleep($1)', '{numeric}', '{0.1}');

--
-- Pass argument types/values separately,
-- and request two significant figures in result.
--
SELECT timeit.now('pg_sleep($1)', '{numeric}', '{0.1}', 2);

ROLLBACK;
