<h1 id="top">⏱️🐘<code>timeit</code></h1>

1. [About](#about)
2. [Dependencies](#dependencies)
3. [Installation](#installation)
4. [Usage](#usage)
5. [API](#api)
    1. [timeit.s()]
    2. [timeit.h()]
    3. [timeit.f()]
    4. [timeit.async()]
    5. [timeit.work()]
6. [Internal types](#internal-types)
    1. [test_state]
7. [Internal functions](#internal-functions)
    1. [timeit.round_to_sig_figs()]
    2. [timeit.measure()]
    3. [timeit.overhead()]
    4. [timeit.eval()]
8. [Examples](#examples)

[timeit.s()]: #timeit-s
[timeit.h()]: #timeit-h
[timeit.f()]: #timeit-f
[timeit.async()]: #timeit-async
[timeit.work()]: #timeit-work
[test_state]: #test-state
[timeit.round_to_sig_figs()]: #timeit-round-to-sig-figs
[timeit.measure()]: #timeit-measure
[timeit.overhead()]: #timeit-overhead
[timeit.eval()]: #timeit-eval

<h2 id="about">1. About</h2>

`timeit` is a [PostgreSQL] extension to measure the execution time of built-in internal
C-functions with high resolution.
The high accurancy is achived by also adjusting for the overhead of the measurement itself.
The number of necessary test iterations/executions are auto-detected and
increased until the final result has the desired number of signifiant figures.

To minimize noise, the executions and measurements are performed in C,
as measuring using PL/pgSQL would be too noisy.

`timeit.s()` and `timeit.h()` immediately measures the execution time for given
internal function. These are suitable when you simply want to do a
single measurement.

`timeit.s()` returns the execution time in seconds as a numeric value.
`timeit.h()` returns the execution time as a human-readable text value,
e.g. "100 ms".

The below example measures the execution time to compute the square root for
the `numeric` value `2`, and returns the result in nanoseconds.

```sql
CREATE EXTENSION timeit;

SELECT timeit.h('clock_timestamp');
   h
-------
 30 ns
(1 row)

SELECT timeit.h('numeric_sqrt','{2}');
   h
--------
 300 ns
(1 row)

SELECT timeit.h('numeric_sqrt','{2e131071}');
   h
-------
 30 ms
(1 row)

SELECT timeit.s('numeric_sqrt','{2e131071}');
  s
------
 0.03
(1 row)

```

Another simple example where we measure `pg_sleep(1)` with three
`significant_figures`.

```sql
CREATE EXTENSION timeit;

SELECT timeit.h('pg_sleep','{1}', 3);
   h
--------
 1.00 s
(1 row)
```

`timeit.async()` defers the measurement and just returns an `id`, that the
caller can keep to allow the `final_result` to be joined in later
when the execution time has been computed by the `timeit.work()` `PROCEDURE`.

`timeit.async()` is meant to be used when you have lots of functions/argument
combinations you want to measure, and have some query or program to
generates those combinations for you, and you want to request all those
values to be measured, without having to do the actual measurement
immediately.

```sql
SELECT timeit.async('numeric_sqrt',ARRAY[format('2e%s',unnest)])
FROM unnest(ARRAY[0,10,100,1000,10000,100000,131071]);

 async
-------
     1
     2
     3
     4
     5
     6
     7
(7 rows)

--
-- timeit.work() can be executed manually like in this example,
-- or, run in the background by adding pg-timeit-worker.sh
-- to e.g. launchd or systemd, see Installation section.
--
CALL timeit.work(return_when_idle := true);
NOTICE:  2023-01-27 22:05:17+01 working
NOTICE:  2023-01-27 22:05:17+01 7 in queue
NOTICE:  2023-01-27 22:05:17+01 7 in queue
NOTICE:  2023-01-27 22:05:17+01 7 in queue
NOTICE:  2023-01-27 22:05:17+01 3 in queue
NOTICE:  2023-01-27 22:05:17+01 3 in queue
NOTICE:  2023-01-27 22:05:17+01 3 in queue
NOTICE:  2023-01-27 22:05:17+01 3 in queue
NOTICE:  2023-01-27 22:05:17+01 3 in queue
NOTICE:  2023-01-27 22:05:17+01 3 in queue
NOTICE:  2023-01-27 22:05:17+01 3 in queue
NOTICE:  2023-01-27 22:05:17+01 3 in queue
NOTICE:  2023-01-27 22:05:17+01 2 in queue
NOTICE:  2023-01-27 22:05:17+01 2 in queue
NOTICE:  2023-01-27 22:05:17+01 2 in queue
NOTICE:  2023-01-27 22:05:17+01 2 in queue
NOTICE:  2023-01-27 22:05:17+01 2 in queue
NOTICE:  2023-01-27 22:05:17+01 2 in queue
NOTICE:  2023-01-27 22:05:17+01 idle

SELECT
    tests.id,
    test_params.function_name,
    test_params.input_values,
    tests.executions,
    tests.final_result
FROM timeit.tests
JOIN timeit.test_params USING (id)
ORDER BY id;

 id | function_name | input_values | executions | final_result
----+---------------+--------------+------------+--------------
  1 | numeric_sqrt  | {2e0}        |        128 |   0.00000009
  2 | numeric_sqrt  | {2e10}       |        128 |   0.00000009
  3 | numeric_sqrt  | {2e100}      |         16 |    0.0000007
  4 | numeric_sqrt  | {2e1000}     |          1 |      0.00001
  5 | numeric_sqrt  | {2e10000}    |          1 |       0.0002
  6 | numeric_sqrt  | {2e100000}   |          1 |         0.02
  7 | numeric_sqrt  | {2e131071}   |          1 |         0.03
(7 rows)

```

Another nice thing with `timeit.async()` and `timeit.work()` is that they
spread out the actual measurements over time, by first doing one measurement,
and then instead of immediately proceeding an doing a second measurement
of the same thing, `timeit.work()` will instead store the first measurement,
and then proceed to do other measurements, and only in the next cycle
proceed and do the second measurement, after which both measurements are
compared to see if a result can be produced, or if the number of executions
needs to be increased further.

By separating the first and second measurement from each other in time,
the risk is reduced that both would be similarily unusually slow,
due to the CPU being similarily busy both times.

[PostgreSQL]: https://www.postgresql.org/

<h2 id="dependencies">2. Dependencies</h2>

None.

<h2 id="installation">3. Installation</h2>

Install the `timeit` extension with:

    $ git clone https://github.com/joelonsql/pg-timeit.git
    $ cd pg-timeit
    $ make
    $ sudo make install
    $ make installcheck

Optionally, if you need `timeit.async()`, you also need to schedule
the `timeit.work()` procedure to run in the background.

Here is how to do that on Ubuntu Linux:

    $ sudo cp timeit-worker.sh /usr/local/bin/
    $ sudo cp timeit.service /etc/systemd/system/
    $ sudo systemctl enable timeit
    $ sudo systemctl start timeit

Here is how to do that on Mac OS X:

    $ ./add-timeit-worker-to-launchd.sh

<h2 id="usage">4. Usage</h2>

Use with:

    $ psql
    # CREATE EXTENSION timeit;
    CREATE EXTENSION;

<h2 id="api">5. API</h2>

<h3 id="timeit-s"><code>timeit.s(function_name [, input_values ] [, significant_figures] [, timeout] [, attempts] [, min_time]) → numeric</code></h3>

  Input Parameter     | Type     | Default
--------------------- | -------- | -----------
 function_name        | text     |
 input_values         | text[]   | ARRAY[]::text[]
 significant_figures  | integer  | 1
 timeout              | interval | NULL
 attempts             | integer  | 1
 min_time             | interval | 10 ms

Immediately measure the execution run time of the built-in internal function named `function_name`.

Returns the measured execution time in seconds.

Optionally, arguments can be passed by specifying `input_values`.

The desired precision of the returned final result can be specified via `significant_figures`, which defaults to 1.

A maximum timeout interval per attempt can be specified via the `timeout` input parameter, which defaults to NULL, which means no timeout.

After `attempts` timeouts, the `significant_figures` will be decreased by one and `attempts` new attempts will be made at that precision level.

When there are no more attempts and when sig. figures. can't be decreased further, it will give up.

<h3 id="timeit-h"><code>timeit.h(function_name [, input_values ] [, significant_figures] [, timeout] [, attempts] [, min_time]) → text</code></h3>

Like `timeit.s()`, but returns result a time unit pretty formatted text string, e.g. "100 ms".

<h3 id="timeit-f"><code>timeit.f(function_name [, input_values ] [, significant_figures] [, timeout] [, attempts] [, min_time]) → float8</code></h3>

Like `timeit.s()`, but returns the result as a float8 without rounding to significant figures.

<h3 id="timeit-async"><code>timeit.async(function_name [, input_values ] [, significant_figures] [, timeout] [, attempts] [, min_time]) → bigint</code></h3>

  Input Parameter     | Type     | Default
--------------------- | -------- | -----------
 function_name        | text     |
 input_values         | text[]   | ARRAY[]::text[]
 significant_figures  | integer  | 1
 timeout              | interval | NULL
 attempts             | integer  | 1
 min_time             | interval | 10 ms

Request measurement of the execution run time of `function_name`.

Returns a bigint `id` value that is the primary key in the `timeit.tests` table where the requested test is stored to.

<h3 id="timeit-now"><code>timeit.work()</code></h3>

This procedure performs the measurements requested by `timeit.async()` and is supposed to be called in a loop from a script or cronjob.

See the [Installation](#installation) section for how to daemonize it.

<h2 id="api">6. Internal types</h2>

<h3 id="test-state"><code>test_state</code></h3>

`timeit.test_state` is an `ENUM` with the following elements:

- **init**: Test has just been initiated.
- **run_test_1**: First test should be executed.
- **run_test_2**: Second test should be executed.
- **final**: The final result has been determined.

<h2 id="internal-functions">7. Internal functions</h2>

<h3 id="timeit-round-to-sig-figs"><code>timeit.round_to_sig_figs(numeric, integer) → numeric</code></h3>

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

<h3 id="timeit-measure"><code>timeit.measure(function_name text, input_values text[], executions bigint) -> numeric</code></h3>

Performs `executions` number of executions of `function_name` with arguments passed via `input_values`.

<h3 id="timeit-eval"><code>timeit.eval(function_name text, input_values text[]) -> text</code></h3>

Performs a single execution of `function_name` with arguments passed via `input_values`.

Returns the result casted to text.

<h2 id="api">8. Examples</h2>

Let's say we want to measure the execution time of

    1.5 + 2.5

Under the hood, the arithmetic add operation is computed using

    numeric_add(1.5,2.5)

so the following two statements do the same thing:

```sql
SELECT 1.5 + 2.5;
 ?column?
----------
      4.0
(1 row)

SELECT numeric_add(1.5, 2.5);
 numeric_add
-------------
         4.0
(1 row)
```

To measure it:

```sql
SELECT timeit.h('numeric_add', ARRAY['1.5','2.5']);
   h
-------
 60 ns
(1 row)
```

By default, a result with one significant figure is produced.

If we instead want two significant figures:

```sql
SELECT timeit.h('numeric_add', ARRAY['1.5','2.5'], 2);
   h
-------
 24 ns
(1 row)
```

We could never measure such a short duration simply by using `psql`'s `\timing`,
or `EXPLAIN ANALYZE`.

```sql
=# \timing
Timing is on.
=# EXPLAIN ANALYZE SELECT 1.5 + 2.5;
                                     QUERY PLAN
-------------------------------------------------------------------------------------
 Result  (cost=0.00..0.01 rows=1 width=32) (actual time=0.002..0.003 rows=1 loops=1)
 Planning Time: 0.088 ms
 Execution Time: 0.024 ms
(3 rows)

Time: 0.909 ms
```

It's noteworthy both `0.024 ms` and `0.909 ms` are wrong with several orders
of magnitude, which is expected, and not a critisism, since they report the
time for the entire statement, not just the expression that we're interested in.

To understand how off these values are from each other,
let's convert them to seconds to allow visual comparison:

```
0.000024    <-- EXPLAIN ANALYZE "Exeuction Time"
0.000909    <-- \timing
0.000000024 <-- timeit.h()
```

But how do we know the claimed exeuction time by `timeit.h()` is reasonable?

Let's demonstrate how we can verify it manually, only standard PostgreSQL
and its existing system catalog functions.

If it's true that the exeuction time is 24 ns, it should take about 2.4 s
to do 1e8 executions. We will use `generate_series()` for the executions,
but we first have to solve two problems. We have to account for the
overhead of `generate_series()`. We must also avoid caching of the
immutable expression, and create a volatile version of `numeric_add`.

```sql
CREATE FUNCTION numeric_add_volatile(numeric,numeric)
RETURNS numeric
VOLATILE
LANGUAGE internal
AS 'numeric_add';
```

Let's measure the overhead time of generate_series:

```sql
SELECT count(null) FROM generate_series(1,1e8);
 count
-------
     0
(1 row)

Time: 11344.158 ms (00:11.344)
```

The execution time is not notably affected by an immutable expression,
since it's only computed once, and that time is minuscule in relation to
the time to generate the 1e8 long series:

```sql
SELECT count(1.5 + 2.5) FROM generate_series(1,1e8);
   count
-----------
 100000000
(1 row)

Time: 11688.894 ms (00:11.689)
```

If we now instead invoke our volatile version of it, we will notice how it
takes about 3 seconds longer time, which nicely matches the `timeit.h()`
returned result:

```sql
SELECT count(numeric_add_volatile(1.5, 2.5)) FROM generate_series(1,1e8);
   count
-----------
 100000000
(1 row)

Time: 14524.570 ms (00:14.525)

SELECT 14.525-11.344;
 ?column?
----------
    3.181
(1 row)
```

Note how `3.181 s` is quite close to the predicted time `2.4 s`.

Under the hood, `timeit` measures the execution time by executing the function
using C, and doesn't use `generate_series()` at all. This was only meant to
demonstrate how users could verify the correctness of the timeit measurements,
using tools available in standard PostgreSQL.
