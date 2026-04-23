---
agent: software-engineer
description: Deploy and validate a Hyper-V lab using AutomatedLab.
---

# Deploy AutomatedLab Environment

Deploy a fully automated Hyper-V lab environment using AutomatedLab, then validate
the deployment with Pester tests.

## Instructions

Follow the **automatedlab-deployment** skill (`Skills/automatedlab-deployment/SKILL.md`).
Execute every phase below in order — the agent MUST run the full pipeline, not
just print a script.

### Agent behavior — MANDATORY

The agent MUST execute the full deployment pipeline itself. It is NOT acceptable
to only generate a script and ask the user to run it. The agent must:

1. Build the `$LabConfig` hashtable from the user's request.
2. Write and execute the deployment script in an **elevated terminal**.
3. **Wait for the deployment to complete** — poll terminal output every 60–90 seconds
   for up to 60 minutes (longer for large labs). Do NOT abandon the task early.
4. After deployment completes, **run validation tests** against every machine
   (connectivity, OS version, installed roles/features, installed software).
5. Report final results to the user.

If terminal or file-editing tools are not enabled, the agent MUST tell the user
exactly which tools to enable (`github.copilot.chat.terminalAccess` and file
editing) and refuse to proceed until they are available — do NOT fall back to
just printing a script.

### Input format

Provide the lab specification as a natural language description. The agent will
parse it into a `$LabConfig` hashtable and execute the full pipeline.

### Common patterns (use these phrases in your prompt)

| Phrase | Effect |
|---|---|
| `internet facing` / `with internet` | Adds internet connectivity to all VMs |
| `domain <name>` / `domain-joined` | Creates AD domain; first server with `RootDC` gets the DC role |
| `Windows 11` / `Windows 10` / `Server 2025` | Sets the `-OperatingSystem` string |
| `<N> machines` | Creates N machines with auto-generated names |
| `file server` / `DC` / `PKI` / `SQL` | Adds the matching AutomatedLab role |
| `workgroup` | No domain (default) |

### Example prompts

```
Please deploy a lab with two Windows 11 machines both internet facing.
```

```
Deploy a domain lab (contoso.com) with one DC running Server 2025,
a file server, and two Windows 11 clients, all internet facing.
```

```
Create an isolated lab with three Server 2022 machines, no internet.
```

## Phase 1 — Parse the request into a LabConfig hashtable

Convert the user's natural language description into a `$LabConfig` hashtable
following this schema:

```powershell
$LabConfig = @{
    LabName    = '<derived from description or auto-generated>'
    DomainName = '<if requested, else omit>'        # e.g. 'contoso.com'
    Network    = @{
        Name         = '<LabName>Net'               # auto-derived
        AddressSpace = '192.168.110.0/24'            # default, adjust if conflict
    }
    Internet   = $true  # or $false
    Machines   = @(
        @{
            Name            = '<name>'               # max 15 chars
            OperatingSystem = '<exact ISO string>'   # verify with Get-LabAvailableOperatingSystem
            Memory          = 4GB                    # sensible defaults per OS
            MinMemory       = 2GB
            MaxMemory       = 8GB
            Processors      = 2
            IpAddress       = '192.168.110.10'       # sequential from .10
            Roles           = @('RoleName')          # optional
        }
        # ... more machines
    )
}
```

**Defaults used when not specified:**
- Lab name: derived from machine types (e.g., `Win11Lab`, `CorpLab`)
- Network address space: `192.168.110.0/24`
- IP addresses: sequential starting from `.10`
- Windows 11 memory: 4GB (min 2GB, max 8GB)
- Windows Server memory: 2GB (min 1GB, max 4GB)
- Processors: 2
- Admin credentials: `Install` / `Somepass1`

## Phase 2 — Verify OS availability

Before deploying, run this **in the terminal** to confirm the ISO is available:

```powershell
Get-LabAvailableOperatingSystem -Path (Get-LabSourcesLocation) |
    Where-Object OperatingSystemName -like '*<OS keyword>*' |
    Select-Object OperatingSystemName
```

If the exact OS string doesn't match, adjust the config.

## Phase 3 — Execute deployment (MUST run, not just print)

Write the full deployment script to a temp file and execute it in an **elevated
terminal**. The agent MUST start the command and then actively monitor it.

```powershell
& '<workspace>\Deploy-LabEnvironment.ps1' -LabConfig $LabConfig
```

#### VM Storage path

