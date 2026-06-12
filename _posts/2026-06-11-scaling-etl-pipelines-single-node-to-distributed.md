---
layout: post
toc: true
title: "Scaling ETL Pipelines: From One Machine to Distributed Systems"
categories: learnings
tags: [data-engineering, etl, python, pandas, spark, performance, distributed-systems, lakehouse]
---

# Scaling ETL Pipelines: From One Machine to Distributed Systems

Most ETL pipelines do not fail because the transformation logic is hard.

They fail because the data gets bigger, the job gets slower, memory gets weird, retries duplicate records, schemas drift, and the system that worked perfectly on a laptop becomes impossible to trust in production.

That is the real data engineering growth curve. First you learn how to survive on a single machine. Then you learn when a single machine is the wrong abstraction.

This post splits that journey into two parts:

- **Part 1: Mastering the single node.** What to do when your data outgrows RAM: diagnosing Python memory leaks, chunking a 50 GB file on 16 GB RAM, optimizing Pandas, understanding object overhead with `__slots__`, and making pipelines safe to retry.
- **Part 2: The distributed shift.** What changes when one machine is not enough anymore: choosing between Pandas, Polars, DuckDB, and Spark; optimizing slow Spark jobs; handling upstream schema changes; exactly-once streaming; and designing for 10x data growth.

The goal is not to worship distributed systems. The goal is to know when your bottleneck is local code, when it is data layout, and when it is finally time to move the workload to a bigger execution model.

## The ETL Scaling Curve

Most pipelines start with something simple:

```python
import pandas as pd

df = pd.read_csv("events.csv")
df["event_time"] = pd.to_datetime(df["event_time"])
df = df.dropna(subset=["user_id"])
df.to_parquet("events_clean.parquet")
```

This is fine for 100 MB.

It might still be fine for 2 GB.

At 50 GB, it becomes a different problem. Not because parsing timestamps suddenly became conceptually harder, but because every hidden assumption starts charging interest:

- The whole file must fit in memory.
- Temporary columns create full-size copies.
- Python objects add overhead beyond the raw data size.
- One bad row can kill a multi-hour run.
- A retry might append duplicate output.
- Local disk becomes a staging system by accident.
- A schema change upstream breaks downstream jobs silently.

This is where ETL stops being only about transformation and becomes systems design.

## Part 1: Mastering the Single Node

When your data outgrows your RAM, the first instinct is often to reach for a cluster.

Sometimes that is right. Often, it is early.

Before reaching for Spark, fix the local pipeline. A well-designed single-node job can process surprisingly large data if it streams, batches, writes incrementally, and avoids unnecessary Python object overhead.

The mistake is thinking "single machine" means "load everything into memory." It should mean "one machine coordinates bounded work."

## Diagnosing Python Memory Leaks

In Python ETL jobs, memory leaks are often not C-style leaks. They are usually retention bugs: the program is still holding references to old data.

That is the interview answer I would start with: Python has garbage collection, so the question is usually "what references are growing without bounds?" rather than "where did I forget to call `free()`?"

For diagnosis, `tracemalloc` is a good first tool because it lets you take snapshots at different points in a long-running worker and compare them:

```python
import tracemalloc

tracemalloc.start()

snapshot1 = tracemalloc.take_snapshot()
run_worker_for_a_while()
snapshot2 = tracemalloc.take_snapshot()

for stat in snapshot2.compare_to(snapshot1, "lineno")[:10]:
    print(stat)
```

That diff tells you which lines allocated memory that stayed alive between snapshots. From there, you can usually find the growing structure.

This pattern looks innocent:

```python
all_batches = []

for chunk in pd.read_csv("events.csv", chunksize=500_000):
    cleaned = transform(chunk)
    all_batches.append(cleaned)

result = pd.concat(all_batches)
result.to_parquet("events_clean.parquet")
```

The code uses chunks, but it still keeps every chunk. Memory grows until the process dies.

The better pattern is to make each chunk disposable:

