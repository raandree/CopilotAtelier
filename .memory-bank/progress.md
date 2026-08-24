---
status: current
last-verified: 2026-08-24
owner: software-engineer
source: CHANGELOG.md and git history
---

# Progress

## Project status

Copilot Atelier is released at `v1.1.0`. The next release is `2.0.0`, the first
published to the PowerShell Gallery. Incremental work is tracked under
`[Unreleased]` in `CHANGELOG.md`.

## Recent milestones

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
  into a project, which is where the Skill had stopped: it produced a library
  set and left the wiring to improvisation, and `WindowsAccessControl` proved
  the cost by taking three passes over its README header. Step 5 carries the
  non-guessable parts — a `<table>` cannot give a borderless two-column header
  on github.com because the markdown CSS borders every cell and the sanitiser
  strips the style that would remove it, the wordmark replaces the `<h1>` so
  `MD041` stays disabled, and a package `IconUri` must be a direct image URL
  because a repository URL is accepted and then silently shows a placeholder.
  Integration names the target repository before writing to it. The trigger
  queries had encoded the opposite boundary: "add an IconUri to the module
  manifest" was a negative pointing at `sampler-framework` and is now a
  positive. Shipped as the full atomic change set after the first commit shipped
  only half of it.

- **2026-08-14**: Added `brand-logo-system`, harvested from a task rather than
  written from general knowledge. A project identity had been produced by hand
  twice in one session and the second run hit the first run's failures again,
  so the Skill carries the three that cost real time: a text substitution over
  `width=`/`height=` also rescales every nested `<use>` and `<rect>` to the full
  canvas; the shared library's "transparent" assets are opaque PNGs with a
  checkerboard painted into their pixels, measured at 0 % transparent; and a
  board claiming the mark survives favicon size is a claim until a 16 px render
  proves it, which for a detailed mark it does not. The bundled renderer
  composes all eleven library slots from one definition plus two or three glyph
  fragments. Proven end to end against AutomatedLab, whose palette and
  gear-and-flask mark were recovered from its own 2025 logo by pixel count. The
  atomic-change-set gate fired on its own author: the first test run failed only
  `brand-logo-system has a trigger-query set`, and passed at 438/0 once the
  twenty labelled queries were added. `Prompts/brand-logo.prompt.md` starts the
  process the Skill executes, and skips the interview entirely when the
  repository already carries a logo.

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

- **2026-08-11**: Took `pester-patterns` from a 796-line body to 149 and
  `systemPatterns.md` to 86, each by moving detail to where it belongs rather
  than by raising a budget. Both baseline entries went in the same change, so
  each gate proves its fix instead of recording the intent.

- **2026-08-11**: Closed the three deferred `Set-CustomizationLink` findings,
  all of which still reproduced. Decision 0020 settles the policy: anything that
  cannot merge without loss stops the merge, and equality is proven by SHA-256
  rather than by presence. The unattended `Update-CopilotAtelier -Force` path is
  why the `Read-Host` opt-in became `-Force`. 7 tests, red then green.

- **2026-08-11**: Moved the trigger-eval sweep onto `Invoke-ShpBatch` — 26.3 s
  against 103.9 s sequential for the same cost — and re-measured
  `skill-creator`, where editing against train took train to 15/15 while
  validation fell to 6/8, so the overfitting signal left the edit uncommitted.

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
