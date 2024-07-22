EXTENSION = timeit
MODULES = timeit
DATA = \
	timeit--1.0.sql

REGRESS = \
	immediate \
	async \
	eval

EXTRA_CLEAN = timeit--1.0.sql

PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

all: timeit--1.0.sql

SQL_SRC = \
	complain_header.sql \
	TYPES/test_state.sql \
	TYPES/measure_type.sql \
	TABLES/tests.sql \
	TABLES/test_params.sql \
	FUNCTIONS/trim_scale.sql \
	FUNCTIONS/round_to_sig_figs.sql \
	FUNCTIONS/measure.sql \
	FUNCTIONS/measure_rdtsc.sql \
	FUNCTIONS/min_executions.sql \
	FUNCTIONS/compute_regression_metrics.sql \
	FUNCTIONS/min_executions_r2.sql \
	FUNCTIONS/overhead.sql \
	FUNCTIONS/overhead_rdtsc.sql \
	FUNCTIONS/eval.sql \
	FUNCTIONS/f.sql \
	FUNCTIONS/s.sql \
	FUNCTIONS/cmp.sql \
	FUNCTIONS/pretty_time.sql \
	FUNCTIONS/h.sql \
	FUNCTIONS/async.sql \
	FUNCTIONS/c.sql \
	PROCEDURES/work.sql \
	PROCEDURES/measure_cold.sql \
	VIEWS/report.sql

timeit--1.0.sql: $(SQL_SRC)
	cat $^ > $@
