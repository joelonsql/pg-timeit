BEGIN;

CREATE EXTENSION IF NOT EXISTS timeit;

SELECT timeit.s('pg_sleep', ARRAY['0.1']);
SELECT timeit.h('pg_sleep', ARRAY['0.1']);

--
-- Request two significant figures in result.
--
SELECT timeit.h('pg_sleep', ARRAY['0.1'], 2);

ROLLBACK;
