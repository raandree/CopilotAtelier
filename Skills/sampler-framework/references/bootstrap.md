# Bootstrap Process (build.ps1)

Extracted from `Skills/sampler-framework/SKILL.md` to keep the main skill body under Anthropic's 500-line budget.

## Contents

- What build.ps1 Does
- Common Invocations
- Why a Separate Process?
- When to Use -ResolveDependency

The `build.ps1` script is the entry point for all build operations. It bootstraps the environment without assuming any pre-existing setup.

### What build.ps1 Does

1. **Updates `$env:PSModulePath`** — prepends `output/` and `output/RequiredModules/` so build dependencies are discoverable
2. **(Optional) Ensures PowerShellGet v2+** — only if using legacy PowerShellGet
3. **Downloads bootstrap modules** — `PowerShell-yaml` and `PSDepend`
4. **Reads `build.yaml`** — loads the build configuration
5. **Installs NuGet provider** — if not present (proxy-aware)
6. **Resolves dependencies** — downloads modules listed in `RequiredModules.psd1` to `output/RequiredModules/`
7. **Invokes build tasks** — hands off to `Invoke-Build` to run the requested workflow

### Common Invocations

> **CRITICAL**: Never run `./build.ps1` directly inside the VS Code integrated terminal's
> current PowerShell session. The build process imports modules, invokes Pester, and runs
> long-lived tasks that can **block the PowerShell extension thread and freeze VS Code**.
> Always invoke `build.ps1` in a **new, isolated `pwsh` process**.

```powershell
# First run: resolve dependencies + full default workflow
pwsh -NoProfile -NonInteractive -Command './build.ps1 -ResolveDependency'

# Build only (skip tests)
pwsh -NoProfile -NonInteractive -Command './build.ps1 -Tasks build'

# Test only (module must already be built)
pwsh -NoProfile -NonInteractive -Command './build.ps1 -Tasks test'

# Build and package as NuGet
pwsh -NoProfile -NonInteractive -Command './build.ps1 -Tasks pack'

# Bootstrap environment without doing anything (useful for IDE setup)
pwsh -NoProfile -NonInteractive -Command './build.ps1 -Tasks noop'

# Resolve dependencies only
pwsh -NoProfile -NonInteractive -Command './build.ps1 -ResolveDependency -Tasks noop'

# List all available tasks
pwsh -NoProfile -NonInteractive -Command './build.ps1 -Tasks ?'

# Run specific test file
pwsh -NoProfile -NonInteractive -Command "./build.ps1 -Tasks test -PesterPath 'tests/Unit/Public/Get-Widget.tests.ps1' -CodeCoverageThreshold 0"

# Run specific test folder
pwsh -NoProfile -NonInteractive -Command "./build.ps1 -Tasks test -PesterPath 'tests/QA' -CodeCoverageThreshold 0"

# Run integration tests (not included in default test workflow)
pwsh -NoProfile -NonInteractive -Command "./build.ps1 -Tasks test -PesterPath 'tests/Integration' -CodeCoverageThreshold 0"
```

### Why a Separate Process?

| Problem | Cause | Solution |
|---|---|---|
| VS Code hangs during build | `build.ps1` blocks the PowerShell extension thread | `pwsh -NoProfile -Command './build.ps1 ...'` |
| Module state leaks between builds | `Import-Module -Force` in-process may not fully unload assemblies | A new process starts clean |
| Stale `$env:PSModulePath` | Previous build runs prepend paths that accumulate | `-NoProfile` starts with a default `PSModulePath` |
| Pester `InModuleScope` deadlocks | Locking conflicts with the language server | Isolated process avoids shared locks |

### When to Use -ResolveDependency

| Scenario | Use `-ResolveDependency`? |
|---|---|
| First clone / fresh checkout | **Yes** |
| `RequiredModules.psd1` changed | **Yes** |
| Updating to latest dependency versions | **Yes** |
| Normal iterative development | **No** (if `output/RequiredModules/` is populated) |
| CI/CD build agent (always clean) | **Yes** |

> **Note**: `-ResolveDependency` downloads but never removes. If you remove a module from `RequiredModules.psd1`, manually delete it from `output/RequiredModules/`.

---

