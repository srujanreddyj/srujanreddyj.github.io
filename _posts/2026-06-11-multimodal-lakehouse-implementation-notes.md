---
layout: post
toc: true
title: "Multimodal Lakehouse Implementation Notes"
categories: learnings
tags: [markdown, multimodal, lakehouse, embeddings, lancedb, ray, modal, deduplication, mlops]
---

# Multimodal Lakehouse Implementation Notes

In the first version of this project, I wrote about the gap between a notebook embedding workflow and a production-shaped multimodal data pipeline. These notes go one layer deeper: what I built, why I used four modalities, where the architecture came from, and how the deduplication and versioning pieces map to the patterns used in larger training data systems.

## What I Built

The system ingests four modalities:

- **Text:** FineWeb-Edu
- **Images:** COCO Captions
- **Video:** FineVideo
- **Audio:** LibriSpeech

Those datasets flow through a 12-stage pipeline:

```text
Source Connectors -> Content-Addressed Store -> Ray Preprocessing -> Quality/Dedup
-> Embedding Service -> Metadata Catalog -> Dataset Versioning -> WebDataset Shards
-> Training Loader -> Eval Feedback -> Precompute Decisions -> Provenance
```

Each stage has one job and one trust contract with the next stage.

The connector outputs a uniform schema. The content-addressed store saves blobs by SHA256. Ray actors embed batches with models loaded once. Quality gates write soft metadata instead of hard-deleting records. The catalog is a single LanceDB table across all modalities. A dataset version is a JSON manifest of content hashes, not a copied folder of terabytes.

The whole thing runs on Modal with ephemeral L4 GPUs. At demo scale, it processes roughly 10,000 records for about $0.15 in GPU cost. The architecture does not change as the data grows. What changes are the limits, actor counts, shard sizes, and GPU tiers.

## Why Four Modalities?

I started text-only.

A text embedding pipeline with 5,000 short documents ran comfortably on my laptop in seconds. Ray was overkill. Modal was overkill. The architecture could not justify itself.

Adding images changed that. CLIP preprocessing is heavier, GPU execution matters, and multimodal retrieval starts to look like a real lakehouse pattern. But two modalities still felt like a search demo.

Video and audio pushed the system into infrastructure territory:

- ffmpeg keyframe extraction
- Whisper encoder projections
- variable-length batches
- decoder library version drift
- modality-specific failure modes
- different quality rules per media type

Four modalities forced every abstraction to be honest. If a schema only worked for text, it broke. If a storage path assumed images, video exposed it. If an embedding API assumed fixed-size inputs, audio pushed back. That was the point of the project.

## The Inspiration: Netflix's Curation Pillars

The spark for this project came from a Netflix data engineering talk on curating large datasets for generative models. The framing that stuck with me was that multimodal data curation needs three pillars.

**Models.** You need a diverse set of models just to understand, annotate, and score raw data: vision models, text embedders, audio encoders, speech models, and quality classifiers.

**Batch inference.** You need a way to run those models across millions of rows efficiently. The lesson I took from Anyscale's disaggregated streaming architecture is that CPU preprocessing and GPU inference should be separated. Expensive GPUs should not sit idle while CPUs decode media.

**Storage.** You need a lakehouse-style format that can grow in two directions: more rows and more feature columns. New embeddings, quality scores, captions, labels, and model outputs should not require copying the full dataset every time.

I wanted to see what it actually took to build those pillars from scratch.

## From Whiteboard to Working Code

It is easy to draw boxes on a whiteboard. The hard part is turning those boxes into contracts.

The theoretical architecture became real only after I made a few implementation decisions:

- raw assets are immutable blobs
- dataset versions are manifests
- quality filtering is soft metadata
- deduplication happens in stages
- embeddings and metadata live in one catalog
- training shards are generated artifacts, not the source of truth

The rest of this post focuses on the two pieces that taught me the most: content-addressed versioning and deduplication.

## Deep Dive 1: Content-Addressed Storage and Versioning

In a naive pipeline, creating a new dataset version or subset means physically copying gigabytes or terabytes of files into a new folder. I wanted to avoid that completely.