```python
import pandas as pd
import pyarrow as pa
import pyarrow.parquet as pq

writer = None

try:
    for chunk in pd.read_csv("events.csv", chunksize=500_000):
        cleaned = transform(chunk)
        table = pa.Table.from_pandas(cleaned, preserve_index=False)

        if writer is None:
            writer = pq.ParquetWriter("events_clean.parquet", table.schema)

        writer.write_table(table)
finally:
    if writer is not None:
        writer.close()
```

The rule is simple: if a batch is finished, write it and release it.

Common memory retention traps:

- Appending every chunk to a list.
- Keeping debug samples from every batch.
- Capturing large DataFrames inside closures.
- Logging full records instead of counts and IDs.
- Creating global caches with no eviction.
- Keeping unclosed file handles or database cursors alive.
- Calling `pd.concat` repeatedly inside a loop.

Chunking only helps if your code lets go.

For a long-running enrichment worker, the culprit is often an unbounded lookup cache:

```python
# Bad: grows forever until the worker runs out of memory.
lookup_cache = {}

def enrich_user(user_id):
    if user_id not in lookup_cache:
        lookup_cache[user_id] = fetch_from_db(user_id)
    return lookup_cache[user_id]
```

The fix is to enforce a boundary on state:

```python
from functools import lru_cache

@lru_cache(maxsize=10_000)
def enrich_user_safe(user_id):
    return fetch_from_db(user_id)
```

The production lesson is that long-running processes need bounded memory by design. Caches, buffers, metrics, errors, and retry state all need limits.

## Chunking Massive Files

The key to processing a 50 GB file on one machine is to make memory usage independent of file size.

If you try this on a 16 GB machine, the operating system will probably kill the process:

```python
df = pd.read_csv("50gb_data.csv")
```

The fix is streaming. Read a small chunk, process it, update a compact result, and throw the chunk away. In Pandas, the mechanism is `read_csv(chunksize=...)`. In plain Python, the equivalent is using the built-in `csv` module as a generator.

That means:

- Read bounded chunks.
- Validate each chunk independently.
- Write output incrementally.
- Track progress in a small checkpoint.
- Make the output safe to retry.

For CSV input, a chunked pattern is often enough:

```python
import pandas as pd

for batch_id, chunk in enumerate(pd.read_csv("events.csv", chunksize=250_000)):
    cleaned = transform(chunk)
    cleaned.to_parquet(
        f"output/events_clean/part-{batch_id:05d}.parquet",
        index=False,
    )
```

Writing one file per chunk is less elegant than a single output file, but it is much more operationally useful. If batch 172 fails, you can inspect it, replay it, or skip already completed batches.

For production, each chunk should become a small transaction:

1. Read chunk.
2. Validate schema and required fields.
3. Transform.
4. Write to a temporary path.
5. Atomically promote the temporary file to a final path.
6. Record the completed batch in a manifest.

That manifest matters. Without it, a retry has to guess which work already finished.

For example, a grouped sum over a massive CSV can keep only one chunk plus the running totals in memory:

```python
import pandas as pd
from collections import defaultdict

total_sums = defaultdict(float)

for chunk in pd.read_csv("50gb_data.csv", chunksize=100_000):
    chunk_aggregated = chunk.groupby("category_key")["sales_amount"].sum()

    for key, value in chunk_aggregated.items():
        total_sums[key] += value
```

This works when `total_sums` stays small. The senior-level edge case is high-cardinality grouping. If the key is `user_id` and there are hundreds of millions of users, the running dictionary can become the new memory problem.

At that point, the answer changes:

- Spill partial aggregates to disk and merge them later.
- Use DuckDB or another local engine that can spill.
- Push the aggregation into a database.
- Move the aggregation to Spark or another distributed engine if the data and SLA justify it.

## Pandas Optimization: Do Less Work

Pandas performance is usually won by reducing work before making work faster.

The classic interview prompt is: "Your Pandas DataFrame is taking 8 GB of RAM. How do you shrink it?"

