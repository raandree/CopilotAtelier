---
name: mecm-dsc-deployment
description: >-
  Deploy and troubleshoot Microsoft Endpoint Configuration Manager (MECM/SCCM) via DSC
  using ConfigMgrCBDsc, CommonTasks, and UpdateServicesDsc modules in DscWorkshop/Datum
  environments. Covers ADK/WinPE product registration, SCCM 2509 silent install,
  UpdateServicesDsc bugs, Datum merge strategies for Tiny scenarios, cross-domain SQL
  access, and AutomatedLab operational patterns.
  USE FOR: SCCM DSC, MECM DSC, ConfigMgrCBDsc, xSccmInstall, xSccmPreReqs, ADK product ID,
  ADK GUID mismatch, WinPE product name, SetupWpf.exe, SCCM silent install, SCCM 2509,
  ConfigurationManagerDeployment, UpdateServicesDsc, WSUS DSC, Products wildcard,
  Classifications wildcard, DatabaseInstance, SqlServerName, TinyMecmSiteServer,
  ConfigMgrVersion ValidateSet, SCCM setup return value 1, SetupWpf mutex,
  UnauthorizedAccessException mutex, cross-domain SQL, Kerberos double-hop SCCM,
  Install-LabSoftwarePackage SCCM, ADK offline layout, ADK download.
  DO NOT USE FOR: general DSC troubleshooting (use dsc-troubleshooting), Sampler build
  issues (use sampler-build-debug), Datum configuration basics (use datum-configuration),
  AutomatedLab deployment (use automatedlab-deployment).
---

# MECM/SCCM DSC Deployment

Skill for deploying and troubleshooting Microsoft Configuration Manager (MECM/SCCM)
installations via PowerShell DSC in DscWorkshop/Datum-based environments.

## When to Use

- DSC resources for SCCM installation fail (xSccmInstall, xSccmPreReqs, ConfigurationManagerDeployment)
- ADK or WinPE Package resources fail with ProductId/Name mismatch
- WSUS (UpdateServicesServer) DSC resource fails after install
- SCCM setup.exe or SetupWpf.exe fails silently or with exit code 1
- Cross-domain SQL connectivity issues during SCCM installation
- Datum/DscWorkshop Tiny scenario overrides for MECM

---

## ADK for Windows 11 24H2 (10.1.26100.x)

### Product Registration Names and GUIDs

The ADK for Windows 11 24H2 registers with DIFFERENT names than older versions:

| Component | Registered Name | GUID |
|-----------|----------------|------|
| ADK | `Windows Assessment and Deployment Kit` | `b09b3bef-7c75-4e26-ae6b-f6cdeb0fb071` |
| WinPE | `Windows Assessment and Deployment Kit Windows Preinstallation Environment Add-ons` | `e0f929f8-610d-469c-bfa1-7961a14eb91b` |

**Key difference**: No `- Windows 10` or `- Windows 11` suffix in the registered product name.

### Verifying Installed ADK

```powershell
# On the target node:
Get-CimInstance Win32_Product | Where-Object Name -like '*Assessment*' |
    Select-Object Name, IdentifyingNumber, Version
```

### ADK Offline Layout Download

```powershell
# Download ADK bootstrapper
Invoke-WebRequest -Uri 'https://go.microsoft.com/fwlink/?linkid=2271337' -OutFile adksetup.exe
Invoke-WebRequest -Uri 'https://go.microsoft.com/fwlink/?linkid=2271338' -OutFile adkwinpesetup.exe

# Create offline layouts
Start-Process adksetup.exe -ArgumentList '/layout "C:\ADKOffline" /quiet' -Wait
Start-Process adkwinpesetup.exe -ArgumentList '/layout "C:\ADKPEOffline" /quiet' -Wait
```

### Cleaning Up Failed ADK Installations

Old ADK installs leave ghost MSI entries that block new installations:

```powershell
# 1. Remove WOW6432Node ghost entries
Get-ChildItem 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall' |
    Get-ItemProperty | Where-Object { $_.DisplayName -like '*Assessment*' -or
    $_.DisplayName -like '*Deployment*' -or $_.DisplayName -like '*User State*' } |
    ForEach-Object { Remove-Item $_.PSPath -Force }

# 2. Remove Package Cache
Remove-Item 'C:\ProgramData\Package Cache' -Recurse -Force

# 3. Uninstall individual MSIs
Get-CimInstance Win32_Product | Where-Object {
    $_.Name -like '*Deployment*' -or $_.Name -like '*User State*'
} | ForEach-Object {
    Start-Process msiexec.exe -ArgumentList "/x $($_.IdentifyingNumber) /qn /norestart IGNOREDEPENDENCIES=ALL" -Wait
}

# 4. Reboot, then install fresh
```

