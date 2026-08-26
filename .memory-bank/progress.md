---
status: current
last-verified: 2026-08-26
owner: software-engineer
source: CHANGELOG.md and git history
---

# Progress

## Project status

Copilot Atelier is published to the PowerShell Gallery and released at `v3.1.0`
(2026-08-07). `main` builds as `4.0.0-preview*`. Incremental work is tracked
under `[Unreleased]` in `CHANGELOG.md`.

## Recent milestones

- **2026-08-26**: Migrated the plugin package to Agent Plugins 1.0. `plugin.json`
  declares the canonical `$schema` and drops the legacy `agents`/`skills` path
  fields; `Skills/` became root `skills/`; agents and hooks moved to
  `com.github.copilot/` with the mandated `hooks.json`; hook commands resolve
  `PLUGIN_ROOT` or the user profile; the installer maps deployed name to source
  path and sweeps legacy capitalised directories. 876 tests pass. Decision 0023.
  Two bulk scripted rewrites corrupted 129 files each and were fully restored
  from git — see the environment hazard in `activeContext.md`.
- **2026-08-26**: Gave a `description` to the twelve Instructions that lacked
  one and held the same twelve against the authoring rules. Without a
  description an Instruction is reachable only through a path its `applyTo`
  glob happens to cover, so `versioning` could not answer a pre-release
  question and `pester` could not reach the first test in a repository that has
  none. The gate is a per-file case in `CustomizationFrontmatter.Tests.ps1`,
  shown red on 12 of its 16 cases against the previous commit. The same pass
  removed eight sections that only restated rules the file had already given,
  four introductory explanations the Strict tier forbids, two link farms whose
  normative links already appear inline, and 78 decorative marks: 355 lines.
  Two defects surfaced while reading — a cross-reference naming `markdown`
  where `changelog` was meant, and two `applyTo` lists carrying patterns fully
  subsumed by a sibling pattern.

- **2026-08-26**: Renamed the seven display-name Custom agent files to their
  declared `name` slug, so every agent is addressed the same way on disk, in a
  handoff, and in a test. The defect was two addresses for one agent rather
  than casing: `%20`-encoded changelog links and a baseline map keyed on the
  display name while asserting handoffs that named the slug. Guarded by a
  filename-to-frontmatter equality assertion in
  `CustomizationFrontmatter.Tests.ps1`, shown to reject a mismatched stem that
  the existing lowercase check passes. No `name:` value changed.

- **2026-08-26**: Added the `software-architect` Custom agent as the first phase
  of the release pipeline. The gap was structural rather than stylistic:
  `grill-me` is advisory content while a Custom agent body is mode instruction,
  so the interview lost inside the Software Engineer agent every time it was
  tried, and nothing owned the requirement while it was still text. Its 31
  tools withhold every sanctioned validation path, so it cannot close the
  Definition of Done on a code change and the handoff is the only productive
  exit; `edit/editFiles` and `execute/runInTerminal` stay because Post-flight
  demands a Memory Bank write, a changelog entry, and a commit on every
  Substantive turn. Interview depth scales to blast radius so the agent stays
  selectable for small work. Decision 0022 records the reasoning, and
  `SoftwareArchitectAgent.Tests.ps1` asserts the withheld tools by name because
  a fingerprint detects change but not correctness.

- **2026-08-25**: Added the `copilot-usage-stats` Skill and the `/usage` Prompt
  on `Ctrl+K U`, then extended it to convert tokens into AI credits and dollars.
  A hook cannot report consumption — no hook event carries usage, the transcript
  records none, and the local `session-store.db` has no token column. Three
  measured facts: `input_tokens` already contains `cache_read_tokens`;
  `sessions.repository` holds three spellings of one repository; and `cost` is a
  legacy request multiplier, not money. Copilot has billed per token since
  2026-06-01, so cached input priced at the input rate inflates by ~10x.

- **2026-08-25**: Fixed the PR pipeline, where GitVersion had *succeeded* and
  the step that reads it threw anyway. `GitVersion.yml` left `feature` and
  `hotfix` unanchored, so `ai/fix-manifest-bom-ps51` matched both — `ai/` and
  `fix-` — and GitVersion warned about the extra match on the same stdout the
  pipeline parses as JSON, where `ci.yml` required the output to start with
  `{`. Both anchored, the step now locates the JSON block and echoes any
  preamble instead of discarding it, and a `-ForEach` gate asserts each
  representative branch name matches exactly one configuration.

- **2026-08-25**: Fixed `Install-Module` failing on Windows PowerShell 5.1 with
  "not a properly-formed module" on every release since `2.0.0`.
  `Create_Changelog_Release_Output` writes the changelog's release section into
  the manifest's `ReleaseNotes` and saves it without a byte-order mark; this
  repository's prose carries em dashes and, since `german-tax-research`, literal
  `€`/`§`, and Windows PowerShell 5.1 decodes a BOM-less file with the ANSI code
  page, corrupting those into mojibake that breaks the manifest's
  restricted-language parser. Reproduced directly with `Test-ModuleManifest`
  under `powershell.exe`; a new `Repair_ManifestEncoding` build task re-saves
  the manifest as UTF-8 with a BOM whenever one is missing, and a regression
  test in `module.tests.ps1` pins it.

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
  `v3.1.0` never reached `main` — `Create_ChangeLog_GitHub_PR` opened both pull
  requests, nobody merged them, and the task cannot fail a build because it
  swallows every error in a `catch` that only logs. The missing sections are
  reconstructed from those two commits, and the new gate in
  `PluginManifest.Tests.ps1` fails whenever a published non-preview tag has no
  section — with a tag at `HEAD` exempt, or every tag push would deadlock on its
  own gate before `deploy` ever runs.

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

- Restore a Windows PowerShell 5.1 CI leg now that `Repair_ManifestEncoding`
  fixes the manifest instead of working around it. The leg was dropped
  2026-07-29 for the defect this fix closes; re-adding it guards the fix and
  needs the `ci.yml` `shell: pwsh` steps distinguished from `powershell.exe`.
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
