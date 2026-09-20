---
layout: post
toc: true
title: "Dex: Implement Plan"
date: 2026-09-20
permalink: /references/dex-implement-plan/
noindex: true
sitemap: false
categories: [references]
tags: [dex-workflow, coding-agents, workflow]
---


# Implement Plan

Implementation should be mechanically focused because research, architecture, and sequencing are already settled.

## Inputs and isolation

Require a `READY` `.pstack/tasks/<task-id>/plan.md`. Start in a fresh context with:

1. the current phase,
2. the relevant design contracts,
3. the specific research references named by that phase,
4. the source and tests in its file scope.

Do not carry raw exploration chats into implementation. Do not preload unrelated phases.

## Plan contract

- Implement only the current phase.
- Preserve its invariants, boundaries, and pass predicate.
- Do not silently redesign APIs, ownership, states, or phase scope.
- Prefer the smallest change that satisfies the phase.
- Follow repository conventions discovered in research.
- Keep unrelated cleanup out of the diff.

When source proves the plan wrong, stop and write:

```text
PLAN_INVALID

Phase:
Contradicted assumption:
Repository evidence:
Design or plan section affected:
Suggested rewind: RESEARCH | DESIGN | PLAN
```

Implementation friction alone is not permission for workarounds. Rewind when the chosen shape is wrong.

## Execute one phase

For each phase:

1. Confirm the baseline and run the nearest existing check.
2. Read the phase's exact files and callers.
3. Add or update behavior tests with literal expected results.
4. Make the minimum production change.
5. Run the phase's unit/integration checks.
6. Exercise the phase's runtime proof.
7. Inspect the diff for scope drift and accidental generated output.
8. Record evidence before advancing.

Never accumulate unverified phases. A failed check keeps the current phase active.

If independent files can be delegated safely, give each worker disjoint write scope and one verification contract. Shared state and contracts stay with one owner. Review actual diffs and outputs, not worker summaries.

## Evidence log

Append to `.pstack/tasks/<task-id>/implementation.md`:

```markdown
# <Task title> implementation

Status: IN_PROGRESS | IMPLEMENTED | PLAN_INVALID | BLOCKED
Revision: <integer>
Inputs: plan.md r<revision>, design.md r<revision> | design NOT_REQUIRED

## Phase <n>: <name>

Result: PASS | FAIL | PLAN_INVALID

### Changes
- `<path>` — <behavior changed>

### Tests
- Command: `<exact command>`
- Result: <exit status and meaningful output>

### Runtime proof
- Procedure: ...
- Observed: ...
- Artifact: <log, screenshot, recording, or output path>

### Diff review
- Scope matched: yes/no
- Unexpected changes: ...

### Decisions forced by implementation
- None, or <decision and why this requires a rewind>
```

Do not mark a phase `PASS` when its runtime proof was skipped. Record `BLOCKED` with the missing capability instead.

## Advance or rewind

- `PASS` and evidence exists → begin the next phase in a new subagent/session that receives only the next phase and named artifacts.
- Local implementation defect → fix and rerun the same phase.
- Contract or ownership assumption false → preserve this artifact as `PLAN_INVALID`, mark any `verification.md` as `STALE`, and rewind.
- New external uncertainty → `NEEDS_LEARNING_TEST` and stop.
- Product decision appears → `NEEDS_HUMAN_DECISION` and stop with options.

After all phases pass, set `Status: IMPLEMENTED` and invoke `verify-change` in a fresh context. Phase checks are necessary evidence, not final verification.
