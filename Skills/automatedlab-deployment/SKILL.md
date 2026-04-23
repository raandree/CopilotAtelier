---
name: automatedlab-deployment
description: >-
  Build and deploy Hyper-V lab environments using AutomatedLab (AL).
  Covers installation, lab definitions, roles (AD, File Server, Routing, PKI, SQL, etc.),
  networking, internet connectivity, post-deployment configuration, VM status monitoring,
  snapshots, file transfer, DSC, certificates, firewall management, and teardown.
  USE FOR: AutomatedLab, Hyper-V lab, deploy lab, create lab, domain controller, file server,
  routing, NAT, lab networking, lab VMs, test environment, lab setup, ISO images, LabSources,
  Install-Lab, New-LabDefinition, Add-LabMachineDefinition, Remove-Lab,
  Get-LabVMStatus, Get-LabVM, Get-LabVMUptime, Wait-LabVM, Wait-LabVMRestart,
  Wait-LabVMShutdown, Wait-LabADReady, Restart-LabVM, Save-LabVM, Remove-LabVM,
  Copy-LabFileItem, Get-LabInternetFile, Invoke-LabDscConfiguration,
  Test-LabMachineInternetConnectivity, Test-LabADReady, Join-LabVMDomain,
  Enable-LabVMFirewallGroup, Disable-LabVMFirewallGroup, Add-LabVMUserRight,
  Request-LabCertificate, Enable-LabCertificateAutoenrollment, Get-LabIssuingCA,
  Add-LabDiskDefinition, Mount-LabIsoImage, Update-LabIsoImage, Set-LabDefaultOperatingSystem,
  Connect-Lab, Enable-LabInternalRouting, Get-LabHyperVAvailableMemory,
  Add-LabVirtualNetworkDefinition -UseNat, NAT switch, NAT gateway, NetNat,
  HyperVUseNAT, internet without router VM, CredSSP, credential delegation,
  double-hop, Enable-LabHostRemoting, network resource access from VM.
  DO NOT USE FOR: Azure VM deployment (use azure-deploy), production infrastructure,
  non-Hyper-V virtualisation.
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

### Internal-Only Network (No Internet)

```powershell
Add-LabVirtualNetworkDefinition -Name 'LabNet' `
    -AddressSpace '192.168.100.0/24' `
    -HyperVProperties @{ SwitchType = 'Internal' }
```

### Internet-Connected Lab — Choosing an Approach

There are several approaches for giving lab VMs internet access. The right
choice depends on the **host SKU** (client vs. server).

#### Pre-flight: Detect host SKU and Default Switch

```powershell
$os = Get-CimInstance Win32_OperatingSystem
$isClientSKU = $os.ProductType -eq 1   # 1=Workstation, 2=DC, 3=Server
$hasDefaultSwitch = [bool](Get-VMSwitch -Name 'Default Switch' -ErrorAction SilentlyContinue)
```

#### Approach priority by host environment

| Host Environment | Preferred Approach | Rationale |
|---|---|---|
| **Client SKU** (Win10/11) with Default Switch | **C. Default Switch** | Built-in Internal+NAT — no NIC binding, no config |
| **Server SKU** | **A. Direct External NIC** or **D. NAT Switch** | No Default Switch; External NIC is reliable on servers |
| **Nested / Azure VM** | **D. NAT Switch (`-UseNat`)** | Physical NICs are bridged; External switches fail |
| **Network isolation needed** | **B. Router + External Switch** | Only when routing/firewall control is required |

#### Full approach comparison

| Approach | Router VM? | Complexity | Reliability | Best For |
|---|---|---|---|---|
| **A. Direct External NIC** | No | Low | High | Server hosts, simple labs |
| **B. Router + External Switch** | Yes | Medium | High | Multi-network, domain labs |
| **C. Default Switch (Internal+NAT)** | No | Lowest | High | **Client hosts** (Win10/11) — preferred |
| **D. NAT Switch (`-UseNat`)** | No | Lowest | High | Single-NIC labs, nested VMs, no physical adapter binding |

#### Pre-flight: Discover a usable physical adapter

> **On client hosts with a Default Switch, skip this section** — use
> Approach C instead. External adapter discovery is only needed for
> Approach A or B on server hosts.

Before defining an External switch, verify a physical NIC is available and
**not already bound** to an existing virtual switch or bridge:

```powershell
# List physical adapters
Get-NetAdapter -Physical | Where-Object Status -eq 'Up' |
    Select-Object Name, InterfaceDescription, Status

# Check if already bound to a Hyper-V switch
Get-VMSwitch -SwitchType External -ErrorAction SilentlyContinue |
    Select-Object Name, NetAdapterInterfaceDescription
```

> **Azure VMs / nested virtualisation**: Physical NICs on Azure VMs are often
> already bridged and **cannot** be used for new External switches. You will
> get the error: *"The given network adapter is already part of a network
> bridge and cannot be used."* In this case, check if an existing External
> switch can be reused, or fall back to Approach C.

### Approach A: Direct External NIC on Every VM — PREFERRED

The simplest approach: create one External switch and attach a second NIC
(DHCP) to **every** VM that needs internet. No router VM, no NAT, no
post-deployment gateway fix.

