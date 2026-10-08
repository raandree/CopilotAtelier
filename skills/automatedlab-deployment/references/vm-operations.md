# VM Operations & Lifecycle

Extracted from `Skills/automatedlab-deployment/SKILL.md` to keep the main skill body under Anthropic's 500-line budget.

## Contents

- Get lab VM objects
- Get VM power state
- Get VM uptime
- Get VM .NET Framework version
- Generate RDP file
- Wait for VM to be ready (accepts remoting)
- Wait for VM restart
- Wait for VM shutdown
- Wait for Active Directory to be ready
- Restart VMs
- Save (hibernate) VMs
- Remove individual VMs
- Remove snapshots
- Remove an older snapshot and keep the newer ones
- Get snapshots
- Copy files to lab VMs
- Download files from the internet
- PowerShell remoting sessions
- CIM sessions

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

> **`Remove-LabVMSnapshot` removes the named snapshot *and all of its child
> snapshots*.** It calls `Remove-VMSnapshot -IncludeAllChildSnapshots
> -ErrorAction SilentlyContinue` on every machine (AutomatedLabCore 5.61.704),
> so every checkpoint below the named one in the VM's checkpoint tree — in a
> linear chain, every later one — is deleted with it, and a VM where nothing
> was removed is not reported. Use it only when the named snapshot is the
> newest one or the whole subtree is expendable.

```powershell
Remove-LabVMSnapshot -ComputerName 'DC1' -SnapshotName 'Baseline'
Remove-LabVMSnapshot -All -SnapshotName 'Baseline'
```

### Remove an older snapshot and keep the newer ones

Remove it per VM with `Remove-VMSnapshot` and **without**
`-IncludeAllChildSnapshots`. Hyper-V merges the removed checkpoint into its
child, so the later checkpoints survive. Address the VMs by their Hyper-V name
— `(Get-LabVM).ResourceName`, which differs from the machine name when the lab
uses a VM name prefix. Wait on `OperationalStatus`, an enum: the `Status` text
is localised, so comparing it to `'Operating normally'` never ends on a
non-English host.

```powershell
$snapshotToRemove = 'Baseline'
$vmNames = (Get-LabVM).ResourceName

foreach ($vmName in $vmNames) {
    Get-VMSnapshot -VMName $vmName |
        Where-Object Name -EQ $snapshotToRemove |
        Remove-VMSnapshot

    # The merge runs in the background; give it a moment to start, then wait it
    # out, and fail loudly instead of hanging if it never finishes
    $deadline = (Get-Date).AddMinutes(30)
    do {
        Start-Sleep -Seconds 5
        $operationalStatus = (Get-VM -Name $vmName).OperationalStatus
        $isMerging = ($operationalStatus -contains 'MergingDisks') -or
            ($operationalStatus -contains 'DeletingSnapshot')
        if ($isMerging -and (Get-Date) -gt $deadline) {
            throw "Merging '$snapshotToRemove' on '$vmName' did not finish within 30 minutes (OperationalStatus: $operationalStatus)."
        }
    } while ($isMerging)
}

# Verify on every VM that only the newer checkpoints remain
Get-VMSnapshot -VMName $vmNames |
    Select-Object VMName, Name, ParentSnapshotName
```

> A checkpoint that exists on only part of the lab cannot restore the lab to a
> consistent state. Apply and remove checkpoints across all lab machines
> together, and confirm the result with `Get-VMSnapshot` on every VM.

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

