---
name: ui-evaluate-and-improve
description: Improve an existing UI through bounded implementation, browser verification, independent review, and comparison with the best accepted version. Use for iterative UI refinement against explicit usability, visual, accessibility, and regression criteria.
---

# UI evaluate and improve

Improve the requested UI while preserving required behavior. Keep a candidate only when evidence supports improvement over the best accepted version. A reviewer score alone does not establish success.

Use this workflow for an existing UI with a bounded improvement goal. Do not expand a small requested edit into a full redesign. Do not apply this workflow to backend-only optimization or a request for critique without implementation.

## Establish the task

Read the project's instructions and inspect the relevant implementation before editing. Identify:

- The screens, routes, states, and user journeys in scope.
- Required behavior, design-system constraints, supported viewports, and accessibility requirements.
- Available build, test, lint, browser, screenshot, and accessibility tools.
- Concrete acceptance criteria and evidence needed to check each one.
- Available reviewers, their exact model identifiers, capabilities, and execution costs where known.

Resolve missing facts from the project first. Ask only when a missing decision materially affects scope, correctness, or authorization. If the goal is vague, propose concrete criteria before optimizing against them. Keep criteria fixed during evaluation; report any later user-authorized change explicitly.

Read [Model roles](references/model-roles.md) when selecting implementation and review models. Its assignments are provisional recommendations, not verified capability or price rankings. Never substitute an unavailable model silently.

## Set bounds and preserve work

Use an isolated branch or worktree when supported and appropriate. Preserve existing user changes and unrelated files. Record a baseline and a recoverable copy of each accepted candidate using the project's available mechanisms. Do not require commits when a diff or isolated copy is sufficient.

Unless the user sets different bounds, allow at most three candidate iterations and stop after two consecutive candidates fail to produce a supported improvement. These are workflow defaults, not measured optimal values.

Honor configured runtime, model-call, and spending limits. Before a billable call, check remaining allowance using available usage data and a bounded estimate. If cost cannot be measured or bounded, say so; do not claim to enforce a dollar cap. Stop dependent calls when a required budget cannot be enforced.

Creating this skill or invoking it does not authorize deployment, publishing, merging, external messages, or additional paid services. Use only the task's authorized resources and actions.

## Capture the baseline

Run the app and exercise the scoped user journeys. Record existing failures separately from regressions introduced by this work.

Capture screenshots for relevant routes, states, and viewports. Keep theme, seed data, authentication state, browser configuration, and rendering conditions consistent across candidates. Use test fixtures where available. Wait for meaningful page readiness, including fonts and required content; do not assume network idleness proves readiness.

Record the baseline's functional and accessibility checks. Screenshots support visual findings, but cannot prove keyboard navigation, focus behavior, screen-reader output, or successful interactions. Test those behaviors directly with suitable tools.

Choose reference interfaces only when they clarify the requested quality standard. References do not replace product requirements or authorize copying unrelated features.

## Evaluate and improve

For each candidate:

1. Select a small set of evidence-backed findings to address. Prioritize functional and accessibility defects, then usability and visual quality.
2. Make focused changes. Preserve required features, business logic, and established components unless the task authorizes changing them.
3. Run relevant build, lint, functional, accessibility, and browser checks. Verify the actual interface at supported viewports and states. Fix failing required checks before requesting optional visual reviews.
4. Capture the candidate's evidence under the same conditions as the baseline. Associate evidence with the exact code revision or diff. Any later code change invalidates affected checks and reviews.
5. Request independent review of that candidate. Reviewers receive the same criteria, candidate evidence, best accepted evidence, and relevant references. Each reviews before seeing other reviewers' findings or the implementer's claims of success.
6. Consolidate findings without dropping severity, evidence, uncertainty, or unresolved disagreements. Verify disputed claims against the app, code, or tests. Do not settle factual disputes by majority vote or model reputation.
7. Apply the acceptance rules below. Record the decision and evidence before starting another candidate.

Delegate independent reviews when available and authorized. Give reviewers read-only responsibility; only the implementation agent edits the candidate. Separate agents using one model provide separate reviews, not model-family diversity. If independent review is unavailable, report that limitation and do not claim independently verified completion.

Do not modify evaluator instructions, thresholds, fixtures, or tests to make a candidate pass. A demonstrated evaluator defect needs a separate correction and a fresh evaluation of both the previous best and candidate. A written instruction is not access isolation: use actual write restrictions where available and disclose when they are absent.

## Reviewer contract

Ask each reviewer to assess hierarchy, typography, spacing, contrast, consistency, usability, and responsiveness where the evidence supports those judgments. Include task-specific criteria. Mark unsupported judgments as unverified rather than inventing observations.

Require a structured report containing:

- Reviewer role, actual model identifier, and candidate identifier.
- Evidence inspected and important coverage gaps.
- Findings with severity, criterion, precise location, evidence reference, problem, and recommended correction.
- Regressions relative to the best accepted version.
- Criterion outcomes: pass, fail, or unverified.
- Optional scores with an explicit rubric and explanation.
- Remaining uncertainty and an overall recommendation.

Validate required report fields before using the result. A missing reviewer, empty score set, malformed response, or missing criterion is not a pass. Do not infer an accessibility pass from a visual opinion.

If scores are used, keep acceptance thresholds out of reviewer prompts. Do not tell reviewers to produce a desired score. Scores help prioritize work; they do not override required checks. Never average away a blocking defect.

## Accept, reject, or stop

Distinguish accepting a candidate as the new best version from completing the task.

Accept a candidate as the new best only when:

- It passes required regression gates and introduces no unresolved blocking defect.
- Evidence shows improvement on at least one targeted criterion relative to the previous best.
- It does not materially worsen another required criterion. Escalate a genuine product trade-off to the user rather than inventing permission to make it.

For subjective or marginal gains, use an unlabeled side-by-side comparison where practical. Repeat the disputed evaluation within the remaining budget if needed. Treat inconclusive evidence as insufficient to replace the best version.

Reject a worse or inconclusive candidate and retain the previous best. Restore only changes owned by this workflow using its isolated checkpoint; never reset unrelated work. If work cannot be safely separated, stop and explain the conflict.

Complete the task only when all required acceptance criteria pass for the exact final version and required independent review is complete. Unverified criteria remain unverified.

Stop when criteria are met, a configured limit is reached, progress stalls, repeated failures prevent evaluation, or a material disagreement cannot be resolved with available evidence. Reaching a limit is not success. Keep the best verified version and explain what remains.

## Evidence and final report

Store only useful evidence in a task-owned location consistent with repository conventions. Keep candidate identifiers, diffs or revision references, screenshots, check results, reviewer reports, acceptance decisions, and measured usage where available. Avoid capturing credentials or unnecessary personal data.

Report:

- What changed and which user-visible problems it addresses.
- What was verified in the real interface and through automated checks.
- The actual reviewer models used and any substitutions or unavailable capabilities.
- Whether acceptance criteria passed or why iteration stopped.
- Remaining defects, unverified criteria, and material trade-offs.
- Links to the final changes and relevant evidence.

Do not present a high reviewer score as proof of perfection. Do not claim screenshots, independent review, budget enforcement, or browser verification that did not occur.
