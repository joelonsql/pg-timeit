<h1 id="top">⏱️🐘<code>timeit</code></h1>

1. [About](#about)
2. [Dependencies](#dependencies)
3. [Installation](#installation)
4. [Usage](#usage)
5. [API](#api)
    1. [timeit.c](#timeit-c)
    2. [timeit.t](#timeit-t)
    3. [timeit.measure](#timeit-measure)
6. [Types](#types)
    1. [timeit.measure_type](#measure-type)
7. [Internal functions](#internal-functions)
    1. [timeit.round_to_sig_figs](#timeit-round-to-sig-figs)
    2. [timeit.compute_regression_metrics](#timeit-compute-regression-metrics)
    3. [timeit.pretty_time](#timeit-pretty-time)
    4. [timeit.measure_time](#timeit-measure-time)
    5. [timeit.measure_cycles](#timeit-measure-cycles)
    6. [timeit.eval](#timeit-eval)
8. [Examples](#examples)

[timeit.c]: #timeit-c
[timeit.t]: #timeit-t
[timeit.measure]: #timeit-measure
[timeit.measure_type]: #measure-type
[timeit.round_to_sig_figs]: #timeit-round-to-sig-figs
[timeit.compute_regression_metrics]: #timeit-compute-regression-metrics
[timeit.pretty_time]: #timeit-pretty-time
[timeit.measure_time]: #timeit-measure-time
[timeit.measure_cycles]: #timeit-measure-cycles
[timeit.eval]: #timeit-eval

<h2 id="about">1. About</h2>

`timeit` is a [PostgreSQL] extension to measure the execution time of built-in
internal C-functions with high resolution. On x86_64, it's also possible to
measure clock cycles.

The number of necessary iterations to obtain a stable measurement is determined
automatically, by starting with one iteration, and then doubling, until the
latest measurements form a more or less straight line, using linear regression,
controlled via the *r_squared_threshold* and *sample_size* parameters,
or until reaching a *timeout*.

This approach allows quickly measuring all types of functions, from just a few
clock cycles up to functions that take seconds, while at the same time ensuring
a stable measurement is obtained.

[PostgreSQL]: https://www.postgresql.org/

<h2 id="dependencies">2. Dependencies</h2>

None, except [PostgreSQL].

<h2 id="installation">3. Installation</h2>

Install the `timeit` extension with:

    $ git clone https://github.com/joelonsql/pg-timeit.git
    $ cd pg-timeit
    $ make
    $ sudo make install
    $ make installcheck

<h2 id="usage">4. Usage</h2>

Use with:

    $ psql
    # CREATE EXTENSION timeit;
    CREATE EXTENSION;

<h2 id="api">5. API</h2>

<h3 id="timeit-c">timeit.c → bigint</h3>

  Input Parameter     | Type     | Default
--------------------- | -------- | -----------
 function_name        | text     | 
 input_values         | text[]   | 
 significant_figures  | integer  | 1
 r_squared_threshold  | float8   | 0.99
 sample_size          | integer  | 10
 timeout              | interval | 1 second
 core_id              | integer  | -1

Returns measured clock cycles, rounded to significant figures.

<h3 id="timeit-t">timeit.t → text</h3>

  Input Parameter     | Type     | Default
--------------------- | -------- | -----------
 function_name        | text     | 
 input_values         | text[]   | 
 significant_figures  | integer  | 1
 r_squared_threshold  | float8   | 0.99
 sample_size          | integer  | 10
 timeout              | interval | 1 second
 core_id              | integer  | -1

Returns measured execution time in human-readable format.

<h3 id="timeit-measure">timeit.measure → TABLE</h3>

  Input Parameter     | Type     | Default
--------------------- | -------- | -----------
 function_name        | text     | 
 input_values         | text[]   | 
 r_squared_threshold  | float8   | 0.99
 sample_size          | integer  | 10
 timeout              | interval | 1 second
 measure_type         | timeit.measure_type | 'time'
 core_id              | integer  | -1

  Output Column       | Type    
--------------------- | --------
 r_squared            | float8  
 slope                | float8  
 intercept            | float8  
 iterations           | bigint  

The `timeit.measure` function benchmarks the execution time or cycles of a
specified function (`function_name`) using provided arguments (`input_values`).

It measures performance by iterating the function call, collecting a specified
number of samples (`sample_size`).

The `measure_type` can be either 'time' or 'cycles', and it can be run on a
specified CPU core (`core_id`).

During benchmarking, the number of iterations is doubled each time until all of
these conditions are met:

- The R-squared value meets or exceeds the threshold.
- The slope is greater than zero, indicating that more iterations naturally
  lead to longer measured times or higher cycle counts.
- The intercept is greater than zero, accounting for the inherent overhead
  in executing the function.

Alternatively, benchmarking stops if the timeout is reached and at least two 
measurements have been completed.

The `timeit.measure` function returns a table with the following columns:
`r_squared`, `slope`, `intercept`, and `iterations`. The `r_squared` value
indicates how well the regression line fits the data. The `slope` represents
the execution time per iteration in microseconds if `measure_type` is 'time',
or cycles if `measure_type` is 'cycles'. The `intercept` is in the same unit
as the slope and represents the overhead of executing the function.
The `iterations` value is the total number of iterations performed in
the last measurement.

<h2 id="types">6. Types</h2>

<h3 id="measure-type">timeit.measure_type</h3>

`timeit.measure_type` is an `ENUM` with the following elements:

- **cycles**: Measure clock cycles.
- **time**: Measure time in microseconds.

<h2 id="internal-functions">7. Internal functions</h2>

<h3 id="timeit-round-to-sig-figs">timeit.round_to_sig_figs → numeric</h3>

  Input Parameter     | Type     
--------------------- | -------- 
 numeric_value        | numeric  
 significant_figures  | integer  

Round `numeric` value to `integer` number of significant figures.

```sql
SELECT timeit.round_to_sig_figs(1234,2);
 round_to_sig_figs
-------------------
              1200
(1 row)

SELECT timeit.round_to_sig_figs(12.456,3);
 round_to_sig_figs
-------------------
              12.5
(1 row)

SELECT timeit.round_to_sig_figs(0.00012456,3);
 round_to_sig_figs
-------------------
          0.000125
(1 row)
```

There is also a `bigint` overload:
`timeit.round_to_sig_figs(bigint, integer) → bigint`

<h3 id="timeit-compute-regression-metrics">timeit.compute_regression_metrics → TABLE</h3>

  Input Parameter     | Type     
--------------------- | -------- 
 x                    | float8[] 
 y                    | float8[] 

  Output Column       | Type    
--------------------- | -------- 
 r_squared            | float8   
 slope                | float8   
 intercept            | float8   

Calculates the regression metrics for benchmarking the execution time or cycles 
of functions, returning the coefficient of determination (R-squared), the slope 
(time or cycles), and the intercept (overhead).

#### Parameters
- **x**: Independent variable values representing the number of 
         iterations.
- **y**: Dependent variable values representing the measured 
         execution times or cycles.

#### Returns
A table with:
- **r_squared**: Indicates how well the regression line fits the data  (0 to 1).
- **slope**: Represents the execution time or cycles per iteration.
- **intercept**: Represents the fixed overhead time or cycles.

#### Requirements
- Arrays must have at least two elements.
- Arrays must be of the same length.

#### Exceptions
- Raises an exception if arrays have fewer than two elements.
- Raises an exception if arrays are of different lengths.

#### Example
```sql
SELECT * FROM timeit.compute_regression_metrics(
    ARRAY[1, 2, 4, 8, 16, 32, 64, 128, 256, 512],
    ARRAY[11.3, 21.5, 42.0, 81.2, 167.3, 334.4, 650.7, 1292.2, 2572.3, 5132.3]
);

     r_squared      |       slope        |     intercept
--------------------+--------------------+-------------------
 0.9999925121104006 | 10.018782621621654 | 5.598537808104993
(1 row)
```

<h3 id="timeit-pretty-time">timeit.pretty_time(numeric) → text</h3>

Returns measured execution time in human-readable output using time unit suffixes.

There is also an overload:
`timeit.pretty_time(numeric, significant_figures integer) → text`

<h3 id="timeit-measure-time">timeit.measure_time → bigint</h3>

  Input Parameter     | Type     
--------------------- | -------- 
 internal_function    | text     
 input_values         | text[]   
 iterations           | bigint   
 core_id              | integer  

Measures execution time for `internal_function` with `input_values` over
a specified number of `iterations`, on given CPU `core_id`.

If `-1` is specified as `core_id`, the kernel will be responsible for
CPU core scheduling.

<h3 id="timeit-measure-cycles">timeit.measure_cycles</h3>

  Input Parameter     | Type     
--------------------- | -------- 
 internal_function    | text     
 input_values         | text[]   
 iterations           | bigint   
 core_id              | integer  

Measures clock cycles for `internal_function` with `input_values` over
a specified number of `iterations`, on given CPU `core_id`.

If `-1` is specified as `core_id`, the kernel will be responsible for
CPU core scheduling.

<h3 id="timeit-eval">timeit.eval → text</h3>

  Input Parameter     | Type     
--------------------- | -------- 
 function_name        | text     
 input_values         | text[]   

Performs a single execution of `function_name` with arguments passed
via `input_values`.

Returns the result cast to text.

<h2 id="examples">8. Examples</h2>

```sql
SELECT timeit.t('pg_sleep', ARRAY['0.01']);
   t
-------
 10 ms
(1 row)
```

```sql
SELECT timeit.t('now', ARRAY[]::text[]);
  t
------
 3 ns
(1 row)
```

```sql
SELECT timeit.t('clock_timestamp', ARRAY[]::text[]);
   t
-------
 20 ns
(1 row)
```

```sql
SELECT timeit.t('numeric_add', ARRAY['1.5','2.5']);
   t
-------
 50 ns
(1 row)
```

By default, a result with one significant figure is produced.

If we instead want two significant figures:

```sql
SELECT timeit.t('numeric_add', ARRAY['1.5','2.5'], 2);
   t
-------
 52 ns
(1 row)
```
