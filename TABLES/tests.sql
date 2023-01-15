CREATE TABLE timeit.tests (
    id bigint NOT NULL GENERATED ALWAYS AS IDENTITY,
    test_state timeit.test_state NOT NULL DEFAULT 'init',
    test_hash bytea NOT NULL,
    -- test parameters:
    input_types text[] NOT NULL,
    input_values text[] NOT NULL,
    test_expression text NOT NULL,
    significant_figures integer NOT NULL,
    -- state:
    base_overhead_time numeric,
    base_test_time numeric,
    executions bigint,
    test_time_1 numeric,
    overhead_time_1 numeric,
    test_time_2 numeric,
    overhead_time_2 numeric,
    final_result numeric,
    last_run timestamptz,
    error text,
    PRIMARY KEY (id),
    UNIQUE (test_hash),
    CHECK (cardinality(input_types) = cardinality(input_values)),
    CHECK ((base_overhead_time IS NULL) = (base_test_time IS NULL)),
    CHECK ((test_time_1 IS NULL) = (overhead_time_1 IS NULL)),
    CHECK ((test_time_2 IS NULL) = (overhead_time_2 IS NULL)),
    CHECK ((final_result IS NOT NULL OR error IS NOT NULL) = (test_state = 'final'))
);

CREATE INDEX ON timeit.tests (last_run) WHERE test_state <> 'final';
