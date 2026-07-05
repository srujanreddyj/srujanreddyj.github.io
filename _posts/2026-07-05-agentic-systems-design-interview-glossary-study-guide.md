---
layout: post
toc: true
hidden_home: true
study_guide: true
title: "Agentic Systems Design Interview Concept Glossary"
categories: [learnings]
tags: [agentic-systems, system-design, interview-prep, ai-infrastructure, glossary, study-guide]
---

# Agentic Systems Design Interview — Concept Glossary

Tailored to a role building **agentic ML-development infrastructure**: agents that work with code, data, experiments, and evaluations. Organized to your framework: **FR → NFR → Core Entities → Data Flow → High-Level Design → Deep Dive.** Name + one-line definition each.

---

## 1. Functional Requirements (what the agent system does)

- **Task scope** — what work the agent performs: coding, data generation, eval, triage, experiment orchestration, debugging.
- **Autonomy level** — fully autonomous vs human-approved vs human-in-the-loop at specific checkpoints.
- **Single-agent vs multi-agent** — one agent with tools vs orchestrated specialists (planner, coder, reviewer, evaluator).
- **Interaction surface** — chat, CLI, IDE plugin, CI hook, API, cron-triggered background worker.
- **Tool/action space** — the concrete set of operations the agent may take (run code, edit files, launch training jobs, query data).
- **Environment** — where actions execute: sandbox, repo checkout, cluster, staging vs prod.
- **Success criteria / definition of done** — how the agent knows a task is complete (tests pass, eval score, human sign-off).
- **Feedback loops** — how outcomes (failures, evals, human corrections) flow back to improve prompts, data, or models.

## 2. Non-Functional Requirements (the numbers/constraints)

- **Latency** — interactive (seconds) vs background (minutes–hours); decides model size, parallelism, streaming.
- **Cost per task** — tokens × price × attempts; the dominant budget line; drives model routing and caching.
- **Token budget** — context window ceiling per call; forces compression/memory strategy.
- **Throughput / concurrency** — simultaneous agent sessions; drives rate-limit management and queueing.
- **Reliability / task success rate** — % of tasks completed correctly; the core SLO of an agent system.
- **Determinism vs reproducibility** — LLMs are stochastic; reproducibility comes from logging seeds, prompts, model versions, and tool outputs.
- **Safety envelope** — blast radius limits: what the agent must never do (prod writes, secrets, spend limits).
- **Auditability** — every action traceable to an agent, prompt, and approving human.
- **Model/provider availability** — fallback across providers/models when one degrades.
- **Rate limits & quotas** — provider TPM/RPM caps; require client-side throttling, queues, backoff.
- **Data privacy** — what code/data may be sent to which models (external API vs self-hosted).
- **Graceful degradation** — reduced autonomy or smaller models under budget/outage pressure rather than hard failure.

## 3. Core Entities (the objects in an agent platform)

- **Agent** — a policy (model + system prompt + tools + memory) pursuing a goal over multiple steps.
- **Task / run / episode** — one end-to-end attempt at a goal, with its full trace.
- **Trajectory / trace** — the ordered sequence of thoughts, tool calls, observations, and outputs in a run.
- **Tool** — a typed function the agent can invoke, with schema, docs, permissions, and side-effect classification.
- **Message / turn** — one unit of the conversation loop (user, assistant, tool result).
- **Prompt template / system prompt** — versioned instructions defining agent behavior; treated as code.
- **Memory** — state persisted across turns or sessions (scratchpad, episodic, semantic, long-term stores).
- **Artifact** — outputs an agent produces: diffs/PRs, datasets, eval reports, experiment configs, checkpoints.
- **Environment / sandbox** — the isolated workspace where agent actions execute.
- **Eval / benchmark / test case** — a task with a grading function used to score agent or model behavior.
- **Policy / permission set** — what a given agent identity is allowed to do (tools, resources, spend).
- **Session / checkpoint** — resumable saved state of a long-running agent.

## 4. Data Flow (the agent loop & pipelines)

