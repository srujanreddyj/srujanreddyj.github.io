# Project launch copy: LinkedIn and X

This document is ready to follow and copy. All times use Pacific Time. If you miss a listed time, post at the same time on the next weekday. Replace nothing inside the post text unless a link has changed.

## Before the first post

1. Confirm that these links open:
   - Lakehouse article: https://srujanreddyj.github.io/learnings/2026/06/01/multimodal-embedding-pipeline-lancedb.html
   - Lakehouse source: https://github.com/srujanreddyj/distributed-embedding-search-lakehouse
   - Feature-store article: https://srujanreddyj.github.io/learnings/2026/06/27/building-a-multimodal-feature-store-product-quality-risk.html
2. Save the lakehouse architecture image from the article.
3. Save or capture the feature-store architecture diagram from the article.
4. Add a short image description, also called alt text, whenever the platform offers the option. Copy the supplied alt text below.
5. Do not publish both projects on the same day.

## Posting schedule

| Date | Time | Platform | Post |
|---|---:|---|---|
| Wednesday, July 22, 2026 | 8:30 a.m. | LinkedIn | Lakehouse launch |
| Thursday, July 23, 2026 | 8:30 a.m. | X | Lakehouse thread |
| Monday, July 27, 2026 | 8:30 a.m. | LinkedIn | Lakehouse lesson |
| Tuesday, July 28, 2026 | 8:30 a.m. | X | Lakehouse follow-up |
| Wednesday, July 29, 2026 | 8:30 a.m. | LinkedIn | Feature-store launch |
| Thursday, July 30, 2026 | 8:30 a.m. | X | Feature-store thread |
| Monday, August 3, 2026 | 8:30 a.m. | LinkedIn | Feature-store lesson |
| Tuesday, August 4, 2026 | 8:30 a.m. | X | Feature-store follow-up |

---

## 1. LinkedIn: lakehouse launch

### What to do

1. Start a LinkedIn post.
2. Attach the horizontal lakehouse architecture image.
3. Add the alt text below.
4. Copy the post exactly as written.
5. Check both links in the preview, then publish.
6. Reply to substantive comments. If someone asks about scale, say that this is a small-scale implementation of a production-shaped design, not a claim that it already runs at internet scale.

### Image alt text

Architecture of a 12-stage multimodal data pipeline. Text, image, video, and audio sources pass through ingestion, content-addressed storage, validation, distributed preprocessing, embedding workers, LanceDB, dataset versioning, and training-ready outputs.

### Copy this post

I started by trying to embed a collection of files. I ended up building a 12-stage data pipeline for text, images, video, and audio.

The hard part was not generating vectors. It was making the resulting data safe to reuse.

That required the system to answer questions such as:

• Which source produced this feature?
• Which model and preprocessing version created it?
• Can a failed run resume without duplicating work?
• Can the same dataset feed both search and model training?

I built a serverless multimodal data lakehouse that includes:

• Content-addressed storage for stable identity and exact deduplication
• Validation and curation before costly inference
• Ray Data for distributed preprocessing
• Warm GPU workers for modality-specific embeddings
• LanceDB for vectors and structured metadata
• Versioned manifests for reproducible datasets
• WebDataset shards for streaming-friendly training
• Provenance across source data, transformations, models, and outputs

The key design choice was to separate durable storage from processing and training layouts. Original assets remain stable, while temporary batches and training shards can change for throughput.

This is a small-scale implementation of a production-shaped system. Its value is not a claim of internet-scale traffic. It is the set of boundaries, failure modes, and trade-offs the implementation made visible.

The main lesson: embeddings are not the product. Reusable, traceable features are the product.

Architecture and implementation notes:
https://srujanreddyj.github.io/learnings/2026/06/01/multimodal-embedding-pipeline-lancedb.html

Source:
https://github.com/srujanreddyj/distributed-embedding-search-lakehouse

If you were reviewing this system for production, which boundary would you test first?

#DataEngineering #MLOps #MachineLearning

---

## 2. X: lakehouse thread

### What to do

1. Start a new post on X.
2. Copy Post 1.
3. Select the option to add another post.
4. Add Posts 2 through 7 in order.
5. Attach the architecture image to Post 2 and add the supplied alt text.
6. Check the links in Post 7, then publish the full thread.

### Post 1

I started by trying to embed some files. I ended up building a 12-stage data pipeline for text, images, video, and audio.

