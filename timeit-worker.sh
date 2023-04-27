#!/bin/sh
psql -X -q -c "CALL timeit.work()"