---

## SCCM 2509 Installation

### xSccmInstall ValidateSet

The `xSccmInstall` resource in ConfigMgrCBDsc 4.0.0 only allows versions up to 2010.
Extend the ValidateSet:

```powershell
# In xSccmInstall.schema.psm1:
[ValidateSet('1902','1906','1910','2002','2006','2010','2103','2107','2111','2203','2207','2211','2303','2309','2403','2503','2509')]
```

### Product Name Prefix

ConfigMgr 2303+ rebranded from "Microsoft Endpoint" to "Microsoft":

```powershell
if ($Version -lt 1910) { $prefix = 'System Center' }
elseif ($Version -lt 2303) { $prefix = 'Microsoft Endpoint' }
else { $prefix = 'Microsoft' }
```

### Setup Path

The `xSccmInstall` resource does `Path = "$SetupExePath\Setup.exe"`. The config data
`ConfigManagerSetupPath` must provide only the **directory path**, not including `setup.exe`:

```yaml
# Correct:
ConfigManagerSetupPath: '\\server\share\MecmBinaries\2509\SMSSETUP\BIN\X64'
# Wrong (causes double path):
ConfigManagerSetupPath: '\\server\share\MecmBinaries\2509\SMSSETUP\BIN\X64\setup.exe'
```

### SetupWpf.exe Silent Install — Verified Working Approach (2026-03-16)

SCCM 2509 uses `SetupWpf.exe` (WPF app) instead of the classic bootstrapper. Multiple
approaches were tested; only ONE works for DSC-driven unattended installation:

**What works**: Scheduled task running `setup.exe` with `LogonType Interactive`.
`setup.exe` bootstraps `SetupWpf.exe` with the correct process context.

**What fails and why**:

| Approach | Failure |
|----------|---------|
| DSC Package resource → `setup.exe` | CreateProcess API → mutex UnauthorizedAccessException |
| Scheduled task → `SetupWpf.exe` + S4U | Non-interactive token → same mutex crash |
| Scheduled task → `SetupWpf.exe` + Interactive | Self-referential prereq bug (see below) |
| Scheduled task → `setup.exe` + S4U | Non-interactive token |
| **Scheduled task → `setup.exe` + Interactive** | **✅ WORKS** |

**Working DSC Script resource** — use `setup.exe` via scheduled task:
```powershell
$action    = New-ScheduledTaskAction -Execute $setupExe `
                -Argument "/SCRIPT $iniFile" `
                -WorkingDirectory $localX64
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' `
                -LogonType Interactive -RunLevel Highest
```

**Critical details**:
- Copy the **entire SMSSETUP directory** locally, not just `BIN\X64`. Setup needs `AI\`,
  `Redist\`, and other subdirectories. Missing `AI\LUTables.enc` causes "Failed to import
  Asset Intelligence data" errors.
- Do NOT quote the INI path: `/SCRIPT C:\path\file.ini` — quotes are treated as literal
  filename characters by SetupWpf, causing "not a valid file name" errors.
- Must start from a **clean system** with no `HKLM:\SOFTWARE\Microsoft\SMS` from prior
  failed attempts (see "Self-Referential Prereq Bug" below).

**Working approach with AutomatedLab** (non-DSC alternative):
```powershell
Install-LabSoftwarePackage -ComputerName YOURNODE `
    -LocalPath 'C:\Path\To\SetupWpf.exe' `
    -CommandLine '/SCRIPT C:\SetupFiles\Setup.ini' `
    -UseShellExecute -ExpectedReturnCodes 0,3010
```

### Self-Referential Prereq Check Bug

**Symptom**: `ERROR: SQL instance SQLSERVER\ is used by another SCCM installation` even
though SQL server has NO CM databases, NO SMS registry, NO SMS services.

**Cause**: SetupWpf.exe creates `HKLM:\SOFTWARE\Microsoft\SMS\Setup` at startup. After
a failed install, stale values remain. On retry, SetupWpf updates some values, prereqchk
reads the inconsistent mix, and reports "another SCCM installation."

