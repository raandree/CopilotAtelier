---
status: accepted
date: 2026-07-16
last-verified: 2026-07-24
owner: software-engineer
source: Instructions/postflight.instructions.md
supersedes: every-turn-documentation
---

# Exempt Non-impacting turns from durable closure

## Context and problem statement

Running full Post-flight documentation for pure Q&A and self-documenting git
operations creates noise without preserving a durable project event.

## Decision outcome

Classify each turn in hindsight. Substantive turns run full Post-flight;
Non-impacting turns emit one visible exemption line and skip verification,
CHANGELOG, progress, prompt history, and commit work that does not apply.

## Consequences

- Routine questions no longer create repository churn.
- Ambiguous turns bias toward Substantive treatment.
- Post-flight owns the `promptHistory.md` append.

## Confirmation

Regression tests verify the trigger boundary and the emitted exemption format.
