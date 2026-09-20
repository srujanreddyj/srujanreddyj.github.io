---
layout: post
toc: true
title: "Dex: Task Research"
date: 2026-09-20
permalink: /references/dex-task-research/
noindex: true
sitemap: false
categories: [references]
tags: [dex-workflow, coding-agents, workflow]
---


# Task Research

Produce a compressed, evidence-backed model of the current system. Answer **what exists?**, not **what should we change?**

## Contract

- Do not modify production code.
- Do not propose architecture or implementation.
- Separate verified facts, inferences, and unresolved questions.
- Cite repository evidence as `path:line` and name symbols when useful.
- Read only what answers a research question. Route broad, independent searches to fresh subagents and keep their summaries, not raw output, in the main context.
- If pstack is installed, use `how` for runtime flow and ownership. Use `why` only when historical intent constrains the task.

## 1. Establish the task

Choose a stable kebab-case `<task-id>`. Create `.pstack/tasks/<task-id>/task.md` if it does not exist. If the coordinator already created it, preserve its routing metadata and update only missing task fields:

```markdown
# <Task title>

Task ID: <task-id>
Class: TRIVIAL | LOCAL | COMPLEX | HIGH_RISK
Classification reason: <why this amount of process matches the risk>

## Request
<The user's request without invented requirements.>

## Success signal
<The observable behavior the user wants.>

## Scope clues
<Named systems, constraints, links, and explicit exclusions.>
```

If the task is too vague to identify a success signal, record that as an open question. Do not fill the gap with a guessed design.

## 2. Write objective research questions

Derive questions before deep exploration. Prefer questions such as:

- Where does the behavior enter the system?
- Which component owns each relevant state?
- What are the valid state transitions and invariants?
- How does data or control flow across boundaries?
- Which API, event, persistence, or wire contracts participate?
- What handles cancellation, retries, concurrency, and failure?
- Which tests exercise the behavior?
- Which external dependency behavior does the design rely on?

Exclude solution-shaped questions such as "Where should we add the button?" or "Which handler should we modify?"

## 3. Explore by independent slice

Split broad work by subsystem or question, not arbitrary directories. Each explorer receives:

1. the task,
2. only its assigned questions,
3. a requirement to return concise findings with evidence,
4. a prohibition on implementation proposals.

Trace from real entry points through state ownership, boundaries, side effects, and tests. Search for semantic equivalents, not only ticket wording. Read generated schemas and pinned dependency versions when they define contracts.

When an answer depends on undocumented external behavior, record the exact question under **External uncertainties**. Do not guess. That question is input to `learning-test`.

## 4. Synthesize the artifact

Write `.pstack/tasks/<task-id>/research.md`:

```markdown
# <Task title> research

Status: READY | BLOCKED
Revision: <integer>
Inputs: task.md

## Task
<Request and success signal.>

## Research questions
- [x] <answered question>
- [ ] <unanswered question>

## System model
<A short mental model and an ASCII flow when useful.>

## Runtime flow
1. <Entry point and evidence.>
2. <Boundary crossing and evidence.>
3. <State/effect and evidence.>

## State ownership and transitions
| State or invariant | Owner | Readers/writers | Evidence |
| --- | --- | --- | --- |

## Relevant components
### `<symbol>`
Role, contract, and why it matters. Evidence: `path:line`.

## Existing behavior
<Observed behavior, including failures, retries, and concurrency.>

## Existing tests and verification surfaces
| Behavior | Test or command | Gap |
| --- | --- | --- |

## External uncertainties
| Question | Why the design depends on it | Cheapest experiment |
| --- | --- | --- |

## Open questions
- <Question, owner, and what evidence would settle it.>

## Facts, inferences, and exclusions
### Verified facts
- ...
### Inferences
- ...
### Not investigated
- ...
```

`READY` means the artifact can onboard a fresh design session. It may contain external uncertainties if each has a concrete learning-test path. Use `BLOCKED` only when a missing fact prevents design and cannot be discovered with available source, tools, or an experiment. On iteration, increment `Revision`, archive the replaced artifact under `.pstack/tasks/<task-id>/archive/research-r<old-revision>.md`, and mark existing design, plan, implementation, and verification artifacts `STALE`.

## 5. Review uncertainty

Audit only the weak points:

- unsupported ownership claims,
- missing callers or consumers,
- races and multiple simultaneous actors,
- state transitions inferred from names instead of code,
- external behavior described without an experiment,
- implementation advice leaking into factual sections.

Iterate the artifact until those points are resolved or explicitly marked. Return the artifact path, status, unresolved questions, and suggested next stage. Do not continue into design in this context.
