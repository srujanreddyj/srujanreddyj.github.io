# Process engineering email intelligence with DBOS and PostgreSQL

Date: 2026-10-19  
Architecture version: 2.0 proposal  
Status: Condensed from the supplied reference architecture. SDK capabilities, code examples, and integration contracts have not been independently verified or implemented.

This proposal replaces Pi Durable in the [original email intelligence design](autonomous-process-engineering-email-intelligence.md) with DBOS. It also proposes a Python-first application with FastAPI and PostgreSQL. The product goal remains a personalized engineering action desk that groups Outlook conversations, ranks operational work, drafts replies, and improves recommendations from explicit engineer feedback.

## Responsibilities and execution model

```text
Outlook / Microsoft Graph
  → Scheduled mailbox sync → Persist messages and sync state
  → Email intelligence → Signals, context, priority, reply draft
  → Engineering action desk → Authenticated engineer review
  → Feedback learning → Evaluated, versioned preferences
  → Future intelligence workflows

DBOS coordinates workflows, steps, queues, and recovery.
PostgreSQL stores runtime state and separately owned application data.
```

| Component | Proposed responsibility |
| --- | --- |
| Microsoft Graph | OAuth-authorized access to incremental Outlook changes |
| DBOS | Scheduled execution, checkpointed workflows, retries, queues, and durable review waits |
| PostgreSQL | DBOS system state plus logically separate application records |
| Jev | Bounded classification of actionability, urgency, impact, relevance, and response requirements |
| Approved LLM | Thread interpretation, technical context synthesis, and reply drafting |
| Python domain services | Ranking, preference processing, examples, and evaluations |
| FastAPI | Authenticated action-desk APIs, review events, and execution status |
| React or Next.js | Engineer work queue and review controls |
| DBOS tooling and OpenTelemetry | Workflow status, traces, failures, and operating metrics |

Model the core pipeline as explicit workflows containing AI-powered steps. Keep classification, ranking, drafting, and learning logic in independent services. DBOS coordinates execution; it does not determine whether a technical recommendation is correct.

The supplied brief describes DBOS as an SDK with PostgreSQL-backed execution that does not require a separate orchestration server. Confirm the selected SDK version, deployment model, and supported APIs before implementation.

## Four workflow boundaries

| Workflow | Input and work | Durable output |
| --- | --- | --- |
| `OutlookSyncWorkflow` | Read mailbox changes every five minutes, normalize and upsert messages, advance committed sync state | New or changed message records |
| `EmailIntelligenceWorkflow` | Process a message or conversation snapshot; gate, classify, enrich, rank, and selectively draft | Versioned signals, recommended actions, optional draft |
| `EngineerReviewWorkflow` | Wait for authenticated review, validate draft version and decision, record any authorized action | Auditable decision and feedback events |
| `FeedbackLearningWorkflow` | Normalize corrections, deduplicate events, update examples or preferences, evaluate and publish changes | Versioned learning state for later processing |

These boundaries isolate failures. Graph downtime must not block review of existing drafts. LLM failures must not stop ingestion. Learning updates must not alter an approval already tied to a particular draft version.

Proposed workload controls are one active sync per mailbox, ten concurrent classifications, three concurrent drafting tasks, event-driven review waits, and serialized preference updates per engineer. These are initial settings, not DBOS defaults. Verify how the implementation enforces mailbox and engineer scope; a global queue limit alone may not express either requirement.

## Five-minute synchronization and cursor safety

Use native DBOS scheduling or an external scheduler. The supplied example proposes the cron expression `*/5 * * * *` and startup schedule reconciliation through `DBOS.apply_schedules`. Treat those names and signatures as references to verify, not a runnable integration.

Create a mailbox-scoped schedule or dispatch from a schedule to configured mailboxes. Stable workflow identity, a queue, or an application lock must protect against overlapping syncs. Schedule frequency alone does not serialize execution.

Store sync state per mailbox and folder. The proposed record contains `mailbox_id`, `folder_id`, an opaque `delta_url`, `last_synced_at`, and a version for concurrency control. Track continuation state separately from a completed delta cursor when needed.

For each Graph page:

1. Fetch the page from the saved cursor or continuation link.
2. Normalize additions, updates, and removals.
3. Persist the changes and corresponding next-page state or completed cursor atomically where possible.
4. Continue pagination until the change-tracking round completes.

The brief identifies `@odata.nextLink` as continuation and `@odata.deltaLink` as completion. Confirm current Graph behavior and recovery requirements before coding. Never advance past changes that have not been committed. Replaying a committed page must remain safe through stable message identity and upserts.

## PostgreSQL ownership and data model

Start with one PostgreSQL deployment while keeping DBOS-managed state separate from application schemas, migrations, and permissions. Let DBOS manage its internal tables. Separate databases can follow if operational requirements warrant them.

| Application schema | Proposed tables |
| --- | --- |
| `mail` | `sync_cursors`, `messages`, `conversations`, `attachments` |
| `intelligence` | `email_signals`, `action_items`, `rankings`, `reply_drafts` |
| `learning` | `feedback_events`, `engineer_preferences`, `training_examples`, `model_versions` |
| `audit` | `decisions`, `approval_events`, `external_actions` |

The source alternates between `preferences` and `engineer_preferences`; this note uses `engineer_preferences` consistently.

