CREATE TABLE timeit.test_params (
    id bigint NOT NULL,
    input_values text[] NOT NULL,
    function_name text NOT NULL,
    significant_figures integer NOT NULL,
    attempts integer NOT NULL,
    min_time interval NOT NULL,
    return_value text,
    timeout interval,
    PRIMARY KEY (id),
    FOREIGN KEY (id) REFERENCES timeit.tests(id),
    CHECK (attempts >= 1)
);
