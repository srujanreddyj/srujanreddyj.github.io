---
layout: post
toc: true
title: "Dex: Design Change"
date: 2026-09-20
permalink: /references/dex-design-change/
noindex: true
sitemap: false
categories: [references]
tags: [dex-workflow, coding-agents, workflow]
---


# Design Change

Move from **what exists?** to **what should exist?** This is the judgment stage. Do not combine it with repository discovery or production implementation.

## Inputs

Require:

- `.pstack/tasks/<task-id>/task.md`,
- a `READY` `.pstack/tasks/<task-id>/research.md`,
- every `PROVEN` learning-test report relevant to the design.

Start in a fresh context. Read the artifacts before source. Open source only to verify a disputed claim or inspect a signature needed for the design.

If research is missing ownership, flow, or state facts, return `RESEARCH_INCOMPLETE` with the exact question to investigate. Do not compensate with a speculative design.

If pstack is installed, use `architect` to compare whole-system shapes. Use `why` when changing established ownership or layering whose rationale matters. Do not let either skill continue into implementation.

## 1. Define the design problem

State:

- desired observable behavior,
- non-goals,
- invariants that must remain true,
- compatibility and rollout constraints,
- actors and concurrent operations,
- confirmed external contracts.

Distinguish requirements from preferences. A short ticket does not imply permission to invent product behavior.

## 2. Model the change before choosing files

Sketch the caller's use first, then:

- authoritative state and ownership,
- states, events, and transitions,
- API and wire contracts,
- failure, retry, cancellation, and concurrency behavior,
- data migration or compatibility boundaries,
- UI states and accessibility when applicable,
- observability needed to detect failure.

Prefer one explicit domain model over synchronized booleans spread across layers.

## 3. Compare whole-shape alternatives

Produce at least two materially different shapes when the decision is non-obvious. Do not disguise minor variations as alternatives.

For each option assess:

- ownership and dependency direction,
- consistency with existing system boundaries,
- behavior under failure and concurrent actors,
- amount of duplicated contract logic,
- migration and rollback cost,
- testability and runtime observability,
- blast radius.

Reject an option explicitly. If the best choice depends on unknown external behavior, stop with `NEEDS_LEARNING_TEST` and provide the exact falsifiable question. If it depends on product taste, policy, or an irreversible tradeoff no experiment can settle, stop with `NEEDS_HUMAN_DECISION` and provide concise options plus a recommendation.

## 4. Write the design artifact

Write `.pstack/tasks/<task-id>/design.md`:

```markdown
# <Task title> design

Status: READY | NEEDS_LEARNING_TEST | NEEDS_HUMAN_DECISION | RESEARCH_INCOMPLETE
Revision: <integer>
Inputs: research.md r<revision>, <learning reports and revisions>
Review: PENDING | ACCEPTED | NOT_REQUIRED
Reviewed by: <human name/handle, or reason review is not required>

## Desired behavior
...

## Non-goals
- ...

## Constraints and invariants
| Constraint | Source | Design consequence |
| --- | --- | --- |

## Proposed system
<Flow and ownership model.>

## State transitions
| Current state | Event | Next state | Side effects | Failure behavior |
| --- | --- | --- | --- | --- |

## Contracts
### Caller experience
...
### Types and signatures
...
### API, event, and persistence changes
...

## Alternatives
### Option A: <name>
...
### Option B: <name>
...

## Decision
<Chosen option and why it wins.>

## Risks and mitigations
| Risk | Consequence | Mitigation or proof |
| --- | --- | --- |

## Learning-test evidence
- `<report path>` proves ...

## Human decisions
| Question | Options | Recommendation | Decision |
| --- | --- | --- | --- |

## Verification strategy
<How the real behavior and important failures will be observed.>
```

`READY` means a fresh planning agent can derive implementation slices without making architecture decisions. It does not by itself mean a human accepted the design. For `COMPLEX` and `HIGH_RISK` tasks, planning requires `Review: ACCEPTED`. Record the reviewer and material decisions in the artifact. `NOT_REQUIRED` is reserved for routes whose coordinator explicitly does not require design review.

On iteration, increment `Revision`, update input revisions, and archive the replaced artifact under `.pstack/tasks/<task-id>/archive/design-r<old-revision>.md`. Mark any existing `plan.md`, `implementation.md`, and `verification.md` as `STALE` before handoff.

## 5. Pressure-test the design

Before `READY`, challenge:

- multiple simultaneous actors,
- stale clients and out-of-order events,
- partial failure between boundaries,
- retries and idempotency,
- interruption during transitional states,
- old/new version compatibility,
- whether a lower layer already owns the hard behavior,
- whether the design can be verified vertically.

Return the artifact path, status, chosen shape, rejected alternative, evidence used, and unresolved decisions. Do not write production code or a file-by-file implementation plan.
