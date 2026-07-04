---
layout: post
toc: true
title: "Data Operations Architecture at Scale"
categories: [learnings]
tags: [markdown, data-engineering, mlops, data-operations, multimodal, governance, monitoring]
---

# Data Operations Architecture at Scale

Production ML data operations is a collection of connected systems: ingestion, annotation, synthetic data, multimodal storage, enrichment, quality monitoring, agentic remediation, self-service tooling, scale patterns, and governance. This post walks through each component as an architecture decision: what the component does, why the design matters, and what tradeoffs come with it.

A structured guide to **every stage** of the data operations cycle underneath a production ML model — not just how data moves (batch/streaming), but how it's collected, labeled, generated, validated, versioned, served, monitored, and fed back into the system.

---

## 1. The Big Picture: It's a Cycle, Not a Pipeline

The biggest mistake in thinking about ML data operations is drawing it as a straight line: *collect → train → deploy*. In reality it's a **closed loop** — production feeds back into collection.

```text
                     ┌─────────────────────────────────────────────┐
                     │                                             │
                     v                                             │
            1. COLLECT / INGEST                                    │
         (batch sources + streaming events)                        │
                     │                                             │
                     v                                             │
            2. VALIDATE / QUALITY GATE                             │
                     │                                             │
                     v                                             │
            3. LABEL / ANNOTATE  <──────┐                          │
                     │                  │ (uncertain samples)      │
                     v                  │                          │
            4. ENRICH / AUGMENT ────────┘                          │
         (ML enrichment + synthetic data)                          │
                     │                                             │
                     v                                             │
            5. TRANSFORM / FEATURE ENGINEER                        │
                     │                                             │
                     v                                             │
            6. STORE / MERGE / VERSION                             │
        (lakehouse + online store + merged view)                   │
                     │                                             │
                     v                                             │
            7. TRAIN                                               │
                     │                                             │
                     v                                             │
            8. SERVE (batch inference + online inference)          │
                     │                                             │
                     v                                             │
            9. MONITOR (drift, quality, skew, SLAs)                │
                     │                                             │
                     v                                             │
           10. GOVERN (privacy, lineage, retention, deletion)      │
                     │                                             │
                     └──────── feedback / prediction logs ─────────┘
```

Each numbered stage below is one section of this guide. Study them in order the first time; use them as a reference afterward.

> 🧠 **Takeaway** *Data operations is not a single pipeline. It is a closed loop of coordinated stages, each with different latency and correctness requirements, that must agree on what the data means.*

---

## 2. Stage 1 — Collect / Ingest: The Two Lanes

All data enters through one of two lanes, chosen by how fast it decays in value.

### 2a. The Batch Lane

**Use for:** anything that can wait — product metadata dumps, daily exports, annotation batches, synthetic datasets, embedding backfills, quality reports, large multimodal assets (video, image corpora).

```text
Source systems (S3 dumps, DB snapshots, API exports, annotation files)
        |
        v
Orchestration (Airflow / Prefect / Dagster)
        |
        v
Distributed processing (Spark / Dask / Ray Data)
        |
        v
Lakehouse storage (Iceberg / Delta / Parquet)
```

**Key design decision:** Batch owns the **durable historical record**. It must answer *"what did the model know at prediction time, six months ago?"*

| Batch Decision | Why It Helps | What It Costs |
|---|---|---|
| Orchestrated jobs | Clear dependency graph, retries | Scheduling overhead |
| Spark/Dask/Ray processing | High-throughput transforms | Cluster cost and tuning |
| Iceberg/Delta storage | Versioning, schema evolution, time travel | Table maintenance overhead |
| Backfill support | Reproducible training and debugging | Requires idempotent jobs |

> ✅ **Rule of thumb:** If correctness, auditability, and cost matter more than freshness → batch.

### 2b. The Streaming Lane

**Use for:** data whose value decays fast — clicks, impressions, fraud signals, device telemetry, live ranking feedback, prediction logs.

```text
Event producers (app events, logs, telemetry, prediction logs)
        |
        v
Message bus (Kafka / Kinesis / Pub/Sub)
        |
        v
Stream processor (Flink / Kafka Streams / Spark Structured Streaming)
        |
        v
Low-latency serving state (Redis / DynamoDB / Cassandra)
        |
        v
Async historical sink (Iceberg / Delta / Parquet)
```

