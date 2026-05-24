---
name: automatedlab-deployment
description: >-
  Build and manage Hyper-V lab environments with AutomatedLab (AL): installation, lab definitions, roles (AD, File Server, Routing, PKI, SQL), networking (incl. NAT), post-deploy configuration, VM status, snapshots, file transfer, DSC, certificates, firewall, and teardown. USE FOR: AutomatedLab, Hyper-V lab, deploy/create lab, domain controller, lab VMs, ISO images, LabSources, Install-Lab, New-LabDefinition, Add-LabMachineDefinition, Remove-Lab, Get-LabVM*, Wait-LabVM, Wait-LabADReady, Restart-LabVM, Save-LabVM, Copy-LabFileItem, Get-LabInternetFile, Invoke-LabDscConfiguration, Test-LabMachineInternetConnectivity, Join-LabVMDomain, Enable/Disable-LabVMFirewallGroup, Add-LabVMUserRight, Request-LabCertificate, Mount-LabIsoImage, Connect-Lab, Enable-LabInternalRouting, Add-LabVirtualNetworkDefinition -UseNat, NetNat, HyperVUseNAT, CredSSP double-hop, Enable-LabHostRemoting. DO NOT USE FOR: Azure VM deployment, production infrastructure, non-Hyper-V virtualisation.
---

# AutomatedLab — Hyper-V Lab Deployment