- **Agent loop (ReAct pattern)** — reason → act (tool call) → observe → repeat until done; the core control flow.
- **Planning / task decomposition** — breaking a goal into subtasks up front (plan-then-execute) or incrementally.
- **Plan-and-execute vs reactive** — explicit upfront plan vs step-by-step decisions; predictability vs adaptability.
- **Tool calling / function calling** — model emits structured (JSON-schema) calls; runtime executes and returns results.
- **Structured output / constrained decoding** — forcing model output into a schema so downstream code can parse it.
- **Tool result truncation/summarization** — compressing large tool outputs before they enter context.
- **Context assembly** — deciding, per call, what goes into the window: instructions, memory, retrieved docs, recent turns.
- **Context compression** — summarizing or pruning history to stay under the token budget while preserving task state.
- **Retrieval-augmented generation (RAG)** — fetching relevant documents/code/embeddings into context instead of storing everything.
- **Embeddings / vector store** — dense representations enabling semantic search over code, docs, and past traces.
- **Chunking** — splitting documents/code into retrieval-sized pieces; chunk boundaries drive retrieval quality.
- **Reranking** — a second-stage model ordering retrieved candidates by relevance.
- **Streaming** — token-by-token output for responsiveness and early cancellation.
- **Handoff / delegation** — one agent passing a subtask and scoped context to another agent.
- **Human-in-the-loop gate** — a pause point where a human approves, edits, or rejects before the agent proceeds.
- **Event/message bus between agents** — async communication substrate for multi-agent coordination.
- **Trace logging pipeline** — capturing every prompt, completion, tool call, and result into storage for eval/debugging/training.

## 5. High-Level Design — Architecture Patterns

- **Orchestrator–worker (supervisor) pattern** — a coordinator agent routes subtasks to specialist agents/tools.
- **Pipeline / workflow (fixed DAG) vs agentic (dynamic)** — predetermined step graph vs model-decided control flow; use the least autonomy that solves the task.
- **Router** — a cheap classifier/model directing requests to the right agent, tool, or model tier.
- **Model routing / cascading** — trying small/cheap models first, escalating to larger ones on failure or low confidence.
- **Evaluator–optimizer (generator–critic) loop** — one model produces, another critiques, iterate until pass.
- **Reflection / self-critique** — the agent reviewing its own output/trace to fix errors before finishing.
- **Debate / ensemble / self-consistency** — multiple samples or agents; majority vote or judge picks the best.
- **Best-of-N with verifier** — sample N candidates, score with a verifier (tests, judge), keep the winner.
- **Blackboard / shared state** — agents coordinating via a shared workspace rather than direct messages.
- **Agent runtime / executor** — the service running the loop: model calls, tool dispatch, retries, timeouts, state.
- **Tool registry** — central catalog of tools with schemas, versions, owners, and permission requirements.
- **MCP (Model Context Protocol) / tool protocol** — standardized interface for exposing tools/resources to agents.
- **Gateway / LLM proxy** — single choke point for all model calls: auth, routing, caching, rate limiting, logging, cost attribution.
- **Prompt caching / KV-cache reuse** — reusing computed prefixes (stable system prompts) to cut latency and cost.
- **Semantic caching** — returning cached responses for semantically-equivalent requests.
- **Session state store** — externalized agent state (DB/object store) so runs survive process restarts.
- **Queue-based task execution** — agent tasks as queued jobs with priorities, retries, and idempotency keys.
- **Checkpoint & resume** — persisting loop state so long tasks recover from crashes without restarting.

## 6. Agent Capabilities Layer

- **Code agent** — agent operating on a repo: read, search, edit, run tests, open PRs.
- **Repo mapping / code indexing** — building searchable structure (symbols, ASTs, embeddings) so agents navigate large codebases.
- **Sandboxed code execution** — running agent-written code in isolated containers/VMs with resource and network limits.
- **Terminal/shell tool** — giving agents command execution; the highest-power, highest-risk tool.
- **Computer/browser use** — agents driving GUIs or web pages for tasks without APIs.
- **Sub-agent spawning** — an agent creating scoped child agents for parallel subtasks (e.g., parallel file edits).
- **Parallel tool calls** — issuing independent tool calls concurrently to cut wall-clock time.
- **Skill / procedure library** — reusable, versioned instructions or scripts agents load on demand.
- **Scratchpad reasoning / chain-of-thought** — intermediate reasoning tokens improving multi-step reliability.

## 7. Memory & Context (called out in the JD)

- **Working memory (context window)** — everything the model sees this call; the scarcest resource.
- **Episodic memory** — records of past runs/interactions retrievable later.
- **Semantic memory** — distilled facts/preferences/knowledge extracted from experience.
- **Procedural memory** — learned how-to knowledge: refined prompts, skills, playbooks.
- **Summarization-based compression** — rolling summaries replacing old turns as conversations grow.
- **Hierarchical summarization** — summaries of summaries for very long horizons.
- **Sliding window + pinned context** — keep recent turns verbatim, pin critical instructions, compress the middle.
- **Memory write policy** — what gets persisted, when, by whom (agent-decided vs rule-based), and how conflicts resolve.
- **Memory retrieval** — scoring stored memories (recency, relevance, importance) for inclusion in context.
- **Context poisoning** — bad/stale/injected content in memory or retrieval corrupting future behavior.
- **Context rot / lost-in-the-middle** — degraded model attention on content buried mid-window; argues for aggressive curation.
- **Knowledge cutoff vs live retrieval** — model's frozen training knowledge vs fetched current state (docs, code HEAD).

