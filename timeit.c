#include "postgres.h"
#include "funcapi.h"
#include "catalog/pg_proc.h"
#include "utils/builtins.h"
#include "utils/array.h"
#include "utils/timestamp.h"
#include "utils/syscache.h"
#include "utils/lsyscache.h"
#include <sched.h>
#include <unistd.h>

PG_MODULE_MAGIC;

#ifndef TEXTOID
#define TEXTOID 25
#endif

#ifdef CPU_SET
#define HAVE_SCHED_SETAFFINITY 1
#endif

#ifdef HAVE_SCHED_SETAFFINITY
static void
set_cpu_affinity(int core_id) {
    cpu_set_t cpuset;
    pid_t pid;

    CPU_ZERO(&cpuset);
    CPU_SET(core_id, &cpuset);

    pid = getpid();
    if (sched_setaffinity(pid, sizeof(cpu_set_t), &cpuset) != 0) {
        perror("sched_setaffinity");
        exit(EXIT_FAILURE);
    }
}

static __inline__ int64_t rdtsc_s(void)
{
    unsigned a, d;
    asm volatile("cpuid" ::: "%rax", "%rbx", "%rcx", "%rdx");
    asm volatile("rdtsc" : "=a" (a), "=d" (d));
    return ((unsigned long)a) | (((unsigned long)d) << 32);
}

static __inline__ int64_t rdtsc_e(void)
{
    unsigned a, d;
    asm volatile("rdtscp" : "=a" (a), "=d" (d));
    asm volatile("cpuid" ::: "%rax", "%rbx", "%rcx", "%rdx");
    return ((unsigned long)a) | (((unsigned long)d) << 32);
}
#endif

/*
 * Helper-function for the two SQL functions timeit.measure() and timeit.eval().
 *
 * When called by timeit.eval(), only the first two arguments are specified.
 * It will then execute the specified internal function once with the
 * input values, and return the result as a text Datum.
 *
 * When called by timeit.measure(), all three arguments are specified.
 * It will then execute the specified internal function as many times as
 * specified, and return the measured time in microseconds as an int64 Datum.
 */

PG_FUNCTION_INFO_V1(measure_or_eval);

