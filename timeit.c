#include "postgres.h"
#include "funcapi.h"
#include "catalog/pg_proc.h"
#include "executor/spi.h"
#include "utils/builtins.h"
#include "utils/array.h"
#include "utils/timestamp.h"
#include "utils/syscache.h"
#include "utils/lsyscache.h"
#include <sched.h>
#include <unistd.h>
#include <linux/perf_event.h>
#include <sys/syscall.h>
#include <string.h>
#include <sys/ioctl.h>
#include <errno.h>

PG_MODULE_MAGIC;

#ifndef TEXTOID
#define TEXTOID 25
#endif

#ifdef CPU_SET
#define HAVE_SCHED_SETAFFINITY 1
#endif

#ifdef HAVE_SCHED_SETAFFINITY
static void
create_cpuset_for_core(int core_id, cpu_set_t *cpuset)
{
	CPU_ZERO(cpuset);
	CPU_SET(core_id, cpuset);
}

static void
get_cpu_affinity(cpu_set_t *cpuset)
{
	pid_t pid = getpid();
	if (sched_getaffinity(pid, sizeof(cpu_set_t), cpuset) != 0)
		ereport(ERROR,
				(errcode(ERRCODE_INTERNAL_ERROR),
				 errmsg("sched_getaffinity failed")));
}

