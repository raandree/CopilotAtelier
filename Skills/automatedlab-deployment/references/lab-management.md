# Lab Management

Extracted from `Skills/automatedlab-deployment/SKILL.md` to keep the main skill body under Anthropic's 500-line budget.

## Contents

- Apply a DSC configuration to lab VMs
- Test if a VM has internet connectivity
- Test if Active Directory is ready
- Test host remoting configuration
- Test host internet connectivity
- Join a VM to a domain
- Force AD replication
- Create AD forest/domain trusts
- Manage firewall rule groups on VMs
- Assign user rights
- Manage UAC status
- Manage auto-logon
- Enable certificate auto-enrollment
- Request a certificate from the lab CA
- Get the issuing CA
- Create a CA template
- Add additional disks to a machine definition
- Mount/Dismount ISO images on lab VMs
- Offline-patch an ISO image
- Set a default OS for all machines
- Set a global name prefix
- Check available Hyper-V memory
- Connect / disconnect labs (VPN between Azure & Hyper-V labs)
- Enable internal routing between lab networks
- Clear the AL cache
- Unblock downloaded LabSources files
- Undo host remoting changes
- Update base images with latest patches
- Update SysInternals tools in LabSources
- Reset AutomatedLab to defaults
- Send a notification
- Useful Sample Scripts on Disk

### Apply a DSC configuration to lab VMs

```powershell
Invoke-LabDscConfiguration -ComputerName 'FS1' -Configuration (Get-Content .\Config.ps1 -Raw)
```

## Testing & Validation

### Test if a VM has internet connectivity

```powershell
Test-LabMachineInternetConnectivity -ComputerName 'RTR1'
```

### Test if Active Directory is ready

```powershell
# Returns $true/$false (non-blocking, unlike Wait-LabADReady)
Test-LabADReady -ComputerName 'DC1'
```

### Test host remoting configuration

```powershell
# Verifies the lab host is configured for CredSSP remoting
Test-LabHostRemoting
```

### Test host internet connectivity

```powershell
Test-LabHostConnected
```

## Domain Operations

### Join a VM to a domain

```powershell
Join-LabVMDomain -ComputerName 'FS1' -DomainName 'contoso.com'
```

### Force AD replication

```powershell
Sync-LabActiveDirectory -ComputerName 'DC1'
```

### Create AD forest/domain trusts

```powershell
# After deploying two forests, create a trust between them
Install-LabADDSTrust
```

## Security & Firewall

### Manage firewall rule groups on VMs

```powershell
# Enable a firewall rule group (e.g., File and Printer Sharing)
Enable-LabVMFirewallGroup -ComputerName 'FS1' -FirewallGroup 'File and Printer Sharing'

# Disable a firewall rule group
Disable-LabVMFirewallGroup -ComputerName 'FS1' -FirewallGroup 'File and Printer Sharing'
```

### Assign user rights

```powershell
Add-LabVMUserRight -ComputerName 'DC1' -UserName 'contoso\SvcAccount' `
    -Privilege 'SeServiceLogonRight'
```

### Manage UAC status

```powershell
Get-LabVMUacStatus -ComputerName 'DC1'
Set-LabVMUacStatus -ComputerName 'DC1' -EnableLUA $false   # Disable UAC
```

### Manage auto-logon

```powershell
Enable-LabAutoLogon -ComputerName 'DC1'
Disable-LabAutoLogon -ComputerName 'DC1'
```

## PKI / Certificates

### Enable certificate auto-enrollment

```powershell
Enable-LabCertificateAutoenrollment -Computer -User
```

### Request a certificate from the lab CA

```powershell
Request-LabCertificate -Subject 'CN=web.contoso.com' -SAN 'web.contoso.com', 'www.contoso.com' `
    -TemplateName 'WebServer' -ComputerName 'WEB1'
```

### Get the issuing CA

```powershell
Get-LabIssuingCA   # returns the issuing CA machine in the lab
```

### Create a CA template

```powershell
New-LabCATemplate -TemplateName 'CustomWebServer' -DisplayName 'Custom Web Server' `
    -SourceTemplateName 'WebServer' -ApplicationPolicy 'Server Authentication' `
    -ComputerName (Get-LabIssuingCA)
```

## Disk & ISO Management

### Add additional disks to a machine definition

```powershell
Add-LabDiskDefinition -Name 'DataDisk1' -DiskSizeInGb 100
Add-LabMachineDefinition -Name 'FS1' -DiskName 'DataDisk1' ...
```

### Mount/Dismount ISO images on lab VMs

```powershell
Mount-LabIsoImage -ComputerName 'FS1' -IsoPath "$labSources\ISOs\en_sql_server_2022.iso"
Dismount-LabIsoImage -ComputerName 'FS1'
```

### Offline-patch an ISO image