I implemented a content-addressed store where raw assets are saved by SHA256 hash in a two-level prefix layout:

```text
ab/cd/abcd1234...jpg
```

This gives exact deduplication for free across all sources. If two sources contain the exact same text snippet, image, audio clip, or media file, it is stored once.

Because of the content-addressed store, a dataset version is not a folder full of copied data. It is an immutable JSON manifest. The manifest records total items, model configurations, source metadata, and a list of content hashes.

That makes the versioning system feel like Git for data:

- Branching to test a new training mix costs zero bytes of media storage.
- Rolling back to a previous dataset version is instant.
- Training jobs read stable manifests instead of mutable folders.
- The actual media bytes are never copied, only referenced.

## How the Industry Solves This

This Git-for-data concept shows up across modern data engineering tools, but each tool approaches it differently.

| Approach | Pattern | Tradeoff |
| --- | --- | --- |
| DVC | Git tracks metadata and pointer files; large blobs live in object storage. | Great for ML experiments, but can feel bolted onto the pipeline. |
| LakeFS / Pachyderm | Git-like branching and committing over object storage. | Powerful, but adds infrastructure and operational surface area. |
| Apache Iceberg / Delta Lake / Lance | Snapshotting and time travel for structured or semi-structured tables. | Excellent for tables, less direct for raw unstructured media before embedding. |

For this portfolio project, I built the primitive myself for three reasons.

First, I wanted to demonstrate the underlying architecture instead of hiding it inside a platform. Second, I did not want to deploy a LakeFS server or Pachyderm cluster for a demo-scale system. Third, the custom manifest integrates directly with the rest of the pipeline: LanceDB catalog queries, WebDataset shard generation, and provenance tracking all use the same hash-based identity.

The point is not that custom CAS is always better. The point is that immutable blobs plus pointer manifests are the core idea. Whether you get that from a platform or implement it directly depends on the project.

## Important Sidebar: Deduplication

While working on this pipeline, I also looked at deduplication strategies from modern LLM and multimodal training pipelines, including Microsoft's Phi-style data reports. The structural pattern is familiar: exact dedup first, then cheaper fuzzy methods, then embedding-based semantic dedup, with provenance kept throughout.

Here is how those ideas map to this project:

| Production strategy | Project equivalent |
| --- | --- |
| Exact hash dedup | SHA256 through the content-addressed store |
| Semantic or embedding dedup | FAISS approximate nearest neighbor search over embedding vectors |
| Soft filtering with metadata | Quality gates record `quality_status` and `quality_reason` instead of deleting records |
| Per-source licensing and provenance | License and source fields live in the catalog |
| Source-specific heuristics | Text, image, video, and audio each have modality-specific quality checks |

The honest framing is this:

My pipeline implements the same structural pattern: exact dedup, embedding-based near-dedup, rule-based quality gates, soft filtering, and provenance tracking. At production scale, I would add MinHash for cheaper fuzzy text dedup before embeddings, learned quality classifiers instead of binary rules, and cross-dataset dedup with priority ordering. Those are extensions of the same stages, not a new architecture.

## What This Project Does Not Yet Do

The project is intentionally smaller than a full industrial curation stack. Some production systems add:

- **MinHash/LSH fuzzy dedup** for token-level text similarity before embedding.
- **Boilerplate removal and templated page detection** for raw HTML crawls.
- **Learned quality classifiers** that bucket data into quality tiers.
- **LLM-based filtering or judging** for ambiguous high-value examples.
- **Cross-dataset dedup with global drop order** so higher-priority sources win conflicts.
- **Data mixture optimization** across topics, quality tiers, languages, and education levels.

The key is that these would not require a new pipeline. They would fit into the existing quality, deduplication, catalog, and versioning stages.

## Per-Modality Deduplication Landscape

Different modalities need different deduplication tools. Exact hashing is universal, but near-duplicate detection changes quickly once you move beyond text.