The hard part was not generating vectors. It was making the data safe to reuse. Here is what I learned:

### Post 2

The system covers ingestion, content-addressed storage, validation, curation, Ray preprocessing, GPU embedding workers, LanceDB, dataset versions, training shards, and provenance.

[Attach the architecture image to this post.]

### Post 3

The first key choice: separate durable storage from throughput-oriented layouts.

Original assets keep stable identities. Processing batches and training shards can change without copying or redefining the source data.

### Post 4

The second key choice: curate before embedding.

Corrupt files, duplicates, unsupported inputs, and low-value samples should fail before they consume GPU time. Curation is part of the data product, not a cleanup step.

### Post 5

Multimodal data exposed every weak boundary.

Text, images, video, and audio differ in size, decoding, batching, schemas, and failure modes. A contract that worked for one modality often broke on the next.

### Post 6

This is a small-scale implementation of a production-shaped design. The useful result was not a scale claim. It was learning where identity, retries, schemas, memory, model versions, and lineage fail once the pieces run together.

### Post 7

My main lesson: embeddings are not the product. Reusable, traceable features are the product.

Architecture + notes:
https://srujanreddyj.github.io/learnings/2026/06/01/multimodal-embedding-pipeline-lancedb.html

Source:
https://github.com/srujanreddyj/distributed-embedding-search-lakehouse

---

## 3. LinkedIn: lakehouse follow-up

### What to do

1. Publish this as a text-only post.
2. If useful, add the same architecture image after the text is ready.
3. Copy the post exactly as written.

### Copy this post

The most useful bug in my multimodal data project came from a boundary that looked harmless.

Different embedding workers returned outputs with compatible-looking shapes, but compatible dimensions did not mean compatible semantics.

A text vector, image vector, and projected audio vector do not become comparable merely because they have the same width. They need a shared, trained embedding space if the system intends to compare them directly.

That distinction changed the design:

• Store the embedding model and version with every feature
• Record the preprocessing and projection configuration
• Prevent unsupported cross-modal comparisons
• Evaluate retrieval quality instead of trusting tensor shape
• Treat a new model as a new feature version, not an in-place update

This is why lineage matters in ML data systems. A vector without its model, preprocessing, source, and dataset version is difficult to trust and hard to reproduce.

The broader lesson: schema compatibility proves that data can move through a system. It does not prove that the data still means what the next stage assumes.

I wrote up the full project here:
https://srujanreddyj.github.io/learnings/2026/06/01/multimodal-embedding-pipeline-lancedb.html

What semantic checks have saved you from a pipeline that was technically “green”?

#DataEngineering #MLOps

---

## 4. X: lakehouse follow-up

### Copy this post

Equal vector dimensions do not mean equal semantics.

An audio vector is not comparable with a text or image vector just because each has 512 values. Cross-modal retrieval needs a shared, trained space—and evaluation that proves it.

That bug changed how I versioned features.

---

## 5. LinkedIn: feature-store launch

### What to do

1. Start a new LinkedIn post.
2. Attach the feature-store architecture diagram.
3. Add the alt text below.
4. Copy the post exactly as written.
5. Check the article link, then publish.

### Image alt text

Architecture of a product-quality risk feature store. Amazon review data passes through quality checks, forward-looking label creation, rolling feature computation, a Postgres offline store, Redis online serving, model training, FastAPI serving, and drift monitoring.

### Copy this post

My first feature-store design predicted product-quality risk at the product level.

The data showed why that design would not work: after filtering for products with enough history, the median product still had only one review in a 30-day window.

There was not enough signal for stable rolling features or labels.

So I changed the grain from product to brand/store.

That pivot became the central lesson of this project: the entity you want to predict is not always the entity your data can support.

I then built the full feature lifecycle around Amazon Electronics reviews:

• Backward-looking 7-, 30-, and 90-day features
• Forward-looking 30-day quality-risk labels
• Point-in-time joins to prevent future data from leaking into training
• Postgres as the offline store for history and training
• Redis as the online store for the latest feature vector
• Time-based train and test splits
• Drift checks for rating, review volume, and other feature changes
• A FastAPI serving path

I kept the first model simple: logistic regression with tabular review features. It reached 0.87 AUC and 0.65 average precision in this experiment.

