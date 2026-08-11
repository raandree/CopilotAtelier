---
status: current
last-verified: 2026-08-11
owner: software-engineer
source: current task evidence
---

# Active context

## Current focus

Return `main` to green after the CI matrix went red on the Linux and macOS
test legs.

## Implemented

- `tests/LongRunningJobMonitor.Tests.ps1` — the cancellation test now splats
  `Start-Process` and adds `WindowStyle` only on Windows; the script path uses
  forward slashes so `pwsh -File` resolves it on every platform.
- `.memory-bank/activeContext.md` — curated from 135 lines, restoring headroom
  on the routing reduction gate.

## Focused evidence

- The failure was platform-specific, not content-specific: `Start-Process
  -WindowStyle` raises `NotSupportedException` on non-Windows PowerShell. The
  Windows leg passed, so a local Windows run could never reproduce it. The CI
  `PesterObject_*.xml` artifact carried the message the NUnit XML dropped.
- `Skills/long-running-job-monitor/scripts/Start-DetachedPowerShell.ps1` already
  guarded the same parameter behind `[PlatformID]::Win32NT`. The test was
  written without that guard, and only the cross-platform matrix could catch it.
- The preceding commit failed for a different reason worth remembering: the
  routing gate reported `49.57 %` against the `50 %` floor documented in
  `decisions/0014-prove-memory-bank-routing.md`. Measured headroom is roughly
  **1 KB** — one ordinary append to `activeContext.md` breaks it, because that
  file is routed into 23 of 25 baseline cases while the decision records that
  dominate the full-read baseline are not.
- Verified: `./build.ps1 -Tasks test` green on Windows; the routing evaluator
  clears the 50 % floor with the curation applied.
- Left uncommitted on `main` at the user's request.

## Open finding

`Prompts/export-emails.prompt.md` in this repository is a generation behind the
copy deployed under `~/.copilot/prompts/` — 106 lines against 126. The deployed
version parameterises the export script with `-PersonNames` and `-FolderSlug`,
derives patterns from email addresses as well as names, and carries a rule
forbidding hardcoded names in the prompt, in commits, and in scratch files. None
of that exists here. A build and install would therefore regress a working
Prompt. Back-porting is a content decision and was left to the owner.

## Next step

Give the routing reduction gate real headroom instead of a coin flip: curate the
widely routed core files further, or add a near-limit warning to
`Test-MemoryBankRouting.ps1` mirroring `LineBudgetNearLimit` in
`Test-MemoryBankHealth.ps1`, so drift is reported before CI turns red.

Still outstanding: add the `GitHubToken` repository secret, without which the
deploy job fails at its guard; write evals for `gilb-requirements-engineering`.