The answer is that Pandas defaults are convenient, not always memory efficient. Whole numbers often become `int64`. Decimal numbers often become `float64`. Text often becomes `object`, which means regular Python objects with a lot of overhead.

Start with these questions:

- Are you reading columns you never use?
- Are string columns actually low-cardinality categories?
- Are integers using larger dtypes than needed?
- Are dates parsed repeatedly?
- Are row-wise `apply` calls hiding Python loops?
- Are you copying the full DataFrame for small changes?
- Can string columns use `string[pyarrow]` instead of Python `object`?

Column pruning is the easiest win:

```python
columns = ["user_id", "event_time", "event_type", "amount"]

df = pd.read_csv(
    "events.csv",
    usecols=columns,
    parse_dates=["event_time"],
)
```

Dtype control can dramatically reduce memory:

```python
dtypes = {
    "user_id": "int32",
    "event_type": "category",
    "amount": "float32",
}

df = pd.read_csv(
    "events.csv",
    usecols=["user_id", "event_time", "event_type", "amount"],
    dtype=dtypes,
    parse_dates=["event_time"],
)
```

You can do the same thing when reading a smaller subset of a file:

```python
df = pd.read_csv(
    "data.csv",
    usecols=["user_id", "status"],
    dtype={
        "user_id": "int32",
        "status": "category",
    },
)
```

The interview checklist is:

- **Filter early:** use `usecols` so unnecessary columns never enter memory.
- **Downcast numerics:** convert `int64` to `int32`, `int16`, or `int8` when values fit; convert `float64` to `float32` when precision allows.
- **Use categories:** convert low-cardinality strings such as `"Pending"`, `"Approved"`, and `"Failed"` to `category`.
- **Use PyArrow-backed strings:** use `string[pyarrow]` for string-heavy columns when available.

For existing DataFrames, measure first:

```python
print(df.memory_usage(deep=True))
```

Then convert the obvious offenders:

```python
df["status"] = df["status"].astype("category")
df["user_id"] = pd.to_numeric(df["user_id"], downcast="integer")
df["amount"] = pd.to_numeric(df["amount"], downcast="float")
df["comment"] = df["comment"].astype("string[pyarrow]")
```

Categories are powerful when a column repeats the same few values. Instead of storing `"Pending"`, `"Approved"`, and `"Failed"` as full strings across millions of rows, Pandas stores a small mapping once and represents each row with compact integer codes.

It looks the same when printed, but the memory usage can drop dramatically.

Avoid row-wise `apply` when a vectorized expression exists:

```python
# Slower: Python function call per row.
df["is_purchase"] = df.apply(lambda row: row["event_type"] == "purchase", axis=1)

# Faster: vectorized comparison.
df["is_purchase"] = df["event_type"].eq("purchase")
```

The deeper lesson is that Pandas is fast when the work stays in arrays. It gets slow when you accidentally turn the job into millions of Python object operations.

## Object Overhead and `__slots__`

Raw data size is misleading.

A 5 GB CSV does not become a 5 GB DataFrame. Strings, Python objects, indexes, temporary arrays, and intermediate copies can multiply memory usage.

This is especially painful with `object` dtype:

```python
print(df.info(memory_usage="deep"))
```

If a column has repeated strings, convert it to `category`:

```python
df["event_type"] = df["event_type"].astype("category")
```

If you are building millions of Python dictionaries, reconsider the shape of the pipeline:

```python
# Expensive at scale.
records = df.to_dict("records")
```

That conversion turns compact columnar data into a large pile of Python objects. It might be convenient for a small API payload, but it is a bad internal representation for large ETL steps.

Prefer columnar formats and columnar execution:

- Parquet instead of CSV for intermediate data.
- Arrow tables instead of lists of dictionaries.
- Vectorized Pandas operations instead of row loops.
- Polars or DuckDB when local columnar execution is a better fit.

On one machine, the difference between "array of values" and "millions of Python objects" can be the difference between finishing and OOM.

