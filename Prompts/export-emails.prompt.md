---
agent: legal-researcher
description: Export recent emails from Outlook (Inbox, Direct, Sent Items) involving persons-of-interest defined in the Memory Bank, avoiding duplicates.
---

# Export Recent Emails to Repository

Export recent emails from Outlook to this repository, keeping the email archive up to date for the persons-of-interest and target folder declared in the Memory Bank.

## Instructions

Execute every phase in order. Phase 1 is a hard ABORT gate — do not proceed if the required Memory Bank entries are missing. Do NOT poll in a tight loop — start a background terminal to monitor or wait a reasonable time before checking the log.

## Phase 1 — Memory Bank Check (ABORT gate)

Verify that `memory-bank/` contains `projectbrief.md` and that it declares:

- A **persons-of-interest** list (full names, optional role annotations). Expected under a heading like `## Persons of Interest`, `## Participants`, or equivalent.
- A **target folder slug** for the archive under `input/emails/` (e.g. `Project_Emails`). Expected under `## Email Archive` or in the project metadata section.

```powershell
$mbFile = Join-Path $PWD 'memory-bank/projectbrief.md'
if (-not (Test-Path $mbFile)) {
    throw 'ABORT: memory-bank/projectbrief.md is missing. Initialize the Memory Bank before running this prompt.'
}
$mb = Get-Content $mbFile -Raw
if ($mb -notmatch '(?ms)^##\s+(Persons of Interest|Participants)\b') {
    throw 'ABORT: projectbrief.md has no "Persons of Interest" (or "Participants") section.'
}
if ($mb -notmatch '(?ms)^##\s+Email Archive\b' -and $mb -notmatch 'input/emails/\S+') {
    throw 'ABORT: projectbrief.md does not declare a target folder under input/emails/.'
}
```

On failure: report the missing section(s) and **stop**. Do not ask the user for the data — this prompt never accepts PII inline.

## Phase 2 — Extract scope from the Memory Bank

Parse `memory-bank/projectbrief.md` and derive:

| Field | Source |
|---|---|
| `personNames` | bullet list under `## Persons of Interest` (or `## Participants`) — take the full name only, strip role annotations |
| `folderSlug` | value under `## Email Archive` or the path fragment matched from `input/emails/<slug>/` |
| `exportScript` | `scripts/Export-RelevantPersonEmails.ps1` by default, or the path declared in the Memory Bank |

If the persons-of-interest list is empty, ABORT. Never hardcode names in this prompt, in commits, or in scratch files.

## Phase 3 — Ask the User

Ask: **How many weeks back should the scan go?** (e.g., 1, 2, 4, 8)

## Phase 4 — Run the Export

The export script scans the Outlook folders **Inbox**, **Direct**, and **Sent Items** for emails involving the names from Phase 2.

Because VS Code typically runs elevated while Outlook runs at normal integrity level, the script **must be run via a Windows Scheduled Task** to avoid COM elevation errors.

Pass the names and folder slug to the script as parameters — do NOT inline them in the wrapper text:

```powershell
$weeksBack   = <WEEKS_FROM_USER>
$scriptPath  = Join-Path $PWD 'scripts\Export-RelevantPersonEmails.ps1'
$logFile     = Join-Path $PWD 'export_log.txt'
$namesCsv    = ($personNames -join ';')        # from Phase 2
$folderSlug  = $folderSlug                     # from Phase 2

$wrapperPath = Join-Path $env:TEMP '_run_export_relevant.ps1'
$wrapperCode = @"
try {
    `$ErrorActionPreference = 'Continue'
    & '$scriptPath' -WeeksBack $weeksBack -PersonNames '$namesCsv' -FolderSlug '$folderSlug' *>&1 |
        Out-File -FilePath '$logFile' -Encoding UTF8
} catch {
    `$_.Exception.Message | Out-File -FilePath '$logFile' -Append -Encoding UTF8
}
"@
Set-Content -Path $wrapperPath -Value $wrapperCode -Encoding UTF8

$taskName = 'ExportRelevantPersonEmails'
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
$action = New-ScheduledTaskAction -Execute 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$wrapperPath`""
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(2)
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings | Out-Null
Start-ScheduledTask -TaskName $taskName
```

If the export script does not yet accept `-PersonNames` and `-FolderSlug`, report that and stop — do not fall back to a hardcoded list.

## Phase 5 — Monitor and Report

Wait for the scheduled task to finish (`(Get-ScheduledTask -TaskName 'ExportRelevantPersonEmails').State`), then read the log file and report:

- How many new emails were exported
- How many were skipped (already present)
- A summary of the new emails (date, direction, subject)

## Rules

- **No PII in this file.** Names, email addresses, organization details, and folder slugs must come from the Memory Bank at runtime.
- **No duplicates**: the script deduplicates by filename against all existing `.md` files in `input/emails/<folderSlug>/from/` and `to/`.
- **Folders scanned**: Inbox, Direct (subfolder of Inbox or root), Sent Items.
- **Output location**: `input/emails/<folderSlug>/from/` (received) and `to/` (sent), where `<folderSlug>` comes from the Memory Bank.
- **Date format**: filenames use `yyyy-MM-dd-HH-mm_<subject>.md`.