static void
set_cpu_affinity(const cpu_set_t *cpuset)
{
	pid_t pid = getpid();
	if (sched_setaffinity(pid, sizeof(cpu_set_t), cpuset) != 0)
		ereport(ERROR,
				(errcode(ERRCODE_INTERNAL_ERROR),
				 errmsg("sched_setaffinity failed")));
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

typedef struct
{
	Datum			   *dvalues;
	Datum			   *values;
	bool			   *nulls;
	int					nelems;
	Form_pg_proc		proc_form;
	FmgrInfo		   *testfunc_finfo;
	FunctionCallInfo	testfunc_fcinfo;
	bool				anynull;
	HeapTuple			proc_tuple;
} FunctionCallData;

static Oid lookup_internal_function(char *internal_function_name_c_string);
static HeapTuple get_function_tuple(Oid proc_oid);
static void convert_arguments_from_text(FunctionCallData *fcd,
										FunctionCallInfo fcinfo);
static void setup_function_call_info(FunctionCallData *fcd);
static void prepare_function_call(text *internal_function_name,
								  ArrayType *input_values,
								  FunctionCallInfo fcinfo,
								  FunctionCallData *fcd);
static void free_function_call_data(FunctionCallData *fcd);
static int perf_event_open(struct perf_event_attr *hw_event, pid_t pid,
						   int cpu, int group_fd, unsigned long flags);

PG_FUNCTION_INFO_V1(eval);
PG_FUNCTION_INFO_V1(measure_time);
PG_FUNCTION_INFO_V1(measure_cycles);
PG_FUNCTION_INFO_V1(overhead_time);
PG_FUNCTION_INFO_V1(overhead_cycles);
PG_FUNCTION_INFO_V1(time_query);

static int
perf_event_open(struct perf_event_attr *hw_event, pid_t pid,
				int cpu, int group_fd, unsigned long flags)
{
	return syscall(__NR_perf_event_open, hw_event, pid, cpu, group_fd, flags);
}

static Oid
lookup_internal_function(char *internal_function_name_c_string)
{
	Oid			proc_oid;

	proc_oid = fmgr_internal_function(internal_function_name_c_string);
	if (proc_oid == InvalidOid)
		ereport(ERROR,
				(errcode(ERRCODE_UNDEFINED_FUNCTION),
				 errmsg("there is no built-in function named \"%s\"",
						internal_function_name_c_string)));
	return proc_oid;
}

static HeapTuple
get_function_tuple(Oid proc_oid)
{
	HeapTuple	proc_tuple;

	proc_tuple = SearchSysCache1(PROCOID, ObjectIdGetDatum(proc_oid));
	if (!HeapTupleIsValid(proc_tuple))
		ereport(ERROR, (errcode(ERRCODE_UNDEFINED_FUNCTION),
						errmsg("Function not found")));
	return proc_tuple;
}

static void
convert_arguments_from_text(FunctionCallData *fcd,
							FunctionCallInfo fcinfo)
{
	int			i;

	fcd->dvalues = (Datum *) palloc(fcd->nelems * sizeof(Datum));
	fcd->anynull = false;
	for (i = 0; i < fcd->nelems; i++)
	{
		Oid			typoid,
					typinput,
					typioparam;
		FmgrInfo   *typfunc_finfo;

		typoid = fcd->proc_form->proargtypes.values[i];
		typfunc_finfo = palloc0(sizeof(FmgrInfo));
		getTypeInputInfo(typoid, &typinput, &typioparam);
		fmgr_info_cxt(typinput, typfunc_finfo, fcinfo->flinfo->fn_mcxt);
		if (fcd->nulls[i])
		{
			fcd->dvalues[i] = (Datum) 0;
			fcd->anynull = true;
		}
		else
		{
			fcd->dvalues[i] = InputFunctionCall(typfunc_finfo,
												TextDatumGetCString(fcd->values[i]),
												typioparam,
												-1);
		}
		pfree(typfunc_finfo);
	}
}

static void
setup_function_call_info(FunctionCallData *fcd)
{
	int			i;
	int			pronargs = fcd->proc_form->pronargs;

	fcd->testfunc_finfo = palloc0(sizeof(FmgrInfo));
	fcd->testfunc_fcinfo = palloc0(SizeForFunctionCallInfo(pronargs));
	fmgr_info(fcd->proc_form->oid, fcd->testfunc_finfo);
	fmgr_info_set_expr(NULL, fcd->testfunc_finfo);
	InitFunctionCallInfoData(*fcd->testfunc_fcinfo,
							 fcd->testfunc_finfo,
							 pronargs,
							 InvalidOid,
							 NULL, NULL);
	for (i = 0; i < fcd->nelems; i++)
	{
		fcd->testfunc_fcinfo->args[i].value = fcd->dvalues[i];
		fcd->testfunc_fcinfo->args[i].isnull = fcd->nulls[i];
	}
	fcd->testfunc_fcinfo->isnull = false;

	if (fcd->testfunc_fcinfo->flinfo->fn_strict && fcd->anynull)
	{
		/* Don't call a strict function with NULL inputs. */
		ereport(ERROR, (errcode(ERRCODE_NULL_VALUE_NOT_ALLOWED),
						errmsg("Cannot call strict function with NULL inputs")));
	}
}

static void
prepare_function_call(text *internal_function_name, ArrayType *input_values,
					  FunctionCallInfo fcinfo, FunctionCallData *fcd)
{
	char	   *internal_function_name_c_string;
	Oid			proc_oid;

	/* Convert internal function name to C string. */
	internal_function_name_c_string = text_to_cstring(internal_function_name);

	/* Get input values. */
	deconstruct_array(input_values, TEXTOID, -1, false, 'i', &(fcd->values),
					 &(fcd->nulls), &(fcd->nelems));

	proc_oid = lookup_internal_function(internal_function_name_c_string);

	fcd->proc_tuple = get_function_tuple(proc_oid);

	/* Get form of internal function. */
	fcd->proc_form = (Form_pg_proc) GETSTRUCT(fcd->proc_tuple);

	if (fcd->proc_form->pronargs != fcd->nelems)
	{
		ereport(ERROR, (errcode(ERRCODE_INVALID_PARAMETER_VALUE),
						errmsg("Function %s expects %d input parameters "
							   "but input_values only contains %d elements",
							   internal_function_name_c_string,
							   fcd->proc_form->pronargs,
							   fcd->nelems)));
	}

	convert_arguments_from_text(fcd, fcinfo);

	setup_function_call_info(fcd);
}

static void
free_function_call_data(FunctionCallData *fcd)
{
	pfree(fcd->testfunc_finfo);
	pfree(fcd->testfunc_fcinfo);
	ReleaseSysCache(fcd->proc_tuple);
	pfree(fcd->dvalues);
	pfree(fcd->values);
}

/*
 * SQL-callable function timeit.eval().
 *
 * Executes the specified internal function once,
 * and return the result as a text Datum.
 */

Datum
eval(PG_FUNCTION_ARGS)
{
	text			   *internal_function_name = PG_GETARG_TEXT_P(0);
	ArrayType		   *input_values = PG_GETARG_ARRAYTYPE_P(1);
	FunctionCallData	fcd;
	Datum				result;
	Oid					proc_typoutput;
	char			   *result_c_string;
	bool				is_var_lena;

	prepare_function_call(internal_function_name, input_values, fcinfo, &fcd);

	result = FunctionCallInvoke(fcd.testfunc_fcinfo);

	if (fcd.testfunc_fcinfo->isnull)
		ereport(ERROR, (errcode(ERRCODE_NULL_VALUE_NOT_ALLOWED),
						errmsg("function returned NULL")));

	/* Convert result to text and return. */
	getTypeOutputInfo(fcd.proc_form->prorettype, &proc_typoutput, &is_var_lena);
	result_c_string = OidOutputFunctionCall(proc_typoutput, result);
	free_function_call_data(&fcd);
	PG_RETURN_TEXT_P(cstring_to_text(result_c_string));
}


/*
 * SQL-callable function timeit.measure_time().
 *
 * Executes the specified internal function as many times as specified,
 * and return the measured time in microseconds as an int64 Datum.
 */

Datum
measure_time(PG_FUNCTION_ARGS)
{
	text			   *internal_function_name = PG_GETARG_TEXT_P(0);
	ArrayType		   *input_values = PG_GETARG_ARRAYTYPE_P(1);
	int64				number_of_iterations = PG_GETARG_INT64(2);
	int					core_id = PG_GETARG_INT32(3);
	FunctionCallData	fcd;
	TimestampTz			start_time;
	TimestampTz			end_time;
	int64				total_time;
	FunctionCallInfo	testfunc_fcinfo;
#ifdef HAVE_SCHED_SETAFFINITY
	cpu_set_t			old_cpuset;
	cpu_set_t			new_cpuset;
#endif

	if (number_of_iterations <= 0)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("number_of_iterations must be at least one, but is %ld",
						number_of_iterations)));

	prepare_function_call(internal_function_name, input_values, fcinfo, &fcd);

	if (core_id != -1)
	{
#ifdef HAVE_SCHED_SETAFFINITY
		get_cpu_affinity(&old_cpuset);
		create_cpuset_for_core(core_id, &new_cpuset);
		set_cpu_affinity(&new_cpuset);
#else
		ereport(ERROR, (errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
						errmsg("not supported on this architecture")));
#endif
	}

	testfunc_fcinfo = fcd.testfunc_fcinfo;
	start_time = GetCurrentTimestamp();
	for (int64 i = 0; i < number_of_iterations; i++)
		FunctionCallInvoke(testfunc_fcinfo);
	end_time = GetCurrentTimestamp();
	total_time = end_time - start_time;