This also matters outside Pandas. If your ETL code creates millions of small Python objects, every instance normally carries a per-object `__dict__` so attributes can be added dynamically:

```python
class Event:
    def __init__(self, user_id, event_type, amount):
        self.user_id = user_id
        self.event_type = event_type
        self.amount = amount
```

Another version of the same problem:

```python
# Bad: uses a __dict__ for every instance.
class UserRecord:
    def __init__(self, user_id, name):
        self.user_id = user_id
        self.name = name
```

For small numbers of objects, this is fine. For millions, the overhead becomes real.

If the shape is fixed, `__slots__` removes the per-instance dictionary:

```python
class Event:
    __slots__ = ("user_id", "event_type", "amount")

    def __init__(self, user_id, event_type, amount):
        self.user_id = user_id
        self.event_type = event_type
        self.amount = amount
```

```python
# Better: no per-instance __dict__.
class SlottedUserRecord:
    __slots__ = ("user_id", "name")

    def __init__(self, user_id, name):
        self.user_id = user_id
        self.name = name
```

That can reduce memory when you truly need Python objects. But the bigger lesson is more important: if the pipeline is doing analytical work, prefer columnar data structures over millions of custom Python objects.

Use `__slots__` as a pressure valve, not as an excuse to turn a data pipeline into object soup.

## Making Pipelines Idempotent

An ETL job is idempotent when running it twice produces the same final state as running it once.

That is not a nice-to-have. It is the difference between reliable pipelines and pipelines that create quiet data corruption.

The easiest test is:

```text
Run the same job twice with the same input.
Does the output contain duplicate rows?
Does the target table have the same record count?
Are partition files replaced predictably?
Can downstream jobs tell which version is complete?
```

Bad retry behavior usually comes from append-only writes:

```python
df.to_sql("events_clean", conn, if_exists="append", index=False)
```

If the job fails halfway and retries, already inserted rows may be inserted again.

Safer patterns include:

- Write to a run-specific staging table, then merge.
- Partition output by deterministic keys such as `event_date`.
- Overwrite only the partitions owned by the run.
- Use primary keys or deduplication keys during upsert.
- Write a success marker only after all expected output is complete.

For database writes, the difference is usually blind insert versus upsert:

```sql
-- Bad: if this runs twice, you get duplicate logical records.
INSERT INTO users (id, name, last_login)
VALUES (1, 'Alice', '2023-10-01');

-- Better: if this runs twice, the existing row is updated.
INSERT INTO users (id, name, last_login)
VALUES (1, 'Alice', '2023-10-01')
ON CONFLICT (id)
DO UPDATE SET last_login = EXCLUDED.last_login;
```

For a Pandas-based batch, the same idea is append plus deterministic deduplication:

```python
# Bad: blindly appends the new batch.
master_df = pd.concat([master_df, new_batch])

# Better: keep one row per id, preserving the newest version.
master_df = pd.concat([master_df, new_batch])
master_df = master_df.drop_duplicates(subset=["id"], keep="last")
```

For file-based pipelines, this often means writing like this:

```text
s3://warehouse/events_clean/event_date=2026-06-11/_tmp/run_id=abc123/part-000.parquet
s3://warehouse/events_clean/event_date=2026-06-11/part-000.parquet
s3://warehouse/events_clean/event_date=2026-06-11/_SUCCESS
```

Consumers should read only complete partitions, not temporary paths from in-progress jobs.

The practical lesson: retries are part of the design, not an exception path.

## When Single-Node Is No Longer Enough

A single-node pipeline can go far, but it has limits.

You should consider a distributed architecture when:

- The input is larger than local disk or practical local processing time.
- One machine cannot meet the pipeline SLA.
- Data must be processed close to object storage.
- Many independent partitions can run in parallel.
- Joins, aggregations, or shuffles exceed local memory.
- Multiple teams need shared tables with schema governance.
- Failure recovery needs to happen at task level, not whole-job level.

The trap is migrating too early. Spark will not fix unclear schemas, non-idempotent writes, or sloppy data contracts. It will make them more expensive.