**Key design decision:** The online store is **serving state, not source of truth**. Every event must also land asynchronously in the lake, or you lose the ability to replay and audit.

**Six concepts to know cold:**

| Concept | Question it answers |
|---|---|
| Keys | What entity does each event update? |
| Event time | When did it actually happen (not when we processed it)? |
| Watermarks | How late can an event arrive before we close the window? |
| Idempotency | Can we replay without double-counting? |
| Backpressure | What happens when the downstream store slows down? |
| State TTL | When should an online feature expire? |

> ✅ **Rule of thumb:** Use streaming only when freshness changes the product or model decision — never by default.

---

## 3. Stage 2 — Validate: Quality Gates Before Anything Downstream Trusts the Data

The worst place to discover bad data is inside model behavior. Every lane needs its own gate, sized to its latency budget.

```text
Batch source  -> batch quality checks  -> batch features
Stream source -> stream quality checks -> stream features
                                      \
                                       +-> merged view
```

**Batch checks (can be heavy):**
- Schema checks — columns, types, timestamp formats
- Value checks — ranges, null rates, uniqueness
- File checks — corrupt images, unreadable audio, broken JSON
- Dedup checks — exact hashes, perceptual hashes, embedding similarity
- Distribution checks — drift, label balance, feature statistics

**Streaming checks (must be light):**
- Schema validation
- Range checks
- Null-rate counters
- Freshness checks
- Anomaly detection on aggregates

**Multimodal-specific checks:**
- Image readability, dimensions, blur, exposure
- Audio duration, sample rate, clipping, silence
- Text language, toxicity, truncation, encoding
- Embedding completeness and vector dimension checks

> ✅ **Principle:** Nothing crosses into the merged view without crossing a trust boundary first.

---

## 4. Stage 3 — Label / Annotate: Turning Raw Data into Supervision

Most raw data has no labels. This stage is where humans (and increasingly, models) attach ground truth.

**Typical annotation pipeline:**

```text
Unlabeled pool
      |
      v
Sampling / prioritization (random, stratified, or uncertainty-driven)
      |
      v
Task creation (instructions, guidelines, UI)
      |
      v
Human labeling (in-house team, vendor, or crowdsource platform)
      |
      v
Quality control (gold sets, inter-annotator agreement, spot review)
      |
      v
Label consolidation (majority vote, adjudication)
      |
      v
Versioned labeled dataset
```

