---
name: send-outlook-email
description: >-
  Send emails via the Outlook COM API from PowerShell. Supports plain-text and
  HTML-formatted emails, sending to self or specified recipients, with subject
  and body content. Handles COM object lifecycle (create, send, release).
  USE FOR: send email, email summary, Outlook email, send via Outlook, email
  myself, mail summary, HTML email, send notification, email report.
  DO NOT USE FOR: reading email, calendar invites, Outlook rules, Exchange
  Web Services, Microsoft Graph API email.
---

# Send Outlook Email

Skill for sending emails programmatically via the Outlook COM API using PowerShell.

## When to Use

- Send a summary or report via email to the current user or a specified recipient
- Send HTML-formatted emails with styled content
- Automate email notifications from within VS Code / PowerShell

## Prerequisites

- **Microsoft Outlook** must be installed and configured with at least one email account
- The Outlook COM API (`Outlook.Application`) must be accessible from PowerShell
- Works on Windows only (COM is a Windows technology)

## Sending a Plain-Text Email to Yourself

```powershell
$ol   = New-Object -ComObject Outlook.Application
$mail = $ol.CreateItem(0)
$mail.To      = $ol.Session.CurrentUser.Address
$mail.Subject = "Your Subject Here"
$mail.Body    = "Plain-text body content here."
$mail.Send()

# Clean up COM objects
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($mail) | Out-Null
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($ol)   | Out-Null
```

## Sending a Plain-Text Email to a Specific Recipient

```powershell
$ol   = New-Object -ComObject Outlook.Application
$mail = $ol.CreateItem(0)
$mail.To      = "recipient@example.com"
$mail.Subject = "Your Subject Here"
$mail.Body    = "Plain-text body content here."
$mail.Send()

[System.Runtime.InteropServices.Marshal]::ReleaseComObject($mail) | Out-Null
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($ol)   | Out-Null
```

## Sending an HTML-Formatted Email

Use the `HTMLBody` property instead of `Body` for rich formatting.

```powershell
$html = @'
<html>
<body style="font-family: Segoe UI, Arial, sans-serif; color: #333; line-height: 1.6; max-width: 700px;">

<h2 style="color: #0078D4; border-bottom: 2px solid #0078D4; padding-bottom: 8px;">
  Email Title
</h2>
<p style="color: #666; font-size: 13px;">Date &bull; Context</p>

<h3 style="color: #444;">Section Heading</h3>
<p>Paragraph with <strong>bold</strong> and <code>code</code> formatting.</p>

<!-- Callout box (warning style) -->
<table style="border-collapse: collapse; width: 100%; margin: 8px 0;">
<tr><td style="padding: 8px 12px; background: #FFF3CD; border-left: 4px solid #FFC107; font-size: 14px;">
  Warning or important note here.
</td></tr>
</table>

<!-- Callout box (info style) -->
<table style="border-collapse: collapse; width: 100%; margin: 8px 0;">
<tr><td style="padding: 8px 12px; background: #E8F4FD; border-left: 4px solid #0078D4; font-size: 14px;">
  Informational note here.
</td></tr>
</table>

<h3 style="color: #444;">Bullet List</h3>
<ul>
  <li>First item</li>
  <li>Second item with <code>inline code</code></li>
  <li><strong>Bold item</strong> with details</li>
</ul>

<hr style="border: none; border-top: 1px solid #ddd; margin: 20px 0;"/>
<p style="color: #999; font-size: 12px;">Footer text</p>

</body>
</html>
'@

$ol   = New-Object -ComObject Outlook.Application
$mail = $ol.CreateItem(0)
$mail.To       = $ol.Session.CurrentUser.Address
$mail.Subject  = "HTML Email Subject"
$mail.HTMLBody = $html
$mail.Send()

[System.Runtime.InteropServices.Marshal]::ReleaseComObject($mail) | Out-Null
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($ol)   | Out-Null
```

## Best Practices

### Use a Script File for HTML Emails

When sending HTML emails from the VS Code integrated terminal, here-strings with
HTML can cause buffering and parsing issues. Write the email logic to a `.ps1`
file and execute it instead:

```powershell
# Write script to temp file, run it, clean up
$script = @'
$html = @"
<html><body><h2>Title</h2><p>Content</p></body></html>
"@
$ol = New-Object -ComObject Outlook.Application
$mail = $ol.CreateItem(0)
$mail.To = $ol.Session.CurrentUser.Address
$mail.Subject = "Subject"
$mail.HTMLBody = $html
$mail.Send()
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($mail) | Out-Null
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($ol) | Out-Null
'@

$tempScript = Join-Path $env:TEMP 'Send-Email.ps1'
$script | Set-Content $tempScript -Encoding UTF8
powershell -NoProfile -File $tempScript
Remove-Item $tempScript -Force
```

### Always Release COM Objects

Outlook COM objects hold references to the Outlook process. Always release them
after sending to avoid orphaned `OUTLOOK.EXE` processes:

```powershell
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($mail) | Out-Null
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($ol)   | Out-Null
```

### Adding CC and BCC Recipients

```powershell
$mail.CC  = "cc-recipient@example.com"
$mail.BCC = "bcc-recipient@example.com"
```

### Adding Attachments

```powershell
$mail.Attachments.Add("C:\path\to\file.pdf")
```

### Setting Importance

```powershell
$mail.Importance = 2  # 0 = Low, 1 = Normal, 2 = High
```

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `New-Object : Retrieving the COM class factory failed` | Outlook not installed | Install Microsoft Outlook |
| `Operation aborted` on `.Send()` | Outlook security prompt blocked send | Run from a trusted context or adjust Outlook Trust Center settings |
| Email stuck in Outbox | Outlook not connected / Send/Receive not triggered | Open Outlook and click Send/Receive, or ensure Outlook is online |
| `RPC_E_CALL_REJECTED` | Outlook is busy (dialog open) | Close any open Outlook dialogs and retry |
