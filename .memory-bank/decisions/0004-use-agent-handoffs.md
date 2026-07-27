---
status: accepted
date: 2026-04-23
last-verified: 2026-07-24
owner: software-engineer
source: Agents
supersedes: none
---

# Use Agent-to-agent handoffs

## Context and problem statement

Implementation, review, documentation, and troubleshooting require different
role-specific behavior without losing in-session context.

## Decision outcome

Declare Agent-to-agent handoffs in Custom agent frontmatter. Use the Software
Engineer, Security Reviewer, Technical Writer, and Technical Troubleshooter as
the core release workflow; keep domain Custom agents supplementary.

## Consequences

- Users can transition between roles with a pre-filled next action.
- Tool access remains role-specific and least privilege.
- Agent-to-agent handoffs remain distinct from Session handoffs.

## Confirmation

`tests/SharedLifecycle.Tests.ps1` fingerprints every handoff target and count.