Distributed systems multiply both throughput and mistakes.

## Part 2: The Distributed Shift

When a single node is not enough anymore, adding machines is only one part of the shift.

Once data outgrows the single-machine model, the question changes from "how do I process this file?" to "how do I design a system that can keep processing changing data safely?"

That brings in engine choice, storage layout, schemas, transactional writes, monitoring, and growth planning.

## Choosing the Right Engine

The classic interview setup is: "A batch job in Pandas takes 6 hours and barely fits in memory. Walk me through how you would decide between scaling Pandas, Dask, Polars, PySpark, DuckDB, or Ray."

A junior answer jumps straight to Spark because Spark is the famous big-data tool.

A senior answer starts with constraints: "Before standing up an expensive cluster, I would see if we can maximize a single node."

There is no universal best engine. There is a best engine for the workload, the team, the latency requirement, and the failure model.

The order I would usually evaluate:

1. **Fix the Pandas job first.** Read fewer columns, downcast types, remove row-wise Python loops, write Parquet, and avoid loading unnecessary data.
2. **Try Polars or DuckDB on one machine.** Both use columnar execution and can often process data larger than RAM through lazy, streaming, or out-of-core execution.
3. **Use Dask when you need distributed execution but want a Pandas-like programming model.** This can be useful for existing Python data workloads, but cross-cluster shuffles can still get painful.
4. **Use PySpark when the workload is truly cluster-scale.** Spark earns its keep for terabytes of data, large joins, heavy aggregations, fault-tolerant batch ETL, and shared data platform work.
5. **Use Ray when the workload is distributed Python, ML, or stateful computation.** Ray can process data, but its strongest fit is not pure SQL-style ETL.

Here is the decision matrix I would keep in my head:

| Engine | Execution model | Data size limit | Best use case | Technical trade-off |
| --- | --- | --- | --- | --- |
| Pandas | Eager, mostly single-node | Fits in RAM, often needing much more RAM than raw data size | Ad-hoc analysis and small datasets | Memory-heavy; many Python-level operations run into interpreter overhead |
| Polars | Lazy, multi-threaded, Apache Arrow-based | Larger than RAM for some streaming/out-of-core workloads | Fast single-node ETL with a DataFrame API | Requires rewriting Pandas code into Polars expressions |
| DuckDB | Vectorized columnar SQL | Larger than RAM for many analytical workloads | SQL analytics over CSV, Parquet, and local/object-store data | SQL-focused; less natural for complex custom Python logic |
| Dask | Lazy distributed task graph | Cluster scale | Scaling existing NumPy/Pandas-style code | Can struggle with large distributed shuffles compared with Spark |
| PySpark | Lazy distributed execution on the JVM | Terabyte to petabyte cluster scale | Massive ETL, heavy joins, aggregations, and fault-tolerant pipelines | Higher operational cost, infrastructure complexity, and JVM/Python serialization overhead |
| Ray | Distributed actor and task model | Cluster scale | Distributed ML, custom Python workloads, stateful services, parallel ingest | Not primarily a SQL/DataFrame query engine, though Ray Data is useful for ML pipelines |

The senior interview answer in one sentence:

```text
Before paying the operational tax of a Spark cluster, I would rewrite the
6-hour Pandas job in Polars or DuckDB and see whether lazy columnar execution
can finish it on a single node.
```

The mistake is choosing based on popularity instead of constraints. Start with volume, latency, joins, shuffle size, state, team skill, operational maturity, and cost.

## Spark Optimization Is Mostly Data Movement

Spark is fast when each executor can do useful work with minimal shuffling.

It is slow when the job constantly moves data across the network.

The interview prompt usually sounds like this: "A Spark job is slow and occasionally fails with executor out-of-memory errors. Diagnose it systematically and list your levers."

The junior answer is "increase executor memory." Sometimes that helps, but it is not a diagnosis.

The senior answer starts with the Spark UI:

