CREATE OR REPLACE FUNCTION timeit.measure
(
    function_name text,
    input_values text[],
    r_squared_threshold float8 DEFAULT 0.99,
    sample_size integer DEFAULT 10,
    timeout interval DEFAULT '1 second'::interval,
    measure_type timeit.measure_type DEFAULT 'time',
    core_id integer DEFAULT -1 /* -1 means let the OS schedule CPU core */
)
RETURNS TABLE
(
    x float8[],
    y float8[],
    r_squared float8,
    slope float8,
    intercept float8,
    iterations bigint
)
LANGUAGE plpgsql
AS $$
declare
    res float8;
    n integer;
    t0 timestamptz;
    is_timeout boolean;
begin
    if (r_squared_threshold between 0.99 and 0.99999) is not true then
        raise exception 'r_squared_threshold must be between 0.99 and 0.99999';
    end if;

    iterations := 1;
    x := ARRAY[]::float8[];
    y := ARRAY[]::float8[];
    t0 := clock_timestamp();
    loop
        if measure_type = 'cycles' then
            res := timeit.measure_cycles(function_name, input_values, iterations, core_id)::float8;
        elsif measure_type = 'time' then
            res := timeit.measure_time(function_name, input_values, iterations, core_id)::float8;
        else
            raise exception 'invalid measure_type %', measure_type;
        end if;

        y := array_append(y, res);
        x := array_append(x, iterations::float8);
        n := array_length(y, 1);

        is_timeout := clock_timestamp() - t0 > timeout;

        if n >= sample_size or (n >= 2 and is_timeout) then
            SELECT r.r_squared, r.slope, r.intercept
            INTO r_squared, slope, intercept
            FROM timeit.compute_regression_metrics(x[n-sample_size+1:n], y[n-sample_size+1:n]) AS r;

            raise debug 'Predicted formula: y = % * x + %, r_squared = %, iterations = %', slope, intercept, r_squared, iterations;

            if r_squared >= r_squared_threshold and slope > 0 then
                return next;
                return;
            end if;

            if is_timeout then
                raise debug 'Timeout';
                return next;
                return;
            end if;
        end if;

        iterations := iterations * 2;
    end loop;
end
$$;
