---
name: outlook-email-export
description: >-
  Export and extract emails from Outlook via COM automation in PowerShell.
  Covers searching by sender, recipient, CC, subject, or date range across
  Inbox, Sent Items, Direct, and Deleted Items folders. Exports to Markdown
  files with metadata tables. Handles COM elevation issues, DASL filters,
  recipient enumeration, deduplication, incremental exports, .msg extraction,
  and embedded email processing via CreateItemFromTemplate.
  USE FOR: export emails, extract emails, Outlook export, read emails,
  email to markdown, export Outlook folder, search Outlook emails,
  email extraction, COM automation Outlook, Outlook COM, export mailbox,
  Mueller emails, email archive, export calendar, Outlook calendar,
  .msg extraction, embedded email, CreateItemFromTemplate.
  DO NOT USE FOR: sending emails (use send-outlook-email skill),
  Microsoft Graph API, Exchange Web Services, IMAP/POP access.
---

# Outlook Email Export via COM Automation

Export emails from Microsoft Outlook to Markdown files using PowerShell COM automation.

## When to Use

- Extract emails from a specific Outlook mailbox folder (Inbox, Sent Items, Direct, Deleted Items)
- Filter emails by sender, recipient, CC, subject keyword, or date range
- Export email metadata and body as Markdown files for documentation or analysis
- Incremental export: only export emails newer than a given cutoff date
- Build an email index (CSV/JSON) from exported Markdown files

## Prerequisites

- **Microsoft Outlook** must be installed and running (or startable via COM)
- The target email profile must be configured in Outlook
- Works on **Windows only** (COM is a Windows technology)
- PowerShell 5.1 (Windows PowerShell) is recommended for COM; PowerShell 7+ has limitations (see Elevation section)

## Critical: VS Code Elevation and COM Access

> **This is the #1 issue when running Outlook COM scripts from VS Code.**

When VS Code runs **elevated** (as Administrator) but Outlook runs **non-elevated**
(normal user), COM calls across integrity levels are blocked with error:
`0x80080005 CO_E_SERVER_EXEC_FAILURE`.

### Solution: Use a Scheduled Task

Run the export script via a Windows Scheduled Task, which executes at the
user's normal integrity level:

```powershell
$scriptPath = 'D:\path\to\Export-Script.ps1'
$logFile    = 'D:\path\to\export_log.txt'

# Wrapper script that captures all output
$wrapperPath = Join-Path $env:TEMP '_run_export.ps1'
$wrapperCode = "& '$scriptPath' *>&1 | Out-File -FilePath '$logFile' -Encoding UTF8"
Set-Content -Path $wrapperPath -Value $wrapperCode -Encoding UTF8

# Create and run scheduled task
$taskName = 'OutlookEmailExport'
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

$action   = New-ScheduledTaskAction -Execute 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' `
            -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$wrapperPath`""
$trigger  = New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(2)
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings | Out-Null
Start-ScheduledTask -TaskName $taskName
```

### As a Background Task (Agent Best Practice)

> **MANDATORY: Never poll in a loop waiting for COM exports to finish.**
> This wastes tokens and produces no useful output. Instead:

1. Start the scheduled task
2. Start a **background terminal** (`isBackground: true`) that monitors
3. Inform the user: "Export is running, I'll check the results shortly."
4. Use `get_terminal_output` once or read the log file after completion

```powershell
# Start export as background task
Start-ScheduledTask -TaskName $taskName

# In a BACKGROUND terminal (isBackground: true), monitor:
while ((Get-ScheduledTask -TaskName $taskName).State -eq 'Running') {
    Start-Sleep -Seconds 15
}
Write-Host "Export complete."
Get-Content $logFile
```

Or simply wait a reasonable time and then read the log file.

**Detecting completion without polling:**

```powershell
# Check if the powershell process from the task is still running
$proc = Get-Process powershell -ErrorAction SilentlyContinue
if (-not $proc) {
    # Process finished, read log file
    Get-Content $logFile
}
```

## Connecting to Outlook

### Windows PowerShell 5.1 (Preferred)

