---
applyTo: "**/build.yaml,**/build.ps1,**/RequiredModules.psd1,**/Resolve-Dependency.psd1,**/GitVersion.yml,**/Datum.yml"
---

# Sampler Build Framework — Enforced Rules

These rules auto-apply when editing Sampler build files. For comprehensive
reference (build.yaml schema, CI/CD recipes, DSC patterns, commands reference),
see the **sampler-framework** skill.

---

## Project Structure Rules

- **One function per file** in `source/Public/` and `source/Private/`
- **Filename must match function name** (e.g., `Get-Widget.ps1` contains `function Get-Widget`)
- **`source/<ModuleName>.psm1` must be empty** — ModuleBuilder compiles all source files into it
- **`output/` is ephemeral** — always gitignored; rebuilt from source
- **Classes use numeric prefixes** for load ordering (e.g., `001.BaseClass.ps1`, `002.DerivedClass.ps1`)

---

## Module Manifest Rules

| Rule | Details |
|---|---|
| **Preserve GUID** | The GUID is the PowerShell Gallery identity — never change it after first publish |
| **Explicit exports** | Always list functions explicitly in `FunctionsToExport`; never use `'*'` wildcards |
| **ModuleVersion** | Set to `0.0.1` in source; GitVersion overrides during build |
| **No `#Requires`** | Do not use `#Requires` in source files; declare in `RequiredModules.psd1` instead |
| **PowerShellVersion** | Set to `5.1` unless the module truly requires PowerShell 7+ |
| **Prerelease tag** | Leave empty in source; the build pipeline sets it via `PrivateData.PSData.Prerelease` |

---

## Build Configuration Rules

- **Pester key**: Use `Script` (not `Path`) in the Pester section of `build.yaml`
- **ModuleBuildTasks**: Always include both `Sampler` and `Sampler.GitHubTasks`
- **`build.ps1` and `Resolve-Dependency.ps1`**: Copy verbatim from a reference project — do not modify
- **`output/`**: Must be in `.gitignore`
- **Custom build tasks**: Use `Set-SamplerTaskVariable -AsNewBuild` and the InvokeBuild `property` keyword

---

## Running Builds Safely

### CRITICAL: Avoid Freezing VS Code

