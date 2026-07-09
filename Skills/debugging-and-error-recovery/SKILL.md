---
name: debugging-and-error-recovery
description: >-
  A disciplined general debugging workflow for PowerShell/DSC code, builds, and
  tests: reproduce, localize, reduce to a minimal case, fix the root cause, then
  guard with a regression test. Stop-the-line on a red build; fix causes not
  symptoms; never swallow an error to make a failure disappear. A language-neutral
  method with PowerShell tactics (`-ErrorAction Stop`, `try/catch`,
  `Get-PSCallStack`).
  USE FOR: debugging, how to debug, systematic debugging, reproduce the bug,
  isolate the failure, root cause analysis, minimal repro, bisect a regression,
  flaky test, intermittent failure, error handling strategy, stop the line,
  regression guard, works on my machine, heisenbug.
  DO NOT USE FOR: DSC resource failures on a node (use dsc-troubleshooting),
  WinRM connectivity (use winrm-troubleshooting), Sampler build or Pester failure
  diagnosis (use sampler-build-debug), whether a long job is stuck (use
  long-running-job-monitor), security review (use agent-security-review).
---

# Debugging & Error Recovery

A repeatable method for turning a failure into a fix without guessing. Domain-neutral, with PowerShell tactics. For a specific stack, hand off to the domain playbook: [`dsc-troubleshooting`](../dsc-troubleshooting/SKILL.md), [`winrm-troubleshooting`](../winrm-troubleshooting/SKILL.md), or [`sampler-build-debug`](../sampler-build-debug/SKILL.md).

## When to Use

- A test, build, or script fails and the cause is not yet understood.
- A bug is reported but not yet reproduced.
- A failure is intermittent, or "only on CI / only on their machine".
- You are tempted to add a retry, a `try/catch`, or `-ErrorAction SilentlyContinue` to make a symptom disappear.

## The loop: Reproduce → Localize → Reduce → Fix → Guard

1. **Reproduce.** Get a deterministic repro before changing anything. Pin the exact command, inputs, module versions, and environment. If it fails only sometimes, find the condition that makes it fail every time (order, data, culture, timezone, path). No repro means no fix, only hope.
2. **Localize.** Narrow down where it breaks. Read the full error and the call stack (`Get-PSCallStack`, `$_.ScriptStackTrace`); do not skim the first line. Bisect: disable half the input or config, or `git bisect` across commits, until the fault sits between a known-good and known-bad point.
3. **Reduce.** Strip the repro to the smallest case that still fails — remove unrelated modules, data, and steps. The minimal case usually names the cause by itself and becomes the seed for the regression test.
4. **Fix the root cause.** Fix the cause, not the symptom. A `$null` you guard with a check is a symptom; where the `$null` came from is the cause. Suppressing the error (empty `catch`, `SilentlyContinue`, blanket retry) hides the bug and ships it.
5. **Guard.** Add a test that fails without the fix and passes with it (see [`test-driven-development`](../test-driven-development/SKILL.md)). The bug is not fixed until a test would catch its return.

## Stop-the-line

A red build or a failing test is a full stop, not a warning to work around. Do not layer new work on a broken base, and do not comment out or `-Skip` a failing test to get green — that discards the signal. Fix it, or revert to the last green commit, then proceed.

## Do not swallow errors

Make failures loud so they stay debuggable:

- Set `-ErrorAction Stop` (or `$ErrorActionPreference = 'Stop'`) on operations that must not silently continue, and wrap them in `try/catch` that handles or rethrows — never an empty `catch {}`.
- `-ErrorAction SilentlyContinue` is for expected, handled absences (a probe that may return nothing), never a tool to mute a real error.
- Preserve context on rethrow (`throw` inside `catch`, or `$PSCmdlet.ThrowTerminatingError($_)`); do not replace a rich error record with a bare string.

See [`powershell.instructions.md`](../../Instructions/powershell.instructions.md) for the repo's error-handling rules.

## Tactics for PowerShell

- `Set-PSDebug -Trace 1` for line-by-line tracing; `Set-PSDebug -Off` after.
- `Write-Debug` with `-Debug`, or breakpoints (`Set-PSBreakpoint`, VS Code F9), over scattered `Write-Host`.
- Inspect the whole error record: `$_ | Format-List * -Force`, `$_.Exception.InnerException`, `$_.ScriptStackTrace`.
- For a hang, capture the stack of the stuck runspace rather than killing it blind.

## Flaky and intermittent failures

Treat a flaky test as a real defect, not noise. Common causes: hidden order dependency between tests, shared mutable state, real time or sleep, culture or timezone assumptions, unseeded randomness, network reliance. Force determinism (fix the seed, inject the clock, isolate state) until it fails every time, then debug it normally. Never paper over flake with a retry loop.

## Anti-rationalization table

| Rationalization | Reality |
|---|---|
| "I see the fix, no need to reproduce." | Without a repro you cannot prove the fix works or that you found the real bug. Reproduce first. |
| "Wrapping it in try/catch fixes it." | Catching an error hides the cause; the bug still exists. Trace it to its origin. |
| "It's just flaky, re-run it." | Flake is a defect with a hidden cause. A re-run is not a fix. |
| "Too small to add a regression test." | The bug already escaped once. The test is what stops it escaping twice. |

## Red flags

- Editing code before you can reproduce the failure on demand.
- Reading only the first line of the error, not the stack trace.
- A new `try/catch`, `SilentlyContinue`, or retry appears and the failure "goes away".
- A failing test is `-Skip`ped, commented out, or its assertion weakened.
- "Fixed" with no test that fails without the change.

When a red flag fires, stop and return to the step you skipped — most often Reproduce or Guard.

## Verification

Done under this skill means:

- A deterministic reproduction existed before the fix.
- The root cause is named, not just the symptom masked.
- A regression test fails without the fix and passes with it; the suite is green, run in a separate process per [`powershell-execution-safety.instructions.md`](../../Instructions/powershell-execution-safety.instructions.md).
- The change clears the [Definition of Done](../../Reference/definition-of-done.md).

## Related

- [`sampler-build-debug`](../sampler-build-debug/SKILL.md), [`dsc-troubleshooting`](../dsc-troubleshooting/SKILL.md), [`winrm-troubleshooting`](../winrm-troubleshooting/SKILL.md) — domain-specific playbooks.
- [`test-driven-development`](../test-driven-development/SKILL.md) — writing the regression guard.
- [`long-running-job-monitor`](../long-running-job-monitor/SKILL.md) — deciding whether a long job is stuck or working.
