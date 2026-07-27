---
status: accepted
date: 2026-07-24
last-verified: 2026-07-24
owner: software-engineer
source: Instructions/preflight.instructions.md
supersedes: duplicated-agent-lifecycle
---

# Centralize shared lifecycle behavior

## Context and problem statement

Repeating Pre-flight, Post-flight, and per-tool narration in every Custom agent
consumes context and allows shared quality rules to drift.

## Decision outcome

Keep shared lifecycle behavior in deployed Pre-flight and Post-flight
Instructions. Keep role workflows, quality gates, tool lists, handoffs, and
role-specific Memory Bank extensions in Custom agents.

## Consequences

- Shared behavior has one deployed source.
- Every substantive edit still receives focused validation, final validation,
  and self-review.
- Independent review scales with risk instead of repeating routine checks.

## Confirmation

`tests/SharedLifecycle.Tests.ps1` fingerprints tools, handoffs, and role
sections while rejecting duplicate lifecycle blocks.
