---
layout: post
toc: true
title: "Serverless Multimodal Data Lakehouse"
categories: learnings
tags: [markdown, multimodal, embeddings, lancedb, ray, machine-learning, data-engineering, mlops]
---

# Serverless Multimodal Data Lakehouse

Every machine learning tutorial shows the same pattern: load a dataset, preprocess it in a notebook, embed it, train a model. It looks simple. It works on 1,000 samples. It fails on 10 million.

The gap between "works in a notebook" and "works in production" is where most ML projects die. I have spent the last few months building that bridge: a 12-component multimodal training data pipeline that handles text, images, video, and audio at scale. This post is about what I learned crossing that gap.

## What "Production Pattern" Actually Means

Before I describe what I built, here is what Netflix and Anyscale taught me about the shape of real data infrastructure:

- **Curation is a first-class pillar, not preprocessing.** The data you keep matters more than how you transform it.
- **Storage and streaming must be disaggregated.** Content-addressed blobs give durability. Ephemeral shards give throughput.
- **Scaling is not linear.** Ray Data `map_batches` has knobs most tutorials skip: memory limits, actor pools, batch sizes, and concurrency. Getting them wrong means OOMs or 10x slower pipelines.
- **Boundaries are where bugs live.** Every assumption about "this will be a dict" or "this path exists" breaks at scale.

I built this pipeline to learn these lessons the hard way. Let me show you the architecture, then the battle scars.

## The Pipeline I Built

The goal was to turn raw multimodal data into model-ready features that could be searched, filtered, joined, and reused across training jobs. I wanted the pipeline to support text, images, video, and audio without treating each modality as a separate one-off project.

