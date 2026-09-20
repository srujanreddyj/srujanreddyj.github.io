---
layout: post
toc: true
title: "Dex Workflow (Coordinator)"
date: 2026-09-20
permalink: /references/dex-workflow/
noindex: true
sitemap: false
categories: [references]
tags: [dex-workflow, coding-agents, workflow]
---


# Dex Workflow

Use the smallest rigorous workflow that matches the task. This is a state machine, not a mandatory ceremony and not a one-way pipeline.

The coordinator owns routing and stage gates. Leaf skills own their stage instructions:

- `task-research`
- `learning-test`
- `design-change`
- `vertical-plan`
- `implement-plan`
- `verify-change`

If pstack is installed, leaf stages may also use `how`, `why`, `architect`, `blast-radius`, and the relevant principle skills. Do not copy those skills into this coordinator.

## Core rules

1. Separate **what exists**, **what should exist**, **how to get there**, **execution**, and **proof**.
2. Start every major stage in a fresh context using artifacts from prior stages.
3. Keep raw repository exploration in research contexts; pass compressed findings forward.
4. Prefer executable evidence over guesses about external behavior.
5. Each implementation phase ends in an observable check before the next begins.
6. Artifacts, not chat memory, are the system of record.
7. Rewind when evidence invalidates an earlier decision.

## 1. Classify the task

Choose the lightest route that controls the real risk:

| Class | Signals | Route |
| --- | --- | --- |
| `TRIVIAL` | obvious mechanical edit, one local owner, no behavioral uncertainty | record request/success signal → implement directly → `verify-change` |
| `LOCAL` | localized behavior, known architecture, cheap test path | targeted `task-research` → mark design not required → `vertical-plan` → `implement-plan` → `verify-change` |
| `COMPLEX` | multiple components or state machines, unfamiliar ownership, brownfield contracts | `task-research` → `design-change` → `vertical-plan` → `implement-plan` → `verify-change` |
| `HIGH_RISK` | external contracts, distributed state, data integrity, security, payments, migrations | `task-research` → `learning-test` as needed → `design-change` → `vertical-plan` → phased `implement-plan` → `verify-change` |

Do not classify by estimated lines of code. A small diff across several state owners can be complex. Record the class and reason in `.pstack/tasks/<task-id>/task.md`.

For `LOCAL`, also record `Design: NOT_REQUIRED — <reason the researched shape is unambiguous>`. Escalate to `COMPLEX` if research exposes competing ownership, contract, or state-machine choices.

## 2. Create the artifact workspace

Use:

```text
.pstack/tasks/<task-id>/
├── task.md
├── research.md
├── learning/
├── design.md
├── plan.md
├── implementation.md
└── verification.md
```

Create only artifacts required by the selected route. Preserve issue and document links in `task.md`. A decision made by a human or agent is authoritative only after it is written into the relevant artifact.

Every generated artifact records `Revision` and `Inputs`. Before replacing an artifact, copy the prior revision to `.pstack/tasks/<task-id>/archive/<artifact>-r<revision>.md`. If an upstream artifact changes, mark all downstream artifacts `Status: STALE` with the invalidating artifact and revision. A stage may consume only current, non-stale input revisions.

## 3. Run stages with hard gates

### Research

Run `task-research`. Continue only when `research.md` is `READY`.

- owned-code uncertainty → iterate research,
- external behavior uncertainty → run `learning-test`,
- missing product requirement → record it for design rather than guessing.

### Learning test

Run one `learning-test` per falsifiable external question. Feed `PROVEN` findings into research or design. `INCONCLUSIVE` does not settle a design fork.

### Design

Run `design-change` in a fresh context.

- `NEEDS_LEARNING_TEST` → experiment, then resume design in another fresh context,
- `NEEDS_HUMAN_DECISION` → present concise options and recommendation; record the answer in `design.md`,
- `RESEARCH_INCOMPLETE` → return to research,
- `READY` → request human review for `COMPLEX` and `HIGH_RISK`; continue only after `design.md` records `Review: ACCEPTED`, reviewer, and decisions.

Human attention belongs primarily on unresolved architecture, product tradeoffs, races, and assumptions, not on rereading every factual research line.

### Plan

Run `vertical-plan` in a fresh context. Continue only when every phase produces an observable behavior and exact proof.

- `DESIGN_INVALID` → return to design,
- `NEEDS_HUMAN_DECISION` → resolve and update design first,
- horizontal or unverifiable phase → rewrite the plan.

### Implementation

Run `implement-plan` one phase at a time. Use faster implementation models only after the plan has removed architectural judgment; use the configured pstack model roles when available.

- local defect → fix within the current phase,
- `PLAN_INVALID` → preserve the failure evidence, mark downstream artifacts stale, and rewind to the named stage,
- `NEEDS_LEARNING_TEST` → experiment before continuing,
- phase `PASS` → begin the next phase.

### Verification

Run `verify-change` in a fresh context against the actual diff and real interface.

- `VERIFICATION_FAILED` due to implementation → return to the failing phase,
- failure of architecture or contract → return to design,
- `BLOCKED` → report the missing proof; do not claim completion,
- `PASS` → ready for normal code review and CI.

## 4. Enforce fresh-context boundaries

Do not continue major stages in the coordinator's conversation. Launch a new subagent or isolated session for each leaf stage and for each implementation phase. Invoking a leaf skill in the same conversation is not a fresh context.

Use the harness's general coding subagent unless pstack provides a configured workflow agent. The coordinator sends this handoff envelope:

```text
Stage: <leaf skill name>
Task directory: .pstack/tasks/<task-id>/
Read:
- <leaf SKILL.md path or installed skill name>
- <only the current artifact paths and revisions>
Open questions:
- <questions this stage owns>
Write:
- <single expected artifact, or current implementation phase scope>
Stop statuses:
- <statuses that return control to the coordinator>
```

The child returns the artifact path, revision, status, and evidence summary. The coordinator inspects the artifact itself before transitioning.

If the harness cannot create isolated contexts, stop and tell the operator that strict isolation is unavailable; offer a degraded single-context run that first summarizes and discards obsolete working notes. Do not claim that degraded mode provides fresh contexts.

At each handoff, give the next context only:

- its leaf skill,
- relevant durable artifacts,
- explicit open questions,
- paths and commands needed for its stage.

Do not pass full prior transcripts, raw search output, discarded designs, or stale assumptions. If several agents research independent areas, each returns a compressed, cited summary and the research owner synthesizes one artifact.

## 5. Report status

At every pause, report:

```text
Task:
Class:
Current stage:
Artifact:
Status:
Evidence produced:
Open gate:
Next transition:
```

Do not collapse `BLOCKED`, `INCONCLUSIVE`, `PLAN_INVALID`, or `VERIFICATION_FAILED` into generic progress. The explicit state tells the next agent whether to move forward or rewind.

Completion means `verification.md` is `PASS`, the diff has received normal code review, and required CI is green. Agent implementation alone is never the terminal state.
