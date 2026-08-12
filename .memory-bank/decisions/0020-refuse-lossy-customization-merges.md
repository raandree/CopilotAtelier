---
status: accepted
date: 2026-08-11
last-verified: 2026-08-11
owner: software-engineer
source: Set-CustomizationLink review findings, reproduced 2026-08-11
---

# Refuse a lossy customization merge instead of resolving it

## Context and problem statement

`Set-CustomizationLink` replaces a discovery folder such as `~/.copilot/skills`
with a link to the canonical target. When that folder is a real directory
holding real content, the content has to go somewhere first.

Three review findings were recorded against how it did that and deferred. All
three still reproduced on 2026-08-11 against the committed implementation:

- It asked `Read-Host` before replacing a non-empty directory. The function is
  reachable unattended through the shipped `Update-CopilotAtelier -Force` path,
  where a prompt does not fail — it waits forever on a host with no console.
- A child present in both the directory and the target was skipped, and then
  destroyed by the `Remove-Item -Recurse` that followed. Measured: a file
  holding `deployed copy, 126 lines` was gone after the merge and only
  `repository copy, 106 lines` remained. The Memory Bank records exactly this
  drift in the wild, where the deployed copy was the newer one.
- `Copy-Item -Recurse` followed a reparse point inside the directory. Measured:
  a junction pointing outside the tree was materialised inside the target as
  real content.

The second finding needs a policy, not just a repair. When a child exists in
both places and differs, something has to win.

## Decision outcome

**Anything that cannot be merged without losing content stops the merge, and
nothing is copied or removed.** One rule covers all three findings.

- **The opt-in is a parameter, not a prompt.** `-Force` on
  `Set-CustomizationLink`, surfaced on `Install-CopilotAtelier` and
  `Setup-CopilotSettings.ps1`. Without it a non-empty directory is left alone
  and the message names `-Force`. An unattended caller therefore either supplies
  the switch or is told what to supply; it can no longer hang, and a first run
  over a populated profile no longer removes anything by default.

- **A differing child stops the merge; neither copy is touched.** Rejected
  alternatives: *newest wins* depends on a timestamp that any editor or sync
  client can move and would silently overwrite the canonical copy; *source
  always wins* silently destroys whichever side is not chosen, which is the
  defect being fixed. Refusing is the only outcome that loses nothing, and the
  report names every conflicting child so the user can reconcile and re-run.

- **Equality is proven, not assumed.** A child already present in the target is
  dropped only when both sides are files with the same length and the same
  SHA-256. A directory on either side counts as a conflict: proving a whole tree
  equal costs more than asking a human to look, and this merge runs once per
  profile.

- **A reparse point is never followed and never copied.** A child that is a
  reparse point, or that contains one at any depth, stops the merge. Validating
  where each link lands was rejected: the safe set is hard to define, and the
  intent — copy this tree, and only this tree — is expressible directly by
  refusing.

## Consequences

- A profile that has drifted needs one manual reconciliation before the link is
  created. That is the intended cost: the alternative is silent data loss, and
  the drift is real rather than hypothetical.
- `Install-CopilotAtelier` gains a `-Force` switch, so the first run over an
  existing profile can now report "skipped" where it previously prompted. That
  is a visible behaviour change for interactive users, who must now re-run with
  `-Force` instead of answering `y` in-flight.
- `Test-CustomizationChildMatch` exists solely as the equality oracle above, so
  the policy has one place to change.
- Seven tests in `tests/Unit/Private/Set-CustomizationLink.Tests.ps1` cover the
  three findings. They create real junctions on Windows and real symbolic links
  elsewhere, neither of which needs elevation, so the reparse-point cases are
  exercised rather than skipped.

## Confirmation

All seven tests fail against the previous implementation and pass against this
one. Two throwaway reproductions measured the loss directly before the fix: a
child holding `deployed copy, 126 lines` was gone after the merge, leaving only
`repository copy, 106 lines`; and a junction inside the folder was materialised
inside the target as real content. Against the fix the first survives untouched
and the second is not copied at all. `./build.ps1 -Tasks build, test` is green.
