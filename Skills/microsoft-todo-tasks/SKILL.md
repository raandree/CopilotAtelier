---
name: microsoft-todo-tasks
description: >-
  Create, list, and manage Microsoft To Do tasks via the Graph REST API using
  raw OAuth2 device code flow in PowerShell. Bypasses the buggy Microsoft.Graph
  SDK (WAM broker issues, System.Text.Json conflicts, empty context after auth).
  Handles personal Microsoft accounts (live.com identity provider) that cannot
  use tenant-specific auth. Includes clean Edge profile launch to avoid cached
  localhost redirects from MSAL.
  USE FOR: create To Do task, Microsoft To Do, Graph API tasks, device code auth,
  OAuth2 device flow, To Do reminder, task list, create task with reminder,
  To Do API, personal Microsoft account Graph auth, live.com Graph auth,
  bypass WAM, bypass MSAL, raw OAuth2 PowerShell, device code flow PowerShell,
  Graph REST API PowerShell, To Do tasks from script, bulk create To Do tasks.
  DO NOT USE FOR: Outlook COM tasks (use Outlook COM directly), Exchange tasks,
  calendar events (use calendar APIs), sending email (use send-outlook-email skill).
---

# Microsoft To Do Tasks via Graph REST API

Create and manage Microsoft To Do tasks using raw OAuth2 device code flow and
`Invoke-RestMethod` — no Microsoft.Graph SDK required.

## Preferred pattern: persistent token cache (one device login per ~90 days)

Device code flow is painful when repeated. The OAuth2 `offline_access` scope returns a
**refresh token valid ~90 days (sliding)**, which can be stored on disk (DPAPI-encrypted,
current-user only) and used to silently mint fresh access tokens. Every subsequent script
run gets a valid token with **no browser, no code entry**.

Package the cache + refresh logic as a small reusable PowerShell module so no script has
to reimplement it:

- Module: `scripts/GraphTokenCache.psm1` (suggested path — adjust to your project's script folder)
- Cache file: `%LOCALAPPDATA%\GraphTokenCache\token.xml` (DPAPI-encrypted via `ConvertFrom-SecureString`)
- Scope: `Tasks.ReadWrite offline_access`
- Authority: `common`
- Client ID: `14d82eec-204b-4c2f-b7e8-296a70dab67e` (Microsoft Graph CLI public client)

### Usage in scripts

```powershell
Import-Module "$PSScriptRoot\GraphTokenCache.psm1" -Force
$accessToken = Get-GraphToken   # silent on first run if cache is fresh; silent refresh if expired
$headers = @{ Authorization = "Bearer $accessToken"; 'Content-Type' = 'application/json' }
# ... now call Graph as usual
```

`Get-GraphToken` logic:

1. If cache file is missing → run device code flow, persist tokens, return access token.
2. If cache has unexpired access token → return it.
3. Otherwise refresh silently via `grant_type=refresh_token` → persist new tokens → return access token.
4. If refresh fails (token revoked, consent changed, 90+ days idle) → fall back to device code flow.

### Minimal module (drop into any project)

```powershell
# scripts/GraphTokenCache.psm1
$script:TokenFile = Join-Path $env:LOCALAPPDATA 'GraphTokenCache\token.xml'
$script:ClientId  = '14d82eec-204b-4c2f-b7e8-296a70dab67e'
$script:Scope     = 'Tasks.ReadWrite offline_access'

function Unprotect-String { param([string]$E) [System.Net.NetworkCredential]::new('', (ConvertTo-SecureString $E)).Password }
function Protect-String   { param([string]$P) ConvertTo-SecureString $P -AsPlainText -Force | ConvertFrom-SecureString }

function Save-GraphToken {
    param([pscustomobject]$Token)
    New-Item (Split-Path $script:TokenFile) -ItemType Directory -Force | Out-Null
    @{
        refresh_token = Protect-String $Token.refresh_token
        access_token  = Protect-String $Token.access_token
        expires_at    = (Get-Date).AddSeconds([int]$Token.expires_in - 60).ToString('o')
        client_id     = $script:ClientId
        scope         = $script:Scope
    } | Export-Clixml $script:TokenFile
}

function Invoke-GraphDeviceLogin {
    $dc = Invoke-RestMethod -Method POST -Uri "https://login.microsoftonline.com/common/oauth2/v2.0/devicecode" -Body @{client_id=$script:ClientId; scope=$script:Scope}
    Set-Clipboard -Value $dc.user_code
    Write-Host "CODE: $($dc.user_code) (on clipboard)  URL: https://login.microsoftonline.com/common/oauth2/deviceauth"
    Start-Process "https://login.microsoftonline.com/common/oauth2/deviceauth"
    $body = @{client_id=$script:ClientId; grant_type='urn:ietf:params:oauth:grant-type:device_code'; device_code=$dc.device_code}
    for ($i=0; $i -lt 180; $i++) {
        try { $t = Invoke-RestMethod -Method POST -Uri "https://login.microsoftonline.com/common/oauth2/v2.0/token" -Body $body -EA Stop; Save-GraphToken $t; return $t.access_token }
        catch {
            $e = ($_.ErrorDetails.Message | ConvertFrom-Json -EA SilentlyContinue).error
            if ($e -eq 'authorization_pending') { Start-Sleep 5 } else { throw "Device login failed: $e" }
        }
    }
    throw 'Device login timed out'
}

function Get-GraphToken {
    if (Test-Path $script:TokenFile) {
        $d = Import-Clixml $script:TokenFile
        if ([datetime]::Parse($d.expires_at) -gt (Get-Date)) { return (Unprotect-String $d.access_token) }
        try {
            $body = @{client_id=$script:ClientId; grant_type='refresh_token'; refresh_token=(Unprotect-String $d.refresh_token); scope=$script:Scope}
            $t = Invoke-RestMethod -Method POST -Uri "https://login.microsoftonline.com/common/oauth2/v2.0/token" -Body $body -EA Stop
            Save-GraphToken $t
            return $t.access_token
        } catch { Write-Host 'Refresh failed; falling back to device login...' }
    }
    Invoke-GraphDeviceLogin
}

Export-ModuleMember -Function Get-GraphToken, Invoke-GraphDeviceLogin
```

### Security notes

- `ConvertFrom-SecureString` uses Windows DPAPI. The encrypted blob is bound to the **current Windows user profile on the current machine** — it cannot be decrypted by another user or if copied to another machine.
- Do not commit `token.xml` to source control. The default location (`%LOCALAPPDATA%\GraphTokenCache\`) sits outside any repo.
- Revoke access any time at <https://microsoft.com/consent> → "Microsoft Graph Command Line Tools".
- To force re-auth: delete the cache file (`Remove-Item $env:LOCALAPPDATA\GraphTokenCache\token.xml`).

The one-shot device-code recipe below is still valid for first-time setup or as a fallback.
New scripts should default to the persistent pattern.

## When to Use

- Create tasks in the Microsoft To Do app (not classic Outlook Tasks)
- Need reminders that show in To Do on mobile, web, and desktop
- Outlook is configured with a local data file (OST) where COM tasks don't sync to To Do
- The Microsoft.Graph PowerShell SDK fails due to WAM, assembly conflicts, or empty context
- The account is a personal Microsoft account (live.com) that can't use tenant-specific auth

## Why Not the Microsoft.Graph SDK?

The `Microsoft.Graph.Authentication` module (v2.x) has multiple issues on Windows:

1. **WAM broker hidden popups**: `Connect-MgGraph` uses Windows Account Manager (WAM) by
   default. In embedded terminals (VS Code), the auth popup hides behind other windows.
   Setting `$env:AZURE_IDENTITY_DISABLE_WAMBROKER = 'true'` is ignored by the module.

2. **Device code returns empty context**: `Connect-MgGraph -UseDeviceCode` completes without
   error but `Get-MgContext` returns empty `Account`, `Scopes`, and `TenantId`.

3. **Assembly version conflicts**: `System.Text.Json` and `Microsoft.IdentityModel.Abstractions`
   version mismatches cause `Could not load file or assembly` errors in terminals where
   other .NET types were loaded.

4. **Personal account (live.com) tenant issues**: Using `-TenantId` with the actual tenant ID
   produces `AADSTS50020` because the account is a live.com identity provider, not a native
   Azure AD account.

**Solution**: Use raw `Invoke-RestMethod` against the OAuth2 device code endpoint directly.

## Prerequisites

- PowerShell 7+ (or Windows PowerShell 5.1)
- Internet access to `login.microsoftonline.com` and `graph.microsoft.com`
- Microsoft Edge browser installed (for clean-profile auth window)
- A Microsoft account (personal or work/school) with To Do enabled

## Recipe: Complete Device Code Auth + Task Creation

### Step 1: Request Device Code

```powershell
$clientId = '14d82eec-204b-4c2f-b7e8-296a70dab67e'  # Microsoft Graph CLI (public client)
$scope = 'Tasks.ReadWrite offline_access'

$dc = Invoke-RestMethod -Method POST `
    -Uri "https://login.microsoftonline.com/common/oauth2/v2.0/devicecode" `
    -Body @{client_id = $clientId; scope = $scope}

Write-Host "CODE: $($dc.user_code)"
Write-Host "URL:  $($dc.verification_uri)"
Write-Host "Expires in: $($dc.expires_in) seconds"

# Copy code to clipboard for easy pasting
Set-Clipboard -Value $dc.user_code
```

**Key details:**
- `client_id`: Use `14d82eec-204b-4c2f-b7e8-296a70dab67e` (Microsoft Graph CLI) — this is
  a well-known public client ID that supports device code flow for both personal and
  work/school accounts.
- Use `common` authority (not `consumers` or a specific tenant ID) — works for both account types.
- The code expires in ~900 seconds (15 minutes). The user must enter it within this window.

### Step 2: Open Browser with Clean Profile

**Critical**: Open Edge with a completely fresh user profile to avoid cached state from
previous MSAL browser auth attempts (which leave localhost redirect cookies).

```powershell
$cleanProfile = "$env:TEMP\edge_clean_$(Get-Random)"
New-Item $cleanProfile -ItemType Directory -Force | Out-Null

Start-Process 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe' `
    -ArgumentList @(
        "--user-data-dir=`"$cleanProfile`""
        '--no-first-run'
        '--no-default-browser-check'
        'https://login.microsoftonline.com/common/oauth2/deviceauth'
    )
```

**Why clean profile?**
- Previous MSAL `AcquireTokenInteractive` attempts set a `http://localhost` redirect URI
- The browser caches cookies/redirects that cause subsequent visits to `microsoft.com/devicelogin`
  to redirect to `http://localhost/?error=invalid_request&error_description=...response_type...`
- InPrivate mode alone is NOT sufficient — the redirect can still trigger
- A fresh `--user-data-dir` guarantees zero cached state

**Correct URL**: Always use `https://login.microsoftonline.com/common/oauth2/deviceauth`
(NOT `https://microsoft.com/devicelogin` or `https://login.microsoft.com/device` — these
redirect through intermediate URLs that can hit the localhost cache issue).

### Step 3: Poll for Token

```powershell
$tokenBody = @{
    client_id  = $clientId
    grant_type = 'urn:ietf:params:oauth:grant-type:device_code'
    device_code = $dc.device_code
}

$token = $null
for ($i = 0; $i -lt 180; $i++) {
    try {
        $token = Invoke-RestMethod -Method POST `
            -Uri "https://login.microsoftonline.com/common/oauth2/v2.0/token" `
            -Body $tokenBody -ErrorAction Stop
        Write-Host "TOKEN OBTAINED!"
        break
    } catch {
        $err = $_.ErrorDetails.Message | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($err.error -eq 'authorization_pending') {
            [System.Threading.Thread]::Sleep(5000)  # Poll every 5 seconds
        } elseif ($err.error -eq 'expired_token') {
            Write-Host "Code expired — user didn't sign in within 15 minutes"
            break
        } else {
            Write-Host "Error: $($err.error) — $($err.error_description)"
            break
        }
    }
}
```

**Error codes:**
- `authorization_pending` — normal, keep polling
- `expired_token` — the 15-minute window expired
- `authorization_declined` — user clicked "Cancel" in the browser
- `bad_verification_code` — wrong device_code (code reuse or mismatch)

### Step 4: Create Tasks

```powershell
if ($token) {
    $headers = @{
        Authorization  = "Bearer $($token.access_token)"
        'Content-Type' = 'application/json'
    }

    # Get the default task list
    $lists = (Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/me/todo/lists" `
        -Headers $headers).value
    $list = $lists | Where-Object { $_.wellknownListName -eq 'defaultList' }
    if (-not $list) { $list = $lists[0] }
    $listId = $list.id

    # Create a task
    $taskBody = @{
        title = '[Client] Task Title'
        body = @{
            content     = 'Task description with action items'
            contentType = 'text'
        }
        dueDateTime = @{
            dateTime = '2026-05-08T00:00:00'
            timeZone = 'Europe/Berlin'
        }
        reminderDateTime = @{
            dateTime = '2026-05-05T07:00:00'
            timeZone = 'Europe/Berlin'
        }
        isReminderOn = $true
        importance   = 'high'  # 'low', 'normal', or 'high'
    } | ConvertTo-Json -Depth 5

    $result = Invoke-RestMethod -Method POST `
        -Uri "https://graph.microsoft.com/v1.0/me/todo/lists/$listId/tasks" `
        -Headers $headers -Body $taskBody -ContentType 'application/json'

    Write-Host "Created: $($result.title) (ID: $($result.id))"
}
```

### Step 5: List Existing Tasks

```powershell
$tasks = (Invoke-RestMethod `
    -Uri "https://graph.microsoft.com/v1.0/me/todo/lists/$listId/tasks?`$top=50&`$orderby=dueDateTime/dateTime" `
    -Headers $headers).value

$tasks | ForEach-Object {
    Write-Host "$($_.dueDateTime.dateTime.Substring(0,10)) | $($_.importance) | $($_.title)"
}
```

## Complete One-Block Recipe (Copy-Paste Ready)

This does everything in one block — get code, open clean browser, poll, create tasks:

```powershell
# === AUTH ===
$clientId = '14d82eec-204b-4c2f-b7e8-296a70dab67e'
$dc = Invoke-RestMethod -Method POST -Uri "https://login.microsoftonline.com/common/oauth2/v2.0/devicecode" -Body @{client_id=$clientId; scope='Tasks.ReadWrite offline_access'}
Set-Clipboard -Value $dc.user_code
Write-Host "CODE: $($dc.user_code)  (on clipboard)"

$cleanProfile = "$env:TEMP\edge_clean_$(Get-Random)"
New-Item $cleanProfile -ItemType Directory -Force | Out-Null
Start-Process 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe' -ArgumentList "--user-data-dir=`"$cleanProfile`"", '--no-first-run', '--no-default-browser-check', 'https://login.microsoftonline.com/common/oauth2/deviceauth'

$tokenBody = @{client_id=$clientId; grant_type='urn:ietf:params:oauth:grant-type:device_code'; device_code=$dc.device_code}
$token = $null
for ($i = 0; $i -lt 180; $i++) {
    try { $token = Invoke-RestMethod -Method POST -Uri "https://login.microsoftonline.com/common/oauth2/v2.0/token" -Body $tokenBody -EA Stop; Write-Host "TOKEN OK!"; break }
    catch { $e = ($_.ErrorDetails.Message | ConvertFrom-Json -EA SilentlyContinue).error; if ($e -eq 'authorization_pending') { [System.Threading.Thread]::Sleep(5000) } else { Write-Host "ERR: $e"; break } }
}

# === CREATE TASKS ===
if ($token) {
    $h = @{Authorization="Bearer $($token.access_token)";'Content-Type'='application/json'}
    $lists = (Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/me/todo/lists" -Headers $h).value
    $list = $lists | Where-Object { $_.wellknownListName -eq 'defaultList' }; if (!$list) { $list = $lists[0] }
    $lid = $list.id

    # Define tasks as an array of hashtables
    $tasks = @(
        @{t='Task Title';b='Description';d='2026-05-08';r='2026-05-05T07:00:00';i='high'}
        # Add more tasks here...
    )

    $ok = 0
    foreach ($t in $tasks) {
        $body = @{title=$t.t;body=@{content=$t.b;contentType='text'};dueDateTime=@{dateTime="$($t.d)T00:00:00";timeZone='Europe/Berlin'};reminderDateTime=@{dateTime=$t.r;timeZone='Europe/Berlin'};isReminderOn=$true;importance=$t.i} | ConvertTo-Json -Depth 5
        try { Invoke-RestMethod -Method POST -Uri "https://graph.microsoft.com/v1.0/me/todo/lists/$lid/tasks" -Headers $h -Body $body -ContentType 'application/json' | Out-Null; $ok++; Write-Host "OK $ok`: $($t.t)" }
        catch { Write-Host "FAIL: $($t.t) - $($_.ErrorDetails.Message)" }
    }
    Write-Host "=== $ok / $($tasks.Count) TASKS CREATED ==="
}
```

## Pitfalls and Lessons Learned

### Personal Microsoft Account (live.com) Auth
- Your account may show as `user@company.com` but be a **personal Microsoft
  account** (identity provider = `live.com`), not a native Azure AD account.
- Using `-TenantId 'tenant-guid'` produces `AADSTS50020: User account from identity
  provider 'live.com' does not exist in tenant`.
- **Always use `common` authority** — works for both personal and work/school accounts.
- Do NOT use `consumers` — the `Tasks.ReadWrite` scope may not be supported there.

### Outlook COM Tasks vs Microsoft To Do
- Outlook COM `CreateItem(3)` creates classic Exchange tasks in the **Aufgaben** folder.
- If `Store.ExchangeStoreType = 0` and `Store.IsDataFileStore = True`, the account uses a
  local data file — **COM tasks will NOT sync to Microsoft To Do**.
- To get tasks in To Do, you MUST use the Graph API (`/me/todo/lists/{id}/tasks`).
- Classic COM tasks still work for Outlook reminders (popup notifications).

### Cached Localhost Redirects
- MSAL `AcquireTokenInteractive` with `http://localhost` redirect URI creates browser state
  that interferes with `microsoft.com/devicelogin`.
- Symptom: redirected to `http://localhost/?error=invalid_request&error_description=...response_type...`
- Fix: Use `--user-data-dir` with a fresh temp directory for Edge.
- InPrivate/Incognito mode alone is NOT sufficient.

### Microsoft.Graph SDK Issues (v2.36+)
- `Connect-MgGraph -UseDeviceCode` in a fresh process returns empty context (no Account, no Scopes).
- WAM broker (`WamEnabled: True`) cannot be disabled via environment variables.
- `System.Text.Json` version 10.0.0.0 assembly binding conflict in terminals with mixed .NET types.
- **Workaround**: Skip the SDK entirely. Use `Invoke-RestMethod` with raw OAuth2 endpoints.

### Edge Path
- Edge is at `C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe` on most systems.
- Verify with: `(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\msedge.exe').'(default)'`
- The `msedge` command may not be in PATH — always use the full path.

### Token Lifetime
- Access tokens are valid for ~60 minutes.
- For long operations, include `offline_access` in scopes to get a refresh token.
- Refresh with: `Invoke-RestMethod -Method POST -Uri ".../token" -Body @{client_id=$clientId; grant_type='refresh_token'; refresh_token=$token.refresh_token; scope=$scope}`

### Graph API Task Properties
- `importance`: `'low'`, `'normal'`, or `'high'`
- `dueDateTime.timeZone`: Use IANA format like `'Europe/Berlin'`, not `'W. Europe Standard Time'`
- `reminderDateTime`: Must include time component (e.g., `2026-05-05T07:00:00`)
- `isReminderOn`: Must be `$true` for the reminder to fire
- `body.contentType`: `'text'` or `'html'`
- `categories`: Array of strings (may not sync to all To Do clients)
