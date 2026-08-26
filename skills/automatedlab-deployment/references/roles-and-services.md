# Roles, File Server, Machine Definitions, Internet, Chocolatey

Extracted from `Skills/automatedlab-deployment/SKILL.md` to keep the main skill body under Anthropic's 500-line budget.

## Contents

- RootDC — Forest Root Domain Controller
- DC — Additional Domain Controller
- FirstChildDC — Child Domain Controller
- External Switch (Approach B — recommended path)

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

