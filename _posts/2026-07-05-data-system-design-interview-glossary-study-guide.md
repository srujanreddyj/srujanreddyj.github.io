---
layout: post
toc: true
hidden_home: true
study_guide: true
title: "Data System Design Interview Glossary"
categories: [learnings]
tags: [data-engineering, system-design, interview-prep, glossary, study-guide]
---

# Data System Design Interview Glossary

A reference of every technical concept a data engineer should be ready to name, define, or trade off in a data architecture interview. Organized to map onto your delivery framework: **Functional Requirements → Non-Functional Requirements → Core Entities → Data Flow → High-Level Design → Deep Dive**.

---

## 1. Requirements & Workload Characterization

*(Functional + Non-Functional Requirements stage — this is where seniors separate from juniors. Quantify everything.)*

- **Workload characterization** — Describing the data workload in numbers before picking tools: volume (GB/TB per day), velocity (events/sec), variety (structured/semi/unstructured), growth rate, and access patterns.
- **Freshness / latency SLA** — How stale data is allowed to be at the consumer (e.g., "dashboards must reflect events within 15 minutes"). The single biggest driver of batch vs streaming.
- **Throughput** — Volume of data processed per unit time (events/sec, MB/sec). Determines partitioning, parallelism, and tool choice.
- **Latency** — Time from event occurrence to it being available/actioned. Distinguish end-to-end latency from per-stage latency.
- **SLA / SLO / SLI** — SLA: the contractual promise (e.g., data ready by 6am). SLO: the internal target (99.5% of runs on time). SLI: the measured indicator (actual landing time).
- **Consumer profile** — Who uses the data: BI/analytics, ML training, real-time applications, reverse-ETL to operational tools. Each has different latency/consistency needs.
- **Read vs write patterns** — Append-only event streams vs mutable operational records; point lookups vs full scans vs aggregations. Shapes storage and serving choices.
- **Data retention requirements** — How long raw and processed data must be kept (compliance, reprocessing, cost).
- **Scalability** — Ability to handle growth in volume/velocity. Horizontal (add nodes) vs vertical (bigger nodes) scaling.
- **Availability** — Percentage of time the system is operational (99.9% = ~8.7 hrs downtime/yr). Trade off against cost and consistency.
- **Durability** — Guarantee that ingested data is never lost (e.g., S3's 11 nines).
- **Consistency (eventual vs strong)** — Strong: all readers see the latest write immediately. Eventual: readers may see stale data briefly. Analytics usually tolerates eventual; financial serving may not.
- **CAP theorem** — In a partition, a distributed system chooses consistency or availability, not both. Frame serving-layer choices with it.
- **Cost budget** — Monthly $ estimate for storage + compute + egress. Senior candidates volunteer a number.
- **Back-of-envelope estimation** — Quick math: events/sec × bytes/event × 86,400 = daily volume; project storage/yr; size Kafka partitions and warehouse compute from it.

---

## 2. Core Entities & Data Modeling Concepts

- **Core entities** — The nouns of the domain (user, order, event, session) and their relationships; drives grain and schema.
- **Grain** — The level of detail one row represents (one row per order? per order line? per event?). Declare grain before designing any table.
- **Fact table** — Table of measurable events at a declared grain (orders, clicks, payments), with foreign keys to dimensions.
- **Dimension table** — Descriptive context for facts (customer, product, date). Denormalized attributes for slicing.
- **Star schema vs snowflake schema** — Star: denormalized dimensions, fewer joins, faster BI. Snowflake: normalized dimensions, less redundancy, more joins.
- **Slowly Changing Dimensions (SCD)** — Handling dimension attribute changes over time. Type 1: overwrite. Type 2: add versioned row with effective dates (preserves history). Type 3: add column for previous value.
- **Normalization vs denormalization** — Normalization removes redundancy (good for OLTP writes); denormalization duplicates for read speed (good for OLAP).
- **Additive / semi-additive / non-additive measures** — Additive: summable across all dimensions (revenue). Semi-additive: summable across some (account balance not across time). Non-additive: never summable (ratios, percentages).
- **Conformed dimensions** — Shared dimensions reused across fact tables so metrics reconcile across subject areas.
- **Surrogate key vs natural key** — Surrogate: system-generated ID, stable across source changes, enables SCD2. Natural: business key from the source.
- **Bridge table** — Resolves many-to-many relationships between facts and dimensions.
- **One Big Table (OBT)** — Fully denormalized wide table; simple for BI, expensive to maintain and prone to grain confusion.
- **Data vault** — Modeling style (hubs, links, satellites) optimized for auditability and multi-source integration.
- **Schema-on-read vs schema-on-write** — Schema-on-write: enforce structure at ingest (warehouse). Schema-on-read: store raw, apply schema at query time (lake).

---

## 3. Ingestion

- **Batch ingestion** — Periodic bulk loads (hourly/daily). Simple, cheap, high latency.
- **Streaming ingestion** — Continuous event capture as data is produced. Low latency, higher operational complexity.
- **Micro-batching** — Small frequent batches (e.g., Spark Structured Streaming) — a middle ground between batch and true streaming.
- **CDC (Change Data Capture)** — Capturing row-level changes (insert/update/delete) from an operational DB, typically by reading the transaction log (e.g., Debezium reading Postgres WAL). Low-impact, near-real-time replication.
- **Log-based vs query-based CDC** — Log-based: reads DB write-ahead log, captures deletes, low source load. Query-based: polls with timestamps, misses deletes, adds load.
- **ETL vs ELT** — ETL: transform before loading (transform in a processing engine). ELT: load raw into warehouse/lake, transform there (dbt pattern). ELT favors cheap storage + elastic warehouse compute.
- **Delivery semantics** — Guarantees on message delivery: **at-most-once** (may lose), **at-least-once** (may duplicate — the practical default), **exactly-once** (no loss, no dupes — requires idempotent producers + transactional/checkpointed consumers, not free).
- **Idempotency** — An operation that produces the same result no matter how many times it runs. The foundation of safe retries, reruns, and at-least-once pipelines (e.g., MERGE/upsert by key instead of blind INSERT).
- **Deduplication** — Removing duplicate records, usually via a unique event ID + window (streaming) or ROW_NUMBER over a business key (batch). Pairs with at-least-once delivery.
- **Backpressure** — What happens when consumers can't keep up with producers; the system must buffer, throttle, or drop. Kafka absorbs it in the log; direct pipelines need explicit handling.
- **Message queue vs event log** — Queue (SQS/RabbitMQ): message consumed once and gone. Log (Kafka/Kinesis): append-only, retained, replayable by many consumers.
- **Kafka core concepts** — Topics, partitions (unit of parallelism and ordering), consumer groups, offsets, replication factor, retention, compacted topics.
- **Partitioning key (streaming)** — Field that determines which partition an event lands in; guarantees ordering per key; poor choice causes hot partitions/skew.
- **Kafka vs Kinesis vs Pub/Sub** — Kafka: max control, ecosystem, self-managed ops burden (or MSK/Confluent). Kinesis/PubSub: managed, quota-limited, cloud-locked. Trade control vs ops.
- **Managed connectors (Fivetran / Airbyte / Kafka Connect)** — Off-the-shelf source connectors; trade build cost vs per-row pricing and flexibility.
- **Schema registry** — Central store of event schemas (Avro/Protobuf/JSON Schema) that enforces compatibility between producers and consumers.
- **Schema evolution & compatibility** — Rules for changing schemas without breaking consumers: backward (new reader, old data), forward (old reader, new data), full.
- **Data contracts** — Explicit, enforced agreements between producers and consumers about schema, semantics, SLAs — shifting quality left to the producer.
- **Ingestion failure handling** — Retries with exponential backoff, dead-letter queues (DLQ) for poison messages, replay from offsets/checkpoints.
- **Dead-letter queue (DLQ)** — Side channel for records that repeatedly fail processing, so one bad record doesn't halt the pipeline.
- **API / webhook / file-drop ingestion** — Pull (poll APIs), push (webhooks), and batch file landing (SFTP → object store) patterns for third-party sources.
- **Full load vs incremental load** — Reload everything vs load only new/changed rows (via high-watermark timestamp, sequence ID, or CDC).
- **High-watermark / bookmark** — Persisted marker of the last successfully ingested position, enabling incremental, restartable loads.

---

## 4. Storage

- **Data lake** — Cheap object storage (S3/GCS/ADLS) of raw and processed files; schema-on-read; flexible but historically weak on transactions.
- **Data warehouse** — Managed MPP analytical database (Snowflake/BigQuery/Redshift); schema-on-write, strong SQL performance, higher cost per TB.
- **Lakehouse** — Lake storage + warehouse capabilities via open table formats (ACID, schema enforcement, time travel) — Databricks/Iceberg pattern.
- **MPP (Massively Parallel Processing)** — Warehouse architecture that shards queries across many nodes.
- **Separation of storage and compute** — Storage (object store) scales independently from compute (elastic clusters/warehouses); enables pay-per-use and multiple engines over one copy of data.
- **Columnar storage** — Storing data column-by-column (Parquet/ORC); reads only needed columns, compresses well — the analytics default.
- **Row-based storage** — Row-by-row (Avro, OLTP databases); good for whole-record reads and writes/streaming payloads.
- **Parquet / ORC / Avro** — Parquet/ORC: columnar analytics file formats. Avro: row-based with rich schema evolution, common on the wire in Kafka.
- **Open table formats: Iceberg / Delta Lake / Hudi** — Metadata layers over Parquet giving ACID transactions, schema evolution, time travel, hidden partitioning (Iceberg), upserts (Hudi/Delta). Compare on ecosystem lock-in, streaming upsert support, and catalog integration.
- **ACID transactions** — Atomicity, Consistency, Isolation, Durability — table formats bring these to the lake, enabling safe concurrent writes.
- **Time travel** — Querying a table as of a previous snapshot/version (debugging, reproducibility, rollback).
- **Medallion architecture (Bronze/Silver/Gold)** — Tiered refinement: Bronze = raw as-ingested, Silver = cleaned/conformed, Gold = business-level aggregates/marts.
- **Raw / staging / curated zones** — The generic version of medallion tiering; always keep immutable raw for reprocessing.
- **Partitioning (storage)** — Physically organizing data by column values (usually date) so queries prune irrelevant data. Wrong partition key = full scans.
- **Partition pruning** — Query engine skipping partitions that can't match the filter — the main lever for cost/perf on big tables.
- **Clustering / sort keys / Z-ordering** — Ordering data within partitions by frequently filtered columns to improve pruning (Snowflake clustering, Redshift sort keys, Delta Z-order).
- **Bucketing** — Hash-distributing data into fixed buckets by key to speed joins/aggregations on that key.
- **Small-file problem** — Many tiny files (from streaming writes) degrade query performance and metadata handling; fixed by compaction.
- **Compaction** — Rewriting many small files into fewer large ones; a required maintenance job for streaming-into-lake designs.
- **Hot / warm / cold storage tiering** — Moving aging data to cheaper storage classes (S3 Standard → IA → Glacier) per access pattern; a top cost lever.
- **Data lifecycle policies** — Automated rules for tiering, archival, and deletion (also serves compliance).
- **Compression (Snappy / ZSTD / GZIP)** — Trade CPU vs storage/scan cost; ZSTD/Snappy typical for Parquet.
- **Immutability & append-only design** — Never mutating raw data; corrections happen downstream — enables replay and audit.
- **Object store consistency** — Modern S3 is strongly consistent; still design writes atomically (write-then-commit patterns via table formats).
- **Catalog / metastore** — Where table metadata lives (Hive Metastore, Glue, Unity Catalog, Iceberg REST catalog); a real tradeoff axis in lakehouse designs.

---

## 5. Processing / Transformation

- **Batch processing** — Processing bounded datasets on a schedule (Spark, warehouse SQL, dbt). Simple, replayable, high latency.
- **Stream processing** — Processing unbounded data continuously (Flink, Kafka Streams, Spark Structured Streaming). Low latency, stateful complexity.
- **Lambda architecture** — Parallel batch layer (accurate, complete) + speed layer (fast, approximate), merged at serving. Tradeoff: two codebases, reconciliation pain.
- **Kappa architecture** — Everything is a stream; the log is the source of truth, batch = replaying the stream. Tradeoff: one codebase, but reprocessing large history via replay is costly.
- **Spark** — Distributed batch (and micro-batch streaming) engine; driver/executors, in-memory processing, lazy DAG execution.
- **Flink** — True event-at-a-time stream processor; best-in-class stateful streaming, event time, and exactly-once via checkpointing.
- **dbt** — SQL-based transformation framework in the warehouse (ELT); models, tests, lineage, docs; batch-only.
- **Shuffle** — Redistributing data across nodes for joins/groupBys; the most expensive operation in distributed processing.
- **Data skew** — Uneven key distribution causing a few tasks/partitions to do most work; mitigated by salting, broadcast joins, repartitioning.
- **Broadcast join vs shuffle join** — Broadcast: ship the small table to every node (avoids shuffle). Shuffle join: repartition both sides by key.
- **Predicate pushdown** — Pushing filters down to the storage/scan layer so less data is read.
- **Incremental processing** — Processing only new/changed data each run instead of full recompute; needs watermarks/merge logic; the default at scale.
- **Full refresh vs incremental models** — Rebuild whole table vs merge deltas; full refresh is simpler and self-healing but expensive.
- **Backfill** — Reprocessing historical data (new logic, fixed bug, late source data). Design for it: idempotent, parameterized-by-date jobs and enough compute headroom.
- **Reprocessing / replayability** — Ability to recompute outputs from retained raw data or the event log; the reason you keep immutable Bronze.
- **Stateful vs stateless processing** — Stateless: each event independent (filter, map). Stateful: needs memory of past events (aggregations, joins, sessionization) — requires state backends and checkpoints.
- **Windowing** — Grouping unbounded streams into finite chunks: **tumbling** (fixed, non-overlapping), **sliding/hopping** (overlapping), **session** (gap-based, per-user activity).
- **Event time vs processing time** — Event time: when it happened (correct, needs handling of lateness). Processing time: when the system saw it (simple, wrong under delays).
- **Watermarks (streaming)** — The engine's notion of "event time has progressed to X; data older than X is late" — controls when windows close.
- **Late-arriving data** — Events arriving after their window closed; handled via allowed lateness, side outputs, or downstream corrections/upserts.
- **Checkpointing** — Periodic durable snapshots of streaming state + offsets, enabling failure recovery and exactly-once.
- **Exactly-once processing** — Achieved end-to-end via idempotent/transactional sinks + checkpointed offsets (e.g., Flink two-phase commit, Kafka transactions). Say precisely *how* — never "for free."
- **Stream-stream and stream-table joins** — Joining two streams within a time window, or enriching a stream against a changing table (egs: orders × payments; clicks × user dimension).
- **Sessionization** — Grouping user events into sessions via inactivity gaps — a classic stateful streaming problem.
- **UDFs** — Custom functions in the engine; flexible but often break pushdown/vectorization.
- **Push vs pull transformation placement** — Transform close to source (ETL), in the warehouse (ELT/dbt), or in a lake engine (Spark) — argue via cost, skill set, and reuse.

---

## 6. Orchestration & Workflow

- **Orchestrator** — System that schedules and coordinates pipeline tasks with dependencies (Airflow, Dagster, Prefect).
- **DAG (Directed Acyclic Graph)** — Tasks and their dependency edges; the unit of pipeline definition.
- **Scheduling: cron vs event-driven vs sensor-based** — Fixed time triggers vs run-on-arrival (file lands, upstream table updates) vs polling for a condition.
- **Sensors / triggers** — Tasks that wait for an external condition (file exists, partition ready) before downstream runs.
- **Retries & exponential backoff** — Automatic re-execution of failed tasks with growing delays; only safe if tasks are idempotent.
- **Idempotent reruns** — Any task can be re-executed for a given logical date without duplicating or corrupting output (overwrite-partition or MERGE patterns).
- **Backfill orchestration** — Running a DAG for a historical date range; requires date-parameterized, idempotent tasks.
- **Catchup** — Orchestrator automatically running missed scheduled intervals.
- **Data-aware orchestration / assets** — Scheduling based on datasets being updated rather than clock time (Dagster assets, Airflow datasets).
- **SLA monitoring & freshness checks** — Alerting when a pipeline misses its landing time or a table hasn't updated within its expected window.
- **Task-level vs pipeline-level failure handling** — Retry a task, skip a branch, fail fast, or continue with partial data — and who gets paged.
- **Upstream dependency failure** — What downstream does when a source is late/failed: block, run with stale data (and flag it), or degrade gracefully.
- **Dynamic pipelines** — Generating DAGs/tasks programmatically for hundreds of similar sources (config-driven ingestion frameworks).
- **Concurrency & pools** — Limiting parallel tasks to protect sources and warehouses from overload.
- **Workflow state / metadata DB** — Where the orchestrator tracks run history; itself a reliability dependency.

---

## 7. Serving / Consumption

- **Serving layer** — Where consumers actually read: warehouse for BI, OLAP store for dashboards, KV store for apps, feature store for ML.
- **OLTP vs OLAP** — OLTP: transactional, row-oriented, point reads/writes. OLAP: analytical, columnar, scans/aggregations. Never serve analytics off the OLTP DB.
- **Real-time OLAP engines (Druid / Pinot / ClickHouse)** — Sub-second aggregation queries over fresh event data for user-facing analytics; trade off vs warehouse cost/latency.
- **Semantic layer / metrics layer** — Centralized metric definitions (e.g., dbt metrics, LookML) so "revenue" means one thing everywhere.
- **Materialized views** — Precomputed, auto-refreshed query results; trade storage + refresh cost for read latency.
- **Pre-aggregation / cube / rollup tables** — Precomputing aggregates at common grains to make dashboards cheap.
- **Reverse ETL** — Syncing warehouse data back into operational tools (CRM, ad platforms, support) — the warehouse as source of truth for operational use.
- **Feature store** — ML feature management: **offline store** (historical, training, warehouse/lake) + **online store** (low-latency KV for inference), with consistency between them.
- **Online/offline consistency (training-serving skew)** — Ensuring the feature value used at inference matches how it was computed for training; solved by single feature definitions materialized to both stores.
- **Point-in-time correctness** — Building training sets using only data available as of each label's timestamp — no future leakage.
- **Caching** — Serving hot results from memory (Redis/CDN) in front of expensive queries; define TTL and invalidation.
- **Low-latency KV serving** — Pushing aggregates to DynamoDB/Redis/Cassandra for millisecond app reads over analytical outputs.
- **Data APIs** — Exposing curated data via REST/GraphQL with pagination, auth, and rate limits.
- **Query federation** — Querying across systems without moving data (Trino/Presto); flexible, but slow for heavy joins.
- **Concurrency & workload isolation** — Separating BI, ad-hoc, and pipeline compute (separate warehouses/clusters) so one workload can't starve another.
- **Data sharing** — Zero-copy sharing to external consumers (Snowflake shares, Delta Sharing) instead of file exports.
- **BI tools & extract vs live query** — Cached extracts (fast, stale) vs direct queries (fresh, costly) in Tableau/Looker/Power BI.

---

## 8. Cross-Cutting: Data Quality, Governance, Reliability, Cost

### Data quality & observability
- **Data quality dimensions** — Accuracy, completeness, consistency, timeliness, uniqueness, validity.
- **Data quality tests** — Assertions in the pipeline: not-null, uniqueness, referential integrity, accepted values, freshness, row-count/volume thresholds (dbt tests, Great Expectations, Soda).
- **Anomaly detection on data** — Statistical monitoring of volumes, distributions, null rates to catch silent breakage (Monte Carlo–style observability).
- **Data observability** — The five pillars: freshness, volume, schema, distribution, lineage — monitored continuously.
- **Circuit breakers / quarantine** — Halting downstream propagation or routing bad batches aside when quality checks fail, instead of publishing bad data.
- **Write-audit-publish (WAP)** — Write to a staging branch/table, run audits, then atomically publish — quality gate pattern (natural with Iceberg branches).
- **Reconciliation** — Comparing counts/sums between source and target to prove completeness of loads.
- **Golden datasets / certified tables** — Officially blessed, tested, owned tables that consumers should use.

### Governance & metadata
- **Data governance** — Policies and processes for data ownership, access, quality, and compliance.
- **Data lineage** — Tracking where data came from and what depends on it, column- or table-level; critical for impact analysis and debugging.
- **Data catalog** — Searchable inventory of datasets with owners, descriptions, and metadata (DataHub, Amundsen, Collibra).
- **PII handling** — Identifying and protecting personal data: masking, tokenization, hashing, column-level encryption.
- **Access control: RBAC / ABAC** — Role-based vs attribute-based permissions; row-level and column-level security in the warehouse.
- **Encryption at rest / in transit** — Baseline security expectation; mention KMS-managed keys.
- **Compliance (GDPR / CCPA / HIPAA)** — Regulatory constraints — notably the **right to be forgotten**, which is hard in immutable lakes (requires delete-capable table formats or crypto-shredding).
- **Data retention & deletion policy** — What is kept, for how long, and how deletion is proven.
- **Audit logging** — Recording who accessed/changed what data, for compliance and security.
- **Data mesh** — Decentralized ownership: domain teams own their data as products, on a self-serve platform with federated governance. Tradeoff vs centralized team: autonomy/scale vs consistency/duplication.
- **Data as a product** — Datasets with owners, SLAs, documentation, and quality guarantees — treated like a product for consumers.
- **Master data management (MDM)** — Single authoritative version of key entities (customer, product) across systems.

### Reliability & operations
- **Failure modes: loss, delay, duplication** — For every hop, name where data can be lost, delayed, or duplicated, and how you detect each.
- **Monitoring & alerting** — Pipeline metrics (lag, failure rates, durations) + data metrics (freshness, volume), routed to on-call.
- **Consumer lag** — How far behind a streaming consumer is from the head of the log; the key streaming health metric.
- **Dead-man's switch / freshness alerting** — Alert when something *doesn't* happen (table not updated), not just when jobs error.
- **Graceful degradation** — Serving stale-but-flagged data or partial results instead of nothing when upstream fails.
- **Disaster recovery: RPO / RTO** — RPO: max acceptable data loss (time). RTO: max acceptable downtime. Drive backup and multi-region design.
- **Backup & restore vs replay** — Restoring snapshots vs recomputing from retained raw/log data.
- **Multi-region / cross-region replication** — For DR or locality; expensive — justify with RPO/RTO.
- **Blue-green / shadow pipelines** — Running new pipeline versions in parallel against the old, comparing outputs before cutover — zero-downtime migration pattern.
- **Versioning of data & code** — Table versions (time travel), schema versions, and pipeline code versions tied together for reproducibility.
- **On-call & runbooks** — Documented incident procedures; who gets paged for pipeline vs data-quality failures.
- **Chaos / failure testing** — Deliberately killing consumers/nodes to validate recovery paths.

### Cost
- **Cost levers** — Storage tiering, compression, partition pruning, incremental processing, compute autoscaling/auto-suspend, spot instances, right-sizing warehouses, reducing data scanned.
- **Compute autoscaling & auto-suspend** — Elastic clusters/warehouses that scale with load and stop when idle.
- **Spot / preemptible instances** — Cheap interruptible compute for fault-tolerant batch jobs.
- **Query cost optimization** — Prune partitions, select only needed columns, avoid SELECT *, cluster on filter keys, cache results.
- **Egress costs** — Cross-region/cross-cloud data transfer fees — often the hidden cost of multi-cloud designs.
- **FinOps / cost attribution** — Tagging and chargeback of compute/storage to teams; monitoring per-query and per-pipeline cost.
- **Storage vs compute cost tradeoff** — Precompute (more storage, less repeated compute) vs compute-on-demand (less storage, more query cost).

---

## 9. Rapid-Fire Tradeoff Axes (name these explicitly in the deep dive)

- **Batch vs streaming** — Latency need vs operational complexity and cost. Default to batch unless the SLA demands streaming.
- **Lambda vs Kappa** — Accuracy-with-two-codebases vs simplicity-with-costly-replay.
- **ETL vs ELT** — Transform control and PII scrubbing pre-load vs raw flexibility and warehouse-native transformation.
- **Lake vs warehouse vs lakehouse** — Cost & flexibility vs performance & simplicity vs both-with-newer-tooling-maturity-risk.
- **Kafka vs Kinesis** — Control/ecosystem vs managed simplicity.
- **Flink vs Spark Structured Streaming** — True streaming latency & state vs unified batch+stream and team familiarity.
- **Iceberg vs Delta vs Hudi** — Engine neutrality vs Databricks ecosystem vs upsert-heavy workloads.
- **Airflow vs Dagster/Prefect** — Ecosystem/maturity vs data-asset-aware modern DX.
- **Managed (Fivetran/Snowflake) vs self-built (Kafka/Spark on K8s)** — Speed & lower ops vs cost at scale & control.
- **Exactly-once vs at-least-once + idempotency** — Pay complexity in the transport vs pay it in the sink. Usually the second.
- **Normalize vs denormalize** — Write efficiency & integrity vs read speed.
- **Centralized platform vs data mesh** — Consistency & efficiency vs domain autonomy & scale of ownership.
- **Precompute vs compute-on-read** — Storage cost & staleness vs query cost & latency.
- **Strong vs eventual consistency at serving** — Correctness guarantees vs availability and latency.
- **Buy vs build** — For every layer: connector, quality tool, catalog, orchestrator.

---

## 10. One-Slide Delivery Checklist

1. **Functional requirements** — consumers, use cases, data sources.
2. **Non-functional** — volume/velocity numbers, freshness SLA, availability, retention, cost budget. *(Say numbers out loud.)*
3. **Core entities** — key nouns, grain of the main facts.
4. **Data flow** — narrate source → ingestion → storage → processing → serving; name where data can be **lost, delayed, or duplicated**.
5. **High-level design** — ingestion choice (batch/CDC/streaming), storage (lake/warehouse/lakehouse + table format + medallion), processing (engine + ELT/ETL + incremental), orchestration, serving per consumer.
6. **Deep dives** — delivery semantics & idempotency, schema evolution, partitioning & small files, backfill strategy, data quality & observability, failure handling & DR, cost levers, governance/PII.
7. **Close with tradeoffs** — for every tool named, say what you gave up.
