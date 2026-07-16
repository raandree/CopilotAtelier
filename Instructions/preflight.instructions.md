---
applyTo: "**"
description: "Mandatory pre-flight checklist that auto-loads on every chat turn. Forces Memory Bank + instruction + skill discovery before the first tool call."
---

# Pre-Flight Compliance Hook

This file applies to every chat turn (`applyTo: "**"`). It is the de facto pre-prompt hook for this workspace: VS Code Copilot auto-loads it, so the agent sees it before producing any output.

## MANDATORY — execute before the first tool call

Do all of these for every new user prompt. Do not skip any step silently.

1. **Probe for `.memory-bank/` before reading anything.** Run one of: `list_dir` on the workspace root, `file_search` for `.memory-bank/**`, or `Test-Path .memory-bank`. The `<workspace_info>` / workspace-structure listing surfaced at session start frequently omits dotfile folders (`.memory-bank`, `.git`, `.vscode`, `.github`) and is **not authoritative** for hidden folders. Concluding "no Memory Bank" from the workspace summary alone — without an explicit probe — is a recurring failure mode and counts as a process violation. The PRE-FLIGHT acknowledgment (step 7) must name the probe used and its result.
2. **Read the Memory Bank.** If the probe in step 1 shows `.memory-bank/` exists, read the always-loaded set: `projectbrief.md`, `activeContext.md`, `techContext.md`, `progress.md`, `systemPatterns.md`, `glossary.md` if present (Ubiquitous Language — governs canonical terminology repo-wide; see [`ubiquitous-language.instructions.md`](ubiquitous-language.instructions.md)), and `promptHistory.md` if present. If the probe shows it is absent, state that with the probe result in the acknowledgment.
3. **Match instruction files.** Scan the `<instructions>` block for every `applyTo` pattern that matches the file(s) you intend to edit, and read each match before editing. If you will not edit files this turn, skip this step but say so.
4. **Match skills.** Scan the `<skills>` block for any skill whose description matches the user's task; read its `SKILL.md` before acting on its domain.
5. **Do not write prompt history at pre-flight.** The `promptHistory.md` append moved to post-flight and fires only on substantive turns (see [postflight.instructions.md](postflight.instructions.md)); reading it in step 2 is sufficient here. Line format when post-flight writes it: `YYYY-MM-DD HH:mm UTC | <agent-name or default> | <one-line intent>`.
6. **Open the reply with a UTC timestamp** `[YYYY-MM-DD HH:mm UTC]`.
7. **Emit a one-line PRE-FLIGHT acknowledgment** immediately after the timestamp on substantive turns. The acknowledgment must name (a) the probe used and its result for `.memory-bank/` (e.g. `list_dir → .memory-bank/ present`, `file_search → no matches`), (b) what was read (or "no Memory Bank"), (c) which instructions matched (or "no matching instructions"), and (d) which skills matched (or "no matching skills"). Trivial conversational turns (clarifications, acknowledgments, single-fact answers) may skip the banner.

## Failure mode

Skipping any step without an explicit reason in the acknowledgment is a process violation. If the user calls it out, stop, perform the missed steps, and continue.

## Scope note

This hook is intentionally short. The full process contract lives in each agent definition (`Agents/*.agent.md`) and in the mode instructions. This file only guarantees the *minimum* discovery pass on every turn, including the default (non-agent) chat mode.
