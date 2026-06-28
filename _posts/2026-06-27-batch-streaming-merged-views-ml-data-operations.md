---
layout: post
toc: true
title: "Batch, Streaming, and Merged Views in ML Data Operations"
categories: [learnings]
tags: [markdown, data-engineering, mlops, batch-processing, stream-processing, lakehouse, feature-store]
---

# Batch, Streaming, and Merged Views in ML Data Operations

In the last few notes, I have been circling around the same lesson from different angles: production ML is mostly data operations. Models matter, but they sit on top of a system that has to acquire data, validate it, enrich it, label it, serve it, monitor it, and keep enough history to debug what happened later.

This post is a companion to my [feature-store system design guide]({% post_url 2026-06-23-machine-learning-system-design-data-centric-feature-stores %}) and the [multimodal feature-store project]({% post_url 2026-06-27-building-a-multimodal-feature-store-product-quality-risk %}). It zooms in on one architectural question that shows up everywhere:

**Which data should move through batch, which data should move through streaming, and how do both paths become one trustworthy view?**

The answer is not "use Spark" or "use Flink." The answer is that different data has different freshness, cost, and correctness requirements. A good data operations platform gives each kind of data the right lane, then forces those lanes to meet behind a shared contract.

## The Three Shapes

At the highest level, I think of data operations as three related shapes.

The batch path:

```text
Data Source (S3, database, API)
       |
       v
[Orchestrator: Airflow/Prefect]
       |
       v
[Processing: Spark/Dask]
       |
       v
[Storage: Data Lake - Iceberg/Delta]
```

The streaming path:

```text
Data Source (Kafka, Kinesis)
       |
       v
[Stream Processor: Flink/Kafka Streams]
       |
       v
[Online Store: Redis/DynamoDB]
       |
       v
[Offline Store: Data Lake (async)]
```

The merged path:

```text
Data Source
       |
  +----+----+
  |         |
  v         v
[Batch]  [Stream]
  |         |
  +----+----+
       |
       v
[Merged View]
```

These are not competing architectures. They are lanes. Batch is for throughput, replay, backfills, and historical correctness. Streaming is for freshness, online decisions, and fast feedback. The merged view is where downstream consumers stop caring which lane produced the data and start trusting one contract.

## The Batch Lane

Batch is the default lane for anything that can wait.

That includes product metadata dumps, daily review exports, annotation batches, synthetic datasets, embedding backfills, periodic quality reports, and large multimodal assets like videos or image corpora. These workloads are expensive to process one record at a time and usually do not need millisecond freshness.

The architecture is intentionally boring:

```text
Source systems
  - S3 object dumps
  - Database snapshots
  - API exports
  - Annotation files
       |
       v
Orchestration
  - Airflow
  - Prefect
  - Dagster
       |
       v
Distributed processing
  - Spark
  - Dask
  - Ray Data
       |
       v
Lakehouse storage
  - Iceberg
  - Delta Lake
  - Parquet
```

The key design decision is that batch owns the durable historical record. If I need to rebuild training data from six months ago, fix a transformation bug, rerun labels, or answer "what did the model know at prediction time?", the batch lane should make that possible.

Batch also gives room for heavy quality gates:

- Schema checks: expected columns, types, timestamp formats
- Value checks: valid ranges, null rates, uniqueness
- File checks: corrupt images, unreadable audio, broken JSON
- Dedup checks: exact hashes, perceptual hashes, embedding similarity
- Distribution checks: drift, label balance, feature statistics

The tradeoff is latency. A daily Spark job is great for cost and reproducibility, but it cannot personalize a user session while the user is still in the session.

| Batch Decision | Why It Helps | What It Costs |
|----------------|--------------|---------------|
| Orchestrated jobs | Clear dependency graph and retries | Scheduling overhead |
| Spark/Dask/Ray processing | High-throughput transforms | Cluster cost and tuning |
| Iceberg/Delta storage | Versioning, schema evolution, time travel | Table maintenance overhead |
| Heavy quality gates | Keeps bad data out of downstream systems | Slower ingestion |
| Backfill support | Reproducible training and debugging | Requires idempotent jobs |

The simplest rule: if correctness, auditability, and cost matter more than freshness, start with batch.

## The Streaming Lane

Streaming is for data whose value decays quickly.

User clicks, impressions, cart events, fraud signals, device telemetry, live ranking feedback, and model-serving logs often need to affect decisions in seconds or minutes. Waiting for tomorrow's batch job means the model is always reacting to yesterday's world.

The streaming path has a different shape:

```text
Event producers
  - App events
  - Service logs
  - Device telemetry
  - Prediction logs
       |
       v
Message bus
  - Kafka
  - Kinesis
  - Pub/Sub
       |
       v
Stream processor
  - Flink
  - Kafka Streams
  - Spark Structured Streaming
       |
       v
Low-latency serving state
  - Redis
  - DynamoDB
  - Cassandra
       |
       v
Async historical sink
  - Iceberg
  - Delta Lake
  - Parquet
```

