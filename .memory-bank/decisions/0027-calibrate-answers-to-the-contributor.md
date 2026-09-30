---
status: accepted
date: 2026-09-30
last-verified: 2026-09-30
owner: software-engineer
source: com.github.copilot/rules/contributor-calibration.instructions.md
supersedes: none
---

# Calibrate answers to the contributor, never store levels in a repository

## Context and problem statement

Contributors who are not experts in a project's field could not follow agent
output or answer its questions, while experts lost time on explanations they
did not need. Audience handling existed only for artifacts, and `grill-me`
turned every unanswerable question into a `TBD` with no path forward for a
contributor working alone.

## Decision outcome

Calibrate the chat to the contributor's Familiarity level per Knowledge area:
`new`, `familiar`, or `expert`, with `familiar` as the default. Deliver it in
two phases.

Phase 1 ships the always-on `contributor-calibration` Instruction and the
`/simpler` and `/deeper` Prompts:

- Every technical decision question carries a recommended answer and a
  `not sure, you pick` option at every level. A delegated answer becomes an
  explicit assumption flagged for expert review.
- The level decides whether a question leads with the plain-language
  recommendation or with the precise term; the precise term always appears.
- Levels are session-scoped and never written to any repository file.
- A level changes wording and depth, never warnings, validation, tests, or
  review. `new` areas get more expert-check guidance.
- `grill-me`, `software-architect`, and `gilb-requirements-engineering` record
  a delegated answer as a flagged assumption instead of blocking.

Phase 2 is designed by `software-architect` as a Design Concept, within these
agreed constraints:

- A private contributor profile lives outside every repository, in the synced
  CopilotAtelier folder, in a subfolder the installer never manages.
- A machine without that folder imports one file, for example with
  `Copy-LabFileItem` on an AutomatedLab VM. A missing profile falls back to
  `familiar`. A change on an unsynced machine is reported as saved on that
  machine only, with an export offer; per-area dates let the newer rating win.
- The SessionStart hook resolves the git identity as a lookup key, not as
  proof, with aliases and a fallback when git has none.
- An interview that is offered, never forced, fills unrated areas; it never
  runs in Q&A, unattended runs, or subagents.
- Opt-out is sticky, reversible, and deletable. The question rules stay on
  after opt-out.

## Consequences

- Personal familiarity data never enters a project repository, so a
  self-assessment stays private and honest, and no other committer can edit
  what shapes another contributor's session.
- The Instruction loads on every turn, so a test caps its size.
- Until Phase 2, a contributor restates levels in each session.
- Prompts run only in the VS Code extension host; in other clients the same
  request in words reaches the Instruction.
- Structural tests prove the wording. A private behavior eval built from 17
  real-chat cases (`claude-opus-5`, K=3) raised the paired pass rate from 55.6%
  to 93.3%: decision questions from 0% to 100%, explanation content only from
  83.3% to 90.0%. Two gaps remain: no concrete example for an abstract finding,
  and no statement of how a derived result was obtained.

## Confirmation

`tests/ContributorCalibration.Tests.ps1` asserts the Instruction's scope, size,
levels, question rules, session-only levels, and safety rule, the two Prompts,
the delegated-answer handling in `grill-me`, `software-architect`, and
`gilb-requirements-engineering`, the `memory-bank` safeguard, and both Glossary
terms. The behavior eval stays outside the repository because its cases come
from the contributor's private chats; its grader self-check must pass 17 of 17
before a paid run.