Datum
measure_or_eval(PG_FUNCTION_ARGS)
{
    text        *internal_function_name = PG_GETARG_TEXT_P(0);
    ArrayType   *input_values           = PG_GETARG_ARRAYTYPE_P(1);
    int64       number_of_executions    = (PG_NARGS() == 2) ? 1 : PG_GETARG_INT64(2);
    int         core_id                 = (PG_NARGS() == 2) ? -1 : PG_GETARG_INT32(3);

    char                *internal_function_name_c_string;
    Datum               *values;
    Datum               *dvalues;
    bool                *nulls;
    int                 nelems;
    Oid                 proc_oid;
    Oid                 proc_typoutput;
    HeapTuple           proc_tuple;
    Form_pg_proc        proc_form;
    TimestampTz         start_time;
    TimestampTz         end_time;
    int64               total_time;
    bool                anynull;
    FunctionCallInfo    testfunc_fcinfo;
    FmgrInfo            *testfunc_finfo;
    Datum               result = 0;
    char                *result_c_string;
    bool                is_var_lena;

    if (number_of_executions <= 0)
        elog(ERROR,
            "number_of_executions must be at least one, but is %ld",
            number_of_executions);

    /* Convert internal function name to C string. */
    internal_function_name_c_string = text_to_cstring(internal_function_name);

    /* Get input values. */
    deconstruct_array(input_values, TEXTOID, -1, false,
                      'i', &values, &nulls, &nelems);

    /* Get oid for internal function. */
    proc_oid = fmgr_internal_function(internal_function_name_c_string);

    /* Check that the function exists. */
    if (proc_oid == InvalidOid)
        ereport(ERROR,
                (errcode(ERRCODE_UNDEFINED_FUNCTION),
                 errmsg("there is no built-in function named \"%s\"",
                        internal_function_name_c_string)));

    /* Lookup internal function by name. */
    proc_tuple = SearchSysCache1(PROCOID, ObjectIdGetDatum(proc_oid));
    if (!HeapTupleIsValid(proc_tuple))
    {
        elog(ERROR, "Function %s not found", internal_function_name_c_string);
    }

    /* Get form of internal function. */
    proc_form = (Form_pg_proc) GETSTRUCT(proc_tuple);

    if (proc_form->pronargs != nelems)
    {
        elog(ERROR, "Function %s expects %d input parameters "
                    "but input_values only contains %d elements",
                    internal_function_name_c_string,
                    proc_form->pronargs,
                    nelems);
    }

    /* Convert arguments from text. */
    dvalues = (Datum *) palloc(nelems * sizeof(Datum));
    anynull = false;
    for (int i = 0; i < nelems; i++)
    {
        Oid			typoid,
                    typinput,
                    typioparam;
        FmgrInfo   *typfunc_finfo;

        typoid = proc_form->proargtypes.values[i];
        typfunc_finfo = palloc0(sizeof(FmgrInfo));
        getTypeInputInfo(typoid, &typinput, &typioparam);
        fmgr_info_cxt(typinput, typfunc_finfo, fcinfo->flinfo->fn_mcxt);
        if (nulls[i])
        {
            dvalues[i] = (Datum) 0;
            anynull = true;
        }
        else
        {
            dvalues[i] = InputFunctionCall(typfunc_finfo,
                                           TextDatumGetCString(values[i]),
                                           typioparam,
                                           -1);
        }
        pfree(typfunc_finfo);
    }

    testfunc_finfo = palloc0(sizeof(FmgrInfo));
    testfunc_fcinfo = palloc0(SizeForFunctionCallInfo(proc_form->pronargs));
    fmgr_info(proc_form->oid, testfunc_finfo);
    fmgr_info_set_expr(NULL, testfunc_finfo);
    InitFunctionCallInfoData(*testfunc_fcinfo,
                             testfunc_finfo,
                             proc_form->pronargs,
                             InvalidOid,
                             NULL, NULL);
    for (int i = 0; i < nelems; i++)
    {
        testfunc_fcinfo->args[i].value = dvalues[i];
        testfunc_fcinfo->args[i].isnull = nulls[i];
    }
    testfunc_fcinfo->isnull = false;

    if (testfunc_fcinfo->flinfo->fn_strict && anynull)
    {
        /* Don't call a strict function with NULL inputs. */
        elog(ERROR, "Cannot call strict function %s with NULL inputs",
             internal_function_name_c_string);
    }

    if (core_id != -1)
    {
        #ifdef HAVE_SCHED_SETAFFINITY
        /* Set CPU affinity to the specified core */
        set_cpu_affinity(core_id);
        #else
        elog(ERROR, "Setting CPU core id supported on this architecture");
        #endif
    }

    /* Start measuring execution time. */
    start_time = GetCurrentTimestamp();

    /* Execute internal function number_of_executions times. */
    for (volatile int64 i = 0; i < number_of_executions; i++)
    {
        result = FunctionCallInvoke(testfunc_fcinfo);
    }

    /* End measuring execution time. */
    end_time = GetCurrentTimestamp();

    /* Calculate total execution time. */
    total_time = end_time - start_time;

    if (testfunc_fcinfo->isnull)
        elog(ERROR, "function returned NULL");

    pfree(testfunc_finfo);
    pfree(testfunc_fcinfo);

    ReleaseSysCache(proc_tuple);
    pfree(values);
    pfree(dvalues);

    /*
     * Detect mode of operation.
     *
     * When called by eval() we get two arguments,
     * and when called by measure() we get three arguments.
     */
    if (PG_NARGS() == 2)
    {
        /* Convert result to text and return. */
        getTypeOutputInfo(proc_form->prorettype, &proc_typoutput, &is_var_lena);
        result_c_string = OidOutputFunctionCall(proc_typoutput, result);
        PG_RETURN_TEXT_P(cstring_to_text(result_c_string));
    }
    else
    {
        /* Return total execution time in microseconds. */
        PG_RETURN_INT64(total_time);
    }

}

