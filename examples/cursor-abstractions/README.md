# Cursor abstraction rules

These are starting rules for a Python monorepo. They have not assessed your project.

## Install

Download the ZIP from the [published guide](https://srujanreddyj.github.io/guides/cursor-abstraction-rules.html) or download these raw files:

- [abstraction-audit.mdc](abstraction-audit.mdc)
- [abstraction-development.mdc](abstraction-development.mdc)
- [python-abstractions.mdc](python-abstractions.mdc)

Copy all three .mdc files into your actual
code repository's .cursor/rules/ directory. Preserve existing rules and check
for conflicts. Do not install them in a notes vault unless that is the project
you intend to assess.

In Cursor's rules view, verify that abstraction-development is Always Apply and
abstraction-audit is Apply Manually. The audit intentionally has no description
or globs; alwaysApply: false makes it manual under the documented rules format.
Verify that python-abstractions applies to matching Python files.

Cursor documentation: https://prod.cursor.com/docs/rules

## Run the first assessment

Type @ in Cursor Agent and select abstraction-audit, then submit:

```text
@abstraction-audit
Assess abstraction quality in this repository. Start with the area we change
most often; ask me if that cannot be determined. This is a Python monorepo:
start with one package and trace its important cross-package callers. Inspect
real callers and tests.
Create docs/abstraction-assessment.md and docs/abstraction-map.md, or use suitable
existing documentation locations and update the development rule's map path.
Do not refactor application code. Cite source locations for each finding and
score. State scope, coverage, confidence, and unknowns. Ask concise questions
where business rules or intended contracts are materially ambiguous.
```

If you know the target area, replace the first sentence about scope with its name.
For a large repository, assess one area per run and preserve prior findings.

Review the map before adopting new architecture constraints. It should distinguish
observed behavior, documented intent, and proposed improvements. Resolve important
conflicts with the person responsible for the affected behavior. Add project-specific
rules only for decisions you adopt, and link actual source and contract tests.

## Use during development

The development rule applies automatically. For an initial trial, ask:

```text
Implement [a small real change]. Before editing, identify the owning module,
existing interface to reuse, and contract to preserve. Verify the changed behavior
and review the diff for duplicated rules or access to another module's internals.
```

Inspect the resulting code and test output. An agent saying it followed a rule is
not evidence that it did. Once module ownership and dependency directions are
settled, use relevant existing lint, import-boundary, or contract checks in CI.
Prompt rules guide behavior; executable checks detect specific violations.

## Compare later assessments

Reassess the same modules and dimensions after relevant changes. Preserve the
earlier scope and evidence where possible. Treat improved scores as hypotheses
until callers need less knowledge, rules have clearer owners, or behavior has
better verification. Do not compare sampled scores as whole-project rankings.
