---
status: current
last-verified: 2026-07-28
owner: software-engineer
source: current task evidence
---

# Active context

## Current focus

Repair the shipped hook commands: VS Code spawns them without a shell, so both
hooks failed to start on Windows and the never-push guard failed open.

## Implemented

- A `Hooks/` Customization deployed to `~/.copilot/hooks`. `PreToolUse` blocks
  remote-mutating and irreversible commands with exit code 2 and a documented
  `COPILOT_ATELIER_ALLOW_REMOTE=1` override; `SessionStart` probes for
  `.memory-bank/index.md` and injects an authoritative present or absent
  statement plus the UTC timestamp.
- Root `plugin.json` so the Agents and Skills install from a Git URL in VS Code,
  the Copilot CLI, and Claude Code. Instructions and hooks stay with the Setup
  script because the plugin format does not carry them.
- Every Custom agent declares `model` as a priority array with a GA fallback.
  Seven heavyweight or domain-specific agents set `disable-model-invocation`,
  and the three that never delegate declare `agents: []`.
- Twenty-five Skills declare `compatibility`. The two Skills that ingest large
  volumes of untrusted external content declare `context: fork`.
- Setup deploys `Hooks/`, writes `chat.hookFilesLocations` and
  `github.copilot.chat.skillTool.enabled`, bumps GitLens to Opus 5, removes the
  inert `github.copilot.advanced.model` key, and gained an opt-in
  `-IncludeClaudeCodeLinks` switch.
- `agent-evals` now routes to the native Chat Customizations Evaluations
  analyzer and the Waza runner before its own fallback harness.

## Focused evidence

- Full suite: 266 passed, 0 failed, 11 skipped.
- `tests/Hooks.Tests.ps1` runs both scripts through a child process exactly as
  VS Code invokes them, and executes the shipped command string through the real
  platform shell so the quoting, `-File`, and stdin contract are proven rather
  than assumed.
- `tests/SkillFrontmatter.Tests.ps1` pins the Agent Skills specification and a
  non-growing baseline of ten Skills whose bodies exceed 500 lines.
- An independent security review found one Blocker and six Major issues. All
  were fixed: the reparse-point recursive delete that could destroy the synced
  customization tree; the fail-open tool-name gate, replaced by tool-agnostic
  command-carrier extraction that also reaches nested task definitions; the
  unanchored git patterns that blocked ordinary commit messages and branch
  names; missing `gh api`, `gh repo create`, `gh workflow run`, and `gh secret`
  coverage; the destructive `-WhatIf` path; and the Claude Code links, now
  create-only so they cannot adopt or repoint another tool's state.
- Three real defects surfaced and were fixed: the reparse-point delete above,
  a 1460-character description on `authenticated-web-extraction` against the
  1024 cap, and the extended `agent-evals` description at 1106.
- AST parse clean on all changed PowerShell; zero PSScriptAnalyzer findings
  outside the Setup script's established `Write-Host` console style.
- Decisions 16 and 17 record the hook enforcement model and the MCP scope
  boundary.

## Next step

Run `Setup-CopilotSettings.ps1` to deploy `Hooks/`, then restart VS Code and
confirm `Load Hooks` lists `~/.copilot/hooks` in the agent debug logs.
