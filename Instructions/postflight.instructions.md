---
applyTo: "**"
description: "Mandatory post-flight checklist that auto-loads on every chat turn. Forces verification, Memory Bank update, CHANGELOG entry, and local commit before ending the reply."
---

# Post-Flight Compliance Hook

This file applies to every chat turn (`applyTo: "**"`). It is the closing counterpart to [preflight.instructions.md](preflight.instructions.md): VS Code Copilot auto-loads it, so every agent sees it before producing a final answer.

## Classify the turn first

Decide in hindsight, from what actually happened, whether the turn is **substantive** or **non-impacting**. A turn is **substantive** if any of these fired:

- A project or config file was created or edited.
- A durable decision emerged that a future agent should know.
- The user explicitly asked to record or remember something.
- A bug, error, or root cause was discovered, even if unfixed.
- A git tag was created.

Otherwise the turn is **non-impacting**. Plain commits and merges are self-documenting through git and do not by themselves make a turn substantive. When genuinely ambiguous, treat the turn as substantive.

## Non-impacting turn

Skip verification, `CHANGELOG.md`, `progress.md`, the local commit, and the `promptHistory.md` append. Refresh `activeContext.md` only if the current focus actually changed. Emit exactly one closing line and nothing else:

`POST-FLIGHT: n/a — non-impacting turn (<reason>)`

## Substantive turn — execute before ending the reply

Do all of these before concluding. Do not skip any step silently.

1. **Verify the change.** Run the language-appropriate check (parse, lint, build, tests) and capture the result. For PowerShell: `Invoke-ScriptAnalyzer` or AST parse via `[System.Management.Automation.Language.Parser]::ParseFile()`. For Markdown-only edits: state "no executable verification required" and confirm the file renders. For a decision-only turn that changed no file: state "no executable verification required".
2. **Update the Memory Bank.** If `.memory-bank/` exists: overwrite `activeContext.md` when the focus changed; append a dated line to `progress.md` for a shipped change or recorded event; record a durable pattern in `systemPatterns.md`; append the `promptHistory.md` line, creating the file if absent. This step owns the `promptHistory.md` append — pre-flight no longer writes it.
3. **Update `CHANGELOG.md`** under `[Unreleased]` for any user-visible change. Skip for pure refactors, doc-only edits to memory-bank files, or decision-only turns with no user-visible effect.
4. **Commit locally** on a topic branch (prefer `ai/<slug>` for AI-driven work) with a conventional-commit message (`feat:`, `fix:`, `refactor:`, `docs:`, `chore:`, `test:`) and a `Co-authored-by: AI Assistant <ai@example.com>` trailer. Never push unless the user explicitly asked.
5. **Emit a POST-FLIGHT checklist** at the end of the reply naming what was done (or "n/a" with reason for each unchecked item). Suggested form:

   ```
   POST-FLIGHT
   - [x] Verified: <command + outcome, or "n/a — doc edit">
   - [x] Memory Bank: activeContext / progress / systemPatterns / promptHistory
   - [x] CHANGELOG: <entry summary, or "n/a">
   - [x] Commit: <branch> @ <short SHA> — "<message>"
   - [ ] Push: deferred (user must request explicitly)
   ```

## Failure mode

Skipping any step without an explicit reason in the checklist is a process violation. Misclassifying a substantive turn as non-impacting is also a violation — when unsure, treat the turn as substantive. If the user calls it out, stop, perform the missed steps, and continue.

## Scope note

This hook is intentionally short. Per-agent specializations (e.g. extra build/test commands, extra memory files) live in each `Agents/*.agent.md`. This file guarantees the *minimum* closure pass on every turn, including the default (non-agent) chat mode. The full standing bar it partially enforces — verification by file type, authoring caps, security, and Ubiquitous Language, versus per-task acceptance criteria — is [`Reference/definition-of-done.md`](../Reference/definition-of-done.md).
