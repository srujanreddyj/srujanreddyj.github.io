# Proactive AI news curation using Pi Durable and Jev

Date: 2026-10-19  
Status: Technical project proposal, condensed from the supplied notes. Claims about the demonstration and SDKs below come from those notes and have not been independently verified.

Reference supplied by the author: [My Jev Pi Durable Agent CURATES News: HYPE, FACT, or SIGNAL](https://www.youtube.com/watch?v=OLqP8jxJ0Wc), by IndyDevDan.

## Purpose

Build a scheduled news intelligence service that collects articles, removes repeated coverage, assesses evidence, ranks useful developments, and adapts to explicit user feedback. A persistent backend owns execution and state; browser and terminal clients can disconnect without stopping work.

Begin with autonomous collection and curation while users review results and adjust preferences. Expand autonomy only after accuracy, recovery, and cost controls have measurable evidence.

## Architecture and processing flow

```text
Scheduler → API → Durable orchestrator
  → Gather → Gate → Deduplicate → Research → Rank → Present
  → User feedback → Versioned preferences → Future sweeps

Browser and terminal clients ↔ API and event stream ↔ Persistent state
```

Use deterministic processing before semantic analysis where possible. In particular, exact URL and content-hash checks can eliminate repeated articles before paid classification. Semantic comparison then groups different articles about the same event while preserving source links.

| Component | Proposed responsibility |
| --- | --- |
| Scheduler | Submit recurring work with a stable execution-window key |
| API | Accept jobs, expose persisted results, and authorize client requests |
| Pi Durable | Coordinate checkpointed tasks and recovery, subject to SDK verification |
| Jev | Make bounded, typed semantic decisions, subject to API verification |
| Generative LLM | Research claims, synthesize evidence, and explain selected stories |
| SQLite | Store initial application data and supported runtime state |
| Browser and terminal clients | Read shared state, submit feedback, and change preferences |

Start with a modular monolith that separates ingestion, classification, research, ranking, persistence, and orchestration. The proposed stack is TypeScript with Node.js, Fastify or Express, React or Vue, cron, Server-Sent Events, structured logs, and OpenTelemetry. Use persistent storage and a runtime suitable for background jobs.

## Pipeline decisions

1. **Schedule.** Submit a durable sweep and return a queued execution ID promptly. The supplied notes describe a one-minute trigger, but source polling intervals can be longer. Prevent overlapping runs from processing the same work.
2. **Gather.** Connect RSS, Atom, supported APIs, official blogs, research metadata, and permitted page retrieval. Normalize source, external ID, title, URL, publication time, collection time, summary, and content.
3. **Gate.** Assess relevance, concrete releases, actionability, and promotional content. A proposed policy processes relevance scores of 0.80–1.00 immediately, 0.50–0.79 when capacity permits, samples or defers 0.20–0.49, and removes lower scores from the active queue. Calibrate these illustrative thresholds and audit rejected items.
4. **Deduplicate.** Apply canonical URL, source ID, and content-hash checks, followed by semantic story clustering. Avoid merging distinct developments merely because they concern the same company or topic.
5. **Research.** Extract important claims, find primary evidence, compare sources, and record supported, conflicting, or unresolved findings. Review uncertain high-impact claims. Model confidence is not proof of truth.
6. **Rank.** Combine independent scores with personal interests, freshness, novelty, source quality, and diversity.
7. **Present.** Display a small feed with source links, evidence status, related coverage, score explanations, and feedback controls. The supplied notes report a configurable seven-card sweep limit in the demonstration.
8. **Learn.** Record feedback, update scoped preferences through an explicit processor, and use the resulting version in later sweeps.

## Independent scores and personalized ranking

| Dimension | Meaning |
| --- | --- |
| Hype | Disproportionate attention or exaggerated claims |
| Fact | Strength of verifiable supporting evidence |
| Signal | Relevance and actionability for a particular user |

These dimensions can overlap. A factual announcement can contain both useful details and exaggerated marketing. Store evidence status separately from classification confidence.

The brief proposes this formula, with inputs normalized to 0–1:

```text
R = 0.35S + 0.25P + 0.15F + 0.10N + 0.10T - 0.05H

S = actionable signal
P = personalized topic relevance
F = factual evidence strength
N = novelty
T = timeliness
H = hype penalty
```

These weights are illustrative. Evaluate them against reviewed stories before adoption. Add source trust, duplicate penalties, freshness decay, or diversity controls only where evidence supports the change.

Users can vote on stories, adjust topics and sources, or submit instructions. The supplied notes describe a Gemini keyword-weight change from 1.2 to 1.3 in the demonstration. Preference updates change ranking inputs; they do not establish that a foundation model has learned or improved.

## Data and API design

The following schema and routes are proposals, not recovered contracts from the demonstrated application.

| Table | Records |
| --- | --- |
| `news_sources` | Source configuration, weight, enabled state, and polling state |
| `raw_articles` | Source IDs, canonical URLs, content hashes, content, and timestamps |
| `story_clusters` | Shared events and canonical story descriptions |
| `article_clusters` | Article-to-story relationships |
| `article_classifications` | Scores, evidence status, and classifier version |
| `user_preferences` | User-specific topic weights and preference versions |
| `news_rankings` | User, story, ranking score, and ranking time |
| `news_feedback` | User, story or article, feedback type, and event time |
| `pipeline_executions` | Sweep status, start and finish times, and errors |
| `agent_events` | Execution-linked actions and audit events |

Keep runtime checkpoints logically separate from news application tables, even if both initially use SQLite. Enforce unique canonical URLs, required metadata, foreign keys, valid score ranges, UTC timestamps, and versioned classifier outputs. Preserve source and model provenance. PostgreSQL is a later option for application data if workload warrants it; runtime storage must follow the framework's supported contract.

| Method | Proposed endpoint | Purpose |
| --- | --- | --- |
| `POST` | `/api/news/sweep` | Queue a sweep with an idempotency key |
| `GET` | `/api/news` | Retrieve curated stories |
| `GET` | `/api/news/timeline` | Retrieve chronology |
| `GET` | `/api/news/:id` | Retrieve story details |
| `POST` | `/api/news/:id/feedback` | Record feedback |
| `GET`, `PATCH` | `/api/preferences` | Read or update scoped preferences |
| `POST` | `/api/agent/messages` | Submit instructions |
| `GET` | `/api/agent/events` | Stream updates |
| `GET` | `/api/executions` | List sweep history |
| `GET` | `/api/executions/:id` | Inspect one execution |

Derive user scope from authenticated identity. On client reconnection, provide a current state snapshot rather than assuming every streamed event arrived.

## Durability, security, and cost controls

Wrapping one ordinary asynchronous function in a durable agent does not establish recovery at every operation. Define checkpoint boundaries for individual steps and make writes safe to retry. Use stable publication keys so a retried sweep does not duplicate cards. Track external side effects and reconcile uncertain outcomes.

Retry transient source and model failures with backoff. Quarantine malformed input, defer unavailable research, limit database transaction duration, and version concurrent preference updates. Back up persistent state and test restoration.

Authenticate APIs, authorize each user's data, protect secrets, rate-limit requests, and restrict outbound retrieval to prevent server-side request forgery. Treat retrieved pages as untrusted data, never as authority to run tools or override instructions. Require approval for high-impact actions outside the curation workflow.

Track collection, classification, research, orchestration, and infrastructure costs separately. Cache classifications by content hash and model version, avoid repeated research on a story, batch requests where supported, and enforce daily inference budgets. The brief's example of 1,000 articles becoming seven published cards is illustrative. Claims that Jev is fast or cheap do not establish production benchmarks.

## Verification and delivery

| Phase | Deliverable | Observable acceptance evidence |
| --- | --- | --- |
| 1 | Ingestion and persistence | At least three sources; valid normalized records; exact duplicates removed |
| 2 | Jev classification and ranking | Reviewed relevance and signal results; configurable preferences affect order |
| 3 | Durable orchestration | Scheduled work continues without clients and resumes after interruption |
| 4 | Feed, timeline, feedback, and events | Clients share persisted results; votes and preference changes affect later runs |
| 5 | Operational controls | Measured costs, recovery tests, access checks, and tested backups |

Test source failures, model timeouts, duplicate scheduler requests, process termination mid-sweep, interrupted publication, disconnected browsers, and feedback submitted during a sweep. Require consistent persisted state, no unexplained data loss, and no unwanted duplicate publication.

Evaluate precision, recall, F1, duplicate-detection precision, confidence calibration, false negatives, and NDCG@K, which measures the relevance order of the top K results. Measure sweep duration, rejection rate, model calls, cost per published story, recovery count, and human interventions. Useful signal rate is positively reviewed relevant cards divided by all user-reviewed cards; report that it covers reviewed cards only.

Compare personalized ranking with a static baseline on held-out labels. Audit filtered stories and account for feedback bias: users cannot vote on stories the system never shows them. Add automated research, semantic clustering, and more adaptive ranking after the core workflow proves reliable.

## Source status and related project

The supplied brief describes scheduled execution, browser and terminal interaction, preference changes, specialized tools, and local and cloud demonstrations. It describes SQLite-backed persistence and Jev classification. This note does not independently confirm those observations. Exact schemas, endpoints, scoring formulas, directory structures, security controls, and evaluation plans are proposed additions. End-to-end automated deployment is not established.

Author-supplied implementation references, retained for later verification:

- [Pi Durable SDK documentation](https://github.com/earendil-works/pi/blob/main/packages/durable/README.md)
- [Durable Pi agent network](https://github.com/disler/durable-pi)
- [Jev Model technical overview](https://github.com/jevmodel/typesafe-ai)

The same collection, filtering, issue grouping, ranking, and feedback design informs the [process engineering email intelligence proposal](autonomous-process-engineering-email-intelligence.md). A data operations variant could collect pipeline failures and quality exceptions, research logs and lineage, and suggest incident actions. Production changes would require separate authorization.
