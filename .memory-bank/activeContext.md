---
status: current
last-verified: 2026-08-11
owner: software-engineer
source: current task evidence
---

# Active context

## Current focus

Four handoff prompts were run end to end in one session: the `skill-creator`
trigger gaps, batch dispatch for the eval harness, the deferred
`Set-CustomizationLink` findings, and the first slice of the budget work.
Nothing is committed; the working tree holds all of it for review.

## Implemented

- `Skills/skill-creator/SKILL.md` — the description covers two concepts it did
  not: building a skill out of existing material, and deciding whether
  something deserves a skill at all and whether it is one skill, two, or a
  reference. 990 to 989 characters, under the 1000-character soft-cap ratchet.
  Dropped to pay for it: `output evals` (agent-evals territory),
  `degrees-of-freedom calibration` (no query covers it), and the gotchas and
  overlap entries that were stated twice.
- `Skills/agent-evals/assets/trigger-queries.skill-creator.json` — five queries.
  `pos-10` German packaging, `pos-11` scoping decision, `pos-12` build from an
  existing document, plus `neg-10` and `neg-11` as matched near-misses so a
  keyword-stuffing edit is penalised rather than rewarded.
- `Skills/agent-evals/scripts/run-trigger-evals.ps1` — `-Dispatch Batch` is the
  default and `-ThrottleLimit` defaults to 4. `Clear-ShpChat` is gone from the
  batch path because every item is dispatched with `-History @()`; failures
  arrive as data; replies are correlated on `Id` because results land in
  completion order. `-Dispatch Sequential` is kept and documented.
  `tests/TriggerEvalHarness.Tests.ps1` grew to 21 hermetic tests.
- `source/Private/Set-CustomizationLink.ps1` — no `Read-Host`. The opt-in is
  `-Force`, surfaced on `Install-CopilotAtelier` and `Setup-CopilotSettings.ps1`.
  Anything that cannot merge without loss stops the merge and is reported, with
  equality proven by SHA-256 in `Test-CustomizationChildMatch`. Decision 0020.
- `Skills/pester-patterns/` — body 796 to 149 lines, patterns 1-13 in two
  one-level references, baseline entry removed. `.memory-bank/systemPatterns.md`
  106 to 86 lines.

## Focused evidence

- `./build.ps1 -Tasks build, test`: 518 passed, 0 failed, coverage 78.44 %,
  2 warnings. The `systemPatterns.md` budget warning is gone; `progress.md` is
  at 174 of 200, below the 180-line warning threshold.
- Routing reduction 56.11 % against the 50 % floor, up from 55.69 % before the
  curation. The recorded 49.57 % no longer holds.
- Trigger evals, all pinned at `-Temperature 0`, 198 judge calls, 2.19 USD:

  | description | train | validation |
  |---|---|---|
  | before | 13/14 (93%) | 7/8 (88%) |
  | after | 15/15 (100%) | 6/8 (75%) |

- Dispatch comparison on the identical 69-call sweep: 26.3 s batched at
  `-ThrottleLimit 4` against 103.9 s sequential, 0.7623 against 0.7659 USD.

## Open findings

- **The description edit is not proven to be an improvement.** Train climbed to
  100 % while validation fell, which is the overfitting signal. It is left
  uncommitted for the owner to accept or revert.
- **`-Temperature 0` does not make the judge reproducible.** Three pinned sweeps
  of one description scored `pos-09` at 1/3, 2/3 and 3/3, and `pos-06` at 3/3,
  1/3 and 2/3. Any query near the 0.5 trigger threshold moves between runs, so a
  single sweep cannot settle a marginal query. `Invoke-ShpBatch` exposes a
  `-Seed` the harness does not use yet.
- **The recorded cause of `pos-07` was wrong.** Its literal English translation
  fails 0/3 while a differently worded German request passes 3/3, so the miss is
  a concept gap rather than a language one. `pos-07` itself still fails.
- The failure-isolation test adds one build warning naming a deliberately failed
  stub item. `-WarningAction SilentlyContinue`, `-WarningAction Ignore` and a
  stream redirect were all measured; Pester surfaces the warning regardless.
- Two grader defects survive, both latent at incidence 0. `**SELECTED:** x`,
  `` SELECTED: `x` ``, `> SELECTED: x` and `SELECTED: x (why)` do not match at
  all; `SELECTED: x.` matches but captures `x.`, so a correct answer is scored
  as a different skill rather than as a format failure.
- `Prompts/export-emails.prompt.md` is a generation behind the copy deployed
  under `~/.copilot/prompts/` — 106 lines against 126. Back-porting is a content
  decision, left to the owner.

## Next step

Decide whether to keep or revert the `skill-creator` description edit. Then the
next budget slice: `german-legal-research` at 780 body lines is the worst of the
nine Skills still baselined.