```powershell
# Internal network for lab communication
Add-LabVirtualNetworkDefinition -Name 'LabNet' `
    -AddressSpace '192.168.100.0/24' `
    -HyperVProperties @{ SwitchType = 'Internal' }

# External network — bound to a physical NIC
Add-LabVirtualNetworkDefinition -Name 'LabExtNet' `
    -HyperVProperties @{ SwitchType = 'External'; AdapterName = 'Ethernet' }

# Every VM gets two NICs: internal (static) + external (DHCP)
$fs1Adapters = @()
$fs1Adapters += New-LabNetworkAdapterDefinition -VirtualSwitch 'LabNet' -Ipv4Address '192.168.100.10'
$fs1Adapters += New-LabNetworkAdapterDefinition -VirtualSwitch 'LabExtNet' -UseDhcp

Add-LabMachineDefinition -Name 'FS1' `
    -Memory 2GB -MinMemory 1GB -MaxMemory 4GB `
    -Processors 2 `
    -OperatingSystem 'Windows Server 2025 Standard (Desktop Experience)' `
    -NetworkAdapter $fs1Adapters `
    -Roles FileServer

$cl1Adapters = @()
$cl1Adapters += New-LabNetworkAdapterDefinition -VirtualSwitch 'LabNet' -Ipv4Address '192.168.100.11'
$cl1Adapters += New-LabNetworkAdapterDefinition -VirtualSwitch 'LabExtNet' -UseDhcp

Add-LabMachineDefinition -Name 'CL1' `
    -Memory 4GB -MinMemory 2GB -MaxMemory 8GB `
    -Processors 2 `
    -OperatingSystem 'Windows 11 Enterprise' `
    -NetworkAdapter $cl1Adapters
```

**Advantages:**
- No router VM (saves RAM and deployment time)
- No post-deployment gateway/DNS fix needed
- Each VM gets its own DHCP lease from the physical network
- Simplest to debug — if the host has internet, VMs have internet

**When NOT to use:** When you need network isolation between VMs and the
physical network, or when you need controlled routing (use Approach B).

### Approach B: Router + External Switch

Create an External switch and a router VM with the `Routing` role. Only
RTR1 connects to the physical network; internal VMs route through it.

```powershell
# Internal network
Add-LabVirtualNetworkDefinition -Name 'LabNet' `
    -AddressSpace '192.168.100.0/24' `
    -HyperVProperties @{ SwitchType = 'Internal' }

# External network — bound to a physical NIC for reliable DHCP
Add-LabVirtualNetworkDefinition -Name 'LabExtNet' `
    -HyperVProperties @{ SwitchType = 'External'; AdapterName = 'Ethernet' }

# Router VM with two NICs
$adapters = @()
$adapters += New-LabNetworkAdapterDefinition -VirtualSwitch 'LabNet' -Ipv4Address '192.168.100.1'
$adapters += New-LabNetworkAdapterDefinition -VirtualSwitch 'LabExtNet' -UseDhcp

Add-LabMachineDefinition -Name 'RTR1' `
    -Memory 1GB -MinMemory 512MB -MaxMemory 2GB `
    -Processors 2 `
    -OperatingSystem 'Windows Server 2025 Standard (Desktop Experience)' `
    -NetworkAdapter $adapters `
    -Roles Routing
```

> **AdapterName**: Use the exact name from `Get-NetAdapter -Physical`. Common
> values: `Ethernet`, `Ethernet 2`, `Wi-Fi`.

When AL detects a machine with the `Routing` role it automatically:

- Installs and configures RRAS on RTR1
- Enables IP forwarding between NICs

> **AL does NOT automatically configure:**
>
> 1. A default gateway on internal VMs (FS1, CL1, etc.) pointing to RTR1
> 2. Public DNS servers on internal VMs
>
> **You MUST add a post-deployment gateway/DNS fix** after `Install-Lab`.
> See the [Post-Deployment Internet Connectivity Fix] section below.

### Approach C: Default Switch (Internal + NAT) — PREFERRED on Client Hosts

On **client SKUs** (Windows 10/11), Hyper-V ships with a built-in virtual
switch named **"Default Switch"**. Despite common misconception, this is
an **Internal** switch — not an External switch. It uses Windows Internet
Connection Sharing (ICS) to provide automatic NAT at `172.25.x.1/20`.
VMs attached to it receive DHCP from the host and get internet through
NAT — no physical NIC binding, no router VM, no post-deployment fix.

> **Server SKUs** (Windows Server) do **not** have a Default Switch. On
> server hosts, use Approach A or D instead.

> **Do NOT define the Default Switch as External.** The switch already
> exists as Internal. Defining it with `SwitchType = 'External'` will
> either fail or create a conflicting switch.

Use this approach when the host is a client SKU and VMs need internet:

```powershell
# Internal network for lab communication
Add-LabVirtualNetworkDefinition -Name 'LabNet' `
    -AddressSpace '192.168.100.0/24' `
    -HyperVProperties @{ SwitchType = 'Internal' }

# Reuse the built-in Default Switch (Internal + NAT) — already exists
Add-LabVirtualNetworkDefinition -Name 'Default Switch' `
    -HyperVProperties @{ SwitchType = 'Internal' }

# Every VM gets two NICs: internal (static) + Default Switch (DHCP+NAT)
$cl1Adapters = @()
$cl1Adapters += New-LabNetworkAdapterDefinition -VirtualSwitch 'LabNet' -Ipv4Address '192.168.100.10'
$cl1Adapters += New-LabNetworkAdapterDefinition -VirtualSwitch 'Default Switch' -UseDhcp

