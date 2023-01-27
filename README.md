<h1 id="top">⏱️🐘<code>pit</code></h1>

1. [About](#about)
2. [Dependencies](#dependencies)
3. [Installation](#installation)
4. [Usage](#usage)
5. [API](#api)
    1. [pit.s()]
    2. [pit.ms()]
    3. [pit.us()]
    4. [pit.ns()]
    5. [pit.async()]
    6. [pit.work()]
6. [Internal types](#internal-types)
    1. [test_state]
7. [Internal functions](#internal-functions)
    1. [pit.round_to_sig_figs()]
    2. [pit.measure()]
    3. [pit.overhead()]
    3. [pit.eval()]
8. [Examples](#examples)

[pit.s()]: #pit-s
[pit.ms()]: #pit-ms
[pit.us()]: #pit-us
[pit.ns()]: #pit-ns
[pit.async()]: #pit-async
[pit.work()]: #pit-work
[test_state]: #test-state
[pit.round_to_sig_figs()]: #pit-round-to-sig-figs
[pit.measure()]: #pit-measure
[pit.overhead()]: #pit-overhead
[pit.eval()]: #pit-eval

<h2 id="about">1. About</h2>

`pit` is a [PostgreSQL] extension to measure the execution time of
built-in internal C-functions with **nanosecond resolution**. The high accurancy
is achived by also adjusting for the overhead of the measurement itself.
The number of necessary test iterations/executions are auto-detected and
increased until the final result has the desired number of signifiant figures.

To minimize noise, the executions and measurements are performed in C,
as measuring using PL/pgSQL would be too noisy.

`pit.s()`, `pit.ms()`, `pit.us()` and `pit.ns()` immediately
measures the execution time for given internal function,
and return the time in seconds, milliseconds, microseconds and nanoseconds
respectively, as numeric values. These are suitable when you simply want
to do a single measurement.

The below example measures the execution time to compute the square root for
the `numeric` value `2`, and returns the result in nanoseconds.

```sql
CREATE EXTENSION pit;

SELECT pit.ns('numeric_sqrt','{2}');
 ns
-----
 200
(1 row)
```

Another simple example where we measure `pg_sleep(1)` with three
`significant_figures`.

```sql
CREATE EXTENSION pit;

SELECT pit.s('pg_sleep','{1}', 3);
  s
------
 1.00
(1 row)
```

`pit.async()` defers the measurement and just returns an `id`, that the
caller can keep to allow the `final_result` to be joined in later
when the execution time has been computed by the `pit.work()` `PROCEDURE`.

`pit.async()` is meant to be used when you have lots of functions/argument
combinations you want to measure, and have some query or program to
generates those combinations for you, and you want to request all those
values to be measured, without having to do the actual measurement
immediately.

```sql
SELECT pit.async('numeric_sqrt',ARRAY[format('2e%s',unnest)])
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
-- pit.work() can be executed manually like in this example,
-- or, run in the background by adding pg-pit-worker.sh
-- to e.g. launchd or systemd, see Installation section.
--
CALL pit.work(return_when_idle := true);
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
FROM pit.tests
JOIN pit.test_params USING (id)
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

Another nice thing with `pit.async()` and `pit.work()` is that they
spread out the actual measurements over time, by first doing one measurement,
and then instead of immediately proceeding an doing a second measurement
of the same thing, `pit.work()` will instead store the first measurement,
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

Install the `pit` extension with:

    $ git clone https://github.com/joelonsql/pg-timeit.git
    $ cd pg-timeit
    $ make
    $ sudo make install
    $ make installcheck

Optionally, if you need `pit.async()`, you also need to schedule
the `pit.work()` procedure to run in the background.

Here is how to do that on Ubuntu Linux:

    $ sudo cp pit-worker.sh /usr/local/bin/
    $ sudo cp pit.service /etc/systemd/system/
    $ sudo systemctl enable pit
    $ sudo systemctl start pit

Here is how to do that on Mac OS X:

    $ ./add-pit-worker-to-launchd.sh

<h2 id="usage">4. Usage</h2>

Use with:

    $ psql
    # CREATE EXTENSION pit;
    CREATE EXTENSION;

<h2 id="api">5. API</h2>

<h3 id="pit-s"><code>pit.s(function_name [, input_values ] [, significant_figures]) → numeric</code></h3>

  Input Parameter     | Type    | Default
--------------------- | ------- | -----------
 function_name        | text    |
 input_values         | text[]  | ARRAY[]::text[]
 significant_figures  | integer | 1

Immediately measure the execution run time of the built-in internal function named `function_name`.

Returns the measured execution time in seconds.

Optionally, arguments can be passed by specifying `input_values`.

The desired precision of the returned final result can be specified via `significant_figures`, which defaults to 1.

<h3 id="pit-ms"><code>pit.ms(function_name [, input_values ] [, significant_figures]) → numeric</code></h3>

Like `pit.s()`, but returns milliseconds instead.

<h3 id="pit-us"><code>pit.ms(function_name [, input_values ] [, significant_figures]) → numeric</code></h3>

Like `pit.s()`, but returns microseconds instead.

<h3 id="pit-ns"><code>pit.ns(function_name [, input_values ] [, significant_figures]) → numeric</code></h3>

Like `pit.s()`, but returns nanoseconds instead.

<h3 id="pit-async"><code>pit.async(function_name [, input_values ] [, significant_figures]) → bigint</code></h3>

  Input Parameter     | Type    | Default
--------------------- | ------- | -----------
 function_name        | text    |
 input_values         | text[]  | ARRAY[]::text[]
 significant_figures  | integer | 1

Request measurement of the execution run time of `function_name`.

Returns a bigint `id` value that is the primary key in the `pit.tests` table where the requested test is stored to.

<h3 id="pit-now"><code>pit.work()</code></h3>

This procedure performs the measurements requested by `pit.async()` and is supposed to be called in a loop from a script or cronjob.

See the [Installation](#installation) section for how to daemonize it.

<h2 id="api">6. Internal types</h2>

<h3 id="test-state"><code>test_state</code></h3>

`pit.test_state` is an `ENUM` with the following elements:

- **init**: Test has just been initiated.
- **run_test_1**: First test should be executed.
- **run_test_2**: Second test should be executed.
- **final**: The final result has been determined.

<h2 id="internal-functions">7. Internal functions</h2>

<h3 id="pit-round-to-sig-figs"><code>pit.round_to_sig_figs(numeric, integer) → numeric</code></h3>

Round `numeric` value to `integer` number of significant figures.

```sql
SELECT pit.round_to_sig_figs(1234,2);
 round_to_sig_figs
-------------------
              1200
(1 row)

SELECT pit.round_to_sig_figs(12.456,3);
 round_to_sig_figs
-------------------
              12.5
(1 row)

SELECT pit.round_to_sig_figs(0.00012456,3);
 round_to_sig_figs
-------------------
          0.000125
(1 row)

```

<h3 id="pit-measure"><code>pit.measure(function_name text, input_values text[], executions bigint) -> numeric</code></h3>

Performs `executions` number of executions of `function_name` with arguments passed via `input_values`.

<h3 id="pit-eval"><code>pit.eval(function_name text, input_values text[]) -> text</code></h3>

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
SELECT pit.ns('numeric_add', ARRAY['1.5','2.5']);
 ns
----
 20
(1 row)
```

By default, a result with one significant figure is produced.

If we instead want two significant figures:

```sql
SELECT pit.ns('numeric_add', ARRAY['1.5','2.5'], 2);
 ns
----
 24
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
0.000000024 <-- the actual time on this machine, expressed in two sig. figs.
```

But how do we know the claimed exeuction time by `pit` is reasonable?

Let's demonstrate how we can verify it manually.

If it's true that the exeuction time is 24 ns, it should take about 2.4 s
to do 1e8 executions. We will use `generate_series()` for the executions,
but we first have to solve two problems. First, we have to account for the
overhead of `generate_series()`. Secondly, we must avoid caching of the
immutable expression, and use the volatile version we created earlier.

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
takes about 3 seconds longer time, which nicely matches the `pit.now()`
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

Under the hood, `pit` measures the execution time by executing the function
using C, and doesn't use `generate_series()` at all, it is only a suggestion
on how SQL users could try to verify the correctness of the `pit` measurements.