- **DAG view:** Which stages are expensive? Where are the shuffle boundaries?
- **SQL tab:** What physical plan did Spark actually run?
- **Tasks tab:** Are task durations roughly even, or did one task run for hours while the others finished in seconds?
- **Shuffle read/write:** Is the job mostly moving data over the network?
- **Spill metrics:** Is Spark repeatedly spilling memory to disk?
- **Input size:** Is the job scanning far more data than the query needs?

If 199 tasks finish in 5 seconds and 1 task takes 2 hours, the problem is probably data skew. One partition got a disproportionate amount of data while the rest of the cluster sat idle.

The main questions for a Spark job are:

- How much data is read?
- How many partitions are created?
- Which operations cause shuffles?
- Are joins broadcastable?
- Are files too small or too large?
- Is one partition much larger than the others?
- Are downstream tables partitioned by the way they are queried?

Column pruning still matters:

```python
df = spark.read.parquet("s3://warehouse/events/")
df = df.select("user_id", "event_time", "event_type", "amount")
```

Predicate pushdown matters:

```python
df = (
    spark.read.parquet("s3://warehouse/events/")
    .where("event_date >= '2026-06-01'")
)
```

Broadcast joins can avoid expensive shuffles when one side is small:

```python
from pyspark.sql.functions import broadcast

# Bad: a standard join can trigger a large network shuffle.
df_joined = huge_transactions_df.join(small_users_df, "user_id")

# Better: copy the small table to each executor and avoid the big shuffle.
df_joined = huge_transactions_df.join(broadcast(small_users_df), "user_id")
```

Broadcast joins are one of the easiest big wins. Joining a 1 TB table with a 10 MB lookup table should not require shuffling both tables across the network.

Data skew needs a different lever. Imagine joining transactions to cities on `city_id`, and 90% of the transactions are for `"NYC"`. Spark may send most of the data to one worker because all those records share the same join key.

One senior-level fix is **salting**:

1. Add a random suffix to the hot key on the huge table, such as `NYC_0`, `NYC_1`, `NYC_2`, `NYC_3`, and `NYC_4`.
2. Replicate the matching row in the small table for each salt value.
3. Join on the salted key so the hot key is spread across multiple partitions.

```python
from pyspark.sql.functions import concat, floor, lit, rand

salted_transactions = huge_transactions_df.withColumn(
    "salted_city_id",
    concat("city_id", lit("_"), floor(rand() * 5)),
)

# Next, replicate each city row in the small table for salt values 0 through 4,
# create the same salted_city_id column there, and join on salted_city_id.
```

Partitioning is a design decision, not a formatting detail. If most queries filter by `event_date`, partitioning by date helps. If you partition by a high-cardinality field like `user_id`, you may create a small-file disaster.

One more rule: do not call `.collect()` on a large distributed dataset.

```python
# Bad: pulls distributed data back to the single driver process.
rows = huge_df.collect()
```

That can instantly move the OOM from the executor to the driver. Use distributed writes, `limit()` for inspection, or aggregate before collecting small results.

Spark performance usually improves when you reduce:

- Data scanned.
- Data shuffled.
- Number of tiny files.
- Skewed partitions.
- Repeated recomputation.
- Python UDF usage.

The cluster is rarely the first problem. The physical plan usually is.

## Schema Evolution

Schemas change because businesses change.

New event types appear. Columns become nullable. IDs change format. Nested fields are added. A source system starts sending `"unknown"` where an integer used to be.

If the pipeline assumes schemas are static, schema evolution becomes an outage.

Good schema evolution has three parts:

- **Compatibility rules:** which changes are allowed?
- **Validation:** where are incompatible records rejected or quarantined?
- **Versioning:** how do consumers know which schema they are reading?

In an interview, I would describe schemas as API contracts. Upstream teams should not be able to silently rename a column, narrow a type, or remove a field that downstream jobs depend on.

That is where a schema registry or catalog helps. For streaming systems, that might be Confluent Schema Registry. For lake and batch systems, it might be AWS Glue, a table catalog, or a lakehouse table format with schema metadata.