```powershell
# Connect to running instance
try {
    $outlook = [Runtime.InteropServices.Marshal]::GetActiveObject('Outlook.Application')
} catch {
    $outlook = New-Object -ComObject Outlook.Application
    Start-Sleep -Seconds 3
}

$namespace = $outlook.GetNamespace('MAPI')
```

### PowerShell 7+ (Limited)

`GetActiveObject` is not available in .NET Core. Use `New-Object -ComObject`
or `[Activator]::CreateInstance([Type]::GetTypeFromProgID('Outlook.Application'))`.
Both require the same integrity level as Outlook (see Elevation section).

## Finding the Target Mailbox Store

```powershell
$targetStore = $null
foreach ($store in $namespace.Stores) {
    if (($store.DisplayName -match 'jan\.schmidt' -or
         $store.DisplayName -match 'Jan\.Schmidt@contoso\.com') -and
        $store.DisplayName -notmatch 'Online Archive') {
        $targetStore = $store
    }
}

# Access standard folders from the store
$inbox     = $targetStore.GetDefaultFolder(6)   # olFolderInbox
$sentItems = $targetStore.GetDefaultFolder(5)   # olFolderSentMail
$deleted   = $targetStore.GetDefaultFolder(3)   # olFolderDeletedItems

# Custom/named folders under root
$rootFolder = $targetStore.GetRootFolder()
foreach ($folder in $rootFolder.Folders) {
    if ($folder.Name -eq 'Direct') { $directFolder = $folder }
}
```

### Outlook Folder Constants

| Constant | Value | Folder |
|----------|-------|--------|
| `olFolderDeletedItems` | 3 | Deleted Items |
| `olFolderSentMail` | 5 | Sent Items |
| `olFolderInbox` | 6 | Inbox |
| `olFolderCalendar` | 9 | Calendar |
| `olFolderDrafts` | 16 | Drafts |
| `olFolderJunk` | 23 | Junk Email |

### Store Discovery: Always List Stores First

> **IMPORTANT**: User-provided mailbox addresses may not match the actual store
> `DisplayName` in Outlook. Always list all stores first to find the correct match.

```powershell
foreach ($store in $namespace.Stores) {
    Write-Output "Found store: $($store.DisplayName)"
}
```

Common mismatches:
- User says `geword@company.com` but store is `geworg@company.com`
- User says `company` but store has full email `user@company.com`
- Online Archive stores have separate entries — filter with `-notmatch 'Online Archive'`

Use flexible matching with `-match` on partial patterns rather than exact string comparison.

## Searching Emails

### Method 1: DASL Restrict Filter (Fast, Server-Side)

Best for searching by sender email address, subject keyword, or specific fields:

```powershell
# Search by sender email
$filter = "@SQL=""urn:schemas:httpmail:fromemail"" ci_phrasematch 'alex.mueller'"
$results = $folder.Items.Restrict($filter)

# Search by subject keyword
$filter = "@SQL=""urn:schemas:httpmail:subject"" ci_phrasematch 'PRL0158330'"
$results = $folder.Items.Restrict($filter)

# Search by To field
$filter = "@SQL=""urn:schemas:httpmail:to"" ci_phrasematch 'maria.weber'"
$results = $folder.Items.Restrict($filter)

# Search by CC field
$filter = "@SQL=""urn:schemas:httpmail:cc"" ci_phrasematch 'maria.weber'"
$results = $folder.Items.Restrict($filter)
```

### Method 2: Date Restrict Filter (Fast Pre-Filter)

Best for incremental exports — pre-filter by date, then check criteria in PowerShell:

```powershell
$cutoffDate = [datetime]::new(2026, 3, 1)
$dateFilter = $cutoffDate.ToString("MM/dd/yyyy HH:mm")
$filter = "[ReceivedTime] >= '$dateFilter'"
$recentItems = $folder.Items.Restrict($filter)
# Then iterate $recentItems and check sender/recipient in PowerShell
```

> **Always prefer Restrict over iterating all items.** A 28,000-item folder takes
> ~15 minutes to iterate via COM but Restrict returns in seconds.

