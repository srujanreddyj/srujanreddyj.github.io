---
layout: post
toc: true
title: "Building a Multimodal Feature Store for Product Quality Risk: A Data-First Journey"
categories: learnings
tags: [markdown, feature-store, data-engineering, mlops, postgres, redis, amazon-reviews, drift-monitoring]
---

# Building a Multimodal Feature Store for Product Quality Risk: A Data-First Journey

## Introduction

Feature stores are the backbone of modern ML systems, yet most tutorials stop at "here's how you write features." This post documents a complete feature-store project from raw data to serving - not as a polished showcase, but as a real engineering journey where the data pushed back, assumptions broke, and the architecture evolved to meet what we actually learned.

The goal: predict whether a brand/store on Amazon is likely to experience quality risk in the next 30 days, using reviews, metadata, and the full lifecycle of a feature store - offline history, online serving, and drift monitoring.

What makes this project different isn't the model, which is a simple logistic regression. It's the **data-centric decisions**: choosing the right grain, preserving temporal correctness, separating offline from online, and monitoring whether the world changed underneath us.

## The Problem

Amazon product reviews contain signals about product quality. A sudden drop in ratings, a spike in negative reviews, or a shift in review patterns can indicate quality issues - counterfeit products, manufacturing defects, or supply chain problems.

We wanted to build a system that could:

1. Detect these signals **before** they become customer complaints
2. Serve the latest risk assessment in real time
3. Alert when the underlying data distribution changes

