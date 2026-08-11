---
status: current
last-verified: 2026-08-11
owner: software-engineer
source: current task evidence
---

# Active context

## Current focus

Pin the trigger-eval judge, then re-measure `skill-creator` against the
category-level description that shipped with the audit remediation.

## Implemented

- `Skills/agent-evals/scripts/run-trigger-evals.ps1` — gained `-Temperature`,
  omit-or-send: bound, it reaches every judge call; unbound, nothing is sent, so
  no existing run moves its operating point. `0` is a meaningful temperature, so
  binding is the only safe test. `-SkillRoot` help now warns that the search is
  recursive, because pointing it at the repository root also picks up the built
  copies under `output/` and puts every skill in the catalogue twice.
- `tests/TriggerEvalHarness.Tests.ps1` — 7 tests: parameter surface, range
  rejection, forwarding, and the omitted case. Hermetic; stubs both `Invoke-Shp`
  and `Clear-ShpChat`.

## Focused evidence

- `./build.ps1 -Tasks build, test`: 447 passed, 0 failed, coverage 70.67 %
  against the 65 % threshold. The one warning is the pre-existing
  `systemPatterns.md` line-budget notice.
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

- The **installed** ShellPilot is `0.4.0` and predates `Invoke-Shp -Temperature`
  (shipped in ShellPilot `c89f14a`). `Import-Module ShellPilot` therefore yields
  a judge that rejects the parameter; the harness must be pointed at a build new
  enough to accept it. The memory-bank note that this was "blocked on ShellPilot
  exposing -Temperature" was half right — the module exposes it, this machine
  does not have that build installed.
- `-Temperature 0` reduces variance but does not remove it: `pos-04` still
  scored 0.67 pinned. The harness exposes no `-Seed`.
- The grader matches `^\s*SELECTED:\s*<name>\s*$`, so a judge that answers in
  prose scores identically to one that picks the wrong skill. At least one reply
  in these runs was prose. A format violation is not a trigger miss.
- `Prompts/export-emails.prompt.md` is a generation behind the copy deployed
  under `~/.copilot/prompts/` — 106 lines against 126. Back-porting is a content
  decision, left to the owner.

## Next step

Decide whether to restore concrete question-shaped phrases to `skill-creator`'s
`USE FOR:` for `pos-09`, and how to cover non-English requests for `pos-07` —
iterating on train only. Then the outstanding handoff prompts: prompt 07
option C, the six worst keyword-stuffed descriptions, and prompt 06's
with/without delta, which is now unblocked.

Still outstanding: add the `GitHubToken` repository secret, without which the
deploy job fails at its guard; give the routing reduction gate real headroom
rather than the roughly 1 KB it has now.
