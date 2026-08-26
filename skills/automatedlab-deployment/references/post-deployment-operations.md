# Post-Deployment Operations

Extracted from `Skills/automatedlab-deployment/SKILL.md` to keep the main skill body under Anthropic's 500-line budget.

## Contents

- Run commands on lab VMs
- Passing variables into `Invoke-LabCommand` script blocks
- Targeting VMs individually vs. in bulk
- Credentials — always use `Invoke-LabCommand`
- CredSSP — why AutomatedLab uses it and what it means
- Windows 11 VMs — WinRM reliability
- Install Windows features
- Install software packages
- Connect to a VM console
- Enter a remote session
- Snapshot / Restore

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

