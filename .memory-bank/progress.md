---
status: current
last-verified: 2026-08-11
owner: software-engineer
source: CHANGELOG.md and git history
---

# Progress

## Project status

Copilot Atelier is released at `v1.1.0`. The next release is `2.0.0`, the first
published to the PowerShell Gallery. Incremental work is tracked under
`[Unreleased]` in `CHANGELOG.md`.

## Recent milestones

- **2026-08-11**: Took the worst over-budget Skill and the tighter Memory Bank
  file back under budget. `pester-patterns` split from a 796-line body to 149,
  with patterns 1-13 moved into two one-level references and patterns 0 and 14
  — the rules that apply to every run — kept in the body; its baseline entry is
  gone, so the gate proves the fix instead of documenting the intent. Its
  description was not touched, so the trigger surface is unchanged. Nine Skills
  remain baselined. `systemPatterns.md` dropped from 106 lines to 86 by deleting
  the repository tree, a changing inventory that duplicated `techContext.md` and
  broke this file's own rule; its build warning is gone. Two premises did not
  hold on inspection: `techContext.md`'s per-test-file inventory was already
  curated away, and the routing reduction is 56.11 % rather than the recorded
  49.57 %, moving further above the floor with each curation.

- **2026-08-11**: Closed the three deferred `Set-CustomizationLink` findings,
  all of which still reproduced. The `Read-Host` is gone: the opt-in is now
  `-Force`, surfaced on `Install-CopilotAtelier` and `Setup-CopilotSettings.ps1`,
  because the function is reachable unattended through
  `Update-CopilotAtelier -Force` where a prompt waits forever rather than
  failing. Measured before the fix: a child present in both places lost the
  deployed copy (`126 lines` gone, `106 lines` left), and `Copy-Item -Recurse`
  materialised a junction's outside content inside the target. Decision 0020
  settles the policy — anything that cannot merge without loss stops the merge
  and nothing is copied or removed, with equality proven by SHA-256 rather than
  by presence. 7 tests, red against the previous implementation, green against
  the fix.

- **2026-08-11**: Moved the trigger-eval sweep onto `Invoke-ShpBatch`. The
  identical pinned 69-call sweep runs in 26.3 s batched at `-ThrottleLimit 4`
  against 103.9 s sequential for the same 0.76 USD, which is what makes the
  N x R x M model-tier comparison practical. `-Dispatch Sequential` is kept so
  an older run stays reproducible. Batch items are stateless by contract, so
  `Clear-ShpChat` is gone from that path; failures arrive as data; and replies
  are correlated on `Id`, because results land in completion order. The
  measurement itself did not move — but the control did the real work: two
  *sequential* runs of one description disagreed with each other as much as
  batch disagreed with sequential (`pos-09` 1/3 then 2/3, `pos-06` 3/3 then
  1/3). `-Temperature 0` reduces run-to-run judge variance without removing it,
  so any query near the 0.5 threshold moves between runs. 21 harness tests,
  still hermetic.

- **2026-08-11**: Re-measured `skill-creator`'s two standing trigger gaps and
  found the recorded cause wrong. A pinned baseline over an extended query set
  gave train 13/14 and validation 7/8: `pos-09` now scores 3/3, so the "1 of 3"
  recorded against it no longer reproduces. An 18-call probe then isolated the
  `pos-07` variable — its literal English translation fails 0/3 while a
  differently worded German request passes 3/3, so the miss is the concept
  "build a skill out of existing material", not the language. Two train
  stand-ins for that concept and for the scoping decision, plus two matched
  near-miss negatives, are now in the query set. Editing the description
  against train only (990 to 989 characters, dropping `output evals`,
  `degrees-of-freedom calibration` and the duplicated gotchas and overlap
  entries) took train to 15/15 — but validation fell to 6/8, because `pos-09`
  dropped from 3/3 to 1/3 while its train stand-in rose to 3/3. Train climbing
  while validation falls is the overfitting signal, so the edit is left
  uncommitted for the owner rather than claimed as an improvement. 198 judge
  calls, 2.19 USD.

- **2026-08-11**: Measured the claim that the trigger-eval grader scores a prose
  reply like a wrong selection, and withdrew it. All 162 stored replies parse;
  the reply cited as evidence leads with `SELECTED: none`, and the quoted
  fragment was line 3 of the explanation beneath it. The regex is multiline, so
  it finds a compliant line anywhere in a reply. No harness change: a
  three-outcome taxonomy would report `unparseable = 0` on every run to date.
  Two latent defects were logged instead — markdown-wrapped, quoted and
  parenthesised answers do not match, and `SELECTED: x.` captures `x.` and is
  therefore scored as a different skill rather than as a format failure.

