---
layout: page
title: Selected data engineering work
description: Case studies in CDC, Apache Iceberg, Amazon Kinesis, and query optimization by Srujan Jabbireddy.
permalink: /case-studies/
body_class: case-studies-page
---

<section class="case-hero" aria-labelledby="case-hero-title">
  <p class="section-kicker">Senior data engineer · selected work</p>
  <h2 id="case-hero-title">I build data systems that stay correct while they get faster.</h2>
  <p class="case-hero-lede">Production case studies across change data capture, lakehouse architecture, event streaming, and query processing—plus a personal multimodal systems project built for the joy of learning how the pieces really work. Start with the outcomes; open the technical notes for the design decisions and failure modes.</p>
  <div class="case-hero-actions">
    <a class="button button-primary" href="#case-studies">View case studies</a>
    <a class="button button-secondary" href="mailto:{{ site.email }}">Contact me</a>
    <a class="case-inline-link" href="{{ '/resume/' | relative_url }}">Resume <span aria-hidden="true">↗</span></a>
  </div>
</section>

<section class="impact-ribbon" aria-label="Selected impact">
  <div><strong>$126K</strong><span>annual platform savings</span></div>
  <div><strong>74%</strong><span>less data scanned</span></div>
  <div><strong>5d → 1d</strong><span>pipeline freshness</span></div>
  <div><strong>96%</strong><span>fewer schema incidents</span></div>
</section>

<section class="case-index" id="case-studies" aria-labelledby="case-index-title">
  <header class="case-section-heading">
    <p class="section-kicker">Case study index</p>
    <h2 id="case-index-title">The short version</h2>
  </header>

  <div class="case-card-grid">
    <a class="case-card" href="#cdc-iceberg">
      <span class="case-number">01</span>
      <span class="case-card-label">uShip · platform modernization</span>
      <h3>CDC to Iceberg</h3>
      <p>Removed duplicate data movement, made replay safe, and shifted heavy processing off premium warehouse compute.</p>
      <span class="case-card-result">67% lower Snowflake compute</span>
    </a>

    <a class="case-card" href="#kinesis-streaming">
      <span class="case-number">02</span>
      <span class="case-card-label">uShip · event ingestion</span>
      <h3>Kinesis event path</h3>
      <p>Built a durable route from application events to governed analytics storage with replay and failure isolation.</p>
      <span class="case-card-result">EventBridge → Kinesis → S3</span>
    </a>

    <a class="case-card" href="#query-optimization">
      <span class="case-number">03</span>
      <span class="case-card-label">Meta · analytical processing</span>
      <h3>Query-path redesign</h3>
      <p>Matched physical processing to real investigation patterns and replaced full refreshes with bounded incremental work.</p>
      <span class="case-card-result">~5 days to ~1 day</span>
    </a>

    <a class="case-card case-card-personal" href="#multimodal-lakehouse">
      <span class="case-number">04</span>
      <span class="case-card-label">Personal project · ML data infrastructure</span>
      <h3>Multimodal lakehouse</h3>
      <p>Built a 12-stage pipeline that turns text, images, video, and audio into traceable, deduplicated, training-ready features.</p>
      <span class="case-card-result">Ray · Modal · LanceDB · WebDataset</span>
    </a>
  </div>
</section>

