---
layout: post
toc: true
math: true
title: "What Comes Next for the Multimodal Lakehouse"
categories: learnings
tags: [markdown, multimodal, lakehouse, faiss, ann, data-quality, evaluation, mlops]
---

# What Comes Next for the Multimodal Lakehouse

This project started as a text search demo and grew into a 12-stage multimodal pipeline. The most valuable outcome was not the finished demo. It was discovering which parts of the system are still shallow once the happy path works.

For context, this post follows three earlier notes:

- [Serverless Multimodal Data Lakehouse]({% post_url 2026-06-01-multimodal-embedding-pipeline-lancedb %})
- [Multimodal Lakehouse Implementation Notes]({% post_url 2026-06-11-multimodal-lakehouse-implementation-notes %})
- [Ray Actors, Catalog Trust Boundaries, and Pipeline Battle Scars]({% post_url 2026-06-12-ray-actors-catalog-trust-boundary %})

This post is the roadmap for that next layer: real-scale ANN deduplication, data quality as a measurable system, and closing the evaluation feedback loop.

## 1. ANN Dedup at Real Scale

My current FAISS dedup uses a flat index: brute-force exact search across all vectors.

At 10,000 vectors, that is fine.

At a billion vectors, it is impossible. A billion 512-dimensional `float32` vectors is roughly 2 TB of RAM, and exact pairwise comparison is \(O(n^2)\).

The next technical step is `IVF-PQ`, which combines two ideas:

- **Product Quantization (PQ)** for memory
- **Inverted File Index (IVF)** for speed

Together, they trade a small amount of exactness for orders-of-magnitude gains in storage and query speed.

## Product Quantization Solves Memory

A 512-dimensional vector stored as `float32` takes:

```text
512 dimensions * 4 bytes = 2,048 bytes
```

At a billion vectors, that is about 2 TB just for the raw embeddings.

Product Quantization changes the representation. Instead of storing 512 floats, you split the vector into smaller sub-vectors. For example:

```text
512 dimensions -> 8 sub-vectors of 64 dimensions
```

For each sub-vector position, you learn a codebook of 256 representative centroids. Then each sub-vector is stored as one byte: "closest to codebook entry #37."

So a full vector becomes:

```text
8 sub-vectors * 1 byte = 8 bytes
```

That moves a billion vectors from roughly 2 TB to roughly 8 GB.

The trick is that the codebooks combine. Eight independent codebooks with 256 entries each can represent:

```text
256^8 ~= 18 quintillion combinations
```

So the storage is tiny, but the representational space is still huge.

## IVF Solves Speed

Product Quantization compresses vectors, but you still need to avoid searching everything.

That is where an Inverted File Index helps.

Before queries run, you cluster all vectors into partitions. For example:

```text
1 billion vectors -> 10,000 coarse clusters
```

Each cluster has a centroid. At query time, you find the nearest few centroids and only search vectors inside those partitions.

That means you skip most of the dataset.

The tuning knob is `nprobe`: how many partitions to search.

- low `nprobe`: faster, lower recall
- high `nprobe`: slower, higher recall

The tradeoff is clear. If a near-duplicate sits in a partition you did not probe, you may miss it. That is the "approximate" in approximate nearest neighbor search.

Graph-based methods like HNSW and Google's ScaNN are variations on the same deeper pattern: compress the representation, narrow the search space, or both.

My next step is to swap the flat FAISS index for `IVF-PQ`, then measure recall, speed, and memory across dataset sizes. The goal is to find the point where brute force stops being viable.

## 2. Data Quality as a Science, Not a Checklist

My current quality gates are rule-based:

- text must have more than 10 words
- captions must be non-empty
- images must not be corrupt
- audio and video must have valid duration

This catches broken data. It does not tell me whether the data is good.

There are three levels of maturity in data quality, and I have only built the first.

## Level 1: Rule-Based Filtering

This is implemented.

Rule-based filtering is cheap and binary. It catches corruption, missing values, invalid formats, and obviously bad rows.

It is necessary, but insufficient.

It cannot tell me that 90 percent of my image dataset is human faces and the model will never learn cars. It cannot tell me that one topic dominates the text corpus. It cannot tell me whether a dataset version is more diverse than the previous one.

## Level 2: Distributional Monitoring

Distributional monitoring looks at the shape of the whole corpus instead of judging rows one at a time.

The key insight is that embeddings turn "diversity" from a vague idea into measurable geometry. Vectors in semantic space form clusters.

