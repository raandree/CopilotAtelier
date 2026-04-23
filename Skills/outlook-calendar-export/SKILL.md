---
name: outlook-calendar-export
description: >-
  Export Outlook calendar entries to Markdown files via COM automation in PowerShell.
  Covers recurring appointments (IncludeRecurrences), date range filtering,
  Markdown generation with metadata tables, index file creation, and UTF-8
  encoding best practices (BOM avoidance).
  USE FOR: export calendar, Outlook calendar, calendar to markdown, Termine exportieren,
  Kalender export, calendar sync, Outlook COM calendar, appointment export,
  recurring appointments, calendar index.
  DO NOT USE FOR: sending calendar invites (use send-outlook-email skill),
  exporting emails (use outlook-email-export skill),
  Microsoft Graph API, Exchange Web Services.
---

# Outlook Calendar Export via COM Automation

Export calendar appointments from Microsoft Outlook to Markdown files using
PowerShell COM automation.

## When to Use

- Export all calendar appointments within a date range to Markdown files
- Create an index of all appointments grouped by month
- Synchronize calendar data for offline analysis or documentation
- Track meeting history for legal or HR documentation purposes

## Prerequisites

- **Microsoft Outlook** must be installed and running (or startable via COM)
- The target calendar must be the default calendar of the configured Outlook profile
- Works on **Windows only** (COM is a Windows technology)
- Same elevation/integrity-level rules as email export apply (see outlook-email-export skill)

## Critical: UTF-8 Encoding Without BOM

> **This is a known pitfall that causes thousands of false Git diffs.**

Windows PowerShell 5.1 `Out-File -Encoding utf8` writes a **UTF-8 BOM** (byte
order mark, 3 bytes: `EF BB BF`) at the start of each file. PowerShell 7+
`Out-File -Encoding utf8` writes **without BOM**. If the export script runs
under different PS versions between exports, every single file appears modified
in Git even though the content is identical.

### Solution: Always Use Explicit UTF-8 Without BOM

```powershell
# Works identically in PS 5.1 and PS 7+
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($filePath, $content, $utf8NoBom)
```

**Never use** `Out-File -Encoding utf8` or `Set-Content -Encoding UTF8` for
files tracked in Git. These produce inconsistent BOM behavior across PS versions.

### If BOM Damage Already Occurred

If an export already created thousands of BOM-only diffs in Git:

```powershell
# 1. Identify BOM-only changes (no real content diff)
$numstats = git diff --numstat -- input/Calendar/
$bomOnly = foreach ($line in $numstats) {
    if ($line -match '^(\d+)\s+(\d+)\s+(.+)$') {
        if ([int]$Matches[1] -le 1 -and [int]$Matches[2] -le 1) {
            $Matches[3].Trim('"')
        }
    }
}

# 2. Reset BOM-only files to committed state
$bomOnly | ForEach-Object { git checkout -- $_ }
```

## Connecting to the Calendar Folder

```powershell
# Connect to Outlook (same as email export)
try {
    $outlook = [Runtime.InteropServices.Marshal]::GetActiveObject('Outlook.Application')
} catch {
    $outlook = New-Object -ComObject Outlook.Application
    Start-Sleep -Seconds 5
}

$namespace = $outlook.GetNamespace('MAPI')

# olFolderCalendar = 9
$calendarFolder = $namespace.GetDefaultFolder(9)
```

## Filtering Appointments by Date Range

> **Critical order of operations**: `IncludeRecurrences` must be set **before**
> applying a Restrict filter. Otherwise, recurring appointments are not expanded
> into individual occurrences.

```powershell
$items = $calendarFolder.Items
$items.Sort('[Start]')
$items.IncludeRecurrences = $true  # MUST be before Restrict!

$startFilter = $StartDate.ToString('MM/dd/yyyy HH:mm')
$endFilter   = $EndDate.ToString('MM/dd/yyyy HH:mm')
$filter = "[Start] >= '$startFilter' AND [Start] <= '$endFilter'"

$filteredItems = $items.Restrict($filter)
```

### Important Notes on IncludeRecurrences

- When `IncludeRecurrences = $true`, the `Items.Count` property is **unreliable**
  (may return a very large number or -1)
- Must iterate with `GetFirst()` / `GetNext()` instead of index-based access
- Date format in the filter string must use US format (`MM/dd/yyyy`)

## Iterating Appointments

```powershell
# Use GetFirst/GetNext pattern (required when IncludeRecurrences = $true)
$item = $filteredItems.GetFirst()
while ($null -ne $item) {
    # Process appointment...
    $subject  = $item.Subject
    $start    = $item.Start
    $end      = $item.End
    $location = try { $item.Location } catch { '' }
    $body     = try { $item.Body } catch { '' }
    $duration = try { $item.Duration } catch { 0 }

    $item = $filteredItems.GetNext()
}
```

## Appointment Properties Reference

