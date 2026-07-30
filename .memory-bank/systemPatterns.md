---
status: current
last-verified: 2026-07-29
owner: software-engineer
source: .memory-bank/decisions
---

# System patterns

Current architecture and Decision record index. Read linked records only when
the task needs their rationale, consequences, or confirmation evidence.

## Architecture overview

```text
CopilotAtelier repository (Sampler project)
├── Agents, Instructions, Skills, Prompts, Hooks, Keybindings
│   └── copied into the built module by Copy_Customizations_To_Output
├── source/
│   ├── CopilotAtelier.psd1 (ModuleVersion replaced by GitVersion)
│   ├── Public/  Install-, Update-, Get-CopilotAtelierVersion
│   └── Private/ path, link, JSONC, and keybinding helpers
├── build.ps1, build.yaml, .build/, GitVersion.yml
├── .github/workflows/ci.yml
├── Setup-CopilotSettings.ps1 (clone entry point shim)
│   └── one Canonical target: OneDrive when available, user profile otherwise
│       ├── ~/.copilot Discovery links
│       └── .copilotatelier.json Deployment record
├── plugin.json
├── tests and Reference
└── .memory-bank
    ├── index.md
    ├── routed canonical files
    ├── decisions/
    ├── topics/
    └── session/
```

## Decision index

| # | Decision record | Status | Date |
|---|---|---|---|
| 1 | [Use OneDrive when available](decisions/0001-use-onedrive-sync.md) | Accepted | 2026-04-23 |
| 2 | [Parse JSONC-tolerant settings](decisions/0002-parse-jsonc-settings.md) | Accepted | 2026-04-23 |
| 3 | [Preserve unrelated location settings](decisions/0003-preserve-location-settings.md) | Accepted | 2026-04-23 |
| 4 | [Use Agent-to-agent handoffs](decisions/0004-use-agent-handoffs.md) | Accepted | 2026-04-23 |
| 5 | [Scope Instructions with applyTo](decisions/0005-scope-instructions-with-applyto.md) | Accepted | 2026-04-23 |
| 6 | [Require Skill frontmatter](decisions/0006-require-skill-frontmatter.md) | Accepted | 2026-04-23 |
| 7 | [Use Claude Opus 4.8](decisions/0007-use-claude-opus-4-8.md) | Accepted | 2026-07-02 |
| 8 | [Store Session handoffs separately](decisions/0008-store-session-handoffs.md) | Accepted | 2026-05-27 |
| 9 | [Codify the Markdown house style](decisions/0009-codify-markdown-style.md) | Accepted | 2026-07-02 |
| 10 | [Detach long-running PowerShell](decisions/0010-detach-long-running-powershell.md) | Accepted | 2026-07-07 |
| 11 | [Exempt Non-impacting turns](decisions/0011-exempt-non-impacting-turns.md) | Accepted | 2026-07-16 |
| 12 | [Govern the Ubiquitous Language](decisions/0012-govern-ubiquitous-language.md) | Accepted | 2026-07-22 |
| 13 | [Centralize shared lifecycle behavior](decisions/0013-centralize-shared-lifecycle.md) | Accepted | 2026-07-24 |
| 14 | [Prove Memory Bank routing](decisions/0014-prove-memory-bank-routing.md) | Accepted | 2026-07-24 |
| 15 | [Keep native memory role-gated](decisions/0015-keep-native-memory-role-gated.md) | Accepted | 2026-07-24 |
| 16 | [Enforce house rules with hooks](decisions/0016-enforce-house-rules-with-hooks.md) | Accepted | 2026-07-28 |
| 17 | [Keep MCP curation out of scope](decisions/0017-keep-mcp-curation-out-of-scope.md) | Accepted | 2026-07-28 |
| 18 | [Distribute as a Sampler-built PowerShell module](decisions/0018-distribute-as-powershell-module.md) | Accepted | 2026-07-29 |

## Live relationships

- The module carries the Customizations as its payload; `Install-CopilotAtelier`
    deploys them and creates Discovery links. The Setup script is a clone-only
    shim over the same command.
- The Deployment record in the Canonical target is the only place that reports
    which version is actually deployed, independent of how it was installed.
- Hooks enforce the rules that must hold regardless of model reasoning;
    Instructions carry the judgement calls.
- Authored guidance takes its form from the baseline failure it corrects:
    prohibitions and rationalization tables for a discipline an agent skips
    under pressure, a positive recipe for output of the wrong shape, a required
    structural slot for an omitted element, and a predicate-keyed conditional
    for behaviour that depends on context. Applying the prohibition form to a
    shaping failure makes the output worse.
- VS Code spawns a hook command without a shell, so no `%VAR%` or `$VAR` token
    is expanded. Each command resolves its own path inside the interpreter and
    propagates the exit code explicitly; a test that runs a hook string through
    a shell does not exercise the real invocation.
- GUI screenshot workflows branch by source ownership: modifiable applications
    own a self-capturing mode; external executables use a process-scoped driver
    with event-driven readiness, restoration, and content verification.
- Custom agent frontmatter controls current tools, model priority, subagent
    eligibility, and Agent-to-agent handoffs.
- Instruction frontmatter controls current `applyTo` scope.
- Prompt frontmatter controls current Custom agent binding.

Read those source files for changing inventories. This file indexes durable
relationships and Decision records only.
