---
name: dsc-troubleshooting
description: >-
  Debug and troubleshoot PowerShell DSC (Desired State Configuration) resource failures
  on target nodes. Covers LCM diagnostics, event log analysis, resource debugging with
  Wait-Debugger and Enter-PSHostProcess, cache clearing, common exit codes, installer
  log analysis, patching third-party DSC resources, and remote troubleshooting via
  AutomatedLab Invoke-LabCommand. Includes Windows Server 2025 specific issues like
  Start-Process UNC path hangs and class-based resource ForceModuleImport failures.
  USE FOR: DSC error, DSC resource failed, DSC troubleshooting, debug DSC resource,
  Wait-Debugger, Enter-PSHostProcess, Debug-Runspace, InBreakpoint, LCM state,
  Get-DscConfigurationStatus, DSC event log, exit code, 30066, 3010, 17022,
  ProviderOperationExecutionFailure, Set-TargetResource failed, Test-TargetResource,
  DSC cache, WmiPrvSE, DebugMode, ForceModuleImport, Enable-DscDebug, xDscDiagnostics,
  Trace-xDscOperation, Get-xDscOperation, DSC verbose log, setup.exe exit code,
  MSI installer DSC, PsDscRunAsCredential debug, DSC resource not working,
  Start-DscConfiguration error, config.xml not found, working directory DSC,
  Start-Process hang, UseShellExecute, UNC path hang, Windows Server 2025 DSC,
  class-based DSC resource, SYSTEM profile logs.
  DO NOT USE FOR: writing new DSC resources from scratch (use DSC resource authoring docs),
  DSC pull server setup (use pull server docs), Azure Automation DSC (use azure-diagnostics),
  building Sampler modules (use sampler-build-debug).
---

# DSC Resource Troubleshooting

Skill for diagnosing and fixing failures in PowerShell DSC (Desired State Configuration)
resource execution on Windows target nodes such as lab VMs.

## When to Use

- A DSC resource fails during `Start-DscConfiguration` with an error or unexpected exit code
- `Get-DscConfigurationStatus` shows `Failure` or resources not in desired state
- `Wait-Debugger` breakpoints halt execution but you cannot find the runspace
- A third-party DSC resource needs patching to work on newer OS versions
- LCM is stuck in `Busy` state or cached modules need refreshing
- You need to read DSC event logs or installer logs from a remote node

## Diagnostic Workflow

Follow this sequence when investigating a DSC resource failure:

```
1. Check LCM state and last run status
2. Read verbose output and error messages
3. Check DSC event logs (Operational, Analytic, Debug)
4. Check application-specific logs (installer logs, Event Viewer)
5. Inspect the DSC resource source code (Set-TargetResource)
6. Reproduce the failure manually on the target node
7. Apply fix and re-test
```

---

## 1. Quick Status Check

### LCM State and Last Configuration Status

```powershell
# Check LCM state (Idle, Busy, PendingReboot, PendingConfiguration)
Get-DscLocalConfigurationManager | Select-Object LCMState, LCMStateDetail

# Last configuration run result
$status = Get-DscConfigurationStatus
$status | Select-Object Status, StartDate, Type, Mode, RebootRequested, NumberOfResources

# Resources that failed
$status.ResourcesNotInDesiredState | Select-Object ResourceId, ModuleName, Error

# All historical runs
Get-DscConfigurationStatus -All | Select-Object Status, StartDate, Type
```

### Remote Status via AutomatedLab

```powershell
Import-Lab -Name <LabName> -NoValidation
Invoke-LabCommand -ComputerName <VMName> -ScriptBlock {
    $lcm = Get-DscLocalConfigurationManager
    $status = Get-DscConfigurationStatus -ErrorAction SilentlyContinue
    [PSCustomObject]@{
        LCMState     = $lcm.LCMState
        DebugMode    = $lcm.DebugMode
        LastStatus   = $status.Status
        LastStart    = $status.StartDate
        FailedCount  = ($status.ResourcesNotInDesiredState | Measure-Object).Count
    }
} -PassThru
```

---

## 2. DSC Event Logs

DSC writes to three event log channels under `Microsoft-Windows-Dsc/`:

