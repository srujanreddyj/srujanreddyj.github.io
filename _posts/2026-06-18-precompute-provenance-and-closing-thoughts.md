---
layout: post
toc: true
title: "From Search Demo to Data Infrastructure"
categories: learnings
tags: [markdown, multimodal, lakehouse, precompute, provenance, observability, mlops]
---

# From Search Demo to Data Infrastructure

The previous post covered the eval feedback loop: the point where a dataset version stops being "new" and has to prove whether it is actually better.

This final post closes the remaining two components of the multimodal lakehouse pipeline:

```text
Component 11: Precompute vs On-the-Fly
Component 12: Provenance and Observability
```

These two pieces answer the last two questions I need before I can trust a dataset version downstream:

```text
What work should be baked into the dataset, and what should happen live?
Can I trace every sample, failure, cost, and decision that produced it?
```

For context, this closes the lakehouse series:

- [Serverless Multimodal Data Lakehouse]({% post_url 2026-06-01-multimodal-embedding-pipeline-lancedb %})
- [Multimodal Lakehouse Implementation Notes]({% post_url 2026-06-11-multimodal-lakehouse-implementation-notes %})
- [Ray Actors, Catalog Trust Boundaries, and Pipeline Battle Scars]({% post_url 2026-06-12-ray-actors-catalog-trust-boundary %})
- [What Comes Next for the Multimodal Lakehouse]({% post_url 2026-06-15-what-comes-next-multimodal-lakehouse %})
- [Training-Ready Multimodal Data: Shards and Loaders]({% post_url 2026-06-18-training-ready-multimodal-data-shards-loaders %})
- [Eval Feedback Loops for Multimodal Dataset Versions]({% post_url 2026-06-18-eval-feedback-loop-multimodal-lakehouse %})

## Component 11: Precompute vs On-the-Fly

By this point in the pipeline, the dataset is already versioned, filtered, deduplicated, searchable, materialized, and benchmarked:

```text
source connectors
-> CAS
-> Ray preprocessing
-> quality/dedup
-> embedding cache
-> LanceDB catalog
-> dataset version manifest
-> WebDataset shards
-> training loader
-> eval feedback loop
```

The next design question is subtle:

```text
Which transformations belong in the dataset,
and which transformations belong in the training loop?
```

That is the precompute vs on-the-fly boundary.

It sounds like an implementation detail. It is not. This boundary affects cost, reproducibility, training speed, model generalization, and debugging.

## Why the Boundary Exists

Not every transformation has the same purpose.

Some transformations are expensive, deterministic, and reused across many experiments:

```text
decode video
extract keyframes
compute CLIP embeddings
compute Whisper features
resize assets to a canonical format
quality-score records
deduplicate embeddings
```

These are good candidates for precompute.

Other transformations are intentionally random:

```text
random crop
color jitter
audio noise
text masking
mixup
cutmix
random frame sampling
```

These are better done on-the-fly during training.

The rule I like is:

```text
Precompute what makes the dataset reproducible.
Randomize what makes training robust.
```

Or, stated another way:

```text
If a transform defines the dataset, precompute it.
If a transform defines the training experience, keep it live.
```

## The Bad Extreme: Precompute Everything

One naive approach is to bake every transformation into the dataset:

```text
image -> resized image -> cropped image -> normalized tensor -> saved forever
```

That makes training fast because the loader has very little work left.

But it can make the dataset rigid.

If I precompute one crop of an image, every training run sees that same crop. If I crop on-the-fly, the model can see slightly different views across epochs.

The same idea applies across modalities:

- precomputing one image crop removes spatial variation
- precomputing one audio perturbation removes acoustic variation
- precomputing one text mask removes token-level variation
- precomputing one video frame sample removes temporal variation

So precomputing everything maximizes throughput, but it can freeze away useful training randomness.

## The Other Bad Extreme: Compute Everything Live

The opposite mistake is moving all preprocessing into the training loader.

For example:

```text
decode video
extract frames
run CLIP
run Whisper
quality score
deduplicate
augment
batch
```

That keeps the dataset flexible, but it makes the training loop responsible for expensive data engineering work.

The result is predictable: the GPU waits.

This is the same lesson from the sharding and loader post. A GPU can be expensive, available, and underused because the data path cannot feed it fast enough.

Computing everything live keeps the dataset flexible, but it risks turning the loader into the bottleneck.

## The Hybrid Boundary

The right architecture is hybrid.

In this project, the boundary looks like this:

