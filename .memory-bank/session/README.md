# Session ephemera

Session-scoped working artifacts produced by per-session prompts. Not curated project knowledge.

## Contents

| File pattern | Producer | Purpose | Lifecycle |
|---|---|---|---|
| `handoff-YYYY-MM-DDTHHmmZ.md` | [`Prompts/session-handoff.prompt.md`](../../Prompts/session-handoff.prompt.md) | Cross-session continuation document so a fresh agent in a new session can resume without re-investigating context | One per session; prune when no longer useful |
| `deadline-handoff-<yyyy-MM-dd-HH-mm>.md` | [`Prompts/sync-project-emails.prompt.md`](../../Prompts/sync-project-emails.prompt.md) | Phase 7a deadline payload handed to `deadline-action-handoff` in a fresh chat | One per sync run |

## Version control

Repo-root [`.gitignore`](../../.gitignore) excludes `handoff-*.md` and `deadline-handoff-*.md` in this folder. The `README.md` is tracked. Per-session artifacts stay out of project history; `progress.md` and `CHANGELOG.md` remain the canonical record.

## Why not the rest of `.memory-bank/`?

- `projectbrief.md`, `activeContext.md`, `progress.md`, `techContext.md`, `systemPatterns.md`, `productContext.md` — curated, version-controlled project knowledge. Always-loaded by every agent at pre-flight.
- `session/` — ephemera produced and consumed in a single user-machine context. Not loaded automatically; the user explicitly attaches a handoff file when starting the next session.

## Consuming a handoff in the next session

1. Locate the most recent `handoff-*.md` in this folder.
2. In the new chat, attach that file or paste its content.
3. Tell the agent: *"Continue from the attached handoff. Read it before pre-flight."*
4. The receiving agent runs the standard PRE-FLIGHT (`.memory-bank/` probe, instruction match, skill match), then resumes from the handoff's Mission section.

## When to invoke `/session-handoff`

- **Closing**: the current session is wrapping (end of day, model swap, machine handover, context approaching saturation).
- **Forward**: while working, you spot an out-of-scope sub-task. Emitting a forward handoff also sharpens the current session — declaring the sub-task out of scope frees the present session to finish its real mission.
- **Return**: a child session (often a prototype or focused debug run) needs to report compressed learnings back to the parent grilling/planning session that spawned it.