### Method 3: Full Iteration (Slow, Last Resort)

Only use when DASL filters can't match the criteria (e.g., matching against
resolved Exchange recipients):

```powershell
$totalItems = $folder.Items.Count
for ($i = $totalItems; $i -ge 1; $i--) {
    $item = $folder.Items.Item($i)
    if ($item.Class -ne 43) { continue }  # 43 = olMail
    # Check criteria...
}
```

## Checking Sender and Recipients

### Testing if a Person Is Involved

```powershell
$searchPatterns = @(
    'Alex Mueller',
    'alex.mueller',
    'amuell',
    'Mueller, Alex'
)

function Test-PersonInvolved {
    param($MailItem, [string[]]$Patterns)

    # Check sender
    foreach ($p in $Patterns) {
        if ($MailItem.SenderName -match [regex]::Escape($p) -or
            $MailItem.SenderEmailAddress -match [regex]::Escape($p)) {
            return $true
        }
    }

    # Check To and CC display strings
    foreach ($p in $Patterns) {
        if ($MailItem.To -match [regex]::Escape($p) -or
            $MailItem.CC -match [regex]::Escape($p)) {
            return $true
        }
    }

    # Check resolved recipients (most reliable)
    try {
        for ($i = 1; $i -le $MailItem.Recipients.Count; $i++) {
            $r = $MailItem.Recipients.Item($i)
            foreach ($p in $Patterns) {
                if ($r.Name -match [regex]::Escape($p) -or
                    $r.Address -match [regex]::Escape($p)) {
                    return $true
                }
            }
            # Try Exchange SMTP address
            try {
                $smtp = $r.AddressEntry.GetExchangeUser().PrimarySmtpAddress
                foreach ($p in $Patterns) {
                    if ($smtp -match [regex]::Escape($p)) { return $true }
                }
            } catch { }
        }
    } catch { }

    return $false
}
```

### Getting Recipient Details

```powershell
function Get-RecipientDetails {
    param($MailItem)

    $toList = @()
    $ccList = @()

    try {
        for ($i = 1; $i -le $MailItem.Recipients.Count; $i++) {
            $r = $MailItem.Recipients.Item($i)
            switch ($r.Type) {
                1 { $toList += $r.Name }   # olTo
                2 { $ccList += $r.Name }   # olCC
                3 { $ccList += "$($r.Name) (BCC)" }
            }
        }
    } catch {
        if ($MailItem.To) { $toList = @($MailItem.To) }
        if ($MailItem.CC) { $ccList = @($MailItem.CC) }
    }

    return @{
        To = ($toList -join '; ')
        CC = ($ccList -join '; ')
    }
}
```

## Exporting to Markdown

### Standard Markdown Format

All exports in this project use this consistent format:

```powershell
$dateStr = $item.ReceivedTime.ToString('yyyy-MM-dd-HH-mm')
$safeSubject = Get-SafeFileName -Name $item.Subject
$fileName = "${dateStr}_${safeSubject}.md"

$recipientInfo = Get-RecipientDetails -MailItem $item

$ccLine = ''
if ($recipientInfo.CC) {
    $ccLine = "`n| **CC** | $($recipientInfo.CC) |"
}

$md = @"
# $($item.Subject)

| Field | Value |
|-------|-------|
| **Folder** | $folderLabel |
| **Date** | $($item.ReceivedTime.ToString('yyyy-MM-dd HH-mm')) |
| **From** | $($item.SenderName) |
| **To** | $($recipientInfo.To) |$ccLine

$($item.Body)
"@