**Fix**: Start from a clean snapshot OR thoroughly clean BOTH servers:
```powershell
# Site server: kill processes, delete services, clean registry
Get-Process setup, SetupWpf -EA 0 | Stop-Process -Force
Get-Service SMS_* -EA 0 | Stop-Service -Force
Get-Service SMS_* -EA 0 | ForEach-Object { sc.exe delete $_.Name }
reg delete 'HKLM\SOFTWARE\Microsoft\SMS' /f

# SQL server (CRITICAL — often missed!):
# SMS_SITE_SQL_BACKUP service recreates registry keys after deletion
Get-Service SMS_* -EA 0 | Stop-Service -Force
Get-Service SMS_* -EA 0 | ForEach-Object { sc.exe delete $_.Name }
reg delete 'HKLM\SOFTWARE\Microsoft\SMS' /f
```

**Kerberos limitation**: Cannot clean SQL from within DSC Script resource (double-hop).
Clean SQL externally before starting DSC.

### SCCM 2509 Blocking Prerequisites

These MUST be installed before the SCCM install resource runs:

| Prerequisite | Blocker Error |
|---|---|
| .NET Framework 3.5 | "Minimum .NET Framework version for Configuration Manager site server" |
| RDC feature | "Microsoft Remote Differential Compression (RDC) library registered" |
| ODBC Driver 18 | Setup connects to SQL and fails |
| VC++ Redistributable x64+x86 | ODBC/Setup dependency |

On air-gapped servers, .NET 3.5 requires the Windows Server ISO:
```powershell
# From Hyper-V host:
Add-VMDvdDrive -VMName YOURVM -Path 'C:\path\to\WindowsServer.iso'
# On the VM:
dism /online /enable-feature /featurename:NetFx3 /all /source:D:\sources\sxs /norestart
```

### AdminConsole Module Path Change in 2509

SCCM 2509 moved `ConfigurationManager.psd1` into a subdirectory:
- **2509+**: `AdminConsole\bin\ConfigurationManager\ConfigurationManager.psd1`
- **Pre-2509**: `AdminConsole\bin\ConfigurationManager.psd1`

Fix in `ConfigMgrCBDsc.ResourceHelper.psm1` (`Import-ConfigMgrPowerShellModule`
and `Set-ConfigMgrCert`):
```powershell
$adminBinPath = Split-Path $ENV:SMS_ADMIN_UI_PATH
$modulePath = Join-Path $adminBinPath 'ConfigurationManager\ConfigurationManager.psd1'
if (-not (Test-Path -Path $modulePath)) {
    $modulePath = Join-Path $adminBinPath 'ConfigurationManager.psd1'
}
Import-Module -Name $modulePath -Global
```

### SQL Server Requirements

SCCM setup connects to SQL using the `SVCACC_SCCM` service account credentials.
The SQL server MUST be in the **same domain** as the SCCM server to avoid Kerberos
double-hop authentication failures.

---

## UpdateServicesDsc Module Bugs

### Products/Classifications Wildcard Comparison

**Bug**: When `Products = '*'` or `Classifications = '*'`, `Test-TargetResource` does a
literal `Compare-Object` against the wildcard string, always returning false.

**Fix** in `MSFT_UpdateServicesServer.psm1`:
```powershell
# Replace literal comparison:
if ($null -ne (Compare-Object ... ($Products | Sort-Object -Unique) ...))

# With wildcard check:
if ($Products -ne '*') {
    if ($null -ne (Compare-Object ... ($Products | Sort-Object -Unique) ...))
}
```

### Null ErrorRecord in Post-Set Validation

**Bug**: After `Set-TargetResource` runs, the post-set `Test-TargetResource` validation
calls `New-InvalidResultException -ErrorRecord $_` where `$_` is null (outside catch block).

**Fix**: Remove `-ErrorRecord $_` from the call.

---

## Datum/DscWorkshop Patterns for MECM

### Tiny Scenario Override (MostSpecific Merge)

Datum's default merge strategy is `MostSpecific`. Tiny scenario overrides
(e.g., `TinyMecmSiteServer.yml`) must contain the **COMPLETE section**, not just
the changed fields:

```yaml
# TinyMecmSiteServer.yml - MUST include ALL fields from MecmSiteServer.yml's
# ConfigurationManagerDeployment section, changing only SqlServerName:
ConfigurationManagerDeployment:
  DependsOn:
    - "[Disks]Disks"
  SiteName: HaFIS
  SiteCode: S00
  DomainCredential: "[x=...]"
  SccmInstallAccount: "[x=...]"
  SqlServerName: '[x={$sqlNode = ...CM domain lookup...}=]'  # Changed field
  DatabaseInstance: ''      # Empty for default SQL instance
  ConfigMgrVersion: 2509
  # ... all other fields must be repeated ...
```

### YAML Null vs Empty String

```yaml
# Does NOT override existing values (Datum treats as "not set"):
DatabaseInstance: null

# Correctly overrides to empty string:
DatabaseInstance: ''
```

### Cross-Domain SQL Access

When the SQL server is in a different domain than the SCCM server, Kerberos
double-hop authentication fails in PSRemoting sessions. Solutions:

1. **Best**: Use a SQL server in the same domain (add CM-domain SQL node to Tiny scenario)
2. **Alternative**: Configure Kerberos constrained delegation
3. **Workaround**: Add computer account to SQL sysadmin and run as SYSTEM

---

## AutomatedLab Operational Notes

### Invoke-LabCommand

- No `-Timeout` parameter exists — use `-AsJob` for long operations
- After `Build.ps1` runs, PSModulePath changes — reimport AutomatedLab with:
  ```powershell
  $env:PSModulePath = [Environment]::GetEnvironmentVariable('PSModulePath','Machine') + ';' +
      [Environment]::GetEnvironmentVariable('PSModulePath','User')
  Import-Module AutomatedLab -Force
  Import-Lab -Name YourLab -NoValidation
  ```

### Polling Loops

- Keep max 10 iterations with 30-60s intervals
- NEVER use `while ($state -eq 3)` — state value `3` means `Ready`, creating infinite loops
- Always include a terminal condition: `if ($state -ne 'Running') { break }`

---

## SCCM 2509 Prerequisites (No Internet on Target)

### Required Software on Share (`\\DSCServer\SoftwarePackages\`)

| Path | Files | Download |
|------|-------|----------|
| `Miscellaneous\` | `vc_redist.x64.exe` | https://aka.ms/vs/17/release/vc_redist.x64.exe |
| `Miscellaneous\` | `vc_redist.x86.exe` | https://aka.ms/vs/17/release/vc_redist.x86.exe |
| `Miscellaneous\` | `msodbcsql18.msi` | https://go.microsoft.com/fwlink/?linkid=2299909 |
| `Miscellaneous\` | `sqlncli.msi` | SQL Server Native Client 11 |
| `Miscellaneous\` | `MicrosoftDeploymentToolkit_x64.msi` | MDT |
| `ADKOffline\` | ADK 24H2 offline layout | `adksetup.exe /layout` |
| `ADKPEOffline\` | WinPE 24H2 offline layout | `adkwinpesetup.exe /layout` |
| `MecmBinaries\2509\` | SCCM 2509 media | Extract ISO |
| `MecmBinaries\2509\SCCMPreReqs\` | `setupdl.exe` output | Run from internet-connected machine |

---

## Post-Install DSC Gotchas

### SMS_ADMIN_UI_PATH Null Under PsDscRunAsCredential

ConfigMgrCBDsc resources use `$ENV:SMS_ADMIN_UI_PATH` to locate the CM PowerShell module.
When DSC runs under `PsDscRunAsCredential`, this env var is **null** because the credential
creates a remote runspace where machine-level env vars aren't loaded.

**Symptom**: `Cannot bind argument to parameter 'Path' because it is null` followed by
`Failure to import SCCM Cmdlets` on any ConfigMgrCBDsc resource (CMDistributionGroup,
CMAdministrativeUser, etc.)

**Fix** in `ConfigMgrCBDsc.ResourceHelper.psm1` (`Import-ConfigMgrPowerShellModule`
and `Set-ConfigMgrCert`):
```powershell
$smsPath = $ENV:SMS_ADMIN_UI_PATH
if (-not $smsPath) {
    $smsPath = [Environment]::GetEnvironmentVariable('SMS_ADMIN_UI_PATH', 'Machine')
}
if (-not $smsPath) {
    $smsPath = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\SMS\Setup' `
        -Name 'UI Installation Directory' -EA SilentlyContinue).'UI Installation Directory'
    if ($smsPath) { $smsPath = Join-Path $smsPath 'bin\i386' }
}
$adminBinPath = Split-Path $smsPath
```

### Registry Force Parameter for Existing Values

SCCM creates registry values during install. If DSC tries to set a value that already
exists with a different type, `xRegistry` fails with "already has a value...specify
the Force parameter as $true."

**Fix**: Add `Force: true` in YAML config:
```yaml
RegistryValues:
  Values:
    - Key: HKEY_LOCAL_MACHINE\Software\Microsoft\SMS\Components\SMS_Inventory_Data_Loader
      ValueName: Max MIF Size
      ValueData: 500000000
      ValueType: Dword
      Force: true    # Required — SCCM pre-creates this value
