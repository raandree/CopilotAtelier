# Evidence and readiness

Use independent control planes to separate orchestration failures from guest
failures and transient startup windows.

## Evidence matrix

| Plane | Evidence | What it proves |
| --- | --- | --- |
| Orchestrator | Process, phase, timestamps, captured streams | The controller is alive and where it is waiting |
| Proxmox | Task result, VM `status`, QEMU `qmpstatus`, uptime | Hypervisor-side state only |
| Guest agent | Agent response, process PID, terminal status | Guest-side command lifecycle without WinRM |
| Template image | Powered-off API configuration plus throwaway-clone `ImageState` and Sysprep logs | Template discovery and image deployability as separate facts |
| Windows | `ImageState`, Sysprep/Panther/setup logs, boot time, service state | Operating-system cause and current boot |
| Protocol | TCP probe, `Test-WSMan`, direct session | The next remote operation can actually run |

Never substitute one plane for another. Correlate them by timestamp.

## QEMU guest execution contract

A successful `guest-exec` request returns a process identifier. It does not
prove the process completed or succeeded.

When ordering depends on completion:

1. Preserve executable switches and quoted arguments when converting the
   command string to QEMU's argument array.
2. Submit `guest-exec` and require a successful API response.
3. Poll `guest-exec-status` for that process identifier until `exited = 1` or
   the explicit timeout expires.
4. Treat a status-query failure as fatal.
5. Treat a nonempty `signal` as fatal.
6. Require an `exitcode` property with a nonempty value.
7. Convert the exit code to an integer and require zero.
8. Include `err-data`, falling back to `out-data`, in the error record.

Tests must cover success, missing VM, failed launch, preserved switches,
nonzero exit code, signal termination, missing exit code, and timeout.

## Proxmox task warnings

Do not treat either `OK` or `WARNINGS:` as the final truth. Query the target
again without cache and test the intended postcondition.

For VM start, accept a warning only when both are true:

- VM `status` is `running`.
- QEMU `qmpstatus` is `running`.

Otherwise surface the warning as a terminating start failure. Apply the same
pattern to other tasks using the postcondition appropriate to that operation.

## Template image state and non-destructive probing

Treat Windows `ImageState` as a first-class readiness signal. Correct tags and
hardware prove that `Get-LWProxmoxVmTemplate` can discover a template; they do
not prove that Windows can complete AutomatedLab's generalize/specialize/OOBE
sequence.

Never start the supplied template directly. Starting it can consume or alter
its OOBE state. Use this evidence pattern instead:

1. Read the powered-off template configuration through the Proxmox API. Record
   `template=1`, normalized OS plus `template` tags, VirtIO SCSI/NIC, `agent`,
   `ostype`, and UEFI/BIOS settings.
2. Clone the template to a uniquely named throwaway VM and boot only the clone.
3. Through the QEMU Guest Agent, read
   `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Setup\State\ImageState` and
   tail `Sysprep\Panther\setuperr.log` plus `setupact.log`.
4. Preserve any failed AutomatedLab VM until its setup evidence is collected.
5. Destroy the throwaway clone, then query the original template again to
   confirm it remained powered off and unchanged.

Interpret the registry signal directly:

- `IMAGE_STATE_COMPLETE`: deployable and usable.
- `IMAGE_STATE_UNDEPLOYABLE`: failed or incomplete Sysprep; reject it.
- `IMAGE_STATE_SPECIALIZE_RESEAL_TO_OOBE`: pre-generalized toward OOBE; reject
  it for AutomatedLab's Proxmox provider.

The pass condition is not merely a booting clone. It is a usable image state,
captured Panther evidence when unusable, cleanup of the disposable probe, and
an untouched source template.

## Restart-scoped readiness

Every deliberate restart creates a new readiness epoch. Discard successful
ping, WinRM, guest-agent, and session observations from the prior boot.

A common Windows sequence is:

1. Proxmox reports QEMU running.
2. ICMP ping returns.
3. TCP 5985 opens.
4. `Test-WSMan` succeeds.
5. `New-LabPSSession` opens and authentication completes.

Run remoting-dependent repair only after the required step for the current
boot. In `Start-LabVM -Wait`, the safe order is `start -> Wait-LabVM -> repair`.

Do not silently add blocking behavior to a no-wait path. Treat that as a
separate API-contract decision and document any residual race.

## Initialization metadata

`LabVMInitState` is a flags enum. Provider metadata may serialize it as a
single name or comma-separated names.

- Test membership with bitwise AND.
- Add a flag with bitwise OR.
- Never replace the whole value when recording one completed action.
- Cast a serialized flags string back to `LabVMInitState` before integer masks.
- Do not cast a comma-separated enum string directly to `Int32`.

Regression tests should use both `EnabledCredSsp` and
`EnabledCredSsp, NetworkAdapterBindingCorrected` serialized forms.

## Controlled live test

Force only the path under test:

1. Back up metadata.
2. Clear only `NetworkAdapterBindingCorrected` while preserving other bits.
3. Restart one guest through `Restart-LabVM -Wait`.
4. Capture all output and scan for the original warning.
5. Verify the final flags.
6. Open a direct `New-LabPSSession` and query WinRM status and start type.

The pass condition is end-to-end: controller exit zero, warning absent,
metadata preserved, and direct remoting successful.
