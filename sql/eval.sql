--
-- Verify pit.eval() works correctly, used by pit.work(),
-- which sets the pit.test_params.return_value text column
-- to the result returned by the function tested.
--
CREATE EXTENSION pit;
SELECT pit.async('numeric_add',ARRAY['10','20']);
SET client_min_messages TO 'warning';
CALL pit.work(return_when_idle := true);
SELECT return_value FROM pit.test_params;
DROP EXTENSION pit;
