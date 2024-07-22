CREATE OR REPLACE FUNCTION timeit.min_executions_r2(
    function_name text,
    input_values text[],
    r2_threshold float8,
    core_id integer,
    measure_type timeit.measure_type,
    timeout interval DEFAULT '1 second'::interval
)
RETURNS bigint
LANGUAGE plpgsql
AS $$
declare
    iterations bigint := 1;
    res float8;
    y float8[] := '{}';
    x float8[] := '{}';
    n integer;
    r_squared float8;
    m float8;
    c float8;
    t0 timestamptz;
begin
    if (r2_threshold between 0.99 and 0.99999) is not true then
        raise exception 'r2_threshold must be between 0.99 and 0.99999';
    end if;

    t0 := clock_timestamp();
    loop
        if measure_type = 'clock_cycles' then
            res := timeit.measure_rdtsc(function_name, input_values, iterations, core_id)::float8;
        elsif measure_type = 'time' then
            res := timeit.measure(function_name, input_values, iterations, core_id)::float8;
        else
            raise exception 'invalid measure_type %', measure_type;
        end if;

        y := array_append(y, res);
        x := array_append(x, iterations::float8);
        n := array_length(y, 1);

        if n >= 3 then
            --
            -- The first measurements could be noisy, so let's only look at
            -- up to three of the last values.
            --
            SELECT r.r_squared, r.m, r.c
            INTO r_squared, m, c
            FROM timeit.compute_regression_metrics(x[n-2:n], y[n-2:n]) AS r;

            raise debug 'Predicted formula: y = % * x + %, r_squared = %, iterations = %', m, c, r_squared, iterations;

            if (m > 0 and c >= 0) is not true then
                raise debug 'Negative slope or overhead detected, continuing with more iterations.';
                r_squared := 0; -- Reset r_squared to ensure continuation
            end if;

            if r_squared >= r2_threshold and m > 0 and c > 0 then
                return iterations;
            end if;
        end if;

        --
        -- Return if we've spent more than timeout already.
        --
        if clock_timestamp() - t0 > timeout then
            raise debug 'Timeout';
            return iterations;
        end if;

        iterations := iterations * 2;
    end loop;
end
$$;
