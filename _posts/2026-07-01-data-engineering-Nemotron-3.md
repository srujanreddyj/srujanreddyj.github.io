---
layout: post
toc: true
title: "Inside Nemotron 3 Super: The Data Engineering Behind a 25-Trillion-Token Model"
categories: [learnings]
tags: [markdown, data-engineering, llm-pretraining, nemotron, data-pipeline, synthetic-data, deduplication]
---

# Inside Nemotron 3 Super: The Data Engineering Behind a 25-Trillion-Token Model

I went through NVIDIA's technical report and public material on Nemotron 3 Super, and the thing that stood out most wasn't the model architecture. It was this: **the hardest engineering problem was building the corpus, not designing the network.**

I came across a twitter account praising the efforts of NVIDIA engineering team of data, so I had to look at it, felt like my interest area of data operations  — the model is the easy part to talk about at a party, and the pipeline underneath it is the part that actually decided whether the model would be any good.

Nemotron 3 Super was pretrained on roughly **25 trillion tokens**. It was a large-scale ETL system — ingestion, cleaning, scoring, deduplication, safety filtering, synthetic generation, mixture design, tokenization, and sharding, built specifically to turn messy internet-scale text into something a model could learn efficiently from. This post walks through that system stage by stage.

## The Shape of the Corpus

The 25T tokens weren't one dataset. They were a blend of web crawl, curated high-quality websites, books, academic papers, source code, math datasets, Wikipedia, and — notably — a meaningful slice of **synthetic data** generated specifically for reasoning and instruction-following.

The training itself ran in **two phases**, and this is one of the more interesting design choices in the whole pipeline:

```text
Phase 1 — 20T tokens
Goal: diversity and broad coverage

Phase 2 — 5T tokens
Goal: higher-quality sources, benchmark accuracy refinement
```

Higher-quality datasets got proportionally more weight in the mixture; similar-quality sources got similar weight. In other words, the curriculum wasn't "shuffle everything together" — it was closer to how a person might study broadly first and then drill into the material that actually shows up on the test.

## Stage 1: Collection — More Sources Than a Single Crawl

The source list reads less like "a dataset" and more like a small library: Common Crawl, high-quality websites, books, academic papers, source code, math datasets, Wikipedia, StackOverflow/GitHub, curated web crawls (things like OpenWebText and Reddit-derived corpora), multilingual data, PDF-derived text, and synthetic SFT-style data. NVIDIA has been releasing a number of these datasets separately under the broader Nemotron project.

The lesson for anyone building a data pipeline at any scale: **diversity of source is a design decision, not an accident of what was easy to scrape.**

## Stage 2: Cleaning — Where Most of the Engineering Effort Actually Lives

This is the stage that eats the most engineering time, and it's almost entirely unglamorous.

**HTML-to-text extraction.** Raw web pages are mostly not content — they're navigation bars, ad slots, cookie banners, and tracking scripts. NVIDIA's Nemotron-CC pipeline uses **jusText** to pull the actual article body out of the HTML noise.

```text
Raw HTML page
      |
      v
jusText extraction (strip nav, ads, boilerplate)
      |
      v
Main article/body text
```

**Boilerplate removal.** Even after extraction, the same handful of phrases — "Contact Us," "Privacy Policy," "Accept Cookies," "Subscribe Now" — show up across millions of pages and can quietly dominate a naive corpus if nobody bothers to strip them out.

**Language detection.** Fast, high-throughput language ID (NVIDIA uses **FastText** for this) decides what stays. Anything that isn't a supported language gets dropped before it costs any further compute.

**Encoding normalization.** Everything gets forced into UTF-8, Unicode-normalized, and stripped of broken or invalid characters — the kind of unglamorous data-hygiene work that never shows up in a paper's abstract but breaks everything downstream if it's skipped.

**Format extraction.** PDFs, Word docs, XML, and Markdown all get converted into plain text before anything else happens to them.

## Stage 3: Quality Scoring — Not Just a Keep/Discard Filter

