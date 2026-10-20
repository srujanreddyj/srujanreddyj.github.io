# Autonomous process engineering email intelligence agent

Date: 2026-10-19  
Status: Project proposal, condensed from the supplied brief. No implementation or tool compatibility has been verified.

## Purpose

Build a personalized engineering work queue from Outlook email. The agent identifies operational issues, groups related conversations, ranks required actions, retrieves technical context, and drafts replies for engineer review. Engineer corrections improve later recommendations through explicit, versioned feedback processing.

The brief assumes an engineer receives 200–400 emails per day about production, quality, equipment, suppliers, engineering changes, and projects. This is a planning assumption, not measured workload data.

## Proposed processing flow

```text
Outlook → Microsoft Graph incremental sync → Durable orchestrator
  → Normalize → Thread → Gate → Classify → Enrich → Rank → Draft
  → Engineering action desk → Engineer review → Feedback store
  → Evaluate and publish preferences or models → Next processing cycle
```

Start with one orchestrator and specialized tools. Add separate agents only when distinct responsibilities and failure handling justify them.

Treat an engineering issue as the main unit of work. One issue can include several threads, documents, participants, deadlines, and actions. A new message must update the current issue state rather than repeat an obsolete request.

## Outlook ingestion

The proposed MVP runs every five minutes and retrieves changes instead of rescanning the full inbox. The brief proposes this initial endpoint:

```http
GET https://graph.microsoft.com/v1.0/me/mailFolders/inbox/messages/delta
Authorization: Bearer <access_token>
```

Maintain a separate cursor for each mailbox and monitored folder. Follow continuation pages until the sync round completes, then save the completed cursor with persisted messages transactionally where practical. Make ingestion idempotent so retries do not duplicate work. Process edits, moves, and deletions, and honor throttling responses, including `Retry-After`.

Each trigger enqueues a durable job. A queue or lock coordinates overlapping runs. Later, change notifications may reduce latency while periodic delta sync reconciles state.

Confirm current Graph behavior, permissions, cursor recovery, and message identity across folder moves before implementation.

## Classification and reasoning

Keep independent signals for actionability, urgency, business impact, technical relevance, response required, deadline, escalation risk, information confidence, novelty, and personal priority. An urgent issue may need action without an email reply.

| Layer | Proposed responsibility |
| --- | --- |
| Deterministic software | Parse metadata, identify duplicates, match conversations, resolve known equipment or project mappings, parse unambiguous dates, and enforce business rules |
| Jev classifier | Make bounded semantic decisions about actionability, urgency, impact, quality risk, reply requirements, and relevance |
| Enterprise-approved LLM | Summarize threads, compare specifications, interpret reports, retrieve supporting context, explain recommendations, and draft replies |

Jev's SDK decisions must map into application-owned types. The brief's classification payloads are conceptual schemas, not confirmed SDK contracts. Pi Durable and Jev remain proposed dependencies pending capability and deployment checks.

## Priority policy

Apply mandatory review rules first for safety concerns, production stops, critical quality holds, and other approved categories. Low model confidence or learned preferences must never suppress those rules.

Rank other work using normalized signals. The brief suggests this illustrative formula:

```text
P = 0.25U + 0.20B + 0.20A + 0.15R + 0.10D + 0.10H

U = urgency
B = business or production impact
A = actionability
R = relevance to the engineer's responsibilities
D = deadline proximity
H = historical importance inferred from feedback
```

Calibrate weights against reviewed examples. These weights and the brief's sample scores are not measured model results.

## Engineer experience and reply approval

The action desk presents grouped issues, priority explanations, source evidence, deadlines, action items, and drafts. Engineers can drill into the original conversations and correct priority, responsibility, category, response requirements, or technical assumptions.

For replies:

1. Generate a draft from conversation history, approved documents, and current response preferences.
2. Check recipients, evidence, sensitive content, unsupported commitments, and technical claims.
3. Present the draft for engineer review and editing.
4. Let the engineer approve and send the reply.
5. Capture the final response and explicit feedback within approved permissions and retention rules.

