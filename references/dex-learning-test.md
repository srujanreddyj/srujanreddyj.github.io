---
layout: post
toc: true
title: "Dex: Learning Test"
date: 2026-09-20
permalink: /references/dex-learning-test/
noindex: true
sitemap: false
categories: [references]
tags: [dex-workflow, coding-agents, workflow]
---


# Learning Test

Do not spend reasoning tokens guessing behavior that executable evidence can settle.

A learning test is a probe, not initially a regression test. It may print an event stream or persisted state instead of asserting business behavior. Its job is to discover the external contract on which a design depends.

## Trigger

Use this skill when all are true:

1. an architectural choice depends on external or runtime behavior,
2. repository source does not establish that behavior,
3. a small experiment can observe it.

First inspect pinned versions, local patches, public types, vendor source, and authoritative documentation. If those settle the question unambiguously, cite them and stop. If they conflict or omit the edge case, run the experiment.

## 1. State one falsifiable question

Bad: "How does cancellation work?"

Good: "After `AbortController.abort()` fires while SDK version 2.4.1 waits for tool approval, which events are emitted, what tool result is recorded, and what context is visible after resume?"

Record:

- the exact dependency and pinned version,
- the initial state,
- the action,
- every observation needed by the design,
- competing expected outcomes.

## 2. Build the smallest real probe

Place durable probes in the project's existing learning-test convention. If none exists, use:

```text
tests/learning/<dependency>/<behavior>.<ext>
```

Store the report at:

```text
.pstack/tasks/<task-id>/learning/<behavior>.md
```

Exercise the real dependency. Avoid mocks for the behavior under investigation. Minimize unrelated application code, network calls, cost, and nondeterminism. Capture raw events, return values, errors, timing, and durable state needed to distinguish outcomes. Redact secrets and personal data.

Do not add a business assertion before learning the result. Add assertions only after the observed contract is understood and stable enough to preserve.

## 3. Run and challenge the result

Run the probe from a clean state. Repeat when timing, retries, concurrency, or remote services could change the outcome. Test the nearest counterexample so the result is not an accident of setup.

Record exact commands and relevant output. If credentials or infrastructure prevent execution, mark the result `BLOCKED`; do not convert an unrun probe into a conclusion.

## 4. Write the report

````markdown
# Learning test: <falsifiable question>

Status: PROVEN | INCONCLUSIVE | BLOCKED
Revision: <integer>
Inputs: research.md r<revision> | design.md r<revision> | standalone question

## Dependency
<Name, pinned version, source/docs inspected.>

## Why this matters
<Design fork this result settles.>

## Competing outcomes
- If A, then ...
- If B, then ...

## Experiment
<Setup, action, observations, and probe path.>

## Reproduce
`<exact command>`

## Raw result
```text
<relevant unedited output>
```

## Finding
<Only what the experiment demonstrates.>

## Architectural implication
<What becomes simpler, necessary, or unsafe.>

## Limits
<Versions, environments, timing, and cases not covered.>

## Keep or delete
KEEP as executable documentation | PROMOTE to regression/contract test | DELETE after decision
````

## 5. Preserve the right artifact

Keep the probe when the architecture depends on undocumented or change-prone behavior and engineers can rerun it after upgrades. Promote it to CI only when it is deterministic, affordable, and failure should block shipping. Delete throwaway setup that taught nothing durable.

If pstack is installed, apply `principle-build-the-lever`: the rerunnable probe is the evidence artifact. Return the report path, status, exact command, finding, and the design decision it settles. Do not implement the product change.

On iteration, increment `Revision`, archive the replaced report under `.pstack/tasks/<task-id>/archive/learning-<behavior>-r<old-revision>.md`, and mark every downstream artifact that cited the old revision `STALE`.
