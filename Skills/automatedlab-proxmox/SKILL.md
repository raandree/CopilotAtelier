---
name: automatedlab-proxmox
description: >-
  Diagnoses AutomatedLab Windows provisioning and remoting failures on
  Proxmox/QEMU from API, guest-agent, Windows Setup, and WinRM evidence.
  Separates deploy-time AppX cleanup from unusable generalized templates.
  USE FOR: AutomatedLab Proxmox, Install-Lab Proxmox hang, Windows could not
  start the installation process, IMAGE_STATE_UNDEPLOYABLE,
  IMAGE_STATE_COMPLETE, pre-sysprepped template, generalized template,
  specialized golden image, BiExportStoreAlterationsToEfi, c000000d, qm
  template, Sysprep AppX 0x80073cf2, guest-exec-status, qmpstatus,
  New-LabPSSession port is closed, NetworkAdapterBindingCorrected, stale
  AutomatedLabCore/AutomatedLabWorker. DO NOT USE FOR: Hyper-V lab deployment
  (use automatedlab-deployment), generic WinRM diagnosis (use
  winrm-troubleshooting), generic job monitoring (use long-running-job-monitor).
---

# AutomatedLab Proxmox troubleshooting

Diagnose Proxmox-backed AutomatedLab failures from correlated evidence, then
make the smallest guarded change and verify it against a live Windows guest.

## When to use

- `Install-Lab` stalls or emits only progress dots on Proxmox.
- Windows Server succeeds but a Windows client fails Sysprep or OOBE.
- A clone's first boot shows an **Install Windows** dialog saying "Windows
  could not start the installation process," or the supplied template may be
  pre-generalized or stuck in a failed Sysprep state.
- `New-LabPSSession` reports a closed port during or after a guest restart.
- QEMU `guest-exec` starts a process but its final result is unknown.
- A patched AutomatedLab module appears installed but a live shell runs old
  code.
- A Proxmox task reports a warning even though the VM may have reached its
  intended state.

## Outcome

Produce a timestamped root-cause account, a focused regression guard, and live
evidence that the affected Windows guest reaches the required protocol and
final state without destroying diagnostic evidence.

## Dependencies and safety

- Require access to the AutomatedLab source and installed module paths.
- Require read access to the Proxmox API and QEMU guest agent.
- Use an alternate channel when WinRM is unavailable: QEMU guest agent,
  Proxmox API, console, or another hypervisor-side control plane.
- Preserve failed VMs and Windows setup logs until the cause is established.
- Never start a supplied Proxmox template directly. Inspect its configuration
  without power-on, then boot a throwaway clone for image-state evidence.
- Never classify a VM from orchestrator output alone.
- Use `long-running-job-monitor` for the monitoring mechanics and status format.

## Workflow

### 1. Pin the failing run

Record the exact command, process start time, module paths and versions, lab
name, VM IDs, guest addresses, and log paths. Determine whether the shell was
already running when module files were replaced.

### 2. Build a multi-plane timeline

Collect timestamped state from each independent plane:

1. Orchestrator: process liveness, current AutomatedLab phase, warning/error
   stream, and terminal marker.
2. Hypervisor: Proxmox task result, VM `status`, QEMU `qmpstatus`, uptime, and
   restart time.
3. Guest agent: availability, command PID, `guest-exec-status`, exit code, and
   signal state.
4. Template image: API configuration plus a throwaway clone's `ImageState` and
  Sysprep/Panther logs; never power on the original template.
5. Windows setup: Panther, Sysprep, setup activity, and setup error logs.
6. Required protocol: TCP 5985/5986, `Test-WSMan`, SSH, HTTP, or another service
   the next orchestration step actually consumes.

Do not infer one plane from another. A running QEMU process does not prove
Windows readiness; ping does not prove WinRM readiness.

### 3. Classify before changing code

- Process alive with target state or a real phase milestone changing: `WORKING`.
- Target state and real phase milestone unchanged beyond the phase threshold:
  `STALLED`, even when synthetic heartbeats continue. Collect evidence before
  stopping only the orchestrator process.
- QEMU command PID returned but no final status: process creation only; poll
  `guest-exec-status`.
- VM restarted and ping returned but the required port is closed: current boot
  is not ready; keep remoting-dependent work behind a readiness gate.
- AutomatedLab reached its own Sysprep and logs `0x80073cf2`: classify this as
  the deploy-time per-user AppX mismatch handled by guarded cleanup.
- A clone enters OOBE before answer-file injection, shows "Windows could not
  start the installation process," or reports `IMAGE_STATE_UNDEPLOYABLE`:
  classify the supplied template as pre-generalized or incompletely
  generalized. This is a template-build failure, not an AppX-cleanup failure.
- Windows setup logs contain the first concrete failure: fix that guest-side
  cause rather than adding retries to the orchestrator.

When template deployability is in doubt:

