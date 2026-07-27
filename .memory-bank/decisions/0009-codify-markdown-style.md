---
status: accepted
date: 2026-07-02
last-verified: 2026-07-24
owner: software-engineer
source: .markdownlint.jsonc
supersedes: none
---

# Codify the Markdown house style

## Context and problem statement

The repository intentionally uses long changelog lines, compact tables, and
other styles that default Markdown lint rules classify as violations.

## Decision outcome

Keep one repository `.markdownlint.jsonc` that disables intentional style
rules and retains correctness checks such as one final newline.

## Consequences

- Editor, command-line, and future CI lint behavior is deterministic.
- Intentional formatting does not require mass rewrites.
- Disabled correctness rules remain explicit follow-up work.

## Confirmation

Run `markdownlint-cli2` across the repository and require zero errors.
