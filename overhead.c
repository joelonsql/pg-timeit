#include "postgres.h"
#include "utils/timestamp.h"

PG_MODULE_MAGIC;

PG_FUNCTION_INFO_V1(overhead);

Datum overhead(PG_FUNCTION_ARGS) {
    int64 number_of_executions = PG_GETARG_INT64(0);
    TimestampTz start_time;
    TimestampTz end_time;
    int64 total_time;
    volatile int dummy = 0;

    /* Start measuring execution time */
    start_time = GetCurrentTimestamp();

    for (int64 i = 0; i < number_of_executions; i++)
    {
        dummy++;
    }

    /* End measuring execution time */
    end_time = GetCurrentTimestamp();

    /* Calculate total execution time */
    total_time = end_time - start_time;

    /* Return total execution time in microseconds */
    PG_RETURN_INT64(total_time);
}
