CREATE OR REPLACE FUNCTION timeit.compute_regression_metrics
(
    x float8[],
    y float8[]
)
RETURNS TABLE
(
    r_squared float8,
    m float8,
    c float8
)
LANGUAGE plpgsql
AS $$
declare
    sum_x float8 := 0;
    sum_y float8 := 0;
    sum_xy float8 := 0;
    sum_x2 float8 := 0;
    sum_y2 float8 := 0;
    n integer := array_length(x, 1);
begin
    if (n >= 2) is not true then
        raise exception 'input arrays must have at least two elements';
    end if;
    if n is distinct from array_length(y, 1) then
        raise exception 'input arrays must be of same length';
    end if;

    for i in 1..n loop
        sum_x := sum_x + x[i];
        sum_y := sum_y + y[i];
        sum_xy := sum_xy + x[i] * y[i];
        sum_x2 := sum_x2 + x[i]^2;
        sum_y2 := sum_y2 + y[i]^2;
    end loop;

    if (n * sum_x2 - sum_x^2) <> 0 and (n * sum_y2 - sum_y^2) <> 0 then
        r_squared := (n * sum_xy - sum_x * sum_y)^2 / ((n * sum_x2 - sum_x^2) * (n * sum_y2 - sum_y^2));
        m := (n * sum_xy - sum_x * sum_y) / (n * sum_x2 - sum_x^2);
        c := (sum_y - m * sum_x) / n;
        return next;
    end if;
end
$$;