#ifdef HAVE_SCHED_SETAFFINITY
	if (core_id != -1)
		set_cpu_affinity(&old_cpuset);
#endif

	free_function_call_data(&fcd);

	/* Return total execution time in microseconds. */
	PG_RETURN_INT64(total_time);
}

/*
 * SQL-callable function timeit.measure_cycles().
 *
 * Executes the specified internal function as many times as specified,
 * and return the measured number of clock cycles as an int64 Datum.
 */

Datum
measure_cycles(PG_FUNCTION_ARGS)
{
#ifdef HAVE_SCHED_SETAFFINITY
	text			   *internal_function_name = PG_GETARG_TEXT_P(0);
	ArrayType		   *input_values = PG_GETARG_ARRAYTYPE_P(1);
	int64				number_of_iterations = PG_GETARG_INT64(2);
	int					core_id = PG_GETARG_INT32(3);
	FunctionCallData	fcd;
	int64				start_cycles;
	int64				end_cycles;
	int64				total_cycles;
	FunctionCallInfo	testfunc_fcinfo;
#ifdef HAVE_SCHED_SETAFFINITY
	cpu_set_t			old_cpuset;
	cpu_set_t			new_cpuset;
#endif

	if (number_of_iterations <= 0)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("number_of_iterations must be at least one, but is %ld",
						number_of_iterations)));

	prepare_function_call(internal_function_name, input_values, fcinfo, &fcd);

	if (core_id != -1)
	{
		get_cpu_affinity(&old_cpuset);
		create_cpuset_for_core(core_id, &new_cpuset);
		set_cpu_affinity(&new_cpuset);
	}

	testfunc_fcinfo = fcd.testfunc_fcinfo;
	start_cycles = rdtsc_s();
	for (int64 i = 0; i < number_of_iterations; i++)
		FunctionCallInvoke(testfunc_fcinfo);
	end_cycles = rdtsc_e();
	total_cycles = end_cycles - start_cycles;

	if (core_id != -1)
		set_cpu_affinity(&old_cpuset);

	free_function_call_data(&fcd);

	PG_RETURN_INT64(total_cycles);