<article class="case-study" id="cdc-iceberg">
  <header class="case-study-header">
    <div>
      <p class="case-number">01 · CDC + Apache Iceberg</p>
      <h2>Re-architecting the lakehouse around the work that mattered</h2>
    </div>
    <p class="case-study-summary">At uShip, replication failures created duplicate events, full-history backfills, and an expensive recovery loop. I redesigned the path so AWS DMS change data landed in S3, Glue merged it into Iceberg, and Snowflake remained the analyst-facing query layer.</p>
  </header>

  <div class="architecture-panel">
    <div class="architecture-caption">
      <span>Architecture</span>
      <p>Durable raw changes, sequence-aware state, and a serving layer that no longer owns heavy ingestion.</p>
    </div>
    <svg class="architecture-diagram" viewBox="0 0 960 270" role="img" aria-labelledby="iceberg-diagram-title iceberg-diagram-desc">
      <title id="iceberg-diagram-title">CDC to Iceberg architecture</title>
      <desc id="iceberg-diagram-desc">Operational databases flow through AWS DMS into an immutable S3 landing zone. Glue Spark deduplicates changes by sequence and merges them into Apache Iceberg. Snowflake reads the catalog-linked Iceberg tables for analytics.</desc>
      <defs>
        <marker id="arrow-iceberg" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse"><path d="M 0 0 L 10 5 L 0 10 z" /></marker>
      </defs>
      <g class="diagram-connector" marker-end="url(#arrow-iceberg)">
        <path d="M190 114 H276"/><path d="M432 114 H518"/><path d="M674 114 H760"/>
      </g>
      <g class="diagram-node">
        <rect x="24" y="56" width="166" height="116" rx="12"/><text x="107" y="95" text-anchor="middle" class="diagram-label">OLTP databases</text><text x="107" y="123" text-anchor="middle" class="diagram-detail">quotes · bids</text><text x="107" y="146" text-anchor="middle" class="diagram-detail">shipment status</text>
        <rect x="276" y="56" width="156" height="116" rx="12"/><text x="354" y="95" text-anchor="middle" class="diagram-label">AWS DMS</text><text x="354" y="123" text-anchor="middle" class="diagram-detail">log-based CDC</text><text x="354" y="146" text-anchor="middle" class="diagram-detail">change sequence</text>
        <rect x="518" y="56" width="156" height="116" rx="12"/><text x="596" y="90" text-anchor="middle" class="diagram-label">S3 + Iceberg</text><text x="596" y="118" text-anchor="middle" class="diagram-detail">Glue MERGE</text><text x="596" y="141" text-anchor="middle" class="diagram-detail">atomic snapshots</text>
        <rect x="760" y="56" width="176" height="116" rx="12"/><text x="848" y="95" text-anchor="middle" class="diagram-label">Snowflake</text><text x="848" y="123" text-anchor="middle" class="diagram-detail">catalog-linked</text><text x="848" y="146" text-anchor="middle" class="diagram-detail">analytics serving</text>
      </g>
      <g class="diagram-note"><text x="480" y="226" text-anchor="middle">Deduplicate each micro-batch by primary key + highest DMS sequence before MERGE</text></g>
    </svg>
  </div>

  <div class="case-results" aria-label="CDC to Iceberg results">
    <div><strong>67%</strong><span>lower Snowflake compute</span></div>
    <div><strong>~40%</strong><span>faster top-20 queries</span></div>
    <div><strong>74%</strong><span>less data scanned</span></div>
    <div><strong>~$10.5K/mo</strong><span>net savings after Glue</span></div>
  </div>

  <div class="case-detail-grid">
    <section>
      <h3>What I changed</h3>
      <p>I removed the Fivetran-to-Snowflake replication and warehouse-side deduplication loop. CDC changes landed cheaply in object storage, then a single Glue writer produced atomic Iceberg snapshots. Hidden partitioning and manifest statistics let readers skip irrelevant files; compaction converted small micro-batch files into query-efficient files.</p>
    </section>
    <section>
      <h3>The correctness trap</h3>
      <p>CDC delivery order is not business order. When multiple updates for one shipment arrived in a micro-batch, a naïve merge could overwrite a fresh price with an older one. The fix was to rank changes per primary key by the DMS sequence and merge only the latest change. Row counts would not have caught this: the row existed, but its state was stale.</p>
    </section>
    <section>
      <h3>Migration safety</h3>
      <p>I used parallel runs and reconciled row counts, aggregates, key distributions, samples, and critical business queries before cutting over each table. The new path carried the burden of proof because more than 100 downstream consumers could not be disrupted.</p>
    </section>
    <section class="case-tradeoff">
      <h3>Trade-off accepted</h3>
      <p>Decoupling storage and compute reduced cost, but introduced lakehouse operations: compaction, snapshot expiry, orphan-file cleanup, catalog monitoring, and cross-engine debugging. Snowflake external reads could also trail native-table performance. For this workload, the lower cost and safer evolution justified that operational surface.</p>
    </section>
  </div>