| Channel | Default | Content |
|---------|---------|---------|
| **Operational** | Enabled | Errors, high-level operation results |
| **Analytic** | Disabled | Detailed resource execution steps |
| **Debug** | Disabled | Low-level engine internals |

### Enable Analytic and Debug Logs

```powershell
wevtutil.exe set-log "Microsoft-Windows-Dsc/Analytic" /q:true /e:true
wevtutil.exe set-log "Microsoft-Windows-Dsc/Debug" /q:true /e:true
```

### Query DSC Events

```powershell
# Recent errors from DSC Operational log
Get-WinEvent -LogName 'Microsoft-Windows-Dsc/Operational' -MaxEvents 20 |
    Where-Object LevelDisplayName -in 'Error','Warning' |
    Select-Object TimeCreated, Id, LevelDisplayName, Message

# Group by Job ID to isolate a single DSC run
$events = Get-WinEvent -LogName 'Microsoft-Windows-Dsc/Operational'
$grouped = $events | Group-Object { $_.Properties[0].Value }
$grouped[0].Group | Select-Object TimeCreated, Id, LevelDisplayName, Message
```

### Using xDscDiagnostics

```powershell
Import-Module xDscDiagnostics

# List recent DSC operations
Get-xDscOperation -Newest 5

# Trace a specific failed operation (by SequenceID or JobID)
Trace-xDscOperation -SequenceID 1

# Remote diagnostics
Trace-xDscOperation -ComputerName <NodeName> -Credential (Get-Credential) -SequenceID 1
```

---

## 3. Debugging DSC Resources

### Method A: Enable-DscDebug (LCM-level, breaks on ALL resources)

```powershell
# Enable — LCM will break into debugger on every resource
Enable-DscDebug -BreakAll

# Verify
(Get-DscLocalConfigurationManager).DebugMode
# Expected: ForceModuleImport, ResourceScriptBreakAll

# Start configuration — it will pause at first resource
Start-DscConfiguration -Path .\Config -Wait -Verbose

# DSC output will tell you exactly what to do:
#   Enter-PSSession -ComputerName <NODE> -Credential <cred>
#   Enter-PSHostProcess -Id <PID> -AppDomainName DscPsPluginWkr_AppDomain
#   Debug-Runspace -Id <ID>

# Disable when done
Disable-DscDebug
```

### Method B: Wait-Debugger (targeted, single resource)

Insert `Wait-Debugger` into the DSC resource `.psm1` file at the point you want
to break. This is more surgical than Enable-DscDebug.

```powershell
function Set-TargetResource {
    param ( ... )

    Wait-Debugger  # <-- Execution halts here

    # ... rest of the resource logic
}
```

**CRITICAL: Finding the runspace depends on PsDscRunAsCredential:**

#### Without PsDscRunAsCredential (resources run inside wmiprvse.exe)

```powershell
# On the target node, from an elevated PowerShell:
Enter-PSHostProcess -Name wmiprvse

# Find the halted runspace
Get-Runspace | Where-Object { $_.Debugger.InBreakpoint }

# Attach
Debug-Runspace -Id <ID>
```

#### With PsDscRunAsCredential (resources run in a SEPARATE powershell.exe)

The LCM spawns a child `powershell.exe` process under the specified credentials.
The halted runspace is inside **that** process, not in your session and not in
wmiprvse.exe. This is the most common reason `Wait-Debugger` appears to not work.

```powershell
# 1. Find the child PowerShell process (not your own PID)
Get-Process powershell | Where-Object { $_.Id -ne $PID } |
    Select-Object Id, StartTime, @{N='CmdLine';E={$_.CommandLine}}

# 2. Enter that process
Enter-PSHostProcess -Id <CHILD_PID>

# 3. Find the halted runspace
Get-Runspace | Where-Object { $_.Debugger.InBreakpoint }

# 4. Attach debugger
Debug-Runspace -Id <ID>

# 5. Use standard debugger commands: s (step), c (continue), v (variables), k (callstack)
```

> **Tip**: If multiple powershell.exe processes exist, the DSC child process is
> typically the most recently started one that you did NOT launch interactively.

---

## 4. Common Failure Patterns

### 4.1 Relative Paths in Start-Process

**Symptom**: Setup.exe returns an unexpected exit code. No log file is created.

