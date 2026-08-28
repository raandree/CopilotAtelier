---
status: current
last-verified: 2026-08-27
owner: software-engineer
source: CHANGELOG.md and git history
---

# Progress

## Project status

Copilot Atelier is published to the PowerShell Gallery and released at `v4.0.0`
(2026-08-26), whose changelog section landed on `main` in #22. Incremental work
is tracked under `[Unreleased]` in `CHANGELOG.md`.

## Recent milestones

- **2026-08-28**: Added the opt-in `cycle: full` development cycle — architect,
  engineer, security reviewer, technical writer, with the reviewer as the gate
  and a two-round cap on the fix loop. The correction that shaped it: removing
  the auto-handover earlier the same day treated *automatic* as the problem,
  but the problem was *unrequested*. Consent at the entry point covers the whole
  chain, so a requested cycle may progress on its own. Close-out defers to the
  final stage or four agents each write a changelog entry and a commit for one
  change. Rules live in the agent bodies because a Skill is advisory and cannot
  bind them; one new handoff edge, `security-reviewer` to `technical-writer`,
  closed the graph. Cycle handoffs set `send: true` so a transition does not ask
  twice, and the architect carries both a trigger phrase book and a refusal list
  — "end-to-end" means end-to-end tests, so it does not start one. `cycle: off`
  ends a running chain at the current stage, which then closes out instead of
  stranding the commit, and both switches are documented in the root README and
  the agents README with the single-agent default listed first.

- **2026-08-28**: Made the Software Engineer agent's independent review opt-in.
  The old rule dispatched `security-reviewer` for "high-risk work" over a
  trigger list — security boundaries, public APIs, cross-module contracts, a
  large unfamiliar diff — that almost every change in an agent-customization
  repository matches, so a risk-scaled default behaved as an unconditional
  handover costing minutes per turn. The trigger list is unchanged; it now gates
  a recommendation instead of a dispatch. `review: on` / `auto` / `off` is
  user-set, advertised in `argument-hint`, and plain language plus the existing
  handoff button both count as `on`. The non-obvious half was
  `postflight.instructions.md`: its Definition of Done demanded independent
  review "was completed", which the model would have satisfied by dispatching
  anyway, so the gate now names the deferral path without dropping the
  requirement for other agents. `software-engineer-contoso` pins the switch to
  `on` and refuses a `review: off` downgrade.

- **2026-08-27**: Diagnosed the red `main` build (CI run 33080179473). `dc6206e`
  appended twenty lines to `systemPatterns.md`, taking it to 122 against a
  110-line budget, so `MemoryBankRouting` and `MemoryBankHealth` both failed —
  on the Windows leg alone, because it is the only leg that runs untagged tests.
  The curation already on this branch clears both. `progress.md` was then curated
  from 194 to 166 lines, because at 194 of 200 the Post-flight append that every
  Substantive turn owes would have re-broken the build on the next commit. The
  `LineBudgetNearLimit` warning names the file before it breaches, but it fails
  nothing, so a breach is still discovered by a red build after the push.

- **2026-08-27**: Added `software-engineer-contoso`, the first corporate overlay
  agent, and learned that a Markdown link between agents inherits nothing — VS
  Code resolves referenced *instructions* files, not `.agent.md`, so the first
  version ran as a bare fragment with no diagnostic. The base body is now inlined
  between markers with a byte-exact drift test in
  `tests/AgentInheritance.Tests.ps1`. The overlay only tightens: 45 tools drop to
  36 (the nine egress and supply-chain tools removed), `agents` narrows to
  `security-reviewer`, and the body carries the Contoso control set — secrets by
  reference, internal-mirror-only dependencies, a "never ship" Blocker list,
  separation of duties ending at the local working tree, a raised and partly
  mandatory review bar, and a seven-item hard stop. The subagent rule is the
  sharp one: `security-reviewer` holds `web/fetch`, so the dispatch carries
  paths and questions, never source. `systemPatterns.md` was curated from 130 to
  under its 110-line budget in the same edit; it had been over since before this
  work.

- **2026-08-27**: Fixed every hook. The host substitutes `$` tokens in a hook
  command before the child parses it, so `$b = if ($env:PLUGIN_ROOT)` arrived as
  `= if ()` and PowerShell rejected it — the never-push block, the Memory Bank
  probe, and the compaction checkpoint were all absent behind one warning
  balloon. Commands are now `$`-free (`[Environment]::GetEnvironmentVariable`,
  `Get-Variable LASTEXITCODE -ValueOnly`, `[IO.Path]::Combine('/', ...)`) and
  probe `PLUGIN_ROOT`, `~/.copilot/hooks`, then
  `~/.vscode*/agent-plugins/*/*/CopilotAtelier`. `Hooks.Tests.ps1` models the
  substitution pass and re-runs the substituted command; 68 tests pass.

- **2026-08-27**: Reworded the role-file clause in Pre-flight step 3. "Create only
  the active Custom agent's required role files" read as the agent's whole
  declared list; it now creates a role file only when the agent declares it and
  the current durable task needs it, and forbids scaffolding another agent's
  schema or pre-creating an unused declared file. Matches `memory-bank` SKILL
  step 6. Prevents empty template files that later turns route to and trust.
- **2026-08-26**: Migrated the plugin package to Agent Plugins 1.0. `plugin.json`
  declares the canonical `$schema` and drops the legacy `agents`/`skills` path
  fields; `Skills/` became root `skills/`; agents and hooks moved to
  `com.github.copilot/` with the mandated `hooks.json`; hook commands resolve
  `PLUGIN_ROOT` or the user profile; the installer maps deployed name to source
  path and sweeps legacy capitalised directories. 876 tests pass. Decision 0023.
  Two bulk scripted rewrites corrupted 129 files each and were fully restored
  from git — see the environment hazard in `activeContext.md`.
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
  line budget; `systemPatterns.md` runs close to its 110-line cap, so any new
  Decision record or relationship needs a trim in the same edit.

## Retention policy

This file keeps current state and recent milestones only. `CHANGELOG.md` and git
history are the authoritative sources for older implementation detail, release
history, and superseded decisions.

Curate the oldest milestones as soon as `Test-MemoryBankHealth.ps1` reports
`LineBudgetNearLimit` for this file. Waiting for `LineBudgetExceeded` means the
breach is discovered by a red CI build rather than by a local run.