</article>

<article class="case-study" id="kinesis-streaming">
  <header class="case-study-header">
    <div>
      <p class="case-number">02 · Amazon Kinesis</p>
      <h2>Separating event arrival from analytical processing</h2>
    </div>
    <p class="case-study-summary">I created an AWS-native path that accepted events through EventBridge, buffered them in Kinesis, landed immutable batches in S3, and loaded governed tables through Snowpipe. The design separated producer availability from warehouse availability and kept a replayable source outside the warehouse.</p>
  </header>

  <div class="architecture-panel">
    <div class="architecture-caption">
      <span>Architecture</span>
      <p>A buffered event log protects producers; object storage provides durable replay before warehouse loading.</p>
    </div>
    <svg class="architecture-diagram" viewBox="0 0 960 270" role="img" aria-labelledby="kinesis-diagram-title kinesis-diagram-desc">
      <title id="kinesis-diagram-title">Kinesis event ingestion architecture</title>
      <desc id="kinesis-diagram-desc">Application events are routed by EventBridge to Kinesis, delivered to an immutable S3 landing zone, then loaded through Snowpipe into modeled Snowflake tables. Failed records are isolated for replay.</desc>
      <defs>
        <marker id="arrow-kinesis" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse"><path d="M 0 0 L 10 5 L 0 10 z" /></marker>
      </defs>
      <g class="diagram-connector" marker-end="url(#arrow-kinesis)">
        <path d="M166 104 H214"/><path d="M370 104 H418"/><path d="M574 104 H622"/><path d="M778 104 H826"/>
      </g>
      <g class="diagram-node diagram-node-compact">
        <rect x="18" y="52" width="148" height="104" rx="12"/><text x="92" y="94" text-anchor="middle" class="diagram-label">Producers</text><text x="92" y="122" text-anchor="middle" class="diagram-detail">domain events</text>
        <rect x="214" y="52" width="156" height="104" rx="12"/><text x="292" y="94" text-anchor="middle" class="diagram-label">EventBridge</text><text x="292" y="122" text-anchor="middle" class="diagram-detail">routing rules</text>
        <rect x="418" y="52" width="156" height="104" rx="12"/><text x="496" y="94" text-anchor="middle" class="diagram-label">Kinesis</text><text x="496" y="122" text-anchor="middle" class="diagram-detail">buffer + ordering</text>
        <rect x="622" y="52" width="156" height="104" rx="12"/><text x="700" y="94" text-anchor="middle" class="diagram-label">Amazon S3</text><text x="700" y="122" text-anchor="middle" class="diagram-detail">immutable landing</text>
        <rect x="826" y="52" width="116" height="104" rx="12"/><text x="884" y="94" text-anchor="middle" class="diagram-label">Snowflake</text><text x="884" y="122" text-anchor="middle" class="diagram-detail">Snowpipe</text>
      </g>
      <g class="diagram-note"><text x="480" y="220" text-anchor="middle">Load only after durable landing · failed records remain replayable</text></g>
    </svg>
  </div>

  <div class="case-detail-grid">
    <section>
      <h3>Why a stream</h3>
      <p>Kinesis absorbed bursts and prevented analytical consumers from becoming a synchronous dependency of event producers. Partition keys preserved ordering where it mattered, while independent consumers could advance at their own rate.</p>
    </section>
    <section>
      <h3>Why land before loading</h3>
      <p>S3 was the durable handoff. Warehouse retries did not require producers to resend events, and a transformation bug could be repaired by replaying the original payloads. Snowpipe then handled continuous ingestion from files rather than coupling directly to the live stream.</p>
    </section>
    <section>
      <h3>Correctness controls</h3>
      <p>Event identifiers and idempotent merges make retries safe. Schema validation and quarantine keep malformed payloads out of curated tables. Freshness, rejected-event counts, duplicates, and source-to-target reconciliation distinguish pipeline health from data correctness.</p>
    </section>
    <section class="case-tradeoff">
      <h3>Trade-off accepted</h3>
      <p>The extra landing step adds latency and another operational boundary. In return, it isolates failures and provides deterministic replay—a better fit for analytics than making the warehouse part of the producer request path.</p>
    </section>
  </div>
