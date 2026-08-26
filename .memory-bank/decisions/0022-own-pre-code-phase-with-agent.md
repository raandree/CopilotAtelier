---
status: accepted
date: 2026-08-26
last-verified: 2026-08-26
owner: software-architect
source: Agents/software-architect.agent.md
supersedes: none
---

# Own the pre-code phase with a Custom agent

## Context and problem statement

The `grill-me` Skill defines an adversarial requirements interview, but a Skill
is advisory content while a Custom agent body is mode instruction. Inside the
Software Engineer Custom agent the two conflict directly: that body forbids
asking for confirmation on a reversible action and opens its loop on the named
file or symbol. The Skill loses, so no agent reliably ran the interview and the
release pipeline started at code development with no owner for the phase where
the requirement is still text.

## Decision outcome

Ship `software-architect` as a Custom agent whose deliverable is a signed-off
Design Concept, never an implementation. Scale interview depth to blast radius,
chain `gilb-requirements-engineering` when an unquantified quality word
survives, and connect to implementation through Agent-to-agent handoffs rather
than subagent invocation, so the interview keeps a direct channel to the user.

Reduce the toolset to 31 tools by removing every sanctioned validation path —
test runner, task runner, notebook execution, and code interpreter. Retain
`edit/editFiles` and `execute/runInTerminal`, because Post-flight requires a
Memory Bank update, a changelog entry, and a local commit on every Substantive
turn.

## Consequences

- The guarantee is bounded and must be stated as such: the agent is not
    prevented from writing code, it is prevented from closing the Definition of
    Done on a code change, which makes the handoff the only productive exit.
- `projectbrief.md` ownership moves to this Custom agent, with the Software
    Engineer and Technical Writer as co-curators.
- Decision records are authored at sign-off instead of reconstructed from the
    implementation afterwards.
- The Software Engineer gains a return handoff for a requirement gap that local
    evidence cannot resolve.

## Confirmation

`tests/SharedLifecycle.Tests.ps1` fingerprints the tool list, the handoff
targets, and the role-specific Memory Bank section for both agents.
`tests/CustomizationFrontmatter.Tests.ps1` asserts the slug name, the
description, and the model priority array with a generally available fallback.
