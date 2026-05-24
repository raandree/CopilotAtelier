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

