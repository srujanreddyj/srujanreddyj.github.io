---
layout: post
toc: true
title: "Dex: Vertical Plan"
date: 2026-09-20
permalink: /references/dex-vertical-plan/
noindex: true
sitemap: false
categories: [references]
tags: [dex-workflow, coding-agents, workflow]
---


# Vertical Plan

Produce a plan an implementation agent can execute without rediscovering the architecture. The plan is the deliverable. Do not implement it in this context.

## Inputs

Require `task.md` and a `READY` `research.md` under `.pstack/tasks/<task-id>/`.

- `COMPLEX` and `HIGH_RISK` tasks also require a `READY` design with `Review: ACCEPTED`.
- `LOCAL` tasks may omit `design.md` only when `task.md` records `Design: NOT_REQUIRED` with a reason and research establishes one unambiguous shape.

Start in a fresh context.

Use source only to name exact symbols, files, existing test commands, and verification surfaces. If source contradicts an artifact, return `DESIGN_INVALID` with evidence. Do not silently repair architecture while planning.

## Verticality rule

Every phase must have this shape:

```text
small coherent behavior
  → necessary cross-layer changes
  → observable result
  → deterministic verification
```

A phase may cross UI, API, domain, and persistence when those pieces are required to observe one behavior. Horizontal buckets such as "backend", "frontend", and "tests" are not phases. Tests belong inside the phase that introduces the behavior.

Prefer the smallest slice that reduces uncertainty or delivers a usable behavior. Put risky contracts, migrations, and state transitions early enough to fail cheaply. Keep the system verifiable after each phase.

## 1. Establish phase boundaries

For each candidate phase ask:

1. What new behavior exists after this phase?
2. How can someone observe it before the next phase?
3. What exact check passes?
4. Does it include all layers required for that check?
5. If it fails, is the debugging surface small?
6. Can it be reverted or corrected without unwinding later phases?

Merge phases that cannot be verified independently. Split phases that contain multiple unrelated behaviors.

## 2. Specify without redesigning

Each phase names:

- behavior and acceptance predicate,
- exact files and symbols expected to change,
- domain shape or state transition from the design,
- tests added or changed,
- runtime exercise,
- expected evidence,
- dependencies and do-not-touch boundaries,
- rollback or stop condition.

Do not prescribe line-by-line edits where the source makes the implementation obvious. Do prescribe contracts, invariants, and evidence tightly enough that implementation does not need architectural judgment.

## 3. Write the plan

Write `.pstack/tasks/<task-id>/plan.md`:

```markdown
# <Task title> implementation plan

Status: READY | DESIGN_INVALID | NEEDS_HUMAN_DECISION
Revision: <integer>
Inputs: research.md r<revision>, design.md r<revision> | design NOT_REQUIRED

## Outcome
<Requested behavior and done condition.>

## Preconditions
- Research: `<path>` status READY
- Design: `<path>` status READY and review ACCEPTED | NOT_REQUIRED because `<reason>`
- Learning tests: ...

## Phase 1: <observable behavior>

### Behavior
<What becomes true for a caller or user.>

### Changes
- [ ] `<path>` — `<symbol>`: <contract-level change>

### Invariants
- ...

### Tests
- [ ] `<test path>`: <literal behavior asserted>
- [ ] Run `<exact command>`.

### Runtime proof
- [ ] <Setup and real interaction.>
- [ ] Observe <exact state, output, event, or screenshot>.

### Pass predicate
<A falsifiable result.>

### Stop or rewind when
<Evidence that invalidates the plan or design.>

## Phase 2: <next observable behavior>
...

## Final system verification
- [ ] <End-to-end scenario>
- [ ] <Failure/cancellation scenario>
- [ ] <Compatibility or regression scenario>

## Blast-radius targets
- <Downstream or cross-boundary area to inspect after the diff exists.>

## Deferred work
- <Explicit non-goal and why it is safe to defer.>
```

## 4. Lint the plan

Reject and rewrite any phase whose title or only result is:

- database changes,
- service/backend changes,
- API changes,
- frontend changes,
- write tests,
- cleanup,
- wire everything together.

For every phase, verify there is a concrete runtime or user-observable proof. Compilation and typechecking may support a phase but cannot be its only proof unless the requested artifact is itself a type-level or build-system change.

If pstack is installed, apply `principle-sequence-verifiable-units` to ordering and `principle-test-behavior-not-implementation` to each test. Return the artifact path, status, ordered phase names, and the proof produced by each phase. Stop before implementation.

On iteration, increment `Revision`, archive the replaced artifact under `.pstack/tasks/<task-id>/archive/plan-r<old-revision>.md`, and mark existing implementation and verification artifacts `STALE`.
