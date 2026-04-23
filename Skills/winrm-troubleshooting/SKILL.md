---
name: winrm-troubleshooting
description: >-
  Debug and troubleshoot Windows Remote Management (WinRM) connectivity failures
  on Windows servers, including lab VMs managed by AutomatedLab. Covers service
  state recovery (StopPending, hung, won't start), listener configuration,
  HTTP.sys conflicts with IIS, authentication failures (Kerberos, NTLM, CredSSP),
  HTTPS certificate issues, firewall rules, TrustedHosts, MaxEnvelopeSize,
  double-hop delegation, and PowerShell Direct as a fallback diagnostic channel.
  USE FOR: WinRM error, WinRM not working, WinRM HTTP 500, WinRM quickconfig
  fails, WinRM StopPending, WinRM service stuck, WinRM listener missing, WinRM
  connection refused, WinRM access denied, WinRM timeout, Enter-PSSession fails,
  Invoke-Command fails, PowerShell remoting broken, WSManFault, 0x80338170,
  0x80070005, 0x80090322, WinRM firewall, WinRM HTTPS, WinRM certificate,
  WinRM CredSSP, WinRM TrustedHosts, WinRM MaxEnvelopeSize, WinRM Kerberos,
  WinRM NTLM, WinRM double-hop, PowerShell Direct, PS Direct, VMBus remoting,
  Invoke-LabCommand fails, WinRM 5985, WinRM 5986, HTTP.sys conflict, IIS WinRM
  conflict, IISADMIN WinRM, WinRM plugin error, Test-WSMan fails,
  New-PSSession fails, remoting not enabled, Enable-PSRemoting fails,
  Set-WSManQuickConfig error, WinRM MaxMemoryPerShellMB, WinRM proxy,
  0x803381A6, 0x80338126, 0x803380E4, SEC_E_NO_CREDENTIALS.
  DO NOT USE FOR: SSH remoting (use SSH docs), PowerShell 7 remoting over SSH,
  Azure Automation DSC (use azure-diagnostics), WMI/CIM connectivity issues
  unrelated to WinRM, general networking (use network troubleshooting).
---

# WinRM Troubleshooting

Skill for diagnosing and fixing Windows Remote Management (WinRM) connectivity
failures on Windows servers, including Hyper-V lab VMs managed by AutomatedLab.

## When to Use

- `Enter-PSSession`, `Invoke-Command`, or `Invoke-LabCommand` fails to connect
- `winrm quickconfig` returns an HTTP 500 or other error
- WinRM service is stuck in `StopPending` or won't start
- `Test-WSMan` fails with access denied, timeout, or connection refused
- PowerShell remoting was working and stopped (after updates, GPO changes, or reboots)
- HTTPS listener needs configuration or certificate renewal
- Double-hop / CredSSP delegation issues prevent access to network resources

## Diagnostic Workflow

Follow this sequence when investigating WinRM connectivity failures:

```
1. Verify network reachability (ping, port 5985/5986)
2. Check WinRM service state on the target
3. Check WinRM listeners (HTTP/HTTPS)
4. Check firewall rules
5. Check authentication (Kerberos/NTLM/CredSSP)
6. Check TrustedHosts (workgroup scenarios)
7. Check HTTP.sys conflicts (IIS)
8. Check WinRM configuration limits
9. Review event logs
```

---

## 1. Establish a Diagnostic Channel

When WinRM is broken, you need an alternative way to run commands on the target.

### Hyper-V: PowerShell Direct (VMBus — bypasses WinRM entirely)

PowerShell Direct uses the Hyper-V VMBus, not the network stack. It works even
when WinRM, networking, or firewall is completely broken.

```powershell
# Using AutomatedLab credentials
$cred = (Get-LabVM -ComputerName <VMName>).GetCredential((Get-Lab))
Invoke-Command -VMName <VMName> -Credential $cred -ScriptBlock {
    hostname
}

# Using explicit credentials
$cred = Get-Credential -UserName 'DOMAIN\AdminUser'
Invoke-Command -VMName <VMName> -Credential $cred -ScriptBlock {
    hostname
}
```

> **Requirements**: Must run on the Hyper-V host. VM must be running.
> Works with local or domain credentials that are valid inside the VM.

### Physical/Remote Servers: PsExec or RDP

When PowerShell Direct is not available:

```powershell
# PsExec (Sysinternals) — runs cmd on the remote machine
psexec \\<ServerName> -s powershell.exe -Command "Get-Service WinRM"

# Or use RDP to log in interactively and run diagnostics locally
mstsc /v:<ServerName>
```

---

## 2. WinRM Service State

### Quick Status Check

```powershell
# Local
Get-Service WinRM | Select-Object Name, Status, StartType

# Remote via PowerShell Direct
Invoke-Command -VMName <VMName> -Credential $cred -ScriptBlock {
    $svc = Get-Service WinRM
    "Status: $($svc.Status), StartType: $($svc.StartType)"
}
```

### Service Stuck in StopPending

**Symptom**: `winrm quickconfig` returns HTTP 500 (`0x80338170`). The service
shows `StopPending` and cannot be started or stopped.

**Root Cause**: The svchost.exe hosting WinRM hung during its shutdown sequence,
commonly while processing WSMan plugin configuration operations. The service
never completed its stop, so start attempts fail because the SCM sees it as
still running.

**Diagnosis**:

```powershell
# Check service state and PID
$svc = Get-CimInstance Win32_Service -Filter "Name='WinRM'"
"PID: $($svc.ProcessId), State: $($svc.State)"

# Verify WinRM is the only service in the svchost (safe to kill)
$sharedSvcs = Get-CimInstance Win32_Service | Where-Object { $_.ProcessId -eq $svc.ProcessId }
$sharedSvcs | Select-Object Name, State
```

**Fix**:

```powershell
# 1. Kill the stuck svchost (only if WinRM is the sole service in the process)
$svcPid = (Get-CimInstance Win32_Service -Filter "Name='WinRM'").ProcessId
Stop-Process -Id $svcPid -Force

# 2. Wait for SCM to recognize the service as stopped
Start-Sleep -Seconds 3

# 3. Verify it's stopped
(Get-Service WinRM).Status  # Should be 'Stopped'

# 4. Start WinRM
Start-Service WinRM

# 5. Verify
(Get-Service WinRM).Status  # Should be 'Running'
```

> **WARNING**: Before killing the svchost, always verify that WinRM is the only
> service in that process. If other services share the same PID, killing it will
> terminate all of them.

### Service Won't Start (Exit Codes)

```powershell
# Check the service's exit code from last failure
$svc = Get-CimInstance Win32_Service -Filter "Name='WinRM'"
"ExitCode: $($svc.ExitCode), ServiceSpecificExitCode: $($svc.ServiceSpecificExitCode)"

# Check System event log for service failures
Get-WinEvent -FilterHashtable @{
    LogName      = 'System'
    ProviderName = 'Service Control Manager'
    Level        = 2  # Error
    StartTime    = (Get-Date).AddHours(-4)
} -MaxEvents 20 | Where-Object { $_.Message -like '*WinRM*' -or $_.Message -like '*Remote Management*' } |
    Select-Object TimeCreated, Id, Message
```

### Reset WinRM Configuration Entirely

As a last resort, reset the WinRM configuration to defaults:

```powershell
# Delete all listeners
Remove-Item WSMan:\localhost\Listener\* -Recurse -Force -ErrorAction SilentlyContinue

# Reset WinRM configuration
winrm invoke Restore winrm/config @{}

# Or re-run quickconfig
winrm quickconfig -Force

# Or use Enable-PSRemoting (does everything)
Enable-PSRemoting -Force -SkipNetworkProfileCheck
```

---

## 3. WinRM Listeners

WinRM needs at least one listener (HTTP on 5985, or HTTPS on 5986) to accept
connections.

### Check Existing Listeners

```powershell
# Via WSMan provider (requires WinRM running)
Get-ChildItem WSMan:\localhost\Listener | ForEach-Object {
    $props = Get-ChildItem $_.PSPath
    [PSCustomObject]@{
        Name      = $_.Name
        Address   = ($props | Where-Object Name -eq 'Address').Value
        Transport = ($props | Where-Object Name -eq 'Transport').Value
        Port      = ($props | Where-Object Name -eq 'Port').Value
        CertThumb = ($props | Where-Object Name -eq 'CertificateThumbprint').Value
        Enabled   = ($props | Where-Object Name -eq 'Enabled').Value
    }
}

# Via registry (works even when WinRM is stopped)
Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WSMAN\Listener' |
    ForEach-Object {
        $props = Get-ItemProperty $_.PSPath
        [PSCustomObject]@{
            Name      = $_.PSChildName
            Transport = $props.Transport
            Port      = $props.Port
            CertThumb = $props.CertificateThumbprint
            Hostname  = $props.hostname
        }
    }
```

### Create HTTP Listener (Port 5985)

```powershell
# Automatic (creates HTTP listener on all addresses)
Enable-PSRemoting -Force -SkipNetworkProfileCheck

# Manual
New-Item WSMan:\localhost\Listener -Transport HTTP -Address * -Force
```

### Create HTTPS Listener (Port 5986)

```powershell
# Requires a valid SSL certificate in Cert:\LocalMachine\My
$cert = Get-ChildItem Cert:\LocalMachine\My |
    Where-Object { $_.Subject -match $env:COMPUTERNAME -and $_.NotAfter -gt (Get-Date) } |
    Sort-Object NotAfter -Descending | Select-Object -First 1

if (-not $cert) {
    Write-Error "No valid certificate found for $env:COMPUTERNAME"
    return
}

New-Item WSMan:\localhost\Listener -Transport HTTPS -Address * `
    -CertificateThumbPrint $cert.Thumbprint -Force -Hostname $env:COMPUTERNAME
```

### HTTPS Certificate Issues

**Symptom**: HTTPS listener exists but connections fail with certificate errors.

```powershell
# Check if the certificate referenced by the listener is valid
$listenerThumb = (Get-ChildItem WSMan:\localhost\Listener |
    Where-Object { (Get-ChildItem "$($_.PSPath)\Transport").Value -eq 'HTTPS' } |
    ForEach-Object { (Get-ChildItem "$($_.PSPath)\CertificateThumbprint").Value })

$cert = Get-ChildItem Cert:\LocalMachine\My\$listenerThumb -ErrorAction SilentlyContinue
if ($cert) {
    "Subject: $($cert.Subject)"
    "Expires: $($cert.NotAfter)"
    "Expired: $($cert.NotAfter -lt (Get-Date))"
    "HasPrivateKey: $($cert.HasPrivateKey)"
} else {
    "Certificate $listenerThumb NOT FOUND in local store - listener is broken"
}
```

**Fix for expired/missing certificate**: Delete the HTTPS listener and recreate
it with a new certificate, or switch to HTTP.

---

## 4. Firewall Rules

### Check WinRM Firewall Rules

```powershell
# Check if WinRM firewall rules exist and are enabled
Get-NetFirewallRule -Name 'WINRM-HTTP-In-TCP*' |
    Select-Object Name, DisplayName, Enabled, Profile, Action

# Check if port 5985 is actually reachable (from the client)
Test-NetConnection -ComputerName <Target> -Port 5985
Test-NetConnection -ComputerName <Target> -Port 5986  # HTTPS
```

### Enable WinRM Firewall Rules

```powershell
# Enable for all profiles
Set-NetFirewallRule -Name 'WINRM-HTTP-In-TCP' -Enabled True
Set-NetFirewallRule -Name 'WINRM-HTTP-In-TCP-PUBLIC' -Enabled True

# Or create rules if they don't exist
New-NetFirewallRule -Name 'WINRM-HTTP-In-TCP-Custom' -DisplayName 'WinRM HTTP' `
    -Direction Inbound -Protocol TCP -LocalPort 5985 -Action Allow -Profile Any
```

### Network Profile Issue

**Symptom**: `Enable-PSRemoting` fails with "WinRM firewall exception will not
work since one of the network connection types on this machine is set to Public."

**Fix**:

```powershell
# Option 1: Skip the network profile check
Enable-PSRemoting -Force -SkipNetworkProfileCheck

# Option 2: Change the network profile to Private
$adapter = Get-NetConnectionProfile | Where-Object NetworkCategory -eq Public
Set-NetConnectionProfile -InterfaceIndex $adapter.InterfaceIndex -NetworkCategory Private
```

---

## 5. Authentication Issues

### Kerberos Failures

**Symptom**: `Invoke-Command` fails with `SEC_E_NO_CREDENTIALS` or
`The WinRM client cannot process the request because the server name cannot be
resolved`.

```powershell
# Verify DNS resolution
Resolve-DnsName <ServerFQDN>
Resolve-DnsName <ServerFQDN> -Type SRV

# Verify Kerberos ticket
klist get HTTP/<ServerFQDN>

# Verify SPN registration
setspn -Q HTTP/<ServerFQDN>
setspn -Q WSMAN/<ServerFQDN>

# Test with explicit authentication
$cred = Get-Credential
Invoke-Command -ComputerName <ServerFQDN> -Credential $cred -Authentication Negotiate -ScriptBlock { hostname }
```

> **Note**: Kerberos requires FQDN. Using IP addresses forces NTLM fallback.
> With NTLM, the target must be in TrustedHosts or be in the same domain.

### NTLM / TrustedHosts (Workgroup or Cross-Domain)

**Symptom**: `Invoke-Command` to an IP address or workgroup machine fails with
"access denied" or "WinRM cannot process the request".

```powershell
# Check current TrustedHosts
Get-Item WSMan:\localhost\Client\TrustedHosts

# Add a specific host
Set-Item WSMan:\localhost\Client\TrustedHosts -Value '<IP or hostname>' -Force

# Add multiple hosts (comma-separated)
Set-Item WSMan:\localhost\Client\TrustedHosts -Value '192.168.1.10,192.168.1.11' -Force

# Allow all (lab environments only — insecure for production)
Set-Item WSMan:\localhost\Client\TrustedHosts -Value '*' -Force
```

### CredSSP (Double-Hop)

**Symptom**: Command runs on the remote server but fails when that server tries
to access a third resource (file share, SQL server, etc.) — "access denied" on
the second hop.

```powershell
# Enable CredSSP on the client (delegating machine)
Enable-WSManCredSSP -Role Client -DelegateComputer '<ServerFQDN>' -Force

# Enable CredSSP on the server (receiving machine)
Enable-WSManCredSSP -Role Server -Force

# Connect using CredSSP authentication
$cred = Get-Credential
Invoke-Command -ComputerName <Server> -Credential $cred -Authentication CredSSP -ScriptBlock {
    # Can now access network resources with delegated credentials
    Get-ChildItem \\FileServer\Share
}

# Verify CredSSP state
Get-WSManCredSSP
```

> **Security Warning**: CredSSP sends credentials to the remote server in a
> delegatable form. Only use in trusted environments (e.g., labs). For production,
> consider Resource-Based Kerberos Constrained Delegation (RBKCD) instead.

---

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
# Increase MaxEnvelopeSize (default 500KB, max 2GB)
Set-Item WSMan:\localhost\MaxEnvelopeSizekb -Value 8192  # 8MB

# Remote
Set-Item WSMan:\localhost\Client\MaxEnvelopeSizekb -Value 8192
```

### MaxMemoryPerShellMB (Out of Memory)

**Symptom**: Remote sessions crash or return incomplete results with large datasets.

```powershell
# Increase per-shell memory (default 1024MB)
Set-Item WSMan:\localhost\Shell\MaxMemoryPerShellMB -Value 2048

# Or set to unlimited (lab only)
Set-Item WSMan:\localhost\Shell\MaxMemoryPerShellMB -Value 0
```

### MaxConcurrentOperationsPerUser

**Symptom**: New sessions fail when many are already open.

```powershell
Set-Item WSMan:\localhost\Service\MaxConcurrentOperationsPerUser -Value 50
```

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

| Error Code | Hex | Meaning | Common Fix |
|---|---|---|---|
| -2144108526 | `0x80338012` | WinRM cannot complete the operation — service not running | `Start-Service WinRM` |
| -2144108176 | `0x80338170` | HTTP server error 500 | Service stuck in StopPending — kill svchost, restart |
| -2144108250 | `0x803380E4` | Cannot connect to remote server | Check firewall, listener, DNS |
| -2144108387 | `0x8033809D` | Access denied | Check credentials, TrustedHosts, authentication |
| -2144108102 | `0x803381A6` | Cannot find the computer | DNS resolution failure |
| -2144108294 | `0x80338126` | WinRM cannot process request | Check authentication method, MaxEnvelopeSize |
| -2144108061 | `0x803381C3` | Server certificate validation failed | Fix HTTPS cert or use HTTP |
| -2146885628 | `0x80090304` | SEC_E_NO_CREDENTIALS | Kerberos/SPN misconfiguration |
| -2146893042 | `0x80090322` | SEC_E_WRONG_PRINCIPAL | SPN mismatch — target name doesn't match certificate or SPN |

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
    $port5985 = (Get-NetTCPConnection -LocalPort 5985 -ErrorAction SilentlyContinue | Measure-Object).Count
    $port5986 = (Get-NetTCPConnection -LocalPort 5986 -ErrorAction SilentlyContinue | Measure-Object).Count
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
        "[$($_.TimeCreated)] ID:$($_.Id) $($_.Message.Split("`n")[0].Substring(0, [Math]::Min(150, $_.Message.Length)))"
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
    $pid = (Get-CimInstance Win32_Service -Filter "Name='WinRM'").ProcessId
    Stop-Process -Id $pid -Force
    Start-Sleep 3
    Start-Service WinRM
    (Get-Service WinRM).Status
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

    # Re-enable firewall rules
    Set-NetFirewallRule -Name 'WINRM-HTTP-In-TCP' -Enabled True -ErrorAction SilentlyContinue
    Set-NetFirewallRule -Name 'WINRM-HTTP-In-TCP-PUBLIC' -Enabled True -ErrorAction SilentlyContinue
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
