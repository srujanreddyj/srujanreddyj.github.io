# ai-system-gen

Architecture reference and semantic-model design notes for the supply-chain assistant.

## Reading order

1. [Architecture review and target specification](architecture-review.md): the supplied version 2.4 review, with blank lines and broken Markdown table rows repaired. The project name and example database schema names have been updated to `ai-system-gen` and `ai_system_gen_dev`.
2. [Semantic models and agent queries](semantic-models-and-agent-queries.md): why cubes help, how to organize many tables, and how the agent discovers and queries metrics.
3. [Supplier quality YAML example](examples/supplier-quality.original.yaml): the supplied model, with indentation and pasted Markdown escapes normalized. Its access-control block is illustrative, not deployable Cube configuration.

## Evidence and scope

The architecture review is user-supplied source material. Its claims of code inspection, line references, performance figures, and unresolved `[cite: ...]` markers have not been independently verified against the ai-system-gen implementation. This repository contains the website, not the inspected ai-system-gen backend. The review's proposed thresholds and guarantees require validation before adoption.

The semantic guide distinguishes documented Cube behavior from recommendations for ai-system-gen. These files add documentation only; they do not install Cube, implement agent tools, or enforce access controls.