**Root Cause**: DSC resource calls `Start-Process` with a relative path argument
(e.g., `/config .\files\config.xml`) but does not set `-WorkingDirectory`.
During DSC execution, the working directory is inherited from the LCM host
process (typically `C:\Windows\System32`), not the source directory.

**Fix**: Add `-WorkingDirectory` to the `Start-Process` call:

```powershell
# Before (broken)
Start-Process -FilePath $setupExe -ArgumentList '/config .\files\config.xml' -Wait -PassThru

# After (fixed)
Start-Process -FilePath $setupExe -ArgumentList '/config .\files\config.xml' -Wait -PassThru `
    -WorkingDirectory $BinaryDir
```

### 4.2 Start-Process Hangs on UNC Paths (Windows Server 2025)

**Symptom**: DSC resource hangs indefinitely during `Set-TargetResource`. The
setup process never completes. Killing the DSC job shows the `Start-Process`
call never returned.

**Root Cause**: PowerShell 5.1's `Start-Process` defaults to `UseShellExecute=$true`,
which calls Win32 `ShellExecuteEx`. On Windows Server 2025 in non-interactive
sessions (WinRM/DSC/SYSTEM context), `ShellExecuteEx` triggers a security zone
check for UNC paths. The resulting prompt is blocked because there is no desktop
to display it on, causing an indefinite hang.

This affects **any** DSC resource that uses `Start-Process` to launch an `.exe`
from a UNC path (e.g., `\\server\share\setup.exe`).

**Fix**: Replace `Start-Process` with `[System.Diagnostics.Process]::Start()`
using `UseShellExecute = $false`:

```powershell
# Before (hangs on UNC paths in non-interactive sessions on Server 2025)
$result = Start-Process -Wait -PassThru -FilePath $setupExe -ArgumentList $args -WindowStyle Hidden

# After (works reliably)
$psi = [System.Diagnostics.ProcessStartInfo]@{
    FileName        = $setupExe
    Arguments       = $args
    UseShellExecute = $false
    CreateNoWindow  = $true
}
$proc = [System.Diagnostics.Process]::Start($psi)
$proc.WaitForExit()
$exitCode = $proc.ExitCode
```

> **Note**: `UseShellExecute = $false` also prevents environment variable
> expansion in the command line and disables shell features like file associations.
> This is the correct behavior for installer executables.

**Affected OS versions**: Windows Server 2025 (build 26100+). Does not reproduce
on Server 2019 or 2022 in most configurations.

### 4.3 LCM Stuck in Busy State

```powershell
# Check current state
(Get-DscLocalConfigurationManager).LCMState

# If stuck, force reset
Remove-DscConfigurationDocument -Stage Current, Pending, Previous -Force

