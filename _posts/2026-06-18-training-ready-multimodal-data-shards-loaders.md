---
layout: post
toc: true
title: "Training-Ready Multimodal Data: Shards and Loaders"
categories: learnings
tags: [markdown, multimodal, lakehouse, webdataset, training-loader, gpu, data-engineering, mlops]
---

# Training-Ready Multimodal Data: Shards and Loaders

The last post was about what comes next for the multimodal lakehouse: better deduplication, measurable data quality, and an evaluation loop that can prove whether one dataset version is better than another.

That roadmap only matters if a versioned dataset can make it all the way into a training run. This post steps back into the pipeline at the exact point where a reproducible dataset has to become useful to a model.

By this stage, the system has already done a lot of work:

```text
connectors -> CAS -> Ray preprocessing -> quality/dedup
-> catalog -> dataset version manifest
```

The dataset version manifest is the reproducibility layer. It says:

```text
These exact item IDs belong to multimodal-demo-v001.
```

That is enough to recreate the dataset selection. It is not enough to train efficiently.

A manifest is a list of references. A training job needs a fast stream of actual samples. That is the boundary this post covers: turning a versioned, queryable dataset into a physical layout that can keep a training loop fed.

For context, this follows the earlier lakehouse notes:

- [Serverless Multimodal Data Lakehouse]({% post_url 2026-06-01-multimodal-embedding-pipeline-lancedb %})
- [Multimodal Lakehouse Implementation Notes]({% post_url 2026-06-11-multimodal-lakehouse-implementation-notes %})
- [Ray Actors, Catalog Trust Boundaries, and Pipeline Battle Scars]({% post_url 2026-06-12-ray-actors-catalog-trust-boundary %})
- [What Comes Next for the Multimodal Lakehouse]({% post_url 2026-06-15-what-comes-next-multimodal-lakehouse %})

## The Problem: A Dataset Version Is Not a Training Layout

The version manifest decides what belongs in the dataset:

```text
dataset_versions/multimodal-demo-v001.json
```

But training has a different access pattern than catalog search.

Catalog workload:

```text
Find pass-quality COCO images with captions about dogs.
```

Training workload:

```text
Give me the next 10 million samples as fast as possible.
```

Those are not the same job.

The LanceDB catalog is good at search, filtering, provenance lookup, vector queries, and dataset construction. It is the queryable truth of the system. But it is not the format I want the training loop to hit for every batch.

Training wants large sequential reads, predictable sample structure, and enough throughput that the GPU does not wait on storage.

That is where Components 8 and 9 fit:

```text
LanceDB catalog -> dataset version manifest -> WebDataset shards
-> training loader -> batches -> GPU training loop
```

The catalog and manifest answer "what data is this?" The shards and loader answer "can training consume it quickly?"

## Component 8: WebDataset Sharding

The naive way to store training samples is as many separate files:

```text
image_000001.jpg
image_000001.json
image_000002.jpg
image_000002.json
...
```

That works at tiny scale. It becomes painful as soon as the dataset grows.

The problem is not only storage size. The problem is the I/O pattern. Training wants to stream samples continuously. If the GPU waits while the filesystem opens thousands or millions of tiny files, throughput collapses.

Small-file training creates several kinds of overhead:

- too many metadata lookups
- too many open and close calls
- poor sequential read performance
- worse cloud object store behavior
- harder distributed shuffling
- easier GPU starvation

WebDataset-style sharding solves this by packing many samples into tar files:

```text
dataset_versions/multimodal-demo-v001.json
        |
        v
shards/multimodal-demo-v001/shard-000000.tar
shards/multimodal-demo-v001/shard-000001.tar
shards/multimodal-demo-v001/shard-000002.tar
```

Instead of opening 50,000 tiny files, the loader can open 50 larger files and stream through them.

The basic trade is:

```text
many tiny random reads -> fewer large sequential reads
```

That is a boring-looking change with a large systems impact.

## What Goes Inside a Shard

WebDataset is not just "put files in tar." It is a convention for storing training samples inside tar files.

A sample usually consists of multiple entries with the same key:

```text
sample_000001.jpg
sample_000001.json

sample_000002.jpg
sample_000002.json
```

Inside a multimodal shard, that might look like:

```text
shard-000000.tar
  coco_522418.jpg
  coco_522418.json
  fineweb_000123.txt
  fineweb_000123.json
  audio_000045.wav
  audio_000045.json
```

The shared base name ties the raw asset to its metadata.

For an image sample:

```text
coco_522418.jpg
coco_522418.json
```

The `.jpg` is the asset. The `.json` can hold fields like:

```text
caption
source
license
content_hash
modality
quality_status
embedding references
```

For text, there may not be a separate binary asset. The text can be stored as a `.txt` entry or embedded directly in the metadata entry. The important part is that each training sample has a stable key and a predictable shape.

