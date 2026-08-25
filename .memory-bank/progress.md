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

- **2026-08-25**: Added the `copilot-usage-stats` Skill and the `/usage` Prompt
  on `Ctrl+K U`, then extended it to convert tokens into AI credits and dollars.
  A hook cannot report consumption — no hook event carries usage, the transcript
  records none, and the local `session-store.db` has no token column. Three
  measured facts: `input_tokens` already contains `cache_read_tokens`;
  `sessions.repository` holds three spellings of one repository; and `cost` is a
  legacy request multiplier, not money. Copilot has billed per token since
  2026-06-01, so cached input priced at the input rate inflates by ~10x.

- **2026-08-25**: Split `skill-creator` from 492 lines to 344 behind two
  references. The Skill carrying the progressive-disclosure rules broke them
  worst — 8 lines from the budget, no references, and an unapplied splitting
  recipe of its own. What moved was decided by "only add context the model does
  not already have": the material upstream already teaches went to
  `references/`, and the repository-specific and original material stayed.
  Description untouched, so no eval sweep is owed.

- **2026-08-25**: Re-verified `copilot-authoring.instructions.md` against the
  current VS Code and agentskills.io documentation. It had drifted into stating
  a rule the repository's own files break — prompts documented as requiring
  `agent: agent | ask` while eight name a Custom agent and one declares none.
  Corrected the Prompt, Instruction, Agent, Skill, and Hook schemas, added the
  stdout half of the hook contract, and marked which keys are house rules
  rather than platform requirements. Then applied the new rule to the file
  itself: it had no `description`, so the authoring question that arrives
  before any file exists could not activate it.

- **2026-08-25**: Closed the compaction gap. The Memory Bank had a deterministic
  entry gate and no exit gate: Post-flight is the only durable write point and
  it runs at end of turn, so a turn compacted mid-run loses everything it
  learned while its summary still claims Pre-flight ran. A `PreCompact` hook now
  writes `.memory-bank/session/compaction-<UTC>Z.md` with the trigger,
  transcript path, and repository state, and Pre-flight gained a
  *Compaction recovery* section. The split is forced by the platform, not
  chosen: `PreCompact` carries no `additionalContext`, so a hook can never reach
  the post-compaction context, while an Instruction is re-sent every request.

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

- **2026-08-14**: Added `brand-logo-system` and the `brand-logo` Prompt that
  starts it, then extended the Skill to cover integrating the assets into a
  project. Harvested from a task done by hand twice that hit the same failures
  both times: resizing an SVG by text substitution rescales every nested `<use>`
  and `<rect>`, the shared library's "transparent" assets are opaque PNGs at 0 %
  transparent pixels, favicon legibility is a claim until a 16 px render proves
  it, github.com borders every table cell so a borderless README header needs a
  float, and a package `IconUri` must be a direct image URL or it silently shows
  a placeholder. The atomic-change-set gate fired on its own author: the first
  run failed only `brand-logo-system has a trigger-query set`, then 438/0.

- **2026-08-19**: Replaced exact-set grading in the route-selection evaluator.
  A superset reply reads more context but loses none, yet scored the same as a
  dropped route. Grading now asks whether anything required went missing and
  reports recall, precision, and over-selection as cost. No precision floor is
  set; inventing one unbacked by a baseline is the mistake being undone.

- **2026-08-13**: Added an offline natural-language Memory Bank route-selection
  evaluator, rebased onto `main` on 2026-08-19. `Prepare` emits label-free
  prompts, `Grade` reports pass@k and pass^k; no model was contacted yet.
- **2026-08-12**: Added the Pester v4 AST detector, the shrink-only
  `SkillTriggerCoverage` baseline, and the `SecretScan` and
  `CustomizationFrontmatter` gates; a planted credential proves it rejects.

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
  line budget; `systemPatterns.md` has 12 lines of headroom, which the Decision
  index consumes one line at a time.

## Retention policy

This file keeps current state and recent milestones only. `CHANGELOG.md` and git
history are the authoritative sources for older implementation detail, release
history, and superseded decisions.

Curate the oldest milestones as soon as `Test-MemoryBankHealth.ps1` reports
`LineBudgetNearLimit` for this file. Waiting for `LineBudgetExceeded` means the
breach is discovered by a red CI build rather than by a local run.
