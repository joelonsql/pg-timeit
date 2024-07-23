EXTENSION = timeit
MODULES = timeit
DATA = timeit--1.0.sql
REGRESS = create_extension \
	t \
	eval \
	pretty_time
EXTRA_CLEAN = timeit--1.0.sql
PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

all: timeit--1.0.sql

SQL_SRC = \
	complain_header.sql \
	TYPES/measure_type.sql \
	FUNCTIONS/trim_scale.sql \
	FUNCTIONS/round_to_sig_figs.sql \
	FUNCTIONS/pretty_time.sql \
	FUNCTIONS/compute_regression_metrics.sql \
	FUNCTIONS/measure_time.sql \
	FUNCTIONS/measure_cycles.sql \
	FUNCTIONS/eval.sql \
	FUNCTIONS/measure.sql \
	FUNCTIONS/t.sql \
	FUNCTIONS/c.sql

timeit--1.0.sql: $(SQL_SRC)
	cat $^ > $@
