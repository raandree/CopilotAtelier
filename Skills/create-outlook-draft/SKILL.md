---
name: create-outlook-draft
description: >-
  Create Outlook email drafts from Markdown email files via COM automation in
  PowerShell. Parses metadata tables (To, CC, Subject) from Markdown, converts
  Markdown body to styled HTML (tables, bold, lists), and saves drafts to the
  Outlook Drafts folder. Handles COM lifecycle, locked items, duplicate
  cleanup, and batch processing of multiple email files.
  USE FOR: create draft, Outlook draft, email draft, draft email, batch drafts,
  markdown to email, md to Outlook, create email from markdown, reminder email,
  save draft, Outlook Drafts folder, bulk email drafts, convert markdown email.
  DO NOT USE FOR: sending emails (use send-outlook-email skill), reading email
  (use outlook-email-export skill), calendar invites, Exchange Web Services,
  Microsoft Graph API.
---

# Create Outlook Draft from Markdown

Skill for creating Outlook email drafts from Markdown email files via COM automation.

## When to Use

- Create one or more email drafts in Outlook from Markdown `.md` files
- Convert Markdown-formatted emails (with metadata tables) to properly styled HTML drafts
- Batch-process a folder of reminder/notification emails into Outlook Drafts

## Prerequisites

- **Microsoft Outlook** must be installed and configured
- The Outlook COM API (`Outlook.Application`) must be accessible from PowerShell
- Windows only (COM technology)

## Expected Markdown Email Format

Each `.md` file must contain a metadata table followed by the email body:

```markdown
# Email Title

| Field | Value |
|-------|-------|
| **Folder** | Outbox |
| **Date** | 2026-04-19 |
| **From** | Sender Name <sender@example.com> |
| **To** | Recipient One <r1@example.com>; Recipient Two <r2@example.com> |
| **CC** | CC Person <cc@example.com> |
| **Subject** | Your Email Subject Here |

Dear Team,

Email body in **Markdown** format with tables, lists, etc.

Best regards,
Sender Name
```

## Critical Lessons Learned

### 1. Always Write to a `.ps1` Script File First

The VS Code integrated terminal **swallows output** from complex inline scripts
with here-strings, HTML, and multi-line content. NEVER run complex Outlook COM
scripts inline. Always write the script to a `.ps1` file first, then execute it:

```powershell
# Write script to file, execute, read results, clean up
$scriptContent | Set-Content 'path\script.ps1' -Encoding UTF8NoBOM
& 'path\script.ps1'
Get-Content 'path\results.txt'
Remove-Item 'path\script.ps1', 'path\results.txt' -Force
```

### 2. Use `[regex]::Match()` — Never PowerShell `-match` with `**`

The metadata table contains `**To**`, `**CC**`, `**Subject**`. PowerShell
interprets `**` as a glob pattern when used with `-match`. ALWAYS use the
`[regex]` class:

```powershell
# CORRECT — [regex] class bypasses PowerShell glob interpretation
$rTo   = [regex]::Match($content, '\|\s+\*{2}To\*{2}\s+\|\s+(.+?)\s*\|')
$rCC   = [regex]::Match($content, '\|\s+\*{2}CC\*{2}\s+\|\s+(.+?)\s*\|')
$rSubj = [regex]::Match($content, '\|\s+\*{2}Subject\*{2}\s+\|\s+(.+?)\s*\|')

$toRaw   = if ($rTo.Success)   { $rTo.Groups[1].Value.Trim() } else { '' }
$ccRaw   = if ($rCC.Success)   { $rCC.Groups[1].Value.Trim() } else { '' }
$subject = if ($rSubj.Success) { $rSubj.Groups[1].Value.Trim() } else { $f.BaseName }
```

### 3. Extract Email Addresses from `Name <email>` Format

Recipients in Markdown use `Name <email@domain.com>` format. Extract only the
email addresses for the Outlook COM API:

```powershell
$toEmails = ([regex]::Matches($toRaw, '<([^>]+@[^>]+)>') |
             ForEach-Object { $_.Groups[1].Value }) -join '; '

# Fallback for plain addresses without angle brackets
if (-not $toEmails -and $toRaw -match '@') {
    $toEmails = ($toRaw -split ';' |
                 ForEach-Object { $_.Trim() } |
                 Where-Object { $_ -match '@' }) -join '; '
}
```

### 4. Use `.Save()` NOT `.Send()` for Drafts

```powershell
$mail = $ol.CreateItem(0)
$mail.To      = $toEmails
if ($ccEmails) { $mail.CC = $ccEmails }
$mail.Subject = $subject
$mail.HTMLBody = $html
$mail.Save()    # Saves to Drafts folder — does NOT send
```

### 5. Handle Locked Items with Try/Catch

Outlook locks items open in the editor. Always wrap `.Delete()`:

```powershell
foreach ($item in $toDelete) {
    try {
        $item.Delete()
    } catch {
        # Item is open in Outlook — skip and retry later
    }
}
```

### 6. Subject Line Trailing Pipe Bug