## 8. Evaluation & Self-Improvement (core of this JD)

- **Eval harness / platform** — infrastructure to run task suites against agents/models and score outputs at scale.
- **Golden dataset / benchmark suite** — curated tasks with reference answers or checkable outcomes.
- **Programmatic graders** — deterministic checks: unit tests pass, output schema valid, exact/numeric match.
- **LLM-as-judge** — a model grading outputs against a rubric; scalable but needs calibration against humans.
- **Rubric-based evaluation** — decomposing quality into scored dimensions (correctness, style, safety).
- **Pairwise comparison / Elo** — ranking systems by head-to-head judgments instead of absolute scores.
- **Human evaluation / annotation pipeline** — structured human labeling with sampling, instructions, and agreement tracking.
- **Inter-annotator agreement** — consistency between human raters; ceiling for judge accuracy.
- **Judge calibration / meta-evaluation** — measuring the judge against human labels before trusting it.
- **Position/verbosity/self-preference bias** — systematic LLM-judge biases requiring randomization and controls.
- **Outcome vs process evaluation** — grading only the final artifact vs grading the trajectory (tool choices, efficiency).
- **Trajectory evaluation** — scoring the steps: unnecessary calls, loops, recovery from errors.
- **pass@k / success rate** — probability at least one of k samples succeeds; the standard agent metric.
- **Regression testing for prompts/agents** — re-running the eval suite on every prompt/model/tool change; CI for AI behavior.
- **A/B testing / shadow mode** — comparing agent variants on live traffic, or running new agents observation-only.
- **Offline vs online evaluation** — benchmark suites pre-deploy vs live metrics and feedback post-deploy.
- **Eval contamination / overfitting to the benchmark** — the suite leaking into prompts/training, inflating scores; hold-out sets.
- **Failure taxonomy / error analysis** — clustering failed traces into named categories to prioritize fixes.
- **Failure mining / triage agents** — agents that scan logs/traces to surface and cluster failures automatically.
- **Synthetic data generation** — models generating training/eval data; needs diversity controls and quality filtering.
- **Data curation / filtering loop** — scoring and selecting generated or logged data before it enters training sets.
- **Distillation from traces** — fine-tuning smaller models on successful agent trajectories.
- **RLHF / RLAIF / DPO (awareness level)** — preference-based post-training methods that eval pipelines feed.
- **Self-improving loop** — deploy → log traces → mine failures → generate/curate data → retrain or re-prompt → re-eval → redeploy.
- **Flywheel data governance** — versioning, provenance, and consent tracking for data harvested from usage.

## 9. ML Pipeline & Experimentation Infrastructure (the substrate agents operate on)

- **Experiment tracking** — logging configs, metrics, artifacts per run (W&B/MLflow-style) so agents and humans compare results.
- **Training orchestration** — scheduling distributed jobs on GPU clusters; queues, priorities, preemption.
- **Hyperparameter search / sweep** — automated exploration of configs; a natural agent-driven workflow.
- **Reproducibility** — pinned code SHA + data version + config + seed + environment = re-runnable experiment.
- **Data versioning** — immutable, addressable dataset versions so experiments and evals are comparable.
- **Model registry** — versioned catalog of trained models with lineage, eval scores, and deployment stage.
- **Feature/dataset lineage** — tracing which data produced which model produced which decision.
- **Checkpointing (training)** — periodic model-state saves for fault tolerance and warm restarts.
- **Multimodal pipelines** — handling text/image/audio/video with per-modality preprocessing, storage, and eval.
- **GPU utilization & scheduling** — the scarce resource; batching, packing, and priority policies.
- **Inference serving** — batching, quantization, autoscaling, and latency/throughput trade-offs for model endpoints.
- **CI/CD for ML** — automated tests + evals gating model, prompt, and pipeline changes.
- **Packaging & environments** — reproducible Python environments (lockfiles, containers) across research and prod.
- **Monorepo / modular codebase health** — abstraction boundaries, interfaces, and testing that keep a fast-moving ML codebase evolvable.

## 10. Safety, Identity & Governance (JD calls out AuthN/AuthZ/IAM)

