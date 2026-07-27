---
status: accepted
date: 2026-07-02
last-verified: 2026-07-24
owner: software-engineer
source: Agents
supersedes: claude-opus-4-7
---

# Use Claude Opus 4.8 for Custom agents

## Context and problem statement

Custom agent declarations and global defaults must not drift to different
model identifiers.

## Decision outcome

Declare `Claude Opus 4.8 (copilot)` in all Custom agents and use the matching
Copilot and GitLens model identifiers in the Setup script.

## Consequences

- Per-agent and global model defaults remain aligned.
- Plans without Opus 4.8 availability fall back to their client default.
- Model availability must be reviewed when Copilot changes its lineup.

## Confirmation

Search all Custom agent frontmatter and Setup settings for the current model
identifiers.