| Transformation | Precompute? | Reason |
| --- | --- | --- |
| Content hash | Yes | Needed for dedup, caching, and reproducibility |
| Media extraction | Yes | Expensive and deterministic |
| Text/image/video/audio embeddings | Yes | Expensive GPU work reused across versions |
| Quality status | Yes | Needed for catalog filtering and versioning |
| ANN dedup decisions | Yes | Dataset-level decision, not per-epoch work |
| Dataset version manifest | Yes | Must be immutable and reproducible |
| WebDataset shards | Yes | Training layout should be materialized |
| Random crop | No | Useful stochastic augmentation |
| Noise injection | No | Should vary across epochs |
| Random masking | No | Useful for training diversity |
| Lightweight normalization | Usually live or precomputed | Depends on framework and model |

The important line is between dataset definition and training variation.

Precomputed artifacts should be part of the data contract. On-the-fly transforms should be part of the training config.

## How This Changes by Modality

The boundary is especially important in a multimodal pipeline because each modality has a different cost profile.

For text:

- token counts can be precomputed
- text embeddings can be precomputed
- quality scores can be precomputed
- random masking should stay live for language-model training

For images:

- decode validity checks can be precomputed
- CLIP embeddings can be precomputed
- canonical resizing can be precomputed if useful
- random crops and color jitter should usually stay live

For video:

- clip extraction should usually be precomputed
- keyframes should usually be precomputed
- full video decoding during training is expensive
- random temporal sampling may stay live if the objective benefits from it

For audio:

- silence detection can be precomputed
- transcripts or Whisper features can be precomputed
- noise augmentation can happen live
- transcript alignment should be versioned if used for retrieval

This is why multimodal data pipelines need explicit transform planning. A video transform can be orders of magnitude more expensive than a text transform.

## What This Project Has Today

The project already implements the foundation of this hybrid approach:

- CAS stores raw assets immutably.
- Ray preprocessing computes embeddings before training.
- Quality and dedup decisions happen before cataloging.
- LanceDB stores vectors and metadata together.
- Dataset versions pin item IDs and model choices.
- WebDataset shards materialize a version into a training layout.
- The loader benchmark checks whether that layout can be streamed efficiently.
- The `precompute_assets` stage exists as the place where deterministic training assets can be prepared.

The architecture separates:

```text
offline data preparation
from
online training-time consumption
```

That separation is the main win.

The training loader should not be responsible for rediscovering quality, recomputing embeddings, rerunning dedup, or rebuilding training assets. It should stream, decode, lightly augment, batch, and prefetch.

## The Next Upgrade: A Transform Registry

A stronger version of this component would add a formal transform registry.

Each transform would be described with metadata:

```text
name
version
input columns
output columns
deterministic: true/false
precompute: true/false
model dependency
config hash
```

Then a dataset manifest could record:

```yaml
transforms:
  resize_v001:
    deterministic: true
    precomputed: true
    config_hash: a31f...

  random_crop_v001:
    deterministic: false
    applied_in_loader: true
    config_hash: 91bd...
```

This matters because transformations are part of reproducibility.

If two model runs use the same dataset rows but different preprocessing, they are not really training on the same dataset.

A production-grade manifest should pin:

- dataset version
- model versions
- embedding versions
- quality thresholds
- dedup thresholds
- transform configs
- loader randomness seed

The dataset version is not just a list of rows. It is a list of rows plus the transformation contract used to produce training samples.

## Failure Modes

The precompute boundary has predictable failure modes.

Precomputing stochastic transforms reduces training diversity. Doing expensive deterministic transforms live slows training and starves the GPU. Failing to version transforms makes old training runs hard to reproduce.

Mixing embeddings from different model versions breaks search and dedup. Changing loader transforms silently makes model regressions hard to debug.

The boundary is not just about speed. It is about being able to explain what the model actually saw.

## Component 12: Provenance and Observability

The final component answers a different question:

```text
Can I explain where every training sample came from,
what happened to it,
and why it ended up in this dataset version?
```

That is provenance.

It also asks:

```text
Can I see whether the pipeline is healthy, slow, expensive, failing, or drifting?
```

That is observability.

Together, they turn a demo pipeline into something closer to real infrastructure.

## Why Provenance Matters

In small projects, it is tempting to treat data as anonymous rows.

In production, every row has a history.

For a single item, I should be able to answer:

```text
Where did it come from?
Which connector ingested it?
What was its original license?
What is its content hash?
Was it filtered?
Was it deduplicated?
Which model embedded it?
Which dataset versions include it?
Which shards contain it?
Was it used in a training run?
```

That chain is the item's lineage.

Without lineage, debugging becomes guesswork.

If a model behaves badly, I need to know whether the issue came from:

