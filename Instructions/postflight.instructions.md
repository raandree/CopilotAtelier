---
applyTo: "**"
description: "Mandatory post-flight checklist that auto-loads on every chat turn. Forces verification, Memory Bank update, CHANGELOG entry, and local commit before ending the reply."
---

# Post-Flight Compliance Hook

This file applies to every chat turn (`applyTo: "**"`). It is the closing counterpart to [preflight.instructions.md](preflight.instructions.md): VS Code Copilot auto-loads it, so every agent sees it before producing a final answer.

## MANDATORY — execute before ending the reply

Do all of these before concluding any substantive turn. Do not skip any step silently.

1. **Verify the change.** Run the language-appropriate check (parse, lint, build, tests) and capture the result. For PowerShell: `Invoke-ScriptAnalyzer` or AST parse via `[System.Management.Automation.Language.Parser]::ParseFile()`. For Markdown-only edits: state "no executable verification required" and confirm the file renders. For documentation-only conversational turns: skip but say so.
2. **Update the Memory Bank.** If `.memory-bank/` exists, overwrite `activeContext.md` with the current focus and next steps, append a one-line dated entry to `progress.md` for any shipped change, and append the matching `promptHistory.md` line if not already done in pre-flight.
3. **Update `CHANGELOG.md`** under `[Unreleased]` for any user-visible change. Skip for pure refactors, doc-only edits to memory-bank files, or trivial conversational turns.
4. **Commit locally** on a topic branch (prefer `ai/<slug>` for AI-driven work) with a conventional-commit message (`feat:`, `fix:`, `refactor:`, `docs:`, `chore:`, `test:`) and a `Co-authored-by: AI Assistant <ai@example.com>` trailer. Never push unless the user explicitly asked.
5. **Emit a POST-FLIGHT checklist** at the end of the reply naming what was done (or "n/a" with reason for each unchecked item). Suggested form:

   ```
   POST-FLIGHT
   - [x] Verified: <command + outcome, or "n/a — doc edit">
   - [x] Memory Bank: activeContext / progress / promptHistory updated
   - [x] CHANGELOG: <entry summary, or "n/a">
   - [x] Commit: <branch> @ <short SHA> — "<message>"
   - [ ] Push: deferred (user must request explicitly)
   ```

## Failure mode

Skipping any step without an explicit reason in the checklist is a process violation. If the user calls it out, stop, perform the missed steps, and continue.

## Scope note

This hook is intentionally short. Per-agent specializations (e.g. extra build/test commands, extra memory files) live in each `Agents/*.agent.md`. This file guarantees the *minimum* closure pass on every turn, including the default (non-agent) chat mode.
