---
agent: legal-researcher
description: Sync new project-relevant emails from Outlook into the repo, update index and Memory Bank, and show a deadline overview with optional handoff.
---

# Sync Project Emails & Deadlines

Recurring sync workflow: export new emails from Outlook, index them, update the Memory Bank, show deadlines.

## Instructions

Execute every phase in order. Phase 1 is a hard ABORT gate — do not proceed if the Memory Bank is missing.

## Phase 1 — Memory Bank Check (ABORT gate)

Verify that `memory-bank/` exists and contains at least `projectbrief.md` and `activeContext.md`.

```powershell
$mbPath = Join-Path $PWD 'memory-bank'
if (-not (Test-Path $mbPath) -or -not (Test-Path (Join-Path $mbPath 'projectbrief.md')) -or -not (Test-Path (Join-Path $mbPath 'activeContext.md'))) {
    throw 'ABORT: Memory Bank missing. Initialize the project first (memory-bank/ with projectbrief.md + activeContext.md).'
}
```

On failure: tell the user clearly that the project must be initialized first, then **stop**. No further steps.

## Phase 2 — Derive sync scope from Memory Bank

Read:

- `memory-bank/projectbrief.md` — people involved, core topics
- `memory-bank/activeContext.md` — current deadlines, waiting states, expected emails
- `memory-bank/productContext.md` (if present) — contract details
- `scripts/Export-RelevantPersonEmails.ps1` — current person-of-interest list

Derive:

| Field | Source |
|---|---|
| Relevant people / email addresses | projectbrief (participants) + export script |
| Keywords / topics | activeContext (open items) |
| Time window | activeContext (last sync) + today |
| Target folder | `input/emails/<Topic>_Emails/from|to/` |

If people / keywords / time window cannot be **unambiguously** derived from the Memory Bank, ask the user:

1. Which email addresses / persons to scan?
2. Which subject/body keywords?
3. Time window (weeks back or from date)?
4. Target folder under `input/emails/`?

## Phase 3 — Run the export

Use the existing scheduled-task pattern from [export-emails.prompt.md](export-emails.prompt.md) (to bypass Outlook COM elevation). Default script: `scripts/Export-RelevantPersonEmails.ps1`. For other scopes pick the matching `Export-*.ps1`, or — if none fits — report the missing scan and ask the user whether to create a new export script.

Requirements:

- Scans **Inbox, Direct, Sent Items** (plus any configured folders)
- Deduplicates against existing `.md` files in the target folder
- Filenames: `yyyy-MM-dd-HH-mm_<subject>.md`
- Split into `from/` (received) and `to/` (sent)

After completion, read the log and report: newly exported, skipped, list of new entries (date, direction, subject).

## Phase 4 — Create or update the index

For each target folder `input/emails/<Topic>_Emails/`:

- If `_INDEX.md` is missing: create it with a YAML header (topic, last updated) and a table `| Date | Direction | Subject | From/To | File |`.
- If it exists: insert new entries in chronological order, update the "last updated" date, keep the row count in the header current.
- Link files as relative markdown links with URL-encoded spaces.

## Phase 5 — Update Memory Bank

- `memory-bank/activeContext.md`: new session entry with date, list of new emails with short assessment (legal relevance, deadlines, open actions). Status icons: 🔴 OPEN, 🟡 WAITING, 🟢 DONE.
- `memory-bank/progress.md`: append a new prompt entry (prompt number, task, result, affected files).
- `memory-bank/promptHistory.md` (if present): append prompt + short answer summary.
- Extract new deadlines from the exported emails and record them as deadline lines in activeContext.

## Phase 6 — Deadline overview (tabular)

Produce **two tables** in the chat output:

### Personal deadlines (user must act)

| Due | Days | Task | Source | Status |
|---|---|---|---|---|

### Project deadlines (involving others)

| Due | Days | Topic | Participants | Source | Criticality |
|---|---|---|---|---|---|

Rules:

- `Due` = `DD Month YYYY`. `Days` = difference to today (negative = overdue).
- Mark overdue / ≤ 7 days with ⚠️.
- `Source` = markdown link to the email or MB file with line anchor.
- `Criticality`: high / medium / low — derive from statutory deadlines (KSchG 3 weeks, § 626 BGB 2 weeks, contractual forfeiture clauses, certification deadlines, customer dates).

## Phase 7 — Write handoff payload and hand off in a new chat

**Mandatory**: Always persist the handoff state to disk before offering Phase 7 actions. Phases 1–6 consume most of the context window (Outlook exports, email bodies, MB reads). Phase 7 (Outlook drafts + To Do tasks) must run in a **fresh chat** to avoid context exhaustion mid-handoff.

### 7a — Write the handoff payload (always)

Write `memory-bank/session/deadline-handoff-<yyyy-MM-dd-HH-mm>.md` with this exact structure:

```markdown
---
created: <yyyy-MM-dd HH:mm>
source_prompt: Prompts/sync-project-emails.prompt.md
next_prompt: Prompts/deadline-action-handoff.prompt.md
---

# Deadline Handoff Payload

Resume instructions: open a new chat, attach this file, and run
`Prompts/deadline-action-handoff.prompt.md`. Do not paraphrase or
renumber phases — the resuming agent re-reads the prompt from disk.

## Context

- Memory Bank root: `memory-bank/`
- Email index folder(s): <list of input/emails/<Topic>_Emails/ touched this sync>
- Last sync timestamp: <yyyy-MM-dd HH:mm>

## Personal deadlines (user must act)

<paste table from Phase 6 verbatim>

## Project deadlines (involving others)

<paste table from Phase 6 verbatim>

## Critical items flagged for handoff

- <one bullet per deadline that should produce a draft or task, with source link>
```

Rules:

- Tables are copied **verbatim** from Phase 6 — no summarisation, no row merging.
- Source links in tables stay as relative markdown links so the new chat can follow them.
- File is created even if the user declines handoff — it serves as an audit trail.

### 7b — Tell the user to start a new chat

After writing the payload, emit exactly this message (substitute the real file path):

> **Context budget reached.** Handoff payload written to
> `memory-bank/session/deadline-handoff-<yyyy-MM-dd-HH-mm>.md`.
>
> To execute Phase 7 (Outlook drafts + To Do tasks), **start a new chat** and run:
>
> ```
> Attach memory-bank/session/deadline-handoff-<yyyy-MM-dd-HH-mm>.md
> and invoke Prompts/deadline-action-handoff.prompt.md
> ```
>
> Do **not** continue in this chat — the context window is near its limit and
> mid-handoff compaction drops table cells and source links.

Then **stop**. Do not attempt to invoke `deadline-action-handoff.prompt.md` in the current chat, even if the user asks — instead, re-emit the new-chat instruction.

### 7c — Exception: only continue inline if context is demonstrably clean

Only skip 7b and invoke `deadline-action-handoff.prompt.md` in the current chat when **all** of the following are true:

- Phase 3 exported zero new emails (no large bodies loaded into context).
- Phases 4–5 touched only the index file and `activeContext.md` (no topic-file reads).
- Fewer than 5 deadlines total across both tables.

In every other case, 7b is mandatory.

## Rules

- No COM calls from the agent process — always use a scheduled task for exports.
- No polling loops. Wait once, then check the log.
- Use German date formatting in MB updates and tables when the rest of the MB is German; otherwise `DD Month YYYY` in English.
- No RDG disclaimer needed (internal sync prompt, no legal work product).
- Date every MB change.
