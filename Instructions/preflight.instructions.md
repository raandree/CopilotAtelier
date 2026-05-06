---
applyTo: "**"
description: "Mandatory pre-flight checklist that auto-loads on every chat turn. Forces Memory Bank + instruction + skill discovery before the first tool call."
---

# Pre-Flight Compliance Hook

This file applies to every chat turn (`applyTo: "**"`). It is the de facto pre-prompt hook for this workspace: VS Code Copilot auto-loads it, so the agent sees it before producing any output.

## MANDATORY — execute before the first tool call

Do all of these for every new user prompt. Do not skip any step silently.

1. **Read the Memory Bank.** If `.memory-bank/` exists in the workspace, read the always-loaded set: `projectbrief.md`, `activeContext.md`, `techContext.md`, `progress.md`, `systemPatterns.md`, and `promptHistory.md` if present. If the folder does not exist, note it in the acknowledgment.
2. **Match instruction files.** Scan the `<instructions>` block for every `applyTo` pattern that matches the file(s) you intend to edit, and read each match before editing. If you will not edit files this turn, skip this step but say so.
3. **Match skills.** Scan the `<skills>` block for any skill whose description matches the user's task; read its `SKILL.md` before acting on its domain.
4. **Append to prompt history.** If `.memory-bank/promptHistory.md` exists, append a one-line entry: `YYYY-MM-DD HH:mm UTC | <agent-name or default> | <one-line intent>`. Create the file only when the rest of the Memory Bank is present and the instruction asks for it.
5. **Open the reply with a UTC timestamp** `[YYYY-MM-DD HH:mm UTC]`.
6. **Emit a one-line PRE-FLIGHT acknowledgment** immediately after the timestamp on substantive turns, naming what was read (or "no Memory Bank", "no matching instructions", "no matching skills"). Trivial conversational turns (clarifications, acknowledgments, single-fact answers) may skip the banner.

## Failure mode

Skipping any step without an explicit reason in the acknowledgment is a process violation. If the user calls it out, stop, perform the missed steps, and continue.

## Scope note

This hook is intentionally short. The full process contract lives in each agent definition (`Agents/*.agent.md`) and in the mode instructions. This file only guarantees the *minimum* discovery pass on every turn, including the default (non-agent) chat mode.
