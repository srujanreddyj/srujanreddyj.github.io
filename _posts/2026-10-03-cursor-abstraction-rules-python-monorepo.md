---
layout: post
title: "Assess and preserve abstractions in a Python monorepo with Cursor"
visibility: public
published: true
content_type: guide
topics: [engineering-practice, ai-ml-systems]
tags: [python, cursor, software-design]
summary: "Download Cursor rules to assess existing module contracts and guide future changes in a Python monorepo."
featured: false
toc: true
permalink: /guides/cursor-abstraction-rules.html
---

A useful abstraction reduces what callers must know to use a module correctly.
For an existing Python monorepo, examine real operations and their callers before
adding new interfaces or preserving old ones.

This guide provides three Cursor rules: a manually invoked assessment, persistent
development guidance, and Python-specific guidance. They are starting instructions,
not an assessment of your repository or proof of correct behavior.

## Download the rules

[Download the rules and usage instructions as a ZIP]({{ '/assets/downloads/cursor-abstraction-rules.zip' | relative_url }}).

The [source folder on GitHub](https://github.com/srujanreddyj/srujanreddyj.github.io/tree/master/examples/cursor-abstractions)
contains the individual files and the README. Download the raw files if copying them
individually so their YAML front matter remains intact.

| Rule | Activation | Purpose |
| --- | --- | --- |
| `abstraction-audit.mdc` | Apply Manually | Trace real workflows, rate inspected modules, and document evidence. |
| `abstraction-development.mdc` | Always Apply | Reuse useful interfaces and preserve or deliberately change their contracts. |
| `python-abstractions.mdc` | Apply to Specific Files: `**/*.py` | Check package ownership, imports, dependencies, and state. |

Cursor project rules use `.mdc` files in `.cursor/rules/`. Their front matter controls
whether they apply always, by file pattern, by relevance, or through an explicit
mention. See the [Cursor rules documentation](https://prod.cursor.com/docs/rules).

## Install in the target monorepo

Extract the bundle and copy its three `.mdc` files into your code repository:

```text
your-monorepo/
  .cursor/
    rules/
      abstraction-audit.mdc
      abstraction-development.mdc
      python-abstractions.mdc
```

Preserve existing rules and resolve conflicting instructions. In Cursor's rules
view, confirm the activation settings in the table. The audit rule intentionally
omits `description` and `globs` and sets `alwaysApply: false`, which makes it manual.
The development rule sets `alwaysApply: true`. The Python rule uses `globs: "**/*.py"`.

Install these in the project you want to assess. Keeping the downloadable examples
in a website repository does not activate them there.

## Run an initial assessment

In Cursor Agent, type `@` and select `abstraction-audit`, then submit this prompt.
Replace the bracketed text with one package or workflow you often change.

```text
@abstraction-audit

Assess abstraction quality in this Python monorepo.
Start with [package or workflow]. Trace its important cross-package callers.

Inspect real source, supported operations, implementations, and relevant tests.
Create docs/abstraction-assessment.md and docs/abstraction-map.md, or use suitable
existing documentation locations and update the development rule's map path.

Do not refactor application code during this assessment.
Support each finding and rating with source locations.
State scope, coverage, confidence, and unknowns.
Distinguish verified behavior, documented intent, and proposed improvements.

Ask concise questions when business rules, ownership, or intended behavior
are materially ambiguous. Continue independent inspection while waiting.
```

Start with one package and inspect enough of its dependencies and callers to
support the findings. A sampled review does not establish the quality of the
entire monorepo.

## Understand the ratings

The audit rates each inspected module on six dimensions. Here, a module can be a
function, class, package, or larger unit with an interface and implementation.
Its interface includes the rules callers must know, beyond its function signatures.

| Dimension | Question |
| --- | --- |
| Caller knowledge | Can callers express a task without coordinating internal steps? |
| Rule ownership | Does one module own and enforce the relevant business rules? |
| Change locality | Do internal changes stay within the owner when its contract stays stable? |
| Contract reliability | Does behavior match the stated success, failure, and concurrency promises? |
| Composition | Can operations work together without hidden interference? |
| Verification | Can tests or observations check meaningful behavior through the interface? |

Ratings run from 0, poor, to 3, strong. Each requires evidence, a concrete example,
caller impact, and confidence. Use "unknown" when evidence is insufficient and
"N/A" with a reason when a dimension does not apply. The rule file includes the
anchors for each dimension.

These ordinal ratings guide discussion. They are not validated measurements.
Do not average them into a project score, reward extra classes or layers, or treat
missing tests as proof of incorrect behavior.

## Review the abstraction map

The assessment identifies useful abstractions and priority problems. The map
records project-specific knowledge for later changes:

- The package that owns each operation and business rule.
- Supported entry points and representative callers.
- Relevant inputs, results, errors, side effects, and concurrency limits.
- Dependency directions and contract tests.
- Observed behavior, documented intent, and proposed design, clearly separated.

For example, a useful entry might say that a membership package owns duplicate
prevention and authorization and exposes `add_member(team_id, user_id)`. It must
also explain relevant failures. A short name alone does not establish a contract.

Review consequential conflicts before adopting new architecture constraints.
Confirm what the operation should promise with the person responsible for its
behavior. Preserve useful interfaces; do not turn every existing pattern into a rule.

The workflow is:

```text
Inspect source, callers, and tests
              ↓
Assessment and abstraction map
              ↓
Review evidence and resolve contract questions
              ↓
Implement through established interfaces
              ↓
Verify behavior, review the diff, and update changed contracts
```

## Use the rules during development

The development rule applies automatically. For a first trial, choose a small
real feature or bug fix and use this prompt:

```text
Implement [small feature or bug fix].

Before editing, identify the owning package, existing interface to reuse,
and contract to preserve.

After editing, verify the changed behavior and review the diff for duplicated
business rules, cross-package internal access, and unnecessary abstraction layers.
```

The rules direct the agent to inspect affected callers, keep business rules with
their owner, and avoid speculative factories, registries, or abstract base classes.
They also require it to explain when an existing abstraction does not fit and make
the smallest justified improvement within the task.

For shared contract changes, check affected consumers as well as the owning
package. Update the relevant map entry when ownership or promises change.
Do not depend on a stale document when source and tests disagree.

## Verify and maintain the result

Inspect the actual diff and test output. An agent saying it followed a rule does
not establish that it did. Once ownership and dependency direction are settled,
use suitable import checks and contract tests in CI to detect specific violations.
Prompt rules guide behavior; executable checks provide separate evidence.

Reassess the same modules after relevant changes. An improved rating should
correspond to less caller knowledge, clearer rule ownership, more local changes,
or better verification. Keep the evidence and scope so later comparisons remain useful.

Avoid placing private code, secrets, or an internal project's assessment in a
public repository. These downloadable files contain reusable instructions only.