| Tier | Text | Image | Video | Audio |
| --- | --- | --- | --- | --- |
| Exact | SHA256 / MD5 | File hash | File hash | File hash |
| Near-exact | MinHash/LSH | pHash / dHash | Keyframe perceptual hash | Audio fingerprinting |
| Semantic | Embedding clusters / SemDeDup | CLIP embeddings + clustering | CLIP on keyframes + pooling | Whisper transcription or spectral embeddings |
| Structural | Boilerplate removal, suffix arrays | Corruption and resolution checks | Scene splitting before dedup | Silence and noise removal |

My project implements:

| Layer | Status |
| --- | --- |
| Exact dedup | Implemented with SHA256 CAS |
| Semantic dedup | Implemented with FAISS ANN over embeddings |
| Near-exact dedup | Not yet implemented; natural extension |
| Structural cleanup | Partially implemented through quality gates |

Production pipelines usually run these layers in cost order. The cheapest pass removes the obvious duplicates first, so the expensive semantic pass sees fewer records.

## MinHash and LSH: The Intuition

MinHash/LSH is one of the standard techniques for large-scale text deduplication.

Imagine two documents. You want to know how similar they are without comparing every document pair in the corpus.

The process has four steps.

**Shingling.** Break each document into overlapping n-grams, such as 5-word windows. Each document becomes a set of shingles.

**Jaccard similarity.** Compare two shingle sets using intersection over union:

```text
similarity = |intersection| / |union|
```

If two documents share 80 percent of their shingles, their Jaccard similarity is 0.8.

**MinHash.** Computing Jaccard for every pair is too expensive. MinHash applies multiple hash functions to each document's shingle set and keeps the minimum hash value from each function. That produces a small fixed-size signature, such as 128 integers per document. The probability that two signatures match at a position approximates their Jaccard similarity.

**Locality-sensitive hashing.** Split each signature into bands. If two documents match in any band, they become candidate duplicates. This avoids comparing every pair. Only documents that land in the same bucket are checked.

The result is that you avoid an O(n²) all-pairs comparison and get something much closer to O(n) candidate generation, with high recall for duplicates above a chosen threshold.

## Why I Used FAISS Instead

MinHash works on token sets, which makes it excellent for text. But the project is multimodal. Images, video, and audio do not naturally become word shingles.

For those modalities, embeddings are the shared representation. Once everything becomes a vector, FAISS approximate nearest neighbor search becomes the natural equivalent. It lets the deduplication stage ask: "Which items are close in embedding space?"

That makes FAISS a good fit for a demo-scale multimodal system. At much larger scale, I would still layer the pipeline:

```text
MinHash/LSH      -> copy-paste and light text edits
Perceptual hash  -> visual near-duplicates
Audio fingerprint -> repeated audio clips
SemDeDup         -> semantic convergence across embeddings
```

Each layer catches duplicates the previous one misses.

## SemDeDup: Semantic Deduplication

MinHash catches documents that share many of the same words. But what about documents that say the same thing in different words?

That is where semantic deduplication comes in.

The basic idea has three steps:

1. **Embed everything.** Run documents, images, or media-derived features through a pretrained encoder. Each item becomes a dense vector.
2. **Cluster.** Use k-means or another clustering method so semantically similar items land in the same neighborhood.
3. **Prune within clusters.** Within each cluster, compute similarity and keep one item from each near-duplicate group, usually using a quality signal to decide which one survives.

This matters because text and media often converge semantically even when their raw bytes are different.

Two explanations of binary search trees can use different words but teach the same concept. Two photos can show the same scene from slightly different angles. Two videos can share the same underlying content with different encodings or cuts. Exact hashing misses those. Semantic dedup can catch them.

My pipeline already has the first and third parts of this pattern: embeddings plus FAISS similarity search. The missing production-scale optimization is clustering before search. At demo scale, searching the embedding set directly is fine. At millions or billions of items, clustering makes the expensive semantic pass tractable.

## Final Takeaway

The architecture is less about any single tool and more about the order of trust.

Start with immutable blobs. Attach metadata instead of deleting records. Version datasets with manifests. Keep embeddings and provenance queryable. Run cheap dedup before expensive dedup. Treat every stage as a contract with the next one.

That is the difference between an embedding demo and a multimodal training data system.