The point was not to build the most complex model. It was to test whether the data, labels, historical joins, serving path, and monitoring formed a correct system.

Three lessons stayed with me:

1. The grain must match the signal density.
2. Offline history and online serving solve different problems.
3. Temporal correctness is a system property, not a final SQL check.

Full project write-up:
https://srujanreddyj.github.io/learnings/2026/06/27/building-a-multimodal-feature-store-product-quality-risk.html

When your preferred prediction grain is too sparse, how do you decide whether to aggregate, widen the time window, or change the target?

#DataEngineering #FeatureStore #MLOps

---

## 6. X: feature-store thread

### What to do

1. Start a new post on X.
2. Copy Post 1.
3. Add Posts 2 through 7 in order.
4. Attach the feature-store architecture diagram to Post 3 and add its alt text.
5. Check the article link in Post 7, then publish the full thread.

### Post 1

My first feature-store design predicted product-quality risk per product.

The data rejected the design: the median product had only 1 review in a 30-day window. That was too sparse for stable features or labels.

So I changed the grain.

### Post 2

I moved from product to brand/store.

That produced denser windows and a target the data could support, though it sacrificed product-level detail.

Lesson: the entity you want to predict is not always the entity your data can support.

### Post 3

I built the full lifecycle around that grain: data checks, rolling features, forward-looking labels, point-in-time joins, offline history, online serving, training, an API, and drift monitoring.

[Attach the architecture diagram to this post.]

### Post 4

Postgres stored full feature history for training and backfills. Redis stored only the latest vector for fast point lookups.

One store optimized for historical correctness; the other optimized for serving latency.

### Post 5

Temporal rule:

Features look backward from prediction time.
Labels look forward.
Training joins use only values available at prediction time.

Without that contract, a model can learn from the future while every pipeline job still passes.

### Post 6

I kept the first model simple: logistic regression with tabular review features.

Result in this experiment: 0.87 AUC and 0.65 average precision.

The goal was to validate the feature lifecycle before adding model complexity.

### Post 7

Three lessons:

1. Grain must match signal density.
2. Offline history and online serving are different problems.
3. Temporal correctness must shape the whole system.

Full write-up:
https://srujanreddyj.github.io/learnings/2026/06/27/building-a-multimodal-feature-store-product-quality-risk.html

---

## 7. LinkedIn: feature-store follow-up

### What to do

1. Publish this as a text-only post.
2. Copy the post exactly as written.

### Copy this post

A machine-learning pipeline can pass every job check and still train on the future.

That was the main risk I wanted to make visible in my product-quality feature store.

For a prediction made at time T:

• Features must use events at or before T
• The label may describe what happens after T
• The training join must retrieve the feature values that existed at T

Joining every training row to the latest feature value breaks this contract. It lets later information leak into earlier examples and makes offline performance look better than the deployed system can achieve.

My design used backward-looking rolling features, forward-looking 30-day labels, time-based splits, and point-in-time joins against feature history.

This required keeping full history in the offline store. Redis held only the latest feature vector for serving; it was not the source for historical training data.

The lesson: leakage prevention is not one filter added before training. Storage design, timestamps, feature computation, labels, joins, and validation all have to enforce the same time boundary.

Full project:
https://srujanreddyj.github.io/learnings/2026/06/27/building-a-multimodal-feature-store-product-quality-risk.html

What check do you use to catch point-in-time leakage before model evaluation?

#DataEngineering #MachineLearning #MLOps

---

## 8. X: feature-store follow-up

### Copy this post

An ML pipeline can pass every job check and still train on the future.

At prediction time T:
• features look backward
• labels may look forward
• training joins retrieve the feature values that existed at T

Leakage prevention is a system contract, not one final filter.

---

## After each post

1. Check the post once for broken line breaks or links.
2. Reply to useful questions with a concrete answer. Do not answer with only “Thanks.”
3. Save good questions. Each can become a later technical post.
4. After 24 hours, record impressions, profile views, link visits, substantive comments, and new connections.
5. After the full sequence, compare which opening, topic, and visual produced the most useful discussion. Use that evidence for the next project launch.

## Profile cleanup after the launches

1. Add both project articles to the Featured section of LinkedIn.
2. Add the lakehouse repository to the Featured section.
3. Pin the stronger launch thread on X. Choose the one that produced more substantive replies or profile visits, not only more likes.
4. Keep the portfolio link visible in both profiles.