| Property | Type | Description |
|----------|------|-------------|
| `Subject` | string | Appointment title |
| `Start` | DateTime | Start date/time |
| `End` | DateTime | End date/time |
| `Duration` | int | Duration in minutes |
| `Location` | string | Meeting location |
| `Body` | string | Full description text |
| `Organizer` | string | Meeting organizer name |
| `RequiredAttendees` | string | Semicolon-separated list |
| `OptionalAttendees` | string | Semicolon-separated list |
| `IsRecurring` | bool | Whether it is a recurring appointment |
| `AllDayEvent` | bool | Whether it is an all-day event |
| `BusyStatus` | int | 0=Free, 1=Tentative, 2=Busy, 3=OOF, 4=WorkingElsewhere |
| `Sensitivity` | int | 0=Normal, 1=Personal, 2=Private, 3=Confidential |
| `ResponseStatus` | int | 0=None, 1=Organized, 2=Accepted, 3=Tentative, 4=Declined |
| `Categories` | string | Comma-separated category names |
| `Importance` | int | 0=Low, 1=Normal, 2=High |

## Markdown Output Format

```markdown
# Meeting Subject

## Termindetails

| Eigenschaft | Wert |
|---|---|
| **Betreff** | Meeting Subject |
| **Start** | 22.03.2026 10:00 |
| **Ende** | 22.03.2026 11:00 |
| **Dauer** | 60 Minuten |
| **Ort** | Microsoft Teams Meeting |
| **Status** | Gebucht |
| **Wiederkehrend** | Ja |
| **Antwortstatus** | Zugesagt |

## Organisator

John Doe

## Erforderliche Teilnehmer

- Jane Smith
- Bob Wilson

## Beschreibung

Meeting agenda and details...
```

## File Naming Convention

```powershell
$datePrefix  = $start.ToString('yyyy-MM-dd_HH-mm')
$safeSubject = $subject -replace '[\\/:*?"<>|]', '_'
$safeSubject = ($safeSubject -replace '\s+', ' ').Trim()
if ($safeSubject.Length -gt 80) { $safeSubject = $safeSubject.Substring(0, 80) }
$fileName = "${datePrefix}_${safeSubject}.md"
```

Example: `2026-03-22_10-00_Weekly Team Standup.md`

## Index File Generation

After exporting all appointments, create an `_INDEX.md` grouped by month:

```powershell
$sortedAppointments = $appointments | Sort-Object Date
$grouped = $sortedAppointments | Group-Object { $_.Date.ToString('yyyy-MM') }

foreach ($group in $grouped) {
    $yearMonth = [datetime]::ParseExact($group.Name, 'yyyy-MM', $null)
    # Write month header + table with Date, Time, Duration, Subject (linked), Location
}

# Write with UTF-8 no BOM
[System.IO.File]::WriteAllText($indexPath, $indexMd.ToString(),
    [System.Text.UTF8Encoding]::new($false))
```

The index header includes export timestamp, date range, and total appointment count:

```markdown
# Kalender-Index

Exportiert am: 22.03.2026 12:00
Zeitraum: 01.01.2023 bis 30.06.2026
Anzahl Termine: 5627
```

## Running the Export

### From an Elevated VS Code Terminal

Use the **Scheduled Task** pattern from the outlook-email-export skill, since
Outlook COM requires the same integrity level:

```powershell
# Direct execution (if VS Code is NOT elevated):
& scripts/Export-OutlookCalendar.ps1 -OutputFolder "c:\Git\WorkInternals\input\Calendar"

# Via Scheduled Task (if VS Code IS elevated):
# See outlook-email-export skill for the Scheduled Task wrapper
```

### Export Parameters

```powershell
.\Export-OutlookCalendar.ps1 `
    -OutputFolder "c:\Git\WorkInternals\input\Calendar" `
    -StartDate "2023-01-01" `
    -EndDate "2026-06-30"
```

## Existing Script

| Script | Purpose |
|--------|---------|
| `scripts/Export-OutlookCalendar.ps1` | Full calendar export with index generation |

## Performance Characteristics

- ~5,600 appointments export in approximately 3-4 minutes
- The script overwrites all files on each run (full export, not incremental)
- Index file is regenerated completely on each run

## Known Issues and Gotchas

1. **BOM inconsistency** — Fixed by using `[System.IO.File]::WriteAllText()`
   with explicit `[System.Text.UTF8Encoding]::new($false)` (see above)
2. **IncludeRecurrences order** — Must be set before `Sort` and `Restrict`
3. **US date format in filters** — Outlook COM always expects `MM/dd/yyyy` regardless
   of system locale
4. **Full overwrite on each run** — The script does not do incremental updates;
   it overwrites every file. This is intentional for consistency but means Git
   will show modifications if encoding or content changed in Outlook
5. **Umlaut encoding** — When switching between PS 5.1 and PS 7, characters like
   `ä`, `ö`, `ü` may be encoded differently. Using `[System.IO.File]::WriteAllText()`
   normalizes this