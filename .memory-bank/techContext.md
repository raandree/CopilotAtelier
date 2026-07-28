---
status: current
last-verified: 2026-07-24
owner: software-engineer
source: Setup-CopilotSettings.ps1
---

# Tech context

## Technology stack

| Layer | Technology | Purpose |
|---|---|---|
| IDE | VS Code | Primary development environment |
| AI assistant | GitHub Copilot with Claude Opus 5, Opus 4.8 fallback | Code, review, and documentation |
| Sync | OneDrive | Cross-machine Customization distribution |
| Setup | PowerShell 5.1+ | Client configuration and file deployment |
| Version control | Git | Repository history and collaboration |
| Tests | Pester 5 | Setup and Customization regression checks |

## Deployment boundary

`Setup-CopilotSettings.ps1` deploys only these directories to the Canonical
target:

- `Agents/`
- `Instructions/`
- `Skills/`
- `Prompts/`
- `Hooks/`

The repository-local `.memory-bank/`, `tests/`, `Reference/`, `plugin.json`, and
documentation are not copied. `Keybindings/keybindings.json` is merged into the
VS Code user profile.

## Discovery model

The Canonical target is `~/OneDrive/CopilotAtelier/` when OneDrive is available
and `~/CopilotAtelier/` otherwise. Discovery links expose its five deployed
directories through `~/.copilot/{agents,instructions,skills,prompts,hooks}`.

- Windows uses NTFS junctions.
- macOS and Linux use symbolic links.
- Agents, Instructions, and Skills need no `chat.*FilesLocations` entry.
- Prompts additionally use `chat.promptFilesLocations = ~/.copilot/prompts`.
- Hooks additionally use `chat.hookFilesLocations = ~/.copilot/hooks`.
- `-IncludeClaudeCodeLinks` adds `~/.claude/skills` and `~/.agents/skills`. It
  is off by default because VS Code reads all three user-level skill locations
  and would register every Skill more than once.
- Setup removes historical `~/CopilotAtelier/*` and
  `~/OneDrive/CopilotAtelier/*` entries while preserving unrelated user paths.

## VS Code settings

| Setting | Value | Purpose |
|---|---|---|
| `chat.includeApplyingInstructions` | `true` | Apply Instructions by `applyTo` |
| `chat.includeReferencedInstructions` | `true` | Resolve referenced Instruction content |
| `chat.hookFilesLocations` | `~/.copilot/hooks` | Load the shared lifecycle hooks |
| `github.copilot.chat.agent.thinkingTool` | `true` | Enable reasoning tools |
| `github.copilot.chat.search.semanticTextResults` | `true` | Improve semantic search |
| `github.copilot.chat.skillTool.enabled` | `true` | Allow `context: fork` Skills |
| `github.copilot.chat.agent.maxRequests` | `500` | Support long agent workflows |
| `gitlens.ai.vscode.model` | `copilot:claude-opus-5` | GitLens model |

Setup removes the `github.copilot.advanced.model` key written by earlier
releases. `github.copilot.advanced` is the completions bag and has no documented
`model` member, so the value was never consumed.

Custom agents declare `model` as a priority array. The last entry must be a GA
model so a retirement degrades instead of breaking every agent.

## Execution constraints

- Run ordinary one-shot commands synchronously.
- Run Pester and build entry points through the detached cross-platform
  launcher under `Skills/long-running-job-monitor/scripts/`.
- Never block the foreground with `Start-Sleep` or a polling loop.
- Write transient test and build logs under `$env:TEMP`.
- Never push or mutate remotes without an explicit current-turn request.

## Validation

- `tests/Setup-CopilotSettings.Tests.ps1` covers sandboxed setup behavior and
  legacy location cleanup.
- `tests/SoftwareEngineerAgent.Tests.ps1` enforces the Custom agent prompt
  budget and quality invariants.
- `tests/LifecycleInstructions.Tests.ps1` enforces one-read Pre-flight behavior.
- `tests/MemoryBank.Tests.ps1` verifies exact canonical creation, LF/no-BOM
  output, byte preservation, idempotency, and complete/partial `-WhatIf` paths.
- `tests/MemoryBankRouting.Tests.ps1` enforces provenance-labeled routing,
  zero critical-file misses, Full-read fallback, and at least 50 percent
  average context reduction.
- `tests/MemoryBankHealth.Tests.ps1` validates canonical structure,
  provenance, freshness warnings, retention, optional Memory Bank topics, and
  compactness budgets.
- `tests/SharedLifecycle.Tests.ps1` fingerprints all Custom agent tools,
  handoffs, and role-specific Memory Bank headings while enforcing shared
  bootstrap, completion behavior, and least-privilege native-memory guidance.
- `tests/Hooks.Tests.ps1` runs both hook scripts through a child process the way
  VS Code invokes them and pins the hook configuration contract.
- `tests/SkillFrontmatter.Tests.ps1` enforces the Agent Skills specification:
  name matches folder, description within 1024 characters, `compatibility`
  present on environment-bound Skills, valid `context`, and a non-growing
  over-budget body baseline.
- PowerShell changes require AST parsing, focused Pester, and PSScriptAnalyzer
  where available.
- Markdown Customizations require frontmatter checks and clean editor or
  markdownlint diagnostics.

## Sources of truth

Do not duplicate changing inventories here. Use:

- `Agents/` for Custom agents and tool declarations.
- `Instructions/` for auto-applied rules and `applyTo` patterns.
- `Skills/` for available Skills and their trigger descriptions.
- `Prompts/` for Prompt bindings.
- `Hooks/` for lifecycle events, hook commands, and the enforcement scripts.
- `plugin.json` for the agent plugin manifest.
- `README.md` for the user-facing catalog.
- `CHANGELOG.md` and git history for historical detail.

## Development setup

1. Clone the repository.
2. Run `Setup-CopilotSettings.ps1`.
3. Restart VS Code or reselect the Custom agent.
4. Verify Customization discovery in Copilot Chat diagnostics.