# Or restart the WMI service
Restart-Service WinMgmt -Force
```

**When WinMgmt restart hangs**: If the command is issued via `Invoke-LabCommand`
(WinRM/PSRemoting), `Restart-Service WinMgmt` will hang because the WMI service
hosts the remoting session. The restart kills the session, which can't report
completion. Solution: **reboot the node from the Hyper-V host**:
```powershell
Stop-VM -Name <VMName> -Force -TurnOff
Start-Sleep 5
Start-VM -Name <VMName>
```

**Phantom Busy state after force reboot**: After a hard reboot during DSC
processing, the LCM may remain in `Busy` with no child processes (powershell.exe,
wmiprvse.exe active in DSC). Verify with:
```powershell
Get-Process powershell, pwsh -EA 0 | Where-Object { $_.Id -ne $PID }  # Should be empty
Get-Process WmiPrvSE -EA 0  # Only base WMI hosts, no DSC activity
```
If no DSC processes are running but LCM reports `Busy`, the state is stale.
A reboot clears it. `Remove-DscConfigurationDocument` alone may not help because
the LCM lock file is held.

### 4.3.1 Auto-Correct Timer Interfering with Long-Running SetScript

When `ConfigurationMode = 'ApplyAndAutoCorrect'`, the consistency timer fires
every 15-30 minutes. If a `Script` resource's `SetScript` takes longer (e.g.,
a 60-minute software install), the timer may re-invoke the resource while the
previous `SetScript` is still running. If the `SetScript` includes cleanup steps
(kill processes, delete directories), it will destroy the in-progress installation.

**Symptoms**: Installation processes vanish mid-install. Setup logs disappear.
No DSC errors — just a new consistency run that starts over.

**Fix in the DSC resource**: Detect running installations before cleanup:
```powershell
SetScript = {
    # Check if a prior install is still actively running
    $activeInstall = Get-Process -Name SetupWpf -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -like '*SCCMSetup*' }
    if ($activeInstall) {
        Write-Verbose "Installation already in progress. Waiting instead of restarting."
        # Wait for it instead of killing it
        $activeInstall | Wait-Process -Timeout 7200
        return
    }
    # ... proceed with cleanup and new install ...
}
```

**Manual workaround**: Temporarily disable the LCM before starting a long install:
```powershell
[DSCLocalConfigurationManager()]
Configuration DisableLCM {
    Settings { ConfigurationMode = 'ApplyOnly'; RefreshMode = 'Disabled' }
}
DisableLCM -OutputPath C:\Temp\LCMDisable | Out-Null
Set-DscLocalConfigurationManager -Path C:\Temp\LCMDisable -Force
# ... run long install ...
# Re-apply original MetaMOF afterward
```

### 4.4 Cached Module Not Updating

DSC caches resource modules in the WMI Provider Host Process (`WmiPrvSE`).
After patching a resource `.psm1` file, the old version may still be cached.

```powershell
# Option 1: Kill the WMI provider host process (quickest, works for MOF-based resources)
$dscProcId = Get-CimInstance -ClassName Msft_Providers -Filter "provider='dsccore'" |
    Select-Object -ExpandProperty HostProcessIdentifier
Stop-Process -Id $dscProcId -Force

# Option 2: Kill ALL WmiPrvSE processes + clear DSC engine cache
Get-Process WmiPrvSE -ErrorAction SilentlyContinue | Stop-Process -Force
Remove-Item "$env:SystemRoot\System32\Configuration\DSCEngineCache.mof" -Force -EA SilentlyContinue

# Option 3: Reboot the node (always works, required for class-based resources)
Restart-Computer -Force
```

> **WARNING**: `DebugMode = 'ForceModuleImport'` only works reliably with
> **MOF-based** DSC resources. For **class-based** DSC resources on PowerShell 5.1,
> `ForceModuleImport` can cause DSC to fail silently (all resources report
> "not in desired state" with duration under 10s and null errors). This happens
> because the module reimport triggers PSDesiredStateConfiguration 2.0 conflicts
> on PS 5.1. **Use a reboot instead** to force class-based resource module reload.

### 4.6 PsDscRunAsCredential Errors

**Symptom**: Resource works when run interactively but fails under DSC.

**Common causes**:
- Credential doesn't have local admin rights on the target
- CredSSP delegation not configured for double-hop scenarios (the DSC resource
  needs to access network resources like file shares or SQL servers, but the
  LCM session does not delegate credentials). In AutomatedLab environments,
  `Invoke-LabCommand` uses CredSSP by default — but the LCM itself does not.
  If the DSC resource needs network access, the RunAs account must have direct
  access without requiring credential delegation, or CredSSP must be configured
  on the node.
- UNC path access requires the RunAs account to have share/NTFS permissions
- Working directory differs from interactive session

### 4.7 Pending Reboot Blocking Configuration

```powershell
# Check reboot flags
$rebootPending = @(
    Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
    Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
    (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -EA SilentlyContinue) -ne $null
)
"Reboot pending: $($rebootPending -contains $true)"

# Allow LCM to reboot automatically (use with caution)
[DSCLocalConfigurationManager()]
Configuration LCMReboot {
    Node localhost {
        Settings { RebootNodeIfNeeded = $true }
    }
}
```

---

## 5. Common Exit Codes

### Office / MSI Installer Exit Codes

| Exit Code | Meaning | Resolution |
|-----------|---------|------------|
| **0** | Success | N/A |
| **3010** | Success, reboot required | Set `$global:DSCMachineStatus = 1` |
| **17022** | Reboot required before install can proceed | Reboot node, re-run |
| **30066** | Unsupported operating system | Setup not finding config.xml (relative path bug) or genuine OS incompatibility |
| **30015** | Prerequisites not met | Install prerequisites first |
| **1603** | MSI fatal error | Check MSI log in `%TEMP%` |
| **1618** | Another installation in progress | Wait or kill competing msiexec |

### Where to Find Installer Logs

```powershell
# Office setup logs (location controlled by config.xml <Logging> element)
Get-ChildItem "$env:TEMP" -Filter '*.log' | Sort-Object LastWriteTime -Descending