Skill for creating, configuring, and managing local Hyper-V lab environments
using [AutomatedLab](https://automatedlab.org).

## When to Use

- Creating a new Hyper-V lab with domain controllers, member servers, or clients
- Adding roles (AD, File Server, Routing, PKI, SQL, Exchange, etc.)
- Configuring lab networking, internet connectivity, or multi-site topologies
- Post-deployment tasks (shares, software installation, DSC)
- Troubleshooting lab deployment issues
- Tearing down and recreating labs

## Pre-flight Checks

AutomatedLab requires **local administrator** privileges. Every generated
deployment script **must** verify admin rights before calling any AL cmdlet.

### Admin-rights guard (mandatory in every script)

```powershell
$currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]$currentIdentity
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'This script must run in an elevated (Run as Administrator) PowerShell session.'
}
```

Place this as the **first executable statement** in the script, before
`New-LabDefinition` or any other AL call. Using `#Requires -RunAsAdministrator`
is also acceptable but the runtime check above gives a clearer error message
when invoked from non-interactive contexts (e.g., CI/CD pipelines, VS Code
terminals).

## Installation

```powershell
# Install the module from PSGallery (elevated PowerShell required)
Install-PackageProvider -Name Nuget -Force
Install-Module -Name AutomatedLab -SkipPublisherCheck -Force

# One-time host preparation
Enable-LabHostRemoting -Force

# Create the LabSources folder structure (adjust drive letter as needed)
New-LabSourcesFolder -DriveLetter C

# Opt out of telemetry (optional)
[Environment]::SetEnvironmentVariable('AUTOMATEDLAB_TELEMETRY_OPTIN', 'false', 'Machine')
$env:AUTOMATEDLAB_TELEMETRY_OPTIN = 'false'
```

### ISO Images

Place ISO files in `<LabSources>\ISOs\`. The LabSources folder location
varies per installation — always resolve it dynamically:

```powershell
$labSources = Get-LabSourcesLocation   # e.g. C:\LabSources, E:\LabSources, etc.
```

> **Never hardcode `C:\LabSources`**. Use `Get-LabSourcesLocation` in scripts and
> commands so they work on any host regardless of where LabSources was created.

Download evaluation ISOs from:

- [Windows Server 2025](https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2025)
- [Windows Server 2022](https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2022)
- [Windows 11 Enterprise](https://www.microsoft.com/en-us/evalcenter/evaluate-windows-11-enterprise)
- [Windows 10 Enterprise](https://www.microsoft.com/en-us/evalcenter/evaluate-windows-10-enterprise)

Verify detected OS names:

```powershell
Get-LabAvailableOperatingSystem -Path (Get-LabSourcesLocation) | Select-Object OperatingSystemName
```

## VM Storage Path Detection

Before creating a new lab, check if an `AutomatedLab-VMs` folder **already
exists** on any drive. If found, use that location for the new lab's VM
disks. Do **not** create a second `AutomatedLab-VMs` folder on another drive.

```powershell
# Scan all fixed drives for an existing AutomatedLab-VMs folder
$existingVmPath = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType = 3" |
    ForEach-Object {
        $candidate = Join-Path $_.DeviceID 'AutomatedLab-VMs'
        if (Test-Path -Path $candidate) { $candidate }
    } | Select-Object -First 1

if ($existingVmPath) {
    Write-Host "Reusing existing VM path: $existingVmPath"
    New-LabDefinition -Name 'MyLab' -DefaultVirtualizationEngine HyperV `
        -VmPath $existingVmPath
} else {
    # Let AL use its default location
    New-LabDefinition -Name 'MyLab' -DefaultVirtualizationEngine HyperV
}
```

> **Why this matters:** Hyper-V hosts often have a dedicated data disk for
> VM storage. If an operator has already set up `D:\AutomatedLab-VMs` or
> `E:\AutomatedLab-VMs`, creating VMs on a different drive wastes space
> and causes confusion.

## VM Name Collision Avoidance

Before deploying a lab, **check that none of the planned VM names collide
with VMs defined in other existing labs**. AutomatedLab will fail if a VM
with the same name already exists.

This check **must be engine-agnostic** — it must work for Hyper-V, Azure,
and any future engine (e.g. Proxmox). Do **not** use `Get-VM` (Hyper-V
only). Instead, use `Import-Lab` + `Get-LabVM` to query each existing
lab — this works for all engines because AL stores lab metadata locally.

### Pre-flight: detect collisions (mandatory in every deployment script)

```powershell
# List of planned VM names for this lab
$plannedNames = @('CL1', 'CL2')   # ← adjust to match your lab machines

# Collect all machine names from existing AL labs (engine-agnostic)
$existingNames = [System.Collections.Generic.List[string]]::new()
foreach ($lab in (Get-Lab -List)) {
    Import-Lab -Name $lab -NoValidation -ErrorAction SilentlyContinue
    (Get-LabVM).Name | ForEach-Object { $existingNames.Add($_) }
}

$collisions = $plannedNames | Where-Object { $_ -in $existingNames }

if ($collisions) {
    Write-Warning "VM name collision detected: $($collisions -join ', ')"
    Write-Warning 'These names are already used in existing AutomatedLab labs.'

    # Auto-generate a short unique prefix (2 uppercase letters) to avoid collisions
    do {
        $prefix = -join ((65..90) | Get-Random -Count 2 | ForEach-Object { [char]$_ })
        $prefixedNames = $plannedNames | ForEach-Object { "$prefix$_" }
        $stillCollides = $prefixedNames | Where-Object { $_ -in $existingNames }
    } while ($stillCollides)

    Write-Host "Using name prefix '$prefix' to avoid collisions (e.g. $($prefixedNames[0]))"
    Set-LabGlobalNamePrefix -Name $prefix
}
```

> **Why this matters:** Common names like `DC1`, `CL1`, `FS1` are reused
> across labs. If a previous lab was not fully cleaned up, or another lab
> is still running, the deployment will fail with a name collision error.

> **Why not `Get-VM`?** `Get-VM` is a Hyper-V cmdlet. It does not work
> for Azure labs, and will not work for future engines like Proxmox.
> `Import-Lab` + `Get-LabVM` works for **all** engines because AL stores
> lab metadata locally regardless of the virtualisation backend.

> **Note:** `Import-Lab` requires elevation and overwrites the "current
> lab" global state, but deployment scripts already require elevation
> and `New-LabDefinition` (called afterward) resets the lab context.

> The collision check **must** run **before** `New-LabDefinition`.
> `Set-LabGlobalNamePrefix` prepends the prefix to every VM name
> defined afterward.

## Core Workflow

Every AutomatedLab deployment follows this pattern:

```powershell
# 0. Pre-flight — verify local administrator rights
$currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]$currentIdentity
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'This script must run in an elevated (Run as Administrator) PowerShell session.'
}

# 1. Define the lab
New-LabDefinition -Name 'MyLab' -DefaultVirtualizationEngine HyperV

# 2. Set credentials & domain
Set-LabInstallationCredential -Username 'Install' -Password 'Somepass1'
Add-LabDomainDefinition -Name 'contoso.com' -AdminUser 'Install' -AdminPassword 'Somepass1'

# 3. Define network(s)
Add-LabVirtualNetworkDefinition -Name 'LabNet' -AddressSpace '192.168.100.0/24'

# 4. Define machines with roles
Add-LabMachineDefinition -Name 'DC1' -OperatingSystem 'Windows Server 2025 Standard (Desktop Experience)' `
    -Roles RootDC -DomainName 'contoso.com' -Network 'LabNet'

# 5. Deploy (use -NoValidation to bypass known validator bugs — see Troubleshooting)
Install-Lab -NoValidation

# 6. Review
Show-LabDeploymentSummary
```

## Operating System Name Strings

The `-OperatingSystem` parameter must match exactly what AL detects on the ISO.
Common values (may vary by ISO edition):

| OS | Typical String |
|---|---|
| Server 2025 Standard (GUI) | `Windows Server 2025 Standard (Desktop Experience)` |
| Server 2025 Datacenter (GUI) | `Windows Server 2025 Datacenter (Desktop Experience)` |
| Server 2022 Standard (GUI) | `Windows Server 2022 Standard (Desktop Experience)` |
| Server 2022 Datacenter (GUI) | `Windows Server 2022 Datacenter (Desktop Experience)` |
| Windows 11 Enterprise | `Windows 11 Enterprise` |
| Windows 11 Pro | `Windows 11 Pro` |
| Windows 10 Enterprise | `Windows 10 Enterprise` |

> **Consumer vs. Evaluation ISOs**: Windows 11 *consumer* ISOs contain Pro/Home
> editions but **not** Enterprise. If you downloaded a consumer ISO, use
> `'Windows 11 Pro'`. Enterprise requires the separate evaluation or VLSC ISO.

**Always verify** with `Get-LabAvailableOperatingSystem` — edition strings change
between ISOs and evaluation vs. retail media.

## Networking

Virtual network definitions, switch types (External/Internal/Private), NAT setup, ``Enable-LabInternalRouting``, ``Add-LabVirtualNetworkDefinition -UseNat``, ``HyperVUseNAT`` notes, and DNS/IP-range planning — read [`references/networking.md`](references/networking.md).

## Roles, File Server, Machine Definitions, Internet, Chocolatey

Active Directory roles, File Server role, ``Add-LabMachineDefinition`` parameters, post-deployment internet connectivity fix, and Chocolatey-based software install — read [`references/roles-and-services.md`](references/roles-and-services.md).

## Post-Deployment Operations

``Invoke-LabCommand``, scriptblock vs file modes, ``-PassThru``, ``-NoDisplay``, ``-AsJob``, ``-ComputerName`` patterns, CredSSP for double-hop, and elevated-context recipes — read [`references/post-deployment-operations.md`](references/post-deployment-operations.md).

## VM Operations & Lifecycle

``Get-LabVM*`` queries, ``Wait-LabVM`` / ``Wait-LabADReady`` operations, restart/save/snapshot lifecycle, ``Copy-LabFileItem``/``Get-LabInternetFile``, and PSSession management — read [`references/vm-operations.md`](references/vm-operations.md).

## Lab Management

DSC configuration, testing & validation, domain operations (``Join-LabVMDomain``), firewall, PKI/certs (``Request-LabCertificate``), disk/ISO management (``Mount-LabIsoImage``), lab data paths, pre/post-install activities, base-image caching, and lab lifecycle — read [`references/lab-management.md`](references/lab-management.md).

## Retrieving Lab Metadata After Import

After `Import-Lab`, use `Get-Lab` to retrieve the lab object. This is the
correct way to obtain the domain name, network info, and other lab-level
configuration. **Never hardcode domain names** — always derive them from
the lab definition so scripts work regardless of how the lab was deployed.

```powershell
Import-Lab -Name 'MyLab' -NoValidation

# Lab object contains domains, networks, machines, and metadata
$lab = Get-Lab

# Domain FQDN (e.g. 'contoso.com')
$domainName = $lab.Domains[0].Name

# Derive DN and NetBIOS from the FQDN
$domainDN = ($domainName -split '\.' | ForEach-Object { "DC=$_" }) -join ','
$domainNetBIOS = ($domainName -split '\.')[0]

# Resolve VM names (accounts for global name prefix)
$labVMs = Get-LabVM
$dc1Name = ($labVMs | Where-Object { $_.Name -like '*DC1' }).Name
```

> **Why this matters:** Deployment scripts accept `-DomainName` as a
> parameter (e.g. `contoso.com`, `mylab.local`). Post-deployment and
> break/fix scripts that hardcode a specific domain name will fail
> when the lab was deployed with a different domain. Always use
> `Get-Lab` to retrieve the actual domain.

Useful `Get-Lab` properties:

| Property | Example Value | Description |
|---|---|---|
| `$lab.Domains[0].Name` | `contoso.com` | Primary domain FQDN |
| `$lab.Domains[0].Administrator` | `contoso\Install` | Domain admin account |
| `$lab.Name` | `MyLab` | Lab name |
| `$lab.DefaultVirtualizationEngine` | `HyperV` | Virtualisation engine |

Pass derived values into `Invoke-LabCommand` scriptblocks using `$using:`:

```powershell
Invoke-LabCommand -ComputerName $dc1Name -ScriptBlock {
    $zone = "_msdcs.$($using:domainName)"
    Get-DnsServerResourceRecord -ZoneName $zone -RRType SRV
}
```

## Reference Lab: Domain + File Server + Client + Internet

A complete lab script is maintained at the project root:

- **Script**: `Deploy-AutomatedLab.ps1`
- **Machines**: DC1 (RootDC), DC2 (DC), FS1 (FileServer), RTR1 (Routing), CL1 (Win11 client)
- **Domain**: `contoso.com`
- **Network**: `192.168.100.0/24` internal + Default Switch (External) for internet
- **Post-deploy**: Creates `\\FS1\Data` share, takes a baseline snapshot

## Troubleshooting

Hyper-V symptoms, WinRM/CredSSP failures, AD-readiness races, ISO mount issues, base-image corruption, and post-install hangs — read [`references/troubleshooting.md`](references/troubleshooting.md).

## Common Roles Quick Reference

| Role | Purpose |
|---|---|
| `RootDC` | Forest root domain controller |
| `FirstChildDC` | Child or tree domain controller |
| `DC` | Additional domain controller |
| `ADDS` | AD DS without automatic promotion |
| `FileServer` | Windows File Server role |
| `WebServer` | IIS Web Server |
| `DHCP` | DHCP Server |
| `Routing` | RRAS router / NAT gateway |
| `CaRoot` | Enterprise Root CA |
| `CaSubordinate` | Subordinate CA |
| `SQLServer2022` | SQL Server 2022 (needs ISO) |
| `SQLServer2019` | SQL Server 2019 (needs ISO) |
| `SQLServer2017` | SQL Server 2017 (needs ISO) |
| `SQLServer` | Generic SQL Server role |
| `Exchange2019` | Exchange Server (needs ISO + prereqs) |
| `DSCPullServer` | DSC Pull Server with SQL reporting |
| `WindowsAdminCenter` | WAC portal |
| `HyperV` | Nested Hyper-V role |
| `FailoverNode` | Failover cluster member |
| `FailoverStorage` | Failover cluster shared storage |
| `ADFS` | Active Directory Federation Services |
| `ADFSWAP` | ADFS Web Application Proxy |
| `Office2013` | Office 2013 deployment |
| `Office2016` | Office 2016 deployment |
| `AzDevOps` | Azure DevOps Server (formerly TFS) |
| `Tfs2018` | Team Foundation Server 2018 |
| `TfsBuildWorker` | TFS/Azure DevOps build agent |

## Cmdlet Quick Reference

Complete table of AutomatedLab cmdlets grouped by area (definition, deployment, query, lifecycle, command execution, network, disk, file transfer) — read [`references/cmdlet-reference.md`](references/cmdlet-reference.md).

## Links

- [AutomatedLab Documentation](https://automatedlab.org/en/latest/)
- [GitHub Repository](https://github.com/AutomatedLab/AutomatedLab)
- [Sample Scripts](https://github.com/AutomatedLab/AutomatedLab/tree/develop/LabSources/SampleScripts)
- [Role Reference](https://automatedlab.org/en/latest/Wiki/Roles/roles/)
- [PowerShell Gallery](https://www.powershellgallery.com/packages/AutomatedLab/)
