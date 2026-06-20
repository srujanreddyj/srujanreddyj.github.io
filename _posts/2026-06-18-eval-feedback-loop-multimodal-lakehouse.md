---
layout: post
toc: true
title: "Eval Feedback Loops for Multimodal Dataset Versions"
categories: learnings
tags: [markdown, multimodal, lakehouse, evaluation, retrieval, data-quality, mlops]
---

# Eval Feedback Loops for Multimodal Dataset Versions

The previous post made a dataset version trainable. It covered the jump from immutable manifests to WebDataset shards and training loaders: the physical layer that lets a model consume data efficiently.

This post asks the next question:

```text
Should this dataset version be promoted at all?
```

Up to this point, the pipeline can ingest data, store raw assets, compute embeddings, run quality and dedup stages, build a catalog, create dataset versions, materialize shards, and benchmark loaders.

That is already a lot of machinery.

But a pipeline that only produces data is incomplete. A production-shaped data pipeline needs a feedback loop that can say whether a data change made the system better.

```text
data change -> new dataset version -> evaluation -> decision
```

Without that loop, every data decision is anecdotal.

I can say:

```text
I added more COCO images.
```

But the better question is:

```text
Did adding those images improve retrieval quality, coverage, diversity,
or downstream training behavior?
```

That is Component 10: the eval and feedback loop.

For context, this continues the multimodal lakehouse series:

- [Serverless Multimodal Data Lakehouse]({% post_url 2026-06-01-multimodal-embedding-pipeline-lancedb %})
- [Multimodal Lakehouse Implementation Notes]({% post_url 2026-06-11-multimodal-lakehouse-implementation-notes %})
- [Ray Actors, Catalog Trust Boundaries, and Pipeline Battle Scars]({% post_url 2026-06-12-ray-actors-catalog-trust-boundary %})
- [What Comes Next for the Multimodal Lakehouse]({% post_url 2026-06-15-what-comes-next-multimodal-lakehouse %})
- [Training-Ready Multimodal Data: Shards and Loaders]({% post_url 2026-06-18-training-ready-multimodal-data-shards-loaders %})

## Component 10: Eval and Feedback Loop

In model-centric ML, evaluation usually compares model versions:

```text
model_v1 vs model_v2
```

In data-centric ML, the dataset version also needs to be evaluated:

```text
dataset_v1 vs dataset_v2
```

That distinction matters for this project because the main artifact is not a trained model. The main artifact is a versioned multimodal data pipeline.

For example:

```text
v001:
  5K text documents
  1K images
  simple quality gates

v002:
  5K text documents
  1K images
  ANN dedup
  better caption filtering
  more balanced image clusters
```

The eval loop asks:

```text
Did v002 improve retrieval quality compared to v001?
Did it reduce duplicates?
Did it improve diversity?
Did it hurt any important query category?
```

That is what makes data quality measurable instead of subjective.

The point is not to say "I made a bigger dataset." The point is to prove whether the data change improved measured behavior.

## Freeze the Test, Change the Data

A good eval loop needs one rule:

```text
keep the eval set fixed while dataset versions change
```

If I change both the dataset and the eval questions at the same time, I cannot tell what caused the result.

The basic loop should look like this:

```text
frozen eval probes
        |
        v
run against dataset v001
        |
        v
record metrics

same frozen eval probes
        |
        v
run against dataset v002
        |
        v
compare metrics
```

The pattern is:

```text
hold eval constant
change dataset
measure difference
```

That is the scientific part of the data pipeline.

It is also the only way to make version promotion meaningful. A version should not be promoted because it built successfully. It should be promoted because it passed a stable set of checks and did not regress important behavior.

## What an Eval Probe Looks Like

This project is a multimodal retrieval system, so the eval set should contain query probes.

A probe is a small test case:

```yaml
id: image_dog_outside_001
query: "a dog running outside"
target_modality: image
expected_terms:
  - dog
  - outside
  - running
expected_source: COCO
```

Another text probe might look like:

```yaml
id: text_reinforcement_learning_001
query: "what is reinforcement learning?"
target_modality: text
expected_terms:
  - reward
  - policy
  - agent
  - learning
```

For each probe, the system runs search and checks whether the top results match the expected intent.

At first, these probes can be simple and hand-written. They do not need to be perfect. They need to be stable enough to catch obvious regressions.

Example probe categories:

| Eval task | Example query | Expected output |
| --- | --- | --- |
| Text to Text | "What is reinforcement learning?" | Educational text about RL |
| Text to Image | "a dog running outside" | COCO image or caption about a dog outside |
| Text to Video | "people cooking food" | Video clip, caption, or keyframe about cooking |
| Text to Audio | "a person reading a sentence" | Speech clip, transcript, or metadata if represented |

The audio case has an important caveat.

Text, image, and some video retrieval can use CLIP-like shared spaces if the embeddings are actually aligned. But dimensional compatibility is not semantic compatibility. Projecting Whisper vectors to 384 dimensions does not automatically make them comparable to MiniLM text vectors unless that projection is trained for the task.