When the regex for Subject extraction does not trim the trailing `|` from the
Markdown table, Outlook saves it as part of the subject. Always use non-greedy
match with explicit pipe boundary:

```powershell
# CORRECT — non-greedy, trims trailing pipe
$rSubj = [regex]::Match($content, '\|\s+\*{2}Subject\*{2}\s+\|\s+(.+?)\s*\|')

# WRONG — greedy match captures the trailing pipe
$rSubj = [regex]::Match($content, '\|\s+\*{2}Subject\*{2}\s+\|\s+(.+)')
```

## Converting Markdown Body to HTML

### Basic Conversion (Plain Text with Bold)

```powershell
# Extract body: everything after the Subject row in the metadata table
$bodyStarted = $false
$bodyLines = @()
foreach ($line in ($content -split "`n")) {
    if ($bodyStarted) { $bodyLines += $line }
    elseif ($line -match '\*{2}Subject\*{2}') { $bodyStarted = $true }
}
$bodyText = ($bodyLines -join "`n").Trim()

# Markdown bold to HTML strong
$htmlBody = [regex]::Replace($bodyText, '\*{2}(.+?)\*{2}', '<strong>$1</strong>')
$htmlBody = $htmlBody -replace "`n`n", '</p><p>'
$htmlBody = $htmlBody -replace "`n", '<br/>'
$htmlBody = "<p>$htmlBody</p>"

$fullHtml = "<html><body style='font-family:Segoe UI,Arial,sans-serif;color:#333;line-height:1.6;max-width:700px;'>$htmlBody</body></html>"
```

### Markdown Tables → Styled HTML Tables

Markdown tables render as raw pipe characters in Outlook. The basic conversion
above CANNOT handle tables. When a markdown email contains a table, build the
full HTML for that specific draft directly in the script:

```html
<table style="border-collapse:collapse;width:100%;margin:12px 0;">
<tr style="background-color:#2E7D32;color:#fff;">
  <th style="border:1px solid #ddd;padding:8px 12px;text-align:left;">Col 1</th>
  <th style="border:1px solid #ddd;padding:8px 12px;text-align:left;">Col 2</th>
</tr>
<tr>
  <td style="border:1px solid #ddd;padding:8px 12px;">Value 1</td>
  <td style="border:1px solid #ddd;padding:8px 12px;">Value 2</td>
</tr>
<tr style="background-color:#f9f9f9;">
  <td style="border:1px solid #ddd;padding:8px 12px;">Value 3</td>
  <td style="border:1px solid #ddd;padding:8px 12px;">Value 4</td>
</tr>
</table>
```

**Style conventions:**
- Header row: `background-color:#2E7D32` (green), `color:#fff` (white text)
- Alternating data rows: every other `<tr>` gets `background-color:#f9f9f9`
- All cells: `border:1px solid #ddd; padding:8px 12px`
- Use `<th>` for header cells, `<td>` for data cells

## Deleting Existing Drafts Before Recreation

To avoid duplicates when re-running, delete existing drafts by subject pattern:

```powershell
$ns = $ol.GetNamespace('MAPI')
$drafts = $ns.GetDefaultFolder(16)  # olFolderDrafts = 16

# Collect first, then delete — deleting during enumeration skips items
$toDelete = @()
foreach ($item in $drafts.Items) {
    if ($item.Subject -match 'REMINDER') {
        $toDelete += $item
    }
}
foreach ($item in $toDelete) {
    try { $item.Delete() } catch { <# item locked — skip #> }
}
```

**Important:** Collect items into an array first, then delete in a separate loop.
Deleting during enumeration changes the collection and skips items.

## Updating an Existing Draft

Find a draft by subject and replace its HTML body:

```powershell
foreach ($item in $drafts.Items) {
    if ($item.Subject -match 'Shipping Instructions') {
        $item.HTMLBody = $newHtml
        $item.Save()
        break
    }
}
```

Use `-match` (regex) for subject matching — it handles both `–` (em-dash) and
`-` (hyphen) without issues, unlike `-eq` exact match.

## Always Release COM Objects

```powershell
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($mail)   | Out-Null
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($drafts) | Out-Null
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($ns)     | Out-Null
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($ol)     | Out-Null
```

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| Subject ends with `\|` | Greedy regex captured trailing pipe | Use non-greedy `(.+?)` with `\s*\|` boundary |
| Terminal shows no output | Complex here-strings swallowed by VS Code terminal | Write to `.ps1` file first, then execute |
| `Outlook cannot delete this item` | Draft is open in Outlook editor | Close the draft in Outlook, retry |
| Duplicate drafts after re-run | Old drafts not cleaned up | Delete by subject pattern before creating |
| `**` parsed as glob in regex | PowerShell interprets `\*\*` as glob | Use `\*{2}` or `[regex]::Match()` |
| HTML table shows as raw pipes | Markdown table not converted | Build HTML table directly in script |
| Empty CC causes error | Blank CC string is fine, `$null` is not | Guard: `if ($ccEmails) { $mail.CC = $ccEmails }` |
| COM object leak | References not released | Always call `ReleaseComObject()` on all COM objects |
