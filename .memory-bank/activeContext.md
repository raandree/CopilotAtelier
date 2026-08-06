---
status: current
last-verified: 2026-08-06
owner: software-engineer
source: current task evidence
---

# Active context

## Current focus

Close the containment gap in `subagent-dispatch`: a delegated recomputation that
can see the answer it was dispatched to reproduce.

## Implemented

- `Skills/subagent-dispatch/SKILL.md` — new section **Never hand a re-performer
  the answer**, placed under the existing no-pre-judging rule as its mirror
  image. Expected values go in a separate file referenced by path; every other
  leak (Memory Bank files, changelogs, prior reports, commit messages) is named
  by path; the reviewer discloses what it read and when; and afterwards
  agreement under exposure is read as weaker than disagreement.
- Integrated into the frontmatter triggers (`blind re-performance`,
  `independent recomputation`), the when-to-use list, the anti-rationalization
  table, the red flags, and the verification close, plus the README Skill
  catalogue row and `CHANGELOG.md`.

## Focused evidence

- The inverse rule was already written — do not tell a reviewer what not to
  flag. Showing a re-performer the target was unwritten and is the easier of
  the two to break by accident, because it looks like helpful context.
- A "sealed" section at the end of the same brief is not a barrier. The brief is
  delivered as one text and read as one text, so a heading that says "open only
  after computing" is a request; only a separate file makes opening it an act.
- The result is asymmetric and has to be read that way: where the values were
  known early the agreements are weak, while the disagreements are stronger
  than usual because they were produced against a known target.

## Superseded focus

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
- Stale Memory Bank path removed from three Prompts — `export-emails`,
  `sync-project-emails`, `deadline-action-handoff`. Thirteen occurrences, two of
  them inside hard ABORT gates that threw on every repository following
  Decision 0001. References to the Skill named `memory-bank` and the deliberate
  legacy variant in `ubiquitous-language.instructions.md` were left untouched.

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

## Open finding

`Prompts/export-emails.prompt.md` in this repository is a generation behind the
copy deployed under `~/.copilot/prompts/` — 106 lines against 126. The deployed
version parameterises the export script with `-PersonNames` and `-FolderSlug`,
derives patterns from email addresses as well as names, and carries a rule
forbidding hardcoded names in the prompt, in commits, and in scratch files. None
of that exists here. A build and install would therefore regress a working
Prompt. Back-porting is a content decision and was left to the owner.
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