This is one of NVIDIA's more genuinely novel contributions. Instead of a binary "keep or throw away," the Nemotron-CC pipeline scores documents using **perplexity, ensemble quality classifiers,** and features like grammatical quality, repetition, spam indicators, and information density — and then sorts documents into **quality bands** rather than a single cutoff:

```text
document
   |
   v
feature extraction
   |
   v
quality classifiers
   |
   v
bucket: high_quality / medium_quality / low_quality_but_recoverable / discard
```

That "recoverable" bucket is the interesting one, and it leads directly into the next stage.

## Stage 4: Synthetic Data as a Recovery Tool, Not Just a Filler

Most people think of synthetic data as "generate more examples to fix class imbalance." NVIDIA's pipeline does something more specific: it uses classifier ensembling plus **LLM-based rephrasing** to take documents that carry useful facts but are poorly written, and rewrite them into clean, usable training text.

```text
Low/medium-quality document
   |
   v
Quality model: "useful facts, poor writing"
   |
   v
LLM rephrasing / rewriting
   |
   v
Re-score
   |
   v
Add to curated corpus
```

That reframes the filtering step: it's not just subtraction (throw away the bad stuff), it's **transformation** (turn weak raw material into something stronger). This is a genuinely different posture from classic ETL, where a failed quality check almost always just means "drop the row."

NVIDIA went further and built **capability-targeted synthetic datasets** — generating and validating problems specifically for algorithmic reasoning, formal logic, economics, and multiple-choice-style QA, released separately as a specialized synthetic dataset collection. This is synthetic data generation aimed at a capability gap, not a coverage gap.

## Stage 5: Deduplication — The Internet Repeats Itself Constantly

A single news story can end up copied across hundreds of sites. Without deduplication, a model doesn't get 600 data points — it gets one data point memorized 600 times, which is a very different (and worse) thing for generalization.

The pipeline runs two layers:

- **Exact deduplication** — hash every document (SHA/MD5-style fingerprinting) and keep one copy per hash.
- **Fuzzy/near-duplicate deduplication** — compute **MinHash signatures** and use **locality-sensitive hashing (LSH)** to catch documents that are, say, 90–98% similar but not byte-identical.

```text
document_id, content_hash, minhash_signature, dedup_cluster_id, canonical_document_flag
```

## Stage 6: Safety, Toxicity, and PII Filtering

Two related but distinct filters run here. Safety/toxicity classifiers remove hate speech, pornography, malware, phishing content, spam, and low-quality AI-generated pages — using trained classifiers rather than keyword blocklists, which catch far less at this scale. Separately, large-scale PII detection strips phone numbers, emails, SSNs, physical addresses, API keys, and secrets — both for legal compliance and to reduce the risk of the model memorizing anything identifiable.

## Stage 7: Document Classification and Balancing

Before sampling, documents get classified into categories — books, code, math, science, conversation, news, forums, legal, medical, and so on. Raw internet data is wildly skewed toward low-value categories (a huge share is navigation boilerplate and SEO spam even after cleaning), so the pipeline explicitly rebalances the mixture toward higher-value categories like books, code, and science rather than training on whatever the internet happens to produce most of.

## Stage 8: Curriculum and Mixture Design

This is where data engineering turns into training strategy. Every source in the pipeline carries metadata — domain, quality score, language, token count, and a weight for each training phase — and the two-phase curriculum described earlier is built directly from those weights: broad and diverse in phase one, weighted toward quality and benchmark-relevant sources in phase two.

## Stage 9–11: Tokenization, Packing, and Sharding

Once the text is clean, scored, deduplicated, and balanced, it stops being text.

```text
Cleaned document
     |
     v
Tokenizer
     |
     v
Token IDs
     |
     v
Packed into fixed-length sequences (8192 / 16384 tokens)
     |
     v
Sharded binary files (bin/idx, Parquet, JSONL)
```

Sequence packing matters for GPU efficiency — training on ragged, variable-length documents wastes compute, so documents get packed into dense fixed-length blocks. Sharding then splits the packed dataset across tens of thousands of files so that each GPU node can read its own shard independently, which is what makes training at this scale parallelizable in the first place.