</article>

<article class="case-study" id="query-optimization">
  <header class="case-study-header">
    <div>
      <p class="case-number">03 · Query optimization</p>
      <h2>Making the processing model match the questions</h2>
    </div>
    <p class="case-study-summary">At Meta, a framework metadata and metrics pipeline took roughly five days to produce data engineers needed for investigations. I replaced history-scaled full refreshes with bounded incremental processing and aligned the physical layout with component- and version-centric access patterns.</p>
  </header>

  <div class="architecture-panel comparison-panel">
    <div class="architecture-caption">
      <span>Processing redesign</span>
      <p>The main optimization was less work—not a larger cluster.</p>
    </div>
    <div class="before-after" role="img" aria-label="Before: full history scans over date-centric partitions. After: incremental correction windows over component- and version-aware partitions, followed by shadow validation and curated investigation views.">
      <div class="before-after-lane before-lane">
        <span class="lane-label">Before</span>
        <div class="lane-step"><strong>Full history</strong><span>rescanned each run</span></div>
        <span class="lane-arrow">→</span>
        <div class="lane-step"><strong>Date partitions</strong><span>poor query fit</span></div>
        <span class="lane-arrow">→</span>
        <div class="lane-step"><strong>~5 days</strong><span>stale for debugging</span></div>
      </div>
      <div class="before-after-lane after-lane">
        <span class="lane-label">After</span>
        <div class="lane-step"><strong>Changed data</strong><span>+ correction window</span></div>
        <span class="lane-arrow">→</span>
        <div class="lane-step"><strong>Component + version</strong><span>aligned access path</span></div>
        <span class="lane-arrow">→</span>
        <div class="lane-step"><strong>~1 day</strong><span>same-day support</span></div>
      </div>
    </div>
  </div>

  <div class="case-results case-results-three" aria-label="Query redesign results">
    <div><strong>~5d → ~1d</strong><span>pipeline freshness</span></div>
    <div><strong>Full → Δ</strong><span>history scans to changed data</span></div>
    <div><strong>Daily</strong><span>matched decision cadence</span></div>
  </div>

  <div class="case-detail-grid">
    <section>
      <h3>Diagnosis before tuning</h3>
      <p>The old pipeline's cost grew with all retained history, while engineers investigated by component and framework version. More compute would only accelerate a mismatched plan. I bounded each run to changed records plus a correction window and organized processing around the dimensions people actually filtered and joined.</p>
    </section>
    <section>
      <h3>Practical query choices</h3>
      <p>I used approximate distinct counts where the decision required percentage deltas rather than exact cardinality. I also bounded work to the roughly six or seven live framework versions because older versions represented less than 1% of users. Both choices removed expensive computation without weakening the decision.</p>
    </section>
    <section>
      <h3>The silent failure mode</h3>
      <p>A mutable timestamp used as a high-water mark can move past late or corrected records. The pipeline stays green while valid data disappears. I caught that risk by running the incremental path in shadow mode against full rebuilds, then added bounded correction windows and periodic reconciliation.</p>
    </section>
    <section class="case-tradeoff">
      <h3>Trade-off accepted</h3>
      <p>I stopped at a one-day batch SLA because the consumer workflow was daily. Streaming would have increased state, late-event, and operational complexity for freshness no one could use. The goal was the fastest trustworthy answer inside the decision window, not the lowest possible latency.</p>
    </section>
  </div>
