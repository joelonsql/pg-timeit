CREATE OR REPLACE FUNCTION timeit.min_executions_r2(
    function_name text,
    input_values text[],
    r2_threshold float8,
    core_id integer,
    measure_type timeit.measure_type
)
RETURNS bigint
LANGUAGE plpgsql
AS $$
declare
    iterations bigint := 1;
    sum_x float8 := 0;
    sum_y float8 := 0;
    sum_xy float8 := 0;
    sum_x2 float8 := 0;
    sum_y2 float8 := 0;
    r_squared float8 := 0;
    clock_cycles bigint;
    measurements bigint[] := '{}';
    n integer;
    m float8;
    c float8;
begin
    if (r2_threshold between 0.99 and 1.0) is not true then
        raise exception 'r2_threshold must be between 0.99 and 1.0';
    end if;

    loop
        if measure_type = 'clock_cycles' then
            clock_cycles := timeit.measure_rdtsc(function_name, input_values, iterations, core_id);
        elsif measure_type = 'time' then
            clock_cycles := timeit.measure(function_name, input_values, iterations, core_id);
        else
            raise exception 'invalid measure_type %', measure_type;
        end if;

        measurements := array_append(measurements, clock_cycles);
        n := array_length(measurements, 1);

        if n > 1 then
            sum_x := 0;
            sum_y := 0;
            sum_xy := 0;
            sum_x2 := 0;
            sum_y2 := 0;
            for i in 1..n loop
                sum_x := sum_x + 2^(i-1);
                sum_y := sum_y + measurements[i];
                sum_xy := sum_xy + 2^(i-1) * measurements[i];
                sum_x2 := sum_x2 + (2^(i-1))^2;
                sum_y2 := sum_y2 + measurements[i]^2;
            end loop;

            if (n * sum_x2 - sum_x^2) <> 0 and (n * sum_y2 - sum_y^2) <> 0 then
                r_squared := (n * sum_xy - sum_x * sum_y)^2 / ((n * sum_x2 - sum_x^2) * (n * sum_y2 - sum_y^2));
                m := (n * sum_xy - sum_x * sum_y) / (n * sum_x2 - sum_x^2);
                c := (sum_y - m * sum_x) / n;
                if m > 0 and c >= 0 then
                    raise debug 'Predicted formula: y = % * x + %', m, c;
                else
                    raise debug 'Negative slope or overhead detected, continuing with more iterations.';
                    r_squared := 0; -- Reset r_squared to ensure continuation
                end if;
            else
                r_squared := 0;
            end if;

            if r_squared >= r2_threshold and m > 0 and c >= 0 then
                return iterations;
            end if;
        end if;

        iterations := iterations * 2;
    end loop;
end
$$;