```

### CM Admin Console Access (SiteAdmins)

To grant console access, add users to `SiteAdmins` in `ConfigurationManagerConfiguration`:
```yaml
ConfigurationManagerConfiguration:
  SiteAdmins:
    - AdminName: 'DOMAIN\AdminGroup'
      RolesToInclude: Full Administrator
      ScopesToInclude: All
    - AdminName: 'DOMAIN\admInst'
      RolesToInclude: Full Administrator
      ScopesToInclude: All
```

**Datum caveat**: Adding a `ConfigurationManagerConfiguration` section to a Tiny scenario
override replaces the ENTIRE parent section (MostSpecific merge), losing required parameters
like `SccmInstallAccount`, `SiteCode`, `SiteServerFqdn`. Add entries to the **parent** role
file instead, or duplicate ALL required fields in the override.

### New-CMAdministrativeUser Fails in Remote Sessions

`New-CMAdministrativeUser` returns "No object corresponds to the specified parameters"
when called via `Invoke-Command` or `Invoke-LabCommand`. The CM cmdlets require a local
process context.

**Workaround**: Run via scheduled task:
```powershell
$script = @'
Import-Module "$($ENV:SMS_ADMIN_UI_PATH)\..\ConfigurationManager\ConfigurationManager.psd1"
Set-Location S00:
New-CMAdministrativeUser -Name 'DOMAIN\user' -RoleName 'Full Administrator' -SecurityScopeName 'All'
'@
Set-Content 'C:\Temp\add_admin.ps1' $script
$a = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument '-NoProfile -ExecutionPolicy Bypass -File C:\Temp\add_admin.ps1'
$p = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType Interactive -RunLevel Highest
Register-ScheduledTask -TaskName 'AddAdmin' -Action $a -Principal $p | Out-Null
Start-ScheduledTask -TaskName 'AddAdmin'
```

### setupdl.exe Requires ODBC 18

`setupdl.exe` for SCCM 2509 requires Microsoft ODBC Driver 18 installed on the machine
where it runs. Install ODBC 18 (+ VC++ Redist) on the machine with internet first, then
run `setupdl.exe <targetDir>`.

### MSI License Acceptance Property Names

```
ODBC 18:   IACCEPTMSODBCSQLLICENSETERMS=YES   (NOT IACCEPTMSODBC18LICENSETERMS)
SQLNCLI:   IACCEPTSQLNCLILICENSETERMS=YES
```

---

## SCCM 2509 DSC Resource Compatibility

### EnableSynchronization Removed

`Set-CMSoftwareUpdatePointComponent` in SCCM 2509 removed `EnableSynchronization`.
Sync behavior is now controlled solely via `SynchronizeAction`.

**Backward-compatible fix** in `DSC_CMSoftwareUpdatePointComponent.psm1`:
```powershell
$cmdInfo = Get-Command Set-CMSoftwareUpdatePointComponent -ErrorAction SilentlyContinue
$supportsEnableSync = $cmdInfo -and $cmdInfo.Parameters.ContainsKey('EnableSynchronization')
if ($supportsEnableSync) {
    $evalList += 'EnableSynchronization'
} elseif ($PSBoundParameters.ContainsKey('EnableSynchronization')) {
    # Map to SynchronizeAction for 2509+
    if ($PSBoundParameters['EnableSynchronization'] -eq $true) {
        $PSBoundParameters['SynchronizeAction'] = 'SynchronizeFromMicrosoftUpdate'
    } else {
        $PSBoundParameters['SynchronizeAction'] = 'DoNotSynchronizeFromMicrosoftUpdateOrUpstreamDataSource'
    }
}
```

### Site Server FQDN Required

SCCM registers servers by FQDN. DSC resources using `$node.NodeName` (short name) fail
with "Not found" when calling `Add-CMManagementPoint`, `Add-CMSoftwareUpdatePoint`.

**Fix**: Add `SiteServerFqdn` parameter to `ConfigurationManagerConfiguration` composite:
```yaml
SiteServerFqdn: '[x={"$($Node.NodeName).$($Datum.Environment.$($Node.Environment).Credentials.$($Node.ServiceTag).DomainFqdn)"}=]'
```

### PsDscRunAsCredential vs SYSTEM for ALL ConfigMgrCBDsc Resources

- `PsDscRunAsCredential` creates a remote PowerShell runspace even for local LCM execution
- In this remote runspace, `Import-ConfigMgrPowerShellModule` fails because:
  - `$ENV:SMS_ADMIN_UI_PATH` is null (env vars not inherited)
  - The WMI query for `SMS_Site` returns null (WMI permissions differ)
  - The `S00:` PSDrive is never created
- **Symptom**: `Cannot find drive S00`, `You cannot call a method on a null-valued expression`,
  `Failure to import SCCM Cmdlets` — on ALL ConfigMgrCBDsc resources
- **Fix**: Remove `PsDscRunAsCredential` from ALL resources in the
  `ConfigurationManagerConfiguration` composite — SYSTEM has direct SMS Provider access
  and the ConfigurationManager module auto-discovers the site correctly under SYSTEM
- This applies to: CMForestDiscovery, CMSystemDiscovery, CMNetworkDiscovery,
  CMHeartbeatDiscovery, CMUserDiscovery, CMClientStatusSettings, CMSiteMaintenance,
  CMBoundaries, CMBoundaryGroups, CMAdministrativeUser, CMCollectionMembershipEvaluationComponent,
  CMStatusReportingComponent, CMManagementPoint, CMSoftwareUpdatePoint,
  CMSoftwareUpdatePointComponent, CMDistributionGroup, CMDistributionPoint, CMAccounts

### WSUS DSC Resource (UpdateServicesDsc)

After SCCM installation, WSUS runs on port 8530 (managed by SCCM). `Get-WsusServer`
defaults to port 80, causing `UpdateServicesServer` DSC resource to always fail.

**Fix**: Replace `UpdateServicesServer` with a `Script` resource that checks
`HKLM:\SOFTWARE\Microsoft\Update Services\Server\Setup\ContentDir` and runs
`WsusUtil.exe postinstall` only if needed.

---

## SQL Server Setup for SCCM

### Required SQL Logins

```yaml
# In Roles/cm/TinyHaSqlServerFirstNode.yml (ServiceTag=CM):
SqlLogins:
  Values:
    - Name: 'DOMAIN\SVCACC_SCCM'
      LoginType: WindowsUser
      InstanceName: MSSQLSERVER
    - Name: 'DOMAIN\MECMSERVER$'    # Machine account
      LoginType: WindowsUser
      InstanceName: MSSQLSERVER

