---
status: accepted
date: 2026-04-23
last-verified: 2026-07-24
owner: software-engineer
source: Instructions
supersedes: none
---

# Scope Instructions with applyTo

## Context and problem statement

Loading every language and framework rule into every task wastes context and
increases conflicts.

## Decision outcome

Give each Instruction the narrowest practical `applyTo` glob. Reserve
`applyTo: "**"` for lifecycle behavior that genuinely applies to every turn.

## Consequences

- File-specific rules load only when relevant.
- Shared lifecycle behavior remains single-source.
- Incorrect globs can suppress required rules and therefore require tests and
  diagnostics.

## Confirmation

Validate frontmatter, inspect VS Code Customization diagnostics, and run the
Instruction regression tests.