Before defining the lab, **scan all fixed drives** for an existing
`AutomatedLab-VMs` folder. If found, pass it as `-VmPath` to
`New-LabDefinition`. Never create a second `AutomatedLab-VMs` folder on
a different drive (see the `automatedlab-deployment` skill for the pattern).

#### VM name collision avoidance (mandatory)

Before adding machine definitions, **check that none of the planned VM names
collide with VMs in existing AutomatedLab labs**. This check is engine-agnostic —
it scans AL's local lab metadata, not the hypervisor directly. If collisions are
found, auto-generate a random 2-letter prefix and apply it with
`Set-LabGlobalNamePrefix`. This must run after `New-LabDefinition` but before
`Add-LabMachineDefinition`.

```powershell
$plannedNames = @('CL1', 'CL2')   # ← all VM names from the LabConfig

# Collect all machine names from existing AL labs (engine-agnostic)
$existingNames = [System.Collections.Generic.List[string]]::new()
foreach ($lab in (Get-Lab -List)) {
    Import-Lab -Name $lab -NoValidation -ErrorAction SilentlyContinue
    (Get-LabVM).Name | ForEach-Object { $existingNames.Add($_) }
}

$collisions = $plannedNames | Where-Object { $_ -in $existingNames }
if ($collisions) {
    do {
        $prefix = -join ((65..90) | Get-Random -Count 2 | ForEach-Object { [char]$_ })
        $prefixedNames = $plannedNames | ForEach-Object { "$prefix$_" }
        $stillCollides = $prefixedNames | Where-Object { $_ -in $existingNames }
    } while ($stillCollides)
    Write-Host "Name collision detected — using prefix '$prefix'"
    Set-LabGlobalNamePrefix -Name $prefix
}
```

See the `automatedlab-deployment` skill `## VM Name Collision Avoidance` for
full details.

#### Internet connectivity — choose the right approach

When the lab needs internet access, **detect the host SKU first**, then
choose the approach. See the SKILL.md `## Networking` section for full code.

```powershell
$os = Get-CimInstance Win32_OperatingSystem
$isClientSKU = $os.ProductType -eq 1   # 1=Workstation, 2=DC, 3=Server
$hasDefaultSwitch = [bool](Get-VMSwitch -Name 'Default Switch' -ErrorAction SilentlyContinue)
```

| Host Environment | Preferred | Approach |
|---|---|---|
| **Client SKU** (Win10/11) with Default Switch | **PREFERRED** | **C. Default Switch** — built-in Internal+NAT, no NIC binding |
| **Server SKU** | Recommended | **A. Direct External NIC** or **D. NAT Switch** |
| **Nested / Azure VM** | Recommended | **D. NAT Switch (`-UseNat`)** |
| **Network isolation needed** | When required | **B. Router + External Switch** |

> **On client hosts (Win10/11), always use the Default Switch** for internet.
> The Default Switch is an **Internal** switch with automatic ICS/NAT — not
> an External switch. Creating a new External switch on a client host can
> break host networking or leave VMs unreachable.
>
> **Do NOT create External switches on client hosts** unless the user
> explicitly requests it and understands the risks.
>
> Reserve **Approach A** (Direct External NIC) for **server hosts** where
> the Default Switch does not exist.

#### Pre-flight: discover host environment

```powershell
# Detect client vs server SKU
$os = Get-CimInstance Win32_OperatingSystem
$isClientSKU = $os.ProductType -eq 1
$hasDefaultSwitch = [bool](Get-VMSwitch -Name 'Default Switch' -ErrorAction SilentlyContinue)

# Only needed for Approach A (server hosts without Default Switch)
Get-NetAdapter -Physical | Where-Object Status -eq 'Up' | Select-Object Name
Get-VMSwitch -SwitchType External -ErrorAction SilentlyContinue
```

If `$isClientSKU` and `$hasDefaultSwitch`, use **Approach C** (Default Switch).
If a physical NIC fails with *"already part of a network bridge"*, fall
back to Approach D (`-UseNat`).

#### Credential and scripting rules

- **Never** construct credentials manually with `[pscredential]::new()`.
  Use `Invoke-LabCommand` — it uses the lab's stored credentials automatically.
- **Never** use `$using:` inside `Invoke-LabCommand` scriptblocks. Define
  variables directly inside the scriptblock or hardcode them.
- **Target VMs individually** for critical commands — if one VM is
  unresponsive, `Invoke-LabCommand` targeting multiple VMs hangs indefinitely.
- **`Import-Lab`** must be run in every new terminal session before any
  `*-Lab*` cmdlet: `Import-Lab -Name '<LabName>' -NoValidation`

