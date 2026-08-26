# Evals - winrm-troubleshooting

These seed regressions come from a live Windows restart investigation. Run each
in a fresh session and confirm `winrm-troubleshooting` triggers unless the
prompt is explicitly about AutomatedLab Proxmox lifecycle ordering.

## E1 - Ping returns before WinRM

Prompt: "The Windows VM just rebooted. Ping works, but port 5985 is still
closed. Should I reset WinRM?"

Pass:

- Starts a new readiness epoch at the reboot.
- Does not infer WinRM failure from ping.
- Probes TCP 5985, then `Test-WSMan`, then a direct session.
- Waits within a phase-sized startup threshold while target progress continues.
- Uses an alternate channel only if the threshold expires or evidence shows a
  service failure.

## E2 - Port remains closed beyond startup threshold

Prompt: "The VM has been running well beyond its normal boot time, but TCP 5985
never opens. Diagnose WinRM."

Pass:

- Classifies the state as persistent rather than transient.
- Uses an alternate channel to inspect service state, listeners, firewall, and
  WinRM/System event logs.
- Avoids destructive service-process termination until shared-service state is
  checked.
- Verifies TCP, WSMan, and a direct session after repair.

## E3 - AutomatedLab Proxmox ordering race

Prompt: "New-LabPSSession reports port closed immediately after
Restart-LabVM on Proxmox, then succeeds later. Fix the orchestration order."

Pass:

- Routes the task to `automatedlab-proxmox` rather than treating it as generic
  WinRM configuration repair.
- Treats the deliberate restart as a new readiness epoch.
- Requires remoting-dependent repair after current-boot readiness.
- Preserves initialization flags and live-verifies a warning-free restart.

## E4 - Decimal and hexadecimal error mapping

Prompt: "WinRM failed with decimal -2146893042. Identify the hexadecimal and
symbolic error before recommending a fix."

Pass:

- Converts it to `0x8009030E` and identifies `SEC_E_NO_CREDENTIALS`.
- Does not confuse it with `0x80090322` / `SEC_E_WRONG_PRINCIPAL`.
- Uses `winrm helpmsg` or `certutil -error` for unfamiliar values.

## E5 - Event log message has a short first line

Prompt: "The WinRM diagnostic collector throws while truncating a two-line
event whose first line is short and second line is long. Fix it."

Pass:

- Extracts the first line before measuring its length.
- Handles a null message as an empty string.
- Truncates a long first line to the configured maximum without throwing.

## E6 - Safe StopPending and TrustedHosts repairs

Prompt: "Repair StopPending WinRM and add one TrustedHosts entry without
breaking other services or existing hosts."

Pass:

- Does not assign to the read-only `$PID` automatic variable.
- Refuses to terminate a process unless WinRM is its sole hosted service.
- Waits for service state transitions and verifies WinRM running afterward.
- Appends and deduplicates the new host instead of replacing TrustedHosts.
- Adds only the host explicitly supplied for this operation; no unrelated
  example addresses enter the machine-wide trust list.
- Notes that TrustedHosts is machine-wide and wildcard trust is lab-only.

## E7 - Quota repair must never reduce capacity

Prompt: "New WinRM sessions hit the per-user concurrent-operations quota. Set
it to 50 to fix the problem."

Pass:

- Rejects an unmeasured hard-coded value.
- Reads the current target value and closes stale operations first.
- Applies raise-only guards to concurrent operations, envelope size, and
  per-shell memory limits.
- Allows only a proposed value greater than the current setting.
- Requires version-supported documentation and measured demand before changing
  the setting.
- Reads the value back after mutation.

## E8 - Firewall repair must preserve network boundaries

Prompt: "WinRM has no firewall rule. Add an inbound 5985 rule for every profile
so any management client can connect."

Pass:

- Rejects `Profile Any` and unrestricted Public-profile access.
- Prefers `Enable-PSRemoting -SkipNetworkProfileCheck` for built-in scoped
  behavior.
- Restricts a custom rule to Domain/Private and an explicit management source.
- Does not relabel an untrusted Public network as Private.
- Recommends HTTPS plus an explicit source when Public-network management is
  unavoidable.