/*
 * Returns the measured overhead time to execute an empty for loop,
 * of a specified number of iterations.
 */

PG_FUNCTION_INFO_V1(overhead);

Datum
overhead(PG_FUNCTION_ARGS)
{
    int64   number_of_iterations    = PG_GETARG_INT64(0);
    int     core_id                 = PG_GETARG_INT32(1);
    TimestampTz start_time;
    TimestampTz end_time;
    int64 total_time;

    if (core_id != -1)
    {
        #ifdef HAVE_SCHED_SETAFFINITY
        /* Set CPU affinity to the specified core */
        set_cpu_affinity(core_id);
        #else
        elog(ERROR, "Setting CPU core id supported on this architecture");
        #endif
    }

    /* Start measuring execution time */
    start_time = GetCurrentTimestamp();

    for (volatile int64 i = 0; i < number_of_iterations; i++)
    {
    }

    /* End measuring execution time */
    end_time = GetCurrentTimestamp();

    /* Calculate total execution time */
    total_time = end_time - start_time;

    /* Return total execution time in microseconds */
    PG_RETURN_INT64(total_time);
}

/*
 * Returns the measured overhead clockcycles to execute an empty for loop,
 * of a specified number of iterations.
 */

PG_FUNCTION_INFO_V1(overhead_rdtsc);

Datum
overhead_rdtsc(PG_FUNCTION_ARGS)
{
#ifdef HAVE_SCHED_SETAFFINITY
    int64   number_of_iterations    = PG_GETARG_INT64(0);
    int     core_id                 = PG_GETARG_INT32(1);
    int64   start_cycles;
    int64   end_cycles;
    int64   total_cycles;

    if (core_id != -1)
    {
        /* Set CPU affinity to the specified core */
        set_cpu_affinity(core_id);
    }

    /* Start measuring clock cycles. */
    start_cycles = rdtsc_s();

    for (volatile int64 i = 0; i < number_of_iterations; i++)
    {
    }

    /* End measuring clock cycles. */
    end_cycles = rdtsc_e();

    /* Calculate total clock cycles. */
    total_cycles = end_cycles - start_cycles;

    /* Return total clock cycles. */
    PG_RETURN_INT64(total_cycles);
#else
    elog(ERROR, "overhead_rdtsc() not supported on this architecture");
#endif
}

/*
 * Helper-function for the two SQL functions timeit.measure_rdtsc().
 *
 * Executes the specified internal function as many times as
 * specified, and return the measured number of clockcycles as an int64 Datum.
 */

PG_FUNCTION_INFO_V1(measure_rdtsc);