SqlRoles:
  Values:
    - ServerRoleName: sysadmin
      MembersToInclude:
        - 'DOMAIN\SVCACC_SCCM'
        - 'DOMAIN\MECMSERVER$'
      InstanceName: MSSQLSERVER
```

Note: The file must be in the correct ServiceTag subfolder under `source/Roles/`.
VCMSQL001 has ServiceTag=CM → file goes in `Roles/cm/`, not `Roles/pf/`.

### SCCM Admin Account Setup

CM PowerShell cmdlets return empty from PSRemoting. Use scheduled task:

```powershell
# Create script, register as scheduled task with SYSTEM + Interactive logon
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-File C:\script.ps1'
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType Interactive -RunLevel Highest
Register-ScheduledTask -TaskName 'TaskName' -Action $action -Principal $principal
Start-ScheduledTask -TaskName 'TaskName'
```

### WSUS on Target Nodes

WSUS requires IIS (W3SVC) to be running. Set it to auto-start:
```powershell
Set-Service W3SVC -StartupType Automatic
Start-Service W3SVC
```

---

## DSC Auto-Correct Interference During Long Installs (2026-03-31)

When the LCM is in `Pull/ApplyAndAutoCorrect` mode, the consistency timer runs every
15-30 minutes. SCCM installation takes 45-75 minutes. During this time:

1. The timer fires, runs `TestScript` on `[Script]SCCM`, finds `root\sms` missing
2. Runs `SetScript`, which kills existing setup processes, removes SMS registry, and
   starts a NEW install — **destroying the in-progress installation**
3. This creates a loop where each install is killed ~15 minutes in

**Symptoms**: Setup log shows progress, then disappears. Processes vanish mid-install.
Configs never reach completion. No errors in DSC log — just a new consistency run.

**Root cause**: The `SetScript` is designed to clean up prior failures before retrying,
but it cannot distinguish between a failed prior install and an actively running one.

**Fix in xSccmInstall resource**: The `SetScript` must detect a running installation
before cleaning up. Check for running `SetupWpf.exe` process and skip cleanup:
```powershell
# At the top of SetScript, before any cleanup:
$runningSetup = Get-Process -Name SetupWpf, setupwpf -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -like '*SCCMSetup*' -or $_.Path -like '*SMSSETUP*' }
if ($runningSetup) {
    Write-Verbose "SetupWpf.exe is already running (PID: $($runningSetup.Id -join ', ')). Waiting for completion instead of starting a new install."
    # Skip to the WaitForSetupWpf section
}
```

**Manual workaround**: Temporarily disable the LCM before running a long install:
```powershell
[DSCLocalConfigurationManager()]
Configuration DisableLCM {
    Settings {
        ConfigurationMode = 'ApplyOnly'
        RefreshMode = 'Disabled'
    }
}
DisableLCM -OutputPath C:\Temp\LCMDisable | Out-Null
Set-DscLocalConfigurationManager -Path C:\Temp\LCMDisable -Force
```
After install completes, re-apply the original MetaMOF.

---

## File Copy Double-Hop on Server 2025 (2026-03-31)

When the DSC `SetScript` runs under `PsDscRunAsCredential`, `robocopy` from a UNC
path (e.g., `\\DSCServer\share`) may hang indefinitely on Server 2025. This is the
same `ShellExecuteEx` UNC security zone check issue affecting `Start-Process`.

Additionally, even with CredSSP configured, `Test-Path` on remote shares can hang
because the PsDscRunAsCredential runspace does not inherit CredSSP delegation.

**Symptoms**: `robocopy` hangs, `Test-Path \\server\share` hangs, setup copies
stall after 0 files with the share showing as inaccessible.

**Fix**: Push files FROM the source server instead of pulling from the target:
```powershell
# From the file server (VCMDSC001):
robocopy 'D:\SoftwarePackages\MecmBinaries\2509\SMSSETUP' `
    '\\VCMSWD010.domain\C$\Temp\SCCMSetup\SMSSETUP' /E /NP /NFL /NDL
```

