---
layout: post
toc: true
title: "Dex: Verify Change"
date: 2026-09-20
permalink: /references/dex-verify-change/
noindex: true
sitemap: false
categories: [references]
tags: [dex-workflow, coding-agents, workflow]
---


# Verify Change

Answer two independent questions:

1. **Correctness:** does the requested behavior work through the real interface?
2. **Safety:** what else could the change break, and which safety fact is actually proven?

Start in a fresh context with the task, actual diff, and every artifact produced by the selected route. A `TRIVIAL` route may have no research, design, plan, or implementation log; verify directly against the recorded request and success signal. Other routes require the accepted design, plan, and implementation log that they produced. Distrust status labels until their artifacts are inspected.

## 1. Inspect the implementation

Read the diff and changed files. Confirm:

- every change maps to a planned behavior,
- no architecture was silently redesigned,
- no unrelated cleanup or generated noise entered the diff,
- tests assert caller-visible outcomes,
- errors, cancellation, retries, and concurrency match the design.

If implementation diverged from the accepted design, return `PLAN_INVALID` or `VERIFICATION_FAILED`; passing tests do not legitimize an unreviewed architecture.

## 2. Build an evidence ladder

Use the highest practical evidence:

```text
static inspection
  < unit test
  < integration test
  < runtime reproduction
  < end-to-end behavior through the real interface
```

Build and typecheck when relevant, but never present them as proof of runtime behavior. Run the feature, send the request, invoke the CLI, query the persisted value, or drive the UI a user actually uses.

Exercise:

- the primary success path,
- the load-bearing failure/cancellation path,
- one relevant regression or compatibility path,
- concurrent or repeated execution when the design depends on it.

Capture exact commands and direct observations. Prefer a rerunnable script over one-time prose. For interactive changes, retain screenshots or a short recording when available.

## 3. Inspect blast radius

If pstack is installed, run `blast-radius` against the actual diff. Otherwise:

1. identify changed symbols, contracts, schemas, events, and side effects,
2. follow consumers beyond direct symbol references,
3. inspect wire formats, storage, generated clients, feature flags, and other languages,
4. state the one fact the change is safe because of,
5. prove that fact by running real code or mark it unproven.

Classify each risk as confirmed, cleared with evidence, or unproven. Do not pad the report with hypothetical maybes.

## 4. Write the verification artifact

Write `.pstack/tasks/<task-id>/verification.md`:

````markdown
# <Task title> verification

Status: PASS | VERIFICATION_FAILED | BLOCKED
Revision: <integer>
Inputs: task.md, <artifact names and revisions>, diff <commit or working-tree marker>

## Verdict
<What is ready or why it is not.>

## Requested behavior
| Scenario | Procedure | Direct observation | Result |
| --- | --- | --- | --- |

## Commands run
```text
<command and exit status>
```

## Runtime evidence
- <artifact path and what it proves>

## Diff review
- Planned scope: ...
- Design conformance: ...
- Unexpected changes: ...

## Blast radius
### One fact it is safe because of
<Fact, proof command, and result; or UNPROVEN.>

### Confirmed risks
- ...

### Cleared risks
- ...

## Unproven assumptions
- None, or ...

## Follow-up
- <Only work that is genuinely outside the requested change.>
````

## 5. Decide honestly

`PASS` requires:

- primary behavior observed through the matching real surface,
- planned failure behavior observed when the task or design defines one; otherwise recorded `N/A` with a reason,
- relevant automated checks green,
- actual diff reviewed,
- no high-impact assumption left unproven.

Use `BLOCKED` when the environment cannot exercise the required surface. Use `VERIFICATION_FAILED` when evidence contradicts the requirement or design. Neither may be rounded up to pass.

If pstack is installed, apply `principle-prove-it-works` and `principle-test-behavior-not-implementation`. Return the artifact path, verdict, strongest direct evidence, blast-radius safety fact, and unproven assumptions.