For audio retrieval, a safer first step is transcript-based search or an embedding model explicitly trained to align audio and text.

That is the same lesson from the catalog schema bug: vectors from different models are not interchangeable just because they fit in a column.

## Retrieval Metrics

Search returns ranked results:

```text
query -> top 5 or top 10 results
```

So the eval loop needs ranking metrics.

## Precision@K

Precision@K asks:

```text
Of the top K results, how many were relevant?
```

For example:

```text
query = "dog running outside"
top 5 results = 4 relevant images

Precision@5 = 4 / 5 = 0.8
```

Precision@K is useful when I care about result cleanliness. If the top five results are noisy, the system feels bad even if a good result appears somewhere later.

For early versions of this project, Precision@5 is probably the simplest useful metric.

## Recall@K

Recall@K asks:

```text
Of all known relevant items, how many did the system retrieve in the top K?
```

Recall is useful when I have known target IDs or a labeled relevance set.

At demo scale, recall is harder because I may not know all relevant items in the corpus. A query like "dog outside" could have many valid images. Unless those are labeled, recall is only approximate.

So I would treat Recall@K as a later metric, once the eval set has stronger labels.

## Mean Reciprocal Rank

Mean Reciprocal Rank, or MRR, asks:

```text
How early did the first good result appear?
```

If the first relevant result appears at rank 1:

```text
score = 1.0
```

If it appears at rank 5:

```text
score = 1 / 5 = 0.2
```

MRR is useful for search demos because users care a lot about whether the first useful result appears near the top.

If v002 has the same Precision@5 as v001 but a better MRR, the first good answer moved earlier. That is a real improvement.

## nDCG@K

nDCG is useful when relevance is graded instead of binary.

Instead of marking each result as relevant or irrelevant, I can score it:

```text
3 = excellent
2 = good
1 = weakly related
0 = irrelevant
```

nDCG rewards systems that put highly relevant results earlier in the ranking.

This is closer to real search evaluation because not all relevant results are equally good.

For this project, the staged path is:

```text
Precision@K first
MRR next
nDCG@K after adding graded judgments
```

That keeps the first eval loop practical while leaving room for more realistic ranking evaluation later.

## Data Quality Metrics Belong in the Same Report

Retrieval metrics measure system behavior. They do not fully describe the dataset.

Because this project is a data pipeline, each version report should also include corpus-level metrics:

| Metric | What it tells me |
| --- | --- |
| Total items | Dataset size |
| Modality counts | Text/image/video/audio balance |
| Duplicate rate | Dedup effectiveness |
| Quality pass rate | Filter strictness |
| Largest cluster percentage | Concentration risk |
| Normalized entropy | Diversity |
| Missing asset count | Broken references |
| License distribution | Compliance and commercial usability |

This is where the previous diversity work fits.

For example:

```text
v001:
  clip_entropy = 0.71
  largest_cluster_pct = 28.4%

v002:
  clip_entropy = 0.83
  largest_cluster_pct = 14.1%
```

That says v002 has a more balanced visual corpus.

But that is not the whole answer. I still need retrieval eval to ask:

```text
Did the better balance improve search quality?
```

The complete feedback loop has two halves:

```text
corpus quality metrics + retrieval metrics
```

One measures the dataset itself. The other measures system behavior.

## What This Project Has Today

The current project has the foundation for this component, but not the full production eval loop yet.

The implemented foundation includes:

- immutable dataset version manifests
- item IDs pinned per version
- model versions recorded in manifests
- modality counts recorded
- LanceDB catalog as the query source
- search endpoints for text, image, and combined search
- WebDataset materialization
- loader benchmark stage
- lightweight version-comparison scaffolding

That means the hard structural pieces exist:

```text
versioned data + searchable catalog + metrics outputs
```

The missing production layer is the frozen eval suite itself:

- a committed eval probe file
- known expected results or relevance labels
- automatic search over each dataset version
- Precision@K, MRR, and nDCG reports
- comparison reports between versions
- a generated datasheet for each promoted dataset version

The honest way to describe the current state is:

```text
I implemented the versioning and catalog foundation needed for an eval loop,
plus lightweight comparison scaffolding. The next production step is a frozen
query-probe set with retrieval metrics per dataset version.
```

That distinction matters. It avoids pretending the project has a complete evaluation harness while still showing that the architecture is ready for one.

## A Four-Level Eval Roadmap

I would build this component in four levels.

## Level 1: Smoke-Test Evals

Start with a small hand-written probe file.

Example categories:

```text
text:
  reinforcement learning
  biology population growth

image:
  dog outside
  woman cutting cake
  people riding horses

video:
  cooking
  sports
  driving

audio:
  speech sample
  reading sentence
```

The goal is simple:

```text
Does search return obviously relevant results?
```

This is useful for demos and sanity checks. It catches broken embedding columns, empty search results, modality-routing bugs, and obvious quality regressions.

