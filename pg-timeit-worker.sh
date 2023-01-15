#!/bin/sh
while true ; do psql -X -q -c "CALL timeit.work()" ; sleep 1 ; done
