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
set_cpu_affinity(int core_id)
{
	cpu_set_t	cpuset;
	pid_t		pid;

	CPU_ZERO(&cpuset);
	CPU_SET(core_id, &cpuset);

	pid = getpid();
	if (sched_setaffinity(pid, sizeof(cpu_set_t), &cpuset) != 0)
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


PG_FUNCTION_INFO_V1(eval);
PG_FUNCTION_INFO_V1(measure_time);
PG_FUNCTION_INFO_V1(measure_cycles);

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

	if (number_of_iterations <= 0)
		ereport(ERROR,
				 (errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				  errmsg("number_of_iterations must be at least one, but is %ld",
						 number_of_iterations)));

	prepare_function_call(internal_function_name, input_values, fcinfo, &fcd);

	if (core_id != -1)
	{
#ifdef HAVE_SCHED_SETAFFINITY
		set_cpu_affinity(core_id);
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

	if (number_of_iterations <= 0)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("number_of_iterations must be at least one, but is %ld",
						number_of_iterations)));

	prepare_function_call(internal_function_name, input_values, fcinfo, &fcd);

	if (core_id != -1)
	{
		set_cpu_affinity(core_id);
	}

	testfunc_fcinfo = fcd.testfunc_fcinfo;
	start_cycles = rdtsc_s();
	for (int64 i = 0; i < number_of_iterations; i++)
		FunctionCallInvoke(testfunc_fcinfo);
	end_cycles = rdtsc_e();
	total_cycles = end_cycles - start_cycles;

	free_function_call_data(&fcd);

	PG_RETURN_INT64(total_cycles);
#else
	ereport(ERROR, (errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
					errmsg("not supported on this architecture")));
#endif
}
