# Troubleshooting

Extracted from `Skills/automatedlab-deployment/SKILL.md` to keep the main skill body under Anthropic's 500-line budget.

## Contents

- Validator bug — "CreateInstance" cast error (AL 5.59.x)
- "Operating system not found"
- "A virtual machine with the given name already exists"
- "Cannot find virtual switch"
- "Not enough memory on the host"
- Windows 11 — "Operating system not found" with consumer ISO
- `Show-LabDeploymentSummary` has no `-Detailed` parameter
- VMs have no internet / `Test-LabMachineInternetConnectivity` returns `$false`
- Lab deployment hangs
- "Access denied" on Invoke-LabCommand
- `Import-Lab` required in every new terminal session
- Cleaning up a failed deployment
- "Network adapter already part of a network bridge" (Azure VM hosts)
- WinRM session becomes unresponsive after software installs

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