**Design questions this stage must answer:**
- **Guideline versioning:** which instructions were active when this label was produced? (Guidelines change — old labels don't automatically match new definitions.)
- **Inter-annotator agreement (IAA):** if two annotators disagree, is the task ambiguous or is one annotator wrong?
- **Cost/throughput tradeoff:** more reviewers = higher quality but higher cost and slower turnaround.
- **Auto-labeling:** can a model pre-label and have humans only correct it ("labeling-assist"), and does that introduce bias toward the pre-labeling model's mistakes?

| Annotation Decision | Why It Helps | What It Costs |
|---|---|---|
| Gold-set spot checks | Catches annotator drift early | Requires curated ground truth |
| Multiple annotators per item | Higher label confidence | Multiplies labeling cost |
| Guideline versioning | Lets you explain label changes over time | Extra metadata to track |
| Auto-label + human review | Cuts cost, speeds throughput | Can propagate model bias into "ground truth" |

> 🧠 **Failure mode to remember:** *silent guideline drift* — the instructions change mid-project, but old and new labels get merged as if they mean the same thing. Always version the guideline, not just the label.

---

## 5. Stage 4 — Active Learning: Deciding What to Label Next

Labeling everything is expensive. Active learning uses the model itself to decide which unlabeled examples are worth human time.

```text
Trained model (current version)
      |
      v
Score unlabeled pool (confidence, entropy, disagreement, embedding novelty)
      |
      v
Select highest-value examples
  - Lowest confidence
  - Highest disagreement between ensemble members
  - Most novel embedding (far from training distribution)
      |
      v
Send to annotation queue
      |
      v
New labels feed back into training data
```

**Common selection strategies:**

| Strategy | Idea | Watch out for |
|---|---|---|
| Uncertainty sampling | Label what the model is least confident about | Can over-sample noisy/mislabeled outliers |
| Query-by-committee | Label where an ensemble disagrees most | Expensive — needs multiple models |
| Diversity/coverage sampling | Label to cover embedding space gaps | Doesn't target current model weaknesses directly |
| Error-driven sampling | Label near known production failure modes | Needs a feedback signal from monitoring first |

> ✅ **Where it lives in the lanes:** batch for the scoring/selection job, but the *signal* that triggers it (a burst of low-confidence predictions in production) is often a stream.

---

## 6. Stage 5 — Enrich / Augment: Adding Value Without Human Labeling

Two different techniques often get bundled together — keep them conceptually separate.

### 6a. ML Enrichment
Using models to add derived information to existing data — not new ground truth, but useful signal: embeddings, entity extraction, toxicity scores, image tags, deduplication signatures.

- **Batch enrichment:** backfilling embeddings for a historical corpus.
- **Streaming enrichment:** tagging a new event in near-real time (e.g., scoring a comment for toxicity as it's posted).

### 6b. Synthetic Data Generation
Creating entirely new training examples, usually to fix a gap real data can't fill cheaply: class imbalance, rare edge cases, privacy-sensitive domains, or domain coverage.

```text
Generator (rules-based, simulation, or generative model)
      |
      v
Filtering (quality thresholds, deduplication vs. real data)
      |
      v
Evaluation (does it actually help downstream model performance?)
      |
      v
Provenance tagging (mark every record as synthetic + generator version)
      |
      v
Merged into training data (usually with a mixing ratio vs. real data)
```

**Things that must be tracked for synthetic data specifically:**
- Generator version / model used to produce it
- Generation parameters (prompt, seed, filters applied)
- Ratio of synthetic to real data in any given training set
- A way to **exclude** synthetic data from evaluation sets (never evaluate on your own generated data as if it were ground truth)

> 🧠 **Failure mode to remember:** *model collapse* — training repeatedly on your own model's synthetic output, generation after generation, causes quality and diversity to degrade. Synthetic data needs the same lineage rigor as labeled data, arguably more, because its provenance is easier to lose track of.

---

## 7. Stage 6 — Transform / Feature Engineer: The Merged View

This is where batch and streaming features stop being two separate things and become **one governed contract**.

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

Downstream consumers should never have to ask "did this come from Spark or Flink?" They should be able to ask: *what entity is this keyed by, what timestamp is it valid for, what definition version produced it, what checks did it pass, can I use it for training or serving or both?*

### The Five Rules of a Good Merged View

**Rule 1 — Event time is the join contract.**
A prediction made at 10:05 should only see features known by 10:05. Processing time is an implementation detail; event time is the ML contract.
- Batch: **ASOF joins** — match each event to the most recent feature at or before its timestamp.
- Streaming: **windowed state + watermarks** — e.g., a 10:00–10:05 window with 2 minutes allowed lateness, feature emitted at 10:07 but only valid for events after 10:05.

**Rule 2 — Feature definitions are shared, not duplicated.**
Training-serving skew usually starts with two teams writing two implementations of the "same" feature (Spark for training, Flink for serving) that quietly diverge — e.g., one filters bot traffic and the other doesn't. The fix is **one definition contract** (entity, timestamp, window, filters, null policy, owner) that both engines implement identically, not necessarily one shared codebase.

**Rule 3 — The online store is a cache of certified state, not historical memory.**
Every value pushed to Redis/DynamoDB should carry metadata to debug it: entity id, feature value, event time, computed time, definition version, TTL. If the online store is flushed, the lakehouse must be able to rebuild it — never the reverse.

**Rule 4 — Quality gates sit before the merge, not after** (see Stage 2 above — this is where its output lands).

**Rule 5 — Version the view, not just the data.** A data version includes:
- Feature definitions · Transformation code · Quality checks · Annotation schema · Synthetic-data generator version · Enrichment model version · Backfill window · Online materialization policy

If any of those change, the model sees a different world even if the raw files look identical.

---

## 8. Stage 7 — Store / Version / Govern: Making the Past Reconstructible

**Storage layer:** Iceberg / Delta / Parquet lakehouse for offline truth; Redis / DynamoDB for online serving state.

**Versioning must answer:**
- Which data trained model `v12`?
- Which feature definition produced this online value?
- Which annotation guideline was active?
- Which synthetic generator created these samples?
- Which downstream datasets are affected if this source is deleted?

**Governance layer (must apply *before* serving or training, not after):**
- **Access control** — who/what can read PII-bearing fields
- **Privacy** — anonymization, differential privacy, consent tracking
- **Retention policy** — how long raw data, labels, and features are kept
- **Deletion path** — when a user requests deletion, can it actually be honored across the lake, the online store, *and* any model that was trained on it?
- **Lineage** — traceable record of what transformed what, needed to answer every question above

> 🧠 **Failure mode to remember:** *no deletion path.* Teams build the collection and training side well, then a compliance request arrives and there's no way to trace — let alone remove — a specific user's data from every downstream table, cache, and training set it touched.

---

## 9. Stage 8 — Train: Consuming the Merged View

Training data preparation is where point-in-time correctness (Rule 1 above) gets tested for real:

- **Train/validation/test splits** must respect entity and time boundaries — a naive random split can leak future information into training (e.g., the same user appearing in both train and test with overlapping time windows).
- **Point-in-time joins** pull the exact feature values that would have been available at each historical prediction time — not the *current* feature value.
- **Dataset snapshotting** — a specific, immutable pull from the merged view, tagged with the version metadata from Stage 7, so the training run can be reproduced exactly later.

> ✅ **Rule of thumb:** If you can't reproduce the exact training set for a model six months from now, you don't have a training pipeline — you have a one-time script.

---

## 10. Stage 9 — Serve: Batch Inference and Online Inference

Two serving modes mirror the two ingestion lanes:

| Mode | Pattern | Feeds from |
|---|---|---|
| Batch inference | Score a large dataset periodically (e.g., nightly recommendations) | Offline view (lakehouse) |
| Online inference | Score a single request in real time | Online view (Redis/DynamoDB), same feature definitions as training |

The reason Rule 2 (shared feature definitions) matters most here: if serving computes `user_clicks_7d` differently than training did, the model's online behavior silently diverges from what it learned — this is training-serving skew, and it's usually invisible until someone investigates a metrics drop.

---

## 11. Stage 10 — Monitor: Watching Both the Data and the Model

Monitoring has to cover more than model accuracy, because by the time accuracy drops, the data has usually already been wrong for a while.

**What to monitor:**
- **Data drift** — is the distribution of incoming features shifting from training?
- **Label drift** — are ground-truth label distributions changing (e.g., fraud rate creeping up)?
- **Prediction drift** — is the model's output distribution shifting even if input looks stable?
- **Freshness SLAs** — is a feature arriving within its expected latency window?
- **Pipeline health** — job failures, schema-check failures, late data, backfill status
- **Training-serving skew** — periodically compare online vs. offline computed values for the same feature/entity/time

**Where checks run:** batch monitoring can do deep statistical comparisons (full distribution tests); streaming monitoring runs light continuous checks (rolling null rates, anomaly detection on aggregates) so problems surface in minutes, not the next day.

---

## 12. Stage 11 (closing the loop) — Feedback: Production Becomes the Next Dataset

This is the stage that turns the pipeline into a cycle instead of a line.

- **Prediction logs** (what the model predicted, and eventually what actually happened) become a new data source feeding back into Stage 1 (Collect).
- **Low-confidence or disagreement cases** surfaced in production feed the active-learning queue (Stage 4).
- **Drift alerts** from Stage 10 (Monitor) can trigger new synthetic data generation (Stage 5) to patch coverage gaps, or trigger a new labeling batch.
- **Deletion/retention events** from Stage 7 (Govern) must propagate backward through every stage that touched the deleted data.

> 🧠 **This is why "data operations" and "MLOps" overlap so much:** the loop only works if every stage can be traced back to and forward from every other stage. That traceability *is* the lineage and versioning work from Stage 7 — it's not a separate concern, it's the connective tissue of the whole cycle.

---

## 13. Cross-Cutting Components (Not Their Own Stage — They Touch All of Them)

| Component | Where it plugs in | Why |
|---|---|---|
| **Self-service tooling** | Merged view only | Users should browse trusted datasets, not raw lane internals |
| **Agentic operations** | Every stage | Agents can monitor pipelines, diagnose failures, auto-remediate — but only after failure patterns are well understood |
| **Multimodal handling** | Collect, Validate, Store | Large binaries need object storage + manifests, not table rows |
| **Cost management** | Collect, Transform, Store | Batch cluster sizing, streaming partition count, and storage tiering all trade cost against latency |

> 🧠 **Why this matters:** don't draw "the ML data platform" as one pipeline with these bolted on the side. They're systems attached to the same contract as everything else — first-class, not optional extras.

---

## 14. Modality-Specific Variations Across the Cycle

The 10-stage cycle in Sections 2–12 holds for every modality — you still collect, validate, label, enrich, transform, store, train, serve, monitor, and feed back. What changes almost completely by modality is **what each stage means technically**: what "cleaning" is, what "duplicate" means, what a quality score is built from, and what the unique safety/compliance risks are. This section is the modality-by-modality technical breakdown, followed by one comparison table.

### 14a. Text (the baseline)

Every generic tool named earlier in this guide (schema checks, hash-based dedup, quality classifiers) was built for text first — it's the cheapest modality to store, clean, and score.

- **Cleaning:** HTML/boilerplate stripping, encoding normalization (UTF-8, Unicode fixes).
- **Dedup:** exact hashing (SHA/MD5) plus **MinHash + Locality-Sensitive Hashing (LSH)** for near-duplicates at the shingle/n-gram level.
- **Quality scoring:** perplexity, grammatical-quality classifiers, repetition and spam signals.
- **Tokenization:** solved problem — BPE-style subword tokenizers.
- **Cost profile:** lowest storage and compute cost per training example of any modality.

### 14b. Images

Almost every stage changes shape.

- **Cleaning:** format/resolution normalization, color-space fixes, corrupt-file detection (truncated JPEGs, broken headers) — not encoding fixes.
- **Dedup:** exact byte hashing fails immediately — a resized, cropped, or re-compressed copy of the same image has a completely different hash. Image pipelines use **perceptual hashing (pHash)** or **embedding-similarity dedup** (CLIP-style embeddings + approximate nearest-neighbor search) instead.
- **Quality scoring:** aesthetic score, blur/exposure/resolution thresholds, watermark detection (a stock-photo watermark baked into millions of training images is a real, documented contamination failure).
- **Safety filtering:** adds a category text mostly doesn't have — mandatory CSAM screening against known-hash databases (a legal requirement in most jurisdictions), plus NSFW and violence classifiers.
- **"Tokenization":** not tokenization in the text sense — images are patchified (ViT-style fixed patches) or passed through a learned discrete codebook (VQ-VAE / VQ-GAN) to produce tokens.
- **Synthetic data role:** mainly **recaptioning** — raw alt-text scraped from the web is frequently irrelevant or SEO-stuffed, so a vision-language model is run over the corpus to generate better captions. This is a different synthetic-data motive than text's "rephrase weak writing."

### 14c. Audio

- **Cleaning:** resampling to a standard sample rate, mono/stereo normalization, silence trimming, loudness normalization.
- **Dedup:** acoustic fingerprinting (Shazam-style), not text or image hashing.
- **Quality scoring:** signal-to-noise ratio, clipping detection, speech-quality metrics (e.g., DNSMOS-style scores) instead of perplexity.
- **Safety/compliance:** adds **voice consent and likeness rights** — a person's voice carries more legal and ethical sensitivity than their written words, especially given voice-cloning risk.
- **"Tokenization":** conversion to mel-spectrograms or discrete tokens via a neural audio codec (EnCodec, SoundStream-style) — a much heavier preprocessing step than text tokenization.
- **Cost profile:** meaningfully higher storage/decode cost per hour than text, but still below video.

### 14d. Video — the most expensive lane

- **Cleaning:** codec/container normalization, frame-rate normalization, and critically, **frame sampling** — adjacent frames are nearly identical, so pipelines run shot/scene detection and keyframe extraction rather than using every frame.
- **Dedup:** runs on embeddings of sampled frames or short clips; byte-level or single-frame hashing misses re-encoded or re-cropped copies.
- **Quality scoring:** adds temporal dimensions on top of per-frame visual quality — camera shake, scene-cut frequency, audio-video sync quality.
- **Annotation:** the most expensive per-item of any modality — temporal action labels, object tracking across frames, and speaker diarization all take far more annotator time than one image label or text span.
- **Cost profile:** dominates every other consideration. Decoding video at scale is itself a compute bottleneck before modeling starts, which makes frame-sampling strategy as much a cost-control decision as a data-quality one.

### 14e. Multimodal Pairing (image-text, video-text, audio-text)

Paired data introduces a problem none of the single-modality pipelines have: **alignment quality between modalities, not just quality within one.** A perfectly clean image paired with an unrelated caption is worse than either being individually flawed, because the model learns a false association.

This needs its own filtering stage, run in addition to (not instead of) each modality's own pipeline:
- **Cross-modal relevance filtering** — commonly a CLIP-style similarity score between image and caption.
- **Transcript-alignment filtering** — ASR word-error-rate used as a proxy for how well an audio track matches its transcript.
- **Provenance requirement:** pairs need lineage on *both* sides — which image-quality pipeline and which text-quality pipeline each half passed through — since a pair can fail for either reason independently.

### 14f. Comparison Table

| Stage/Concern | Text | Image | Audio | Video |
|---|---|---|---|---|
| Dedup method | Hash / MinHash-LSH | Perceptual hash / embedding similarity | Acoustic fingerprinting | Frame/clip embedding similarity |
| Quality signal | Perplexity, grammar | Aesthetic score, blur, resolution | SNR, clipping, speech quality | Camera shake, scene cuts, A/V sync |
| Extra safety concern | PII, toxicity | CSAM, NSFW, watermarks | Voice consent/likeness | All of the above, plus per-frame |
| "Tokenization" | BPE subwords | Patches / VQ codebook | Mel-spectrogram / neural codec | Sampled frames + patches |
| Synthetic data role | Rephrase weak text | Recaption (VLM-generated captions) | TTS-generated pairs | VLM-generated descriptions/labels |
| Relative storage/compute cost | Lowest | Medium | Medium–high | Highest |
| Unique failure mode | Boilerplate dominance | Byte-dedup misses near-dupes | Consent/likeness issues | Redundant-frame waste |

### 14g. The Cross-Cutting Shift: Quality Checks Become Someone Else's Model's Job

The pattern that cuts across every non-text modality: **the further you get from text, the more "cleaning" and "quality" are delegated to an auxiliary model** — a CLIP score, a VLM caption, a codec, an ASR transcript — rather than a hand-written heuristic.

That shifts the engineering burden from *writing filters* to **validating and versioning the auxiliary models doing the filtering**. A stale CLIP checkpoint or a degraded captioning model silently lowers corpus quality in a way that's much harder to detect than a broken regex — it doesn't throw an error, it just quietly passes worse data through. This means Rule 5 from Section 7 ("version the view, not just the data") gets an extra item for multimodal pipelines: **the version of every auxiliary model used for cleaning, scoring, or captioning must be tracked as part of the data version**, exactly like a synthetic-data generator version.

> 🧠 **Remember this line:** *Multimodal doesn't add a new stage to the cycle — it changes what every existing stage is built out of, and it adds one new stage (cross-modal alignment) that single-modality pipelines never need.*

---

## 15. A Practical Reference Architecture

The smallest version that still preserves the right shape end-to-end:

```text
                          +--------------------+
Batch sources ----------> | Landing zone       |
APIs, DB snapshots,       | S3/raw tables      |
annotation exports        +---------+----------+
                                    |
                                    v
                          +--------------------+
                          | Spark/Dask jobs    |
                          | quality + features |
                          | + synthetic data   |
                          +---------+----------+
                                    |
                                    v
                          +--------------------+
                          | Iceberg/Delta      |
                          | offline truth      |
                          +---------+----------+
                                    |
                                    v
                              [Merged View] ----> Training ----> Batch inference
                                    ^
Streaming sources ------> +--------------------+
Kafka/Kinesis events      | Flink/Kafka Streams|
prediction logs           | fast features      |
                          +----+----------+----+
                               |          |
                               v          v
                         Redis/DynamoDB  Iceberg/Delta
                         online serving  replay/history
                               |
                               v
                         Online inference ----> Monitoring ----> Feedback
                                                                     |
                                                                     v
                                                        (loops back to Collect)
```

**Growth order — add complexity only when requirements force it:**
1. Start batch-only, with quality gates.
2. Add human labeling once you need supervised targets you don't already have.
3. Add streaming only for features where freshness changes a decision.
4. Add active learning once labeling cost becomes painful.
5. Add synthetic data only for class imbalance, edge cases, or coverage gaps.
6. Add production monitoring and feedback loops as soon as the model ships (this one isn't optional — treat it as part of the initial build).
7. Add agentic auto-remediation only after incident patterns are well understood.
8. Add self-service tooling once multiple teams need the same trusted data.

> ✅ **Design principle:** The architecture should grow from the contract, not from tool enthusiasm.

---

## 16. Common Failure Modes (Full List — Memorize These)

Every one of these traces back to the same root cause: **a stage bypassed the shared contract with the rest of the cycle.**

| Failure Mode | What Actually Goes Wrong |
|---|---|
| Streaming without replay | Online store has latest values, but the lake never got the raw events — can't reproduce them |
| Batch without freshness | Training data is correct, but online decisions are stale because events wait for tomorrow's job |
| Two feature definitions | Batch and stream implementations drift apart → training-serving skew |
| Quality checks only in batch | Real-time data bypasses validation and pollutes online serving |
| No late-event policy | Windows close too early or too late → silent count errors |
| Online store treated as source of truth | Debugging becomes impossible; low-latency state has no history |
| Silent guideline drift | Annotation instructions change mid-project but old/new labels are merged as equivalent |
| Auto-label bias loop | A model pre-labels data, humans rubber-stamp it, and the model's own errors become "ground truth" |
| Untracked synthetic provenance | Synthetic and real data get mixed with no way to separate them later, and evaluation accidentally includes synthetic samples |
| Model collapse | Training on your own model's synthetic output repeatedly, degrading quality/diversity each generation |
| Naive train/test split | Same entity or overlapping time window leaks into both train and test, inflating offline metrics |
| No deletion path | Privacy/retention requirements ignored until a compliance request arrives, and data can't be traced across every table/cache/model it touched |
| Monitoring without feedback wiring | Drift gets detected but there's no path for it to trigger relabeling, resampling, or synthetic generation |
| Byte-level dedup on non-text media | A resized image or re-encoded audio/video clip passes exact-hash dedup untouched, so the "duplicate" trains the model multiple times anyway |
| Unversioned auxiliary model | A captioning/CLIP/ASR model used for cleaning gets silently upgraded or degrades, and corpus quality shifts with no record of why |
| Untracked cross-modal misalignment | Image-caption or audio-transcript pairs are individually clean but mismatched, teaching the model false associations |

---

## 17. The Interview-Ready Answer

**Short version (memorize this):**
> "I think of ML data operations as a closed loop, not a pipeline: data is collected through batch and streaming lanes, validated at each lane's own quality gate, labeled or synthetically augmented to fill gaps, merged into one governed view keyed by event time and shared feature definitions, versioned along with its transformation and generation code, used to train and serve consistently, and monitored in production — with drift, low-confidence predictions, and prediction logs feeding back into collection and labeling so the loop closes. The lanes can use different engines, but they all answer to the same contract."

**Then defend the tradeoffs:**
- Batch is cheaper, easier to debug, better for backfills and reproducibility.
- Streaming is faster but operationally harder and easier to get subtly wrong.
- Labeling and synthetic data both need their own provenance and versioning — they're not "extra," they're part of the same lineage story as raw data.
- The merged view is where correctness lives; online stores are serving state, not historical truth.
- Monitoring is incomplete unless it has a wired path back into collection/labeling — otherwise drift is detected but nothing happens.

> 🧠 Tool names (Spark, Flink, Redis, Iceberg, Airflow, a specific annotation vendor) are implementation detail. The *design* is the separation of stages plus the discipline of a shared contract connecting all of them — lead with that.

---

## 18. Glossary

| Term | Definition |
|---|---|
| **Event time** | The timestamp when something actually happened in the real world |
| **Processing time** | The timestamp when the system happened to handle the event — not the contract |
| **Watermark** | A system's estimate of how far event time has progressed, used to decide when to close a window |
| **ASOF join** | A join that matches each event to the most recent feature value at or before its timestamp |
| **Idempotency** | The property that reprocessing the same event doesn't change the result (no double-counting) |
| **Backpressure** | What a stream processor does when a downstream sink can't keep up |
| **Lakehouse** | Storage layer (Iceberg/Delta/Parquet) combining lake-style scale with table-style versioning/schema evolution |
| **Feature store** | System that serves the same feature definitions to both training (offline) and serving (online) |
| **Training-serving skew** | When the data a model was trained on differs from what it sees in production |
| **Lineage** | The traceable record of where a piece of data came from and what transformed it |
| **Inter-annotator agreement (IAA)** | A measure of how consistently multiple human labelers agree on the same item |
| **Active learning** | Using a model's own uncertainty or disagreement to choose which unlabeled examples to send for human labeling |
| **Synthetic data** | Artificially generated training examples, used to fill coverage gaps real data can't cheaply provide |
| **Model collapse** | Progressive quality/diversity loss from repeatedly training a model on its own generated output |
| **Data drift** | A change in the statistical distribution of input data compared to what a model was trained on |
| **Point-in-time correctness** | The property that a training example only uses information that would have actually been available at that historical moment |
| **Perceptual hash (pHash)** | A hash designed so visually similar images produce similar hash values, unlike exact byte hashing |
| **MinHash / LSH** | A technique (MinHash) plus an indexing method (Locality-Sensitive Hashing) for finding near-duplicate items cheaply at scale |
| **CLIP score** | A similarity score between an image and text caption from a joint vision-language embedding model, used to filter mismatched pairs |
| **VQ-VAE / VQ-GAN** | Models that convert images into discrete tokens via a learned codebook, the image analog of text tokenization |
| **Neural audio codec** | A model (e.g., EnCodec, SoundStream) that converts raw audio into discrete tokens for training |
| **Frame sampling** | Selecting a representative subset of a video's frames (via shot/scene detection) instead of using every frame |
| **Cross-modal alignment** | The correctness of the pairing between two modalities (e.g., does this caption actually describe this image) |
| **Recaptioning** | Regenerating captions for an image/video corpus with a vision-language model when the original scraped text is low quality |

---

## 19. Self-Check Questions

Try answering from memory before checking the sections above.

1. Draw the full cycle from memory — what are the 10 stages, and which one closes the loop back to the start?
2. Why is the online store (Redis/DynamoDB) not considered a source of truth?
3. What's the difference between event time and processing time, and why does it matter for training data?
4. Name the six concepts that streaming design depends on.
5. What's the difference between ML enrichment and synthetic data generation?
6. Why does synthetic data need *more* provenance tracking than real data, not less?
7. Name three things a "view version" must track beyond the raw files.
8. What's a naive mistake in creating train/test splits that inflates offline metrics?
9. Why is monitoring "incomplete" if it doesn't feed back into labeling or collection?
10. Describe the failure mode "auto-label bias loop" — what breaks and why?
11. In the growth order for building this system from scratch, what should never be treated as optional, even in the smallest version?
12. Why does exact-hash deduplication fail for images and audio, and what replaces it for each?
13. What's the difference between recaptioning and text's "recovery rephrasing" as synthetic-data techniques?
14. Why does video annotation cost more per item than any other modality?
15. What is cross-modal alignment, and why is it a stage single-modality pipelines never need?
16. Why does adding non-text modalities change what needs to be tracked in a data version (Rule 5 / Section 7)?

---

### One-line takeaway
**Data operations for ML isn't a pipeline from raw data to a trained model — it's a closed loop where collection, labeling, augmentation, storage, training, serving, and monitoring all answer to one shared contract, and production feeds itself back into the beginning.**