Additive changes are usually safest:

```text
old schema:
user_id, event_time, event_type

new schema:
user_id, event_time, event_type, device_type
```

Breaking changes need explicit migration:

```text
old:
amount: string

new:
amount: decimal(12, 2)
```

Safe changes are changes like:

- Adding a nullable column.
- Adding a column with a default.
- Widening a type, such as `int` to `bigint`.

Unsafe changes include:

- Renaming a column.
- Dropping a column.
- Narrowing a type, such as `string` to `int`.
- Changing semantics while keeping the same name.

Unsafe changes should usually create a new versioned table or a compatibility layer instead of breaking existing consumers.

For lakehouse tables, formats like Delta Lake, Apache Iceberg, and Apache Hudi exist because raw Parquet files alone do not solve table evolution, transactional metadata, and concurrent writes.

For safe additive changes in Delta Lake, schema merge can handle new columns without rewriting the entire table:

```python
df_new_data.write \
    .format("delta") \
    .mode("append") \
    .option("mergeSchema", "true") \
    .save("/path/to/table")
```

For bad records, do not fail the whole pipeline if you can safely isolate them. Send contract violations to a dead-letter queue or quarantine path, alert the owning team, and keep the valid data moving:

```text
s3://warehouse/_dlq/events/date=2026-06-11/run_id=abc123/
```

The key point: schema management is not paperwork. It is how producers and consumers avoid surprising each other.

## Exactly-Once Processing Is a System Property

Exactly-once processing is not a line of code. It is a property of the whole pipeline.

You need to reason about:

- Source offsets or input versions.
- Deterministic transformation logic.
- Idempotent writes.
- Transactional commits.
- Deduplication keys.
- Checkpoints.
- Consumer visibility.

In batch ETL, exactly-once often means:

```text
For a given input version and target partition, publish one complete output version.
Retries may recompute work, but they must not publish duplicates.
```

In streaming ETL, the problem is harder because the job never really ends. You need checkpointed offsets, state management, and sinks that can commit consistently.

The interview version is usually: "You consume a Kafka stream and write to a warehouse. How do you guarantee no data loss and no duplicates across worker restarts?"

The senior answer is that true exactly-once delivery over a network is not something you casually switch on. You design for **effectively exactly-once** processing:

- **At-least-once delivery:** commit the source offset only after the sink write succeeds.
- **Idempotent writes:** make the sink write an upsert or merge keyed by a unique event ID.

The order matters:

```python
for batch in stream.poll():
    processed_data = transform(batch)

    warehouse.upsert(processed_data, primary_key="event_id")

    # Commit only after the warehouse write succeeds.
    stream.commit_offset(batch.offset)
```

If the worker crashes after the upsert but before the offset commit, the batch may replay. That is fine because the warehouse write is idempotent.

A practical design is:

1. Read from a versioned source or tracked offset.
2. Transform records deterministically.
3. Write to a staging location.
4. Validate output counts and quality checks.
5. Commit metadata atomically.
6. Expose only committed versions to readers.

Exactly-once is usually built from at-least-once execution plus idempotent or transactional output.

That is the engineering reality: tasks may run more than once. The data should not look like they did.

## Designing for 10x Growth

"Can this handle 10x more data?" is not only a compute question.

The interview version is: "Your pipeline works today, but data volume will 10x in a year. Design for that growth and tell me what you would instrument now."

A junior answer jumps to bigger servers. A senior answer focuses on decoupling, horizontal scalability, storage layout, and observability.

It is a question about every boundary in the system:

- Can ingestion handle 10x files?
- Can storage handle 10x partitions without small-file pain?
- Can metadata operations handle 10x table versions?
- Can the orchestrator schedule 10x tasks?
- Can downstream dashboards tolerate 10x latency?
- Can quality checks still run in the available window?
- Can backfills run without blocking daily jobs?
- Can costs grow sublinearly?

The best 10x designs usually have a few common traits:

- Queue-based ingestion to absorb spikes.
- Partitioned data by access pattern.
- Columnar file formats.
- Idempotent partition replacement.
- Clear data contracts.
- Separate raw, cleaned, and serving layers.
- Backfill strategy that does not fight scheduled jobs.
- Observability at the dataset level, not just task level.
- Compute that can scale independently from storage.

For example:

```text
raw/events/source=web/event_date=2026-06-11/
clean/events/event_date=2026-06-11/
curated/user_activity_daily/ds=2026-06-11/
```

This layout separates ingestion from cleaning from serving. Each layer has a different contract. Raw data is append-only. Cleaned data is validated and normalized. Curated data is shaped for users, dashboards, models, or downstream applications.

That separation makes growth easier because each layer can be optimized without rewriting the whole pipeline.

For ingestion, put a durable buffer between sources and workers:

```text
source systems -> Kafka/Kinesis -> bounded workers -> object storage/table
```

If traffic spikes, the queue gets deeper instead of crashing workers. Then you can scale consumers horizontally.

For observability, monitor leading indicators, not only failures:

```yaml
# Bad: this tells you after the system is already broken.
alert: SystemOutOfMemory
threshold: "> 99%"

# Better: this tells you capacity is falling behind.
alert: QueueDepthIncreasing
condition: "messages_arriving_per_second > messages_processed_per_second"
duration: "15 minutes"
```

Other useful leading indicators:

- Queue depth and consumer lag.
- Memory high-water mark.
- Disk spill volume.
- Rows processed per second.
- File counts per partition.
- Freshness delay for critical tables.
- Cost per million rows processed.

## The Architecture I Would Aim For

For a serious ETL system, I would design around these principles:

- **Object storage as the durable data layer.** Keep raw and processed data in cheap, scalable storage.
- **Columnar formats for analytics.** Use Parquet or a table format built on it.
- **Table metadata for reliability.** Use Iceberg, Delta, or Hudi when concurrent writes, schema evolution, and time travel matter.
- **Orchestration with explicit dependencies.** Airflow, Dagster, or Prefect should model data dependencies, not just task order.
- **Compute matched to workload.** Pandas, DuckDB, Polars, Spark, or Flink depending on scale and latency.
- **Idempotent writes everywhere.** Every retry path should be boring.
- **Data quality gates.** Validate row counts, null rates, uniqueness, freshness, and schema expectations.
- **Observability at data boundaries.** Track what changed, how much changed, and whether consumers should trust it.

The architecture does not need to start complex. It needs to start with contracts that can survive complexity later.

## A Practical Decision Checklist

When a pipeline starts struggling, I like to ask these questions in order:

1. **Can I reduce the input?** Read fewer columns, fewer partitions, or a narrower date range.
2. **Can I stream it?** Process bounded chunks instead of loading the full dataset.
3. **Can I change the representation?** Use Parquet, Arrow, categories, or smaller dtypes.
4. **Can I remove Python loops?** Push work into vectorized operations, SQL, or native execution.
5. **Can I make writes idempotent?** Fix retries before scaling execution.
6. **Can I partition by access pattern?** Make reads and overwrites cheaper.
7. **Can I isolate bad records?** Quarantine instead of crashing the whole job.
8. **Can I run partitions independently?** Parallelism starts with independent work units.
9. **Do I need distributed execution?** Move to Spark or another engine when local execution is no longer enough.
10. **Do I need a table format?** Add transactional metadata when raw files become hard to manage.

This order matters. If the pipeline is wasteful on one machine, it will be expensive on a cluster.

## Final Takeaway

The path from intermediate to advanced ETL is not just learning bigger tools.

It is learning how data systems fail.

At the single-node level, the hard lessons are memory, chunking, object overhead, and efficient local execution. At the distributed level, the hard lessons are data movement, schema contracts, idempotent writes, table metadata, and operational trust.

A good data engineer knows how to squeeze performance out of one machine.

A great data engineer knows when the problem is no longer about one machine at all.
