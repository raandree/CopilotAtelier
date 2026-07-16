# Windows Sysprep failure modes

Separate AutomatedLab's deploy-time AppX cleanup from an unusable source
template before changing orchestration.

## Contents

- [Failure-mode decision](#failure-mode-decision)
- [Mode 1 - deploy-time AppX mismatch](#mode-1---deploy-time-appx-mismatch)
- [Mode 2 - pre-generalized or undeployable template](#mode-2---pre-generalized-or-undeployable-template)
- [Validation by mode](#validation-by-mode)

## Failure-mode decision

| Mode | Earliest concrete signal | Owning fix |
| --- | --- | --- |
| Deploy-time AppX mismatch | AutomatedLab has injected its answer file and its own Sysprep logs `0x80073cf2` | Keep the template; run AutomatedLab's narrow, waited AppX cleanup before its Sysprep |
| Pre-generalized or failed template | First boot enters OOBE before injection, shows "Windows could not start the installation process," or reports an unusable `ImageState` | Rebuild the supplied template as a specialized, non-sysprepped golden image |

Do not apply AppX cleanup to repair a broken template contract. Conversely, do
not rebuild a usable specialized template when AutomatedLab's own Sysprep has
reached a concrete per-user AppX mismatch.

## Mode 1 - deploy-time AppX mismatch

### AppX symptom and evidence

Error `0x80073cf2` commonly means Sysprep found an AppX package installed for a
user that is not provisioned consistently for all users. Windows client images
are more likely than server images to acquire Store-updated per-user packages.

Collect these before deleting or rebuilding the VM:

- `%WINDIR%\System32\Sysprep\Panther\setupact.log`
- `%WINDIR%\System32\Sysprep\Panther\setuperr.log`
- `%WINDIR%\Panther\setupact.log`
- `%WINDIR%\Panther\setuperr.log`
- Current AppX provisioned packages and all-user package registrations
- Sysprep process exit data from QEMU `guest-exec-status`

Use the QEMU guest agent or console when WinRM is unavailable.

### Identity comparison

Compare full identities, not package names alone:

- Provisioned tuple: `DisplayName | PublisherId | Version`
- Installed tuple: `Name | PublisherId | Version`

A package is a cleanup candidate only when all are true:

- At least one `PackageUserInformation` entry has `InstallState = Installed`.
- Its full identity is absent from the provisioned identity set.
- `IsFramework` is false.
- `NonRemovable` is false.

Do not remove packages whose only user state is `Staged`. A version mismatch is
a real mismatch even when package name and publisher match.

### Fail-closed cleanup

Run cleanup as a waited QEMU guest process before launching Sysprep. If cleanup
fails, do not start Sysprep.

One narrow stale-registration case can be tolerated:

- Outer AppX deployment HRESULT is `0x80073CFA` (`-2147009286`).
- The exception message contains inner file-not-found code `0x80070002`.

This means the registration remains but its payload is already absent. Rethrow
every other removal error, including access denied or a different inner code.

### AutomatedLab Sysprep invocation

Pass the generated answer file explicitly:

```powershell
C:\Windows\System32\Sysprep\sysprep.exe /generalize /oobe /reboot /unattend:C:\Unattend.xml
```

The sequence is:

1. Encode and launch cleanup with `-Wait`.
2. Require cleanup exit code zero.
3. Launch Sysprep with `/generalize /oobe /reboot` and explicit `/unattend`.
4. Require the launch request itself to succeed.
5. Observe reboot and final Windows state independently.

### AppX regression coverage

Cover these behaviors:

- Cleanup runs before Sysprep and is waited.
- User-installed unprovisioned packages are removed.
- A provisioned/installed version mismatch is removed.
- Matching identities are retained.
- Staged-only, framework, and nonremovable packages are retained.
- Only `0x80073CFA` plus inner `0x80070002` is tolerated.
- Any other cleanup error prevents Sysprep launch.
- Sysprep command contains the explicit answer-file path.
- Guest execution surfaces nonzero exit, signal, missing exit code, and timeout.

## Mode 2 - pre-generalized or undeployable template

### AutomatedLab template contract

The Proxmox provider consumes an existing template; it does not install from an
ISO. The source path is:

1. `New-LWProxmoxVM` calls `Get-LWProxmoxVmTemplate`.
2. Template lookup requires `template = 1` and tags containing the normalized
   operating-system name plus literal `template`.
3. `New-PveNodesQemuClone` creates the VM clone.
4. AutomatedLab saves its `Unattend.xml`, starts the clone, and waits for the
   QEMU Guest Agent.
5. It pushes `C:\Unattend.xml`, sets `SkipRearm`, and runs:

   ```text
   sysprep.exe /generalize /oobe /reboot /unattend:C:\Unattend.xml
   ```

6. `New-LabVM` accepts the result only when
   `Get-LWProxmoxVMSysprepState` returns `IMAGE_STATE_COMPLETE`.

The shipped answer file in `Initialization.ps1` contains only `generalize`,
`specialize`, and `oobeSystem` passes, with no `windowsPE` pass. AutomatedLab
therefore owns generalization. Its source template must be a specialized,
non-sysprepped golden image.

### Setup symptom and ground truth

The distinct template failure appears on first boot as a dialog titled
**Install Windows** with this message:

```text
Windows could not start the installation process.
```

Read this registry value through a throwaway clone, never by starting the
original template:

```text
HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Setup\State\ImageState
```

| `ImageState` | AutomatedLab meaning |
| --- | --- |
| `IMAGE_STATE_COMPLETE` | Deployable and usable |
| `IMAGE_STATE_UNDEPLOYABLE` | Failed or incomplete Sysprep; unusable |
| `IMAGE_STATE_SPECIALIZE_RESEAL_TO_OOBE` | Pre-generalized toward OOBE; unusable for this provider contract |

A pre-generalized clone boots into OOBE before AutomatedLab can inject its
answer file and run its own Sysprep. A failed or incomplete Sysprep can prevent
first-boot Setup from starting at all.

### Confirmed UEFI and BCD failure example

Template VM ID 131, `AL-W10-Sysprepped`, met every discovery precondition:

- `template=1`;
- tags `windows10enterprise;template`;
- `virtio-scsi-single` and a VirtIO `net0`;
- `agent=1` and `bios=ovmf`;
- VirtIO drivers ISO still mounted.

A throwaway clone nevertheless reported
`ImageState = IMAGE_STATE_UNDEPLOYABLE`. Four generalize attempts in
`C:\Windows\System32\Sysprep\Panther\setuperr.log` failed with:

```text
BCD: BiExportStoreAlterationsToEfi failed c000000d
Failed to export alterations to firmware
```

`c000000d` is `STATUS_INVALID_PARAMETER`: a UEFI/BCD write failure during
Sysprep. Correct tags and virtual hardware proved discovery only; they did not
prove image deployability.

### Template remediation

Build the Proxmox template as a specialized golden image:

1. Install Windows, VirtIO drivers, and the QEMU Guest Agent.
2. Apply required patches and leave Windows specialized; audit mode is valid.
3. Do not run Sysprep.
4. Shut down the VM.
5. Add tags `<normalized-os>;template`.
6. Run `qm template <vmid>`.
7. Keep exactly one matching template per operating system;
   `Get-LWProxmoxVmTemplate` fails on zero or multiple matches.

If another workflow truly requires a pre-generalized capture, repair the
UEFI/BCD `c000000d` failure first and prove a clean `ImageState`. Do not supply
that capture to AutomatedLab's Proxmox provider.

## Validation by mode

For the AppX mode, do not stop at process launch. Verify:

- Sysprep state is complete.
- OOBE completed.
- The cached answer file exists when expected.
- The machine has the expected identity and address.
- WinRM is running and reachable.

For the template mode, verify:

- the original template was never started;
- the throwaway probe captured `ImageState` and both Sysprep Panther logs;
- the probe clone was destroyed only after evidence capture;
- a clone of the rebuilt specialized template starts with
  `IMAGE_STATE_COMPLETE` and lets AutomatedLab perform its own Sysprep.
