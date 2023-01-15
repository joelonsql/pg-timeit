CREATE OR REPLACE FUNCTION timeit.round_to_sig_figs(numeric, integer)
RETURNS numeric
LANGUAGE sql
AS $$
SELECT round($1, $2 - 1 - floor(log($1))::int);
$$;