- tight, dense clusters mean low diversity
- evenly spread points mean higher diversity
- one giant cluster means collapse

I am already closer to this than I realized. A FAISS IVF index clusters vectors into centroids. By counting how many vectors land in each cluster, I get a diversity histogram almost for free.

To collapse that histogram into one trackable metric, I can use Shannon entropy:

$$H = -\sum_{i=1}^{N} p_i \log_2(p_i)$$

where \(p_i\) is the fraction of vectors in cluster \(i\).

Maximum entropy means the data is spread evenly across clusters. Zero entropy means everything collapsed into one cluster.

To compare experiments with different cluster counts, I can normalize it:

$$H_{normalized} = \frac{H}{\log_2(N)}$$

That gives a 0-to-1 diversity score.

The histogram tells me where the imbalance is:

```text
cluster #7 is 40% portraits
```

Entropy tells me how much imbalance there is:

```text
v002 improved from 0.71 to 0.83
```

I need both. The histogram is actionable. The entropy score is comparable.

This metric can wire directly into the dataset version manifest:

```json
{
  "version": "multimodal-demo-v002",
  "diversity": {
    "text_entropy": 0.87,
    "text_largest_cluster_pct": 12.3,
    "clip_entropy": 0.83,
    "clip_largest_cluster_pct": 14.1
  }
}
```

Text and image diversity should be tracked separately because their embedding spaces are independent. Balanced text does not imply balanced images.

## Level 3: Model-Based Scoring

The next level is using learned models to judge quality.

This is what Netflix's curation framing points toward. Before training the final model, the data pipeline already needs models that score and annotate the data:

- aesthetic models for visual quality
- CLIP alignment scores for image-caption agreement
- audio quality models for noisy or clipped speech
- language and topic classifiers
- educational quality classifiers for text

FineWeb-Edu itself was built using classifier-based quality scoring. That is the level beyond simple rules.

The catch is that scorers are imperfect. An aesthetic model has its own biases. A quality classifier inherits its training distribution. A CLIP score can reward superficial caption-image alignment while missing deeper usefulness.

So the validators need validation:

- track scorer agreement
- compare model scores with human labels
- monitor for drift
- audit false positives and false negatives
- version the scoring models themselves

The data pipeline becomes full of models before you ever reach the training model. That is the deeper meaning behind the "models" pillar in data curation: you need a diversity of models just to curate.

## 3. Closing the Eval Feedback Loop

Dedup quality, distributional diversity, and model-based scoring are only useful if I can prove that one dataset version is better than another.

Right now, I can build dataset versions. I cannot yet prove improvement.

The missing piece is a frozen, version-pinned eval set: a small set of query probes with expected results that never changes between versions.

The loop should look like this:

```text
change the data
-> build a new dataset version
-> measure corpus diversity
-> run frozen retrieval probes
-> compare against the previous version
-> decide whether to keep the change
```

For retrieval, the eval set might contain:

- text queries with expected nearest documents
- image queries with expected caption or neighbor matches
- cross-modal examples, such as text-to-image retrieval
- hard negatives that should not appear near the top
- duplicate or near-duplicate probes

Run the same probes against `v001` and `v002`, compare hit rates, and the link between a data decision and retrieval quality becomes measurable rather than anecdotal.

Combined with diversity entropy tracked per version, this creates the feedback loop I actually want:

```text
data decision -> corpus shape -> retrieval quality -> keep or reject
```

Without that loop, curation is guesswork.

## The Honest Takeaway

At demo scale, Ray is overkill. My deduplication is brute force. My metrics validate correctness more than performance.

But the useful result is knowing which parts of the skeleton need to become measurable next:

- content-addressed storage
- stateful actors
- trust boundaries
- immutable version manifests
- diversity-tracked dataset evolution
- evaluation feedback loops

The next version should prove those pieces, not just include them.

I built the skeleton. Now I know where the hard engineering starts: measuring whether each data decision actually improves the dataset.

## New Terms

**Product Quantization (PQ):** A compression technique that chops vectors into sub-vectors and replaces each with a codebook index, reducing storage by orders of magnitude.

**IVF (Inverted File Index):** A partitioning technique that clusters vectors into groups and only searches the nearest groups at query time, trading some recall for speed.

**Shannon Entropy:** A metric for how evenly data is spread across clusters. Higher entropy means more even coverage.

**Normalized Entropy:** Entropy divided by its theoretical maximum, giving a 0-to-1 diversity score comparable across different cluster counts.
