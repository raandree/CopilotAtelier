---
name: sampler-build-debug
description: >-
  Debug and troubleshoot Sampler-based PowerShell module builds and Pester 5 test failures.
  Covers running builds safely (without freezing VSCode), reading Pester results, diagnosing
  common mock/assertion failures, and fixing tests.
  USE FOR: build fails, test fails, Pester errors, troubleshoot build, debug tests, run build,
  Sampler build, module build, Pester mock issues, VSCode freezes during build.
  DO NOT USE FOR: creating new modules from scratch, Azure deployments, CI/CD pipeline config.
---

# Sampler Build & Test Debugging

Skill for troubleshooting Sampler-based PowerShell module builds and Pester 5 test failures.

## When to Use

- Build fails with test errors
- Pester tests fail and need diagnosis
- VSCode becomes unresponsive during builds
- Mock-related test failures (parameter validation, missing commands)
- Need to run builds safely from the integrated terminal

## Running Builds Without Freezing VSCode

**CRITICAL**: Never run `./build.ps1` directly inside the VS Code integrated terminal's
current PowerShell session. The build process imports modules, invokes Pester, and runs
long-lived tasks that can **block the PowerShell extension thread and freeze VS Code**.
Always invoke `build.ps1` in a **new, isolated `pwsh` process**.

### Recommended: Detached Process with Log Polling

**IMPORTANT**: Even `pwsh -NoProfile -NonInteractive -Command '...'` can still hang the
VS Code terminal because the terminal synchronously waits for the child process to exit.
If Pester or the build framework writes output that interacts badly with VS Code's terminal
renderer or the PowerShell Extension Host's pipe, the terminal freezes. **Always use
`Start-Process` (fully detached)** — it creates a process with no parent-child pipe, so
VS Code's terminal never blocks on it.

```powershell
# 1. Start build detached — log MUST go to $env:TEMP (NOT output/!)
#    Sampler's Clean task deletes everything in output/ and will lock/fail the build.
$logPath = "$env:TEMP\sampler_build.log"
Remove-Item $logPath -ErrorAction SilentlyContinue
Start-Process -FilePath pwsh -ArgumentList @(
    '-NoProfile', '-NonInteractive', '-Command',
    "Set-Location '$PWD'; .\build.ps1 -Tasks test *>&1 | Out-File -FilePath '$logPath' -Encoding utf8"
) -WindowStyle Hidden -PassThru

# 2. Poll for completion (non-blocking)
for ($i = 0; $i -lt 120; $i++) {
    Start-Sleep 3
    if (Test-Path $logPath) {
        $c = Get-Content $logPath -Raw -ErrorAction SilentlyContinue
        if ($c -match 'Build (FAILED|succeeded)') {
            Get-Content $logPath -Tail 25
            break
        }
    }
    if ($i % 10 -eq 0) { Write-Host "Waiting... ($($i*3)s)" }
}
```

### Key Rules

- **Log files go to `$env:TEMP`**, NEVER to `output/` (Sampler Clean task deletes it mid-build).
- **Skip `-ResolveDependency`** if `output/RequiredModules/` already exists and is populated.
- Use `-Tasks test` to run only tests, not the full build pipeline.
- Use `-Tasks build` to rebuild the module without running tests.

## Source & Test File Encoding — UTF-8 **with BOM** Required

Sampler's QA test suite includes a `Missing BOM encoding for non-ASCII encoded file`
check. All files under `source/` and `tests/` that contain any non-ASCII byte
**must** be saved as UTF-8 **with BOM**.

**Trap**: In PowerShell 7.x, `Set-Content -Encoding UTF8` writes a **BOM-less**
file (the default changed from Windows PowerShell 5.1). This silently breaks
Sampler QA. The failure message looks like:

```text
Expected 'UTF8 BOM' encoding for file 'MyFunction.ps1', but got
Missing BOM encoding for non-ASCII encoded file 'MyFunction.ps1'.
```

**Fix** — always use the explicit `utf8BOM` encoding when writing source/test files:

```powershell
# Wrong (pwsh 7): produces BOM-less UTF-8, breaks Sampler QA
Set-Content -Path 'source/Public/MyFunction.ps1' -Value $content -Encoding UTF8

# Correct
Set-Content -Path 'source/Public/MyFunction.ps1' -Value $content -Encoding utf8BOM

# Bulk re-save an existing tree
Get-ChildItem -Path source,tests -Recurse -Include *.ps1,*.psm1,*.psd1,*.ps1xml |
    ForEach-Object {
        $c = Get-Content -LiteralPath $_.FullName -Raw
        Set-Content -LiteralPath $_.FullName -Value $c -Encoding utf8BOM -NoNewline
    }
```