[System.IO.File]::WriteAllText($filePath, $md, [System.Text.Encoding]::UTF8)
```

### Safe Filename Generation

```powershell
function Get-SafeFileName {
    param([string]$Name, [int]$MaxLength = 80)
    $safe = $Name -replace '[\\/:*?"<>|]', '_'
    $safe = $safe -replace '\s+', ' '
    if ($safe.Length -gt $MaxLength) { $safe = $safe.Substring(0, $MaxLength) }
    return $safe.Trim()
}
```

### File Organization

Emails are sorted into subdirectories:

```
Mueller_Emails/
├── from/          # Emails FROM the person (received)
├── to/            # Emails TO the person (sent by mailbox owner)
├── email_index.csv
└── email_index.json
```

### Deduplication by Filename

```powershell
# Build set of existing filenames
$existingFiles = @{}
Get-ChildItem -Path $fromFolder -Filter '*.md' | ForEach-Object { $existingFiles[$_.Name] = $true }
Get-ChildItem -Path $toFolder -Filter '*.md' | ForEach-Object { $existingFiles[$_.Name] = $true }

# Skip if already exported
if ($existingFiles.ContainsKey($fileName)) {
    Write-Host "SKIP (exists): $fileName"
    continue
}

# Handle duplicates within the same run
$counter = 1
while (Test-Path $filePath) {
    $fileName = "${dateStr}_${safeSubject}_${counter}.md"
    $filePath = Join-Path $targetDir $fileName
    $counter++
}
```

## Building an Email Index

After exporting, parse the Markdown files to create a structured index:

```powershell
# Parse all exported emails
$emailFiles = @()
$emailFiles += Get-ChildItem "$BasePath\from\*.md" |
    ForEach-Object { [PSCustomObject]@{ File = $_; Direction = 'received' } }
$emailFiles += Get-ChildItem "$BasePath\to\*.md" |
    ForEach-Object { [PSCustomObject]@{ File = $_; Direction = 'sent' } }

# Extract metadata from each file's Markdown table
foreach ($item in $emailFiles) {
    $content = Get-Content $item.File.FullName -Raw
    # Parse subject from H1: ^# (.+)$
    # Parse metadata from table: \| \*\*Field\*\* \| (.+?) \|
}

