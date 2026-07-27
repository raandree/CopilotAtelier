---
status: accepted
date: 2026-04-23
last-verified: 2026-07-24
owner: software-engineer
source: Skills
supersedes: none
---

# Require Skill frontmatter

## Context and problem statement

VS Code cannot discover a Skill reliably without bounded metadata that tells
the agent what the Skill does and when to load it.

## Decision outcome

Every `SKILL.md` starts with `name` and `description`; the name matches the
folder and the description includes task triggers and exclusions.

## Consequences

- Skills remain discoverable and progressively loaded.
- Descriptions must stay under the Agent Skills 1,024-character limit.
- Detailed references remain one link level below `SKILL.md`.

## Confirmation

Validate Skill frontmatter and body budgets with repository tests and
Markdown lint.