The dataset: [Amazon Reviews 2023](https://huggingface.co/datasets/McAuley-Lab/Amazon-Reviews-2023), specifically the Electronics category - about 10M reviews with rich metadata including ratings, timestamps, verified purchase flags, and product information.

## The Journey: Where the Data Pushed Back

### Attempt 1: Product-Level Prediction

We started with the obvious grain: **one product, one prediction**. Each row in our training data would represent a product at a point in time, with features computed from its review history and a label based on what happened in the next 30 days.

**The problem:** Most products have very few reviews. After filtering to products with at least 10 lifetime reviews, we found that the median product had only **1 review per 30-day window**. You can't compute a meaningful "average rating over 30 days" from a single review.

This was our first lesson: **the grain must match the signal density.**

### Attempt 2: Widening the Window

We tried extending the label window to 90 days. This helped, but many products still had insufficient data, and we were losing temporal resolution - a 90-day window blurs short-term quality shifts.

### The Breakthrough: Brand/Store Grain

We pivoted to **brand/store-level aggregation**. Instead of predicting risk for a specific product, we predicted risk for a brand's overall quality profile. This gave us:

- **Dense windows**: Brands like Logitech had about 8 reviews per 30-day window; Amazon had about 104.
- **Stable labels**: Enough data to compute meaningful averages and ratios.
- **Business relevance**: Quality issues often affect a brand's entire product line, not just one SKU.

This pivot wasn't a failure. It was the data teaching us what was actually predictable.

## Architecture: The Full Lifecycle

```text
+-----------------------------------------------------------------+
|                        RAW DATA LAYER                           |
|  Amazon Reviews 2023 (streaming) + Product Metadata (DuckDB)    |
+---------------------+-------------------------------------------+
                      |
                      v
+-----------------------------------------------------------------+
|                    DATA QUALITY LAYER                           |
|  - Timestamp parsing (ms -> datetime)                           |
|  - Missingness profiling (empty lists != NaN)                   |
|  - Density validation (grain x window)                          |
+---------------------+-------------------------------------------+
                      |
                      v
+-----------------------------------------------------------------+
|                    LABEL ENGINEERING                            |
|  Forward 30-day window:                                         |
|    avg_rating < 3.0 OR neg_ratio > 0.30 -> quality_risk = True  |
|  Min support: >=3 reviews in window                             |
+---------------------+-------------------------------------------+
                      |
                      v
+-----------------------------------------------------------------+
|                 FEATURE ENGINEERING                             |
|  Rolling windows (7d, 30d, 90d):                                |
|    - review_count, avg_rating, neg_ratio                        |
|    - verified_ratio, has_image_ratio                            |
|    - avg_text_len, avg_title_len                                |
|    - rating_momentum (7d - 90d)                                 |
+---------------------+-------------------------------------------+
                      |
          +-----------+------------+
          v                        v
+---------------+          +---------------+
| OFFLINE STORE |          | ONLINE STORE  |
|  (Postgres)   |          |   (Redis)     |
|               |          |               |
| Full history  |          | Latest vector |
| ASOF joins    |          | per brand     |
| Training data |          | Low latency   |
+------+--------+          +------+--------+
       |                          |
       v                          v
+---------------+          +---------------+
|   TRAINING    |          |   SERVING     |
|               |          |               |
| Time-based    |          | FastAPI       |
| split         |          | /features/    |
| Baseline      |          | {brand}       |
| model         |          |               |
+------+--------+          +------+--------+
       |                          |
       +------------+-------------+
                    v
          +-------------------+
          | DRIFT MONITORING  |
          |                   |
          | PSI, KS, missing  |
          | Mean shift        |
          +-------------------+
```

## Component Deep-Dives

### 1. Streaming Ingestion with Bounded Sampling

The full Amazon Reviews dataset is massive. We needed a representative sample that was:

- **Dense enough** for meaningful features
- **Small enough** to iterate quickly
- **Reproducible** across runs

**Solution:** Stream reviews, bucket by `parent_asin`, keep products once they cross a review threshold of 10+ reviews, and stop after N products.

```python
for row in stream:
    asin = row["parent_asin"]
    buckets[asin].append(row)
    if len(buckets[asin]) == REVIEW_THRESHOLD:
        kept.add(asin)
    if len(kept) >= N_PRODUCTS:
        break
```

**Tradeoff:** This biases toward popular products. For a production system, we'd want stratified sampling or importance weighting. For a prototype, it gave us the density we needed.

### 2. Data Quality: Beyond `isna()`

Pandas `isna()` told us there were no missing values. But profiling revealed:

- **91.5% of review-level image lists were empty**: not NaN, but empty lists
- Timestamps were in milliseconds, not datetime objects
- Some products had reviews from 1970 because of parsing errors

**Lesson:** `isna()` catches NULLs, not semantic emptiness. We added explicit checks for:

- Empty lists/tuples
- Blank strings
- Invalid timestamps
- Sentinel values, such as `rating = 0`

### 3. Label Engineering: Forward-Looking, Backward-Featuring

The label uses **future data**:

```python
future_window = reviews[(timestamp > t) & (timestamp <= t + 30 days)]
avg_rating = future_window["rating"].mean()
neg_ratio = (future_window["rating"] <= 2).mean()
quality_risk = (avg_rating < 3.0) or (neg_ratio > 0.30)
```

Features use **only historical data**:

```python
past_window = reviews[timestamp < t]
# Compute rolling aggregates...
```

This separation is critical. If a feature accidentally includes the current review, you've leaked the label into your features.

**Min-support rule:** If the future window has fewer than 3 reviews, the label is NaN, not False. This prevents noisy labels from sparse data.

### 4. Point-in-Time Correctness: The ASOF Join

When retrieving features for training, we need the **latest feature row available at or before the event timestamp**:

```sql
SELECT *
FROM brand_feature_events
WHERE store = :store
  AND timestamp <= :event_timestamp
ORDER BY timestamp DESC
LIMIT 1;
```

This is an **ASOF join**. It matches on the closest timestamp that doesn't exceed the event time.

**Validation:** After the join, we verify:

```python
assert (df["feature_timestamp"] <= df["event_timestamp"]).all()
```

**Nuance:** Some rows have `feature_timestamp == event_timestamp`. This is safe because rolling features use `closed="left"`, excluding the current event.

### 5. Offline vs. Online Store: Why Two?

**Offline store (Postgres):**

- Stores full feature history
- Supports ASOF joins for training
- Optimized for analytical queries
- Can be large, from GB to TB

**Online store (Redis):**

- Stores only the **latest** feature vector per brand
- Optimized for low-latency point lookups
- Memory-bounded at 512MB in our config
- Uses `allkeys-lru` eviction policy

**Why not just use Postgres for serving?** Latency. A Redis lookup takes about 1ms; a Postgres query with ASOF semantics takes about 10-50ms. For real-time serving, that matters.

**Why not just use Redis for everything?** Memory. Redis can't efficiently store full feature history. The offline store needs to support historical queries, backfills, and large-scale analytics.

### 6. Drift Monitoring: Alert, Not Diagnosis

We implemented four drift metrics:

- **PSI (Population Stability Index)**: Measures distribution shift using baseline quantile bins.
- **KS test**: Statistical test for numeric distribution difference.
- **Missingness drift**: Did NaN rate change?
- **Mean/std shift**: Simple interpretable level change.

**Top drift findings:**

```text
review_count_7d   PSI 2.67, mean dropped ~22.9
review_count_30d  PSI 2.52, mean dropped ~81.6
review_count_90d  PSI 2.49, mean dropped ~194.1
```

**Interpretation:** The current period, 2021 and later, has substantially lower review volume than the baseline, which is pre-2021. This could be:

- Real-world behavior change, such as fewer reviews per product
- Sampling/coverage change, such as a different product mix
- Seasonality, such as holiday spikes versus baseline
- Pipeline change, such as an updated data source

**Key insight:** Drift is an **alert**, not a diagnosis. The metrics tell you something changed; you still need to investigate why.

**Pitfall:** With large datasets, KS p-values go to zero easily. Don't alert on p-value alone. Use effect size: PSI, KS statistic, and mean shift.

## Decisions and Tradeoffs

### Decision 1: Brand Grain Over Product Grain

**Why:** Product-level 30-day windows had median 1 review - too sparse for stable labels.

**Tradeoff:** Brand-level prediction is less granular. You can't say "Product X is risky," only "Brand Y's overall quality is declining."

**When to revisit:** If you have high-volume products, such as bestsellers with 100+ reviews/month, product grain becomes viable.

### Decision 2: Tabular Features Only, For Now

**Why:** We focused on rolling aggregates - rating, volume, and ratios - because they're interpretable, fast to compute, and sufficient for a baseline.

**Tradeoff:** We're not using text embeddings or image features yet. These could capture sentiment shifts or visual quality issues.

**When to revisit:** Once the tabular baseline is stable, add text embeddings, such as sentence-transformers, and image features, such as CLIP embeddings.

### Decision 3: Logistic Regression Baseline

**Why:** Simple, interpretable, fast to train. Good for validating feature quality before adding complexity.

**Tradeoff:** It may not capture non-linear relationships or interactions.

**Results:** AUC 0.87, average precision 0.65 - strong signal from features.

**When to revisit:** Try XGBoost or neural networks once you've validated the feature pipeline end to end.

### Decision 4: JSON Serialization in Redis

**Why:** Debuggable, human-readable, easy to inspect.

**Tradeoff:** Larger payload size than binary formats, such as Protocol Buffers.

**When to revisit:** At high QPS or large feature vectors, switch to binary serialization.

## What We Learned

### 1. Data Quality Is the Foundation

You can't build good features on bad data. Timestamp correctness, missingness semantics, and density validation are not optional. They're prerequisites.

### 2. The Grain Must Match the Signal

Don't force a grain that doesn't have enough data. If your label is sparse at the product level, aggregate to a coarser grain: brand, category, or seller.

### 3. Temporal Correctness Is Causality

Forward-looking labels + backward-looking features + point-in-time joins = no leakage. This is non-negotiable.

### 4. Offline and Online Are Different Problems

The offline store optimizes for history and training. The online store optimizes for latency and freshness. Don't conflate them.

### 5. Drift Is an Alert, Not a Diagnosis

Metrics tell you something changed. You still need to investigate why: seasonality, sampling, real-world behavior, or pipeline issues.

### 6. Start Simple, Scale Later

Logistic regression + tabular features + Postgres + Redis is enough to validate the full lifecycle. Don't add complexity - embeddings, Spark, Kubernetes - until you've proven the basics work.

## Scaling: GB -> TB -> PB

### GB Scale: Current

- **Tools:** pandas, Postgres, Redis, sklearn
- **Good for:** Prototyping, debugging, validating feature logic
- **Limitations:** Full scans, single-machine, manual orchestration

### TB Scale

- **Tools:** Spark, partitioned Parquet/Iceberg, Airflow/Dagster
- **Changes:**
  - Avoid full scans by partitioning by date/entity
  - Pre-aggregate daily rollups
  - Use batch ASOF joins
  - Monitor schema and data quality per partition
- **Redis:** Redis Cluster or managed online feature store

### PB Scale

- **Tools:** Iceberg/BigQuery, distributed SQL engines, data lakehouse
- **Changes:**
  - Never recompute full history unnecessarily
  - Use partition pruning, clustering, and time travel
  - Use incremental processing with exactly-once semantics
  - Add data quality gates and lineage tracking
  - Plan for schema evolution and backward compatibility
- **Redis:** Still only stores latest vectors; history stays in the lakehouse

**Key principle:** At PB scale, the architecture becomes **lakehouse-centric**. Raw data lives in the lakehouse, pre-aggregated features are materialized to serving stores, and the feature store becomes a thin layer on top.

## Future Scope

### 1. Multimodal Features

Add text embeddings for sentiment and topic, plus image embeddings for visual quality and defect detection. This requires:

- Shared `transforms.py` contract across modalities
- Embedding storage, either a vector database or a feature store with vector support
- Drift monitoring for embedding distributions, such as centroid shift and cosine similarity

### 2. Real-Time Feature Computation

Move from batch materialization to real-time feature computation:

- Stream processing with Kafka and Flink
- Online aggregation with incremental rolling windows
- Sub-second latency for serving

### 3. Model Serving

Add a `/predict/{brand}` endpoint:

- Load trained model artifact
- Apply the same imputation and scaling used in training
- Return risk score and confidence interval

### 4. Feedback Loop

Track predictions to outcomes:

- Did the brand actually experience quality issues?
- Were false positives investigated?
- Use outcomes to retrain and improve the model

### 5. Alerting and Observability

Move from drift reports to active monitoring:

- Alert on sustained drift, not just one-off spikes
- Track feature freshness and materialization lag
- Build a dashboard for data quality and model performance

## Conclusion

This project wasn't about building the most complex model. It was about building a **complete, correct, and scalable feature store** - from raw data to serving to monitoring.

The hardest part wasn't the code. It was listening to what the data was telling us:

- "Product grain is too sparse." -> Pivot to brand.
- "Timestamps are wrong." -> Fix parsing.
- "Review volume changed." -> Investigate drift.

The best feature stores aren't built by engineers who know all the answers. They're built by engineers who ask the right questions and let the data guide the architecture.

Thanks for reading. If you're building a feature store, I'd love to hear what challenges you've faced, especially the ones where the data pushed back.
