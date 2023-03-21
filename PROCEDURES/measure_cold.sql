CREATE OR REPLACE PROCEDURE pit.measure_cold(internal_function text, input_values text[], executions bigint, n bigint)
LANGUAGE plpgsql AS
$$
declare

    nonsense bigint;
    measurements numeric[] := ARRAY[]::numeric[];
    sig_figs int := 2;

begin

    for i in 1..n loop

        perform pg_sleep(0.2);

        measurements := measurements ||
        (
            pit.measure(internal_function, input_values, executions)::numeric
            /
            executions::numeric
        );

        raise debug '%', measurements[cardinality(measurements)];

        COMMIT;

    end loop;

    raise notice '%',
    (
        WITH
        data AS
        (
            SELECT unnest/1e6 AS t FROM unnest(measurements)
        ),
        stats AS
        (
            SELECT
                AVG(t) AS avg,
                PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY t)::numeric AS median,
                STDDEV_SAMP(t) AS stddev,
                string_agg(pit.pretty_time(t,sig_figs),' ') AS vals
            FROM data
        ),
        ci AS
        (
            SELECT
                *,
                (avg - 1.96 * stddev / sqrt(n))::numeric AS lo,
                (avg + 1.96 * stddev / sqrt(n))::numeric AS hi
            FROM stats
        )
        SELECT format('(avg %s) (median %s) (95%% CI [%s, %s]) (σ %s) (n %s) (%s)',
                        pit.pretty_time(avg,sig_figs),
                        pit.pretty_time(median,sig_figs),
                        pit.pretty_time(lo,sig_figs),
                        pit.pretty_time(hi,sig_figs),
                        pit.pretty_time(stddev,sig_figs),
                        n,
                        vals
                     )
        FROM ci
    );

end
$$;
