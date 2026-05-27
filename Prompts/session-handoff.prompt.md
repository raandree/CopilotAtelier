---
agent: agent
description: Write a compact handoff document so a fresh agent in a new session can continue this work. Saves to .memory-bank/session/; references existing artifacts by path instead of duplicating Memory Bank, plan.md, CHANGELOG, or commits.
---

# Session Handoff

Produce a handoff document so a fresh agent in a new session can continue this work without re-investigating context. Used at the end of a long run, before a model switch, on context saturation, or when passing work to a different agent or machine.

This is the cross-session document handoff. Not to be confused with the in-session agent-to-agent `handoffs:` button defined in agent frontmatter (see `.memory-bank/systemPatterns.md` Decision 4 vs Decision 8).

## When to use

Pick the pattern; it shapes the document's content.

- **Closing handoff** — this session ends; the next session resumes the same mission. Triggers: context approaching saturation, end of work day, model swap, machine handover.
- **Forward handoff** — this session continues; a separate session takes a discovered out-of-scope sub-task (refactor, prototype, side bug). Document is a self-contained spec for the sub-task.
- **Return handoff** — a child session reports compressed learnings back to its parent session. Document captures only what is non-obvious from the artifacts (prototype branch, commits, PR) the child produced.

Triggering pattern goes in section 1 (Header) as `Pattern:`.

## Output file

Path: `.memory-bank/session/handoff-<UTC>.md`
`<UTC>` format: `YYYY-MM-DDTHHmmZ` (ISO-8601 compact, UTC, e.g. `2026-05-27T1015Z`).

Create `.memory-bank/session/` if it does not exist. The pattern `handoff-*.md` under that folder is gitignored; the folder's `README.md` is tracked.

One handoff per invocation. Never overwrite a prior handoff; new timestamp, new file.

## Required document sections

In order. Skip a section only when it has no content; do not pad.

### 1. Header

- Produced (UTC)
- Pattern (`closing` / `forward` / `return`)
- Source agent (current persona, e.g. `software-engineer`)
- Source model (id, e.g. `claude-opus-4.7-xhigh`)
- Branch (`git rev-parse --abbrev-ref HEAD`)
- Worktree (`git rev-parse --show-toplevel`)
- Last commit (short SHA, `git rev-parse --short HEAD`)
- Dirty files (`git status --porcelain`)
- Parent handoff (path to the handoff that spawned this session; `return` pattern only)

### 2. Mission

One paragraph stating what the next session must accomplish. If the user passed arguments to `/session-handoff`, treat them as the focus statement and refine into prose. Otherwise derive from `activeContext.md` plus the most recent user turn.

### 3. State pointers

Paths only. Never inline content from these — link by path or URL.

- `.memory-bank/activeContext.md`
- `.memory-bank/progress.md` (latest dated entry)
- Session plan file (`~/.copilot/session-state/<id>/plan.md` if present)
- `CHANGELOG.md` `[Unreleased]` (line range)
- Open todos from the session todo store (id + status + title)
- In-flight `Results/` artifacts (one per line)
- Branch-scoped spec or design files

### 4. Suggested next agent

One value: an agent `name:` from `Agents/*.agent.md` (kebab-case), `agent` (generic), `ask` (read-only chat), or a different harness/tool when the handoff is cross-tool (e.g. `Claude Code`, `Codex`, `Copilot CLI`, `Cursor`). One sentence saying why.

### 5. Suggested skills

Two lists:

- **Loaded this session** — skills the present session loaded (visible in this session's PRE-FLIGHT banners).
- **Pre-load for next session** — skill `name:` values the receiver should load for the Mission. Pull names verbatim from `Skills/<name>/SKILL.md` frontmatter.

### 6. Open questions

Unresolved decisions, ambiguities, or blockers the next session must address. One per line. Empty if none.

### 7. Redaction note

State that the following were redacted or omitted:

- API keys, refresh tokens, OAuth client secrets
- Passwords, connection strings, SAS URIs
- Personally identifiable information not already public
- Mailbox content from `outlook-email-export` / `outlook-calendar-export` runs
- Browser profile data under `%LOCALAPPDATA%\CareerAuthBrowser\`
- Customer or contract-specific identifiers

## Rules

- Reference by path or URL. Never inline duplicate text from Memory Bank, `plan.md`, `CHANGELOG.md`, commit bodies, or diffs. Duplication produces bloated handoffs that stop being useful as the work grows; pointers stay readable.
- Do not modify canonical Memory Bank files (`projectbrief.md`, `activeContext.md`, `progress.md`, `techContext.md`, `systemPatterns.md`) as part of this prompt. The receiving session's post-flight handles those updates.
- Match the language of the receiving agent's domain (English default; German for `legal-researcher` / `tax-researcher` if the case is German).
- If you cannot determine a section's content without inventing facts, leave it empty and add it to Open questions.

## Arguments

The focus statement is mandatory. A handoff without a clear focus produces a fabricated mission. Resolution order:

1. User arguments to `/session-handoff` — use verbatim as the focus.
2. If no arguments: derive from `activeContext.md` plus the most recent user turn, only when the next focus is unambiguous.
3. If neither yields a clear focus: leave Mission empty and list "Next-session focus undefined" as the first item in Open questions.

Examples:

- `/session-handoff` — no focus; resolve via 2 or 3.
- `/session-handoff continue the lab deploy validation pass` — focus statement.
- `/session-handoff @security-reviewer review the new prompt` — target agent (`@<name>`) + focus.
- `/session-handoff forward: extract Datum merge perf regression to its own session` — pattern hint + focus.

## Done

The run is complete when:

- `.memory-bank/session/handoff-<UTC>.md` exists, all seven sections populated or explicitly empty.
- The chat reply states the file path so the user can attach it in the next session.