1. Read the powered-off template configuration through the Proxmox API.
2. Clone it to a throwaway VM and boot only the clone.
3. Use the QEMU guest agent to read `Setup\State\ImageState` and the Sysprep
   Panther logs.
4. Destroy the probe clone after evidence capture and confirm the original
   template remained untouched.

For command/result semantics and restart ordering, read
[`references/evidence-and-readiness.md`](references/evidence-and-readiness.md).

### 4. Fix the smallest owning path

Move to the nearest function that directly controls the failing ordering,
state transition, or command result. Avoid suppressing warnings, blanket
retries, and catch-and-continue behavior.

Maintain these invariants:

- A successful QEMU `guest-exec` request means process creation, not success.
- AutomatedLab owns `/generalize /oobe`; its Proxmox template must be a
  specialized, non-sysprepped golden image with a usable `ImageState`.
- A deliberate restart invalidates every readiness observation from the prior
  boot.
- Remoting-dependent repair runs only after readiness for the current boot.
- Initialization state is a bitmask; add flags with bitwise OR.
- A Proxmox task warning is nonfatal only when a fresh state query proves the
  intended postcondition.
- Reload changed dependency modules explicitly in long-lived PowerShell
  sessions.
- Capability guards verify the required behavior, not a correlated proxy.

For Windows Sysprep/AppX diagnosis, read
[`references/windows-sysprep.md`](references/windows-sysprep.md).
For build, reload, and installed-artifact checks, read
[`references/module-development.md`](references/module-development.md).

### 5. Guard the behavior

Write focused tests that fail without the change. For restart/network repair,
cover at least:

- call order: `start -> wait -> repair`;
- preservation of existing initialization flags;
- idempotent skip when repair is already recorded;
- serialized metadata forms returned by the live provider.

Do not weaken nonblocking `-Wait:$false` semantics implicitly. If a no-wait
path remains exposed to the race, record it as a residual risk or design a
separate contract change.

### 6. Verify live

Use a controlled restart of one existing test guest before a full deployment:

1. Back up VM metadata.
2. Clear only the flag needed to force the target path.
3. Restart through the real AutomatedLab command with readiness enabled.
4. Observe the interval where VM-running or ping may precede the required
   protocol.
5. Require a zero exit marker and absence of the original warning.
6. Confirm all expected metadata flags remain set.
7. Open a direct session and verify the remote service state.
8. Rebuild from current source and compare the artifact hash with the installed
   module that passed the live test.

For a template-build failure, replace the restart test with a fresh throwaway
clone probe, rebuild the template without pre-running Sysprep, then require
AutomatedLab's own Sysprep gate to reach `IMAGE_STATE_COMPLETE`.

## Edge cases

- Metadata may serialize a flags enum as comma-separated names. Cast it back to
  the enum before integer masking; never cast the combined string directly to
  `Int32`.
- A control-channel disconnect is not guest-process failure. Reconnect through
  an independent plane and read the remote process result.
- If the full repository build is unavailable, derive the concatenation order
  from the repository build task. Do not assume an order from memory.
- Keep plaintext lab credentials out of reusable scripts and skill examples.
- Preserve unrelated user edits and running VMs while testing a module patch.

## Anti-rationalization

| Rationalization | Reality |
| --- | --- |
| "The VM is running, so Windows is ready." | Hypervisor power state does not prove guest protocol readiness. |
| "Ping works, so WinRM is broken." | Ping commonly returns before TCP 5985 after reboot. Probe the protocol and timeout boundary. |
| "guest-exec returned a PID, so Sysprep succeeded." | A PID proves only process creation. Require terminal status and exit data. |
| "The tags and hardware are correct, so the template is fine." | Template discovery is not deployability. Read `ImageState` from a throwaway clone. |
| "Import-Module -Force loaded the patch." | A parent reload can retain already-loaded dependency modules. Verify command source and behavior. |
| "The warning is harmless." | Prove the intended postcondition with a fresh target query before accepting it. |

## Red flags

- Repair or remoting starts immediately after a deliberate restart.
- A task warning is ignored without a fresh VM/QEMU state query.
- A metadata assignment replaces a flags enum instead of OR-ing a flag.
- A live test reports success without a direct protocol session.
- Installed and source module hashes differ after the claimed verification.
- The supplied template is powered on instead of a disposable probe clone.
- The failed VM is deleted before setup and guest-agent evidence is collected.

## Verification

Before reporting done, require:

- focused tests green in an isolated PowerShell process;
- changed PowerShell files parse with zero errors;
- no new ScriptAnalyzer findings relative to the repository baseline;
- live controlled restart exits zero;
- original warning absent from captured output;
- direct protocol session succeeds after the restart;
- final VM metadata preserves all prior flags;
- installed artifact hash matches the current source build;
- when a template is implicated, its probe clone records `ImageState` and
  Panther evidence before teardown, while the original remains untouched.

## Evals

Real-session regression prompts and deterministic pass criteria live in
[`notes-evals.md`](notes-evals.md).
