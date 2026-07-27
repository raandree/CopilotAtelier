---
status: accepted
date: 2026-05-27
last-verified: 2026-07-24
owner: software-engineer
source: Prompts/session-handoff.prompt.md
supersedes: none
---

# Store Session handoffs separately

## Context and problem statement

Long-running work needs a portable continuation artifact without mixing
per-session details into curated project history.

## Decision outcome

Write Session handoffs under `.memory-bank/session/` with UTC names. Exclude
generated handoffs from version control and require explicit attachment in the
receiving session.

## Consequences

- Fresh sessions can resume from a bounded artifact.
- Session ephemera does not pollute `progress.md` or git history.
- Agent-to-agent handoffs remain the in-session mechanism.

## Confirmation

Verify Prompt output paths, `.gitignore`, and the tracked session README.