The online store is not the source of truth. It is serving state. That distinction matters. Redis can answer "what is this user's latest session count?" quickly, but the lake should still receive the same events asynchronously so the system can replay, audit, and rebuild.

Streaming design lives or dies on event semantics:

- **Keys:** What entity does each event update?
- **Event time:** When did the event happen, not when did we process it?
- **Watermarks:** How late can events arrive before we close a window?
- **Idempotency:** Can we replay without double-counting?
- **Backpressure:** What happens when the downstream store slows down?
- **State TTL:** When should online features expire?

The tradeoff is operational complexity. Streaming systems have more moving parts, more failure modes, and more subtle correctness bugs. A broken batch job is often obvious. A broken stream can quietly produce plausible but stale or duplicated features.

| Streaming Decision | Why It Helps | What It Costs |
|-------------------|--------------|---------------|
| Kafka/Kinesis ingestion | Durable ordered event log | Partitioning and retention design |
| Flink/Kafka Streams | Stateful low-latency transforms | Stateful recovery complexity |
| Redis/DynamoDB online store | Fast point lookups | TTL, sync, and cache correctness |
| Async lake sink | Replay and training history | Dual-write consistency concerns |
| Watermarks and event time | Handles late data correctly | Harder mental model |

The simplest rule: use streaming only when freshness changes the product or the model decision.

## The Merged View

The merged view is the part that makes the architecture feel simple to everyone else.

Downstream users should not have to ask, "did this field come from Spark or Flink?" They should ask:

- What entity is this feature keyed by?
- What timestamp is it valid for?
- What version of the definition produced it?
- What quality checks did it pass?
- Can I use it for training, serving, or both?

That means the merged view is not just a table. It is a contract.

```text
                      +----------------------+
Batch features  ----> |                      |
                      |  Merge and Validate  | ---> Offline view
Stream features ----> |                      | ---> Online view
                      +----------------------+
                                |
                                v
                       Registry and lineage
```

A good merged view has five rules.

## Rule 1: Use Event Time as the Join Contract

Training data has to be point-in-time correct. If a model made a prediction at 10:05, it should only see features known by 10:05. Batch and streaming data both need to respect that.

For batch, that usually means ASOF joins:

```sql
SELECT
  e.entity_id,
  e.event_timestamp,
  f.feature_timestamp,
  f.feature_value
FROM events e
ASOF JOIN features f
  ON e.entity_id = f.entity_id
 AND f.feature_timestamp <= e.event_timestamp
```

For streaming, it means windowed state with event-time watermarks:

```text
event_time window: 10:00-10:05
allowed lateness: 2 minutes
feature emitted: 10:07
valid_for: events after 10:05, not before
```

Processing time is an implementation detail. Event time is the ML contract.

## Rule 2: Keep Feature Definitions Shared

Training-serving skew often starts as duplicated code.

One team writes a Spark transformation for training. Another team writes a Flink transformation for serving. Both are called `user_clicks_7d`. They look similar enough to pass a code review, but one filters bot traffic and the other does not. The model trains on one world and serves in another.

The fix is not always literally one codebase. Spark SQL and Flink jobs may still be separate. The fix is one definition contract:

```yaml
feature: user_clicks_7d
entity: user_id
timestamp: event_time
window: 7 days
filters:
  - event_type = 'click'
  - is_bot = false
null_policy: fill_zero
owner: ranking-platform
serving:
  online: true
  offline: true
```

The implementation can vary by engine, but the semantics cannot.

## Rule 3: Treat the Online Store as a Cache of Certified State

Redis and DynamoDB are excellent online stores. They are not good historical memory.

The online path should be fed by certified feature updates, and every update should carry enough metadata to debug it:

```json
{
  "entity_id": "user_123",
  "feature_name": "user_clicks_7d",
  "feature_value": 42,
  "event_time": "2026-06-28T10:05:00Z",
  "computed_at": "2026-06-28T10:05:08Z",
  "definition_version": "v3",
  "ttl_seconds": 604800
}
```

If the online store is corrupted, expired, or accidentally flushed, the lakehouse should be able to rebuild it. If the lakehouse is missing the data, the online store cannot explain what happened.

## Rule 4: Put Quality Gates Before the Merge

The worst place to discover bad data is inside model behavior.

Each lane needs quality checks before it contributes to the merged view:

```text
Batch source  -> batch quality checks  -> batch features
Stream source -> stream quality checks -> stream features
                                      \ 
                                       +-> merged view
```

Batch checks can be heavier: full scans, distribution tests, duplicate detection, and historical comparisons. Streaming checks need to be lighter: schema validation, range checks, null-rate counters, freshness checks, and anomaly detection on aggregates.

For multimodal systems, the gates need to cover more than tables:

- Image readability, dimensions, blur, exposure
- Audio duration, sample rate, clipping, silence
- Text language, toxicity, truncation, encoding
- Annotation agreement and label consistency
- Synthetic-data quality, diversity, and lineage
- Embedding completeness and vector dimension checks

The important principle is that the merged view should only contain data that has crossed a trust boundary.

