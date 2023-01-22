EXTENSION = timeit
DATA = \
	timeit--1.0.sql

REGRESS = \
	now \
	async

EXTRA_CLEAN = timeit--1.0.sql

PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

all: timeit--1.0.sql

SQL_SRC = \
	complain_header.sql \
	TYPES/test_state.sql \
	TABLES/tests.sql \
	TABLES/test_params.sql \
	FUNCTIONS/round_to_sig_figs.sql \
	SCHEMAS/timeit_hash_functions.sql \
	FUNCTIONS/create_or_lookup_function.sql \
	FUNCTIONS/measure.sql \
	FUNCTIONS/eval.sql \
	FUNCTIONS/now.sql \
	FUNCTIONS/async.sql \
	PROCEDURES/work.sql

timeit--1.0.sql: $(SQL_SRC)
	cat $^ > $@