Signals retain message identity, classifier version, actionability, urgency, business impact, technical relevance, response requirements, confidence, and classification time. Constrain normalized scores to 0–1 and define mailbox or tenant scope for identifiers and access checks.

Feedback retains a unique event ID, engineer and message references, correction type, previous and corrected values, explanation, processing state, and timestamps. Preferences retain engineer scope, key, structured value, and version. Preserve prior versions or an audit history so rollback can reconstruct the previous state.

## Intelligence workflow and checkpoint boundaries

Read an immutable or versioned message/conversation snapshot, apply gating, classify signals, retrieve approved context, calculate personalized priority, generate a draft when needed, and persist results for review.

Make external calls and persisted stage results explicit steps. Keep large message bodies, attachments, and retrieved documents outside checkpoint payloads; pass secure references and stable IDs instead.

The source describes reuse of completed DBOS step results after recovery. Failed or interrupted steps may run again. A checkpoint does not make an external API action execute exactly once. Record the message, context, classifier, ranking configuration, and draft versions needed to explain each result.

Mandatory safety and critical-incident review rules remain outside learned preference overrides, as in the original design.

## Human review and Outlook actions

Use a dedicated review workflow so an engineer can respond hours or days later. The supplied design references durable message waits such as `DBOS.recv`; confirm timeout, delivery, restart, and resource behavior for the chosen SDK.

```text
DRAFT_READY → AWAITING_REVIEW → APPROVED or REJECTED
APPROVED → Authorized action, if enabled → Recorded outcome
Review decision and outcome → FEEDBACK_CAPTURED
```

FastAPI authenticates the reviewer, validates authorization, and persists the decision before signaling the workflow. Include a versioned draft ID, decision ID, and reviewer identity. Reject stale approvals when draft content or relevant authorization has changed. Rejection must not lead to an Outlook send action.

Keep application sending disabled initially. Save suggested drafts and let engineers send them manually in Outlook. Any later send integration needs explicit authorization, duplicate protection, and reconciliation for uncertain outcomes.

## Feedback learning

Process feedback as durable application work:

1. Capture priority changes, draft edits, and action decisions.
2. Identify the correction type and its context.
3. Deduplicate events and resolve conflicting updates.
4. Curate examples and propose scoped preference or model changes.
5. Evaluate changes against the baseline and critical-email cases.
6. Activate an accepted version and retain rollback data.

For example, a P3-to-P1 correction on a critical supplier deviation may reveal a missing supplier-criticality feature. Store the correction before deciding whether it warrants a preference change. A single contextual edit does not establish a global rule.

Apply explicit scoped preferences without retraining when appropriate. Gate broader classifier or ranking changes on reviewed evaluation results. Link each future prediction to the exact active configuration so improvement and regressions can be measured.

## Recovery guarantees and tests

| Operation | Required protection |
| --- | --- |
| Scheduled sync | Stable logical run identity and mailbox concurrency control |
| Message ingestion | Scoped unique IDs and idempotent upserts |
| Cursor advancement | Atomic persistence of changes and matching sync state |
| Classification | Checkpointed, versioned results |
| Draft generation | Checkpointing and version-aware reuse |
| Action-card publication | Stable unique publication key |
| Feedback application | Unique event ID and transactional preference update |
| Outlook draft creation | Durable operation record and reconciliation after uncertain responses |
| Optional future sending | Authenticated approval, conservative recovery, and duplicate-send controls |

Test crashes after Graph retrieval, after message persistence, and before cursor advancement. Also test repeated classifier failures, restart during drafting, restart during pending review, duplicate feedback delivery, and ambiguous draft creation. Verify actual persisted records and Outlook effects rather than relying on workflow completion status alone.

## Implementation sequence and open checks

1. Provision PostgreSQL, configure DBOS, and establish schema ownership, secrets, and logging.
2. Implement OAuth, paginated Graph delta sync, safe cursor persistence, and mailbox concurrency controls.
3. Add intelligence workflows, validated classifier outputs, thread context, ranking, and selective drafting.
4. Expose action-desk APIs and review UI with versioned decisions and audit records.
5. Add durable feedback processing, preference versions, evaluation datasets, crash tests, backups, and monitoring.

Organize the Python application around `api`, `workflows`, `steps`, `integrations`, `learning`, `repositories`, and `models`, with separate migrations, frontend, durability tests, and evaluations. This is a proposed structure, not an implemented codebase.

Before implementation, verify DBOS API signatures and version compatibility, Graph permissions and identity behavior, Jev integration, model approval, retention, tenant isolation, durable event delivery, workflow deployment upgrades, and external-action reconciliation. Preserve the original design's encryption, audit, prompt-injection defenses, and critical-email evaluation requirements.

## Author-supplied references

These links came from the supplied brief and remain starting points for verification:

- [DBOS architecture](https://docs.dbos.dev/architecture)
- [Python durable workflows](https://docs.dbos.dev/python/tutorials/workflow-tutorial)
- [Scheduled workflows](https://docs.dbos.dev/python/tutorials/scheduled-workflows)
- [Durable steps and retries](https://docs.dbos.dev/python/tutorials/step-tutorial)
- [Human-in-the-loop agents](https://docs.dbos.dev/python/examples/agent-inbox)
- [AI agent integration](https://docs.dbos.dev/ai/ai-quickstart)

Related notes: [original engineering email proposal](autonomous-process-engineering-email-intelligence.md) and [proactive news curation architecture](proactive-ai-news-curation-pi-durable-jev.md).
