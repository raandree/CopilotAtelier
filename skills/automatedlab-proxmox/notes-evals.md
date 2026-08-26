# Evals - automatedlab-proxmox

These regression cases come from the July 2026 Windows 10 Proxmox incident.
Run each in a fresh session, confirm `automatedlab-proxmox` triggers, and grade
against the deterministic pass criteria.

## E1 - Windows client stalls while server succeeds

Prompt: "AutomatedLab on Proxmox deploys Server 2025, but Windows 10 sits on
dots during unattended setup. Investigate without deleting the VM."

Pass:

- Preserves the failed VM and captures a timestamped deployment log.
- Checks Proxmox/QEMU state independently of controller output.
- Retrieves Sysprep/Panther logs through the guest agent or console.
- Uses the first concrete Windows setup error to drive the fix.
- Does not add retries or rebuild the VM before collecting evidence.

## E2 - QEMU command returned a process identifier

Prompt: "Proxmox guest-exec returned PID 42, so can I assume AppX cleanup
finished and start Sysprep?"

Pass:

- Answers no: a PID proves process creation only.
- Requires `guest-exec-status` until `exited = 1`.
- Rejects signal termination, missing exit code, nonzero exit code, and timeout.
- Preserves executable switches and quoted arguments.

## E3 - VM start task returned a warning

Prompt: "Start-PveVm completed with WARNINGS. Should Install-Lab fail?"

Pass:

- Performs a fresh, no-cache VM query.
- Accepts the warning only when `status` and `qmpstatus` are both `running`.
- Otherwise surfaces a terminating start failure containing the warning.

## E4 - Ping works after reboot but WinRM is closed

Prompt: "New-LabPSSession says port 5985 is closed after a deliberate restart,
but the machine already answers ping. Fix the orchestration race."

Pass:

- Treats the restart as a new readiness epoch.
- Explains that ICMP can recover before WinRM.
- Places remoting-dependent repair after `Wait-LabVM` for the waited path.
- Tests `start -> wait -> repair`, bit preservation, and idempotent skip.
- Live-verifies absence of the warning and opens a direct session.

## E5 - Installed patch is not active

Prompt: "The installed AutomatedLabWorker hash matches my build, but the
running deployment says the private command has no Wait parameter."

Pass:

- Suspects a long-lived shell retaining dependency modules.
- Checks module path, command source, and command capabilities.
- Explicitly removes/reimports affected dependencies from disk.
- Uses a capability guard before any hypervisor mutation.
- Verifies the installed artifact in a fresh process.

## E6 - Combined initialization flags fail integer conversion

Prompt: "Get-LWVMDescription returns 'EnabledCredSsp,
NetworkAdapterBindingCorrected'. Clearing one bit by casting directly to Int32
throws. How should the test mutate it?"

Pass:

- Casts the serialized value to `AutomatedLab.LabVMInitState` first.
- Applies the integer mask only after enum conversion.
- Adds flags with bitwise OR rather than replacement.
- Verifies both `EnabledCredSsp` and `NetworkAdapterBindingCorrected` afterward.

## E7 - AppX cleanup must be narrow and fail closed

Prompt: "Sysprep fails with 0x80073cf2 on Windows 10. Write the cleanup rules
without removing staged, framework, or provisioned packages."

Pass:

- Compares `Name/DisplayName`, `PublisherId`, and `Version` identities.
- Removes only packages installed for a user, absent from the provisioned set,
  removable, and non-framework.
- Retains staged-only and matching provisioned packages.
- Tolerates only outer `0x80073CFA` with inner `0x80070002`.
- Prevents Sysprep launch on every other cleanup failure.
- Uses `/unattend:C:\Unattend.xml` explicitly.

## E8 - Build and guard a patched dependency module

Prompt: "The full AutomatedLab build is unavailable. Build the patched core,
install it safely, and prove the deployment will run the fixed ordering."

Pass:

- Reads the repository build task and derives the current concatenation order.
- Parses and imports the temporary artifact with runtime dependencies present.
- Backs up the installed module and compares SHA-256 hashes.
- Reloads affected Core/Worker dependencies in a fresh or cleaned process.
- Guards actual `Wait-LabVM`-before-repair behavior, not a correlated edit.
- Rebuilds current source after live validation and matches the installed hash.

## E9 - No-wait callers retain their contract

Prompt: "Moving Proxmox repair after Wait-LabVM fixes Start-LabVM -Wait. Should
the same patch silently block callers that did not request -Wait?"

Pass:

- Answers no: adding a wait changes the nonblocking contract.
- Records the no-wait path as a residual race when left unchanged.
- Requires a separate design and test change before altering no-wait behavior.
- Does not claim the waited-path fix covers every caller.

## E10 - Supplied template enters broken OOBE

Prompt: "AutomatedLab cloned my Proxmox Windows template, but first boot shows
an Install Windows dialog saying 'Windows could not start the installation
process.' The template tags and VirtIO hardware look correct. Diagnose it
without destroying evidence."

Pass:

- Separates AutomatedLab's deploy-time AppX `0x80073cf2` cleanup from a
    pre-generalized or failed-Sysprep source template.
- States that AutomatedLab clones a Proxmox template and runs its own
    `/generalize /oobe /unattend:C:\Unattend.xml`; the source must therefore be a
    specialized, non-sysprepped golden image.
- Never starts the original template. Reads its powered-off API configuration,
    boots a throwaway clone, and uses the QEMU Guest Agent to collect
    `ImageState`, `setuperr.log`, and `setupact.log`.
- Treats `IMAGE_STATE_COMPLETE` as usable and rejects
    `IMAGE_STATE_UNDEPLOYABLE` or `IMAGE_STATE_SPECIALIZE_RESEAL_TO_OOBE`.
- Preserves the failed AutomatedLab VM and probe logs until evidence is
    captured, then destroys only the throwaway clone and confirms the source
    template is untouched.
- Recommends rebuilding the template with Windows, VirtIO drivers, and QEMU
    Guest Agent installed, without pre-running Sysprep, then tagging it
    `<normalized-os>;template` and converting it with `qm template <vmid>`.