- bad source data
- wrong connector parsing
- corrupted media
- bad caption alignment
- duplicate records
- unsafe content
- wrong embedding model
- broken sharding
- loader skew
- license-restricted data

Provenance gives me a way to trace backward from model behavior to data decisions.

The simplest rule:

```text
If I cannot trace a sample, I cannot trust the dataset.
```

## Licensing Is Provenance

Licensing is not just paperwork. It changes what a dataset can be used for.

The source datasets in this project have different usage expectations:

```text
FineWeb-Edu
COCO
FineVideo
LibriSpeech
MSR-VTT-style datasets
```

Some data may be open for broad use. Some may be research-only. Some may require attribution. Some may not be appropriate for commercial training.

Each catalog row should carry license metadata so the system can answer:

```text
show all research-only items
exclude non-commercial sources
build a version using only permissive data
remove all items from source X
```

That last case is important.

A takedown request should become a new manifest excluding a source, not a full re-ingestion project.

That is the power of provenance plus versioning.

## What to Track Per Item

At minimum, each item should track:

| Field | Why it matters |
| --- | --- |
| `id` | Stable item identity |
| `source` | Original dataset or provider |
| `modality` | Text/image/video/audio |
| `content_hash` | CAS identity and dedup key |
| `content_path` | Where the raw asset lives |
| `license` | Usage rights |
| `connector_version` | How it was ingested |
| `quality_status` | Whether it passed filters |
| `quality_reason` | Why it failed or passed |
| `embedding_model` | Which model produced vectors |
| `embedding_version` | Prevents mixing incompatible vectors |
| `created_at` | Audit/debug timestamp |
| `dataset_versions` | Which versions include this item |

The current catalog already captures many of these ideas: source, modality, content hash, license, quality status, vectors, and metadata.

A production version would make the lineage fields more explicit and queryable.

## Observability: What to Measure

Provenance tells me what happened to a row.

Observability tells me what is happening to the system.

For this pipeline, useful observability metrics fall into a few groups.

## Ingestion Metrics

```text
rows scanned
rows accepted
rows skipped
skip reasons
download failures
decode failures
bytes written to CAS
duplicate hash count
```

These answer:

```text
Are my connectors healthy?
```

## Preprocessing Metrics

```text
batches processed
rows/sec
GPU utilization
model load time
inference time
batch size
OOM count
retry count
```

These answer:

```text
Are my Ray actors and GPUs doing useful work?
```

## Quality and Dedup Metrics

```text
quality pass rate
quality fail reasons
near duplicates removed
largest cluster percentage
normalized entropy
safety filter counts
```

These answer:

```text
Is the dataset getting cleaner or collapsing?
```

## Catalog and Versioning Metrics

```text
catalog row count
missing embeddings
missing assets
rows per modality
license distribution
version size
version diff from previous
```

These answer:

```text
Is the catalog trustworthy?
```

## Sharding and Loader Metrics

```text
number of shards
average shard size
shard size skew
items/sec
MB/sec
batch latency
worker imbalance
GPU idle time
```

These answer:

```text
Can training consume this dataset efficiently?
```

## Cost Metrics

```text
Modal GPU seconds
CPU seconds
memory GB-seconds
storage used
egress/download cost
cost per 1K records
cost per modality
```

These answer:

```text
What does it cost to build this dataset version?
```

Cost matters because data quality work can become expensive quietly. A useful pipeline should not only say that v002 is better. It should also say what v002 cost to produce.

## Failure Observability

Good observability is not only about success metrics. It should preserve failure reasons.

The battle scars from this project were all boundary failures:

```text
empty video manifest
audio decoder object shape changed
CLIP return shape changed
LanceDB rename failed on Modal Volume
text content treated as file path
```

A robust pipeline should report structured failure events:

```text
stage
modality
item_id
error type
error message
retryable or not
skip reason
```

This turns failures into searchable data.

Instead of reading logs manually, I should be able to ask:

```text
How many LibriSpeech rows failed because audio decoding changed?
How many video rows had no usable bytes?
How many images failed because files were corrupt?
```

That is the difference between logs and observability.

Logs tell me something happened. Observability lets me measure the pattern.

## Lineage Events

A stronger production version would emit structured lineage events for every stage:

```text
stage_name
input_artifacts
output_artifacts
row_count
duration
cost
code_version
config_hash
status
```

Then a single item could be traced end to end:

```text
FineVideo row
-> CAS hash
-> keyframes
-> CLIP embedding
-> quality pass
-> catalog row
-> dataset version
-> shard
-> loader benchmark
```