## Rule 5: Version the View, Not Just the Data

A data version is not only a list of files. It is also:

- The feature definitions
- The transformation code
- The quality checks
- The annotation schema
- The synthetic-data generator version
- The enrichment model version
- The backfill window
- The online materialization policy

If any of those change, the model may see a different world.

For a data operations platform, versioning should answer questions like:

- Which data trained model `v12`?
- Which feature definition produced this online value?
- Which annotation guideline was active?
- Which synthetic generator created these samples?
- Which downstream datasets are affected if this source is deleted?

That is why lineage and governance are part of the architecture, not paperwork after the fact.

## Where the Other Components Fit

Batch, streaming, and merged views are the backbone. The other data operations components plug into that backbone.

| Component | Natural Lane | Why |
|-----------|--------------|-----|
| Annotation workflows | Mostly batch | Human labels arrive in batches and need review |
| Active learning queues | Batch plus feedback stream | Model uncertainty can stream into future labeling batches |
| Synthetic data generation | Batch | Generation, filtering, and evaluation are expensive |
| Multimodal storage | Batch foundation | Large binary assets belong in object storage and manifests |
| ML enrichment | Batch or stream | Backfill embeddings in batch, enrich urgent events in stream |
| Data quality monitoring | Both | Batch checks are deep, stream checks are fast |
| Agentic operations | Both | Agents monitor pipelines, diagnose failures, and apply guarded fixes |
| Self-service tools | Merged view | Users should browse trusted datasets, not raw lane internals |
| Governance | Both | Privacy, lineage, and access control must apply before serving or training |

This is the reason I do not like drawing "the ML data platform" as a single pipeline. Annotation, synthetic data, enrichment, monitoring, and governance are not afterthoughts. They are systems attached to the same contract.

## A Practical Architecture

If I were designing this from scratch, I would start with the smallest version that still preserves the right shape:

```text
                          +--------------------+
Batch sources ----------> | Landing zone       |
APIs and DB snapshots --> | S3/raw tables      |
                          +---------+----------+
                                    |
                                    v
                          +--------------------+
                          | Spark/Dask jobs    |
                          | quality + features |
                          +---------+----------+
                                    |
                                    v
                          +--------------------+
                          | Iceberg/Delta      |
                          | offline truth      |
                          +---------+----------+
                                    |
                                    v
                              [Merged View]

Streaming sources ------> +--------------------+
Kafka/Kinesis events      | Flink/Kafka Streams|
                          | fast features      |
                          +----+----------+----+
                               |          |
                               v          v
                         Redis/DynamoDB  Iceberg/Delta
                         online serving  replay/history
                               |          |
                               +-----+----+
                                     |
                                     v
                              [Merged View]
```

Then I would add complexity only where the requirements force it:

- Add streaming only for features where freshness matters.
- Add active learning only when labeling cost becomes painful.
- Add synthetic data only for class imbalance, edge cases, or domain coverage.
- Add agentic auto-remediation only after the incident patterns are well understood.
- Add self-service tooling once multiple teams need to explore the same trusted data.

The architecture should grow from the contract, not from tool enthusiasm.

## Common Failure Modes

The mistakes are predictable.

**Streaming without replay.** The online store has the latest values, but the lake does not have the events needed to reproduce them.

**Batch without freshness.** The training data is correct, but online decisions are stale because important events wait for tomorrow's job.

**Two feature definitions.** Batch and stream implementations drift apart, creating training-serving skew.

**Quality checks only in batch.** Real-time data bypasses validation and pollutes online serving.

**No late-event policy.** Streaming windows close too early or too late, causing silent count errors.

**Online store as source of truth.** Debugging becomes impossible when low-latency state is treated as historical memory.

**No deletion path.** Privacy and retention requirements are ignored until a compliance request arrives.

The deeper pattern is the same in each case: one lane bypasses the shared contract.

## How I Would Explain This in an Interview

I would keep the answer short first:

> I would build data operations as two latency lanes feeding one governed view. Batch handles high-throughput historical processing into Iceberg or Delta. Streaming handles freshness-sensitive events into Redis or DynamoDB, while also writing back to the lake for replay. The merged view is governed by event time, shared feature definitions, quality gates, lineage, and access control, so training and serving consume the same semantics even if the engines are different.

Then I would defend the tradeoff:

- Batch is cheaper, easier to debug, and better for backfills.
- Streaming is faster but operationally harder.
- The merged view is where correctness lives.
- Online stores are serving state, not historical truth.
- Every path needs quality checks before it can affect a model.

That answer is more important than naming any particular tool. Spark, Flink, Redis, Iceberg, and Airflow are implementation choices. The design is the separation of latency lanes and the discipline of merging them behind one contract.

## Takeaway

Data operations is not a single pipeline. It is a set of coordinated paths with different latency and correctness requirements.

Batch gives you history, replay, and cost efficiency. Streaming gives you freshness. The merged view gives you trust.

The hard part is not moving data from one box to another. The hard part is making sure every box agrees on what the data means.
