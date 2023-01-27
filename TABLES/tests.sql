CREATE TABLE pit.tests (
    id bigint NOT NULL GENERATED ALWAYS AS IDENTITY,
    test_state pit.test_state NOT NULL,
    executions bigint,
    test_time_1 bigint,
    overhead_time_1 bigint,
    test_time_2 bigint,
    overhead_time_2 bigint,
    final_result numeric,
    last_run timestamptz,
    error text,
    PRIMARY KEY (id),
    CHECK ((test_time_1 IS NULL) = (overhead_time_1 IS NULL)),
    CHECK ((test_time_2 IS NULL) = (overhead_time_2 IS NULL)),
    CHECK ((final_result IS NOT NULL OR error IS NOT NULL) = (test_state = 'final'))
);

CREATE INDEX ON pit.tests (last_run) WHERE test_state <> 'final';