```powershell
# Integrate Windows Updates into an existing ISO — creates a patched copy
Update-LabIsoImage -SourceIsoImagePath "$labSources\ISOs\WS2025.iso" `
    -PatchFolder "$labSources\OSUpdates" `
    -TargetIsoImagePath "$labSources\ISOs\WS2025_Patched.iso"
```

## Lab Configuration

### Set a default OS for all machines

```powershell
# Avoids repeating -OperatingSystem on every Add-LabMachineDefinition
Set-LabDefaultOperatingSystem -OperatingSystem 'Windows Server 2025 Standard (Desktop Experience)'
```

### Set a global name prefix

```powershell
# Prefixes all VM names — useful to avoid collisions when running parallel labs
Set-LabGlobalNamePrefix -Name 'T1'
# VM named 'DC1' becomes 'T1DC1'
```

### Check available Hyper-V memory

```powershell
Get-LabHyperVAvailableMemory   # returns available MB on the Hyper-V host
```

### Connect / disconnect labs (VPN between Azure & Hyper-V labs)

```powershell
# Create an S2S VPN between two labs (one Azure, one Hyper-V)
Connect-Lab -SourceLab 'HyperVLab' -DestinationLab 'AzureLab'

# Tear down the VPN
Disconnect-Lab -SourceLab 'HyperVLab' -DestinationLab 'AzureLab'
```

### Enable internal routing between lab networks

```powershell
# Sets up routing between multiple internal lab networks (no Routing role needed)
Enable-LabInternalRouting
```

## Maintenance & Cleanup

### Clear the AL cache

```powershell
Clear-LabCache
```

### Unblock downloaded LabSources files

```powershell
# Removes the NTFS "blocked" mark from all files in LabSources
Unblock-LabSources
```

### Undo host remoting changes

```powershell
# Reverses the changes made by Enable-LabHostRemoting
Undo-LabHostRemoting
```

### Update base images with latest patches

```powershell
Update-LabBaseImage
```

### Update SysInternals tools in LabSources

```powershell
Update-LabSysinternalsTools
```

### Reset AutomatedLab to defaults

```powershell
Reset-AutomatedLab
```

### Send a notification

```powershell
# Sends notifications (Toast, Ifttt, Mail, etc.) — configure providers first
Send-ALNotification -Activity 'Lab Deployed' -Message 'CorpLab deployment complete'
```

## Pre/Post Installation Activities

```powershell
# Define a post-installation activity (runs on VM after OS install)
$postInstall = Get-LabPostInstallationActivity -ScriptFileName 'C:\Scripts\PostSetup.ps1'
Add-LabMachineDefinition -Name 'FS1' -PostInstallationActivity $postInstall ...

# Define a custom installation activity
$activity = Get-LabInstallationActivity -ScriptFileName 'C:\Scripts\Install.ps1'
Add-LabMachineDefinition -Name 'FS1' -InstallationActivity $activity ...
```

## Base Image Caching

AL creates base VHDX images in the VM storage path (e.g.,
`D:\AutomatedLab-VMs\BASE_*.vhdx`). These images:

- Are **not deleted** when a lab is removed — they persist across labs.
- Are **reused** by any future lab that needs the same OS edition and version.
- Dramatically speed up subsequent deployments (minutes instead of 10+ min per image).

To reclaim disk space, delete the `BASE_*.vhdx` files manually.

## Lab Data & Paths

| Item | Default Path |
|---|---|
| Lab definition XML files | `C:\ProgramData\AutomatedLab\Labs\<LabName>\` |
| VM disks & base images | `D:\AutomatedLab-VMs\` (or configured path) |
| LabSources (ISOs, tools, scripts) | Resolved via `Get-LabSourcesLocation` |
| Sample scripts (installed with AL) | `<LabSources>\SampleScripts\` |
| Switch deployment lock file | Retrieved via `Get-LabConfigurationItem -Name SwitchDeploymentInProgressPath` |

### Useful Sample Scripts on Disk

After installing AL, sample scripts are at `<LabSources>\SampleScripts\`:

| Script | Pattern |
|---|---|
| `Introduction\05 Single domain-joined server (internet facing).ps1` | Minimal internet lab |
| `Workshops\PowerShell Lab - HyperV with Internet.ps1` | Full lab with DCs + FileServer + Routing |
| `Scenarios\InternalRouting.ps1` | Multi-network internal routing |

## Lab Lifecycle

```powershell
# List all labs
Get-Lab -List

# Import an existing lab (required after closing PowerShell)
# Use -NoValidation to avoid the validator bug in AL 5.x (see Troubleshooting)
Import-Lab -Name 'CorpLab' -NoValidation

# Start / Stop VMs
Start-LabVM -All
Stop-LabVM -All

# Remove the entire lab (VMs, disks, switches — base images are kept)
Remove-Lab -Name 'CorpLab' -Confirm:$false
```

