---
status: accepted
date: 2026-04-23
last-verified: 2026-07-24
owner: software-engineer
source: Setup-CopilotSettings.ps1
supersedes: none
---

# Parse JSONC-tolerant VS Code settings

## Context and problem statement

VS Code settings use JSON with comments, while Windows PowerShell 5.1
`ConvertFrom-Json` accepts standard JSON only.

## Decision outcome

Strip line and block comments before parsing `settings.json`, then serialize
the updated settings as JSON.

## Consequences

- Commented settings parse reliably on PowerShell 5.1.
- Comments in the rewritten settings file are not preserved.
- Settings behavior is tested against sandbox files rather than the live user
  profile.

## Confirmation

Run `tests/Setup-CopilotSettings.Tests.ps1` and parse the resulting settings
with `ConvertFrom-Json`.