#else
	ereport(ERROR, (errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
					errmsg("not supported on this architecture")));
#endif
}

/*
 * SQL-callable function timeit.overhead_time().
 *
 * Executes an empty for loop as many times as specified,
 * and return the measured time in microseconds as an int64 Datum.
 */

Datum
overhead_time(PG_FUNCTION_ARGS)
{
	text			   *internal_function_name = PG_GETARG_TEXT_P(0);
	ArrayType		   *input_values = PG_GETARG_ARRAYTYPE_P(1);
	int64				number_of_iterations = PG_GETARG_INT64(2);
	int					core_id = PG_GETARG_INT32(3);
	FunctionCallData	fcd;
	TimestampTz			start_time;
	TimestampTz			end_time;
	int64				total_time;
#ifdef HAVE_SCHED_SETAFFINITY
	cpu_set_t			old_cpuset;
	cpu_set_t			new_cpuset;
#endif

	if (number_of_iterations <= 0)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("number_of_iterations must be at least one, but is %ld",
						number_of_iterations)));

	prepare_function_call(internal_function_name, input_values, fcinfo, &fcd);

	if (core_id != -1)
	{
#ifdef HAVE_SCHED_SETAFFINITY
		get_cpu_affinity(&old_cpuset);
		create_cpuset_for_core(core_id, &new_cpuset);
		set_cpu_affinity(&new_cpuset);
#else
		ereport(ERROR, (errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
						errmsg("not supported on this architecture")));
#endif
	}

	start_time = GetCurrentTimestamp();
    for (volatile int64 i = 0; i < number_of_iterations; i++)
    {
    }
	end_time = GetCurrentTimestamp();
	total_time = end_time - start_time;

#ifdef HAVE_SCHED_SETAFFINITY
	if (core_id != -1)
		set_cpu_affinity(&old_cpuset);
#endif

	free_function_call_data(&fcd);

	/* Return total execution time in microseconds. */
	PG_RETURN_INT64(total_time);
}

/*
 * SQL-callable function timeit.overhead_cycles().
 *
 * Executes an empty for loop as many times as specified,
 * and return the measured number of clock cycles as an int64 Datum.
 */

Datum
overhead_cycles(PG_FUNCTION_ARGS)
{
#ifdef HAVE_SCHED_SETAFFINITY
	text			   *internal_function_name = PG_GETARG_TEXT_P(0);
	ArrayType		   *input_values = PG_GETARG_ARRAYTYPE_P(1);
	int64				number_of_iterations = PG_GETARG_INT64(2);
	int					core_id = PG_GETARG_INT32(3);
	FunctionCallData	fcd;
	int64				start_cycles;
	int64				end_cycles;
	int64				total_cycles;
#ifdef HAVE_SCHED_SETAFFINITY
	cpu_set_t			old_cpuset;
	cpu_set_t			new_cpuset;
#endif

	if (number_of_iterations <= 0)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("number_of_iterations must be at least one, but is %ld",
						number_of_iterations)));

	prepare_function_call(internal_function_name, input_values, fcinfo, &fcd);

	if (core_id != -1)
	{
		get_cpu_affinity(&old_cpuset);
		create_cpuset_for_core(core_id, &new_cpuset);
		set_cpu_affinity(&new_cpuset);
	}

	start_cycles = rdtsc_s();
    for (volatile int64 i = 0; i < number_of_iterations; i++)
    {
    }
	end_cycles = rdtsc_e();
	total_cycles = end_cycles - start_cycles;

	if (core_id != -1)
		set_cpu_affinity(&old_cpuset);

	free_function_call_data(&fcd);

	PG_RETURN_INT64(total_cycles);