# Export as CSV + JSON
$results | Export-Csv -Path 'email_index.csv' -NoTypeInformation -Encoding UTF8
$results | ConvertTo-Json -Depth 5 | Set-Content 'email_index.json' -Encoding UTF8
```

See `scripts/Parse-EmailIndex.ps1` for the full implementation with language
detection, thread grouping, word count, and preview text extraction.

## Extracting Embedded .msg Files

Emails often contain `.msg` attachments (forwarded emails saved as files).
Extract them using Outlook's `CreateItemFromTemplate`:

```powershell
function Convert-MsgToMarkdown {
    param([string]$MsgPath, $Outlook)
    $mdPath = $MsgPath -replace '\.msg$', '.md'
    if (Test-Path $mdPath) { return 'SKIP' }
    try {
        $item = $Outlook.CreateItemFromTemplate($MsgPath)
        if (-not $item) { return 'OPEN_FAIL' }
        
        $subject = if ($item.Subject) { $item.Subject } else { 'no-subject' }
        $from = if ($item.SenderName) { $item.SenderName } else { 'unknown' }
        $to = if ($item.To) { $item.To } else { '' }
        $cc = if ($item.CC) { $item.CC } else { '' }
        $date = if ($item.ReceivedTime -and $item.ReceivedTime.Year -gt 2000) {
            $item.ReceivedTime.ToString('yyyy-MM-dd HH:mm')
        } elseif ($item.SentOn -and $item.SentOn.Year -gt 2000) {
            $item.SentOn.ToString('yyyy-MM-dd HH:mm')
        } else { 'unknown' }
        $body = if ($item.Body) { $item.Body } else { '' }
        
        # Build markdown using StringBuilder (avoid here-strings with pipe chars)
        $sb = New-Object System.Text.StringBuilder
        [void]$sb.AppendLine("# $subject")
        [void]$sb.AppendLine()
        [void]$sb.AppendLine('| Field | Value |')
        [void]$sb.AppendLine('|-------|-------|')
        [void]$sb.AppendLine("| **Source** | Embedded .msg |")
        [void]$sb.AppendLine("| **Date** | $date |")
        [void]$sb.AppendLine("| **From** | $from |")
        [void]$sb.AppendLine("| **To** | $to |")
        if ($cc) { [void]$sb.AppendLine("| **CC** | $cc |") }
        [void]$sb.AppendLine()
        [void]$sb.AppendLine($body)
        
        # Extract nested attachments if present
        if ($item.Attachments.Count -gt 0) {
            $nestedDir = Join-Path ([System.IO.Path]::GetDirectoryName($MsgPath)) `
                ([System.IO.Path]::GetFileNameWithoutExtension($MsgPath) + '_nested')
            [void]$sb.AppendLine(); [void]$sb.AppendLine('## Nested Attachments')
            for ($a = 1; $a -le $item.Attachments.Count; $a++) {
                $att = $item.Attachments.Item($a)
                if (-not (Test-Path $nestedDir)) {
                    New-Item -Path $nestedDir -ItemType Directory -Force | Out-Null
                }
                $attPath = Join-Path $nestedDir (Get-SafeFileName -Name $att.FileName)
                $att.SaveAsFile($attPath)
                [void]$sb.AppendLine("- **$($att.FileName)**")
            }
        }
        
        $item.Close(1) # olDiscard
        [System.IO.File]::WriteAllText($mdPath, $sb.ToString(), [System.Text.Encoding]::UTF8)
        return 'OK'
    } catch {
        return "ERR: $_"
    }
}
```

> **Note**: `CreateItemFromTemplate` requires Outlook COM and therefore
> Windows PowerShell 5.1 (for `GetActiveObject`). The `.msg` file must be
> accessible from the file system (not from a ZIP or memory).

## Complete Export Script Template

```powershell
<#
.SYNOPSIS
    Exports emails involving [Person] from Outlook to Markdown.
#>
param(
    [string]$OutputFolder = 'D:\Git\WorkInternals\input\emails\Person_Emails',
    [datetime]$AfterDate  = [datetime]::new(2026, 1, 1)
)

$ErrorActionPreference = 'Continue'

$fromFolder = Join-Path $OutputFolder 'from'
$toFolder   = Join-Path $OutputFolder 'to'
@($OutputFolder, $fromFolder, $toFolder) | ForEach-Object {
    if (-not (Test-Path $_)) { New-Item -Path $_ -ItemType Directory -Force | Out-Null }
}

# Dedup
$existingFiles = @{}
Get-ChildItem "$fromFolder\*.md" -ErrorAction SilentlyContinue |
    ForEach-Object { $existingFiles[$_.Name] = $true }
Get-ChildItem "$toFolder\*.md" -ErrorAction SilentlyContinue |
    ForEach-Object { $existingFiles[$_.Name] = $true }

# Connect
$outlook   = [Runtime.InteropServices.Marshal]::GetActiveObject('Outlook.Application')
$namespace = $outlook.GetNamespace('MAPI')

# Find store and folder (see patterns above)
# ...

# Use Restrict for fast filtering
$dateFilter = $AfterDate.ToString("MM/dd/yyyy HH:mm")
$filtered = $folder.Items.Restrict("[ReceivedTime] >= '$dateFilter'")

for ($i = 1; $i -le $filtered.Count; $i++) {
    $item = $filtered.Item($i)
    if ($item.Class -ne 43) { continue }

    # Check if person is involved (see Test-PersonInvolved)
    # Determine direction, build Markdown, write file
    # ...
}
```

## Existing Scripts in This Project

| Script | Purpose | Search Method |
|--------|---------|---------------|
| `Export-NewMuellerEmails.ps1` | Incremental Mueller emails (Inbox, Sent, Direct) | Full iteration with date filter |
| `Export-DeletedItemsMueller.ps1` | Mueller emails from Deleted Items | Full iteration |
| `Export-WeberEmailsThisWeek.ps1` | Maria Weber emails (Direct, date-restricted) | Restrict by date, then check |
| `Export-TeamAlertsEmails.ps1` | teamalerts@contoso.com emails | DASL Restrict (From/To/CC) |
| `Export-AcmeCorpEmails.ps1` | AcmeCorp keyword search | DASL Restrict |
| `Export-PRL0158330-Emails.ps1` | PRL0158330 subject search (Direct only) | DASL ci_phrasematch |
| `Export-MSVacationEmails.ps1` | MS Vacation emails from existing index | JSON index filter + optional COM |
| `Export-OutlookCalendar.ps1` | Calendar entries to Markdown | Calendar folder iteration |
| `Parse-EmailIndex.ps1` | Build CSV/JSON index from exported .md files | File system (no COM) |

## Performance Tips

1. **Always use `Restrict` or DASL filters** instead of iterating all items
2. **Pre-filter by date** when you only need recent emails — reduces 28,000 items to dozens
3. **Combine DASL filters** for multiple criteria where possible
4. **Use the Scheduled Task pattern** when running from elevated VS Code
5. **Log to a file** (`*>&1 | Out-File`) — COM scripts may produce output that can't be captured by the parent process
6. **Never iterate Sent Items just to skip** — if the person's emails are in a specific folder (e.g., Direct), skip Inbox/Sent Items entirely

## Known Pitfalls

### Sent-Items Gap: Emails to Third Parties Missing from Person-Based Exports

When exporting emails filtered by a specific person (e.g., "Alex Mueller"),
**Sent Items emails addressed to third parties are systematically missed** even
if the person was originally on CC in the draft or conversation.

**Example:** An email sent by the mailbox owner to `Maria Weber` and
`Stefan Koch` with `Alex Mueller` on CC — but when the final sent
email has no CC (only To recipients), the person-based filter finds no match.

**Root cause:** The `$item.To` and `$item.CC` properties reflect the final
sent state. If the person was removed from CC before sending, or if the email
was a new message to different recipients in the same thread, the filter won't
match.

**Detection:** When an email draft exists in `Results/` but no corresponding
sent email appears in the export, check Sent Items manually with a subject or
date filter:

```powershell
# Search Sent Items by date range and subject keyword (bypasses person filter)
$filter = "[SentOn] >= '02/23/2026' AND [SentOn] <= '02/25/2026'"
$filtered = $sentItems.Items.Restrict($filter)
foreach ($item in $filtered) {
    if ($item.Subject -match 'PRL0158331|Klarstellung') {
        Write-Host "FOUND: $($item.Subject) | To: $($item.To) | CC: $($item.CC)"
    }
}
```

**Prevention:** For complete coverage, consider a secondary export pass that
searches Sent Items by **subject keywords** or **date ranges** rather than
recipient names alone.

### Restrict Date Format Is Locale-Dependent

The `Restrict` filter uses **US date format** (`MM/dd/yyyy`) regardless of system
locale when using the short property syntax (`[SentOn]`). For DASL syntax, use
ISO format. Always test with a known date range first.

### PowerShell 7 Has No GetActiveObject

`[Runtime.InteropServices.Marshal]::GetActiveObject()` is .NET Framework only.
In PowerShell 7+, use `New-Object -ComObject Outlook.Application` or shell out
to Windows PowerShell: `powershell.exe -NoProfile -Command { ... }`.

### Here-Strings with Pipe Characters Corrupt in Terminal

When building PowerShell scripts via the VS Code terminal using here-strings
(`@"..."@` or `@'...'@`), markdown table syntax with `|` characters causes
PowerShell to interpret them as pipe operators, corrupting the script.

**Solution**: Use `StringBuilder` to construct markdown content:
```powershell
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('| Field | Value |')
[void]$sb.AppendLine('|-------|-------|')
[void]$sb.AppendLine("| **From** | $from |")
```
Or write the script to a file using `[System.IO.File]::WriteAllText()` with
a single-quoted here-string that doesn't contain embedded variables or pipes.

### Scheduled Task May Not Produce Log Output

When using the Scheduled Task pattern, the task may run but produce no log
file if:
- The script has parse errors (no output captured)
- `$env:TEMP` resolves differently in the task context
- The task runs under a different user profile

**Diagnostic steps**:
1. Check `Get-ScheduledTaskInfo | Select LastRunResult, LastRunTime`
2. Use absolute paths in the wrapper script (not `$env:TEMP`)
3. If not elevated, skip the Scheduled Task entirely — run via
   `Start-Process powershell.exe -RedirectStandardOutput $logPath` directly