![Horizontal architecture diagram for the serverless multimodal data lakehouse](https://raw.githubusercontent.com/srujanreddyj/distributed-embedding-search-lakehouse/main/docs/assets/horizontal_excalidraw.png)

_The high-level pipeline: source connectors, content-addressed storage, distributed preprocessing, embedding, cataloging, versioning, and training-ready outputs._

At a high level, the system has twelve components:

1. **Dataset registry** for tracking datasets, sources, versions, and schemas.
2. **Raw asset ingestion** for pulling files from local storage, object storage, or external sources.
3. **Content-addressed blob storage** so assets can be deduplicated and referenced reliably.
4. **Metadata extraction** for dimensions, duration, MIME type, language, timestamps, and source information.
5. **Validation and quality gates** to reject corrupt, missing, or unsupported samples early.
6. **Curation rules** for filtering low-value data before expensive embedding jobs.
7. **Ray Data processing** for distributed batch transforms.
8. **Modality-specific embedding workers** for text, image, video, and audio models.
9. **Feature normalization** to make vectors and metadata consistent across modalities.
10. **LanceDB storage** for serving embeddings and structured metadata together.
11. **Feature retrieval APIs** for downstream model training and evaluation.
12. **Monitoring and lineage** for understanding what changed, what failed, and which data created which feature set.

The important design decision was separating storage durability from processing throughput. The original media assets are stored as content-addressed blobs. The processing layer creates temporary batches, shards, and intermediate artifacts only when needed. The embedding store then becomes a queryable feature layer rather than a dumping ground for every file transformation.

## Why LanceDB

I used LanceDB because I wanted embeddings and metadata to live together. For machine learning feature work, vector search alone is not enough. I usually need to ask questions like:

- Find image embeddings similar to this example, but only from a specific dataset version.
- Retrieve text and audio features for samples that passed a quality rule.
- Join embeddings back to labels, source metadata, and curation decisions.
- Serve features quickly enough that training code does not need to rebuild them.

LanceDB gave me a practical way to store vectors with structured fields and query them as part of the same workflow. That matters because multimodal training data is never just an embedding. It is an embedding plus source path, modality, model name, model version, preprocessing config, dataset split, label, quality score, and lineage.

The lesson for me was simple: embeddings are not the product. Reusable, traceable features are the product.

## Curation Before Embedding

The most expensive mistake is embedding everything.

In a notebook, it feels natural to load the dataset and run the model across every row. At production scale, this is backwards. Bad data should be removed before it touches the expensive part of the system.

For text, this meant removing empty strings, boilerplate, repeated examples, unsupported languages, and records with broken metadata. For images, it meant checking dimensions, decode failures, near-duplicates, and low-information samples. For video and audio, it meant validating duration, container metadata, sample rate, and extraction boundaries.

This changed how I thought about preprocessing. Preprocessing is not just transformation. It is an investment decision. Every sample that survives curation is a sample I am agreeing to spend compute, storage, and training attention on.

## Ray Data Lessons

Ray Data made it possible to think in batches instead of single examples, but it also made me respect the operational details that tutorials often skip.

The main lessons:

- **Batch size is a systems parameter, not just a model parameter.** Too small and the GPU is underused. Too large and memory spikes.
- **Actor pools need to match the model lifecycle.** Loading a model per batch is slow. Keeping too many model actors alive can exhaust memory.
- **`map_batches` boundaries need strict schemas.** Returning slightly different shapes from different workers creates painful downstream bugs.
- **Object references hide memory pressure until they do not.** Intermediate results need to be consumed, written, or released deliberately.
- **CPU and GPU stages should be separated.** Decoding, validation, and metadata work should not compete with embedding inference.

The biggest mindset shift was treating Ray as a distributed execution engine, not magic. It gives you the tools to parallelize work, but it does not remove the need to reason about memory, serialization, model loading, and backpressure.

## Multimodal Makes Boundaries Harder

Text pipelines are forgiving compared with multimodal pipelines. Text is small, easy to serialize, and usually fails loudly. Images, video, and audio fail in more interesting ways.

Some examples I ran into:

- A file path exists, but the file cannot be decoded.
- A video has metadata, but frame extraction fails halfway through.
- An image opens locally, but breaks inside a worker because the dependency stack is different.
- A sample has a label, but the asset hash points to a missing blob.
- A batch contains a mix of valid and invalid records, so one bad item can poison a whole worker call.
- A model returns embeddings with a different shape because the input path took a different preprocessing branch.

This is where I learned to make boundaries explicit. Every component should accept and return predictable records. Every failed sample should become a structured failure event, not a mystery exception buried in a worker log.

## Serving Features for Machine Learning

Once embeddings are stored in LanceDB, the next step is serving them as features for training and evaluation.

The feature layer needs to support three workflows:

1. **Similarity retrieval** for finding nearest neighbors, duplicates, and hard negatives.
2. **Dataset construction** for joining embeddings with labels, splits, and curation metadata.
3. **Training-time reuse** so downstream jobs can load feature tables instead of recomputing embeddings.

This is where the pipeline started to feel useful. Instead of every experiment beginning with "run the embedding notebook again," experiments could start from a versioned feature table. That made it easier to compare model runs, debug dataset changes, and reuse expensive computation.

It also made one problem very clear: feature stores are only useful when lineage is boringly reliable. If I cannot answer which model created an embedding, which preprocessing config was used, and which dataset version it came from, then the feature is not production-ready.

## Battle Scars

The bugs that taught me the most were not glamorous model bugs. They were boundary bugs:

- Assuming every batch item had the same keys.
- Assuming metadata extraction would always return a valid MIME type.
- Assuming failed downloads would be rare enough to ignore.
- Assuming an embedding model would always return the same vector shape.
- Assuming local paths and distributed worker paths meant the same thing.
- Assuming a downstream training job would know which feature version it was reading.

Each assumption became a contract. Each contract became a schema, validation rule, or lineage field.

That is probably the most practical lesson I learned: production ML data pipelines are mostly contract management. Models matter, but the system survives because data contracts are explicit.

## What I Would Do Differently

If I rebuilt the pipeline from scratch, I would make three changes earlier:

- **Define schemas before writing processing code.** It is much easier to debug distributed jobs when records have a clear shape.
- **Track lineage from day one.** Retrofitting lineage after features already exist is painful.
- **Build failure datasets.** Failed samples are not just errors; they are the best source of future validation rules.

I would also invest earlier in small local integration tests that run one or two samples through the full path: ingestion, validation, embedding, LanceDB write, and feature retrieval. Unit tests help, but the hardest bugs appeared between components.

## Final Takeaway

The main thing I learned is that multimodal embedding infrastructure is not about running a model over files. It is about building a reliable feature production system.

The model creates vectors. The pipeline creates trust.

That trust comes from curation, explicit schemas, durable storage, distributed execution, queryable feature storage, and lineage. Once those pieces are in place, embeddings become more than one-off experiment artifacts. They become reusable training data infrastructure.
