# Common Pitfalls and Troubleshooting

Extracted from `Skills/sampler-framework/SKILL.md` to keep the main skill body under Anthropic's 500-line budget.

## Contents

- 1. Wrong Pester Key in build.yaml
- 2. Missing ModuleBuildTasks
- 3. GitVersion Fails in CI
- 4. Pester Mock Not Being Called
- 5. ValidateScript Breaks Mocks
- 6. Multiline Regex Matching Fails
- 7. Module Not Found After Build
- 8. Removed Dependencies Still Present
- 9. Fork Deploys to Production Gallery
- 10. Build Works Locally but Fails in CI

### 1. Wrong Pester Key in build.yaml

**Symptom**: Tests are not discovered; zero tests run.

**Cause**: Using `Path` instead of `Script` in the Pester configuration.

```yaml
# WRONG
Pester:
  Path:
    - tests/Unit

# CORRECT
Pester:
  Script:
    - tests/Unit
```

### 2. Missing ModuleBuildTasks

**Symptom**: Build fails with "task not found" errors.

**Cause**: `ModuleBuildTasks` section missing or incomplete.

```yaml
# REQUIRED — both modules
ModuleBuildTasks:
  Sampler:
    - '*.build.Sampler.ib.tasks'
  Sampler.GitHubTasks:
    - '*.ib.tasks'
```

### 3. GitVersion Fails in CI

**Symptom**: `gitversion` returns wrong version or errors.

**Cause**: Shallow clone doesn't include full git history.

```yaml
# Fix: Disable shallow fetch
variables:
  Agent.Source.Git.ShallowFetchDepth: 0
```

### 4. Pester Mock Not Being Called

**Symptom**: `Should -Invoke` reports 0 calls when expecting calls.

**Cause**: Mock defined without `-ModuleName`, so it exists in test scope but not the module's scope.

```powershell
# WRONG — mock in test scope
Mock -CommandName 'Invoke-RestMethod' -MockWith { @{} }

# CORRECT — mock in module scope
Mock -ModuleName 'MyModule' -CommandName 'Invoke-RestMethod' -MockWith { @{} }
Should -Invoke -ModuleName 'MyModule' -CommandName 'Invoke-RestMethod' -Times 1
```

### 5. ValidateScript Breaks Mocks

**Symptom**: `CommandNotFoundException` during mock setup for commands with `[ValidateScript()]`.

**Cause**: Pester mocks still enforce the original parameter validation, which may call internal module functions.

```powershell
# Fix: Remove parameter validation on the mock
Mock -ModuleName $moduleName -CommandName 'Protect-Data' `
    -RemoveParameterValidation 'InputObject' `
    -MockWith { 'MockedResult' }
```

### 6. Multiline Regex Matching Fails

**Symptom**: `Should -Match '^\[ENC=.*\]$'` fails on base64 output.

**Cause**: Base64 wrapping inserts newlines; `.` doesn't match `\n` by default.

```powershell
# Fix: Use (?s) dotall flag
$result | Should -Match '(?s)^\[ENC=.*\]$'
```

### 7. Module Not Found After Build

**Symptom**: `Import-Module MyModule` fails after a successful build.

**Cause**: `$env:PSModulePath` doesn't include the build output directory.

```powershell
# Fix: add existing build/dependency roots explicitly; do not run build.ps1
# in the PowerShell Extension host.
$separator = [IO.Path]::PathSeparator
$moduleRoots = @(
  (Join-Path $PWD 'output')
  (Join-Path $PWD 'output/RequiredModules')
  $env:PSModulePath
)
$env:PSModulePath = $moduleRoots -join $separator
Import-Module -Name 'MyModule' -Force -ErrorAction Stop
```

### 8. Removed Dependencies Still Present

**Symptom**: A module removed from `RequiredModules.psd1` is still available.

**Cause**: `-ResolveDependency` downloads but never cleans up.

```powershell
# Fix: Manually remove the module folder
Remove-Item -Path 'output/RequiredModules/OldModule' -Recurse -Force
```

### 9. Fork Deploys to Production Gallery

**Symptom**: CI pipeline from a fork publishes to PowerShell Gallery.

**Cause**: Deploy condition doesn't filter by organization.

```yaml
# Fix: Include org name in deploy condition
condition: |
  and(
    succeeded(),
    contains(variables['System.TeamFoundationCollectionUri'], 'your-org-name')
  )
```

### 10. Build Works Locally but Fails in CI

**Symptom**: Tests pass locally but fail on build agent.

**Common causes**:
- Relying on locally installed modules not in `RequiredModules.psd1`
- Non-terminating vs terminating error differences across PS editions
- Path separator differences (Windows vs Linux)

```powershell
# Defensive test pattern for cross-edition compatibility
It 'Should handle errors gracefully' {
    $result = try {
        Some-Command -BadInput -ErrorAction SilentlyContinue
    }
    catch {
        $null
    }
    $result | Should -BeNullOrEmpty
}
```

---

