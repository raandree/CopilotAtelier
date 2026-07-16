# Post-restart WinRM readiness

Distinguish the expected service-start window after reboot from a persistent
WinRM failure before changing configuration.

## Start a new readiness epoch

Every restart invalidates successful sessions and probes from the prior boot.
Pin the restart or boot timestamp, then observe the current boot independently.

A normal recovery sequence can be:

1. Hypervisor reports the VM running.
2. Guest agent responds.
3. ICMP ping succeeds.
4. TCP 5985 or 5986 opens.
5. `Test-WSMan` succeeds.
6. Authentication and a direct PowerShell session succeed.

Each stage proves only itself. Ping does not prove a WinRM listener, and an open
port does not prove WSMan protocol or authentication readiness.

## Classify transient versus persistent

Treat the state as transient startup when all are true:

- A restart occurred recently.
- Hypervisor or guest evidence shows forward progress.
- The elapsed time remains inside the expected service-start threshold.
- No alternate-channel evidence shows WinRM is disabled or failed.

Treat it as a WinRM failure when one is true:

- The phase-sized threshold expires with no protocol progress.
- An alternate channel shows the WinRM service stopped, disabled, or failed.
- No listener exists after the service reports running.
- Event logs show a persistent listener, HTTP.sys, firewall, or authentication
  error.

Do not use a fixed global timeout. Size the threshold to the guest, update
phase, and observed boot history.

## Probe in dependency order

```powershell
$target = '<ServerNameOrAddress>'

Test-Connection -ComputerName $target -Count 1 -Quiet
Test-NetConnection -ComputerName $target -Port 5985
Test-WSMan -ComputerName $target
Invoke-Command -ComputerName $target -ScriptBlock { hostname }
```

If WinRM is still unavailable, inspect the target through an independent
channel such as PowerShell Direct, QEMU guest agent, console, or out-of-band
management.

## Orchestration rules

- Place remoting-dependent work after readiness for the current boot.
- Do not reuse a pre-restart PSSession as evidence.
- Do not repair WinRM merely because ping returned first.
- Do not hide startup races with blanket retries or warning suppression.
- Preserve nonblocking semantics when a caller intentionally omits waiting;
  changing that contract requires a separate design decision.

For `New-LabPSSession` ordering on Proxmox-backed AutomatedLab guests, use
`automatedlab-proxmox`. That skill covers `Wait-LabVM`, network repair, VM
initialization flags, and controlled live validation.

## Verification

Require all of these before declaring recovery:

- TCP listener reachable.
- `Test-WSMan` successful.
- Direct PowerShell session successful.
- Remote WinRM service is `Running` and start type is appropriate.
- Original warning absent from the controlled restart output.
- No pre-restart session or readiness result was reused.