# MSI verbose logs
msiexec /i package.msi /l*v "$env:TEMP\msi_install.log"

# Windows Installer events in Event Viewer
Get-WinEvent -FilterHashtable @{
    LogName      = 'Application'
    ProviderName = 'MsiInstaller'
    StartTime    = (Get-Date).AddHours(-2)
}
```

> **Important**: When DSC runs under `PsDscRunAsCredential`, logs are written to
> **that user's** `%TEMP%` directory, not the interactive user's. Check
> `C:\Users\<RunAsUser>\AppData\Local\Temp\`.
>
> When DSC runs as SYSTEM (no PsDscRunAsCredential), logs go to
> `C:\Windows\System32\config\systemprofile\AppData\Local\Temp\`.
>
> Some installers write logs to non-TEMP locations under `%LOCALAPPDATA%`.
> Under the SYSTEM account, this resolves to
> `C:\Windows\System32\config\systemprofile\AppData\Local\`. Always search
> this path tree when looking for installer logs from DSC-initiated setups:
>
> ```powershell
> # Find recent log files under SYSTEM's profile
> Get-ChildItem 'C:\Windows\System32\config\systemprofile\AppData\Local' `
>     -Filter '*.log' -Recurse -ErrorAction SilentlyContinue |
>     Sort-Object LastWriteTime -Descending | Select-Object -First 10
> ```

---

## 6. Patching Third-Party DSC Resources

When a community DSC resource has a bug, patch it locally and prevent the build
from overwriting the fix:

### Step 1: Edit the resource .psm1 in output/RequiredModules

```
output/RequiredModules/<ModuleName>/<Version>/DSCResources/<ResourceName>/<ResourceName>.psm1
```

### Step 2: Track the patched module in Git

Add an exclusion to `.gitignore` so the patched module is version-controlled:

```gitignore
# .gitignore already has:
output/RequiredModules/*

# Add exception for the patched module:
!output/RequiredModules/<ModuleName>
```

### Step 3: Prevent build from overwriting the patch

Comment out the module in `RequiredModules.psd1` with a note:

```powershell
# RequiredModules.psd1
@{
    # ...
    #<ModuleName> = '<Version>' # Patched: <brief description of fix>
    # ...
}
```

### Step 4: Deploy the fix to the target node

```powershell
# Copy the patched file to the VM
Copy-LabFileItem -Path 'output\RequiredModules\<ModuleName>\<Version>\DSCResources\<Resource>\<Resource>.psm1' `
    -ComputerName <VMName> `
    -DestinationFolderPath 'C:\Program Files\WindowsPowerShell\Modules\<ModuleName>\<Version>\DSCResources\<Resource>'

# Clear the DSC cache so the patched version gets loaded
Invoke-LabCommand -ComputerName <VMName> -ScriptBlock {
    $proc = Get-CimInstance Msft_Providers -Filter "provider='dsccore'" -EA SilentlyContinue
    if ($proc) { Stop-Process -Id $proc.HostProcessIdentifier -Force }
}
```

### Step 5: File an upstream issue

Report the bug to the module's GitHub repository with:
- Detailed scenario description
- Verbose DSC logs showing the failure
- Suggested fix (diff or code snippet)
- OS version, PowerShell version, module version
- Minimal reproduction configuration

---

## 7. Remote Troubleshooting via AutomatedLab

### Connecting to Lab VMs

```powershell
Import-Module AutomatedLab
Import-Lab -Name <LabName> -NoValidation

# Run commands on the target VM
Invoke-LabCommand -ComputerName <VMName> -ScriptBlock {
    # ... diagnostic commands ...
} -PassThru

# Copy files to the VM
Copy-LabFileItem -Path <LocalPath> -ComputerName <VMName> -DestinationFolderPath <RemotePath>
```

