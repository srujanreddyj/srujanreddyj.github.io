# Provisional model assignments

These assignments preserve the user's proposed model roster. They are a starting configuration to evaluate, not established rankings of coding quality, visual judgment, speed, or cost. Exact endpoint names and capabilities must be confirmed in the execution environment. The user supplied "haik 5-5"; this document tentatively interprets that as Haiku 5.5.

| User-supplied model | Proposed responsibility | Use condition |
| --- | --- | --- |
| Sonnet 5.5 | Main implementation agent | Make focused changes, run checks, and address findings. |
| GLM 5.3 | Independent code reviewer | Review correctness, edge cases, and regressions after required automated checks pass. |
| Kimi K3 | Final independent reviewer | Check requirements coverage and unresolved findings before declaring completion. |
| Opus 5.5 | Difficult-case investigation | Investigate stalled iterations or unresolved disagreements using reproducible evidence. It does not overrule failing tests or receive final authority by model name. |
| Haiku 5.5 | Optional report consolidation | Deduplicate and format findings while preserving evidence, severity, disagreement, and uncertainty. Prefer deterministic processing when it suffices. |
| Gemini Argon | Candidate visual reviewer | Use only after confirming the exact endpoint, image support, and useful performance on representative screenshot reviews. |
| Gemini 38 Flash | Candidate preliminary reviewer | Use only if measured latency, cost, and defect detection justify the extra stage. Its opinion alone must not indefinitely prevent independent review. |

## Small starting configuration

Use Sonnet to implement, GLM to review candidates that pass required checks, and Kimi to review the proposed final version independently. Use Opus only when a bounded investigation can resolve a specific difficult issue. Haiku and the Gemini options are optional, not mandatory calls on every iteration.

For visual acceptance, include at least one reviewer with confirmed image support and access to the actual screenshots. If neither the chosen Gemini endpoint nor another authorized reviewer can inspect images, disclose the missing visual review. Code review is not a substitute.

Run deterministic build, functional, and accessibility checks outside the model opinion process. Let explicit acceptance rules determine decisions. A model can extract findings or recommend acceptance, but must not redefine the gates to accept its own work.

If using a preliminary reviewer, reserve an independent review within the overall call budget so that repeated preliminary rejection does not exclude all other judgments. Skip this extra stage when the task is too small to justify it.

## Calibrate before relying on assignments

Use a small, representative set of UI tasks and known defects. Keep prompts, evidence, test conditions, and evaluation criteria comparable. Measure:

- Successful implementations and introduced regressions.
- Reviewer detection of known defects, missed defects, and false alarms.
- Consistency on repeated or unlabeled comparisons.
- Actual elapsed time, usage, and cost per accepted improvement where available.

Use separate cases to check whether role assignments generalize beyond the calibration tasks. Choose roles from observed task performance; do not infer specialization from model branding. Different providers do not guarantee independent errors.

Record requested and actual model identifiers for every run. If the requested model is unavailable, use an already-authorized equivalent only when the substitution preserves required capabilities and constraints; disclose it. Otherwise report the limitation and request the missing decision. Do not claim access to this roster merely because it appears in the skill.
