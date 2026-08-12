---
status: current
last-verified: 2026-08-12
owner: software-engineer
source: CHANGELOG.md and git history
---

# Progress

## Project status

Copilot Atelier is released at `v1.1.0`. The next release is `2.0.0`, the first
published to the PowerShell Gallery. Incremental work is tracked under
`[Unreleased]` in `CHANGELOG.md`.

## Recent milestones

- **2026-08-12**: Adopted four items from a review of an external Copilot
  catalogue, reimplemented rather than copied. `pester-patterns` gained an AST
  detector for Pester v4 constructs plus a v4-to-v5 reference; against this
  repository's own suite it returns 0 `BlockBodyCommand` and 18
  `TopLevelCommand` findings, all of them deliberate discovery-time `-ForEach`
  builders, which is the signal-to-noise a detector needs to survive.
  `SkillTriggerCoverage` turns "1 Skill of 44 has ever been measured for
  discovery" into a shrink-only baseline of 38, with five sets shipped for the
  Pester and Sampler cluster whose negatives are near misses lifted from each
  other. `SecretScan` and `CustomizationFrontmatter` close the two gates that
  did not exist, the former carrying a planted-credential test because a gate
  never shown to reject is not a gate. `AGENTS.md` now names the atomic change
  set per Customization type. 603 passed, 0 failed, coverage 78.44 %.

- **2026-08-12**: Unblocked CI. Every test leg failed at *Prepare all required
  actions* on `Unable to resolve action astral-sh/setup-uv@v9`. The action
  publishes no floating major alias past `v7` — `v9.0.0` is a release tag,
  `refs/tags/v9` does not exist — so the reference was never resolvable and no
  upstream deletion occurred. Pinned to `v9.0.0`; the step takes no inputs, so
  the major bump carries no configuration risk. The lesson generalises: a
  `@vN` reference is an assumption about the publisher's tagging habit, and it
  has to be verified against the tag API rather than inferred from the release
  number.

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

- **2026-08-11**: Withdrew the claim that the trigger-eval grader scores a prose
  reply like a wrong selection. All 162 stored replies parse; the regex is
  multiline, so it matches a compliant line anywhere. Two latent defects were
  logged instead: markdown-wrapped, quoted and parenthesised answers do not
  match, and `SELECTED: x.` scores as a different skill, not a format failure.

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

- Run the five shipped trigger-query sets, then cover the 38 Skills still on the
  `SkillTriggerCoverage` uncovered baseline. The sets are authored but
  unmeasured, so the gate currently proves only that the queries exist.
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