NVIDIA's own tooling draws a clean line here: **NeMo Curator** owns the large-scale curation work — deduplication, quality filtering, language ID, PII removal — while a separate module (`nemotron.data_prep`) owns the "last mile": tokenization, packing, chat templating, and loss-mask creation, running on Ray for distributed processing with deterministic shard plans, resumable jobs, and checksum verification.

## Stage 12: Post-Training Data Operations

Pretraining isn't the end of the data story. After the base model exists, a second wave of data preparation kicks in for supervised fine-tuning (SFT), reinforcement learning (RL), preference data, reward modeling, tool-use trajectories, and agentic workflow examples — much of it synthetically generated rather than human-collected, since the target behaviors (following instructions, using tools, reasoning step by step) are easier to generate and verify than to source at scale from the wild.

## The Whole Pipeline, End to End

```text
Raw Internet Data
        |
        v
Data Collection (web, books, code, math, academic, synthetic)
        |
        v
HTML/PDF/Text Extraction
        |
        v
Cleaning & Normalization
        |
        v
Language Detection
        |
        v
Quality Scoring
        |
        v
Synthetic Rephrasing (recover "useful but poorly written" docs)
        |
        v
Deduplication (exact + MinHash/LSH)
        |
        v
Toxicity & PII Filtering
        |
        v
Document Classification & Balancing
        |
        v
Curriculum & Mixture Weighting (Phase 1 / Phase 2)
        |
        v
Tokenization
        |
        v
Sequence Packing
        |
        v
Sharding
        |
        v
25 Trillion Training Tokens
        |
        v
Distributed GPU Training
```

## Why This Matters If You Work in Data Engineering

Strip away the LLM framing and this is a familiar shape: ingestion from heterogeneous sources, parsing and standardization, ML-based quality scoring, deduplication, classification, weighted sampling, and a storage layer optimized for how the "consumer" — in this case a GPU training job instead of a BI dashboard — actually reads data.

| ETL Concept | Nemotron Pipeline Equivalent |
|---|---|
| Ingestion | Crawl dumps, HF datasets, PDFs, code repos |
| Parsing | HTML/PDF/Markdown/code extraction (jusText) |
| Standardization | UTF-8, Unicode normalization, schema cleanup |
| Filtering | Language ID, spam, safety, PII |
| Deduplication | Exact hash + fuzzy MinHash/LSH |
| Scoring | Quality classifiers, perplexity, domain score |
| Enrichment | Domain labels, quality buckets, metadata |
| Synthetic generation | Rephrasing, QA generation, reasoning data |
| Sampling | Weighted blend by source/domain/quality/phase |
| Tokenization | Text → token IDs |
| Packing | Fixed-length sequence construction |
| Sharding | Distributed training files |
| Validation | Checksums, manifests, token counts |

The scale is different — trillions of tokens instead of terabytes of business data — but the concerns are the same ones every data platform eventually has to answer: is this correct, is this deduplicated, is this balanced, can I reproduce it, and can the thing consuming it actually read it efficiently.

## Takeaway

The model architecture in the technical report is genuinely interesting. But if you read it as a data engineer, the real story is the pipeline: a two-phase curriculum built on a corpus that was collected from a dozen source types, cleaned, scored into quality bands, selectively *rewritten* rather than just filtered, deduplicated at both the exact and fuzzy level, rebalanced away from the internet's natural skew, and packed into shards a GPU cluster could consume in parallel.

Training the model was the last step. Building a corpus worth training on was the project.

---

**Sources referenced:**
- NVIDIA, *Nemotron 3 Super Technical Report* (research.nvidia.com)
- NVIDIA Developer Blog, *Building Nemotron-CC: A High-Quality Trillion-Token Dataset*
- NVIDIA Docs, *Nemotron Data Preparation Module*
- NVIDIA-NeMo/Nemotron GitHub repository
- [Study Guide: The Nemotron 3 Super Data Engineering Pipeline](/learnings/2026/07/04/nemotron-3-super-data-engineering-pipeline-study-guide.html)
