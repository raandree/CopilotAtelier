---
status: accepted
date: 2026-11-09
last-verified: 2026-11-09
owner: software-engineer
source: Copilot models endpoint and GitHub supported-models documentation, 2026-11-09; owner ruling of 2026-11-09
supersedes: 0007-use-claude-opus-4-8
---

# Declare Claude Opus 5.5 and Sonnet 5.5 for Custom agents

## Context and problem statement

Fifteen Custom agents declared `['Claude Opus 5 (copilot)', 'Claude Opus 4.8 (copilot)']`
and `spec-work-implementer` declared `['Claude Sonnet 5 (copilot)', 'Claude Opus 4.8 (copilot)']`.
By 2026-10-21 the owner's Copilot no longer offered Opus 5 or Opus 4.8, although
GitHub's list of supported models still named both as generally available: which
models a user gets depends on the Copilot plan and on organization model policy.
On 2026-10-18 the Custom `security-reviewer` agent could not start, because the
model its definition names was not available (`docs/SECURITY-REVIEW.md`), and on
2026-10-23 `research-analyst`, `technical-writer`, `software-engineer`, and
`security-reviewer` failed to start in a VS Code Copilot SDK host. Decision 0007
expected a plan without the declared model to fall back to the client default;
that host did not fall back.

## Decision outcome

Custom agents declare `['Claude Opus 5.5 (copilot)', 'Claude Sonnet 5.5 (copilot)']`.
`spec-work-implementer` keeps its standard-tier order,
`['Claude Sonnet 5.5 (copilot)', 'Claude Opus 5.5 (copilot)']`. Setup writes
`copilot:claude-opus-5.5` to `gitlens.ai.vscode.model`. The owner's Copilot offered
both models on 2026-11-09, GitHub lists both as generally available, and the owner
chose the pair on 2026-11-09.

## Consequences

- The fallback comes from another model family, so withdrawing one model still
  leaves an entry that starts the agent.
- `tests/CustomizationFrontmatter.Tests.ps1` holds the models an agent may name and
  fails an agent that names another. The list changes only with a Decision record.
- A user whose plan or policy offers neither model gets agents that do not start in
  the Copilot SDK host. What other hosts do then was not measured.
- Model availability must be reviewed when the owner's Copilot changes its lineup.

## Confirmation

The test above passes, and each Custom agent starts in a VS Code Copilot SDK host
after a redeploy. The start check is the owner's and was open on 2026-11-09.
