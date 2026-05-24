# Networking

Extracted from `Skills/automatedlab-deployment/SKILL.md` to keep the main skill body under Anthropic's 500-line budget.

## Contents

- Internal-Only Network (No Internet)
- Internet-Connected Lab — Choosing an Approach
- Approach A: Direct External NIC on Every VM — PREFERRED
- Approach B: Router + External Switch
- Approach C: Default Switch (Internal + NAT) — PREFERRED on Client Hosts
- Approach D: NAT Switch (`-UseNat`) — Simplest Path to Internet

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

