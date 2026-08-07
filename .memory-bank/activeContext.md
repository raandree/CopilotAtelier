---
status: current
last-verified: 2026-08-07
owner: software-engineer
source: current task evidence
---

# Active context

## Current focus

Carry the shading Word silently drops through `pandoc-docx-export`, and repair
the changelog entry that recorded it.

## Implemented

- `Skills/pandoc-docx-export/SKILL.md` — Recipe 3 gained **Grey Shading for
  Block Quotes and Inline Code**: the `BlockText` paragraph and `VerbatimChar`
  character styles, both `w:shd` patches with print-legible fills, the optional
  left bar, and a verification snippet that counts both styles in the produced
  `word/document.xml`. Gotcha #6 records the enforced OOXML child order for
  `w:pPr` and `w:rPr`. Six triggers added to the description; the workflow step
  for the reference document updated to match.
- `CHANGELOG.md` — the new entry had replaced the `subagent-dispatch` bullet of
  2026-08-06 and absorbed its 1922-character body as its own second paragraph.
  Split back into two bullets; the restored entry is byte-identical to `HEAD`.

## Focused evidence

- Pandoc maps both constructs correctly; the loss is in the stock reference
  document, where neither style carries a fill. Nothing warns, so verification
  counts `w:val="BlockText"` and `w:val="VerbatimChar"` in the output — a style
  that fails to apply falls back to body text and looks like ordinary output.
- `w:pPr` and `w:rPr` are ordered sequences. Parsing the patched `styles.xml`
  with `[xml]` catches malformed XML but not an order violation, because
  wrongly ordered children are still well-formed. Only a headless LibreOffice
  conversion to PDF proves the file opens.
- The description now measures 1013 of 1024 characters. One more trigger
  keyword breaks the cap, and an over-cap Skill is dropped silently.
- `tests/SkillFrontmatter.Tests.ps1`: 188 passed, 0 failed, 10 skipped (the
  documented over-budget baseline, which already lists this Skill at 795 body
  lines). `markdownlint-cli2` over both changed files: 0 issues.

## Superseded focus

Close the containment gap in `subagent-dispatch`: a delegated recomputation
that can see the answer it was dispatched to reproduce. Landed as **Never hand
a re-performer the answer** — expected values go in a separate file, every
other leak is named by path, the reviewer discloses what it read, and
afterwards agreement under exposure counts weaker than disagreement.

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
