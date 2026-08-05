---
status: current
last-verified: 2026-08-05
owner: software-engineer
source: current task evidence
---

# Active context

## Current focus

Add an evidentiary-integrity audit for long-running case files, invoked
deliberately and run in a fresh session.

## Implemented

- `Prompts/audit-case-file.prompt.md` — read-only audit of a case file and its
  unsent drafts. Rules: project memory is a finding aid, not evidence; run in a
  fresh session because a drafting agent confirms its own conclusions; author
  and addressee are part of every claim. Six hunted error classes, five
  verification results, deadline-ordered scope, explicit "not found" finding.
  Orchestrates `citation-integrity`, `devils-advocate-review`, and the severity
  labels of `code-review-and-quality`.

## Focused evidence

- Trigger: one drafting session on a live case file checked three assertions
  against the primary corpus for the first time. One was refuted by a message
  the author had sent himself, one had been framed backwards by the assistant,
  one was attackable in wording. All three had survived because nobody had
  opened the source file since the claim was written down.
- Built as a Prompt, not a Skill: deliberately invoked, fixed procedure, single
  artefact — the analogue of `peer-review.prompt.md`. A Skill would overlap
  `citation-integrity` and degrade auto-selection for both.
- Folder roles are derived from the routing table at run time, so the Prompt
  carries no project-specific paths, route names, or facts.

## Superseded focus

Cover Tom and Kai Gilb's requirements method, which no Customization touched
before this turn.

## Implemented

- `Skills/gilb-requirements-engineering` — a 322-line body over four
  references: `planguage-keywords.md`, `impact-estimation.md`,
  `evo-planning.md`, `spec-quality-control.md`. The body carries the nine-step
  protocol, a required Planguage slot template, a worked
  vague-to-quantified transformation, an anti-rationalization table, red flags,
  and a verification close.
- `grill-me` now names the new Skill in its `DO NOT USE FOR:` anti-triggers and
  hands off to it from "Pairs with". Elicitation and quantification are
  adjacent stages, not competitors.

## Focused evidence

- Nothing in the repository mentioned Gilb, Planguage, or Evolutionary Project
  Management before this turn. `grill-me` was the nearest neighbour and is
  Brooks-derived and deliberately qualitative, so its Design Concept never
  produces a `Scale`, a `Meter`, or a number.
- Placed as a Skill rather than a Custom agent: the knowledge is portable across
  harnesses and auto-triggers from any agent, while a persona must be selected,
  pins a model priority array, and carries role Memory Bank files. The
  repository ratio, 43 Skills to 11 Custom agents, is the same call made
  repeatedly.
- The first description measured 1237 characters against the 1024 cap the
  Copilot CLI silently enforces by dropping the Skill. Trimming the prose
  summary rather than the `USE FOR:` keywords brought it to 930, because only
  the keywords drive auto-selection.
- No `systemPatterns.md` entry was added. The Skill-versus-Custom-agent
  placement rule already lives in `Skills/skill-creator/SKILL.md` and
  `Instructions/copilot-authoring.instructions.md`, and the file sits at 96 of
  110 budgeted lines.
- `markdownlint-cli2` over the six new and edited files: 0 issues. Frontmatter
  parses through `ConvertFrom-Yaml`, the folder name matches `name`, the body is
  322 lines against the 500 budget, and all ten relative links resolve.

## Next step

The Skill has no evals. Write three real requirement fragments carrying
unquantified quality words, confirm the Skill triggers by name on the PRE-FLIGHT
line, and check that the output actually carries `Scale`, `Meter`, and a sourced
benchmark.

Still outstanding from the previous focus: add the `GitHubToken` repository
secret, without which the deploy job fails at its guard, and the macOS test leg
remains unproven until it runs green.
