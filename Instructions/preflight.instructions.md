---
applyTo: "**"
description: "Mandatory pre-flight checklist for Memory Bank discovery or safe initialization plus Instruction and Skill loading before the first tool call."
---

# Pre-Flight Compliance Hook

This file applies to every chat turn (`applyTo: "**"`). It is the de facto pre-prompt hook for this workspace: VS Code Copilot auto-loads it, so the agent sees it before producing any output.

## MANDATORY — execute before the first tool call

Do all of these for every new user prompt. Do not skip any step silently.

1. **Probe for `.memory-bank/` before reading anything.** Run one of: `list_dir` on the workspace root, `file_search` for `.memory-bank/**`, or `Test-Path .memory-bank`. The `<workspace_info>` / workspace-structure listing surfaced at session start frequently omits dotfile folders (`.memory-bank`, `.git`, `.vscode`, `.github`) and is **not authoritative** for hidden folders. Concluding "no Memory Bank" from the workspace summary alone — without an explicit probe — is a recurring failure mode and counts as a process violation. The PRE-FLIGHT acknowledgment (step 8) must name the probe used and its result.
2. **Route Memory Bank reads.** Read `.memory-bank/index.md` as the only unconditional Memory Bank read. When `loading-mode: routed`, apply its routing table to the current task and planned file paths, combine applicable routes, and read only task-relevant files. Do not read `promptHistory.md` during routine Pre-flight; read it only for interaction-history analysis or Memory Bank evals. When the index is missing or invalid, `loading-mode: full`, the task is ambiguous, routes conflict, or a critical fact is missing, fail open to the complete available base and name the fallback in the acknowledgment. The required version-controlled base is `index.md`, `projectbrief.md`, `productContext.md`, `activeContext.md`, `techContext.md`, `progress.md`, and `systemPatterns.md`; include local `promptHistory.md`, optional `glossary.md`, and every existing `decisions/*.md` record. Missing local history or glossary is not a routing failure.
3. **Initialize only for durable work.** If a durable project/configuration write or explicit durable record is requested and `.memory-bank/` or a required version-controlled base file is missing, load `memory-bank`, create only missing files before the first project edit, and never overwrite existing content. The initializer may also create local `promptHistory.md`; an absent local log or optional `glossary.md` does not make a read-only checkout incomplete. Do not initialize for Q&A, clarification, read-only investigation, or transient personal preferences. After initialization, read the index and apply its routes. Create only the active Custom agent's required role files.
4. **Match instruction files.** Scan the `<instructions>` block for every `applyTo` pattern that matches the files you intend to edit. Reuse full Instruction content already supplied in the current context. Read a matching file from disk only when its content is absent or incomplete. Do not re-read the same Instruction during a turn. If you will not edit files, skip this step and say so.
5. **Match skills.** Scan the `<skills>` block for descriptions matching the task. Read each matching `SKILL.md` at most once per turn, and skip the read when its full body is already supplied in the current context.
6. **Do not write prompt history at Pre-flight.** Post-flight owns the `promptHistory.md` append for Substantive turns. Format: `YYYY-MM-DD HH:mm UTC | <agent-name or default> | <one-line intent>`.
7. **Open the reply with a UTC timestamp** `[YYYY-MM-DD HH:mm UTC]`.
8. **Emit a one-line PRE-FLIGHT acknowledgment** immediately after the timestamp on substantive turns. Name the probe result, selected Memory Bank route and files (or full-read fallback), initialized files, matching Instructions, and matching Skills. Trivial conversational turns may skip the banner.

## Compaction recovery

The steps above run per user prompt. Compaction happens mid-turn, so it bypasses them: the conversation is replaced by a summary, and the Memory Bank files read earlier in the session are no longer in context even though the summary says Pre-flight ran. This Instruction is re-sent with every request and therefore survives; the conversation does not.

Treat the turn as compacted when the transcript shows a summary in place of earlier turns, when a checkpoint message names a compaction, or when you cannot recall a file the summary claims you read. Then, before the next edit:

1. **Distrust the summary of pending or completed work.** It was produced by the truncation. Do not resume from it and do not re-do work it claims is outstanding without checking.
2. **Read the newest `.memory-bank/session/compaction-*.md`.** The `PreCompact` hook writes it with the trigger, the transcript path, and the branch, commit, and changed paths at the moment of truncation. Delete it once the work it anchors is closed out.
3. **Re-read `.memory-bank/index.md` and re-apply its routes.** Routed reads are conversation content, not re-injected context.
4. **Re-read from disk any Prompt, Instruction, or Skill that was driving the run**, plus the Custom agent definition when one is active.
5. **Verify the working tree** against the checkpoint's recorded state before continuing.

State in the reply that the turn was compacted and which of these you re-read.

## Failure mode

Skipping any step without an explicit reason in the acknowledgment is a process violation. If the user calls it out, stop, perform the missed steps, and continue.

## Scope note

This hook owns the shared discovery contract. Custom agent definitions own only role-specific execution behavior, and mode instructions may add stricter requirements. The hook applies to every turn, including default chat mode.