That predictable shape matters because the loader should not need to rediscover what a sample is at training time.

## Sharding Is Materialization, Not Filtering

The sharding stage should not decide what belongs in the dataset.

That decision has already happened upstream:

```text
quality gates -> catalog -> dataset version manifest
```

The manifest says:

```text
item_ids = [...]
```

The shard writer says:

```text
for each item_id:
    fetch catalog metadata
    fetch CAS asset if needed
    write sample into tar shard
```

That makes sharding a materialization step, not a curation step.

This separation is important. If the shard writer starts quietly filtering rows, then the manifest no longer fully describes the dataset. If it starts querying new rows from the catalog, then the dataset version is no longer frozen.

The clean contract is:

```text
dataset versioning decides what belongs in the dataset
WebDataset sharding decides how that version is physically laid out
```

That is the same trust-boundary lesson from the earlier post, applied to training data layout. Every downstream stage should consume the approved output of the previous stage, not reach around it for convenience.

## Choosing Shard Size

Shard size is a tradeoff.

If shards are too small:

```text
too many files
too much per-shard overhead
small-file behavior starts coming back
```

If shards are too large:

```text
harder to shuffle
harder to retry
slower to resume after a failure
more painful worker imbalance
```

For a demo, fixed-count shards are easy to explain:

```text
100 to 1,000 samples per shard
```

For production, shard size is usually more naturally expressed in bytes:

```text
128 MB
512 MB
1 GB
```

The right target depends on sample size, modality mix, network bandwidth, loader parallelism, distributed training setup, and failure recovery needs.

This matters more for multimodal data than for plain text. Text samples are usually small and somewhat uniform. Multimodal samples vary wildly:

```text
text document: a few KB
image: hundreds of KB
audio clip: MBs
video clip: many MBs
```

Fixed-count sharding can create skew. One shard might contain mostly short text and finish quickly. Another might contain long audio or video samples and become the straggler.

So the production upgrade is size-aware sharding: target roughly equal bytes per shard rather than equal record counts.

For this project, fixed-count shards are fine because they make the boundary visible. The next version would make the boundary more robust by accounting for sample size.

## Component 9: The Training Loader

Once the dataset version has been materialized into shards, the next question is whether a training job can consume those shards fast enough.

That is the job of the training loader.

```text
WebDataset shards -> training loader -> batches -> GPU training loop
```

The loader sits at the boundary between data infrastructure and model training. It does not decide what data belongs in the dataset. It reads the versioned shards and turns them into batches.

A loader usually does this sequence:

```text
1. choose which shards to read
2. stream samples from shards
3. decode raw bytes
4. apply lightweight transforms
5. shuffle
6. batch
7. prefetch
8. yield to the training loop
```

The success condition is simple:

```text
the loader delivers batches faster than the GPU consumes them
```

If the loader is slow, the GPU waits. The model code can be correct, the GPU can be expensive, and the job can still underperform because the data path cannot keep up.

This is why the loader is a separate component instead of a detail hidden inside training code.

## Streaming and Prefetching

The loader should exploit the layout created by the sharding stage.

Bad pattern:

```text
open image_1.jpg
open image_1.json
open image_2.jpg
open image_2.json
...
```

Better pattern:

```text
open shard-000000.tar
read sample 1
read sample 2
read sample 3
...
```

That sequential stream is only half the story. The loader should also work ahead of the GPU.

Without prefetching:

```text
load batch 1 -> train batch 1 -> load batch 2 -> train batch 2
```

The GPU waits during every load.

With prefetching:

```text
GPU trains batch 1 while CPU prepares batch 2
GPU trains batch 2 while CPU prepares batch 3
```

The point is to overlap storage, decoding, and CPU transforms with GPU compute.

For this pipeline, heavy deterministic preprocessing should already have happened upstream:

```text
Ray preprocessing -> embeddings/keyframes/features
```

The loader should not re-run CLIP embeddings, re-extract video keyframes, query LanceDB for every row, or redo global deduplication. Those decisions belong before materialization.

Good loader work is narrower:

- decode already-materialized assets
- parse metadata
- apply cheap random augmentations
- normalize simple inputs
- form tensors
- batch records

That boundary keeps training fast and keeps preprocessing decisions reproducible.

## Shuffling Without Losing Reproducibility

Training usually needs shuffled data. A model should not see all examples from one source, topic, or modality in a fixed order.

But shuffling streaming data is not the same as shuffling a local array.

For terabytes of shards, the loader cannot read the whole dataset into memory and call `shuffle`.

Instead, the loader shuffles at multiple levels:

```text
shuffle shard order
shuffle samples within a buffer
shuffle batches
```

Example:

```text
epoch 1 shard order:
  shard-003, shard-000, shard-005, ...

epoch 2 shard order:
  shard-001, shard-004, shard-002, ...
```

Inside each stream, the loader can keep a shuffle buffer:

```text
read 10,000 samples -> randomly emit from buffer
```

This gives approximate randomness without requiring the whole dataset in memory.

The catch is that randomness must still be debuggable. If a model improves or regresses, I want to know whether the change came from the dataset version, the training code, the model config, or just a different data order.

So the loader should use deterministic seeds:

```text
seed = hash(dataset_version + epoch + worker_id)
```

That gives a useful contract:

- same version plus same epoch gives the same order
- different epochs can get different orders
- different workers get different shard slices

The loader should be random enough for training and deterministic enough for debugging.

## Distributed Workers Need Different Data

In distributed training, multiple workers train at the same time:

```text
worker 0 -> GPU 0
worker 1 -> GPU 1
worker 2 -> GPU 2
worker 3 -> GPU 3
```

If every worker reads the same shard, the system wastes compute by training on duplicate samples.

The loader needs to know:

```text
world_size = total number of workers
rank = this worker's ID
```

Then it can assign shards by worker:

```text
worker 0 reads shards 0, 4, 8
worker 1 reads shards 1, 5, 9
worker 2 reads shards 2, 6, 10
worker 3 reads shards 3, 7, 11
```

This matters for DDP, FSDP, DeepSpeed, Ray Train, and any other setup where multiple workers consume the same dataset version.

The key is that distributed loading is not only about parallelism. It is about avoiding accidental duplication while preserving reproducibility.

## Resume State and Loader Metrics

Long training runs fail. A reliable loader should be able to resume close to where it stopped instead of restarting an entire epoch.

Conceptually, a loader checkpoint needs enough state to reconstruct progress:

```text
version: multimodal-demo-v001
epoch: 3
worker_rank: 2
current_shard: shard-000147.tar
sample_offset: 812
shuffle_seed: 92817
```

This matters more at production scale than in my current demo, but the design point is useful: the loader is part of training infrastructure, not just a Python iterator.

It also needs its own metrics.

Useful loader metrics include:

```text
items/sec
MB/sec
batch latency
time waiting on I/O
time waiting on decode
GPU idle time
```

The benchmark question is:

```text
Can this dataset version produce samples faster than the model consumes them?
```

If the model trains at 2,000 samples per second but the loader delivers 500, the bottleneck is not the model. It is the data path.

That is why the project has a loader benchmark stage. It closes the loop between physical data layout and training performance:

```text
dataset version -> tar shards -> streaming loader -> measured throughput
```

## Failure Modes

The shard and loader boundary has its own failure modes.

Too-small shards recreate the small-file problem. Too-large shards make retry, resume, and shuffling painful. Fixed-count shards can create multimodal skew when one worker gets video-heavy data and another gets text-heavy data.

Bad shuffling can make workers see duplicate examples or make experiments hard to reproduce. Slow decoding can starve the GPU even when storage is fast. Missing observability can make the model look slow when the real bottleneck is the loader.

The important lesson is that training performance depends on the whole path:

```text
version selection -> physical layout -> streaming loader -> GPU utilization
```

The model is only one part of that system.

## The Takeaway

The catalog makes the dataset searchable. The manifest makes it reproducible. Shards make it streamable. The loader makes it trainable.

That distinction is the point of Components 8 and 9.

A dataset is not training-ready just because it exists. It is training-ready when a loader can deliver batches faster than the GPU consumes them, while preserving the version, shuffle order, worker assignment, and resume state needed to debug the run later.

For this project, the current implementation proves the architecture shape:

```text
LanceDB catalog = queryable truth
dataset manifest = reproducible selection
WebDataset shards = high-throughput training layout
training loader = continuous batch stream
```

The next production upgrades are clear: size-aware shard construction, better loader metrics, deterministic distributed shuffling, and stronger mid-epoch resume support.

Those are the pieces that turn a multimodal lakehouse from "I can find data" into "I can train on this version reliably."

## Running Glossary

**WebDataset:** A convention for storing training samples in tar shards, usually with related sample files sharing the same base key.

**Shard:** A larger file that packs many training samples together so loaders can stream data sequentially instead of opening many tiny files.

**Materialization:** Turning a logical dataset version into physical training artifacts without changing which records belong to the version.

**Training Loader:** The component that reads shards, decodes samples, shuffles, batches, prefetches, and yields data to the training loop.

**Prefetching:** Preparing future batches while the GPU is working on the current batch, hiding data-loading latency behind compute.

**Shuffle Buffer:** A bounded in-memory buffer used to approximate random ordering while streaming data that is too large to shuffle all at once.

**Worker Rank:** The ID of a distributed training worker, used to assign each worker a different slice of shards.
