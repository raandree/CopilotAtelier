# Active context

## Current work focus

The AutomatedLab Proxmox knowledge port into the canonical Copilot Atelier
repository is complete on `ai/port-proxmox-knowledge`. The final refinement
keeps `Invoke-Pester`, `Invoke-Build`, and build entry points fully detached on
Windows and non-Windows systems without foreground polling. The working tree is
deliberately uncommitted and unstaged per the user's instruction.

## Final implementation state

- `Start-DetachedPowerShell.ps1` is the single launch implementation:
  `Start-Process` on Windows and `sh` plus `nohup` on non-Windows systems.
- A detached supervisor runs the encoded payload in an inner `pwsh`, writes
  `ResultPath` as `0` for success or `1` for failure, and preserves explicit
  nonzero exits as well as thrown failures.
- Detached callers return `ProcessId`, `LogPath`, and `ResultPath`; an absent
  result file means no completion result is available yet. Status is read only
  on demand, with no agent-side sleep or polling loop.
- Direct and configured Pester payloads propagate `FailedCount`; tagged runs
  use `TagFilter`; configuration runs use `Run.PassThru` and `Run.Exit`.
- Sampler and VS Code wrappers use GUID-scoped logs, preserve apostrophe/space
  paths, log full child errors, and delegate launch semantics to the helper.
- Encoded monitor probes contain the PowerShell body without surrounding
  script-block braces. The sidecar rejects the ambiguous outer-braced form with
  a targeted error and enforces one `Summary` / `Liveness` / `ProgressToken`
  object.

## Verification

- All 135 Markdown files lint clean; `git diff --check` passes.
- Both executable scripts have zero AST parse errors, zero ScriptAnalyzer
  warnings/errors, and CRLF line endings.
- 530 executable PowerShell fences, four PowerShell files, and 28 JSON task
  surfaces contain zero foreground Pester/build commands.
- Helper markers pass success, throw, and explicit-exit cases (`0`, `1`, `1`).
- Detached direct/configured Pester failures produce `ResultPath=1` and log the
  failed count.
- VS Code wrapper success/failure cases produce `ResultPath=0/1`, including an
  apostrophe path.
- The Windows helper and Git-sh `nohup` strategy pass; the latter records `1`
  for intentional `exit 9`.
- The detached monitor passes shared heartbeat, token, liveness, target,
  terminal-marker, and `ResultPath=0` checks.
- Independent security review reports no Blocker or Major findings.

## Next step

The user reviews the uncommitted diff and explicitly requests a commit when
ready. Do not stage, commit, or push before that request.
