---
layout: post
toc: true
title: "Ray Actors, Catalog Trust Boundaries, and Pipeline Battle Scars"
categories: learnings
tags: [markdown, multimodal, ray, lancedb, gpu, batch-inference, data-engineering, mlops]
---

# Ray Actors, Catalog Trust Boundaries, and Pipeline Battle Scars

This is the second implementation deep dive in my serverless multimodal data lakehouse project.

For the broader architecture, start with [Serverless Multimodal Data Lakehouse]({% post_url 2026-06-01-multimodal-embedding-pipeline-lancedb %}). For the first implementation notes on content-addressed storage, versioning, and deduplication, read [Multimodal Lakehouse Implementation Notes]({% post_url 2026-06-11-multimodal-lakehouse-implementation-notes %}).

This post covers three pieces that mattered a lot once the pipeline moved beyond a local script:

- why Ray stateful actors are the real batch inference story
- why the LanceDB catalog became the trust boundary
- a few small bugs that exposed big assumptions

## Deep Dive 2: Ray Stateful Actors and GPU Scaling

The most common mistake when moving from a local script to a distributed pipeline is how models are loaded.

In a basic script, you load the model once and loop over your data. But in a distributed system, if you pass a simple function to map over your data, the system can end up reloading model weights for every batch. If the model is 2 GB, that means you spend most of your time loading weights into GPU memory and very little time doing inference.

That is the opposite of what a batch inference pipeline should do.

To fix this, the pipeline uses stateful actors in Ray Data. Instead of passing a plain function, I pass a callable Python class. Ray initializes the class once per worker, loads the model in `__init__`, and then routes many batches through the same warm model.

Here is the pattern:

```python
class ImagePreprocessor:
    def __init__(self):
        # Runs once when the Ray actor starts.
        # The CLIP model is loaded into GPU memory here.
        device = "cuda" if torch.cuda.is_available() else "cpu"
        self.model = SentenceTransformer("openai/clip-vit-base-patch32").to(device)

    def __call__(self, batch: dict) -> dict:
        # Runs for every batch of images.
        # The model is already warm, so this path is inference throughput.
        embeddings = self.model.encode(batch["image"])
        return {"id": batch["id"], "embedding": embeddings}
```

Then Ray Data creates a pool of those actors:

```python
embedded_ds = raw_ds.map_batches(
    ImagePreprocessor,
    batch_size=64,
    compute=ray.data.ActorPoolStrategy(size=2),
    num_gpus=1.0,
)
```

That small change is the heart of the batch inference design.

The actor's lifecycle now looks like this:

1. Ray starts the actor.
2. `__init__` loads the model into GPU memory once.
3. Ray streams batches into `__call__`.
4. The same model handles thousands of examples.
5. The actor shuts down only when the job is finished.

This is also where the disaggregated streaming idea becomes concrete. CPU workers read data, decode records, and prepare batches. GPU workers stay inside the hot `ImagePreprocessor` actor, doing inference without repeatedly tearing down and rebuilding model state.

The important operational knobs are:

| Knob | What it controls | What goes wrong |
| --- | --- | --- |
| `batch_size` | How many records each actor processes per call | Too small underuses the GPU; too large causes memory spikes |
| `ActorPoolStrategy(size=...)` | How many hot model actors stay alive | Too few limits throughput; too many exhaust GPU memory |
| `num_gpus` | GPU allocation per actor | Wrong values cause oversubscription or idle hardware |
| model loading in `__init__` | Whether weights are reused across batches | Loading inside `__call__` destroys throughput |

The lesson is that distributed inference is not only about parallelism. It is about keeping expensive state warm.

## Deep Dive 3: The Catalog as the Trust Boundary

This was the lesson that changed how I think about pipelines.

The metadata catalog is the single LanceDB table where every consumer goes to find valid data: search, dataset versioning, sharding, training, and evaluation. That makes the catalog a trust boundary. Anything that enters the catalog is implicitly treated as correct by everything downstream.

My first implementation got this wrong.

```text
connectors -> manifests -> catalog
```

That path bypassed the quality gates.

The problem is subtle but serious. Rows that failed quality checks could still enter the searchable, training-ready catalog. A corrupt image or an empty caption would silently become a valid training sample. The bug was not a crash. It was worse: the system looked like it worked while quietly poisoning every downstream consumer.

The fix was to make the catalog ingest only from the approved, filtered output:

```text
connectors -> manifests -> quality/dedup -> filtered -> catalog
```

The catalog now reads strictly from filtered artifacts, such as:

```text
filtered/*_filtered.parquet
```

Quality gates control exactly what crosses the boundary.

The deeper principle is simple: in a multi-stage pipeline, every stage must consume the previous stage's approved output. It should not reach back to raw data for convenience. The moment one stage skips the boundary, the trust contract collapses, and you can no longer reason about what is in your dataset.

## Battle Scars: The Silly Ones

Some bugs are embarrassing precisely because they are so small: one missing argument, one wrong assumption about a data type, one overloaded column name.

Here are three that cost real debugging time.

## 1. The Missing String Argument

The COCO connector had this line:

```python
raw_row.get()  # what's the key?
```

It should have been:

```python
raw_row.get("cocoid") or idx
```

A single missing argument meant the entire ingestion stage crashed before preprocessing or cataloging could even start.

The lesson: source connectors need tiny smoke tests. Dataset schemas are brittle, and one bad field access can stop the whole pipeline.

## 2. A Pandas Series Is Not a Dict

