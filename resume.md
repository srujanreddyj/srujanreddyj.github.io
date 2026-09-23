---
layout: page
title: Professional snapshot
description: Srujan Jabbireddy's senior data engineering experience, selected impact, and technical focus.
permalink: /resume/
body_class: resume-page
---

<section class="resume-hero">
  <p class="section-kicker">Srujan Jabbireddy · Senior Data Engineer</p>
  <p class="resume-deck">I design data platforms, lakehouses, streaming systems, and ML data infrastructure with an emphasis on correctness, measurable efficiency, and safe evolution.</p>
  <div class="hero-actions">
    <a class="button button-primary" href="https://read.cv/srujan">View full CV</a>
    <a class="button button-secondary" href="mailto:{{ site.email }}">{{ site.email }}</a>
    <a class="hero-text-link" href="https://www.linkedin.com/in/{{ site.linkedin_username }}/">LinkedIn ↗</a>
  </div>
</section>

<section class="resume-impact" aria-label="Selected impact">
  <div><strong>$126K</strong><span>annual platform savings</span></div>
  <div><strong>74%</strong><span>less data scanned</span></div>
  <div><strong>5d → 1d</strong><span>pipeline freshness</span></div>
  <div><strong>96%</strong><span>fewer schema incidents</span></div>
</section>

<section class="resume-section-block">
  <p class="section-kicker">Experience themes</p>
  <div class="resume-experience-grid">
    <article>
      <span>Data platform modernization</span>
      <h2>Lakehouse architecture and CDC</h2>
      <p>Redesigned change-data paths around durable object storage and Apache Iceberg, reducing warehouse compute while preserving safe replay, sequence-aware state, and migration controls for downstream consumers.</p>
    </article>
    <article>
      <span>Event infrastructure</span>
      <h2>Streaming ingestion and recovery</h2>
      <p>Built an AWS-native path using EventBridge, Kinesis, S3, and Snowpipe so event producers, durable storage, and analytical consumers could fail and recover independently.</p>
    </article>
    <article>
      <span>Analytical processing</span>
      <h2>Incremental query-path design</h2>
      <p>Replaced full-history processing with bounded correction windows and layouts aligned to investigation patterns, improving freshness without introducing streaming complexity the workflow did not need.</p>
    </article>
    <article>
      <span>ML data infrastructure</span>
      <h2>Traceable multimodal datasets</h2>
      <p>Designed a multimodal pipeline with stable content identity, quality gates, reusable GPU workers, vector search, dataset manifests, provenance, and training-oriented materialization.</p>
    </article>
  </div>
</section>

<section class="resume-section-block resume-capabilities">
  <div>
    <p class="section-kicker">Core capabilities</p>
    <h2>Systems I work on</h2>
  </div>
  <ul>
    <li>Batch and streaming data pipelines</li>
    <li>Change data capture and replay safety</li>
    <li>Lakehouse tables and query optimization</li>
    <li>Data quality, lineage, and reconciliation</li>
    <li>Distributed preprocessing and ML data loading</li>
    <li>Dataset identity, versioning, and provenance</li>
  </ul>
</section>

<section class="resume-section-block resume-tools">
  <p class="section-kicker">Selected tools</p>
  <p>Python · SQL · Spark · Ray · Airflow · AWS DMS · Kinesis · S3 · Glue · Apache Iceberg · Snowflake · LanceDB · FAISS · PyTorch · WebDataset</p>
</section>

<section class="resume-next">
  <div>
    <p class="section-kicker">Evidence, not keyword lists</p>
    <h2>See the architecture, decisions, and results.</h2>
  </div>
  <a class="button button-primary" href="{{ '/case-studies/' | relative_url }}">Explore selected work</a>
</section>