Add-LabMachineDefinition -Name 'CL1' `
    -Memory 4GB -MinMemory 2GB -MaxMemory 8GB `
    -Processors 2 `
    -OperatingSystem 'Windows 11 Enterprise' `
    -NetworkAdapter $cl1Adapters
```

**Advantages:**
- No physical NIC binding (avoids breaking host networking)
- No router VM (saves RAM and deployment time)
- No post-deployment gateway/DNS fix needed
- Already exists on client hosts — zero switch creation overhead
- Each VM gets DHCP + internet automatically through host NAT

**When NOT to use:** On server SKUs (switch doesn't exist), or when VMs
need to be directly reachable from the physical network (NAT provides
outbound-only connectivity).

### Approach D: NAT Switch (`-UseNat`) — Simplest Path to Internet

Use the `-UseNat` switch on `Add-LabVirtualNetworkDefinition` to create a
Hyper-V internal switch with an automatic NAT gateway. VMs get internet
access through the host's NAT — no router VM, no external switch binding,
no post-deployment gateway fix, and only a single NIC per VM.

This feature was added in [PR #1812](https://github.com/AutomatedLab/AutomatedLab/pull/1812)
and requires AutomatedLab builds from the `develop` branch after March 2026
(or the next stable release that includes it).

```powershell
# Minimal lab with NAT internet — single VM, no domain
New-LabDefinition -Name 'NatLab' -DefaultVirtualizationEngine HyperV

Add-LabVirtualNetworkDefinition -Name 'NatLab' -UseNat
Add-LabMachineDefinition -Name 'VM1' -Network 'NatLab' -Memory 4GB `
    -OperatingSystem 'Windows Server 2025 Datacenter Evaluation (Desktop Experience)'

Install-Lab
```

Domain lab with NAT:

```powershell
New-LabDefinition -Name 'NatDomainLab' -DefaultVirtualizationEngine HyperV

Add-LabVirtualNetworkDefinition -Name 'NatDomainLab' -UseNat
Add-LabMachineDefinition -Name 'NAT1DC1' -Role RootDC -Domain 'nat.local' `
    -Network 'NatDomainLab' -Memory 4GB `
    -OperatingSystem 'Windows Server 2025 Datacenter Evaluation (Desktop Experience)'
Add-LabMachineDefinition -Name 'NAT1VM1' -Network 'NatDomainLab' -Memory 4GB `
    -OperatingSystem 'Windows Server 2025 Datacenter Evaluation (Desktop Experience)'
Add-LabMachineDefinition -Name 'NAT1VM2' -Domain 'nat.local' `
    -Network 'NatDomainLab' -Memory 4GB `
    -OperatingSystem 'Windows Server 2025 Datacenter Evaluation (Desktop Experience)'

Install-Lab

# Verify connectivity
Test-LabMachineInternetConnectivity -ComputerName NAT1DC1
Test-LabMachineInternetConnectivity -ComputerName NAT1VM1
Test-LabMachineInternetConnectivity -ComputerName NAT1VM2
```

**What happens under the hood when `-UseNat` is used:**

1. AL creates a Hyper-V internal switch
2. A `NetNat` object is created for the network's address space
   (`New-NetNat -Name <SwitchName> -InternalIPInterfaceAddressPrefix <AddressSpace>`)
3. Each VM's default gateway is automatically set to the network's first
   usable IP address — no manual gateway configuration needed
4. Non-domain VMs get the host's default DNS forwarder instead of `0.0.0.0`
5. For domain labs, `Set-LabADDNSServerForwarder` is called automatically
   during `Install-Lab` to ensure DNS resolution works through NAT
6. On lab removal, the NAT gateway IP and `NetNat` object are cleaned up

**Enable NAT by default for all labs** (optional):

```powershell
# Set the configuration item so all networks use NAT unless overridden
Set-PSFConfig -Module 'AutomatedLab' -Name HyperVUseNAT -Value $true
```

> **Limitations**: `-UseNat` only works with the **HyperV** virtualisation
> engine. It is ignored (with a warning) on Azure labs or when combined
> with an External switch type.

**Advantages of NAT over other approaches:**
- No physical network adapter binding required (works on hosts with no
  spare NIC, including nested Hyper-V in Azure VMs)
- No router VM (saves RAM and deployment time)
- No post-deployment gateway/DNS fix
- Single NIC per VM — simplest possible configuration
- Multiple NAT labs can coexist on the same host

**When NOT to use:** When you need VMs directly reachable from the physical
network (NAT provides outbound-only connectivity by default), or when you
need controlled routing between multiple lab networks.

## Active Directory Roles

### RootDC — Forest Root Domain Controller

```powershell
Add-LabMachineDefinition -Name 'DC1' `
    -OperatingSystem 'Windows Server 2025 Standard (Desktop Experience)' `
    -Roles RootDC `
    -DomainName 'contoso.com' `
    -Network 'LabNet' -IpAddress '192.168.100.10'
```

With custom functional levels and site:

```powershell
$role = Get-LabMachineRoleDefinition -Role RootDC @{
    ForestFunctionalLevel = 'WinThreshold'
    DomainFunctionalLevel = 'WinThreshold'
    SiteName              = 'HQ'
    SiteSubnet            = '192.168.100.0/24'
}
Add-LabMachineDefinition -Name 'DC1' ... -Roles $role
```

### DC — Additional Domain Controller

```powershell
Add-LabMachineDefinition -Name 'DC2' `
    -OperatingSystem 'Windows Server 2025 Standard (Desktop Experience)' `
    -Roles DC `
    -DomainName 'contoso.com' `
    -Network 'LabNet' -IpAddress '192.168.100.11'
