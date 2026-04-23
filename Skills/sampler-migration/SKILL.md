---
name: sampler-migration
description: >-
  Step-by-step guide for migrating a legacy PowerShell module project to the Sampler build
  framework. Covers migrating from AppVeyor, PSDepend, PSDeploy, Pester 4, and other legacy
  build systems to full Sampler scaffolding with ModuleBuilder, InvokeBuild, Pester 5,
  GitVersion, and Azure Pipelines.
  USE FOR: migrate to Sampler, Sampler setup, new Sampler project, legacy module migration,
  PSDepend to Sampler, AppVeyor to Sampler, PSDeploy to Sampler, Pester 4 to Pester 5,
  Sampler project structure, Sampler conventions.
  DO NOT USE FOR: debugging existing Sampler builds (use sampler-build-debug), Azure deployments,
  CI/CD pipeline config outside of Sampler.
---

# Sampler Migration Skill

## Description

Step-by-step guide for migrating a legacy PowerShell module project to the
[Sampler](https://github.com/gaelcolas/Sampler) build framework. Sampler is a
PowerShell module scaffolding and build automation system that uses ModuleBuilder,
InvokeBuild, Pester 5, GitVersion, and Azure Pipelines to provide a complete
CI/CD pipeline for PowerShell modules.

This skill was derived from a real migration of the Datum.ProtectedData module
from a legacy stack (AppVeyor + InvokeBuild custom tasks + PSDepend + PSDeploy +
Pester 4) to full Sampler scaffolding.

## When to Use

- Migrating a PowerShell module from any legacy build system to Sampler
- Setting up a new Sampler-based module project from scratch
- Debugging Sampler build or test failures
- Understanding the Sampler project structure and conventions

## Migration Checklist

### Phase 1: Analysis

Before touching any files, inventory the existing project:

1. **Identify the module manifest** (*.psd1) — note the GUID, version,
   `FunctionsToExport`, `RequiredModules`, and `RootModule`.
2. **Identify source files** — public functions, private helpers, classes,
   DSC resources, nested modules.
3. **Identify existing tests** — test framework version (Pester 4 vs 5),
   test structure, coverage.
4. **Identify build artifacts** — CI config (AppVeyor, GitHub Actions, etc.),
   dependency management (PSDepend, etc.), deploy scripts (PSDeploy, etc.).
5. **Find a reference project** — ideally a sibling module by the same maintainer
   that has already been migrated. Clone it for reference.

### Phase 2: Source Restructuring

The Sampler convention places all module source under `source/`:

```text
source/
  Public/           # Exported functions (one .ps1 file per function)
  Private/          # Internal helper functions (optional)
  Classes/          # PowerShell classes (optional)
  en-US/            # Localized string resources (optional)
  Prefix.ps1        # Code prepended to the built .psm1 (optional)
  <ModuleName>.psd1 # Module manifest (source version)
  <ModuleName>.psm1 # Empty placeholder (ModuleBuilder fills it)
```

**Actions:**

1. Create `source/Public/` and move all public function files there (one
   function per file, filename must match function name).
2. Create `source/Private/` if there are internal helper functions.
3. Create a **new module manifest** at `source/<ModuleName>.psd1`:

```powershell
@{
    RootModule        = '<ModuleName>.psm1'
    ModuleVersion     = '0.0.1'  # GitVersion will override this at build time
    GUID              = '<PRESERVE-EXISTING-GUID>'
    Author            = '<Author>'
    CompanyName       = '<Company>'
    Copyright         = '(c) <Author>. All rights reserved.'
    Description       = '<Module description>'
    PowerShellVersion = '5.1'
    RequiredModules   = @('<RuntimeDependency>')
    FunctionsToExport = @(
        'Function-One',
        'Function-Two'
    )
    CmdletsToExport   = @()
    AliasesToExport    = @()
    PrivateData       = @{
        PSData = @{
            Tags         = @('Tag1', 'Tag2')
            LicenseUri   = 'https://github.com/<owner>/<repo>/blob/master/LICENSE'
            ProjectUri   = 'https://github.com/<owner>/<repo>'
            Prerelease   = ''
            ReleaseNotes = ''
        }
    }
}
```

4. Create an **empty** `source/<ModuleName>.psm1`:

```powershell
# This file is intentionally left empty.
# ModuleBuilder will populate it during the build process.
```

**Critical rules:**

- **Preserve the module GUID** — this is the PSGallery identity.
- **Use explicit `FunctionsToExport`** — never use wildcards (`'*'`).
- **Remove `#Requires` statements** from individual `.ps1` source files —
  declare dependencies in the manifest `RequiredModules` instead.
- Set `PowerShellVersion = '5.1'` unless the module truly requires PS 7+.

### Phase 3: Build System Files

Copy these files from a working Sampler project (or generate with
`New-SampleModule`). Adapt, do not blindly copy.

#### `build.ps1` (standard Sampler bootstrap — ~543 lines)

Copy verbatim from a reference project or from the Sampler module itself. This
file rarely needs customization.

#### `Resolve-Dependency.ps1` and `Resolve-Dependency.psd1`

Copy verbatim. These handle downloading build-time dependencies to
`output/RequiredModules/`.

#### `RequiredModules.psd1`

Declare all build-time and runtime module dependencies:

```powershell
@{
    InvokeBuild                    = 'latest'
    PSScriptAnalyzer               = 'latest'
    Pester                         = 'latest'
    Plaster                        = 'latest'
    ModuleBuilder                  = 'latest'
    ChangelogManagement            = 'latest'
    Sampler                        = 'latest'
    'Sampler.GitHubTasks'          = 'latest'
    MarkdownLinkCheck              = 'latest'
    'Indented.ScriptAnalyzerRules' = 'latest'
    PlatyPS                        = 'latest'

    # Runtime dependencies (also in module manifest RequiredModules)
    '<YourRuntimeDep>'             = 'latest'
}
```

#### `build.yaml`

This is the heart of the Sampler configuration. Key sections:

```yaml
---
BuildWorkflow:
  '.':
    - build
    - test
  build:
    - Clean
    - Build_Module_ModuleBuilder
    - Build_NestedModules_ModuleBuilder
    - Create_Changelog_Release_Output
  pack:
    - build
    - package_module_nupkg
  test:
    - Pester_Tests_Stop_On_Fail
    - Convert_Pester_Coverage
    - Pester_If_Code_Coverage_Under_Threshold
  publish:
    - Publish_Release_To_GitHub
    - Publish_Module_To_gallery

CopyPaths: []
Encoding: UTF8
VersionedOutputDirectory: true
BuiltModuleSubdirectory: builtModule

ModuleBuildTasks:
  Sampler:
    - '*.build.Sampler.ib.tasks'
  Sampler.GitHubTasks:
    - '*.ib.tasks'

Pester:
  OutputFormat: NUnitXML
  ExcludeFromCodeCoverage: []
  Script:
    - tests/Unit
    - tests/Integration
  ExcludeTag:
  Tag:
  CodeCoverageOutputFile: JaCoCo_coverage.xml
  CodeCoverageOutputFileEncoding: ascii
  CodeCoverageThreshold: 0  # Increase after establishing baseline

Resolve-Dependency:
  Gallery: 'PSGallery'
  AllowPrerelease: false
  Verbose: false

GitHubConfig:
  GitHubFilesToAdd:
    - 'CHANGELOG.md'
  GitHubConfigUserName: dscbot
  GitHubConfigUserEmail: dsccommunity@outlook.com
  UpdateChangelogOnPrerelease: false
```

**Important Pester configuration notes:**

- Use `Script` key (not `Path`) — Sampler's Pester task uses `Script`.
- Include both `tests/Unit` and `tests/Integration` if you have integration
  tests.
- Start with `CodeCoverageThreshold: 0` and increase after the first
  successful build establishes a baseline.

#### `GitVersion.yml`

```yaml
mode: ContinuousDelivery
next-version: 0.2.0  # Set to your desired next version
major-version-bump-message: '(breaking\schange|breaking|major)\b'
minor-version-bump-message: '(adds?|features?|minor)\b'
patch-version-bump-message: '\s?(fix|patch)'
no-bump-message: '\+semver:\s?(none|skip)'
assembly-informational-format: '{NuGetVersionV2}+Sha.{Sha}.Date.{CommitDate}'
branches:
  master:
    tag: preview
  pull-request:
    tag: PR
  feature:
    tag: useBranchName
    increment: Minor
    regex: f(eature(s)?)?[\/-]
    source-branches: ['master']
  hotfix:
    tag: fix
    increment: Patch
    regex: (hot)?fix(es)?[\/-]
    source-branches: ['master']
ignore:
  sha: []
merge-message-formats: {}
```

**Note:** If the default branch is `main` instead of `master`, update the
branch configuration accordingly.

### Phase 4: Azure Pipelines CI/CD

Create `azure-pipelines.yml` with three stages:

```yaml
trigger:
  branches:
    include:
    - master
  paths:
    exclude:
    - CHANGELOG.md
  tags:
    include:
    - "v*"
    exclude:
    - "*-*"

variables:
  buildFolderName: output
  buildArtifactName: output
  testResultFolderName: testResults
  defaultBranch: master
  Agent.Source.Git.ShallowFetchDepth: 0

stages:
  - stage: Build
    jobs:
      - job: Package_Module
        displayName: 'Package Module'
        pool:
          vmImage: 'ubuntu-latest'
        steps:
          - pwsh: |
              dotnet tool install --global GitVersion.Tool --version 5.*
              $gitVersionObject = dotnet-gitversion | ConvertFrom-Json
              $gitVersionObject.PSObject.Properties.ForEach{
                  Write-Host "Setting Task Variable '$($_.Name)' with value '$($_.Value)'."
                  Write-Host "##vso[task.setvariable variable=$($_.Name);]$($_.Value)"
              }
              Write-Host "##vso[build.updatebuildnumber]$($gitVersionObject.FullSemVer)"
            displayName: Calculate ModuleVersion (GitVersion)
          - task: PowerShell@2
            name: package
            displayName: 'Build & Package Module'
            inputs:
              filePath: './build.ps1'
              arguments: '-ResolveDependency -tasks pack'
              pwsh: true
            env:
              ModuleVersion: $(NuGetVersionV2)
          - task: PublishPipelineArtifact@1
            displayName: 'Publish Build Artifact'
            inputs:
              targetPath: '$(buildFolderName)/'
              artifact: $(buildArtifactName)
              publishLocation: 'pipeline'
              parallel: true

  - stage: Test
    dependsOn: Build
    jobs:
      - job: test_windows_core
        displayName: 'Windows (PowerShell)'
        pool:
          vmImage: 'windows-latest'
        steps:
          - task: DownloadPipelineArtifact@2
            displayName: 'Download Build Artifact'
            inputs:
              buildType: 'current'
              artifactName: $(buildArtifactName)
              targetPath: '$(Build.SourcesDirectory)/$(buildFolderName)'
          - task: PowerShell@2
            name: test
            displayName: 'Run Tests'
            inputs:
              filePath: './build.ps1'
              arguments: '-tasks test'
              pwsh: true
          - task: PublishTestResults@2
            displayName: 'Publish Test Results'
            condition: succeededOrFailed()
            inputs:
              testResultsFormat: 'NUnit'
              testResultsFiles: '$(buildFolderName)/$(testResultFolderName)/NUnit*.xml'
              testRunTitle: 'Windows (PowerShell)'
          - task: PublishPipelineArtifact@1
            displayName: 'Publish Test Artifact'
            inputs:
              targetPath: '$(buildFolderName)/$(testResultFolderName)/'
              artifactName: 'CodeCoverageWinPS7'
              parallel: true

      - job: test_windows_ps
        displayName: 'Windows (Windows PowerShell)'
        pool:
          vmImage: 'windows-latest'
        steps:
          - task: DownloadPipelineArtifact@2
            displayName: 'Download Build Artifact'
            inputs:
              buildType: 'current'
              artifactName: $(buildArtifactName)
              targetPath: '$(Build.SourcesDirectory)/$(buildFolderName)'
          - task: PowerShell@2
            name: test
            displayName: 'Run Tests'
            inputs:
              filePath: './build.ps1'
              arguments: '-tasks test'
              pwsh: false
          - task: PublishTestResults@2
            displayName: 'Publish Test Results'
            condition: succeededOrFailed()
            inputs:
              testResultsFormat: 'NUnit'
              testResultsFiles: '$(buildFolderName)/$(testResultFolderName)/NUnit*.xml'
              testRunTitle: 'Windows (Windows PowerShell)'
          - task: PublishPipelineArtifact@1
            displayName: 'Publish Test Artifact'
            inputs:
              targetPath: '$(buildFolderName)/$(testResultFolderName)/'
              artifactName: 'CodeCoverageWinPS51'
              parallel: true

  - stage: Deploy
    dependsOn: Test
    condition: |
      and(
        succeeded(),
        or(
          eq(variables['Build.SourceBranch'], 'refs/heads/master'),
          startsWith(variables['Build.SourceBranch'], 'refs/tags/')
        ),
        contains(variables['System.TeamFoundationCollectionUri'], '<orgname>')
      )
    jobs:
      - job: Deploy_Module
        displayName: 'Deploy Module'
        pool:
          vmImage: 'ubuntu-latest'
        steps:
          - task: DownloadPipelineArtifact@2
            displayName: 'Download Build Artifact'
            inputs:
              buildType: 'current'
              artifactName: $(buildArtifactName)
              targetPath: '$(Build.SourcesDirectory)/$(buildFolderName)'
          - task: PowerShell@2
            name: publishRelease
            displayName: 'Publish Release'
            inputs:
              filePath: './build.ps1'
              arguments: '-tasks publish'
              pwsh: true
            env:
              GitHubToken: $(GitHubToken)
              GalleryApiToken: $(GalleryApiToken)
              ReleaseBranch: $(defaultBranch)
              MainGitBranch: $(defaultBranch)
          - task: PowerShell@2
            name: sendChangelogPR
            displayName: 'Send Changelog PR'
            inputs:
              filePath: './build.ps1'
              arguments: '-tasks Create_ChangeLog_GitHub_PR'
              pwsh: true
            env:
              GitHubToken: $(GitHubToken)
              ReleaseBranch: $(defaultBranch)
              MainGitBranch: $(defaultBranch)
```

**Key points:**

- `pwsh: true` runs PowerShell 7 (Core); `pwsh: false` runs Windows
  PowerShell 5.1.
- Test on both PS editions to catch cross-edition compatibility issues.
- `Agent.Source.Git.ShallowFetchDepth: 0` is required for GitVersion to work
  (it needs full git history).
- Deploy condition should include your Azure DevOps org name to prevent
  fork deployments.

### Phase 5: Tests

#### Test directory structure

```text
tests/
  QA/
    module.tests.ps1         # PSScriptAnalyzer, help, changelog quality tests
  Unit/
    Public/
      <FunctionName>.tests.ps1   # One test file per public function
    Private/
      <FunctionName>.tests.ps1   # One test file per private function
  Integration/
    <ModuleName>.Integration.tests.ps1  # Real functionality tests
```

#### QA module test template (Pester 5)

Use the standard Sampler QA test pattern. Key blocks:

```powershell
BeforeDiscovery {
    $ProjectPath = "$PSScriptRoot\..\.." | Convert-Path
    $ProjectName = (Get-ChildItem $ProjectPath\*\*.psd1 | Where-Object {
            ($_.Directory.Name -match 'source|src' -or $_.Directory.Name -eq $_.BaseName) -and
            $(try { Test-ModuleManifest $_.FullName -ErrorAction Stop } catch { $false })
        }
    ).BaseName
    # ... discover functions, parse ASTs for parameter validation ...
}

Describe "$($_.FunctionName)" -ForEach $script:functionTestData {
    It 'Should have comment-based help' { ... }
    It 'Should pass PSScriptAnalyzer rules' { ... }
}
```

#### Unit test template (Pester 5)

```powershell
BeforeAll {
    $script:moduleName = '<ModuleName>'

    if (-not (Get-Module -Name $script:moduleName -ListAvailable))
    {
        & "$PSScriptRoot/../../build.ps1" -Tasks 'noop' 2>&1 4>&1 5>&1 6>&1 > $null
    }

    Import-Module -Name $script:moduleName -Force -ErrorAction 'Stop'
}

AfterAll {
    Remove-Module -Name $script:moduleName -Force
}

Describe '<FunctionName>' -Tag 'Unit' {
    Context 'When the function is called' {
        It 'Should be exported from the module' {
            Get-Command -Name '<FunctionName>' -Module $script:moduleName |
                Should -Not -BeNullOrEmpty
        }
    }
}
```

#### Integration test template (Pester 5)

```powershell
BeforeAll {
    $script:moduleName = '<ModuleName>'

    if (-not (Get-Module -Name $script:moduleName -ListAvailable))
    {
        & "$PSScriptRoot/../../build.ps1" -Tasks 'noop' 2>&1 4>&1 5>&1 6>&1 > $null
    }

    Import-Module -Name $script:moduleName -Force -ErrorAction 'Stop'
}

AfterAll {
    Remove-Module -Name $script:moduleName -Force
}

Describe 'End-to-end functionality' -Tag 'Integration' {
    Context 'When performing a round-trip operation' {
        It 'Should return the original value' {
            # Test real functionality without mocks
        }
    }
}
```

### Phase 6: Community and Configuration Files

Create these files (adapt from a reference project):

- `CHANGELOG.md` — Use [Keep a Changelog 1.1.0](https://keepachangelog.com)
  format with imperative mood.
- `CONTRIBUTING.md` — Contribution guidelines.
- `CODE_OF_CONDUCT.md` — Link to `https://opensource.microsoft.com/codeofconduct/`.
- `SECURITY.md` — Security policy.
- `codecov.yml` — Codecov configuration.
- `.markdownlint.json` — Markdown linting rules.
- `.gitattributes` — Git line ending configuration.
- `.gitignore` — Must include `output/` directory.
- `.vscode/settings.json` — VSCode workspace settings for Sampler.
- `.vscode/analyzersettings.psd1` — PSScriptAnalyzer settings.
- `.vscode/launch.json` — Debug configurations.
- `.github/ISSUE_TEMPLATE/` — Issue templates.
- `.github/PULL_REQUEST_TEMPLATE.md` — PR template.

### Phase 7: Cleanup

Remove all legacy files:

- Old CI config: `appveyor.yml`, `.travis.yml`, etc.
- Old dependency management: `PSDepend.build.psd1`
- Old deploy scripts: `Deploy.PSDeploy.ps1`
- Old build scripts: `.build.ps1`, `.build/` directory
- Old module directory if source was not in `source/`

### Phase 8: Verification

```powershell
# First run (resolves all dependencies):
./build.ps1 -ResolveDependency -Tasks test

# Subsequent runs (skip dependency resolution):
./build.ps1 -Tasks test
```

Expected output:

```text
Build succeeded. 9 tasks, 0 errors, 0 warnings 00:00:XX.XXXXXXX
```

## Troubleshooting

### Running builds in VSCode without freezing

Running `./build.ps1` directly in the integrated terminal can freeze VSCode
when the build takes a long time. Use a detached process:

```powershell
$logPath = Join-Path $PWD 'output\test.log'
if (Test-Path $logPath) { Remove-Item $logPath -Force }

Start-Process pwsh -ArgumentList @(
    '-NoProfile', '-NonInteractive', '-Command',
    "Set-Location '$PWD'; .\build.ps1 -Tasks test *>&1 | Out-File '$logPath' -Encoding utf8"
)

# Poll for completion:
do {
    Start-Sleep -Seconds 3
    if (Test-Path $logPath) {
        $content = Get-Content $logPath -Raw -ErrorAction SilentlyContinue
    }
} while ($content -notmatch 'Build (FAILED|succeeded)')

Get-Content $logPath -Tail 30
```

Skip `-ResolveDependency` if `output/RequiredModules/` already exists.

### Pester mock issues with ValidateScript

If the module you depend on uses `[ValidateScript()]` attributes that call
internal module functions, Pester mocks will fail because the validation runs
in the mock scope where those internal functions don't exist.

**Fix:** Use `-RemoveParameterValidation` on the mock:

```powershell
Mock -CommandName 'Protect-Data' -RemoveParameterValidation 'InputObject' -MockWith {
    return [PSCustomObject]@{ MockedResult = $true }
}
```

### Regex matching multiline base64

If your module wraps base64 at a line length (e.g., 100 characters), the
output will contain `\r\n` characters. Standard regex `.*` does not match
newlines. Use the `(?s)` dotall flag:

```powershell
# Wrong: fails on multiline base64
$encrypted -match '^\[ENC=.*\]$'

# Correct: (?s) makes . match newlines too
$encrypted -match '(?s)^\[ENC=.*\]$'
```

### Non-terminating vs terminating errors across environments

Some PowerShell modules behave differently across PS editions or environments.
A command might emit a non-terminating error locally but throw a terminating
error on a CI agent (or vice versa). Write defensive tests:

```powershell
It 'Should fail gracefully with wrong input' {
    $result = try
    {
        Some-Command -BadInput -ErrorAction SilentlyContinue
    }
    catch
    {
        $null
    }

    $result | Should -BeNullOrEmpty
}
```

### Pester 4 to Pester 5 migration

Key differences:

| Pester 4 | Pester 5 |
| --- | --- |
| `Should Be $value` | `Should -Be $value` |
| Top-level `$variable` | `BeforeAll { $script:variable }` |
| `$TestDrive` in `Describe` | `$TestDrive` in `It` (via `BeforeAll`) |
| `Mock` in `Describe` | `Mock` in `BeforeAll` or `BeforeEach` |
| `-TestCases @{...}` | `-ForEach @{...}` or `-TestCases @{...}` |
| Discovery + Run mixed | `BeforeDiscovery` vs `BeforeAll` separation |

### Common build.yaml mistakes

1. **Wrong Pester key**: Use `Script` (not `Path`) for test paths in the
   Pester section — Sampler's task reads `Script`.
2. **Missing task modules**: Ensure `ModuleBuildTasks` includes both
   `Sampler` and `Sampler.GitHubTasks`.
3. **Missing `Convert_Pester_Coverage`**: Include this task in the `test`
   workflow for code coverage conversion to work.

## Final Project Structure

After a successful migration, a Sampler project should look like this:

```text
<ModuleName>/
+-- source/
|   +-- Public/              # One .ps1 per exported function
|   +-- Private/             # Internal helpers (optional)
|   +-- <ModuleName>.psd1    # Module manifest
|   +-- <ModuleName>.psm1    # Empty placeholder
+-- tests/
|   +-- QA/module.tests.ps1  # Quality assurance tests
|   +-- Unit/Public/          # Unit tests per function
|   +-- Integration/          # Integration tests (optional)
+-- docs/                    # Documentation
+-- .github/                 # Issue templates, PR template
+-- .vscode/                 # VSCode settings, analyzer, launch
+-- build.ps1                # Sampler bootstrap (standard)
+-- build.yaml               # Build configuration
+-- RequiredModules.psd1     # Dependencies
+-- Resolve-Dependency.ps1   # Dependency resolution (standard)
+-- Resolve-Dependency.psd1  # Dependency config
+-- azure-pipelines.yml      # CI/CD pipeline
+-- GitVersion.yml           # Semantic versioning
+-- CHANGELOG.md             # Keep a Changelog format
+-- CONTRIBUTING.md
+-- CODE_OF_CONDUCT.md
+-- SECURITY.md
+-- README.md                # Comprehensive with badges
+-- LICENSE
+-- .gitignore               # Must include output/
+-- .gitattributes
+-- .markdownlint.json
+-- codecov.yml
+-- output/                  # Build artifacts (gitignored)
```

## References

- [Sampler GitHub repository](https://github.com/gaelcolas/Sampler)
- [Sampler on PowerShell Gallery](https://www.powershellgallery.com/packages/Sampler/)
- [ModuleBuilder](https://github.com/PoshCode/ModuleBuilder)
- [InvokeBuild](https://github.com/nightroman/Invoke-Build)
- [GitVersion](https://gitversion.net/docs/)
- [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
- [Pester 5 documentation](https://pester.dev/)
- [DSC Community style guidelines](https://dsccommunity.org/styleguidelines/)