Files containing only ASCII bytes pass the check regardless of BOM, but any
em-dash, smart-quote, umlaut, or non-ASCII comment character will fail without
a BOM. Save everything with BOM unconditionally.

## Diagnosing Test Failures

### Step 1: Read the Pester Object

The richest failure data is in the serialized Pester object, not the log file:

```powershell
$pesterFile = Get-ChildItem 'output\testResults\PesterObject_*.xml' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$pester = Import-Clixml $pesterFile.FullName
$pester.Failed | ForEach-Object {
    Write-Host "TEST: $($_.ExpandedName)" -ForegroundColor Red
    $_.ErrorRecord | Out-String | Write-Host
}
```

### Step 2: Check the NUnit XML for CI-style Output

```powershell
$nunit = Get-ChildItem 'output\testResults\NUnitXml_*.xml' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
[xml]$xml = Get-Content $nunit.FullName
$xml.SelectNodes('//test-case[@result="Failed"]') | ForEach-Object {
    "$($_.fullname): $($_.failure.message)"
}
```

### Step 3: Read the Summary from the Log

```powershell
Select-String -Path 'output\test.log' -Pattern 'tests\.ps1|Total run time' |
    ForEach-Object { $_.Line.Trim() }
```

## Common Pester 5 Mock Issues

### Problem: ValidateScript Calls Internal Functions

**Symptom**: `CommandNotFoundException` for functions like `Get-ProtectedDataSupportedType`
or `Test-IsProtectedData` when mocking `Protect-Data` or `Unprotect-Data` from the
ProtectedData module.

**Cause**: Pester mocks replace the function body but still enforce the original command's
`[ValidateScript()]` parameter attributes. If those attributes call module-internal functions,
they fail because the internal functions aren't exported.

**Fix**: Use `-RemoveParameterValidation` on the mock:

```powershell
Mock -ModuleName $moduleName -CommandName Protect-Data `
    -RemoveParameterValidation 'InputObject' `
    -MockWith { 'ProtectedBlob' }

Mock -ModuleName $moduleName -CommandName Unprotect-Data `
    -RemoveParameterValidation 'InputObject' `
    -MockWith { 'DecryptedSecret' }
```

### Problem: Regex Doesn't Match Multiline Base64

**Symptom**: `Should -Match '^\[ENC=.*\]$'` fails even though the output looks correct.

**Cause**: `Protect-Datum` wraps base64 at `MaxLineLength` (default 100), inserting `\r\n`.
The `.` metacharacter does not match newlines by default.

**Fix**: Use the `(?s)` dotall flag:

```powershell
$result | Should -Match '(?s)^\[ENC=.*\]$'
```

### Problem: Mock Not Being Called

**Symptom**: `Should -Invoke` fails with "Expected X calls but got 0".

**Cause**: Mock is defined without `-ModuleName`, so it's scoped to the test, not the module.
When the module's function calls `Protect-Data`, it resolves to the real command, not the mock.

**Fix**: Always specify `-ModuleName` matching the module under test:

```powershell
Mock -ModuleName 'Datum.ProtectedData' -CommandName Unprotect-Data -MockWith { 'value' }
# ... call the function ...
Should -Invoke -ModuleName 'Datum.ProtectedData' -CommandName Unprotect-Data -Times 1
```

## Sampler Build Tasks Reference

| Task | Purpose |
|---|---|
| `.\build.ps1 -Tasks noop` | Bootstrap only — resolve dependencies, no build |
| `.\build.ps1 -Tasks build` | Compile the module to `output/builtModule/` |
| `.\build.ps1 -Tasks test` | Build + run all Pester tests |
| `.\build.ps1 -Tasks pack` | Build + create NuGet package |
| `.\build.ps1 -ResolveDependency` | Force re-download of all RequiredModules |

## Project-Specific Notes

- **Module**: Datum.ProtectedData (GUID: `132c634a-1fe1-40f7-b327-5e723a0b23b2`)
- **Runtime dependency**: `ProtectedData` (Dave Wyatt) — must be available for mocks to work
- **Test structure**: `tests/QA/module.tests.ps1` (58 quality tests) + `tests/Unit/Public/*.tests.ps1`
- **Build output**: `output/builtModule/Datum.ProtectedData/<version>/`
- **Code coverage**: Currently disabled (`CodeCoverageThreshold: 0` in `build.yaml`)