- **2026-08-11**: `run-trigger-evals.ps1 -Mode Execute` probes `Invoke-Shp` for
  `-Temperature` and throws once instead of failing 54 calls in the binder. It
  tests the parameter, not the version: `0.4.0-preview0003` reports `0.4.0`, so
  the Skill's own "0.4.0 or later" claim passed the build that fails. The
  machine now carries `0.4.0-preview0005`, built with `$env:ModuleVersion`
  because this host has no GitVersion and Sampler otherwise stamps `0.0.1`.

- **2026-08-11**: Audited the customization library against the live upstream
  sources and closed six gaps. The category-level `USE FOR:` rewrite had
  conflated two different upstream rules — the specification wants domain
  keywords, only failed-query wording overfits — which is what `pos-09` had been
  paying for; the rule now reads "keep the domain vocabulary, drop the
  failed-query wording" in all four files. `skill-creator` gained the fifth
  upstream authoring page it never cited, `using-scripts`, plus a pointer to the
  optional frontmatter fields. The primer's "third person, always"
  contradiction and its Anthropic-first source list are fixed. Three guards
  landed: `plugin.json` is validated for the first time, including version drift
  and the `$schema`-versus-capital-`Skills` trap, and the over-budget Skill
  baseline and the near-cap descriptions both became per-Skill high-water marks.

- **2026-08-11**: Audited the Agent Skills guidance refresh and remediated it.
  The content held up — no truncation, no encoding drift, both upstream sources
  re-verified — but the process did not: committed and pushed against a standing
  "do not commit", no Memory Bank or changelog entry, and a harness run left 108
  scratch files inside the published `Skills/` payload that `Copy-Item -Recurse`
  would have shipped to the Gallery. The `skills-ref` gate was real locally and
  inert in CI, because nothing installed `uv` there. Now closed: scratch is
  ignored and pruned, CI installs `uv` and the gate throws rather than skips, a
  negative fixture proves it rejects a bad `name`, and `agent-evals` declares
  the dependencies it had silently acquired. The handoff's "CHANGELOG.md does
  not parse" premise was false throughout — all four supposed pre-existing
  failures pass under `build.ps1` and appear only under a bare `Invoke-Pester`.

## Stable capabilities

- Deterministic lifecycle hooks that block remote mutation and prove Memory Bank
  presence without relying on model compliance.
- Screenshot documentation for modifiable Windows applications, existing or
  third-party executables without source access, and windows the user already
  has open.
- One-command, idempotent Setup script with Windows, macOS, and Linux path
  handling.
- One Canonical target exposed through `~/.copilot` Discovery links, with
  opt-in Claude Code and Agent Skills links.
- Agent plugin packaging for installation from a Git URL.
- Role-specific Custom agents with Agent-to-agent handoffs, model priority
  arrays, and explicit subagent eligibility.
- File-scoped Instructions and on-demand Skills with declared environment
  requirements.
- Prompt templates for repeatable development, research, legal, and operations
  workflows.
- Detached Pester and build execution with persistent completion evidence.
- Test-first behavior changes, regression guards, risk-scaled review, and
  agentic-security checks.
- Routed Memory Bank loading with deterministic non-inferiority, health,
  provenance, compactness, and rollback checks.

## Open work

- Split the nine Skills still on the `SkillFrontmatter` over-budget baseline
  into bodies under 500 lines plus one-level references, one per change,
  removing each from the baseline as it lands. `german-legal-research` at 780
  body lines is the next worst.
- Continue splitting oversized auto-applied Instructions into concise enforced
  rules plus on-demand Skill references where that can be done without losing
  behavior.
- Keep Custom agent bodies within explicit prompt budgets and add deterministic
  regression checks for other frequently used agents.
- Extend the routing eval set when real retrieval failures are observed.
- Add Markdown linting to continuous integration when the required runtime is
  available.
- Review model identifiers when Copilot model availability changes; the last
  entry of every agent `model` array must stay GA.
- Evaluate the remaining VS Code surfaces that no Customization covers yet:
  the agent host and its harness selection, `chat.assistedPermissions.enabled`,
  and organization-level instructions and agents.
- Curate `techContext.md` and `systemPatterns.md` when either approaches its
  line budget. The per-test-file inventory `techContext.md` once carried is
  already gone, and `systemPatterns.md` now has 24 lines of headroom, which the
  Decision index consumes one line at a time.

## Retention policy

This file keeps current state and recent milestones only. `CHANGELOG.md` and git
history are the authoritative sources for older implementation detail, release
history, and superseded decisions.

Curate the oldest milestones as soon as `Test-MemoryBankHealth.ps1` reports
`LineBudgetNearLimit` for this file. Waiting for `LineBudgetExceeded` means the
breach is discovered by a red CI build rather than by a local run.
