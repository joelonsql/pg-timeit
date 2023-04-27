/*
 *  View that shows the variance of the measurements. Note that this says
 *  very little about the variance of the execution time for the functions being
 *  measured, which is something completely different and not shown here.
 */
CREATE OR REPLACE VIEW timeit.report AS
WITH
data AS
(
    SELECT
        test_params.function_name,
        test_params.input_values,
        tests.final_result,
        test_params.significant_figures,
        tests.executions
    FROM timeit.tests
    JOIN timeit.test_params USING (id)
),
stats AS
(
    SELECT
        function_name,
        input_values,
        AVG(final_result) AS avg,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY final_result)::numeric AS median,
        STDDEV_SAMP(final_result) AS stddev,
        COUNT(final_result) AS n,
        MIN(significant_figures) AS significant_figures,
        AVG(executions)::bigint AS executions
    FROM data
    GROUP BY function_name, input_values
),
ci AS
(
    SELECT
        *,
        (avg - 1.96 * stddev / sqrt(n))::numeric AS ci_lower,
        (avg + 1.96 * stddev / sqrt(n))::numeric AS ci_upper
    FROM stats
)
SELECT
    function_name,
    input_values,
    timeit.pretty_time(avg, significant_figures) AS avg,
    timeit.pretty_time(median, significant_figures) AS median,
    timeit.pretty_time(stddev, significant_figures) AS stddev,
    format('[%s-%s]',
        timeit.pretty_time(ci_lower, significant_figures),
        timeit.pretty_time(ci_upper, significant_figures)
    ) AS ci,
    n,
    executions,
    avg AS avg_numeric
FROM ci;