**Alternative fix in DSC resource**: Use `net use` to map the drive with explicit
credentials before copying, or verify the path is accessible before attempting
`robocopy` and throw a clear error if not:
```powershell
$maxRetry = 3
for ($r = 0; $r -lt $maxRetry; $r++) {
    if (Test-Path $setupDir -ErrorAction SilentlyContinue) { break }
    Write-Verbose "Source path not accessible (attempt $($r+1)/$maxRetry): $setupDir"
    Start-Sleep -Seconds 10
}
if (-not (Test-Path $setupDir -ErrorAction SilentlyContinue)) {
    throw "Source UNC path is not accessible: $setupDir. Check network, DNS, and credential delegation."
}
```

---

## Stale CM Database Blocking Installation (2026-03-31)

When a prior SCCM install created the `CM_S00` database but failed midway through,
the database contains user-defined objects (tables, views, stored procs).

**Error**: `ERROR: SQL Server Database has user defined objects, cannot configure database.`
followed by `Setup has encountered fatal errors during database initialization.`

Setup exits with code 0 (the bootstrapper considers the exit successful) but SCCM is
not installed. The WMI namespace `root\sms` is never created.

**The DSC resource reports success** because setup.exe returned 0 and the resource
did not validate the actual installation result.

**Fix**: Always clean the SQL database externally before retrying. Cannot be done
from the DSC resource due to Kerberos double-hop:
```powershell
# On the SQL server:
IF EXISTS (SELECT name FROM sys.databases WHERE name = 'CM_S00')
BEGIN
    ALTER DATABASE [CM_S00] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [CM_S00];
END
```

**Also clean SMS on both servers** (site server AND SQL server — per Self-Referential
Prereq Check Bug section above).

**Prevention**: The DSC resource should validate `root\sms` WMI namespace after
setup exits and throw if missing, so DSC correctly reports failure instead of
silently continuing.
