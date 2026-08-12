---
name: pester-patterns
compatibility: Requires PowerShell 5.1+ with Pester 5.
description: >-
  Common Pester 5 test patterns and recipes for PowerShell module testing.
  Covers mocking file systems, REST APIs, DSC resources, databases, credentials,
  and other external dependencies. Provides ready-to-use test templates for
  common scenarios.
  USE FOR: Pester test patterns, mock file system, mock REST API, mock database,
  test DSC resource, test credentials, parametrized tests, Pester recipes,
  test template, testing patterns, how to test, mock example, run Pester,
  invoke tests, VS Code hang, separate process.
  DO NOT USE FOR: debugging failing builds (use sampler-build-debug),
  migrating to Sampler (use sampler-migration), general Pester syntax
  (covered by pester.instructions.md).
---

# Pester 5 Test Patterns & Recipes

Ready-to-use test patterns for common PowerShell testing scenarios using Pester 5.

## When to Use

- You need to mock an external dependency (file system, REST API, database, etc.)
- You need a test template for a specific scenario
- You want proven patterns for testing complex PowerShell code
- You need to test credential handling, DSC resources, or async operations
- You need to run Pester tests without hanging VS Code

## Pattern 0: Run Tests via the Fully Detached Launcher

> **CRITICAL**: Running Pester inside VS Code's integrated PowerShell session — **or even
> via `pwsh -NoProfile -Command { ... }`** — can cause VS Code to hang or become completely
> unresponsive. The terminal synchronously waits for the child process and Pester output
> can stall the pipe. Always use the canonical fully detached launcher.

Use the encoded cross-platform wrapper in
[`powershell-execution-safety.instructions.md`](../../Instructions/powershell-execution-safety.instructions.md).
It creates GUID-scoped `$env:TEMP` log/result files and returns `ProcessId`,
`LogPath`, and `ResultPath`.

Choose one of these as the inner child payload; never run a fragment in the
current PowerShell session:

```text
# All tests
$result = Invoke-Pester -Path './tests' -Output Detailed -PassThru
if ($result.FailedCount -gt 0) { throw "Pester failed $($result.FailedCount) test(s)." }

# One file
$result = Invoke-Pester -Path './tests/Unit/Get-Widget.Tests.ps1' -Output Detailed -PassThru
if ($result.FailedCount -gt 0) { throw "Pester failed $($result.FailedCount) test(s)." }

# One tag
$result = Invoke-Pester -TagFilter 'Unit' -Output Detailed -PassThru
if ($result.FailedCount -gt 0) { throw "Pester failed $($result.FailedCount) test(s)." }

# Sampler test workflow
.\build.ps1 -Tasks test
```

For a full configuration, set `$config.Run.PassThru = $true` and
`$config.Run.Exit = $false`, capture `$result = Invoke-Pester -Configuration
$config`, then throw when `$result.FailedCount` is greater than zero. Do not use
`-PassThru` with `-Configuration`; they are different parameter sets.

### Key Rules

- **Log files go to unique paths under `$env:TEMP`**, never the project root or
    Sampler `output/`.
- **Always use `-WindowStyle Hidden`** to prevent a visible console flash.
- Return `ProcessId`, `LogPath`, and `ResultPath`; inspect them only on demand.
- Never add a foreground `Start-Sleep` polling loop.

### Why This Matters

| Problem | Cause |
|---|---|
| VS Code freezes with `pwsh -Command` | Terminal synchronously waits for child; Pester output stalls the pipe |
| VS Code freezes with in-process Pester | Blocks the PowerShell extension's thread |
| Module state leaks between runs | `Import-Module -Force` in-process may not fully unload assemblies |
| `InModuleScope` deadlocks | Locking conflicts with the language server |
| Stale `$Error` / breakpoints | Previous debug sessions pollute the session |

Detached-execution regression prompts live in
[`notes-evals.md`](notes-evals.md).

## Recipes

Patterns 0 and 14 apply to every Pester run, so they stay here. Patterns 1 to
13 apply only to whichever dependency or construct a given test happens to
touch, so they live one level down and keep their numbers.

| Reference | Patterns | Covers |
|---|---|---|
| [`references/mocking-external-dependencies.md`](references/mocking-external-dependencies.md) | 1-3 | Mocking the file system and `TestDrive`, `Invoke-RestMethod` and `Invoke-WebRequest` including paginated responses, `PSCredential` and `SecureString` |
| [`references/testing-powershell-constructs.md`](references/testing-powershell-constructs.md) | 4-13 | Class-based and MOF-based DSC resources, PowerShell classes, pipeline functions, `ErrorVariable` and warning and verbose streams, dates and times, `ShouldProcess`, environment variables, module exports, private functions, external test fixtures |

## Pattern 14: Helpers Used Inside `It` Must Live in `BeforeAll`

### The problem

Pester 5 runs each `It` block in an **isolated runspace**. Helper functions defined as siblings of `It` blocks inside `Describe` are not visible inside `It`. The symptom is the same on every test:

```text
CommandNotFoundException: The term 'Get-MarpSlide' is not recognized as a name
of a cmdlet, function, script file, or executable program.
```

It looks like a typo or a missing dot-source. It's neither — it's runspace isolation.

### The broken pattern

```powershell
Describe 'X' {
    # WRONG — not visible inside It
    function Get-Thing { ... }
    function Test-Thing { ... }

    It 'works' {
        Get-Thing | Should -Not -BeNullOrEmpty   # CommandNotFoundException
    }
}
```

### The fix

Define helpers inside `BeforeAll`. The `BeforeAll` block runs once and its definitions are available to every `It` in the `Describe`. Use `$script:` scope for any state the tests should share.

```powershell
Describe 'X' {
    BeforeAll {
        $script:fixtureDir = $PSScriptRoot

        function Get-Thing { ... }
        function Test-Thing { ... }
    }

    It 'works' {
        Get-Thing | Should -Not -BeNullOrEmpty   # works
    }
}
```

### Related gotchas

- Same rule for variables — use `$script:foo` in `BeforeAll`, not bare `$foo`, or it won't survive into `It`.
- For data needed by `-ForEach` on `It`, define it in `BeforeDiscovery`, not `BeforeAll` — `-ForEach` is resolved at discovery time, before `BeforeAll` runs.
- Don't avoid the issue by writing helpers as inline scriptblocks inside every `It` — that's the cargo-cult workaround, not the fix.

## Quick Reference: Mock Cheat Sheet

| What to Mock | Mock Command | Key Detail |
|---|---|---|
| File I/O | `Mock Get-Content`, `Mock Set-Content` | Use TestDrive for real files |
| File existence | `Mock Test-Path -MockWith { $true }` | Use `-ParameterFilter` for specific paths |
| REST API | `Mock Invoke-RestMethod` | Return `[PSCustomObject]` |
| HTTP call | `Mock Invoke-WebRequest` | Return object with `StatusCode`, `Content` |
| Date/time | `Mock Get-Date` | Return fixed `[datetime]` |
| Registry | Use `TestRegistry:` | Windows only |
| Services | `Mock Get-Service` | Return object with `Name`, `Status` |
| Processes | `Mock Get-Process` | Return object with `Name`, `Id`, `CPU` |
| Module command | `Mock -ModuleName X -CommandName Y` | Always match `-ModuleName` on `Should -Invoke` |
| Throwing mock | `Mock X -MockWith { throw ... }` | Use typed exceptions |
| Void mock | `Mock X` (no `-MockWith`) | Returns nothing |
