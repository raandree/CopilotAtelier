---
status: current
last-verified: 2026-08-25
owner: software-engineer
source: CHANGELOG.md and git history
---

# Progress

## Project status

Copilot Atelier is published to the PowerShell Gallery and released at `v3.1.0`
(2026-08-07). `main` builds as `4.0.0-preview*`. Incremental work is tracked
under `[Unreleased]` in `CHANGELOG.md`.

## Recent milestones

- **2026-08-25**: Closed the release provenance gap. `plugin.json` had announced
  `2.0.0` through two releases because the changelog rollover for `v3.0.0` and
  `v3.1.0` never reached `main` — `Create_ChangeLog_GitHub_PR` ran and opened
  both pull requests (`origin/updateChangelogAfterv3.0.0`,
  `origin/updateChangelogAfterv3.1.0`), nobody merged them, and the task cannot
  fail a build because it swallows every error in a `catch` that only logs. The
  missing sections are reconstructed from those two commits rather than from the
  commit log, verified lossless line by line, and the new gate in
  `PluginManifest.Tests.ps1` fails whenever a published non-preview tag has no
  section — with a tag at `HEAD` exempt, or every tag push would deadlock on its
  own gate before `deploy` ever runs.

- **2026-08-24**: Closed the README catalogue gap and built the gate that would
  have caught it. `AGENTS.md` had required an *Available Skills* row per Skill
  since 2026-08-12 with nothing checking it, and the drift was 36 rows against
  45 shipped Skills — `skill-creator` and `agent-evals` among the nine missing,
  which are the two a new contributor needs first. `SkillCatalogue.Tests.ps1`
  checks both directions and guards its own parser with a count assertion,
  because a moved heading would otherwise pass with zero cases. Shown to reject
  before being accepted: one row removed gives 133 passed and 1 failed on
  `agent-evals has a catalogue row`; restored, 136 of 136 pass. In the same
  change the unsupported `german-tax-research` red flag was dropped rather than
  retro-fitted with invented evidence — it named editing-tool hygiene, not a tax
  rule, and no reference taught it.

- **2026-08-24**: Hardened `german-tax-research` against two failures that
  produce a confidently wrong number instead of a visible error. A title,
  filename, or category column is metadata written for another purpose, so the
  finding must be the operative sentence: an e-mail headed `Your sessions at
  NIC Cloud Connect 2023` read *have not been accepted* in its body. And a
  transaction set filtered by sign hides the entry that changes the answer —
  `1.725,05 €` of flight charges netted `848,12 €` after a refund three days
  later. The `description` is untouched, so no eval sweep is owed.

- **2026-08-19**: Stored `Get-SteuerFrist.ps1` as UTF-8 with a BOM; the script
  emits German legal text, so the ANSI fallback would reach a Finanzamt as
  mojibake. The triage is the durable part: `ai/german-tax-research-skill`
  looked unmerged under three-dot `git diff main...branch`, which reports only
  the branch side of the merge base. `main` already held the Skill
  byte-identical and the branch was 38 commits behind. Compare trees two-dot.

- **2026-08-14**: Extended `brand-logo-system` to cover integrating the assets
  into a project, where the Skill had stopped and left the wiring to
  improvisation. Step 5 carries the non-guessable parts: github.com borders
  every table cell and strips the style that would remove it, so a borderless
  two-column README header needs a float rather than a `<table>`, and a package
  `IconUri` must be a direct image URL because a repository URL is accepted and
  then silently shows a placeholder. Integration names the target repository
  before writing to it. Shipped as the full atomic change set after the first
  commit shipped only half of it.

- **2026-08-14**: Added `brand-logo-system` and the `brand-logo` Prompt that
  starts it, harvested from a task that had been done by hand twice and hit the
  same three failures both times: resizing an SVG by text substitution rescales
  every nested `<use>` and `<rect>`, the shared library's "transparent" assets
  are opaque PNGs measured at 0 % transparent pixels, and favicon legibility is
  a claim until a 16 px render proves it. Proven end to end against
  AutomatedLab, whose palette and mark were recovered from its own 2025 logo by
  pixel count. The atomic-change-set gate fired on its own author: the first run
  failed only `brand-logo-system has a trigger-query set`, then passed 438/0.

- **2026-08-19**: Replaced exact-set grading in the route-selection evaluator
  after review found it misaligned with the risk it exists to catch. A reply
  selecting a superset reads more context but loses none, yet scored the same as
  a dropped route, and Decision 0014 had turned that into a pass^k demand no run
  could meet. Grading now asks the sibling gate's question — did anything
  required go missing — and reports recall, precision, over-selection, and exact
  matches as cost. The obvious hole was closed in a test, not in prose: a reply
  naming every route passes safety at 100 % recall and 50 % precision. No
  precision floor is set; inventing one unbacked by a baseline is the mistake
  being undone.

- **2026-08-13**: Added an offline natural-language Memory Bank route-selection
  evaluator, rebased onto `main` on 2026-08-19. `Prepare` emits label-free
  prompts containing one real task and the compact index; `Grade` accepts strict
  JSON route arrays, handles Full-read fallback explicitly, and reports pass@k
  plus pass^k. Twenty-five real cases produced 75 isolated prompts without
  contacting a model, and the replies are not executed yet, so reliability is
  not claimed.
- **2026-08-12**: Adopted four items from a review of an external Copilot
  catalogue, reimplemented rather than copied. `pester-patterns` gained an AST
  detector for Pester v4 constructs plus a v4-to-v5 reference; against this
  repository's own suite it returns 0 `BlockBodyCommand` and 18
  `TopLevelCommand` findings, all deliberate discovery-time `-ForEach` builders,
  which is the signal-to-noise a detector needs to survive.
  `SkillTriggerCoverage` turns "1 Skill of 44 has ever been measured for
  discovery" into a shrink-only baseline of 38. `SecretScan` and
  `CustomizationFrontmatter` close the two gates that did not exist, the former
  carrying a planted-credential test because a gate never shown to reject is not
  a gate. `AGENTS.md` now names the atomic change set per Customization type.

- **2026-08-12**: Unblocked CI. Every test leg failed at *Prepare all required
  actions* on `Unable to resolve action astral-sh/setup-uv@v9`. The action
  publishes no floating major alias past `v7`, so the reference was never
  resolvable and no upstream deletion occurred. The lesson generalises: a `@vN`
  reference is an assumption about the publisher's tagging habit, and it has to
  be verified against the tag API rather than inferred from the release number.

- **2026-08-11**: Three curation and correctness landings. `pester-patterns`
  went from a 796-line body to 149 and `systemPatterns.md` to 86, each by moving
  detail rather than raising a budget, with both baseline entries removed in the
  same change. The three deferred `Set-CustomizationLink` findings all still
  reproduced and were closed red-then-green under Decision 0020: nothing merges
  that cannot merge without loss, equality is proven by SHA-256, and the
  `Read-Host` opt-in became `-Force` because `Update-CopilotAtelier -Force` runs
  unattended. The trigger-eval sweep moved onto `Invoke-ShpBatch` at 26.3 s
  against 103.9 s sequential, and the `skill-creator` re-measurement left its
  edit uncommitted: train reached 15/15 while validation fell to 6/8.

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

- Run the seven shipped trigger-query sets, then cover the 38 Skills still on
  the `SkillTriggerCoverage` uncovered baseline. The sets are authored but
  unmeasured, so the gate currently proves only that the queries exist. Execute
  mode needs ShellPilot plus a paid backend, neither present on this machine.
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
