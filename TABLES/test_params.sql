CREATE TABLE pit.test_params (
    id bigint NOT NULL,
    input_values text[] NOT NULL,
    function_name text NOT NULL,
    significant_figures integer NOT NULL,
    attempts integer NOT NULL,
    return_value text,
    timeout interval,
    PRIMARY KEY (id),
    FOREIGN KEY (id) REFERENCES pit.tests(id),
    CHECK (attempts >= 1)
);
