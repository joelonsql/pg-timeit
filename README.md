<h1 id="top">⏱️🐘<code>timeit</code></h1>

1. [About](#about)
2. [Dependencies](#dependencies)
3. [Installation](#installation)
4. [Usage](#usage)
5. [API](#api)
    1. [timeit.now()]
    2. [timeit.async()]
    3. [timeit.work()]
6. [Internal types](#internal-types)
    1. [test_state]
7. [Internal functions](#internal-functions)
    1. [timeit.round_to_sig_figs()]
    2. [timeit.create_or_lookup_function()]
    3. [timeit.measure()]
    4. [timeit.eval()]
8. [Examples](#examples)

[timeit.now()]: #timeit-now
[timeit.async()]: #timeit-async
[test_state]: #test-state
[timeit.round_to_sig_figs()]: #timeit-round-to-sig-figs
[timeit.create_or_lookup_function()]: #timeit-create-or-lookup-function
[timeit.measure()]: #timeit-measure
[timeit.eval()]: #timeit-eval
[timeit.work()]: #timeit-work

<h2 id="about">1. About</h2>

`timeit` is a [PostgreSQL] extension to measure the execution time of
SQL expressions, with **nanosecond resolution**. The high accurancy is achived
by also adjusting for the overhead of the measurement itself.
The number of necessary test iterations/executions are auto-detected and
increased until the final result has the desired number of signifiant figures.

`timeit.now()` immediately measures the execution time for an expression,
suitable when you simply want to do a single measurement.

The below example measures the execution time to compute the square root for
the `numeric` value `2`. The `numeric_sqrt_volatile()` function is necessary
to avoid caching since `sqrt` is an [immutable] function.

```sql
CREATE EXTENSION timeit;

CREATE FUNCTION numeric_sqrt_volatile(numeric) RETURNS numeric LANGUAGE internal AS 'numeric_sqrt';

SELECT timeit.now('numeric_sqrt_volatile(2)');
    now
-----------
 0.0000002
(1 row)
--
-- 0.0000002 s = 200 ns
--
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
CREATE FUNCTION numeric_sqrt_volatile(numeric) RETURNS numeric LANGUAGE internal AS 'numeric_sqrt';

SELECT timeit.async(format('numeric_sqrt_volatile(2e%s)',unnest))
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
NOTICE:  working
NOTICE:  7 in queue
NOTICE:  7 in queue
NOTICE:  7 in queue
NOTICE:  5 in queue
NOTICE:  5 in queue
NOTICE:  4 in queue
NOTICE:  4 in queue
NOTICE:  4 in queue
NOTICE:  4 in queue
NOTICE:  4 in queue
NOTICE:  4 in queue
NOTICE:  4 in queue
NOTICE:  4 in queue
NOTICE:  3 in queue
NOTICE:  3 in queue
NOTICE:  3 in queue
NOTICE:  3 in queue
NOTICE:  2 in queue
NOTICE:  2 in queue
NOTICE:  1 in queue
NOTICE:  1 in queue
NOTICE:  idle

SELECT
    tests.id,
    test_params.test_expression,
    tests.executions,
    tests.final_result
FROM timeit.tests
JOIN timeit.test_params USING (id)
ORDER BY id;

 id |         test_expression         | executions | final_result
----+---------------------------------+------------+--------------
  1 | numeric_sqrt_volatile(2e0)      |       1024 |    0.0000001
  2 | numeric_sqrt_volatile(2e10)     |        512 |    0.0000001
  3 | numeric_sqrt_volatile(2e100)    |        128 |    0.0000008
  4 | numeric_sqrt_volatile(2e1000)   |         32 |      0.00001
  5 | numeric_sqrt_volatile(2e10000)  |          1 |       0.0006
  6 | numeric_sqrt_volatile(2e100000) |          2 |         0.05
  7 | numeric_sqrt_volatile(2e131071) |          1 |         0.09
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

    $ git clone https://github.com/truthly/pg-timeit.git
    $ cd pg-timeit
    $ make
    $ sudo make install
    $ make installcheck

Optionally, if you need `timeit.async()`, you also need to schedule
the `timeit.work()` procedure to run in the background.

Here is how to do that on Ubuntu Linux:

    $ sudo cp pg-timeit-worker.sh /usr/local/bin/
    $ sudo cp pg-timeit.service /etc/systemd/system/
    $ sudo systemctl enable pg-timeit
    $ sudo systemctl start pg-timeit

Here is how to do that on Mac OS X:

    $ ./add-pg-timeit-worker-to-launchd.sh

<h2 id="usage">4. Usage</h2>

Use with:

    $ psql
    # CREATE EXTENSION timeit;
    CREATE EXTENSION;

<h2 id="api">5. API</h2>

<h3 id="timeit-now"><code>timeit.now(test_expression [, input_types, input_values ] [, significant_figures]) → numeric</code></h3>

  Input Parameter     | Type    | Default
--------------------- | ------- | -----------
 test_expression      | text    |
 input_types          | text[]  | ARRAY[]::text[]
 input_values         | text[]  | ARRAY[]::text[]
 significant_figures  | integer | 1

Immediately measure the execution run time of `test_expression`.

Optionally, arguments can be passed by specifying `input_types` and `input_values`.

The desired precision of the returned final result can be specified via `significant_figures`, which defaults to 1.

<h3 id="timeit-now"><code>timeit.now(test_expression, significant_figures) → numeric</code></h3>

  Input Parameter     | Type    | Default
--------------------- | ------- | -----------
 test_expression      | text    |
 significant_figures  | integer | 1

Immediately measure the execution run time of `test_expression` and produce a result with `significant_figures` significant figures.

<h3 id="timeit-now"><code>timeit.async(test_expression [, input_types, input_values ] [, significant_figures]) → bigint</code></h3>

  Input Parameter     | Type    | Default
--------------------- | ------- | -----------
 test_expression      | text    |
 input_types          | text[]  | ARRAY[]::text[]
 input_values         | text[]  | ARRAY[]::text[]
 significant_figures  | integer | 1

Request measurement of the execution run time of `test_expression`.

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

<h3 id="timeit-create-or-lookup-function"><code>timeit.create_or_lookup_function(argtypes text[], function_definition text, rettype text) → text</code></h3>

Create a temp function with taking `argtypes` as input, defined as
`function_definition` returning `rettype` and return the function name.

The function name is the hash of the input parameters, a concept sometimes
referred to has "content-addressed naming". This idea is inspired by the
Unison language.

It avoids the risk of conflicts and the need to recreate the same function.

Thanks to this concept, the same function can be reused if needed by other
tests, which reduces the bloat caused by the temp functions.

<h3 id="timeit-measure"><code>timeit.measure(test_expression text, input_types text[], input_values text[], executions bigint) -> numeric</code></h3>

Performs `executions` number of executions of `test_expression` with arguments passed via `input_types` and `input_values`.

`input_types` and `input_values` can be empty arrays if the arguments are already contained in the `test_expression`.

<h3 id="timeit-eval"><code>timeit.eval(test_expression text, input_types text[], input_values text[]) -> text</code></h3>

Performs a single execution of `test_expression` with arguments passed via `input_types` and `input_values`.

`input_types` and `input_values` can be empty arrays if the arguments are already contained in the `test_expression`.

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

`numeric_add` and all other arthimetic functions are [immutable], meaning
the function will always return the same output given the same input.
Immutable functions might be cached, which is problematic when benchmarking,
so to circumvent that problem we will create [volatile] versions of the
functions we want to measure.

[immutable]: https://www.postgresql.org/docs/current/xfunc-volatility.html
[volatile]: https://www.postgresql.org/docs/current/xfunc-volatility.html

```sql
CREATE FUNCTION numeric_add_volatile(numeric,numeric)
RETURNS numeric
VOLATILE
LANGUAGE internal
AS 'numeric_add';

SELECT numeric_add_volatile(1.5, 2.5);
 numeric_add_volatile
----------------------
                  4.0
(1 row)
```

We're now ready to measure it.

```sql
SELECT timeit.now('numeric_add_volatile(1.5, 2.5)');
    now
------------
 0.00000003
(1 row)
```

Optionally, we can pass the argument separately:

```sql
SELECT timeit.now('numeric_add_volatile($1, $2)', '{numeric,numeric}', '{1.5, 2.5}');
    now
------------
 0.00000003
(1 row)
```

By default, a result with one significant figure is produced.

If we instead want two significant figures:

```sql
SELECT timeit.now('numeric_add_volatile(1.5, 2.5)', 2);
     now
-------------
 0.000000032
(1 row)
```

```sql
SELECT timeit.now('numeric_add_volatile($1, $2)', '{numeric,numeric}', '{1.5, 2.5}', 2);
     now
-------------
 0.000000032
(1 row)
```

Note the time resolution of the result, `0.000000032` is `0.000000032 * 1e9 = 32 ns`.

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
0.000000032 <-- the actual time on this machine, expressed in one sig. fig.
```

But how do we know the claimed exeuction time by `timeit` is reasonable?

Let's demonstrate how we can verify it manually.

If it's true that the exeuction time is 32 ns, it should take about 3.2 s
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
takes about 3 seconds longer time, which nicely matches the `timeit.now()`
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

Note how `3.181 s` is very close to the predicted time `3.2 s`.
