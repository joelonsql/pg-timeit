#!/bin/sh
psql -X -q -c "CALL pit.work()"
