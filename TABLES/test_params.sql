CREATE TABLE timeit.test_params (
    id bigint NOT NULL,
    input_values text[] NOT NULL,
    test_expression text NOT NULL,
    significant_figures integer NOT NULL,
    return_value text,
    PRIMARY KEY (id),
    FOREIGN KEY (id) REFERENCES timeit.tests(id)
);
