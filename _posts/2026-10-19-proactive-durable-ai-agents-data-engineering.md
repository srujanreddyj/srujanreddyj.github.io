---
layout: post
title: "15 high-value data engineering use cases for proactive durable AI agents"
visibility: public
published: true
content_type: guide
topics: [data-platforms, ai-ml-systems]
tags: [data-engineering, ai-agents, durable-execution, observability]
summary: "Fifteen proposed agent workflows for data operations, with a reusable architecture, an incident-investigation example, and a staged approach to autonomy."
featured: false
toc: true
permalink: /guides/proactive-durable-ai-agents-data-engineering.html
---

Adapted from the [shared ChatGPT guide](https://chatgpt.com/s/t_6ad6f2be3318819193c1bd092f2eccf5).
The scenarios, incidents, and priority ratings below are design proposals and illustrative examples, not measured production results.

A proactive data engineering agent starts work from a schedule, an event, or an alert. It can collect evidence before an engineer starts an investigation. A durable agent preserves workflow progress so an interrupted investigation can resume.

Together, these capabilities could support a data operations platform that monitors pipelines, investigates problems, handles approved maintenance, and escalates consequential decisions. SQL queries, statistical methods, and existing monitoring systems still perform the work they handle well. Model reasoning helps where interpreting unstructured evidence adds value.

## A reusable agent architecture

Most scenarios below share the same workflow:

```text
Schedules, events, webhooks, and monitoring alerts
                         |
                         v
             Durable workflow orchestrator
        Persistent state, checkpoints, retries, resumption
                         |
                         v
       Collect -> Gate -> Deduplicate -> Analyze -> Rank -> Act
                         |
             +-----------+-----------+
             |                       |
             v                       v
       Persistent history       Human oversight
       Patterns and feedback    Approvals and exceptions
```

Gating decides whether an event needs further investigation. Deduplication groups repeated reports of the same problem. Rules and lightweight classifiers can handle routine decisions before a model processes expensive or ambiguous cases.

The shared source names Pi Durable for orchestration and Jev for semantic classification. Those names reflect its proposed implementation, not requirements of this architecture or a verification of those tools. The requirements are persistent progress, explicit action policies, evidence collection, and recovery from interruption.

## Fifteen scenarios worth building

### 1. Pipeline incident investigator

Monitor Airflow, Databricks Jobs, Spark, and other ETL pipelines. When a job fails or slows, collect logs, locate the failed stage, compare previous incidents, and propose a response.

**Example:** A PySpark job fails with an executor out-of-memory error. The agent compares executor logs, shuffle statistics, and input growth to distinguish possible skew from broader memory pressure.

**Possible actions:** Classify the incident, collect diagnostics, create an issue, and execute a tightly controlled retry when policy allows it.

### 2. Continuous data quality guardian

Monitor completeness, uniqueness, freshness, validity, referential integrity, and volume anomalies. Use business context to distinguish urgent failures from routine deviations.

**Example:** A transactions table has 20% fewer rows than expected. The agent checks historical load patterns, upstream ingestion, and recent deployments before reporting suspected missing data.

**Possible actions:** Run extra checks, identify affected datasets, alert owners, and quarantine suspicious batches where authorized.

### 3. Schema drift and contract monitor

Detect changes in source tables, Kafka schemas, API payloads, and Parquet or Delta files. Compare the change with downstream contracts to assess compatibility.

**Example:** A source changes `customer_id` from a numeric field to a string. The agent checks dependent transformations and contracts for assumptions that may no longer hold.

**Possible actions:** Produce compatibility reports, recommend transformations, and prepare migration pull requests for review.

### 4. Spark and Databricks performance optimization agent

Analyze execution plans, task durations, skew, shuffle spill, partition sizes, and job configuration.

**Example:** A nightly aggregation grows from 20 minutes to 70 minutes. The agent compares plans and task metrics to investigate a larger shuffle stage or an inefficient join.

**Possible actions:** Recommend benchmarks, propose partitioning or join changes, and test approved alternatives in staging.

### 5. Cloud data platform cost optimization agent

Correlate job history, warehouse usage, storage costs, billing exports, and schedules to identify wasted compute.

**Example:** A Databricks job consumes more DBUs after a configuration change without processing more data. The agent identifies the regression and proposes a cheaper configuration for evaluation.

**Possible actions:** Estimate savings, recommend schedules, flag idle compute, and prepare approved configuration changes.

### 6. Data freshness and SLA prediction agent

Compare ingestion lag, job dependencies, runtimes, and delivery deadlines to estimate whether a dataset will miss its service-level agreement.

**Example:** A report due at 7 AM depends on five upstream jobs. At 5:30 AM, one delayed source makes a freshness miss likely.

**Possible actions:** Notify the responsible team, increase monitoring frequency, and start approved recovery workflows.

### 7. Data lineage and root-cause analysis agent

Query dataset lineage to trace how failures affect tables, dashboards, APIs, and machine learning features.

**Example:** A dashboard reports incorrect revenue. The agent traces the metric through transformation models, intermediate tables, ingestion jobs, and source changes to find the first inconsistent stage.

**Possible actions:** Generate impact reports, identify suspected causes, and notify affected data-product owners.

### 8. CDC and Kafka streaming reliability agent

Watch change data capture pipelines, consumer lag, throughput, dead-letter queues, schema changes, connector status, and checkpoint health.

**Example:** Consumer lag grows after a source-database traffic spike. The agent checks whether the backlog reflects a transient burst or sustained processing undercapacity.

**Possible actions:** Diagnose connector errors, inspect approved dead-letter samples, and recommend scaling or replay procedures.

### 9. Backfill and data recovery planner

Detect missing partitions, incomplete loads, failed incremental jobs, and reconciliation mismatches. Determine which date ranges or keys need recovery.

**Example:** A job fails for three days, then later runs succeed. The agent checks watermark history to identify records that remain missing.

**Possible actions:** Estimate affected partitions, prepare dry runs, and execute approved idempotent backfills. An idempotent backfill preserves the intended result if the same recovery request runs again.

### 10. Data catalog, metadata, and documentation agent

Scan database metadata, transformation models, repositories, and catalogs for undocumented datasets or stale descriptions.

**Example:** A curated customer table appears without documentation. The agent reads its schema, lineage, transformation logic, and usage to draft a description and data dictionary.

**Possible actions:** Draft documentation, flag missing owners, and propose catalog updates.

### 11. Sensitive data discovery and governance agent

Inspect metadata and approved samples for potential personally identifiable information, sensitive identifiers, financial data, or policy violations.

**Example:** An analytics table unexpectedly includes email addresses and phone numbers. The agent flags the classification mismatch and investigates downstream exposure.

**Possible actions:** Report risks, draft policy updates, and escalate suspected access-control violations. Access changes require authorization.

### 12. Data pipeline code review agent

Review SQL, PySpark, dbt, and pipeline configuration changes for correctness, performance, reliability, and compatibility.

**Example:** A pull request removes a partition filter from a large incremental transformation. The agent identifies the expanded scan and explains the evidence in its review.

**Possible actions:** Review changes, recommend tests, and flag risky migrations. Production approval remains a separate decision.

### 13. Data reconciliation agent

Compare source and target systems during migrations, ingestion, financial processing, or warehouse modernization.

**Example:** PostgreSQL and BigQuery row counts match after a migration, but transaction totals differ. The agent compares date and business-key groups to isolate discrepancies.

**Possible actions:** Run reconciliation queries, identify mismatched groups, and generate exception reports.

### 14. Business metric anomaly and data reliability agent

Monitor revenue, orders, transactions, active users, or conversion rates. Investigate whether unusual movements reflect business events or broken data processing.

**Example:** Daily revenue drops by 30%. The agent checks ingestion completeness, metric logic changes, source availability, and historical seasonality.

**Possible actions:** Explain anomalies with supporting evidence and route business questions and data incidents to the appropriate teams.

### 15. Incident knowledge and runbook agent

Use previous incidents, execution traces, remediation decisions, and engineer feedback to maintain operational knowledge.

**Example:** A Spark job fails because of a recurring upstream dependency problem. The agent finds previous resolutions and checks whether the same recovery procedure applies.

**Possible actions:** Summarize incidents, draft runbooks, connect recurring issues, and recommend validated recovery procedures.

## Which scenarios to build first

Priority depends on incident frequency, available evidence, investigation cost, and how clearly success can be measured. The following ratings preserve the shared guide's qualitative assessment. They are not measured financial returns or guarantees of safe autonomy.

| Scenario | Potential business value | Complexity | Potential for bounded autonomy |
| --- | --- | --- | --- |
| Pipeline incident investigation | Very high | Medium | High |
| Data quality guardian | Very high | Medium | High |
| Schema drift monitor | High | Low to medium | High |
| Spark performance optimization | Very high | High | Medium |
| Cloud cost optimization | Very high | Medium | Medium |
| Freshness and SLA prediction | High | Medium | High |
| Lineage and impact analysis | High | High | Medium |
| Streaming reliability | Very high | High | Medium |
| Backfill recovery planner | High | High | Medium |
| Catalog documentation | Medium | Low | High |
| Sensitive data governance | Very high | High | Low to medium |
| Pipeline code review | High | Medium | High |
| Data reconciliation | Very high | Medium | High |
| Business metric anomalies | Very high | High | Medium |
| Incident knowledge agent | High | Low to medium | High |

Pipeline incident investigation, data quality, and schema drift are plausible starting projects. They have identifiable triggers, observable inputs, and outcomes engineers can review. They can also share lineage, incident history, and notification mechanisms.

## Reference design: pipeline incident investigation

Consider a nightly Databricks pipeline that normally completes in 25 minutes but fails after 18 minutes. A failed-job event starts an investigation.

```text
Pipeline failure event
          |
          v
Create or find incident; persist workflow state
          |
     +----+----------------+----------------+
     |                     |                |
     v                     v                v
Logs and metrics    Incident history    Data lineage
     |                     |                |
     +---------------------+----------------+
                           |
                           v
               Classify and compare evidence
                           |
                           v
               Rank diagnoses; propose action
                           |
                 +---------+---------+
                 |                   |
                 v                   v
       Preapproved recovery     Human approval
       Bounded, idempotent      Risky or uncertain changes
```

### Tooling integration

Airflow supports callbacks for failure and retry events. These can provide investigation triggers. Callback behavior has limits: UI or CLI state changes do not trigger callbacks in the same way as execution-driven state changes. See the [Airflow callback documentation](https://airflow.apache.org/docs/apache-airflow/stable/administration-and-deployment/logging-monitoring/callbacks.html).

Databricks system tables expose operational records for jobs, billing, and lineage. Table availability and access depend on the account configuration and permissions. These records are useful evidence, but their freshness must suit the workflow. See the [Databricks system table reference](https://docs.databricks.com/aws/en/admin/system-tables/).

OpenLineage models jobs, runs, and datasets across compatible processing systems. That model can help connect an incident with affected datasets. See the [OpenLineage object model](https://github.com/OpenLineage/OpenLineage/blob/main/website/docs/spec/object-model.md).

### An illustrative incident report

| Field | Example |
| --- | --- |
| Pipeline | `customer_transactions_daily` |
| Status | Review required |
| Suspected cause | Executor memory pressure during a large shuffle |
| Alternative to investigate | Data skew or a recent configuration change |
| Proposed action | Run a non-production diagnostic comparison and prepare an optimization recommendation |

Evidence to validate includes executor out-of-memory errors, shuffle spill, task skew, input-volume trends, and recent code or compute changes. An error message identifies a symptom. The diagnosis needs evidence that distinguishes competing causes.

Changing production cluster configuration remains an approval decision in this example.

### Durable execution requirements

Persist each investigation's progress. If a process stops after collecting logs but before producing a report, it can resume from saved results. Repeated failure events for the same pipeline run should attach to the same incident.

Workflow recovery also needs an explicit policy for external effects. If a retry request succeeds but the agent crashes before saving its result, replay must not trigger an uncontrolled second retry. Use stable operation identifiers, idempotent tools, or a reconciliation check for uncertain outcomes. Durable progress alone does not provide exactly-once external effects.

## A shared platform for the scenarios

The common runtime can serve specialized agents without duplicating event handling, persistence, permissions, and evaluation for each use case.

```text
           Databricks, Airflow, Kafka, cloud systems
                              |
                              v
                    Events and schedules
                              |
                              v
                     Durable agent runtime
                              |
                 +------------+------------+
                 |            |            |
                 v            v            v
             Pipeline      Quality       Schema
              agent         agent         agent
                 |            |            |
                 +------------+------------+
                              |
                              v
                      Shared tool registry
                              |
                 +------------+------------+
                 |            |            |
             Metadata     Rules and     Data stores
             and lineage  model reasoning and history
                 |            |            |
                 +------------+------------+
                              |
                              v
                    Actions and approvals
                              |
                              v
                    Feedback and evaluation
```

Shared capabilities include identity, access control, execution state, retry policies, model routing, tool permissions, audit logs, evaluation, and feedback. Each specialized agent supplies its inputs, tools, classification criteria, and action policy.

### A staged approach to autonomy

| Stage | Agent responsibility | Engineer responsibility |
| --- | --- | --- |
| Observe | Collect and classify events | Investigate and resolve |
| Diagnose | Correlate evidence and propose causes | Review diagnosis and remediation |
| Assist | Execute approved diagnostics and prepare actions | Approve consequential changes |
| Controlled autonomy | Perform preapproved reversible operations | Handle exceptions and audit outcomes |
| Optimized operations | Coordinate bounded workflows across systems | Govern policies, risk, and performance |

Destructive operations, schema migrations, production access changes, and large backfills need separate action policies. A durable workflow can recover execution progress without making its decisions correct or safe.

## An implementation scenario to evaluate

For a first pipeline incident investigator, define the following contract before granting recovery permissions:

| Part | Proposed behavior |
| --- | --- |
| Trigger | Job failure callback or monitoring alert |
| Inputs | Run logs, Spark metrics, deployment history, and historical incidents |
| Gating | Ignore explicitly recognized harmless retries and group repeated events for one incident |
| Investigation | Compare the failed stage, resource use, code changes, and similar incidents |
| Output | Diagnosis with evidence and, if policy permits, one bounded retry request |
| Success measure | Time from failure event to a reviewed diagnosis, with diagnosis quality tracked separately |

Define diagnosis time explicitly rather than calling it MTTD, which commonly means mean time to detect. Faster reports are useful only if engineers can trust their evidence.

The first three scenarios can form a data reliability platform because they share evidence and ownership information. Expand to performance, cost, streaming recovery, or governance when the shared runtime has demonstrated reliable behavior on the initial workflows.