### Comprehensive Remote Diagnostic Script

```powershell
Invoke-LabCommand -ComputerName <VMName> -ScriptBlock {
    $results = [ordered]@{}

    # LCM State
    $lcm = Get-DscLocalConfigurationManager
    $results['LCMState'] = $lcm.LCMState
    $results['DebugMode'] = $lcm.DebugMode -join ', '

    # Last configuration status
    $status = Get-DscConfigurationStatus -ErrorAction SilentlyContinue
    $results['LastStatus'] = $status.Status
    $results['LastStart'] = $status.StartDate
    $results['Duration'] = $status.DurationInSeconds

    # Failed resources
    $failed = $status.ResourcesNotInDesiredState
    $results['FailedResources'] = ($failed | ForEach-Object { $_.ResourceId }) -join '; '

    # Reboot pending?
    $results['RebootPending'] = (
        (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or
        (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')
    )

    # Recent DSC errors in event log
    $dscErrors = Get-WinEvent -LogName 'Microsoft-Windows-Dsc/Operational' -MaxEvents 50 -EA SilentlyContinue |
        Where-Object LevelDisplayName -eq 'Error' |
        Select-Object -First 3 TimeCreated, Message
    $results['RecentErrors'] = ($dscErrors | ForEach-Object { "$($_.TimeCreated): $($_.Message.Substring(0, [Math]::Min(200, $_.Message.Length)))" }) -join "`n"

    [PSCustomObject]$results
} -PassThru
```

---

## 8. LCM Configuration Reference

| Setting | Default | Troubleshooting Use |
|---------|---------|---------------------|
| `DebugMode` | `None` | Set to `ForceModuleImport` to reload patched resources |
| `RebootNodeIfNeeded` | `$false` | Set `$true` if resources need reboots mid-configuration |
| `ConfigurationMode` | `ApplyAndMonitor` | Use `ApplyOnly` during debugging to prevent auto-remediation |
| `RefreshMode` | `Push` | Ensure `Push` for lab/debug scenarios |
| `ActionAfterReboot` | `ContinueConfiguration` | Ensures multi-reboot configs resume |

---

## References

- [Microsoft Docs: Troubleshooting DSC](https://learn.microsoft.com/en-us/powershell/dsc/troubleshooting/troubleshooting?view=dsc-1.1)
- [Microsoft Docs: Debugging DSC Resources](https://learn.microsoft.com/en-us/powershell/dsc/troubleshooting/debugResource?view=dsc-1.1)
- [xDscDiagnostics on GitHub](https://github.com/PowerShell/xDscDiagnostics)
- [DSC Community Resources](https://github.com/dsccommunity)

---

## PsDscRunAsCredential and Remote Runspace Behavior

When a DSC resource uses `PsDscRunAsCredential`, the LCM creates a **remote PowerShell
runspace** (via S4U logon) even though execution is local. This affects:

- WMI/CIM queries that require interactive logon (e.g., SMS WMI Provider)
- COM-based APIs that need a desktop session
- Cmdlets that create mutexes or named pipes with specific security contexts

**Symptoms**: Cmdlets return empty results, "Not found" errors, or `UnauthorizedAccessException`.

**Diagnosis**: Check DSC ETW logs for `AsyncResult.EndInvoke()` or `CoreInvokeRemoteHelper`
in the stack trace — these confirm a remote runspace is being used.

**Fix options**:
1. Remove `PsDscRunAsCredential` — let the resource run as SYSTEM (if SYSTEM has required access)
2. Use a `Script` resource with a scheduled task (Interactive logon type) for operations that need interactive context
3. Use `ServiceAccount` logon type in scheduled task for SYSTEM-equivalent access

**Example — Scheduled task pattern for interactive context**:
```powershell
Script MyResource {
    SetScript = {
        $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-File C:\script.ps1'
        $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType Interactive -RunLevel Highest
        Register-ScheduledTask -TaskName 'DSC_MyTask' -Action $action -Principal $principal
        Start-ScheduledTask -TaskName 'DSC_MyTask'
        # Poll for completion...
        Unregister-ScheduledTask -TaskName 'DSC_MyTask' -Confirm:$false
    }
}
```
