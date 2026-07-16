# Active context

## Current work focus

The AutomatedLab Proxmox knowledge port now includes the supplied-template
failure mode diagnosed from vmid 131. During validation, the repository moved
externally to `main` at `a819777` (`origin/main`), which already contains the
updated skill body and E10. The remaining reference and record refinements are
deliberately unstaged and uncommitted.

## Final implementation state

- The skill separates AutomatedLab's deploy-time AppX `0x80073cf2` cleanup
  from a pre-generalized or failed-Sysprep source template.
- The Proxmox provider contract now states that AutomatedLab clones a
  specialized, non-sysprepped golden image, injects its answer file, runs its
  own Sysprep, and gates on `IMAGE_STATE_COMPLETE`.
- Template diagnosis reads powered-off configuration, boots only a throwaway
  clone, captures `ImageState` and Panther logs through the QEMU Guest Agent,
  then destroys the probe while confirming the source template is untouched.
- The Windows reference records the vmid 131 structural preconditions and
  `BiExportStoreAlterationsToEfi failed c000000d` UEFI/BCD evidence.
- Remediation installs VirtIO drivers and QEMU Guest Agent but does not run
  Sysprep before tagging and `qm template`; exactly one template may match each
  operating system.
- External scripts poll public `Get-LWProxmoxVM ... -NoCache` state rather than
  calling internal `Wait-LWProxmoxTasksStatus`.
- E10 deterministically requires contract identification, safe clone probing,
  failed-VM evidence preservation, and specialized-template rebuilding.

## Verification

- The five requested skill files lint with zero errors.
- The description is third-person and 834 characters; `SKILL.md` is 223 total
  lines with a 207-line body.
- Every reference over 100 lines has a direct `Contents` map.
- Deterministic semantic assertions cover all requested contract, evidence,
  safety, remediation, scope, trigger, and eval requirements.
- Fresh read-only review reports no Blocker or Major findings; its duplicated
  state-definition minor was resolved by giving the exact table one owner.

## Next step

The user reviews the remaining uncommitted diff. Do not switch branches, stage,
commit, or push without a new explicit request.
