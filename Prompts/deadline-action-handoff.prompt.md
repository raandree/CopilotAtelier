---
agent: legal-researcher
description: Create Outlook drafts for critical project deadlines and Microsoft To Do tasks for personal deadlines, based on the tables from sync-project-emails. Send a single summary email containing both tables to the user.
---

# Deadline Action Handoff

Process the two deadline tables produced by [sync-project-emails.prompt.md](sync-project-emails.prompt.md) and create actions in Outlook and Microsoft To Do.

## Instructions

This prompt expects two tables as input (personal deadlines + project deadlines). If none are passed, extract them from `memory-bank/activeContext.md` or request a run of the sync prompt first. Execute every phase in order.

## Execution contract

Print this checklist in chat before starting. Tick each item as completed. Do not report success until every box is ticked.

- [ ] Phase 0 — dedup preflight (Sent Items + existing draft files) completed
- [ ] Phase 1 — per-deadline Outlook drafts created (Drafts folder, not sent)
- [ ] Phase 2 — Microsoft To Do tasks created
- [ ] Phase 3 — status table produced
- [ ] Phase 4 — Memory Bank updated
- [ ] Phase 5 — summary email SENT to self (user's own record; team is notified by the Phase 1 drafts once user reviews and sends them)
- [ ] Final verification — re-read this prompt; confirm all 6 phases executed

## Compaction resilience

If the conversation is compacted mid-run:

1. Do not trust any summary of "pending tasks". It may be incomplete.
2. Re-read this prompt file from disk before any further action.
3. Re-read the handoff payload from `memory-bank/session/*.md` (if any).
4. Resume from the first unticked item in the Execution contract.

## Phase 0 — Dedup preflight (REQUIRED FIRST STEP)

Before creating any drafts or tasks, build the "already-handled" set so the same deadline isn't actioned twice:

1. **Sent Items scan** — enumerate Outlook Sent Items for the last 14 days via COM. Collect subjects matching `^(REMINDER|Reminder|Erinnerung):` and any subject that references a deadline topic from the input tables. Record sender date + full subject.
2. **Draft files scan** — list existing `out/*.md` (or project-configured reminder folder) from the last 14 days. Record filename stems.
3. **To Do scan** — fetch open tasks via Graph (`status ne 'completed'`). Record titles.

For each row in the input tables, mark it as:

- `SKIP-SENT` — a matching Sent Items subject exists within 14 days
- `SKIP-DRAFT` — a matching `out/*.md` already exists (draft already staged)
- `SKIP-TASK` — a matching open To Do task already exists
- `ACTION` — none of the above; proceed in Phase 1 / Phase 2

Print the preflight table in chat:

| Deadline row | Sent? | Draft file? | To Do? | Decision |
|---|---|---|---|---|

Only `ACTION` rows proceed to Phase 1 / Phase 2. `SKIP-*` rows flow through Phase 3 reporting and Phase 5 summary with their skip reason, so the user still sees the full deadline set.

## Phase 1 — Project deadlines → Outlook drafts

Load skill: read `Skills/create-outlook-draft/SKILL.md` **before** any COM call.

For **every project deadline with criticality = high** (or ≤ 7 days):

1. Create a markdown file under `Results/Reminders/YYYY-MM-DD_<short>.md` containing:
   - Metadata table: `| To | CC | Subject |`
     - `To` = participants from the deadline row (email addresses from `memory-bank/projectbrief.md` or ask if ambiguous)
     - `Subject` = `Reminder: <topic> — due <DD Month YYYY>`
   - Body in formal language (match the language used by the recipients; default English):
     - Short opening (1 sentence)
     - Deadline + topic
     - Concrete expected action
     - Optional: link to source
     - Closing
2. Hand the file(s) to the create-outlook-draft skill (batch mode if multiple).
3. Show the user the list of created drafts (do not send — drafts only).

Rules:

- **Never send the per-deadline drafts.** They must remain in the Outlook "Drafts" folder only. The only email that gets sent is the summary in Phase 5.
- No sending. Drafts only, in the Outlook "Drafts" folder.
- Avoid escalation tone unless the deadline is already overdue.
- For deadlines with no clear participants: ask the user, don't guess.

## Phase 2 — Personal deadlines → Microsoft To Do

Load skill: read `Skills/microsoft-todo-tasks/SKILL.md` **before** any Graph call.

Auth: the user must not be forced to re-authenticate on every run. Use a persistent refresh-token cache:

1. Look for a project-local auth module exposing `Get-GraphToken` (typical path: `scripts/GraphTokenCache.psm1`). If present, import and use it — it handles device-code on first run and silent refresh thereafter.
2. If no such module exists in the current project, create `scripts/GraphTokenCache.psm1` using the minimal module shown in the skill's "Preferred pattern: persistent token cache" section (DPAPI-encrypted cache via `ConvertFrom-SecureString`, `offline_access` scope, refresh-token grant, device-code fallback). Add the cache file (default `%LOCALAPPDATA%\GraphTokenCache\token.xml`) to `.gitignore` if it sits inside the repo.
3. Only call the raw device-code flow directly if the user explicitly requests it or the persistent module cannot be created (e.g., read-only project).

For **every personal deadline**:

1. Create a To Do task with:
   - Title: `<task> — <topic>` (short, action-oriented)
   - Due date: from the `Due` column
   - Reminder: 2 days before due (immediate if ≤ 3 days)
   - Body: source (markdown link) + short context from the MB
   - List: default list or `Work` — ask the user once, then remember for the session
2. Use raw OAuth2 device code flow (see skill) — **not** the Microsoft.Graph SDK.
3. Avoid duplicates: before creating, search for a task with the same title + due date.

## Phase 3 — Report

Final table in the chat:

| Type | Target | Deadline | Status |
|---|---|---|---|
| Draft | Recipient | Date | ✅ created / ⚠️ failed |
| To-Do | Title | Date | ✅ created / ⚠️ duplicate / ⚠️ failed |

## Phase 4 — Memory Bank

Append to `memory-bank/progress.md`: list of created drafts (file paths) + created To Do tasks (title + id if available). Use `DD Month YYYY`.

## Phase 5 — Summary email (REQUIRED FINAL STEP — to user SELF only)

Load skill: read `Skills/send-outlook-email/SKILL.md` before any COM call.

**Audience**: the user's own mailbox (self). This email is a personal record and does **not** notify the team. The team is notified separately when the user reviews and sends the Phase 1 drafts from the Outlook Drafts folder. Therefore:

- Do not treat the summary as a substitute for the individual reminders.
- Do not delete the Phase 1 drafts after sending the summary.

Produce one summary email and send it to the user (self). The per-deadline drafts from Phase 1 stay in the Drafts folder untouched.

1. Build a markdown document at `Results/Reminders/YYYY-MM-DD_deadline-summary.md` containing:
   - H1: `Deadline Summary — <DD Month YYYY>`
   - Section `## Project deadlines` — the full project-deadlines table (as received in input / Phase 1).
   - Section `## Personal deadlines` — the full personal-deadlines table (as received in input / Phase 2).
   - Section `## Actions taken` — the Phase 3 status table (drafts created + To Do tasks created).
   - Short footer noting that per-deadline drafts are saved in the Outlook Drafts folder and were **not** sent.
2. Convert the markdown to HTML (preserve tables, headings, bold) and send it via the send-outlook-email skill:
   - `To` = the user's own mailbox (self).
   - `Subject` = `Deadline Summary — <DD Month YYYY>`.
   - Body = the HTML rendering of the markdown above.
3. Confirm in chat: summary sent ✅, and reconfirm that the Phase 1 drafts remain drafts.

## Rules

- If Phase 1 fails: still attempt Phase 2. Report failures separately.
- Only Phase 5 sends email. Phases 1–4 must never call `.Send()` on any draft.
- Never create tasks without a due date.
- Match the recipient's language for draft bodies; English default for To Do titles and the summary email.
- Put all output in tables — no redundant prose.

## Done criteria

The run is done only when all three are true:

- `Results/Reminders/YYYY-MM-DD_deadline-summary.md` exists.
- Outlook Sent Items contains a message with subject `Deadline Summary — <DD Month YYYY>` dated today.
- `memory-bank/activeContext.md` Handoff Queue shows ✅ DONE for this run.

Verify all three before reporting completion.
