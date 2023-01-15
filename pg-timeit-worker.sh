#!/bin/sh
while true ; do psql -c "CALL timeit.work()" ; sleep 1 ; done