A production-grade version could use OpenLineage-style events, Prometheus metrics, Grafana dashboards, structured JSON logs, validation reports, dataset datasheets, model/data cards, and cost reports per run.

The specific tool is less important than the contract:

```text
every artifact should have lineage
```

## Provenance Makes Versioning Auditable

Provenance and versioning are tightly linked.

A dataset version should not only say:

```text
these item IDs are included
```

It should also say:

```text
where those items came from
which licenses they carry
which transforms were applied
which models embedded them
which filters accepted them
which metrics describe them
```

That turns a manifest from a list into an audit record.

A stronger manifest might include:

```text
version name
created time
source counts
license counts
quality thresholds
embedding model versions
transform config hashes
diversity metrics
eval metrics
shard paths
```

Then the dataset version becomes reproducible and explainable.

## What This Project Has Today

This project implements several provenance and observability foundations:

- source connectors preserve source identity
- CAS gives every raw asset a content hash
- the catalog stores source, modality, content hash, license, quality status, metadata, and vectors
- dataset manifests pin item IDs and model choices
- sharding materializes a version into a physical training layout
- loader benchmarks record throughput
- Modal runs record runtime and cost observations
- architecture notes document failures and tradeoffs
- battle scars act as human-readable operational history

That is more than a typical search demo needs.

The honest limitation is that observability is mostly file, log, and report based today. It is not a full dashboard.

That is fine for the scale of this project. The production extension would export structured events and metrics to a dashboard.

## Closing Thoughts: From Search Demo to Data Infrastructure

I started this project thinking I was building a multimodal search demo.

The first version was simple:

```text
text/images -> embeddings -> LanceDB -> search endpoint
```

But the deeper I went, the more I realized that embedding search is only one small part of the real problem.

Production multimodal data infrastructure is not just about generating vectors. It is about building a system where data can be ingested, traced, filtered, deduplicated, versioned, searched, materialized, benchmarked, evaluated, and trusted.

That is why the project grew into a 12-component pipeline:

```text
source connectors
-> content-addressed storage
-> Ray preprocessing
-> quality/dedup
-> embedding cache
-> metadata catalog
-> dataset versioning
-> WebDataset sharding
-> training loader
-> eval feedback loop
-> precompute/on-the-fly boundary
-> provenance and observability
```

Each component taught me a different lesson.

The source connectors taught me that public datasets are not stable APIs. The CAS taught me that reproducibility starts with immutable content hashes. Ray taught me that distributed inference is mostly about keeping models warm and GPUs fed. The catalog taught me that trust boundaries matter. Versioning taught me that a dataset should be an artifact, not a folder.

Sharding and loaders taught me that training performance depends on physical layout. The eval loop taught me that a dataset version is not better because it is bigger. It is better only if it improves measured behavior. Provenance taught me that if I cannot trace a sample, I cannot trust the dataset.

This is still a demo-scale system. It does not process full web-scale datasets. It does not have production auth, dashboards, autoscaling policies, or enterprise governance. Some pieces are intentionally simple.

But the architecture follows the same pattern I saw in large-scale multimodal data systems:

- separate raw storage from metadata
- separate query formats from training formats
- precompute expensive deterministic work
- preserve lineage
- close the loop with evaluation

The biggest lesson was that ML data engineering is not just preprocessing.

It is infrastructure for making data reusable, measurable, and trustworthy.

If I had to summarize the project in one sentence:

```text
I built a demo-scale multimodal lakehouse pipeline to understand how raw data
becomes a trusted, versioned, training-ready dataset.
```

And if I had to summarize what I learned:

```text
The hard part is not embedding the data.
The hard part is knowing which data I embedded,
why it was kept,
how it changed,
whether it improved the system,
and whether I can reproduce it later.
```

That is the difference between a notebook demo and data infrastructure.

## Running Glossary

**Precompute:** Running deterministic, reusable transformations ahead of training and storing the result.

**On-the-Fly Transform:** A transformation applied live during training, often because randomness improves generalization.

**Transform Registry:** A versioned record of transformations, configs, inputs, outputs, and whether each transform is deterministic.

**Transformation Contract:** The set of preprocessing and augmentation rules that define how raw rows become training samples.

**Provenance:** The lineage of a data item, including where it came from, how it was transformed, and which versions include it.

**Observability:** Metrics, logs, traces, and reports that reveal pipeline health, failures, throughput, data quality, and cost.

**Lineage Event:** A structured record emitted by a pipeline stage describing inputs, outputs, row counts, duration, config, code version, and status.

**Dataset Datasheet:** Documentation that describes a dataset's sources, composition, intended use, limitations, licensing, metrics, and known risks.