```

Read-only DC:

```powershell
$role = Get-LabMachineRoleDefinition -Role DC @{
    IsReadOnly = 'true'
    SiteName   = 'Branch'
    SiteSubnet = '192.168.200.0/24'
}
```

### FirstChildDC — Child Domain Controller

```powershell
$role = Get-LabMachineRoleDefinition -Role FirstChildDC @{
    ParentDomain = 'contoso.com'
    NewDomain    = 'emea'
}
Add-LabMachineDefinition -Name 'CDC1' `
    -DomainName 'emea.contoso.com' `
    -Roles $role ...
```

## File Server Role

```powershell
Add-LabMachineDefinition -Name 'FS1' `
    -OperatingSystem 'Windows Server 2025 Standard (Desktop Experience)' `
    -Roles FileServer `
    -DomainName 'contoso.com' `
    -Network 'LabNet' -IpAddress '192.168.100.20'
```

Post-deployment share creation:

```powershell
Invoke-LabCommand -ComputerName 'FS1' -ActivityName 'Create Data share' -ScriptBlock {
    $path = 'C:\Shares\Data'
    New-Item -Path $path -ItemType Directory -Force | Out-Null
    New-SmbShare -Name 'Data' -Path $path `
        -FullAccess 'contoso\Domain Admins' `
        -ChangeAccess 'contoso\Domain Users'
}
```

## Machine Definition Parameters

Key parameters for `Add-LabMachineDefinition`:

| Parameter | Purpose | Example |
|---|---|---|
| `-Name` | VM name (max 15 chars for NetBIOS) | `'DC1'` |
| `-Memory` | Startup RAM | `2GB` |
| `-MinMemory` / `-MaxMemory` | Dynamic memory range | `1GB` / `4GB` |
| `-Processors` | vCPU count | `2` |
| `-OperatingSystem` | OS string from ISO | `'Windows Server 2025 ...'` |
| `-Network` | Virtual switch name | `'LabNet'` |
| `-IpAddress` | Static IP | `'192.168.100.10'` |
| `-DnsServer1` / `-DnsServer2` | DNS servers | `'192.168.100.10'` |
| `-DomainName` | AD domain to join | `'contoso.com'` |
| `-Roles` | One or more AL roles | `RootDC`, `DC`, `FileServer` |
| `-NetworkAdapter` | Multi-NIC definitions | Array from `New-LabNetworkAdapterDefinition` |

## Post-Deployment Internet Connectivity Fix

> **Not needed for Approach A** (direct External NIC) or **Approach D**
> (NAT switch with `-UseNat`). Both provide internet access automatically
> without manual gateway/DNS configuration. Skip this section if using
> either approach.

For **Approach B** (Router + External switch) and **Approach C** (Default
Switch), you **must** configure the default gateway and DNS on internal VMs
so they can reach the internet through RTR1. AL's Routing role enables IP
forwarding on RTR1 but does **not** set gateway/DNS on the other lab machines.

### External Switch (Approach B — recommended path)

With an External switch RTR1 gets a real DHCP lease — only the internal VMs
need a gateway and DNS fix:

```powershell
# ── Post-Deployment: Fix Internet Connectivity ─────────────────
$targetMachines = @('FS1', 'CL1')  # all internal VMs (not RTR1)

