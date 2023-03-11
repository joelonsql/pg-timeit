CREATE OR REPLACE FUNCTION pit.round_to_sig_figs(numeric, integer)
RETURNS numeric
LANGUAGE sql
AS $$
SELECT round($1, $2 - 1 - floor(coalesce(log(nullif(abs($1),0)),0))::int);
$$;

CREATE OR REPLACE FUNCTION pit.round_to_sig_figs(bigint, integer)
RETURNS bigint
LANGUAGE sql
AS $$
SELECT round($1, $2 - 1 - floor(coalesce(log(nullif(abs($1),0)),0))::int);
$$;