> **NEVER** run `./build.ps1`, `Invoke-Pester`, or `Invoke-Build` directly in any
> VS Code terminal — not even via `pwsh -Command "..."`. The terminal synchronously waits
> for the child process, which freezes the entire VS Code UI.
>
> **ALWAYS** use `Start-Process` (fully detached) with log polling. See the
> `powershell-execution-safety.instructions.md` file for the full rationale and common mistakes.
> Log files MUST go to `$env:TEMP`, never to `output/` (Sampler's Clean task deletes it).

### Detached Process with Log Polling

```powershell
# Log MUST go to $env:TEMP (NOT output/ — Sampler Clean deletes it mid-build)
$logPath = "$env:TEMP\sampler_build.log"
Remove-Item $logPath -ErrorAction SilentlyContinue
Start-Process -FilePath pwsh -ArgumentList @(
    '-NoProfile', '-NonInteractive', '-Command',
    "Set-Location '$PWD'; .\build.ps1 -Tasks test *>&1 | Out-File -FilePath '$logPath' -Encoding utf8"
) -WindowStyle Hidden -PassThru

# Poll for completion (non-blocking)
for ($i = 0; $i -lt 120; $i++) {
    Start-Sleep 3
    if (Test-Path $logPath) {
        $c = Get-Content $logPath -Raw -ErrorAction SilentlyContinue
        if ($c -match 'Build (FAILED|succeeded)') {
            Get-Content $logPath -Tail 30
            break
        }
    }
    if ($i % 10 -eq 0) { Write-Host "Waiting... ($($i*3)s)" }
}
```

### Common Task Variants

Replace `-Tasks test` in the snippet above with:

| Task | Purpose |
|---|---|
| `-Tasks build` | Build only (no tests) |
| `-Tasks test` | Run tests only |
| `-ResolveDependency` | First run / dependency update |
| (no `-Tasks`) | Full default workflow (build + test) |

### When to Use -ResolveDependency

| Scenario | Use `-ResolveDependency`? |
|---|---|
| First clone / fresh checkout | **Yes** |
| `RequiredModules.psd1` changed | **Yes** |
| Updating to latest dependency versions | **Yes** |
| Normal iterative development | **No** (if `output/RequiredModules/` is populated) |
| CI/CD build agent (always clean) | **Yes** |

---

## DO / DON'T Quick Reference

### DO

- **DO** use `New-SampleModule` to scaffold new projects
- **DO** place all source code under `source/Public/` and `source/Private/`
- **DO** keep one function per file with matching filename
- **DO** use an empty `.psm1` file (ModuleBuilder populates it)
- **DO** use the `Script` key (not `Path`) in Pester build.yaml configuration
- **DO** include both `Sampler` and `Sampler.GitHubTasks` in `ModuleBuildTasks`
- **DO** use GitVersion for automatic semantic versioning
- **DO** set `Agent.Source.Git.ShallowFetchDepth: 0` in CI
- **DO** test on both PowerShell 7 and Windows PowerShell 5.1
- **DO** run builds via detached `Start-Process` with log polling (see `powershell-execution-safety.instructions.md`)
- **DO** specify `-ModuleName` on all Pester mocks and `Should -Invoke` assertions
- **DO** use `-RemoveParameterValidation` when mocking commands with `[ValidateScript()]`
- **DO** start with `CodeCoverageThreshold: 0` and increase after baseline
- **DO** use `./build.ps1 -Tasks noop` to set up the VSCode session environment
- **DO** add `output/` to `.gitignore`
- **DO** preserve the module GUID when migrating existing modules
- **DO** list functions explicitly in `FunctionsToExport` (no wildcards)
- **DO** use `RequiredModules.psd1` for all dependencies (build and runtime)
- **DO** include deploy conditions with your org name to prevent fork deploys
- **DO** use `Set-SamplerTaskVariable -AsNewBuild` in custom build task files
- **DO** use the InvokeBuild `property` keyword for parameter defaults in task files
- **DO** use conditional task execution (`-if`) for platform-specific tasks
- **DO** configure `.vscode/tasks.json` with problem matchers for Pester test output
- **DO** set `SetPSModulePath.RemovePersonal: true` in DSC projects to isolate module resolution

### DON'T

- **DON'T** use `Path` instead of `Script` in Pester build.yaml config
- **DON'T** use `FunctionsToExport = '*'` in the module manifest
- **DON'T** put `#Requires` statements in individual source files
- **DON'T** run `./build.ps1` directly in any VS Code terminal (including via `pwsh -Command`)
- **DON'T** use `Start-Process -Wait` for build execution in VS Code
- **DON'T** put build log files in `output/` (Sampler Clean deletes them mid-build — use `$env:TEMP`)
- **DON'T** modify `build.ps1` or `Resolve-Dependency.ps1` (copy verbatim)
- **DON'T** commit `output/` to source control
- **DON'T** change the module GUID after publishing to PowerShell Gallery
- **DON'T** define mocks without `-ModuleName` (they won't affect module-scoped calls)
- **DON'T** mix dependency resolution methods in the same session
- **DON'T** assume `-ResolveDependency` removes deleted dependencies
- **DON'T** use shallow git clones in CI (GitVersion needs full history)
- **DON'T** deploy from forks without org-name filtering in conditions
- **DON'T** nest modules inside other modules in multi-module repos
- **DON'T** leave `PSDesiredStateConfiguration` 2.0+ in `output/RequiredModules/` when building on Windows PowerShell 5.1
- **DON'T** mix DSC compilation across PS editions without verifying MOF encoding
