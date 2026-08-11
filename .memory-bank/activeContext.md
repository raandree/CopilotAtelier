---
status: current
last-verified: 2026-08-11
owner: software-engineer
source: current task evidence
---

# Active context

## Current focus

Close the conformance gaps a web audit found against the live Agent Skills
sources, then return to the trigger-eval iteration for `skill-creator`.

## Implemented

- `Skills/skill-creator/SKILL.md` — cites `using-scripts`, the fifth upstream
  authoring page, and carries its rules as **Design the interface for a
  non-interactive caller**: never prompt, `--help`, actionable errors, stdout
  versus stderr, bounded output, distinct exit codes, idempotency, dependencies
  declared in the script. Frontmatter now points at the optional fields and
  records that `context: fork` is why two Skills fail `skills-ref`. 473/500.
- The keyword rule is narrowed in all four files that state it: the
  specification wants domain keywords, and only failed-query wording overfits.
- `Reference/howto-write-skills.md` — "third person, always" replaced by the
  reconciliation `skill-creator` already carried; sources reordered so the open
  standard's five pages lead and the VS Code surface is named.
- `tests/PluginManifest.Tests.ps1` — first validation of `plugin.json`: name,
  component paths, version against the newest released changelog section, and
  the `$schema`-with-capital-`Skills` trap. Manifest gained `license`,
  `repository`, `homepage`, `keywords`.
- `tests/SkillFrontmatter.Tests.ps1` — the over-budget baseline is now a map of
  Skill to current body length, so a baselined body cannot grow further. A
  second ratchet holds descriptions to a 1000-character soft cap below the 1024
  hard cap, with the eight Skills already past it pinned to their current
  length; `authenticated-web-extraction` sits at exactly 1024.
- `run-trigger-evals.ps1` — `Execute` mode probes `Invoke-Shp` for
  `-Temperature` before the loop and throws once, naming the resolved build and
  the fix. The probe tests the parameter, not the version: `0.4.0-preview0003`
  reports `0.4.0`, so the `compatibility` claim "ShellPilot 0.4.0 or later"
  passed the build that fails. That field now names `0.4.0-preview0004` and says
  why a version test cannot decide it. `tests/TriggerEvalHarness.Tests.ps1`
  stands a real stale module on disk rather than a bare function, so the message
  it asserts carries a version, a prerelease and a path.
- The machine's ShellPilot is current: `0.4.0-preview0005` at
  `~\Documents\PowerShell\Modules\ShellPilot\0.4.0`, built from
  `V:\Git\ShellPilot` at tag `v0.4.0-preview0005` with `$env:ModuleVersion`
  supplying what GitVersion could not — neither GitVersion nor dotnet exists on
  this host, so a plain Sampler build stamps the source manifest's `0.0.1` and
  loses to the installed `0.4.0`. The displaced `preview0003` is kept at
  `~\Documents\PowerShell\ShellPilot-0.4.0-preview0003.backup`, outside any
  module path.

## Focused evidence

- Detached Pester over `SkillFrontmatter`, `PluginManifest`, `SharedLifecycle`:
  206 passed, 0 failed, 10 skipped, exit 0. `markdownlint-cli2` reports 0 issues
  across the four changed Markdown files. The last full `./build.ps1 -Tasks
  build, test` before these edits: 447 passed, 0 failed, coverage 70.67 %.
- Paired sweeps, same 44-skill catalogue, same `claude-haiku-4.5`, same
  description (`57b2cf9`), 54/54 succeeding each, 0.60 USD each:

  | | train | validation | false negatives |
  |---|---|---|---|
  | `-Temperature 0` | 10/10 (100%) | 6/8 (75%) | `pos-07`, `pos-09` |
  | unpinned | 10/10 (100%) | 5/8 (62%) | `pos-06`, `pos-07`, `pos-09` |

- **13 points of validation was sampler noise.** `pos-06` scored 1.00 pinned and
  0.33 unpinned; unpinned it would have been "fixed" by editing a description
  that already worked. That row is the whole argument for the parameter.
- Two failures survive pinning and are real. `pos-07`
  (`kannst du aus dieser Anleitung einen wiederverwendbaren Skill bauen?`) is
  **0 of 3 both ways** — a repeatable miss on a German request. `pos-09`
  (`should this be one skill or split into references?`) is 1 of 3 both ways.
  Both are plausibly the cost of the category-level rewrite: `USE FOR:` used to
  carry the literal `split into references` and `body too long`.
- The earlier "train 10/10, validation 7/8" figure taken on 2026-08-11 by the
  ShellPilot session is **withdrawn**: it used `-SkillRoot` at the repository
  root, so the judge chose from 88 entries with every skill duplicated.

## Open findings

- `-Temperature 0` reduces variance but does not remove it: `pos-04` still
  scored 0.67 pinned. The harness exposes no `-Seed`.
- **Withdrawn: the grader does not mis-score prose.** All 162 stored replies
  under `%TEMP%\trigger-evals\` and `.evalwork\` parse; none is unparseable. The
  reply cited as prose, `skill-creator-temp0\neg-01.rep2`, leads with
  `SELECTED: none` and was graded `none` — the quoted fragment is line 3 of the
  explanation beneath it. The regex is multiline, so a compliant line anywhere in
  the reply is found. 16 of 162 replies do append prose after a compliant line,
  and every one answers `none`: the judge obeys the format, then explains why it
  declined.
- Two grader defects survive that measurement, both latent at incidence 0.
  `**SELECTED:** x`, `` SELECTED: `x` ``, `> SELECTED: x` and `SELECTED: x (why)`
  do not match at all; `SELECTED: x.` matches but captures `x.`, so a correct
  answer is scored as a *different skill* rather than as a format failure.
  Hardening the capture is cheap insurance — decide it on its own merits, not on
  the withdrawn premise.
- `Prompts/export-emails.prompt.md` is a generation behind the copy deployed
  under `~/.copilot/prompts/` — 106 lines against 126. Back-porting is a content
  decision, left to the owner.

## Next step

Restore the domain vocabulary the category rewrite stripped from
`skill-creator`'s `USE FOR:` — the narrowed rule now permits it — and re-measure
`pos-09` on train only. `pos-07` is a non-English request and nothing upstream
covers multilingual triggering. Then the outstanding handoff prompts: prompt 07
option C, the six worst keyword-stuffed descriptions, and prompt 06's
with/without delta.

Still outstanding: give the routing reduction gate real headroom rather than the
roughly 1 KB it has now. The `GitHubToken` secret is no longer outstanding — it
is configured, and `Publish_Release_To_GitHub` has tagged every build from
`v3.0.0-preview0003` through `v3.2.0-preview0001`.