## Level 2: Versioned Eval Reports

For every dataset version, run the same frozen probes and write a report:

```text
run frozen probes
collect top K results
compute metrics
write eval_report.json
```

The report should include:

```json
{
  "dataset_version": "multimodal-demo-v002",
  "probe_count": 48,
  "precision_at_5": 0.71,
  "mrr": 0.82,
  "empty_result_rate": 0.04,
  "duplicate_result_rate": 0.07,
  "by_modality": {
    "text": {"precision_at_5": 0.78},
    "image": {"precision_at_5": 0.74},
    "video": {"precision_at_5": 0.61},
    "audio": {"precision_at_5": 0.42}
  }
}
```

Now version comparison becomes concrete:

```text
v001 Precision@5 = 0.62
v002 Precision@5 = 0.71
```

That is much better than "v002 has more rows."

## Level 3: Graded Relevance

Once the basic loop works, add graded relevance:

```text
0 = irrelevant
1 = weak
2 = good
3 = excellent
```

Then compute nDCG@K.

This is closer to industry search evaluation because it captures quality differences among relevant results. A perfect match should count more than a merely acceptable match.

It also lets me inspect category-specific regressions:

```text
image food queries improved
image sports queries regressed
video cooking queries still empty
audio retrieval is unreliable without transcripts
```

That is the level where evaluation starts pointing directly at data work.

## Level 4: Feedback Into Data Decisions

The final step is using the report to decide what to change.

An eval report should not only summarize scores. It should suggest data actions:

```text
dog image queries improved
cooking video queries are empty
audio search needs transcript alignment
largest CLIP cluster is still too large
caption mismatch rate is high
duplicate image results appear in top K
```

Those findings feed back into:

- connector choice
- quality thresholds
- dedup thresholds
- sampling and balancing strategy
- model choice
- embedding-space design
- version promotion rules

That closes the loop.

```text
data decision -> dataset version -> eval report -> next data decision
```

The system starts learning from its own outputs.

## Promotion Gates

The eval loop should produce a decision.

A dataset version should not be promoted just because the pipeline finished.

It should be promoted if:

- it passes quality checks
- it improves or preserves retrieval metrics
- it does not regress important query categories
- it has acceptable diversity and duplicate-rate metrics
- it has acceptable license and provenance coverage
- it has no missing assets referenced by the manifest

Conceptually:

```text
catalog
  |
  v
dataset version manifest
  |
  v
frozen eval probes
  |
  v
metrics report
  |
  v
decision: promote, reject, or revise
```

This is the production mindset: a dataset version is an artifact with a release gate.

## The Takeaway

The eval loop connects data-engineering decisions to measurable system behavior.

Without it, I can build new dataset versions forever and only guess whether they are better. With it, I can compare versions against a frozen set of probes, track retrieval metrics, inspect corpus health, and decide whether a version deserves promotion.

The short version:

```text
A dataset version is not better because it is bigger.
It is better if it improves measured behavior under a frozen eval.
```

That is the point of Component 10.

The earlier components made the data durable, queryable, versioned, streamable, and trainable. The eval feedback loop makes it accountable.

## Running Glossary

**Eval Probe:** A fixed query test case used to evaluate search or retrieval behavior across dataset versions.

**Frozen Eval Set:** A stable collection of eval probes that stays constant while dataset versions change.

**Precision@K:** The fraction of the top K retrieved results that are relevant.

**Recall@K:** The fraction of known relevant items retrieved within the top K results.

**Mean Reciprocal Rank (MRR):** A ranking metric based on how early the first relevant result appears.

**nDCG@K:** A ranked retrieval metric that uses graded relevance and rewards highly relevant results appearing early.

**Empty Result Rate:** The fraction of probes that return no useful results.

**Duplicate Result Rate:** The fraction of top results that are duplicates or near-duplicates, useful for evaluating dedup quality.

**Promotion Gate:** The quality and evaluation threshold a dataset version must pass before being used downstream.

## Further Reading

- [Stanford Introduction to Information Retrieval: Precision and Recall](https://nlp.stanford.edu/IR-book/html/htmledition/evaluation-of-unranked-retrieval-sets-1.html)
- [Stanford Introduction to Information Retrieval: Ranked Retrieval Evaluation](https://nlp.stanford.edu/IR-book/html/htmledition/evaluation-of-ranked-retrieval-results-1.html)
- [scikit-learn `ndcg_score`](https://scikit-learn.org/0.24/modules/generated/sklearn.metrics.ndcg_score.html)
- [NIST TREC](https://trec.nist.gov/)
- [MLCommons DataPerf](https://www.dataperf.org/home)
- [Datasheets for Datasets](https://arxiv.org/abs/1803.09010)
- [Google Data Cards Playbook](https://www.research.google/blog/the-data-cards-playbook-a-toolkit-for-transparency-in-dataset-documentation/)
- [TensorFlow Data Validation](https://tensorflow.github.io/tfx/guide/tfdv/)