The shard writer pulled a record from the catalog and did a simple truthiness check:

```python
record = df_indexed.loc[item_id]
if not record:
    continue
```

Pandas did not like that:

```text
ValueError: The truth value of a Series is ambiguous
```

`df.loc[...]` returns a Pandas Series, not a dict. Pandas refuses to guess what "truthy" means for a Series.

The fix was to normalize the row to a dict at the boundary:

```python
row = df_indexed.loc[item_id]
record = row.to_dict()
```

The lesson: catalog rows, manifests, and shards all need explicit interchange shapes. Do not let library-specific objects leak across stage boundaries.

## 3. Text Content Is Not a File Path

Sharding crashed with:

```text
OSError: File name too long
```

The writer treated every `content_path` as a real file:

```python
asset_path = Path(record["content_path"])
asset_path.exists()
```

For images and audio, `content_path` pointed to a CAS file path. For text rows, the same column held the article text. The code tried to call `stat()` on a 2,000-character article as if it were a filename.

The fix was to branch by modality before interpreting the field:

```python
if record["modality"] == "text":
    payload = record["content_path"].encode("utf-8")
else:
    asset_path = Path(record["content_path"])
    payload = asset_path.read_bytes()
```

The lesson: a shared catalog column can mean different things per modality. Downstream code has to respect the modality contract before it interprets a value.

## Battle Scars: The Hard Ones

These were not typos. They were architectural lessons that only surfaced under real conditions: library version drift, deployment filesystems, and embedding-space math.

## 1. CLIP's Return Shape Changed Under Me

Image preprocessing crashed in Modal with:

```text
AttributeError: 'BaseModelOutputWithPooling' object has no attribute 'cpu'
```

My code expected `get_image_features()` to return a plain tensor. In that version of Transformers, it returned a wrapped output object instead.

The fix was a compatibility adapter that accepted the possible return shapes and always normalized them to a tensor:

- a plain tensor
- `image_embeds`
- a pooled output
- a mean-pooled hidden state

Then a second bug hid inside the fix.

I projected a 512-dimensional pooled tensor through a 768-to-512 projection layer and got:

```text
mat1 and mat2 shapes cannot be multiplied
```

The real rule: do not assume "pooler output" means "pre-projection." Inspect the tensor width before applying a projection.

The lesson: model wrappers are conveniences, not contracts.

## 2. LanceDB Could Not Rename Files on a Modal Volume

Catalog creation failed with:

```text
RuntimeError: Unable to rename file: Operation not permitted
```

LanceDB commits data using atomic renames. That is normal on a local disk, but Modal Volume semantics rejected the operation.

The fix was to separate write semantics from persistence:

1. Build the catalog on local `/tmp`.
2. Let LanceDB finish its atomic commit there.
3. Copy the completed directory into the Modal Volume.

The lesson: persistent cloud volumes are not always clean POSIX build directories.

## 3. One Embedding Column Was the Wrong Abstraction

My first catalog had a single `embedding` column.

That looked clean, but it hid a fundamental problem: text and audio embeddings from MiniLM were 384-dimensional, while image and video embeddings from CLIP were 512-dimensional. They also lived in different vector spaces with different distance scales.

Mixing them in one column was meaningless.

The fix was to make the schema honest:

```text
text_vector
clip_vector
```

Search now returns results separately per embedding family instead of pretending all modalities share the same geometry.

The lesson: you cannot paper over an embedding-space mismatch with a shared schema. The architecture has to make the difference visible.

## Running Glossary

**CAS (Content-Addressed Store):** A storage system where files are saved and retrieved using a cryptographic hash of their contents, such as SHA256, instead of a human file name. This gives automatic exact deduplication.

**Manifest:** A lightweight JSON file that lists the contents of a dataset version: hashes, metadata, model configurations, and other pointers. The manifest versions the dataset without copying the physical files.

**Stateful Actor:** A long-lived worker process, managed here by Ray, that loads expensive resources like GPU model weights once and keeps them in memory across many tasks.

**Disaggregated Streaming:** An architecture where CPU preprocessing and GPU inference run on separate workers concurrently, streaming data between stages instead of saving every intermediate step to disk.

**Trust Boundary:** A point in the pipeline where data is certified as valid. Everything downstream relies on that guarantee, so bad data crossing the boundary corrupts the system's assumptions.

**Quality Gate:** A filtering stage that checks rules before data proceeds, such as text length, non-empty captions, decodable images, valid duration, or supported formats.

**Soft Filtering:** Recording filter decisions as metadata, such as `quality_status: "fail"`, instead of deleting rows. This lets thresholds be tuned later without re-ingesting the source data.

**Interchange Shape:** The explicit data shape passed between stages, such as a dict, Arrow table, Parquet row, or manifest record. Making this explicit prevents library-specific objects from leaking across boundaries.

**Compatibility Adapter:** Code at a boundary that normalizes varying return shapes from different library versions into one stable type.

**Atomic Rename:** A filesystem operation databases rely on for safe commits. It is common on local POSIX filesystems, but not guaranteed on all networked or cloud-backed volumes.

**Embedding Space:** The vector geometry produced by a specific model. Vectors from different models, dimensions, or training objectives are not directly comparable.

## Final Takeaway

The hard part of batch inference is not only getting a GPU. It is keeping the GPU fed with warm model state.

The hard part of cataloging is not only writing rows. It is deciding which rows are trusted enough for downstream consumers.

And the hard part of multimodal pipelines is not only supporting four media types. It is remembering that every shared abstraction has modality-specific edges.