#else
	ereport(ERROR, (errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
					errmsg("not supported on this architecture")));
#endif
}

/*
 * SQL-callable function timeit.time_query().
 *
 * Executes the specified SQL query once,
 * and returns a record with the measured planning_time and execution_time.
 */
Datum
time_query(PG_FUNCTION_ARGS)
{
	text	   *sql_query = PG_GETARG_TEXT_P(0);
	char	   *sql_query_cstring;
	TimestampTz start_time, end_time;
	int64		planning_time_us, execution_time_us;
	double		planning_time_sec, execution_time_sec;
	SPIPlanPtr	plan;
	int			ret;
	TupleDesc	tupdesc;
	Datum		values[6];  /* Updated to hold more values */
	bool		nulls[6] = {false, false, false, false, false, false};
	HeapTuple	rettuple;

	/* Variables for performance counters */
	struct perf_event_attr pe;
	int fd_cycles = -1, fd_instructions = -1, fd_cache_references = -1, fd_cache_misses = -1;
	long long count_cycles = 0, count_instructions = 0, count_cache_references = 0, count_cache_misses = 0;

	/* Initialize performance event attributes */
	memset(&pe, 0, sizeof(struct perf_event_attr));
	pe.type = PERF_TYPE_HARDWARE;
	pe.size = sizeof(struct perf_event_attr);
	pe.disabled = 1;
	pe.exclude_kernel = 1;
	pe.exclude_hv = 1;

	/* Open performance counter for counting cycles */
	pe.config = PERF_COUNT_HW_CPU_CYCLES;
	fd_cycles = perf_event_open(&pe, 0, -1, -1, 0);
	if (fd_cycles == -1)
		ereport(ERROR,
				(errmsg("Error opening perf_event for CPU cycles: %m")));

	/* Open performance counter for instructions retired, grouped under cycles */
	pe.config = PERF_COUNT_HW_INSTRUCTIONS;
	fd_instructions = perf_event_open(&pe, 0, -1, fd_cycles, 0);
	if (fd_instructions == -1)
	{
		close(fd_cycles);
		ereport(ERROR,
				(errmsg("Error opening perf_event for instructions: %m")));
	}

	/* Open performance counter for cache references */
	pe.config = PERF_COUNT_HW_CACHE_REFERENCES;
	fd_cache_references = perf_event_open(&pe, 0, -1, fd_cycles, 0);
	if (fd_cache_references == -1)
	{
		close(fd_cycles);
		close(fd_instructions);
		ereport(ERROR,
				(errmsg("Error opening perf_event for cache references: %m")));
	}

	/* Open performance counter for cache misses */
	pe.config = PERF_COUNT_HW_CACHE_MISSES;
	fd_cache_misses = perf_event_open(&pe, 0, -1, fd_cycles, 0);
	if (fd_cache_misses == -1)
	{
		close(fd_cycles);
		close(fd_instructions);
		close(fd_cache_references);
		ereport(ERROR,
				(errmsg("Error opening perf_event for cache misses: %m")));
	}

	/* Convert SQL query from text to C string */
	sql_query_cstring = text_to_cstring(sql_query);

	/* Connect to SPI manager */
	ret = SPI_connect();
	if (ret != SPI_OK_CONNECT)
	{
		close(fd_cycles);
		close(fd_instructions);
		close(fd_cache_references);
		close(fd_cache_misses);
		ereport(ERROR,
				(errmsg("SPI_connect failed: %s", SPI_result_code_string(ret))));
	}

	/* Measure planning time */
	start_time = GetCurrentTimestamp();
	plan = SPI_prepare(sql_query_cstring, 0, NULL);
	end_time = GetCurrentTimestamp();
	planning_time_us = end_time - start_time;

	if (plan == NULL)
	{
		SPI_finish();
		close(fd_cycles);
		close(fd_instructions);
		close(fd_cache_references);
		close(fd_cache_misses);
		ereport(ERROR,
				(errmsg("SPI_prepare failed: %s", SPI_result_code_string(SPI_result))));
	}

	/* Start counting performance counters */
	if (ioctl(fd_cycles, PERF_EVENT_IOC_RESET, PERF_IOC_FLAG_GROUP) == -1 ||
		ioctl(fd_cycles, PERF_EVENT_IOC_ENABLE, PERF_IOC_FLAG_GROUP) == -1)
	{
		SPI_freeplan(plan);
		SPI_finish();
		close(fd_cycles);
		close(fd_instructions);
		close(fd_cache_references);
		close(fd_cache_misses);
		ereport(ERROR,
				(errmsg("Error starting perf_event counters: %m")));
	}

	/* Measure execution time */
	start_time = GetCurrentTimestamp();
	ret = SPI_execute_plan(plan, NULL, NULL, true, 0);
	end_time = GetCurrentTimestamp();
	execution_time_us = end_time - start_time;

	/* Stop counting performance counters */
	if (ioctl(fd_cycles, PERF_EVENT_IOC_DISABLE, PERF_IOC_FLAG_GROUP) == -1)
	{
		SPI_freeplan(plan);
		SPI_finish();
		close(fd_cycles);
		close(fd_instructions);
		close(fd_cache_references);
		close(fd_cache_misses);
		ereport(ERROR,
				(errmsg("Error stopping perf_event counters: %m")));
	}

	if (ret < 0)
	{
		SPI_freeplan(plan);
		SPI_finish();
		close(fd_cycles);
		close(fd_instructions);
		close(fd_cache_references);
		close(fd_cache_misses);
		ereport(ERROR,
				(errmsg("SPI_execute_plan failed: %s", SPI_result_code_string(ret))));
	}

	/* Read the performance counters */
	if (read(fd_cycles, &count_cycles, sizeof(long long)) == -1 ||
		read(fd_instructions, &count_instructions, sizeof(long long)) == -1 ||
		read(fd_cache_references, &count_cache_references, sizeof(long long)) == -1 ||
		read(fd_cache_misses, &count_cache_misses, sizeof(long long)) == -1)
	{
		SPI_freeplan(plan);
		SPI_finish();
		close(fd_cycles);
		close(fd_instructions);
		close(fd_cache_references);
		close(fd_cache_misses);
		ereport(ERROR,
				(errmsg("Error reading perf_event counters: %m")));
	}

	/* Close the file descriptors */
	close(fd_cycles);
	close(fd_instructions);
	close(fd_cache_references);
	close(fd_cache_misses);

	/* Free the plan and disconnect from SPI manager */
	SPI_freeplan(plan);
	SPI_finish();

	/* Build result tuple */
	if (get_call_result_type(fcinfo, NULL, &tupdesc) != TYPEFUNC_COMPOSITE)
		ereport(ERROR,
				(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
				 errmsg("function returning record called in context that cannot accept type record")));

	/* Convert times to seconds */
	planning_time_sec = (double)planning_time_us / 1e6;
	execution_time_sec = (double)execution_time_us / 1e6;

	/* Prepare the values */
	values[0] = Float8GetDatum(planning_time_sec);
	values[1] = Float8GetDatum(execution_time_sec);
	values[2] = Int64GetDatum(count_cycles);
	values[3] = Int64GetDatum(count_instructions);
	values[4] = Int64GetDatum(count_cache_references);
	values[5] = Int64GetDatum(count_cache_misses);

	/* Build the tuple */
	rettuple = heap_form_tuple(tupdesc, values, nulls);

	/* Return the result as a Datum */
	PG_RETURN_DATUM(HeapTupleGetDatum(rettuple));
}

