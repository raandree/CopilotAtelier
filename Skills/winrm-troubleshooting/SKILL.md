---
name: winrm-troubleshooting
description: >-
  Diagnoses WinRM failures on Windows servers and AutomatedLab VMs: service
  startup, listeners, HTTP.sys/IIS, authentication, HTTPS, firewall,
  TrustedHosts, limits, double hop, and fallback channels. USE FOR: WinRM error,
  HTTP 500, quickconfig failure, StopPending, service won't start, listener
  missing, connection refused/denied/timeout, Enter-PSSession failure,
  Invoke-Command failure, WSManFault, 0x80338170, 0x80070005, 0x80090322,
  firewall, HTTPS, CredSSP, TrustedHosts, Kerberos, double hop, PowerShell
  Direct, MaxEnvelopeSize, port 5985/5986, Test-WSMan, ping works but WinRM is
  closed after reboot. DO NOT USE FOR: AutomatedLab Proxmox lifecycle ordering
    (use automatedlab-proxmox), monitoring a running remote job (use
    long-running-job-monitor), SSH remoting, Azure Automation DSC, general
    networking.
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

```text
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
```

The guard must refuse termination when another service shares the process.

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

# Reset WinRM configuration. Quote the literal native-command payload.
winrm invoke Restore winrm/config '@{}'

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
# Select an explicit certificate; do not guess from a subject regex.
$hostname = '<server.example.com>'
$thumbprint = '<certificate thumbprint>'
$cert = Get-Item "Cert:\LocalMachine\My\$thumbprint" -ErrorAction Stop

if (-not $cert.HasPrivateKey -or
    $cert.NotBefore -gt (Get-Date) -or
    $cert.NotAfter -le (Get-Date) -or
    -not (Test-Certificate -Cert $cert -Policy SSL -DNSName $hostname)) {
    throw "Certificate '$thumbprint' is not valid and trusted for '$hostname'."
}

New-Item WSMan:\localhost\Listener -Transport HTTPS -Address * `
    -CertificateThumbPrint $cert.Thumbprint -Force -Hostname $hostname
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
# Prefer the built-in configuration. On Public networks,
# -SkipNetworkProfileCheck keeps the rule scoped to the local subnet.
Enable-PSRemoting -Force -SkipNetworkProfileCheck

# If a custom rule is required, restrict source and trusted profiles.
$managementSubnet = '<management subnet CIDR>'
New-NetFirewallRule -Name 'WINRM-HTTP-In-TCP-Custom' -DisplayName 'WinRM HTTP' `
    -Direction Inbound -Protocol TCP -LocalPort 5985 -Action Allow `
    -Profile Domain,Private -RemoteAddress $managementSubnet
```

Do not create `Profile Any` rules or unrestricted Public-profile rules. For a
Public network, prefer HTTPS and permit only an explicit management source.

### Network Profile Issue

**Symptom**: `Enable-PSRemoting` fails with "WinRM firewall exception will not
work since one of the network connection types on this machine is set to Public."

**Fix**:

```powershell
# Option 1: Skip the network profile check
Enable-PSRemoting -Force -SkipNetworkProfileCheck

# Option 2: Change only a verified trusted network to Private.
$trustedAdapterName = '<trusted adapter name>'
$interfaceIndex = (Get-NetAdapter -Name $trustedAdapterName -ErrorAction Stop).ifIndex
$profile = Get-NetConnectionProfile -InterfaceIndex $interfaceIndex
if ($profile.NetworkCategory -ne 'Public') {
    throw "Interface $($profile.InterfaceIndex) is not Public."
}
Set-NetConnectionProfile -InterfaceIndex $profile.InterfaceIndex `
    -NetworkCategory Private
```

Do not relabel an untrusted network as Private merely to open WinRM.

---

## 5. Authentication Issues

### Kerberos Failures

**Symptom**: `Invoke-Command` fails with `SEC_E_NO_CREDENTIALS` or
`The WinRM client cannot process the request because the server name cannot be
resolved`.

```powershell
# Verify DNS resolution
Resolve-DnsName <ServerFQDN>
Resolve-DnsName '_kerberos._tcp.<ADDomainFQDN>' -Type SRV

# Verify Kerberos ticket
klist get HTTP/<ServerFQDN>

# Verify SPN registration
setspn -Q HTTP/<ServerFQDN>
setspn -Q WSMAN/<ServerFQDN>

# Test with explicit authentication
$cred = Get-Credential
Invoke-Command -ComputerName <ServerFQDN> -Credential $cred -Authentication Negotiate -ScriptBlock { hostname }
```

> **Note**: Kerberos requires a target name with a matching SPN. Short names can
> work when DNS and SPNs are valid; an FQDN is usually easier to verify. An IP
> address normally prevents Kerberos, so use HTTPS or explicit NTLM credentials
> with that exact target in `TrustedHosts`.

### NTLM / TrustedHosts (Workgroup or Cross-Domain)

**Symptom**: `Invoke-Command` to an IP address or workgroup machine fails with
"access denied" or "WinRM cannot process the request".

```powershell
# Check current TrustedHosts
Get-Item WSMan:\localhost\Client\TrustedHosts

# Append specific hosts without replacing the machine-wide list.
$trustedHostsPath = 'WSMan:\localhost\Client\TrustedHosts'
$hostToAdd = '<IP or hostname>'
$currentValue = (Get-Item $trustedHostsPath).Value
if ($currentValue -ne '*') {
    $trustedHosts = @(
        $currentValue -split ','
        $hostToAdd
    ) | ForEach-Object { $_.Trim() } |
        Where-Object { $_ } |
        Sort-Object -Unique

    Set-Item $trustedHostsPath -Value ($trustedHosts -join ',') -Force
}
```

`TrustedHosts` is machine-wide. Preserve the current value, add only explicit
hosts supplied for this operation, and avoid wildcard trust. If `*` is intentionally required in a
disposable isolated lab, set it as a separate explicit operation and restore
the prior value afterward.

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

## Post-restart readiness

For staged readiness after reboot, protocol-specific probes, and the boundary
between expected startup and persistent failure, read
[`references/post-restart-readiness.md`](references/post-restart-readiness.md).
For AutomatedLab Proxmox lifecycle ordering, use `automatedlab-proxmox`.

## Advanced diagnostics and fixes

- For HTTP.sys/IIS conflicts, WinRM limits, event logs, and error codes, read
  [`references/advanced-diagnostics.md`](references/advanced-diagnostics.md).
- The same reference contains the comprehensive remote diagnostic script and
  quick fix recipes.

## Evals

Real restart-readiness regressions live in [`notes-evals.md`](notes-evals.md).