- **Agent identity** — each agent has its own principal/service account, distinct from any human user.
- **Authentication (AuthN)** — proving who the agent is (workload identity, short-lived tokens, mTLS).
- **Authorization (AuthZ)** — what the identity may do; enforced at the tool/resource layer, not by the prompt.
- **Least privilege** — agents get the minimum permissions for the task, scoped and time-boxed.
- **Scoped / short-lived credentials** — per-task tokens that expire; no long-lived secrets in agent context.
- **On-behalf-of (delegation) semantics** — agent actions carrying both the agent's identity and the initiating user's.
- **Secrets management** — credentials injected at execution time by the runtime, never placed in the prompt.
- **Prompt injection** — malicious instructions embedded in data (web pages, files, tool results) hijacking the agent.
- **Instruction/data boundary** — treating all tool/retrieved content as untrusted data, never as commands.
- **Jailbreaking** — adversarial inputs bypassing model safety behavior.
- **Excessive agency** — agent granted more tools/permissions/autonomy than the task requires.
- **Sandboxing / isolation** — containers/VMs/network policies limiting what executed code can touch.
- **Egress controls** — allowlisting network destinations to prevent data exfiltration by compromised agents.
- **Side-effect classification** — labeling tools read-only vs reversible-write vs irreversible; gating accordingly.
- **Approval workflows** — human sign-off required for high-risk action classes (prod deploys, spend, deletion).
- **Action budget / spend limits** — hard caps on tokens, dollars, API calls, or steps per run.
- **Kill switch / circuit breaker** — immediate halt of an agent or fleet when anomalous behavior is detected.
- **Guardrails (input/output filtering)** — classifiers or rules screening prompts and outputs for policy violations.
- **Audit trail** — immutable log of every agent action with identity, inputs, and results.
- **Rollback / reversibility** — preferring undoable actions (branch + PR, not direct push; soft delete).
- **Content provenance / watermarking (awareness)** — marking agent-generated artifacts as machine-produced.

## 11. Reliability & Failure Modes (deep-dive ammunition)

- **Non-determinism handling** — retries produce different outputs; verify with checks, don't assume replays match.
- **Hallucination** — confident fabrication (APIs, file paths, results); mitigated by grounding, retrieval, and verification.
- **Hallucinated tool calls** — calling nonexistent tools or invalid arguments; schema validation + graceful error feedback.
- **Infinite loops / repeated actions** — agent stuck retrying the same failing step; step limits + loop detection.
- **Max-step / timeout limits** — hard ceilings on iterations and wall-clock per run.
- **Error feedback loop** — returning tool errors to the model so it can self-correct, vs failing the run.
- **Retry with idempotency** — safe re-execution requires idempotency keys on side-effectful tools.
- **Compensating actions (saga pattern)** — undo steps for multi-step workflows that fail midway.
- **Partial failure in multi-agent runs** — one sub-agent fails; supervisor must retry, reassign, or degrade.
- **Deadlock / livelock between agents** — agents waiting on or endlessly negotiating with each other.
- **Error propagation / compounding** — small per-step error rates compound over long horizons (0.99^50 ≈ 0.6).
- **Context overflow failure** — task state exceeding the window mid-run; needs proactive compression triggers.
- **Model version drift** — provider silently updates a model, shifting behavior; pin versions + regression evals.
- **Prompt regression** — a prompt edit fixing one case and breaking others; caught only by eval suites.
- **Cascading rate-limit failures** — parallel agents exhausting shared quotas; central gateway + admission control.
- **Cost runaway** — loops or fan-out exploding token spend; per-run and per-tenant budgets with hard stops.
- **Observability for agents** — distributed-tracing-style spans over LLM calls and tool calls (OpenTelemetry conventions).
- **Trace debugging / replay** — re-running a recorded trajectory step-by-step to localize the failure.
- **Online monitoring metrics** — success rate, steps per task, tokens per task, tool-error rate, human-override rate, cost per task.
- **Drift detection** — task mix or model behavior shifting over time, degrading success rates.
- **What breaks at 10x** — for agents: quota exhaustion, queue backlog, eval throughput, trace-storage volume, judge cost.

---

## Quick trade-off checklist (name these out loud)

- Workflow (fixed DAG) vs agent (dynamic) → **predictability/debuggability vs flexibility**; use the least autonomy that works
- Single agent vs multi-agent → **simplicity vs specialization/parallelism (and coordination + compounding-error cost)**
- Bigger model vs cascade/routing → **quality vs cost & latency**
- More context vs retrieval/compression → **fidelity vs cost, latency, and lost-in-the-middle**
- Autonomy vs human-in-the-loop gates → **speed vs safety/trust**; gate on side-effect severity
- LLM-as-judge vs human eval → **scale & speed vs ground-truth reliability**; calibrate judge against humans
- Outcome vs process evaluation → **cheap signal vs diagnosable signal**
- Best-of-N / reflection vs single pass → **success rate vs multiplied token cost**
- Synthetic data vs human data → **volume & cost vs diversity and quality risk (model collapse)**
- Guardrails in prompt vs enforcement in runtime → **flexible but bypassable vs hard but rigid**; security lives in the runtime
- Pin model versions vs auto-upgrade → **stability vs missing improvements**; upgrade behind regression evals
