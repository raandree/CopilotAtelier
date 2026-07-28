---
status: current
last-verified: 2026-07-25
owner: software-engineer
source: .memory-bank/decisions
---

# System patterns

Current architecture and Decision record index. Read linked records only when
the task needs their rationale, consequences, or confirmation evidence.

## Architecture overview

```text
CopilotAtelier repository
├── Agents, Instructions, Skills, Prompts, Hooks
├── Setup-CopilotSettings.ps1
│   └── one Canonical target: OneDrive when available, user profile otherwise
│       └── ~/.copilot Discovery links
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

## Live relationships

- The Setup script deploys the five Customization directories and creates
    Discovery links.
- Hooks enforce the rules that must hold regardless of model reasoning;
    Instructions carry the judgement calls.
- GUI screenshot workflows branch by source ownership: modifiable applications
    own a self-capturing mode; external executables use a process-scoped driver
    with event-driven readiness, restoration, and content verification.
- Custom agent frontmatter controls current tools, model priority, subagent
    eligibility, and Agent-to-agent handoffs.
- Instruction frontmatter controls current `applyTo` scope.
- Prompt frontmatter controls current Custom agent binding.

Read those source files for changing inventories. This file indexes durable
relationships and Decision records only.
