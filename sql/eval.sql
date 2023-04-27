--
-- Verify timeit.eval() works correctly, used by timeit.work(),
-- which sets the timeit.test_params.return_value text column
-- to the result returned by the function tested.
--
CREATE EXTENSION timeit;
SELECT timeit.async('numeric_add',ARRAY['10','20']);
SET client_min_messages TO 'warning';
CALL timeit.work(return_when_idle := true);
SELECT return_value FROM timeit.test_params;
DROP EXTENSION timeit;