The MVP requires human approval before sending. Later automation may cover preapproved, low-risk acknowledgments under company policy. Verify Graph draft creation and send permissions separately before integration.

## Explicit feedback and learning

Storing feedback alone does not change future decisions. A processor must turn reviewed events into preferences, retrievable examples, or evaluated model updates.

| Feedback type | Result | Constraint |
| --- | --- | --- |
| Importance corrections | Scoped priority preferences and weights | Preserve mandatory review rules |
| Draft edits | Response style preferences and accepted examples | Separate stable preferences from factual corrections and one-time changes |
| Classification corrections | Reviewed labels for examples and calibration | Evaluate critical false negatives before promotion |
| Validated domain knowledge | Issue histories and useful approved references | A previous email reply is not approved engineering policy |

Start with immediate, inspectable personalization. Next, retrieve validated classifications and accepted response examples for similar issues. Scope retrieval to authorized users or teams and exclude expired instructions.

Only consider retraining or specialized ranking models after enough reviewed examples exist. Compare candidates against a held-out set and the current baseline. Define acceptance thresholds, retain versions, and support rollback. Higher average accuracy does not justify worse detection of critical issues.

## Proposed storage

Use PostgreSQL for application metadata and feedback, plus the orchestrator's supported checkpoint store.

| Entity | Records |
| --- | --- |
| `mailbox_sync_state` | Mailbox, folder, and delta cursor |
| `email_messages` | Message and conversation IDs, sender, received time, secure content reference |
| `engineering_issues` | Category, status, owner, and severity |
| `issue_email_links` | Relationships between issues and messages |
| `email_signals` | Signal values and producing model or rule version |
| `ranked_actions` | Engineer-specific priorities and explanations |
| `response_drafts` | Draft versions and review status |
| `feedback_events` | Correction, actor, time, reason, and affected entity |
| `engineer_preferences` | Scoped, versioned preferences and weights |
| `learning_examples` | Labels, review status, and originating feedback |
| `learning_versions` | Evaluation results and activation history |
| `agent_executions` | Stage status and checkpoint references |

Retain bodies and attachments only as company policy permits. Preserve enough provenance to explain and reproduce a recommendation.

## Security and operational constraints

- Use OAuth, least-privilege Graph permissions, approved model processing, encryption, audit trails, retention controls, and user-specific data isolation.
- Treat email and attachments as untrusted content. Their text must not become agent instructions.
- Do not authorize automation solely from sender identity.
- Keep mandatory safety and compliance rules outside preference overrides.
- Cite technical evidence and make learning changes inspectable and reversible.
- Do not infer low importance from an unopened or unanswered email.

## Delivery sequence and evidence

| Phase | Deliverable | Evidence required |
| --- | --- | --- |
| 1 | Incremental Outlook ingestion | Reliable sync, retry recovery, and no duplicate processing |
| 2 | Multi-signal classification | High recall on reviewed critical messages |
| 3 | Grouped action desk | Faster identification of important work |
| 4 | Context-aware reply drafts | Useful replies with fewer edits |
| 5 | Feedback processor | Corrections change subsequent recommendations as intended |
| 6 | Evaluated learning releases | Improvement over baseline without critical recall regression |
| 7 | Controlled automation | Approved repetitive actions execute within policy |

Track critical-email recall, action precision, draft acceptance rate, draft edit distance, time to triage, and personalization improvement over baseline. Establish targets before judging success. Learning stages depend on data quality and volume, not a promised weekly timeline.

## Proposed stack and open decisions

The brief proposes Microsoft Graph, a managed scheduler, Pi Durable, TypeScript with Fastify, Jev, an approved LLM, Python with scikit-learn, PostgreSQL with full-text or vector retrieval, React or Next.js, OpenTelemetry, and Azure Container Apps or another approved persistent runtime.

Before implementation, confirm dependency identities and supported APIs, enterprise data-processing approval, mailbox scope, retention policy, critical incident rules, model hosting, permission boundaries, and evaluation thresholds. The source mentions an original video but provides no identifiable reference. This note records the supplied proposal rather than independent technical research.
