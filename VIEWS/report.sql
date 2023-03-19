CREATE OR REPLACE VIEW pit.report AS
WITH
data AS
(
    SELECT
        tests.id,
        pit.function_signature(test_params.function_name, test_params.input_values),
        tests.final_result,
        test_params.significant_figures,
        tests.executions
    FROM pit.tests
    JOIN pit.test_params USING (id)
),
stats AS
(
    SELECT
        function_signature,
        AVG(final_result) AS avg,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY final_result)::numeric AS median,
        STDDEV_SAMP(final_result) AS stddev,
        COUNT(final_result) AS n,
        MIN(significant_figures) AS significant_figures,
        AVG(executions)::bigint AS executions
    FROM data
    GROUP BY function_signature
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
    function_signature,
    pit.pretty_time(avg, significant_figures) AS avg,
    pit.pretty_time(median, significant_figures) AS median,
    pit.pretty_time(stddev, significant_figures) AS stddev,
    format('[%s-%s]',
        pit.pretty_time(ci_lower, significant_figures),
        pit.pretty_time(ci_upper, significant_figures)
    ) AS ci,
    n,
    executions
FROM ci;