</article>

<article class="case-study personal-case-study" id="multimodal-lakehouse">
  <header class="case-study-header">
    <div>
      <p class="case-number">04 · Personal project</p>
      <h2>Building a lakehouse for data a model can trust</h2>
    </div>
    <div>
      <p class="case-study-summary">I built this project to learn what sits between “embed some files” and reusable multimodal training infrastructure. One pipeline ingests text, images, video, and audio; preserves stable identity and provenance; runs distributed preprocessing and GPU inference; then produces both searchable features and streaming-friendly training shards.</p>
      <div class="case-project-links">
        <a href="{% post_url 2026-06-01-multimodal-embedding-pipeline-lancedb %}">Read the overview</a>
        <a href="https://github.com/srujanreddyj/distributed-embedding-search-lakehouse">View source</a>
      </div>
    </div>
  </header>

  <div class="architecture-panel">
    <div class="architecture-caption">
      <span>12-stage system, compressed</span>
      <p>Durable identity, warm GPU workers, a governed catalog, and a separate layout for training throughput.</p>
    </div>
    <svg class="architecture-diagram" viewBox="0 0 960 286" role="img" aria-labelledby="multimodal-diagram-title multimodal-diagram-desc">
      <title id="multimodal-diagram-title">Multimodal lakehouse architecture</title>
      <desc id="multimodal-diagram-desc">Text, image, video, and audio connectors write immutable content-addressed assets. Ray actors perform quality checks, deduplication, and embedding on Modal. Approved records enter a LanceDB catalog, version manifests select stable datasets, and WebDataset shards feed training loaders.</desc>
      <defs>
        <marker id="arrow-multimodal" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse"><path d="M 0 0 L 10 5 L 0 10 z" /></marker>
      </defs>
      <g class="diagram-connector" marker-end="url(#arrow-multimodal)">
        <path d="M174 116 H212"/><path d="M382 116 H420"/><path d="M590 116 H628"/><path d="M798 116 H836"/>
      </g>
      <g class="diagram-node diagram-node-compact">
        <rect x="18" y="58" width="156" height="116" rx="12"/><text x="96" y="92" text-anchor="middle" class="diagram-label">4 modalities</text><text x="96" y="120" text-anchor="middle" class="diagram-detail">text · image</text><text x="96" y="143" text-anchor="middle" class="diagram-detail">video · audio</text>
        <rect x="212" y="58" width="170" height="116" rx="12"/><text x="297" y="92" text-anchor="middle" class="diagram-label">CAS + quality</text><text x="297" y="120" text-anchor="middle" class="diagram-detail">SHA256 identity</text><text x="297" y="143" text-anchor="middle" class="diagram-detail">soft filtering</text>
        <rect x="420" y="58" width="170" height="116" rx="12"/><text x="505" y="92" text-anchor="middle" class="diagram-label">Ray on Modal</text><text x="505" y="120" text-anchor="middle" class="diagram-detail">warm GPU actors</text><text x="505" y="143" text-anchor="middle" class="diagram-detail">embeddings + FAISS</text>
        <rect x="628" y="58" width="170" height="116" rx="12"/><text x="713" y="92" text-anchor="middle" class="diagram-label">LanceDB catalog</text><text x="713" y="120" text-anchor="middle" class="diagram-detail">vectors + metadata</text><text x="713" y="143" text-anchor="middle" class="diagram-detail">trust boundary</text>
        <rect x="836" y="58" width="106" height="116" rx="12"/><text x="889" y="92" text-anchor="middle" class="diagram-label">Training</text><text x="889" y="120" text-anchor="middle" class="diagram-detail">manifests</text><text x="889" y="143" text-anchor="middle" class="diagram-detail">shards</text>
      </g>
      <g class="diagram-note"><text x="480" y="230" text-anchor="middle">Search reads the catalog · training streams materialized WebDataset shards</text><text x="480" y="253" text-anchor="middle">Every output retains content hash, model version, quality decision, and provenance</text></g>
    </svg>
  </div>

  <div class="case-results" aria-label="Multimodal project scope">
    <div><strong>4</strong><span>media modalities</span></div>
    <div><strong>12</strong><span>pipeline stages</span></div>
    <div><strong>~10K</strong><span>records at demo scale</span></div>
    <div><strong>~$0.15</strong><span>observed demo GPU cost</span></div>
  </div>

  <div class="case-detail-grid">
    <section>
      <h3>Identity before features</h3>
      <p>Raw assets are immutable blobs addressed by SHA256. Exact duplicates across sources are stored once, and a dataset version is a JSON manifest of content hashes rather than another copied media folder. Branching a training mix adds metadata, not terabytes of duplicated assets.</p>
    </section>
    <section>
      <h3>Keeping expensive state warm</h3>
      <p>Ray Data uses stateful actors so each worker loads its embedding model once and serves many batches. CPU stages decode and validate media; GPU actors focus on inference. Batch size, actor count, and memory limits are explicit controls rather than hidden magic.</p>
    </section>
    <section>
      <h3>The catalog as a trust boundary</h3>
      <p>My first design let raw manifests reach the LanceDB catalog before quality gates. That meant corrupt or rejected samples could look valid downstream. I changed the contract so only approved filtered artifacts enter the catalog, and every search, version, shard, training job, and evaluation reads from that governed boundary.</p>
    </section>
    <section>
      <h3>Search and training need different layouts</h3>
      <p>LanceDB keeps embeddings and structured metadata together for filtering, similarity search, and provenance. Training needs fewer large sequential reads, so frozen manifests materialize into WebDataset tar shards. Shards optimize delivery; the catalog and manifest remain the source of truth.</p>
    </section>
    <section>
      <h3>Deduplication in cost order</h3>
      <p>SHA256 removes exact duplicates before inference. FAISS then finds semantic neighbors across the shared embedding layer, while quality decisions remain soft metadata instead of destructive deletes. Near-exact perceptual and fingerprint-based passes are documented next steps, not claimed as complete.</p>
    </section>
    <section class="case-tradeoff">
      <h3>Demo scale, production-shaped</h3>
      <p>The measured run is intentionally small: roughly 10,000 records on ephemeral L4 GPUs for about $0.15. It does not prove billion-item throughput. What it validates is the system shape—stable identity, explicit stage contracts, reusable model actors, auditable curation, versioned datasets, and separate serving layouts.</p>
    </section>
  </div>

  <div class="case-reading-list" aria-label="Multimodal project technical notes">
    <span>Technical series</span>
    <a href="{% post_url 2026-06-11-multimodal-lakehouse-implementation-notes %}">Storage, versioning, and dedup</a>
    <a href="{% post_url 2026-06-12-ray-actors-catalog-trust-boundary %}">Ray actors and trust boundaries</a>
    <a href="{% post_url 2026-06-18-training-ready-multimodal-data-shards-loaders %}">Training shards and loaders</a>
  </div>
</article>

<section class="case-contact" aria-labelledby="case-contact-title">
  <p class="section-kicker">Let’s talk systems</p>
  <h2 id="case-contact-title">Looking for someone who can connect architecture decisions to measurable outcomes?</h2>
  <p>I’m interested in senior data engineering, data platform, and infrastructure roles where correctness, cost, and operability all matter.</p>
  <div class="case-hero-actions">
    <a class="button button-primary" href="mailto:{{ site.email }}">Email me</a>
    <a class="button button-secondary" href="https://www.linkedin.com/in/{{ site.linkedin_username }}/">LinkedIn</a>
  </div>
</section>

<p class="case-disclosure">Architecture details are intentionally generalized to protect proprietary information. Published figures are limited to confirmed results or deliberately approximate values; approximate values are marked with “~”.</p>
