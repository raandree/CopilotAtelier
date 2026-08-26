# Cmdlet Quick Reference

Extracted from `Skills/automatedlab-deployment/SKILL.md` to keep the main skill body under Anthropic's 500-line budget.

## Contents

- Lab Definition
- Deployment
- Lab Lifecycle
- VM Operations
- Snapshots
- Remote Execution & Sessions
- Software & Features
- File Transfer & Downloads
- Networking & Domain
- Security & Firewall
- PKI / Certificates
- DSC
- Testing
- Maintenance

Commonly used cmdlets grouped by category. Internal worker cmdlets
(`*-LW*`) are omitted — use the `*-Lab*` public surface.

### Lab Definition

| Cmdlet | Description |
|---|---|
| `New-LabDefinition` | Start a new lab definition |
| `Add-LabDomainDefinition` | Add a domain to the lab |
| `Add-LabVirtualNetworkDefinition` | Add a virtual network |
| `Add-LabMachineDefinition` | Add a VM to the lab |
| `Add-LabDiskDefinition` | Add an extra disk to a VM |
| `Add-LabIsoImageDefinition` | Register an ISO for a role |
| `New-LabNetworkAdapterDefinition` | Create multi-NIC definitions |
| `Get-LabMachineRoleDefinition` | Create role definitions with properties |
| `Set-LabInstallationCredential` | Set default credentials |
| `Set-LabDefaultOperatingSystem` | Set default OS for all VMs |
| `Set-LabGlobalNamePrefix` | Prefix all VM names |
| `Get-LabInstallationActivity` | Define custom install activities |
| `Get-LabPostInstallationActivity` | Define post-install activities |

### Deployment

| Cmdlet | Description |
|---|---|
| `Install-Lab` | Deploy the lab (use `-NoValidation`) |
| `Show-LabDeploymentSummary` | Display deployment results |

### Lab Lifecycle

| Cmdlet | Description |
|---|---|
| `Get-Lab` | Get current lab / list labs (`-List`) |
| `Import-Lab` | Re-import a lab in a new session |
| `Export-Lab` | Export lab definition |
| `Remove-Lab` | Destroy the entire lab |
| `Clear-Lab` | Clear the in-memory lab definition |

### VM Operations

| Cmdlet | Description |
|---|---|
| `Get-LabVM` | Get VM objects (by name, role, or all) |
| `Get-LabVMStatus` | Get power state of VMs |
| `Get-LabVMUptime` | Get VM uptime |
| `Start-LabVM` | Start VMs |
| `Stop-LabVM` | Stop VMs |
| `Restart-LabVM` | Restart VMs |
| `Save-LabVM` | Hibernate VMs |
| `Remove-LabVM` | Remove individual VMs |
| `Connect-LabVM` | Open VM console |
| `Wait-LabVM` | Wait for VM to accept remoting |
| `Wait-LabVMRestart` | Wait for VM to restart |
| `Wait-LabVMShutdown` | Wait for VM to shut down |

### Snapshots

| Cmdlet | Description |
|---|---|
| `Checkpoint-LabVM` | Create a snapshot |
| `Get-LabVMSnapshot` | List snapshots |
| `Restore-LabVMSnapshot` | Restore a snapshot |
| `Remove-LabVMSnapshot` | Delete a snapshot |

### Remote Execution & Sessions

| Cmdlet | Description |
|---|---|
| `Invoke-LabCommand` | Run script blocks on VMs |
| `Enter-LabPSSession` | Enter interactive remote session |
| `New-LabPSSession` | Create a PSSession |
| `Get-LabPSSession` | Get existing PSSessions |
| `Remove-LabPSSession` | Remove PSSessions |
| `New-LabCimSession` | Create a CIM session |
| `Get-LabCimSession` | Get existing CIM sessions |
| `Remove-LabCimSession` | Remove CIM sessions |

### Software & Features

| Cmdlet | Description |
|---|---|
| `Install-LabWindowsFeature` | Install Windows features |
| `Uninstall-LabWindowsFeature` | Remove Windows features |
| `Get-LabWindowsFeature` | List installed features |
| `Get-LabSoftwarePackage` | Create a software package object |
| `Install-LabSoftwarePackage` | Install software on VMs |
| `Install-LabSoftwarePackages` | Install multiple packages |

### File Transfer & Downloads

| Cmdlet | Description |
|---|---|
| `Copy-LabFileItem` | Copy files to VMs |
| `Get-LabInternetFile` | Download a file from the internet |

### Networking & Domain

| Cmdlet | Description |
|---|---|
| `Join-LabVMDomain` | Join a VM to a domain |
| `Sync-LabActiveDirectory` | Force AD replication |
| `Install-LabADDSTrust` | Create inter-forest trusts |
| `Wait-LabADReady` | Wait for AD to be ready |
| `Test-LabADReady` | Test if AD is ready |
| `Enable-LabInternalRouting` | Route between lab networks |

### Security & Firewall

| Cmdlet | Description |
|---|---|
| `Enable-LabVMFirewallGroup` | Enable firewall rule group |
| `Disable-LabVMFirewallGroup` | Disable firewall rule group |
| `Add-LabVMUserRight` | Assign user rights |
| `Get-LabVMUacStatus` | Get UAC status |
| `Set-LabVMUacStatus` | Set UAC status |
| `Enable-LabAutoLogon` | Enable auto-logon |
| `Disable-LabAutoLogon` | Disable auto-logon |

### PKI / Certificates

| Cmdlet | Description |
|---|---|
| `Get-LabIssuingCA` | Get the issuing CA in the lab |
| `Enable-LabCertificateAutoenrollment` | Enable cert auto-enrollment |
| `Request-LabCertificate` | Request a certificate from the CA |
| `New-LabCATemplate` | Create a CA certificate template |
| `Test-LabCATemplate` | Test if a CA template exists |

### DSC

| Cmdlet | Description |
|---|---|
| `Invoke-LabDscConfiguration` | Apply DSC configuration |

### Testing

| Cmdlet | Description |
|---|---|
| `Test-LabMachineInternetConnectivity` | Test VM internet access |
| `Test-LabHostRemoting` | Verify host remoting setup |
| `Test-LabHostConnected` | Verify host internet |

### Maintenance

| Cmdlet | Description |
|---|---|
| `Clear-LabCache` | Clear AL cache |
| `Unblock-LabSources` | Unblock downloaded files |
| `Update-LabBaseImage` | Patch base VHDX images |
| `Update-LabIsoImage` | Offline-patch ISO images |
| `Update-LabSysinternalsTools` | Update SysInternals tools |
| `Enable-LabHostRemoting` | Enable CredSSP on host |
| `Undo-LabHostRemoting` | Reverse host remoting changes |
| `Reset-AutomatedLab` | Reset AL to defaults |
| `Send-ALNotification` | Send deployment notifications |