## Phase 4 — Wait for deployment (MANDATORY — do NOT skip)

The agent MUST monitor the deployment to completion:

- Poll terminal output every **60–90 seconds**.
- Expect the deployment to take **15–60 minutes** depending on lab size.
- Do NOT give up, hand back to the user, or declare the task done while the
  deployment is still running.
- If the deployment times out at 60 minutes, alert the user but keep monitoring
  if still producing output.
- On failure, capture the error output and report it.

## Phase 5 — Internet connectivity fix (MANDATORY for internet-facing labs)

After `Install-Lab` completes and VMs are running, the deployment script MUST
fix internet connectivity **before** attempting any software installation.

> **Not needed for Approach A** (direct External NIC on every VM), **Approach C**
> (Default Switch on client hosts — VMs get DHCP+NAT automatically), or
> **Approach D** (`-UseNat` — NAT gateway is set up by AL). Skip this step
> for these approaches.

For **Approach B** (Router + External Switch):

1. RTR1 gets a real DHCP lease from the physical network automatically
2. **Set default gateway** on each internal VM (FS1, CL1, etc.) to RTR1's
   internal IP (e.g. `192.168.110.1`)
3. **Set DNS** to public servers (`8.8.8.8`, `8.8.4.4`)

**For all approaches, verify** internet with
`Test-Connection -ComputerName '8.8.8.8'` on all machines, with up to 3
retries before proceeding to software installation.

> **Target VMs individually** during verification. If one VM
> (especially Windows 11) is unresponsive, a bulk `Invoke-LabCommand`
> will hang forever.

See the `automatedlab-deployment` skill for the complete code patterns.

## Phase 6 — Post-deployment validation tests (MANDATORY)

After deployment completes successfully, the agent MUST run validation tests
against **every machine** in the lab. Execute the following checks in the terminal:

> **Important**: When installing software via Chocolatey, always refresh
> `$env:Path` from Machine/User environment variables at the start of each
> `Invoke-LabCommand` script block. AL remoting sessions cache the old PATH —
> without the refresh, `choco` will not be found.

> **Windows 11 resilience**: Target Windows 11 VMs **individually** — never
> batch them with server VMs. If a Windows 11 VM becomes unresponsive after
> software installs, restart it first:
> `Restart-LabVM -ComputerName 'CL1' -Wait`

```powershell
# 1. Verify all VMs are running
Get-LabVM | ForEach-Object {
    $vm = Get-VM -Name $_.Name
    Write-Host "$($_.Name): State=$($vm.State)"
}

# 2. Test connectivity to each VM
Get-LabVM | ForEach-Object {
    $result = Test-Connection -ComputerName $_.Name -Count 2 -Quiet
    Write-Host "$($_.Name): Ping=$result"
}

# 3. Verify installed roles/features (for Server VMs)
Invoke-LabCommand -ComputerName '<ServerName>' -ScriptBlock {
    Get-WindowsFeature | Where-Object Installed | Select-Object Name, InstallState
} -PassThru

# 4. Verify installed software
Invoke-LabCommand -ComputerName '<MachineName>' -ScriptBlock {
    Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* |
        Select-Object DisplayName, DisplayVersion |
        Where-Object DisplayName -like '*<SoftwareName>*'
} -PassThru

# 5. Verify internet connectivity (if requested)
Invoke-LabCommand -ComputerName '<MachineName>' -ScriptBlock {
    Test-Connection -ComputerName 8.8.8.8 -Count 1 -Quiet
} -PassThru
```

Adapt the tests to the specific lab request (check each requested role, each
requested software package, internet connectivity if specified, etc.).

**If any test fails**, report the failure clearly and attempt remediation once
before reporting a final failure.

## Phase 7 — Report results

After deployment AND testing, report:

| Item | Detail |
|---|---|
| Deployment duration | Total elapsed time |
| VM states | All must be `Running` |
| Connectivity | Ping results per VM |
| Internet access | Per VM (if applicable) |
| Roles/features | Installed vs requested per VM |
| Software | Installed vs requested per VM |
| Test summary | X passed / Y failed |
| Connect command | `Connect-LabVM -ComputerName '<name>'` per VM |
| Tear down command | `Remove-Lab -Name '<LabName>' -Confirm:$false` |

## Tool Requirements

This prompt requires the following VS Code Copilot tools to be enabled:

- **Terminal access** — to run PowerShell commands (`github.copilot.chat.terminalAccess`)
- **File editing** — to write deployment scripts to disk

If these tools are not available, instruct the user to enable them and do NOT
fall back to printing scripts for manual execution.
