# WinRM advanced diagnostics

## Contents

- [HTTP.sys conflicts](#6-httpsys-conflicts-iis)
- [WinRM configuration limits](#7-winrm-configuration-limits)
- [WinRM event logs](#8-winrm-event-logs)
- [Common error codes](#9-common-error-codes)
- [Remote diagnostic script](#10-comprehensive-remote-diagnostic-script)
- [Quick fix recipes](#11-quick-fix-recipes)
- [External references](#references)

These recipes extend the core WinRM workflow with HTTP.sys/IIS conflicts,
resource limits, event logs, error codes, a collection script, and common
repairs.

## 6. HTTP.sys Conflicts (IIS)

WinRM and IIS both use HTTP.sys for HTTP request handling. Conflicts arise when
IIS components are partially installed or misconfigured.

### Diagnosis

```powershell
# Check service states — W3SVC, WAS, IISADMIN, HTTP
'W3SVC', 'IISADMIN', 'HTTP', 'WinRM', 'WAS' | ForEach-Object {
    $svc = Get-Service $_ -ErrorAction SilentlyContinue
    if ($svc) { "$_ : $($svc.Status) ($($svc.StartType))" }
    else { "$_ : NOT INSTALLED" }
}

# Check HTTP.sys URL reservations for WinRM
netsh http show urlacl | Select-String -Pattern 'wsman' -Context 0,3

# Check HTTP.sys service state (active request queues)
netsh http show servicestate
```

### IISADMIN Running Without W3SVC

**Symptom**: IISADMIN service is running but W3SVC (World Wide Web Publishing)
and WAS (Windows Process Activation) are not installed. WinRM fails with HTTP 500.

**Root Cause**: IISADMIN can interfere with HTTP.sys URL namespace registration
when partially installed. The IIS Management Service may be holding HTTP.sys
resources that WinRM needs.

**Fix**:

```powershell
# Option 1: Stop IISADMIN if IIS web hosting is not needed
Stop-Service IISADMIN -Force
Set-Service IISADMIN -StartupType Disabled
Restart-Service WinRM

# Option 2: Install the full IIS stack if IIS is actually needed
Install-WindowsFeature Web-Server -IncludeManagementTools
Restart-Service WinRM

# Option 3: Remove IIS completely if not needed
Remove-WindowsFeature Web-Server, Web-Mgmt-Tools
Restart-Service WinRM
```

---

## 7. WinRM Configuration Limits

### Check Current Configuration

```powershell
# Full WinRM config dump (requires running service)
winrm get winrm/config

# Key limits via WSMan provider
$limits = @(
    'WSMan:\localhost\MaxEnvelopeSizekb'
    'WSMan:\localhost\MaxTimeoutms'
    'WSMan:\localhost\MaxBatchItems'
    'WSMan:\localhost\Shell\MaxMemoryPerShellMB'
    'WSMan:\localhost\Shell\MaxProcessesPerShell'
    'WSMan:\localhost\Shell\MaxShellsPerUser'
    'WSMan:\localhost\Shell\MaxConcurrentUsers'
)
foreach ($p in $limits) {
    $val = Get-Item $p -ErrorAction SilentlyContinue
    "$($val.Name) = $($val.Value)"
}
```

### MaxEnvelopeSize (Large Data Transfers)

**Symptom**: `The WinRM client sent a request to an HTTP server and got a
response saying the request was too large` or truncated results.

```powershell
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateRange(1, [int]::MaxValue)]
    [int]$ProposedEnvelopeSizeKb
)

$limitPath = 'WSMan:\localhost\MaxEnvelopeSizekb'
$currentValue = [int](Get-Item $limitPath).Value
if ($ProposedEnvelopeSizeKb -le $currentValue) {
    throw "Proposed value $ProposedEnvelopeSizeKb must exceed current value $currentValue."
}

Set-Item $limitPath -Value $ProposedEnvelopeSizeKb
Get-Item $limitPath
```

Defaults and supported ranges vary by Windows/WinRM version. Check current
Microsoft documentation before setting a larger value; do not treat 2 GB as a
supported universal maximum.

### MaxMemoryPerShellMB (Out of Memory)

**Symptom**: Remote sessions crash or return incomplete results with large datasets.

```powershell
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateRange(1, [int]::MaxValue)]
    [int]$ProposedMemoryMb
)

$limitPath = 'WSMan:\localhost\Shell\MaxMemoryPerShellMB'
$currentValue = [int](Get-Item $limitPath).Value
if ($ProposedMemoryMb -le $currentValue) {
    throw "Proposed value $ProposedMemoryMb must exceed current value $currentValue."
}

Set-Item $limitPath -Value $ProposedMemoryMb
Get-Item $limitPath
```

Do not assume a universal default or that `0` means unlimited; verify semantics
for the target Windows/WinRM version.

### MaxConcurrentOperationsPerUser

**Symptom**: New sessions fail when many are already open.

```powershell
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateRange(1, [int]::MaxValue)]
    [int]$ProposedQuota
)

$quotaPath = 'WSMan:\localhost\Service\MaxConcurrentOperationsPerUser'
$currentQuota = [int](Get-Item $quotaPath).Value
if ($ProposedQuota -le $currentQuota) {
    throw "Proposed quota $ProposedQuota must be greater than current quota $currentQuota."
}

Set-Item $quotaPath -Value $ProposedQuota
Get-Item $quotaPath
```

First close stale operations and measure actual concurrency. Raise the quota
only when demand exceeds the current value, and validate the proposed value
against documentation for the target Windows/WinRM version. Never apply a
generic hard-coded value that can lower the existing quota.

---

## 8. WinRM Event Logs

### WinRM Operational Log

```powershell
# Recent WinRM events
Get-WinEvent -LogName 'Microsoft-Windows-WinRM/Operational' -MaxEvents 30 |
    Select-Object TimeCreated, Id, LevelDisplayName,
        @{N='Message';E={$_.Message.Split("`n")[0]}}

# Errors only
Get-WinEvent -FilterHashtable @{
    LogName = 'Microsoft-Windows-WinRM/Operational'
    Level   = 2  # Error
} -MaxEvents 10

# Service start/stop events (ID 224 = started, 211 = stopping)
Get-WinEvent -FilterHashtable @{
    LogName = 'Microsoft-Windows-WinRM/Operational'
    Id      = 224, 211
} -MaxEvents 10 | Select-Object TimeCreated, Id, Message
```

### System Event Log (Service Control Manager)

```powershell
# WinRM service lifecycle events
Get-WinEvent -FilterHashtable @{
    LogName      = 'System'
    ProviderName = 'Service Control Manager'
    StartTime    = (Get-Date).AddDays(-1)
} -MaxEvents 50 | Where-Object {
    $_.Message -like '*WinRM*' -or $_.Message -like '*Windows Remote Management*'
} | Select-Object TimeCreated, Id, Message
```

### Enable WinRM Analytic/Debug Logs

For deep debugging when standard logs don't show the cause:

```powershell
# Enable analytic log
wevtutil.exe set-log "Microsoft-Windows-WinRM/Analytic" /q:true /e:true

# Enable debug log
wevtutil.exe set-log "Microsoft-Windows-WinRM/Debug" /q:true /e:true

# Disable after troubleshooting (generates a lot of data)
wevtutil.exe set-log "Microsoft-Windows-WinRM/Analytic" /e:false
wevtutil.exe set-log "Microsoft-Windows-WinRM/Debug" /e:false
```

---

## 9. Common Error Codes

| Signed decimal | Hex | Windows message | Diagnostic direction |
| --- | --- | --- | --- |
| -2144108526 | `0x80338012` | Client cannot connect to the destination | Check service, listener, firewall, and `winrm quickconfig` |
| -2144108176 | `0x80338170` | WinRM client received HTTP status 500 | Inspect WinRM, HTTP.sys, and server event logs |
| -2144108316 | `0x803380E4` | Authentication requires HTTPS or TrustedHosts | Check Kerberos, domain membership, HTTPS, and TrustedHosts |
| -2144108387 | `0x8033809D` | Unknown security error | Inspect authentication configuration and security logs |
| -2144108122 | `0x803381A6` | Maximum concurrent operations exceeded | Close operations or raise the per-user quota |
| -2144108250 | `0x80338126` | WinRM cannot complete the operation | Check name resolution, network access, and firewall scope |
| -2144108093 | `0x803381C3` | RunAs credentials could not be verified | Verify the RunAs username and password |
| -2146893042 | `0x8009030E` | `SEC_E_NO_CREDENTIALS` | Acquire valid credentials or Kerberos tickets |
| -2146893022 | `0x80090322` | `SEC_E_WRONG_PRINCIPAL` | Correct DNS/SPN target-name mismatch |

Verify unfamiliar values on the affected Windows host with
`winrm helpmsg <hex>` or `certutil -error <hex>` before prescribing a fix.

---

## 10. Comprehensive Remote Diagnostic Script

Run this from the Hyper-V host via PowerShell Direct to gather all WinRM state:

```powershell
$cred = (Get-LabVM -ComputerName <VMName>).GetCredential((Get-Lab))
$diagnostics = Invoke-Command -VMName <VMName> -Credential $cred -ScriptBlock {
    $out = [ordered]@{}

    # Service state
    $svc = Get-Service WinRM
    $out['ServiceStatus'] = "$($svc.Status) ($($svc.StartType))"

    if ($svc.Status -eq 'StopPending') {
        $cimSvc = Get-CimInstance Win32_Service -Filter "Name='WinRM'"
        $out['StuckPID'] = $cimSvc.ProcessId
        $shared = Get-CimInstance Win32_Service | Where-Object ProcessId -eq $cimSvc.ProcessId
        $out['SharedServices'] = ($shared.Name -join ', ')
    }

    # Listeners (from registry, works even when WinRM is stopped)
    $listenerPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WSMAN\Listener'
    if (Test-Path $listenerPath) {
        $listeners = Get-ChildItem $listenerPath
        $out['ListenerCount'] = $listeners.Count
        $out['Listeners'] = ($listeners.PSChildName -join ', ')
    } else {
        $out['ListenerCount'] = 0
    }

    # Firewall
    $fwRules = Get-NetFirewallRule -Name 'WINRM-HTTP-In-TCP*' -ErrorAction SilentlyContinue
    $out['FirewallRules'] = ($fwRules | ForEach-Object { "$($_.Name)=$($_.Enabled)" }) -join ', '

    # Port check
    $port5985 = (Get-NetTCPConnection -LocalPort 5985 -State Listen -ErrorAction SilentlyContinue | Measure-Object).Count
    $port5986 = (Get-NetTCPConnection -LocalPort 5986 -State Listen -ErrorAction SilentlyContinue | Measure-Object).Count
    $out['Port5985Listeners'] = $port5985
    $out['Port5986Listeners'] = $port5986

    # Related services (IIS/HTTP.sys)
    foreach ($name in 'HTTP', 'W3SVC', 'IISADMIN', 'WAS') {
        $s = Get-Service $name -ErrorAction SilentlyContinue
        $out["Svc_$name"] = if ($s) { "$($s.Status) ($($s.StartType))" } else { 'NOT INSTALLED' }
    }

    # Recent errors
    $errors = Get-WinEvent -FilterHashtable @{
        LogName = 'Microsoft-Windows-WinRM/Operational'; Level = 2
    } -MaxEvents 5 -ErrorAction SilentlyContinue
    $out['RecentErrors'] = ($errors | ForEach-Object {
        $firstLine = [string](($_.Message -split "`r?`n", 2)[0])
        $summary = $firstLine.Substring(0, [Math]::Min(150, $firstLine.Length))
        "[$($_.TimeCreated)] ID:$($_.Id) $summary"
    }) -join '; '

    [PSCustomObject]$out
}
$diagnostics | Format-List
```

---

## 11. Quick Fix Recipes

### Recipe: WinRM StopPending (HTTP 500)

```powershell
# Via PowerShell Direct from Hyper-V host
$cred = (Get-LabVM -ComputerName <VMName>).GetCredential((Get-Lab))
Invoke-Command -VMName <VMName> -Credential $cred -ScriptBlock {
    $winRmService = Get-CimInstance Win32_Service -Filter "Name='WinRM'"
    $serviceProcessId = [int]$winRmService.ProcessId
    $servicesInProcess = @(
        Get-CimInstance Win32_Service |
            Where-Object ProcessId -eq $serviceProcessId
    )

    if ($winRmService.State -ne 'Stop Pending') {
        throw "WinRM is '$($winRmService.State)', not Stop Pending."
    }
    if ($serviceProcessId -le 0 -or
        $servicesInProcess.Count -ne 1 -or
        $servicesInProcess[0].Name -ne 'WinRM') {
        throw 'Refusing to terminate a process that is absent or hosts services other than WinRM.'
    }

    Stop-Process -Id $serviceProcessId -Force
    (Get-Service WinRM).WaitForStatus('Stopped', [TimeSpan]::FromSeconds(15))
    Start-Service WinRM
    (Get-Service WinRM).WaitForStatus('Running', [TimeSpan]::FromSeconds(15))
    Get-Service WinRM | Select-Object Name, Status, StartType
}
```

### Recipe: Enable PSRemoting from Scratch

```powershell
Invoke-Command -VMName <VMName> -Credential $cred -ScriptBlock {
    Enable-PSRemoting -Force -SkipNetworkProfileCheck
    Set-Service WinRM -StartupType Automatic
    # Verify
    Test-WSMan -ComputerName localhost
}
```

### Recipe: Fix After Windows Update Breaks WinRM

```powershell
Invoke-Command -VMName <VMName> -Credential $cred -ScriptBlock {
    # Re-register WinRM URL ACLs
    winrm quickconfig -Force

    # Restart dependent services
    Restart-Service WinRM -Force

    # Restore built-in scoped firewall and remoting configuration.
    Enable-PSRemoting -Force -SkipNetworkProfileCheck

    Get-NetFirewallRule -Name 'WINRM-HTTP-In-TCP*' |
        Select-Object Name, Enabled, Profile
    Test-WSMan -ComputerName localhost
}
```

### Recipe: Verify Connectivity End-to-End

```powershell
# From the client machine
$target = '<ServerName>'

# Step 1: Network
Test-NetConnection -ComputerName $target -Port 5985

# Step 2: WinRM protocol
Test-WSMan -ComputerName $target

# Step 3: PowerShell remoting
Invoke-Command -ComputerName $target -ScriptBlock { hostname }
```

---

## References

- [Microsoft Docs: WinRM Troubleshooting](https://learn.microsoft.com/en-us/windows/win32/winrm/installation-and-configuration-for-windows-remote-management)
- [Microsoft Docs: Enable-PSRemoting](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/enable-psremoting)
- [Microsoft Docs: about_Remote_Troubleshooting](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_remote_troubleshooting)
- [Microsoft Docs: PowerShell Direct](https://learn.microsoft.com/en-us/virtualization/hyper-v-on-windows/user-guide/powershell-direct)
- [Microsoft Docs: WinRM Security](https://learn.microsoft.com/en-us/windows/win32/winrm/authentication-for-remote-connections)
