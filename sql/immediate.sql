BEGIN;

CREATE EXTENSION IF NOT EXISTS pit;

SELECT pit.s('pg_sleep', ARRAY['0.1']);
SELECT pit.ms('pg_sleep', ARRAY['0.1']);
SELECT pit.us('pg_sleep', ARRAY['0.1']);
SELECT pit.ns('pg_sleep', ARRAY['0.1']);

--
-- Request two significant figures in result.
--
SELECT pit.ms('pg_sleep', ARRAY['0.1'], 2);

ROLLBACK;