# Internal VMs — set default gateway (RTR1's internal IP) + public DNS
Invoke-LabCommand -ComputerName $targetMachines -ActivityName 'Set gateway and DNS' -ScriptBlock {
    $adapter = Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object -First 1
    if (-not (Get-NetRoute -InterfaceIndex $adapter.ifIndex -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue)) {
        New-NetRoute -InterfaceIndex $adapter.ifIndex -DestinationPrefix '0.0.0.0/0' `
                     -NextHop '192.168.110.1' | Out-Null
    }
    Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex `
                               -ServerAddresses @('8.8.8.8', '8.8.4.4')
}

# Verify internet connectivity with retries
$allMachines = @('RTR1') + $targetMachines
$retries = 3
for ($attempt = 1; $attempt -le $retries; $attempt++) {
    $results = Invoke-LabCommand -ComputerName $allMachines -ScriptBlock {
        [PSCustomObject]@{
            Name   = $env:COMPUTERNAME
            Online = (Test-Connection -ComputerName '8.8.8.8' -Count 1 -Quiet)
        }
    } -PassThru
    $offline = $results | Where-Object { -not $_.Online }
    if (-not $offline) { Write-Host 'All machines have internet connectivity.' -ForegroundColor Green; break }
    Write-Host "Attempt $attempt/$retries — offline: $($offline.Name -join ', '). Retrying in 15 s…" -ForegroundColor Yellow
    Start-Sleep -Seconds 15
}
if ($offline) {
    Write-Warning "Internet still unavailable on: $($offline.Name -join ', '). Software installs may fail."
}
```

> **Default Switch note**: Since "Default Switch" is an External switch
> bound to a physical NIC, VMs attached to it get a real DHCP lease from
> the physical network. No NAT rules or static IP fixes are required.

## Installing Software via Chocolatey

After internet connectivity is confirmed, use this pattern to install
Chocolatey and packages on lab VMs:

```powershell
# Install Chocolatey
Invoke-LabCommand -ComputerName $targetMachines -ActivityName 'Install Chocolatey' -ScriptBlock {
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
    $env:chocolateyUseWindowsCompression = 'true'
    Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
    # Refresh PATH immediately so choco is found in the same session
    $env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                [System.Environment]::GetEnvironmentVariable('Path', 'User')
    Write-Host "$env:COMPUTERNAME — Chocolatey $(choco --version) installed"
} -PassThru

# Install packages
Invoke-LabCommand -ComputerName $targetMachines -ActivityName 'Install Software' -ScriptBlock {
    $env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                [System.Environment]::GetEnvironmentVariable('Path', 'User')
    choco install notepadplusplus  -y --no-progress
    choco install powershell-core  -y --no-progress
    choco install vscode           -y --no-progress
    Write-Host "$env:COMPUTERNAME — all packages installed"
} -PassThru
```

> **Important**: Always refresh `$env:Path` from the Machine/User environment
> variables at the start of each `Invoke-LabCommand` script block. The
> Chocolatey installer modifies the Machine PATH, but AL remoting sessions
> cache the old PATH — without the refresh, `choco` will not be found.

## Post-Deployment Operations

### Run commands on lab VMs

```powershell
Invoke-LabCommand -ComputerName 'DC1' -ScriptBlock { Get-ADDomain }
```

### Passing variables into `Invoke-LabCommand` script blocks

`Invoke-LabCommand` supports the `$using:` scope modifier just like
`Invoke-Command`. Use `$using:` to reference host-scope variables
inside the remote script block.

```powershell
# Pass host variables into the remote scriptblock via $using:
$domainName = 'contoso.com'
$sharePath = 'C:\Shares\Data'

Invoke-LabCommand -ComputerName 'FS1' -ScriptBlock {
    $netBIOS = ($using:domainName -split '\.')[0]
    New-SmbShare -Name 'Data' -Path $using:sharePath `
        -FullAccess "$netBIOS\Domain Admins"
}
```

For complex expressions, assign the `$using:` value to a local variable
first to keep the code readable:

```powershell
Invoke-LabCommand -ComputerName $dc1Name -ScriptBlock {
    $domain = $using:domainName
    $zone = "_msdcs.$domain"
    Get-DnsServerResourceRecord -ZoneName $zone -RRType SRV
}
```

### Targeting VMs individually vs. in bulk

When running `Invoke-LabCommand` against **multiple** VMs, if **any** VM
is unresponsive (e.g., WinRM not ready, Windows 11 still booting), the
entire command **hangs** and blocks all subsequent operations.

**Best practice**: For critical post-deployment steps, target each VM
individually. This isolates failures and allows the remaining VMs to
proceed:

```powershell
# RISKY — hangs if CL1 is unresponsive
Invoke-LabCommand -ComputerName 'FS1', 'CL1' -ScriptBlock { ... }

# SAFER — each VM processed independently
foreach ($vm in 'FS1', 'CL1') {
    Invoke-LabCommand -ComputerName $vm -ActivityName "Fix $vm" -ScriptBlock { ... }
}
```

### Credentials — always use `Invoke-LabCommand`

**Never** construct credentials manually with `[pscredential]::new()` or
`Get-Credential` and pass them to `Invoke-Command -VMName`. AutomatedLab
stores all credentials in the lab definition and `Invoke-LabCommand`
automatically selects the correct credential for each VM.

```powershell
# WRONG — manual credentials bypass the lab definition
$cred = [pscredential]::new('Administrator', $securePass)
Invoke-Command -VMName 'FS1' -Credential $cred -ScriptBlock { ... }

# RIGHT — AL handles credentials automatically
Invoke-LabCommand -ComputerName 'FS1' -ScriptBlock { ... }
```

### CredSSP — why AutomatedLab uses it and what it means

AutomatedLab configures **CredSSP** (Credential Security Support Provider) as
its default authentication mechanism for all PowerShell remoting. This is set
up on the host by `Enable-LabHostRemoting` (run automatically during
`Install-Lab` or manually via `Enable-LabHostRemoting -Force`) and on each VM
during deployment.

**Why CredSSP instead of default Kerberos/NTLM?**

Standard PowerShell remoting uses Kerberos (domain) or NTLM (workgroup), which
do **not** delegate credentials to the remote machine. This causes the
**double-hop problem**: from the remote session, you cannot access network
resources (file shares, SQL servers, other VMs, web services) because your
credentials are not forwarded.

```
Host ──[WinRM/Kerberos]──> VM1 ──[access denied]──> \\FileServer\Share
Host ──[WinRM/CredSSP]───> VM1 ──[credentials delegated]──> \\FileServer\Share  ✓
```

With CredSSP, the actual credentials are sent to the remote machine, which can
then use them to authenticate to third-party resources. AutomatedLab enables
this by default so that scripts running inside `Invoke-LabCommand` can:

- Access UNC paths and file shares on other lab VMs
- Query Active Directory on a domain controller from a member server
- Connect to SQL Server instances on other VMs
- Download files from the internet (when combined with internet connectivity)
- Install software from a central share or LabSources

**All AL remoting cmdlets use CredSSP automatically:**

| Cmdlet | Uses CredSSP |
|---|---|
| `Invoke-LabCommand` | Yes — default |
| `Enter-LabPSSession` | Yes — default |
| `New-LabPSSession` | Yes — default |
| `Copy-LabFileItem` | Yes — for file transfers |

> **Important**: If you bypass AL cmdlets and use `Invoke-Command` or
> `Enter-PSSession` directly, you get **standard Kerberos/NTLM** authentication
> — no credential delegation, no network resource access. Always use the AL
> cmdlets.

**Troubleshooting CredSSP issues:**

```powershell
# Verify CredSSP is enabled on the host
Test-LabHostRemoting

# Re-enable if broken (e.g., after Windows Update)
Enable-LabHostRemoting -Force

# Check CredSSP client configuration on the host
Get-WSManCredSSP

# Revert all host remoting changes (cleanup after lab removal)
Undo-LabHostRemoting
```

**Common CredSSP error symptoms:**

| Symptom | Cause | Fix |
|---|---|---|
| "Access denied" on `Invoke-LabCommand` | CredSSP not enabled on host | `Enable-LabHostRemoting -Force` |
| Network resources unreachable from VM session | Using `Invoke-Command` instead of `Invoke-LabCommand` | Switch to AL cmdlets |
| "The WinRM client cannot process the request" | CredSSP policy reverted (GPO, Windows Update) | `Enable-LabHostRemoting -Force` |
| File share access works interactively but fails in script | Script uses `Invoke-Command` without CredSSP | Use `Invoke-LabCommand` or add `-Authentication CredSSP` |

### Windows 11 VMs — WinRM reliability

Windows 11 VMs are **significantly slower** to become responsive than
Server VMs. After software installs (especially VS Code, .NET runtime
updates), WinRM sessions may become **stale or unresponsive**.

**Mitigations:**

- Use `Wait-LabVM -ComputerName 'CL1'` before running commands
- Restart the VM if WinRM becomes unresponsive:
  `Restart-LabVM -ComputerName 'CL1' -Wait`
- Target Windows 11 VMs individually (not in bulk with servers)

### Install Windows features

```powershell
Install-LabWindowsFeature -ComputerName 'FS1' -FeatureName 'FS-FileServer', 'FS-Resource-Manager'
```

> **Client OS (Win10/11) — RSAT / `Add-WindowsCapability`**:
> `Install-LabWindowsFeature` uses `Enable-WindowsOptionalFeature` on clients, which
> does **not** recognise FOD capability names like
> `Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0`.
> `Add-WindowsCapability` is the correct cmdlet, but it fails with **"Access is
> denied"** over WinRM due to UAC remote token filtering on client OSes.
>
> **Workaround — scheduled task running as SYSTEM**:
>
> ```powershell
> Invoke-LabCommand -ComputerName 'CL1' -ScriptBlock {
>     $taskName = 'InstallRsatAdTools'
>     $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument (
>         '-NoProfile -NonInteractive -Command "Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0 | Out-File -FilePath C:\RsatInstall.log"'
>     )
>     $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
>     Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Force
>     Start-ScheduledTask -TaskName $taskName
>
>     while ((Get-ScheduledTaskInfo -TaskName $taskName).LastTaskResult -eq 267009) {
>         Start-Sleep -Seconds 5
>     }
>
>     $taskResult = Get-ScheduledTaskInfo -TaskName $taskName
>     $log = if (Test-Path -Path C:\RsatInstall.log) { Get-Content -Path C:\RsatInstall.log -Raw } else { 'No log file found.' }
>     Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
>     Remove-Item -Path C:\RsatInstall.log -ErrorAction SilentlyContinue
>
>     if ($taskResult.LastTaskResult -ne 0) {
>         throw "RSAT install task failed with exit code $($taskResult.LastTaskResult). Log: $log"
>     }
>     Write-Host $log
> }
> ```
>
> This pattern applies to **any** `Add-WindowsCapability` call on client VMs,
> not just RSAT. PowerShell Direct (`Invoke-Command -VMName`) also works but
> ties you to the Hyper-V host and cannot be used inside `Invoke-LabCommand`.

### Install software packages

```powershell
$pkg = Get-LabSoftwarePackage -Path "$labSources\SoftwarePackages\7z.exe" -CommandLine '/S'
Install-LabSoftwarePackage -ComputerName 'CL1' -SoftwarePackage $pkg
```

### Connect to a VM console

```powershell
Connect-LabVM -ComputerName 'CL1'
```

### Enter a remote session

```powershell
Enter-LabPSSession -ComputerName 'DC1'
```

### Snapshot / Restore

```powershell
Checkpoint-LabVM -All -SnapshotName 'Baseline'
Restore-LabVMSnapshot -All -SnapshotName 'Baseline'
```

## VM Queries & Status

### Get lab VM objects

```powershell
# All VMs in the current lab
Get-LabVM -All

# By name (supports wildcards)
Get-LabVM -ComputerName 'DC1'
Get-LabVM -ComputerName 'DC*'

# By role
Get-LabVM -Role RootDC
Get-LabVM -Role DC, FileServer

# Only running VMs
Get-LabVM -All -IsRunning

# With a filter script block
Get-LabVM -All -Filter { $_.Memory -ge 2GB }
```

### Get VM power state

```powershell
# All VMs — returns a hashtable-like output of Name → Status
Get-LabVMStatus

# Specific VMs
Get-LabVMStatus -ComputerName 'DC1', 'FS1'

# As a hashtable for programmatic use
$status = Get-LabVMStatus -AsHashTable
if ($status['DC1'] -ne 'Started') { Start-LabVM -ComputerName 'DC1' }
```

### Get VM uptime

```powershell
# Returns TimeSpan via remote WMI — VM must be running
Get-LabVMUptime -ComputerName 'DC1'
Get-LabVMUptime -ComputerName 'DC1', 'FS1'
```

### Get VM .NET Framework version

```powershell
Get-LabVMDotNetFrameworkVersion -ComputerName 'DC1'
```

### Generate RDP file

```powershell
# Creates an .rdp file for the specified VM
Get-LabVMRdpFile -ComputerName 'DC1'
```

## Wait Operations

Use these cmdlets to synchronize deployment scripts — they block until
the target condition is met or the timeout expires.

### Wait for VM to be ready (accepts remoting)

```powershell
Wait-LabVM -ComputerName 'DC1'

# With timeout (default is 15 minutes)
Wait-LabVM -ComputerName 'DC1' -TimeoutInMinutes 30

# Wait, then run a command
Wait-LabVM -ComputerName 'DC1'; Invoke-LabCommand -ComputerName 'DC1' -ScriptBlock { Get-Service }

# With a post-delay (seconds to wait after VM becomes available)
Wait-LabVM -ComputerName 'DC1' -PostDelaySeconds 30
```

### Wait for VM restart

```powershell
# Blocks until the VM restarts (reboots and comes back online)
Wait-LabVMRestart -ComputerName 'DC1'
Wait-LabVMRestart -ComputerName 'DC1' -TimeoutInMinutes 20
```

### Wait for VM shutdown

```powershell
# Blocks until the VM shuts down
Wait-LabVMShutdown -ComputerName 'DC1'
Wait-LabVMShutdown -ComputerName 'DC1' -TimeoutInMinutes 10
```

### Wait for Active Directory to be ready

```powershell
# Blocks until AD DS on the DC is responding
Wait-LabADReady -ComputerName 'DC1'
```

## VM Lifecycle (Extended)

### Restart VMs

```powershell
Restart-LabVM -ComputerName 'DC1'
Restart-LabVM -ComputerName 'DC1' -Wait   # blocks until fully restarted
```

### Save (hibernate) VMs

```powershell
Save-LabVM -ComputerName 'DC1'
Save-LabVM -All
```

### Remove individual VMs

```powershell
# Removes a single VM without destroying the entire lab
Remove-LabVM -Name 'CL1'
```

### Remove snapshots

```powershell
Remove-LabVMSnapshot -ComputerName 'DC1' -SnapshotName 'Baseline'
Remove-LabVMSnapshot -All -SnapshotName 'Baseline'
```

### Get snapshots

```powershell
Get-LabVMSnapshot -ComputerName 'DC1'
```

## File & Data Transfer

### Copy files to lab VMs

```powershell
# Copy a local file to a VM
Copy-LabFileItem -Path 'C:\Scripts\Setup.ps1' -ComputerName 'DC1' -DestinationFolderPath 'C:\Temp'

# Copy a directory
Copy-LabFileItem -Path 'C:\Scripts' -ComputerName 'DC1' -DestinationFolderPath 'C:\' -Recurse
```

### Download files from the internet

```powershell
# Downloads a file from a URL to the local machine
$labSources = Get-LabSourcesLocation
Get-LabInternetFile -Uri 'https://example.com/tool.exe' `
    -Path "$labSources\SoftwarePackages\tool.exe"
```

## Session Management

### PowerShell remoting sessions

```powershell
# Create a new PSSession to a lab VM
New-LabPSSession -ComputerName 'DC1'

# Get existing sessions
Get-LabPSSession -ComputerName 'DC1'

# Clean up sessions
Remove-LabPSSession -ComputerName 'DC1'
Remove-LabPSSession -All
```

### CIM sessions

```powershell
New-LabCimSession -ComputerName 'DC1'
Get-LabCimSession -ComputerName 'DC1'
Remove-LabCimSession -ComputerName 'DC1'
```

## DSC Configuration

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

### Validator bug — "CreateInstance" cast error (AL 5.59.x)

AutomatedLab 5.59.595 has a bug in the `AutomatedLab.UnknownRoleProperties`
validator. When `Install-Lab` runs validation, the validator's constructor throws:

```text
Exception calling "CreateInstance" with "1" argument(s):
"Unable to cast object of type 'System.Collections.Hashtable' to type 'System.Object[]'."
```

**Workaround**: Use `Install-Lab -NoValidation` to skip the validator phase.
This is safe — deployment errors will still surface during the actual install.
Also use `Import-Lab -Name '<Lab>' -NoValidation` when re-importing labs.

### "Operating system not found"

The `-OperatingSystem` string doesn't match any image in `<LabSources>\ISOs\`.
Run `Get-LabAvailableOperatingSystem` and copy the exact `OperatingSystemName`.

### "A virtual machine with the given name already exists"

A VM with the same name is already registered in another lab. This happens
when a previous lab was not fully removed, or another lab is still running
with VMs using the same names (e.g., `CL1`, `DC1`).

**Fix**: Use the engine-agnostic VM name collision check (see
[VM Name Collision Avoidance]) to auto-prefix all VM names. Alternatively,
remove the conflicting lab first:

```powershell
Import-Lab -Name '<OldLabName>' -NoValidation
Remove-Lab -Name '<OldLabName>' -Confirm:$false
```

### "Cannot find virtual switch"

The virtual switch name in the machine definition doesn't match.
Check with `Get-VMSwitch` and ensure the names match exactly.

### "Not enough memory on the host"

Reduce `-Memory` / `-MaxMemory` on machines, or use Dynamic Memory:

```powershell
Add-LabMachineDefinition -Name 'DC1' -Memory 1GB -MinMemory 512MB -MaxMemory 2GB ...
```

### Windows 11 — "Operating system not found" with consumer ISO

Consumer ISOs (e.g., `en-us_windows_11_consumer_editions_...`) contain
Home and Pro but **not** Enterprise. Use `'Windows 11 Pro'` as the
`-OperatingSystem` value. Verify with:

```powershell
Get-LabAvailableOperatingSystem | Where-Object OperatingSystemName -like '*11*' |
    Select-Object OperatingSystemName
```

### `Show-LabDeploymentSummary` has no `-Detailed` parameter

The cmdlet does **not** accept `-Detailed`. Use it without parameters:

```powershell
Show-LabDeploymentSummary
```

### VMs have no internet / `Test-LabMachineInternetConnectivity` returns `$false`

**With an External switch:**
- RTR1 should get a DHCP lease from the physical network automatically.
  If not, check `Get-NetAdapter -Physical` on the host — the adapter name
  in `Add-LabVirtualNetworkDefinition` must match exactly.
- Internal VMs (FS1, CL1) need a default gateway pointing to RTR1's
  internal IP + public DNS. See [Post-Deployment Internet Connectivity Fix].

**With the Default Switch (External):**
- The Default Switch is an External switch bound to a physical NIC.
- VMs should get a DHCP lease from the physical network automatically.
- If not, verify the adapter name matches `Get-NetAdapter -Physical` output.

### Lab deployment hangs

- Check Hyper-V Manager — the VM may be waiting at a prompt.
- Ensure ISOs are not corrupt (re-download if needed).
- Run `Enable-LabHostRemoting -Force` again.

### "Access denied" on Invoke-LabCommand

AutomatedLab uses CredSSP. Ensure the host was prepared with `Enable-LabHostRemoting -Force`.

A second common cause on **client OSes (Win10/11)**: UAC remote token filtering
strips the full admin token from WinRM sessions even for local administrators.
Cmdlets that require true elevation — `Add-WindowsCapability`, `dism.exe`,
etc. — will return "Access is denied" (DISM error 5). The fix is to run the
elevated work in a **scheduled task as SYSTEM** inside the `Invoke-LabCommand`
script block. See the example under [Install Windows features](#install-windows-features).

### `Import-Lab` required in every new terminal session

After a lab is deployed, the lab context exists **only in the PowerShell
session that ran `Install-Lab`**. If you open a new terminal (or the
session is recycled), all `*-Lab*` cmdlets will fail with errors like
*"The lab is not loaded"* or *"No machines imported"*.

**Always** run this at the start of a new session before any lab commands:

```powershell
Import-Lab -Name '<LabName>' -NoValidation
```

Use `-NoValidation` to skip the validator bug in AL 5.59.x.

### Cleaning up a failed deployment

```powershell
# Try the graceful path first
Import-Lab -Name '<LabName>' -NoValidation
Remove-Lab -Name '<LabName>' -Confirm:$false

# If Import-Lab fails ("no machines imported"), clean up manually:
# 1. Remove VMs in Hyper-V Manager or via Get-VM | Remove-VM -Force
# 2. Delete lab data:  Remove-Item 'C:\ProgramData\AutomatedLab\Labs\<LabName>' -Recurse -Force
# 3. Delete VM disks: Remove-Item 'D:\AutomatedLab-VMs\<VMName>*' -Recurse -Force
# 4. Remove lab switch: Remove-VMSwitch -Name '<LabNetName>' -Force
#    (Do NOT remove 'Default Switch' — it is a shared External switch!)
```

### "Network adapter already part of a network bridge" (Azure VM hosts)

When running AutomatedLab inside an **Azure VM** with nested Hyper-V, the
physical NICs are already bound to an Azure virtual bridge. Creating a new
External switch fails with:

```text
The given network adapter (...) for the external virtual switch (...)
is already part of a network bridge and cannot be used.
```

**Workaround:** Check if an existing External switch is already available
(`Get-VMSwitch -SwitchType External`). If not, use Approach C (Default
Switch fallback) or request a NIC from Azure that isn't bridged.

### WinRM session becomes unresponsive after software installs

After installing software (especially on Windows 11), the WinRM service
may stop responding. `Invoke-LabCommand` hangs indefinitely.

**Mitigations:**

1. **Restart the VM**: `Restart-LabVM -ComputerName 'CL1' -Wait`
2. **Target VMs individually** — don't batch Windows 11 with servers
3. **Set a timeout** — if supported, use connection timeouts
4. **Use PowerShell Direct as emergency fallback**:
   `Invoke-Command -VMName 'CL1' -Credential (Get-LabVMCredential 'CL1') -ScriptBlock { ... }`

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

## Links

- [AutomatedLab Documentation](https://automatedlab.org/en/latest/)
- [GitHub Repository](https://github.com/AutomatedLab/AutomatedLab)
- [Sample Scripts](https://github.com/AutomatedLab/AutomatedLab/tree/develop/LabSources/SampleScripts)
- [Role Reference](https://automatedlab.org/en/latest/Wiki/Roles/roles/)
- [PowerShell Gallery](https://www.powershellgallery.com/packages/AutomatedLab/)