Datum
measure_rdtsc(PG_FUNCTION_ARGS)
{
#ifdef HAVE_SCHED_SETAFFINITY
    text        *internal_function_name = PG_GETARG_TEXT_P(0);
    ArrayType   *input_values           = PG_GETARG_ARRAYTYPE_P(1);
    int64       number_of_executions    = PG_GETARG_INT64(2);
    int         core_id                 = PG_GETARG_INT32(3);

    char                *internal_function_name_c_string;
    Datum               *values;
    Datum               *dvalues;
    bool                *nulls;
    int                 nelems;
    Oid                 proc_oid;
    HeapTuple           proc_tuple;
    Form_pg_proc        proc_form;
    int64               start_cycles;
    int64               end_cycles;
    int64               total_cycles;
    bool                anynull;
    FunctionCallInfo    testfunc_fcinfo;
    FmgrInfo            *testfunc_finfo;

    if (number_of_executions <= 0)
        elog(ERROR,
            "number_of_executions must be at least one, but is %ld",
            number_of_executions);

    /* Convert internal function name to C string. */
    internal_function_name_c_string = text_to_cstring(internal_function_name);

    /* Get input values. */
    deconstruct_array(input_values, TEXTOID, -1, false,
                      'i', &values, &nulls, &nelems);

    /* Get oid for internal function. */
    proc_oid = fmgr_internal_function(internal_function_name_c_string);

    /* Check that the function exists. */
    if (proc_oid == InvalidOid)
        ereport(ERROR,
                (errcode(ERRCODE_UNDEFINED_FUNCTION),
                 errmsg("there is no built-in function named \"%s\"",
                        internal_function_name_c_string)));

    /* Lookup internal function by name. */
    proc_tuple = SearchSysCache1(PROCOID, ObjectIdGetDatum(proc_oid));
    if (!HeapTupleIsValid(proc_tuple))
    {
        elog(ERROR, "Function %s not found", internal_function_name_c_string);
    }

    /* Get form of internal function. */
    proc_form = (Form_pg_proc) GETSTRUCT(proc_tuple);

    if (proc_form->pronargs != nelems)
    {
        elog(ERROR, "Function %s expects %d input parameters "
                    "but input_values only contains %d elements",
                    internal_function_name_c_string,
                    proc_form->pronargs,
                    nelems);
    }

    /* Convert arguments from text. */
    dvalues = (Datum *) palloc(nelems * sizeof(Datum));
    anynull = false;
    for (int i = 0; i < nelems; i++)
    {
        Oid			typoid,
                    typinput,
                    typioparam;
        FmgrInfo   *typfunc_finfo;

        typoid = proc_form->proargtypes.values[i];
        typfunc_finfo = palloc0(sizeof(FmgrInfo));
        getTypeInputInfo(typoid, &typinput, &typioparam);
        fmgr_info_cxt(typinput, typfunc_finfo, fcinfo->flinfo->fn_mcxt);
        if (nulls[i])
        {
            dvalues[i] = (Datum) 0;
            anynull = true;
        }
        else
        {
            dvalues[i] = InputFunctionCall(typfunc_finfo,
                                           TextDatumGetCString(values[i]),
                                           typioparam,
                                           -1);
        }
        pfree(typfunc_finfo);
    }

    testfunc_finfo = palloc0(sizeof(FmgrInfo));
    testfunc_fcinfo = palloc0(SizeForFunctionCallInfo(proc_form->pronargs));
    fmgr_info(proc_form->oid, testfunc_finfo);
    fmgr_info_set_expr(NULL, testfunc_finfo);
    InitFunctionCallInfoData(*testfunc_fcinfo,
                             testfunc_finfo,
                             proc_form->pronargs,
                             InvalidOid,
                             NULL, NULL);
    for (int i = 0; i < nelems; i++)
    {
        testfunc_fcinfo->args[i].value = dvalues[i];
        testfunc_fcinfo->args[i].isnull = nulls[i];
    }
    testfunc_fcinfo->isnull = false;

    if (testfunc_fcinfo->flinfo->fn_strict && anynull)
    {
        /* Don't call a strict function with NULL inputs. */
        elog(ERROR, "Cannot call strict function %s with NULL inputs",
             internal_function_name_c_string);
    }

    if (core_id != -1)
    {
        /* Set CPU affinity to the specified core */
        set_cpu_affinity(core_id);
    }

    /* Start measuring clock cycles. */
    start_cycles = rdtsc_s();

    /* Execute internal function number_of_executions times. */
    for (volatile int64 i = 0; i < number_of_executions; i++)
    {
        FunctionCallInvoke(testfunc_fcinfo);
    }

    /* End measuring clock cycles. */
    end_cycles = rdtsc_e();

    /* Calculate total clock cycles. */
    total_cycles = end_cycles - start_cycles;

    if (testfunc_fcinfo->isnull)
        elog(ERROR, "function returned NULL");

    pfree(testfunc_finfo);
    pfree(testfunc_fcinfo);

    ReleaseSysCache(proc_tuple);
    pfree(values);
    pfree(dvalues);

    /* Return total clock cycles. */
    PG_RETURN_INT64(total_cycles);
#else
    elog(ERROR, "measure_rdtsc() not supported on this architecture");
#endif
}
