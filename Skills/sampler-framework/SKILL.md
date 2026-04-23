---
name: sampler-framework
description: >-
  Comprehensive reference for the Sampler PowerShell module build framework.
  Covers project structure, build.yaml configuration, dependency management,
  build workflows and tasks, custom build tasks, testing patterns, GitVersion
  versioning, CI/CD pipelines (Azure Pipelines, GitHub Actions), DSC/Datum
  configuration data projects, VSCode integration, multi-module repositories,
  community files, troubleshooting, and command reference.
  USE FOR: Sampler, Sampler framework, build.yaml, RequiredModules.psd1,
  Resolve-Dependency, ModuleBuilder, InvokeBuild, New-SampleModule, Add-Sample,
  Sampler project structure, PowerShell module build, GitVersion configuration,
  CI/CD pipeline, Azure Pipelines PowerShell, DSC Datum, DscWorkshop,
  Sampler.DscPipeline, custom build task, build workflow, Pester configuration,
  code coverage threshold, NuGet package, Publish-Module, PowerShell Gallery,
  module manifest conventions, Set-SamplerTaskVariable, build task variables,
  Sampler commands reference, multi-module repository, patched module,
  locally patched, commented out RequiredModules, gitignore exception,
  third-party module patch, module not in RequiredModules.
  DO NOT USE FOR: debugging existing Sampler builds (use sampler-build-debug),
  migrating legacy modules to Sampler (use sampler-migration),
  general Pester syntax (use pester.instructions.md),
  AutomatedLab deployments (use automatedlab-deployment).
---

# Sampler PowerShell Module Build Framework

Comprehensive reference for the [Sampler](https://github.com/gaelcolas/Sampler) build framework.
Sampler provides scaffolding, build automation, testing, versioning, and CI/CD pipeline
integration using ModuleBuilder, InvokeBuild, Pester 5, and GitVersion.

> **Note**: For enforced coding rules that auto-apply when editing Sampler build files,
> see `sampler.instructions.md`. For debugging build failures, see the `sampler-build-debug`
> skill. For migrating legacy modules, see the `sampler-migration` skill.

---

## Overview

Sampler serves several purposes:

- **Scaffold** a PowerShell module project with consistent structure and practices
- **Build** modules using ModuleBuilder and InvokeBuild tasks
- **Test** with Pester 5 (unit, integration, and quality assurance tests)
- **Version** automatically via GitVersion (semantic versioning from git history)
- **Package** as NuGet packages for PowerShell Gallery publication
- **Deploy** through Azure Pipelines or GitHub Actions CI/CD
- **Works cross-platform** on Windows, Linux, and macOS
- **Assumes nothing** about the local environment (no admin rights required)

### Core Dependencies

| Component | Purpose |
|---|---|
| [InvokeBuild](https://github.com/nightroman/Invoke-Build) | Task runner for build automation |
| [ModuleBuilder](https://github.com/PoshCode/ModuleBuilder) | Compiles source files into a single `.psm1` |
| [Pester 5](https://pester.dev/) | Testing framework |
| [GitVersion](https://gitversion.net/) | Semantic versioning from git history |
| [PSScriptAnalyzer](https://github.com/PowerShell/PSScriptAnalyzer) | Static analysis and linting |
| [Plaster](https://github.com/PowerShellOrg/Plaster) | Template engine for scaffolding |
| [ChangelogManagement](https://github.com/natescherer/ChangelogManagement) | Changelog automation |

---

## Getting Started

### Prerequisites

1. **PowerShell 5.1+** or **PowerShell 7.2+**
2. **Git** installed and available on `PATH`
3. **GitVersion** (recommended for automatic versioning):

```powershell
# Windows (Chocolatey)
choco upgrade gitversion.portable

# macOS/Linux (Homebrew)
brew upgrade gitversion

# .NET tool (cross-platform)
dotnet tool install --global GitVersion.Tool
```

### Installing Sampler

```powershell
Install-Module -Name 'Sampler' -Scope 'CurrentUser'
```

### Creating a New Project

Use `New-SampleModule` to scaffold a new project. Choose the template that fits your needs:

| Template | Description |
|---|---|
| `SimpleModule` | Minimal structure with build pipeline automation |
| `SimpleModule_NoBuild` | Simple module without build automation |
| `CompleteSample` | Complete structure with example files |
| `dsccommunity` | DSC Community baseline with full CI/CD pipeline |
| `CustomModule` | Interactive prompts for custom scaffolding |

#### SimpleModule (Recommended Starting Point)

```powershell
$newSampleModuleParameters = @{
    DestinationPath   = 'C:\source'
    ModuleType        = 'SimpleModule'
    ModuleName        = 'MyModule'
    ModuleAuthor      = 'Your Name'
    ModuleDescription = 'A brief description of the module'
}

New-SampleModule @newSampleModuleParameters
```

#### CustomModule (Full Control)

```powershell
$samplerModule = Import-Module -Name Sampler -PassThru

$invokePlasterParameters = @{
    TemplatePath    = Join-Path -Path $samplerModule.ModuleBase -ChildPath 'Templates/Sampler'
    DestinationPath = 'C:\source'
    ModuleType      = 'CustomModule'
    ModuleName      = 'MyModule'
    ModuleAuthor    = 'Your Name'
    ModuleDescription = 'A brief description of the module'
}

Invoke-Plaster @invokePlasterParameters
```

### First Build

```powershell
cd C:\source\MyModule

# Resolve dependencies and build (first run)
./build.ps1 -ResolveDependency -Tasks build

# Resolve dependencies and run full default workflow (build + test)
./build.ps1 -ResolveDependency
```

---

## Project Structure

A properly structured Sampler project follows this layout:

```text
<ModuleName>/
├── source/
│   ├── Public/                     # Exported functions (one .ps1 per function)
│   ├── Private/                    # Internal helper functions (optional)
│   ├── Classes/                    # PowerShell classes (optional, prefix with ###.)
│   ├── Enum/                       # Enumerations (optional)
│   ├── en-US/                      # Localized string resources (optional)
│   ├── DSCResources/               # MOF-based DSC resources (optional)
│   ├── Prefix.ps1                  # Code prepended to built .psm1 (optional)
│   ├── Suffix.ps1                  # Code appended to built .psm1 (optional)
│   ├── <ModuleName>.psd1           # Module manifest (source version)
│   └── <ModuleName>.psm1           # Empty placeholder (ModuleBuilder populates)
├── tests/
│   ├── QA/
│   │   └── module.tests.ps1        # PSScriptAnalyzer + help quality tests
│   ├── Unit/
│   │   ├── Public/                 # Unit tests per public function
│   │   └── Private/                # Unit tests per private function
│   └── Integration/                # Integration tests (optional)
├── docs/                           # Documentation (optional)
├── .build/                         # Custom build tasks (optional)
│   └── *.build.ps1                 # Custom InvokeBuild tasks
├── .github/                        # GitHub templates
│   ├── ISSUE_TEMPLATE/
│   └── PULL_REQUEST_TEMPLATE.md
├── .vscode/                        # VSCode workspace settings
│   ├── settings.json
│   ├── analyzersettings.psd1
│   └── launch.json
├── build.ps1                       # Sampler bootstrap (standard, rarely modified)
├── build.yaml                      # Build configuration (primary config file)
├── RequiredModules.psd1            # Build and runtime dependencies
├── Resolve-Dependency.ps1          # Dependency resolution script (standard)
├── Resolve-Dependency.psd1         # Dependency resolution configuration
├── azure-pipelines.yml             # Azure Pipelines CI/CD (or GitHub Actions)
├── GitVersion.yml                  # Semantic versioning configuration
├── CHANGELOG.md                    # Keep a Changelog format
├── CONTRIBUTING.md                 # Contribution guidelines
├── CODE_OF_CONDUCT.md              # Code of conduct
├── SECURITY.md                     # Security policy
├── README.md                       # Project documentation with badges
├── LICENSE                         # License file
├── .gitignore                      # Must include output/
├── .gitattributes                  # Line ending configuration
├── .markdownlint.json              # Markdown linting rules
├── codecov.yml                     # Code coverage configuration
└── output/                         # Build artifacts (gitignored)
    ├── builtModule/                # Compiled module
    ├── RequiredModules/            # Downloaded dependencies
    └── testResults/                # Test output files
```

### Key Conventions

- **One function per file** in `source/Public/` and `source/Private/`
- **Filename must match function name** (e.g., `Get-Widget.ps1` contains `function Get-Widget`)
- **`source/<ModuleName>.psm1` is empty** — ModuleBuilder compiles all source files into it
- **`output/` is ephemeral** — always gitignored; rebuilt from source
- **Classes use numeric prefixes** for load ordering (e.g., `001.BaseClass.ps1`, `002.DerivedClass.ps1`)

---

## Module Manifest Conventions

The source manifest at `source/<ModuleName>.psd1` follows these rules:

```powershell
@{
    RootModule        = '<ModuleName>.psm1'
    ModuleVersion     = '0.0.1'   # GitVersion overrides at build time
    GUID              = '<unique-guid>'
    Author            = '<Author Name>'
    CompanyName       = '<Company>'
    Copyright         = '(c) <Author Name>. All rights reserved.'
    Description       = '<Clear, concise module description>'
    PowerShellVersion = '5.1'

    # Explicit exports — NEVER use wildcards
    FunctionsToExport = @(
        'Get-Widget'
        'Set-Widget'
        'New-Widget'
        'Remove-Widget'
    )
    CmdletsToExport   = @()
    AliasesToExport    = @()
    VariablesToExport  = @()

    # Runtime dependencies (not build-time dependencies)
    RequiredModules    = @(
        'SomeDependencyModule'
    )

    PrivateData = @{
        PSData = @{
            Tags         = @('Tag1', 'Tag2', 'Tag3')
            LicenseUri   = 'https://github.com/<owner>/<repo>/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/<owner>/<repo>'
            IconUri      = ''
            Prerelease   = ''
            ReleaseNotes = ''
        }
    }
}
```

### Manifest Rules

| Rule | Details |
|---|---|
| **Preserve GUID** | The GUID is the PowerShell Gallery identity — never change it after first publish |
| **Explicit exports** | Always list functions explicitly; never use `'*'` wildcards |
| **ModuleVersion** | Set to `0.0.1` in source; GitVersion overrides during build |
| **No `#Requires`** | Do not use `#Requires` in source files; declare in `RequiredModules` instead |
| **PowerShellVersion** | Set to `5.1` unless the module truly requires PowerShell 7+ |
| **Prerelease tag** | Leave empty in source; the build pipeline sets it via `PrivateData.PSData.Prerelease` |

---

## Build Configuration (build.yaml)

The `build.yaml` file is the heart of the Sampler configuration. It defines workflows, tasks, Pester settings, and module build options.

### Minimal build.yaml

```yaml
---
BuildWorkflow:
  '.':           # Default workflow (invoked when no -Tasks specified)
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
```

### Key build.yaml Sections

#### BuildWorkflow

Defines named workflows composed of task sequences. The `.` workflow is the default when `./build.ps1` is invoked without `-Tasks`.

```yaml
BuildWorkflow:
  '.':       # Default: build + test
    - build
    - test
  build:     # Compile the module
    - Clean
    - Build_Module_ModuleBuilder
    - Build_NestedModules_ModuleBuilder
    - Create_Changelog_Release_Output
  test:      # Run all tests
    - Pester_Tests_Stop_On_Fail
    - Convert_Pester_Coverage
    - Pester_If_Code_Coverage_Under_Threshold
  pack:      # Build + create NuGet package
    - build
    - package_module_nupkg
  publish:   # Publish to GitHub + Gallery
    - Publish_Release_To_GitHub
    - Publish_Module_To_gallery
```

#### Module Build Options

```yaml
CopyPaths: []                        # Extra paths to copy to built module
Encoding: UTF8                       # Source file encoding
VersionedOutputDirectory: true       # Output to output/<Module>/<Version>/
BuiltModuleSubdirectory: builtModule # Subdirectory under output/ for built module
```

#### ModuleBuildTasks

Import build tasks from modules. **Both Sampler and Sampler.GitHubTasks are typically required:**

```yaml
ModuleBuildTasks:
  Sampler:
    - '*.build.Sampler.ib.tasks'    # Core build tasks
  Sampler.GitHubTasks:
    - '*.ib.tasks'                  # GitHub release/changelog tasks
```

> **DSC projects** import additional task modules — see [DSC-Specific ModuleBuildTasks](#dsc-specific-modulebuildtasks) for `Sampler.DscPipeline`, `DscResource.Test`, `DscResource.DocGenerator`, and `Sampler.AzureDevOpsTasks`.

#### TaskHeader (Optional)

Customize the terminal output decoration for each build task:

```yaml
TaskHeader: |
  param($Path)
  ""
  "=" * 79
  Write-Build Cyan "`t`t`t$($Task.Name.replace("_"," ").ToUpper())"
  Write-Build DarkGray  "$(Get-BuildSynopsis $Task)"
  "-" * 79
  Write-Build DarkGray "  $Path"
  Write-Build DarkGray "  $($Task.InvocationInfo.ScriptName):$($Task.InvocationInfo.ScriptLineNumber)"
  ""
```

#### Pester Configuration

```yaml
Pester:
  OutputFormat: NUnitXML
  ExcludeFromCodeCoverage: []
  Script:                            # IMPORTANT: Use 'Script' key, not 'Path'
    - tests/Unit
    - tests/QA
  ExcludeTag: []
  Tag: []
  CodeCoverageOutputFile: JaCoCo_coverage.xml
  CodeCoverageOutputFileEncoding: ascii
  CodeCoverageThreshold: 85          # Percentage threshold (0 to disable)
```

> **CRITICAL**: Use the `Script` key (not `Path`) for test paths — Sampler's Pester task reads `Script`. Using `Path` will cause tests to not be discovered.

#### Changelog Configuration

```yaml
ChangelogConfig:
  FilesToAdd:
    - 'CHANGELOG.md'
  UpdateChangelogOnPrerelease: false  # true = PR on every preview release
```

#### Git Configuration

```yaml
GitConfig:
  UserName: bot
  UserEmail: bot@company.local
```

#### GitHub Release Configuration

```yaml
GitHubConfig:
  GitHubFilesToAdd:
    - 'CHANGELOG.md'
  GitHubConfigUserName: dscbot
  GitHubConfigUserEmail: dsccommunity@outlook.com
  UpdateChangelogOnPrerelease: false
```

#### Resolve-Dependency Configuration

```yaml
Resolve-Dependency:
  Gallery: 'PSGallery'
  AllowPrerelease: false
  Verbose: false
```

#### PSModulePath Configuration (Optional)

For DSC resource modules that conflict between installed and RequiredModules paths:

```yaml
SetPSModulePath:
  RemovePersonal: false
  RemoveProgramFiles: false
  RemoveWindows: false
  SetSystemDefault: false
```

#### SemVer Override (Optional)

Override GitVersion for testing or when GitVersion is unavailable:

```yaml
SemVer: '99.0.0-preview1'    # Overrides all other version sources
```

---

## Dependency Management (RequiredModules.psd1)

The `RequiredModules.psd1` file declares all modules needed at build time and runtime. Dependencies are downloaded to `output/RequiredModules/` and are NOT installed system-wide.

### Standard RequiredModules.psd1

```powershell
@{
    # Build infrastructure
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

    # Runtime dependencies (must also be in manifest RequiredModules)
    'SomeRuntimeDependency'        = 'latest'
}
```

### Version Specification Syntax

The syntax works with all three dependency resolution methods (PSResourceGet, ModuleFast, PowerShellGet):

```powershell
@{
    # Latest stable release
    Pester = 'latest'

    # Pinned to a specific version
    Pester = '5.6.1'

    # Latest preview/prerelease
    'SomeModule' = @{
        Version    = 'latest'
        Parameters = @{
            AllowPrerelease = $true
        }
    }

    # Pinned prerelease
    'SomeModule' = @{
        Version    = '2.0.0-preview0005'
        Parameters = @{
            AllowPrerelease = $true
        }
    }
}
```

### ModuleFast-Only Syntax (PowerShell 7.2+)

When using ModuleFast exclusively, additional version constraint syntax is available:

```powershell
@{
    'SomeModule' = ':9.0.*'          # Latest patch for v9.0
    'SomeModule' = '!'              # Latest preview
    'SomeModule' = '!>9.0.0'       # Latest (including previews) higher than v9.0.0
    'SomeModule' = '>=2.0.0'       # v2.0.0 or higher
    'SomeModule' = ':[1.0.0,2.0.0]' # Inclusive range: v1.0.0 to v2.0.0
    'SomeModule' = ':(1.0.0,2.0.0)' # Exclusive range: above v1.0.0, below v2.0.0
}
```

> **Note**: ModuleFast-specific syntax is not compatible with PSResourceGet or PowerShellGet.

---

## Dependency Resolution Configuration

### Resolve-Dependency.psd1

Controls which method resolves dependencies:

```powershell
@{
    Gallery            = 'PSGallery'
    AllowPrerelease    = $false
    WithYAML           = $true

    # PSResourceGet is default (recommended)
    UsePSResourceGet   = $true

    # ModuleFast (PowerShell 7.2+ only)
    UseModuleFast      = $false
}
```

### Resolution Methods

| Method | PowerShell Version | Default | Notes |
|---|---|---|---|
| **PSResourceGet** | 5.1+ | Yes (default) | Cross-platform, recommended |
| **ModuleFast** | 7.2+ | No | Fastest, more version syntax options |
| **PowerShellGet + PSDepend** | 5.1+ | No (legacy) | Fallback when others disabled |

### Priority When Multiple Methods Enabled

- **PowerShell 7.2+**: ModuleFast preferred over PSResourceGet
- **PowerShell 5.1 / 7.0-7.1**: PSResourceGet preferred

### Command-Line Override

Override the configured method from the command line:

```powershell
# Force PSResourceGet
./build.ps1 -ResolveDependency -Tasks noop -UsePSResourceGet

# Force ModuleFast
./build.ps1 -ResolveDependency -Tasks noop -UseModuleFast
```

> **Important**: Avoid mixing resolution methods in the same PowerShell session. Open a new session when switching methods.

---

## Bootstrap Process (build.ps1)

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

## Build Workflows and Tasks

### Built-in Workflows

| Workflow | Tasks | Invocation |
|---|---|---|
| `.` (default) | `build` + `test` | `./build.ps1` |
| `build` | Clean → Build_Module → Build_NestedModules → Create_Changelog | `./build.ps1 -Tasks build` |
| `test` | Pester_Tests → Coverage_Convert → Coverage_Threshold | `./build.ps1 -Tasks test` |
| `pack` | `build` + `package_module_nupkg` | `./build.ps1 -Tasks pack` |
| `publish` | Publish_Release_To_GitHub + Publish_Module_To_gallery | `./build.ps1 -Tasks publish` |

### Core Build Tasks

| Task | Source Module | Purpose |
|---|---|---|
| `Clean` | Sampler | Remove `output/` directory |
| `Build_Module_ModuleBuilder` | Sampler | Compile source files into built module |
| `Build_NestedModules_ModuleBuilder` | Sampler | Build nested/helper modules |
| `Create_Changelog_Release_Output` | Sampler | Extract current release notes from CHANGELOG |
| `package_module_nupkg` | Sampler | Create NuGet package |
| `Pester_Tests_Stop_On_Fail` | Sampler | Run Pester tests, fail build on test failure |
| `Convert_Pester_Coverage` | Sampler | Convert coverage to JaCoCo format |
| `Pester_If_Code_Coverage_Under_Threshold` | Sampler | Fail if coverage below threshold |
| `Publish_Release_To_GitHub` | Sampler.GitHubTasks | Create GitHub release with assets |
| `Publish_Module_To_gallery` | Sampler.GitHubTasks | Publish to PowerShell Gallery |
| `Create_ChangeLog_GitHub_PR` | Sampler.GitHubTasks | Create PR to update changelog |
| `Create_Release_Git_Tag` | Sampler | Create and push release tag |
| `Create_Changelog_Branch` | Sampler | Push changelog branch for PR |
| `Set_PSModulePath` | Sampler | Configure `PSModulePath` for build |
| `noop` | Sampler | No operation (bootstrap only) |

### Discovering Available Tasks

```powershell
# List all available tasks (dependencies must be resolved first)
./build.ps1 -Tasks ?
```

---

## Custom Build Tasks

Create custom InvokeBuild tasks in the `.build/` folder:

### Creating a Custom Task

```powershell
# .build/MyCustomTask.build.ps1
task MyCustomTask {
    Write-Build Green "Running custom task..."

    # Access build variables
    $moduleVersion = $script:ModuleVersion
    $outputDir = $script:OutputDirectory

    # Your custom logic here
    Write-Host "Building version $moduleVersion to $outputDir"
}
```

### Task Files with Parameters

For complex tasks, use a `param` block with InvokeBuild's `property` keyword to access build variables with defaults:

```powershell
# .build/MyAdvancedTask.build.ps1
param (
    [Parameter()]
    [System.String]
    $OutputDirectory = (property OutputDirectory (Join-Path $BuildRoot 'output')),

    [Parameter()]
    [System.String]
    $BuiltModuleSubdirectory = (property BuiltModuleSubdirectory ''),

    [Parameter()]
    [System.String]
    $ModuleVersion = (property ModuleVersion ''),

    [Parameter()]
    [System.Collections.Hashtable]
    $BuildInfo = (property BuildInfo @{ })
)

task MyAdvancedTask {
    # Initialize standard Sampler task variables (SourcePath, ProjectName, etc.)
    . Set-SamplerTaskVariable -AsNewBuild

    Write-Build DarkGray "`tOutput Directory = $OutputDirectory"
    Write-Build DarkGray "`tModule Version   = $ModuleVersion"

    # Task logic here
}
```

### Conditional Task Execution

Use the `-if` parameter to execute tasks only when conditions are met:

```powershell
# Only run on Windows PowerShell 5.1
task PowerShell5Compatibility -if ($PSVersionTable.PSEdition -eq 'Desktop') {
    # Remove modules incompatible with PS5.1
}

# Only run on PowerShell Core
task BuildGCPackages -if ($PSVersionTable.PSEdition -eq 'Core') {
    # Build Guest Configuration packages (requires PS7+)
}

# Only run when environment variables are set
task PublishPackages -if (
    $PSVersionTable.PSEdition -eq 'Core' -and ($env:azureClientSecret -or $env:azureIdToken)
) {
    # Publish with Azure credentials
}
```

### Registering Custom Tasks

Add the task to a workflow in `build.yaml`:

```yaml
BuildWorkflow:
  build:
    - Clean
    - MyCustomTask               # Custom task from .build/ folder
    - Build_Module_ModuleBuilder
    - Build_NestedModules_ModuleBuilder
    - Create_Changelog_Release_Output
```

### Inline Task Definition

For simple tasks, define them directly in `build.yaml`:

```yaml
BuildWorkflow:
  MyInlineTask: |
    {
        Write-Host "Running inline task"
    }

  build:
    - Clean
    - MyInlineTask
    - Build_Module_ModuleBuilder
```

---

## Testing Patterns

### Test Directory Structure

```text
tests/
├── QA/
│   └── module.tests.ps1          # Quality assurance (PSScriptAnalyzer, help)
├── Unit/
│   ├── Public/
│   │   ├── Get-Widget.tests.ps1  # One test file per public function
│   │   └── Set-Widget.tests.ps1
│   └── Private/
│       └── ConvertTo-InternalFormat.tests.ps1
└── Integration/
    └── MyModule.Integration.tests.ps1
```

### Unit Test Template (Pester 5)

```powershell
BeforeAll {
    $script:moduleName = 'MyModule'

    # Ensure module is available (build if needed)
    if (-not (Get-Module -Name $script:moduleName -ListAvailable)) {
        & "$PSScriptRoot/../../build.ps1" -Tasks 'noop' 2>&1 4>&1 5>&1 6>&1 > $null
    }

    Import-Module -Name $script:moduleName -Force -ErrorAction 'Stop'
}

AfterAll {
    Remove-Module -Name $script:moduleName -Force
}

Describe 'Get-Widget' -Tag 'Unit' {

    Context 'When called with a valid name' {
        BeforeAll {
            Mock -ModuleName $script:moduleName -CommandName 'Invoke-RestMethod' -MockWith {
                return @{ Name = 'TestWidget'; Status = 'Active' }
            }

            $script:result = Get-Widget -Name 'TestWidget'
        }

        It 'Should return the widget' {
            $script:result | Should -Not -BeNullOrEmpty
        }

        It 'Should have the correct name' {
            $script:result.Name | Should -Be 'TestWidget'
        }

        It 'Should call the REST API exactly once' {
            Should -Invoke -ModuleName $script:moduleName -CommandName 'Invoke-RestMethod' -Times 1 -Exactly
        }
    }

    Context 'When the widget does not exist' {
        BeforeAll {
            Mock -ModuleName $script:moduleName -CommandName 'Invoke-RestMethod' -MockWith {
                throw [System.Net.WebException]::new('404 Not Found')
            }
        }

        It 'Should throw an error' {
            { Get-Widget -Name 'NonExistent' } | Should -Throw
        }
    }
}
```

### QA Module Test Pattern

```powershell
BeforeDiscovery {
    $ProjectPath = "$PSScriptRoot\..\.." | Convert-Path
    $ProjectName = (Get-ChildItem $ProjectPath\*\*.psd1 | Where-Object {
            ($_.Directory.Name -match 'source|src' -or $_.Directory.Name -eq $_.BaseName) -and
            $(try { Test-ModuleManifest $_.FullName -ErrorAction Stop } catch { $false })
        }
    ).BaseName

    Import-Module -Name $ProjectName -Force -ErrorAction 'Stop'
}

Describe 'Module Quality Tests' -Tag 'QA' {
    It 'Should have a valid module manifest' {
        $manifestPath = "$PSScriptRoot\..\..\source\$ProjectName.psd1"
        { Test-ModuleManifest -Path $manifestPath } | Should -Not -Throw
    }

    It 'Should pass all PSScriptAnalyzer rules' {
        $sourcePath = "$PSScriptRoot\..\..\source"
        $results = Invoke-ScriptAnalyzer -Path $sourcePath -Recurse -Severity 'Error'
        $results | Should -BeNullOrEmpty
    }
}
```

### Integration Test Pattern

```powershell
BeforeAll {
    $script:moduleName = 'MyModule'

    if (-not (Get-Module -Name $script:moduleName -ListAvailable)) {
        & "$PSScriptRoot/../../build.ps1" -Tasks 'noop' 2>&1 4>&1 5>&1 6>&1 > $null
    }

    Import-Module -Name $script:moduleName -Force -ErrorAction 'Stop'
}

AfterAll {
    Remove-Module -Name $script:moduleName -Force
}

Describe 'End-to-end round-trip' -Tag 'Integration' {
    Context 'When performing a full operation cycle' {
        It 'Should create, retrieve, and delete successfully' {
            $widget = New-Widget -Name 'IntegrationTest'
            $widget | Should -Not -BeNullOrEmpty

            $retrieved = Get-Widget -Name 'IntegrationTest'
            $retrieved.Name | Should -Be 'IntegrationTest'

            { Remove-Widget -Name 'IntegrationTest' } | Should -Not -Throw
        }
    }
}
```

### Pester Configuration in build.yaml

```yaml
Pester:
  OutputFormat: NUnitXML
  ExcludeFromCodeCoverage:
    - Prefix.ps1                    # Exclude bootstrap code from coverage
  Script:                           # MUST use 'Script' key, not 'Path'
    - tests/Unit
    - tests/QA
  ExcludeTag:
    - helpQuality                   # Exclude tags during normal runs
    - Integration                   # Integration tests run separately
  Tag: []
  CodeCoverageOutputFile: JaCoCo_coverage.xml
  CodeCoverageOutputFileEncoding: ascii
  CodeCoverageThreshold: 85
```

### Running Tests

```powershell
# Run all tests (unit + QA)
./build.ps1 -Tasks test

# Run specific test file
./build.ps1 -Tasks test -PesterPath 'tests/Unit/Public/Get-Widget.tests.ps1' -CodeCoverageThreshold 0

# Run only QA tests
./build.ps1 -Tasks test -PesterPath 'tests/QA' -CodeCoverageThreshold 0

# Run integration tests
./build.ps1 -Tasks test -PesterPath 'tests/Integration' -CodeCoverageThreshold 0
```

---

## Versioning with GitVersion

Sampler uses [GitVersion](https://gitversion.net/) for automatic semantic versioning based on git history. This replaces manual version management.

### GitVersion.yml Configuration

```yaml
mode: ContinuousDelivery
next-version: 1.0.0
major-version-bump-message: '(breaking\schange|breaking|major)\b'
minor-version-bump-message: '(adds?|features?|minor)\b'
patch-version-bump-message: '\s?(fix|patch)'
no-bump-message: '\+semver:\s?(none|skip)'
assembly-informational-format: '{NuGetVersionV2}+Sha.{Sha}.Date.{CommitDate}'
branches:
  main:
    tag: preview
    increment: Minor
  pull-request:
    tag: PR
  feature:
    tag: useBranchName
    increment: Minor
    regex: f(eature(s)?)?[\/-]
    source-branches: ['main']
  hotfix:
    tag: fix
    increment: Patch
    regex: (hot)?fix(es)?[\/-]
    source-branches: ['main']
ignore:
  sha: []
merge-message-formats: {}
```

### How Version is Determined (Priority Order)

1. **`ModuleVersion` parameter** — passed directly to build task
2. **`$env:ModuleVersion`** or parent-scope `$ModuleVersion` — environment variable
3. **GitVersion `NuGetVersionV2`** — computed from git history (most common)
4. **Module manifest** — `ModuleVersion` + `PrivateData.PSData.Prerelease` from source
5. **`SemVer` key in `build.yaml`** — overrides all of the above

### Releasing with Git Tags

```powershell
# Tag a release (triggers version calculation)
git tag -a v1.0.0 -m "Release v1.0.0"
git push origin v1.0.0
```

### GitVersion Modes

| Mode | Description | Use Case |
|---|---|---|
| `ContinuousDelivery` | Tags mark releases; commits after tag get prerelease suffix | **Recommended** for OSS modules |
| `ContinuousDeployment` | Every commit gets a unique version | Automated deployment pipelines |
| `ManualDeployment` | Version only changes on tag | Strict release control |

### Commit Message Conventions

```text
# Bump major (breaking change): 1.0.0 → 2.0.0
git commit -m "breaking change: Removed Get-OldWidget"

# Bump minor (new feature): 1.0.0 → 1.1.0
git commit -m "feature: Added Get-NewWidget"

# Bump patch (bug fix): 1.0.0 → 1.0.1
git commit -m "fix: Corrected widget parsing"

# No version bump
git commit -m "+semver: none - Documentation update"
```

---

## CI/CD Integration

### Azure Pipelines (azure-pipelines.yml)

A standard three-stage pipeline:

```yaml
trigger:
  branches:
    include:
      - main
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
  defaultBranch: main
  Agent.Source.Git.ShallowFetchDepth: 0   # REQUIRED for GitVersion

stages:
  #---------------------------------------------------------------------------
  # Stage 1: Build
  #---------------------------------------------------------------------------
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

  #---------------------------------------------------------------------------
  # Stage 2: Test (multiple editions)
  #---------------------------------------------------------------------------
  - stage: Test
    dependsOn: Build
    jobs:
      - job: test_windows_ps7
        displayName: 'Windows (PowerShell 7)'
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
              pwsh: true            # PowerShell 7

          - task: PublishTestResults@2
            displayName: 'Publish Test Results'
            condition: succeededOrFailed()
            inputs:
              testResultsFormat: 'NUnit'
              testResultsFiles: '$(buildFolderName)/$(testResultFolderName)/NUnit*.xml'
              testRunTitle: 'Windows (PS7)'

      - job: test_windows_ps51
        displayName: 'Windows (PowerShell 5.1)'
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
              pwsh: false           # Windows PowerShell 5.1

          - task: PublishTestResults@2
            displayName: 'Publish Test Results'
            condition: succeededOrFailed()
            inputs:
              testResultsFormat: 'NUnit'
              testResultsFiles: '$(buildFolderName)/$(testResultFolderName)/NUnit*.xml'
              testRunTitle: 'Windows (PS5.1)'

  #---------------------------------------------------------------------------
  # Stage 3: Deploy
  #---------------------------------------------------------------------------
  - stage: Deploy
    dependsOn: Test
    condition: |
      and(
        succeeded(),
        or(
          eq(variables['Build.SourceBranch'], 'refs/heads/main'),
          startsWith(variables['Build.SourceBranch'], 'refs/tags/')
        ),
        contains(variables['System.TeamFoundationCollectionUri'], '<your-org-name>')
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

### Critical CI/CD Configuration

| Setting | Value | Why |
|---|---|---|
| `Agent.Source.Git.ShallowFetchDepth` | `0` | GitVersion needs full git history |
| `pwsh: true` | PowerShell 7 | Cross-platform, modern features |
| `pwsh: false` | Windows PowerShell 5.1 | Test backward compatibility |
| Deploy `condition` | Include org name | Prevent fork deployments |
| `ReleaseBranch` / `MainGitBranch` | `main` | Must match default branch |

### Required Pipeline Variables (Secrets)

| Variable | Purpose |
|---|---|
| `GitHubToken` | GitHub personal access token for releases and PRs |
| `GalleryApiToken` | PowerShell Gallery API key for publishing |

---

## Adding Code Samples with Add-Sample

Use `Add-Sample` to add scaffolded elements to an existing project:

```powershell
# Add a public function with unit test
Add-Sample -Sample PublicFunction -PublicFunctionName Get-MyWidget

# Add a private function
Add-Sample -Sample PrivateFunction -PrivateFunctionName ConvertTo-InternalFormat

# Add a class
Add-Sample -Sample ClassResource -ResourceName MyResource
```

This creates the source file in the appropriate directory and a matching test file.

---

## Multi-Module Repositories

When a single repository contains multiple modules, each module must have its own folder with a distinct, non-overlapping structure.

### Correct Structure

```text
GitRootFolder/
├── Module1/
│   ├── source/
│   ├── tests/
│   ├── build.yaml
│   └── ...
├── Module2/
│   ├── source/
│   ├── tests/
│   ├── build.yaml
│   └── ...
└── SomeModuleGroup/          # Not a module — just a grouping folder
    ├── GroupModule1/
    │   ├── source/
    │   └── ...
    └── GroupModule2/
        ├── source/
        └── ...
```

### Incorrect Structure (Nested Modules)

```text
GitRootFolder/
├── Module3/
│   ├── SubModule1/           # WRONG: modules nested inside modules
│   └── SubModule2/
└── Module3                   # WRONG: duplicate folder names
```

### GitVersion Tag Prefix for Multi-Module

Use the `tag-prefix` configuration in `GitVersion.yml` to differentiate versions per module:

```yaml
# Module1/GitVersion.yml
tag-prefix: 'Module1-v'
```

---

## DSC and Datum Configuration Data Projects

Sampler is not limited to standard PowerShell module builds. Projects like [DscWorkshop](https://github.com/dsccommunity/DscWorkshop) use Sampler to compile DSC configuration data via [Datum](https://github.com/gaelcolas/Datum) into MOF artifacts, producing an end-to-end release pipeline for infrastructure-as-code.

### DSC Project Structure

A Datum-based DSC project differs significantly from a standard module project:

```text
MyDscProject/
├── .build/                          # Custom build tasks
│   ├── ConvertMofFilesToUnicode.ps1
│   ├── GuestConfigurationTasks.ps1
│   └── PowerShell5Compatibility.ps1
├── .vscode/
│   ├── analyzersettings.psd1
│   ├── settings.json
│   └── tasks.json
├── source/
│   ├── AllNodes/                    # Per-node configuration data (YAML)
│   │   ├── Dev/
│   │   │   ├── DSCFile01.yml
│   │   │   └── DSCWeb01.yml
│   │   ├── Prod/
│   │   └── Test/
│   ├── Baselines/                   # Baseline configuration layers
│   │   ├── DscLcm.yml
│   │   ├── Security.yml
│   │   └── Server.yml
│   ├── Datum.yml                    # Datum resolution precedence definition
│   ├── Domains/                     # Domain-specific data
│   ├── Environment/                 # Shared environment defaults
│   ├── Environments/                # Per-environment overrides
│   ├── Global/                      # Global settings (shared across all)
│   ├── Locations/                   # Location-specific data
│   ├── Roles/                       # Role definitions (WebServer, FileServer, etc.)
│   │   ├── DomainController.yml
│   │   ├── FileServer.yml
│   │   └── WebServer.yml
│   ├── MyDscProject.psd1           # Module manifest (composite resources)
│   └── MyDscProject.psm1           # Root module (may be empty)
├── tests/
│   ├── Acceptance/                  # Post-build MOF verification
│   │   └── TestMofFiles.Tests.ps1
│   ├── ConfigData/                  # Configuration data validation
│   │   ├── ConfigData.Tests.ps1
│   │   └── CompositeResources.Tests.ps1
│   ├── QA/                          # Module quality assurance
│   │   └── module.tests.ps1
│   └── ReferenceFiles/             # Reference RSOP comparison
│       └── TestReferenceFiles.Tests.ps1
├── build.ps1
├── build.yaml
├── RequiredModules.psd1
├── Resolve-Dependency.ps1
├── Resolve-Dependency.psd1
├── GitVersion.yml
├── CHANGELOG.md
├── azure-pipelines.yml
├── azure-pipelines On-Prem.yml     # On-premises variant
└── azure-pipelines Guest Configuration.yml
```

### Datum Resolution Hierarchy (Datum.yml)

Datum merges configuration data from multiple layers using a precedence order. The `Datum.yml` file defines the resolution order and merge behavior:

```yaml
ResolutionPrecedence:
  - AllNodes\$($Node.Environment)\$($Node.NodeName)
  - Environment\$($Node.Environment)
  - Locations\$($Node.Location)
  - Roles\$($Node.Role)
  - Baselines\Security
  - Baselines\$($Node.Baseline)
  - Baselines\DscLcm

DatumHandlersThrowOnError: true
DatumHandlers:
  Datum.ProtectedData::ProtectedDatum:
    CommandOptions:
      PlainTextPassword: SomeSecret
  Datum.InvokeCommand::InvokeCommand:
    SkipDuringLoad: true

DscLocalConfigurationManagerKeyName: LcmConfig

default_lookup_options: MostSpecific

lookup_options:
  Configurations:
    merge_basetype_array: Unique
  Baseline:
    merge_hash: deep
  WindowsFeatures:
    merge_hash: deep
  WindowsFeatures\Names:
    merge_basetype_array: Unique
  RegistryValues:
    merge_hash: deep
  RegistryValues\Values:
    merge_hash_array: UniqueKeyValTuples
    merge_options:
      tuple_keys:
        - Key
```

### Node Definition Files

Each node (server/machine) gets a YAML file under `source/AllNodes/<Environment>/`:

```yaml
# source/AllNodes/Dev/DSCWeb01.yml
NodeName: '[x={ $Node.Name }=]'
Environment: '[x={ $File.Directory.BaseName } =]'
Role: WebServer
Description: '[x= "$($Node.Role) in $($Node.Environment)" =]'
Location: Singapore
Baseline: Server

ComputerSettings:
  Name: '[x={ $Node.NodeName }=]'
  Description: '[x= "$($Node.Role) in $($Node.Environment)" =]'

NetworkIpConfiguration:
  Interfaces:
    - InterfaceAlias: DscWorkshop 0
      IpAddress: 192.168.111.101

PSDscAllowPlainTextPassword: True
PSDscAllowDomainUser: True

LcmConfig:
  ConfigurationRepositoryWeb:
    Server:
      ConfigurationNames: '[x={ $Node.NodeName }=]'

DscTagging:
  Layers:
    - '[x={ Get-DatumSourceFile -Path $File } =]'
  NodeVersion: '[x={ $datum.Baselines.DscLcm.DscTagging.Version } =]'
  NodeRole: '[x={ $Node.Role } =]'
```

### Role Definition Files

Roles define which DSC configurations apply and their parameters:

```yaml
# source/Roles/WebServer.yml
Configurations:
  - WindowsServices
  - RegistryValues
  - FileSystemObjects
  - WebApplicationPools
  - WebApplications

FileSystemObjects:
  Items:
    - DestinationPath: C:\Inetpub\TestApp1
      Type: Directory
    - DestinationPath: C:\Inetpub\TestApp1\default.html
      Type: File
      Contents: This is TestApp1
      DependsOn: '[FileSystemObject]FileSystemObject_C__Inetpub_TestApp1'

WebApplicationPools:
  Items:
    - Name: TestAppPool1
      Ensure: Present
      IdentityType: ApplicationPoolIdentity
      State: Started
  DependsOn:
    - '[FileSystemObjects]FileSystemObjects'
    - '[WindowsFeatures]WindowsFeatures'
```

### DSC Build Configuration (build.yaml)

A DSC project's `build.yaml` differs from a standard module project in several key ways:

```yaml
---
BuiltModuleSubDirectory: Module

BuildWorkflow:
  '.':
    - build
    - pack
    - test

  build:
    - Clean
    - PowerShell5Compatibility       # Remove PS7-only modules on PS5.1
    - Build_Module_ModuleBuilder
    - LoadDatumConfigData            # Load Datum hierarchy
    - TestConfigData                 # Validate config data integrity
    - CompileDatumRsop               # Compile Resultant Set of Policy
    - TestReferenceRsop              # Compare RSOP against references
    - Set_PSModulePath               # Isolate module path
    - TestDscResources               # Validate DSC resources exist
    - CompileRootConfiguration       # Compile MOF files
    - CompileRootMetaMof             # Compile Meta MOF files

  pack:
    - PowerShell5Compatibility
    - LoadDatumConfigData
    - ConvertMofFilesToUnicode       # Fix MOF encoding
    - NewMofChecksums                # Generate checksums
    - CompressModulesWithChecksum    # Package DSC resources
    - Compress_Artifact_Collections  # Package build artifacts
    - TestBuildAcceptance            # Verify artifacts were created

  packguestconfiguration:           # Azure Guest Configuration packages
    - PowerShell5Compatibility
    - LoadDatumConfigData
    - NewMofChecksums
    - CompressModulesWithChecksum
    - Compress_Artifact_Collections
    - TestBuildAcceptance
    - build_guestconfiguration_packages_from_MOF
    - publish_guestconfiguration_packages

  rsop:                             # Quick RSOP-only workflow
    - LoadDatumConfigData
    - CompileDatumRsop
    - TestDscResources

  hqrmtest:                         # High Quality Resource Module tests
    - Invoke_HQRM_Tests_Stop_On_Fail

  publish:
    - publish_module_to_gallery
    - Publish_Release_To_GitHub
    - Create_ChangeLog_GitHub_PR
```

### DSC-Specific ModuleBuildTasks

DSC projects import tasks from additional modules beyond the standard `Sampler` and `Sampler.GitHubTasks`:

```yaml
ModuleBuildTasks:
  Sampler:
    - '*.build.Sampler.ib.tasks'      # Core build tasks
  Sampler.DscPipeline:
    - '*.ib.tasks'                    # DSC pipeline tasks (LoadDatumConfigData,
                                      #   CompileDatumRsop, CompileRootConfiguration, etc.)
  Sampler.GitHubTasks:
    - '*.ib.tasks'                    # GitHub release/changelog tasks
  Sampler.AzureDevOpsTasks:
    - 'Task.*'                        # Azure DevOps integration tasks
  DscResource.DocGenerator:
    - 'Task.*'                        # DSC documentation generation
  DscResource.Test:
    - 'Task.*'                        # HQRM test tasks
```

### DSC-Specific Pester and HQRM Configuration

DSC projects typically have two Pester configuration blocks — one for standard tests and one for HQRM (High Quality Resource Module) tests:

```yaml
# Standard Pester tests (QA, unit)
Pester:
  Configuration:
    Run:
      Path:
        - tests/QA
    Output:
      Verbosity: Detailed
      StackTraceVerbosity: Full
      CIFormat: Auto
    CodeCoverage:
      CoveragePercentTarget: 0
      OutputPath: JaCoCo_coverage.xml
      OutputEncoding: ascii
      UseBreakpoints: false
    TestResult:
      OutputFormat: NUnitXML
      OutputEncoding: ascii
  ExcludeFromCodeCoverage:

# HQRM tests (DscResource.Test)
DscTest:
  Pester:
    Configuration:
      Filter:
        ExcludeTag:
          - BuiltModule Tests - Validate Localization
      Output:
        Verbosity: Detailed
        CIFormat: Auto
      TestResult:
        OutputFormat: NUnitXML
        OutputEncoding: ascii
        OutputPath: ./output/testResults/NUnitXml_HQRM_Tests.xml
  Script:
    ExcludeSourceFile:
      - output
    ExcludeModuleFile:
      - MyDscProject.psm1
    MainGitBranch: main
```

### Sampler.DscPipeline Configuration

Configure DSC composite resource modules in `build.yaml`:

```yaml
Sampler.DscPipeline:
  DscCompositeResourceModules:
    - PSDesiredStateConfiguration
    - DscConfig.Demo
    # Optionally pin version:
    # - Name: CommonTasks
    #   Version: 0.3.259
```

### SetPSModulePath for DSC Isolation

DSC projects should isolate `PSModulePath` to prevent conflicts between system-installed and build-local modules:

```yaml
SetPSModulePath:
  RemovePersonal: true
  RemoveProgramFiles: true
```

### DSC RequiredModules.psd1

DSC projects require additional dependencies beyond standard build tools:

```powershell
@{
    PSDependOptions              = @{
        AddToPath  = $true
        Target     = 'output\RequiredModules'
        Parameters = @{
            Repository      = 'PSGallery'
            AllowPreRelease = $true
        }
    }

    # Build infrastructure
    InvokeBuild                  = '5.14.22'
    PSScriptAnalyzer             = '1.24.0'
    Pester                       = '5.7.1'
    Plaster                      = '1.1.4'
    ModuleBuilder                = '3.1.8'
    ChangelogManagement          = '3.1.0'
    Sampler                      = '0.118.3'
    'Sampler.GitHubTasks'        = '0.3.5-preview0002'
    'Sampler.AzureDevOpsTasks'   = '0.1.2'
    'Sampler.DscPipeline'        = '0.3.0'
    'powershell-yaml'            = '0.4.12'
    MarkdownLinkCheck            = '0.2.0'
    PowerShellForGitHub          = '0.17.0'

    # DSC build helpers and testing
    'DscResource.AnalyzerRules'  = '0.2.0'
    'DscResource.Test'           = '0.18.0'
    'DscResource.DocGenerator'   = '0.13.0'
    DscBuildHelpers              = '0.3.0'
    xDscResourceDesigner         = '1.13.0.0'

    # Datum (configuration data management)
    Datum                        = '0.41.0'
    'Datum.ProtectedData'        = '0.0.1'
    'Datum.InvokeCommand'        = '0.3.0'
    ProtectedData                = '5.0.0'
    Configuration                = '1.6.0'
    Metadata                     = '1.5.7'

    # DSC resources (domain-specific)
    PSDesiredStateConfiguration  = '2.0.7'
    GuestConfiguration           = '4.11.0'
    ComputerManagementDsc        = '10.0.0'
    NetworkingDsc                = '9.1.0'
    WebAdministrationDsc         = '4.2.1'
    SecurityPolicyDsc            = '2.10.0.0'

    # Azure modules (for Guest Configuration publishing)
    'Az.Accounts'                = '4.0.2'
    'Az.Storage'                 = '8.2.0'
    'Az.Resources'               = '7.9.0'
}
```

### DSC-Specific Build Output

DSC builds produce multiple artifact types (not just a module package):

```text
output/
├── Module/                        # Built module (BuiltModuleSubDirectory)
│   └── MyDscProject/
│       └── 0.4.0/
├── MOF/                           # Compiled MOF files (one per node)
│   ├── DSCFile01.mof
│   ├── DSCWeb01.mof
│   └── *.mof.checksum
├── MetaMOF/                       # Meta MOF files (LCM configuration)
├── RSOP/                          # Resultant Set of Policy (JSON)
├── CompressedModules/             # Zipped DSC resource modules
├── GCPackages/                    # Guest Configuration packages
├── testResults/                   # Test results (NUnit XML)
└── RequiredModules/               # Downloaded dependencies
```

### DSC Testing Categories

DSC projects use specialized test categories beyond standard unit/integration tests:

#### Acceptance Tests (Post-Build Verification)

Acceptance tests verify that build artifacts were created correctly:

```powershell
# tests/Acceptance/TestMofFiles.Tests.ps1
BeforeDiscovery {
    $datumDefinitionFile = Join-Path -Path $ProjectPath -ChildPath source\Datum.yml
    $datum = New-DatumStructure -DefinitionFile $datumDefinitionFile
    $configurationData = Get-FilteredConfigurationData -Filter $Filter

    $mofFiles = Get-ChildItem -Path "$OutputDirectory\MOF" -Filter *.mof -Recurse
    $mofChecksumFiles = Get-ChildItem -Path "$OutputDirectory\MOF" -Filter *.mof.checksum -Recurse
    $metaMofFiles = Get-ChildItem -Path "$OutputDirectory\MetaMOF" -Filter *.mof -Recurse
    $nodes = $configurationData.AllNodes
}

Describe 'MOF Files' -Tag BuildAcceptance {
    It 'All nodes have a MOF file' -TestCases $allMofTests {
        $mofFiles.Count | Should -Be $nodes.Count
    }

    It "Node '<NodeName>' should have a MOF file" -TestCases $individualTests {
        $MofFiles | Where-Object BaseName -EQ $NodeName |
            Should -BeOfType System.IO.FileSystemInfo
    }
}
```

#### ConfigData Tests (Configuration Data Validation)

ConfigData tests validate the Datum YAML structure before compilation:

```powershell
# tests/ConfigData/ConfigData.Tests.ps1
BeforeDiscovery {
    $configurationData = Get-FilteredConfigurationData
    $datumDefinitionFile = Join-Path -Path $ProjectPath -ChildPath source\Datum.yml
    $datum = New-DatumStructure -DefinitionFile $datumDefinitionFile

    $environments = Get-ChildItem $ProjectPath\source\Environments -EA SilentlyContinue |
        Select-Object -ExpandProperty BaseName
    $locations = Get-ChildItem $ProjectPath\source\Locations -EA SilentlyContinue |
        Select-Object -ExpandProperty BaseName
    $roles = Get-ChildItem $ProjectPath\source\Roles -EA SilentlyContinue |
        Select-Object -ExpandProperty BaseName
}

Describe 'Datum Definition' -Tag ConfigData {
    It 'Datum.yml exists' {
        Test-Path $datumDefinitionFile | Should -BeTrue
    }

    It 'Datum.yml is valid YAML' {
        $datumYamlContent | Should -Not -BeNullOrEmpty
    }
}
```

#### CompositeResources Tests

Tests verify that DSC composite resources have all required module dependencies:

```powershell
# tests/ConfigData/CompositeResources.Tests.ps1
BeforeDiscovery {
    $dscCompositeResourceModules = $BuildInfo.'Sampler.DscPipeline'.DscCompositeResourceModules
    # Scans composite resource .psm1 files for Import-DscResource statements
    # and verifies referenced modules are in RequiredModules.psd1
}

Describe "Composite resource '<compositeResourceModuleName>'" -Tag ConfigData {
    It "Should have required module '<ModuleName>' in RequiredModules.psd1" {
        $dscResources.Keys | Should -Contain $ModuleName
    }
}
```

### DSC CI/CD Pipeline Variants

DSC projects often maintain multiple pipeline files for different deployment scenarios:

#### Standard Pipeline (Cloud-Hosted Agents)

The standard pipeline builds on both PowerShell 5.1 and PowerShell 7 in parallel, publishes multiple artifact types, and runs HQRM tests:

```yaml
# azure-pipelines.yml
stages:
  - stage: Build
    jobs:
      - job: CompileDscOnWindowsPowerShell
        displayName: Compile DSC Configuration on Windows PowerShell 5.1
        pool:
          vmImage: 'windows-latest'
        steps:
          - task: PowerShell@2
            name: build
            inputs:
              filePath: './build.ps1'
              arguments: '-ResolveDependency -tasks build'
              pwsh: false              # Windows PowerShell 5.1
            env:
              ModuleVersion: $(NuGetVersionV2)
          - task: PowerShell@2
            name: pack
            inputs:
              filePath: './build.ps1'
              arguments: '-tasks pack'

          # Publish multiple artifact types
          - task: PublishPipelineArtifact@1
            inputs:
              targetPath: '$(buildFolderName)/MOF'
              artifact: 'MOF5'
          - task: PublishPipelineArtifact@1
            inputs:
              targetPath: '$(buildFolderName)/MetaMOF'
              artifact: 'MetaMOF5'
          - task: PublishPipelineArtifact@1
            inputs:
              targetPath: '$(buildFolderName)/CompressedModules'
              artifact: 'CompressedModules5'
          - task: PublishPipelineArtifact@1
            inputs:
              targetPath: '$(buildFolderName)/RSOP'
              artifact: 'RSOP5'

      - job: CompileDscOnPowerShellCore
        # Same build but with pwsh: true for PS7
        # Also publishes GCPackages if they exist

  - stage: Test
    dependsOn: Build
    jobs:
      - job: Test_HQRM
        displayName: 'HQRM'
        steps:
          - task: PowerShell@2
            name: test
            inputs:
              filePath: './build.ps1'
              arguments: '-Tasks hqrmtest'
              pwsh: true
```

#### On-Premises Pipeline (Self-Hosted Agents)

For air-gapped or internal deployments with a private PowerShell repository:

```yaml
# azure-pipelines On-Prem.yml
variables:
  PSModuleFeed: PowerShell
  RepositoryUri: RepositoryUri_WillBeChanged  # Replaced during lab deployment

stages:
  - stage: build
    jobs:
      - job: Dsc_Build
        pool:
          name: Default             # Self-hosted agent pool
        steps:
          - task: PowerShell@2
            displayName: Register PowerShell Gallery
            inputs:
              targetType: inline
              script: |
                $uri = '$(RepositoryUri)'
                $name = 'PowerShell'
                $r = Get-PSRepository -Name $name -ErrorAction SilentlyContinue
                if (-not $r -or $r.SourceLocation -ne $uri) {
                    Unregister-PSRepository -Name $name -ErrorAction SilentlyContinue
                    Register-PSRepository -Name $name -SourceLocation $uri `
                        -PublishLocation $uri -InstallationPolicy Trusted
                }
```

#### Guest Configuration Pipeline

For Azure Policy Guest Configuration with service principal authentication:

```yaml
# azure-pipelines Guest Configuration.yml
stages:
  - stage: Build
    jobs:
      - job: CompileDscOnPowerShellCore
        steps:
          - task: AzureCLI@2
            name: setVariables
            inputs:
              azureSubscription: GC1
              scriptType: ps
              addSpnToEnvironment: true
              inlineScript: |
                Write-Host "##vso[task.setvariable variable=azureClientId;isOutput=true]$($env:servicePrincipalId)"
                Write-Host "##vso[task.setvariable variable=azureClientSecret;isOutput=true]$($env:servicePrincipalKey)"
                Write-Host "##vso[task.setvariable variable=azureIdToken;isOutput=true]$($env:idToken)"

          - task: PowerShell@2
            name: pack
            inputs:
              filePath: './build.ps1'
              arguments: '-tasks pack'
              pwsh: true
            env:
              azureClientId: $(setVariables.azureClientId)
              azureClientSecret: $(setVariables.azureClientSecret)
              azureIdToken: $(setVariables.azureIdToken)
```

### DSC Custom Build Task Patterns

DscWorkshop demonstrates several advanced custom build task patterns:

#### Conditional Task Execution

Use the `-if` parameter to conditionally execute tasks:

```powershell
# .build/PowerShell5Compatibility.ps1
task PowerShell5Compatibility -if ($PSVersionTable.PSEdition -eq 'Desktop') {
    $path = "$requiredModulesPath\PSDesiredStateConfiguration"
    if (Test-Path -Path $path) {
        Remove-Item -Path $path -ErrorAction Stop -Recurse -Force
        Write-Warning "'PSDesiredStateConfiguration' > 2.0 is not supported on Windows PowerShell."
    }
}
```

#### Tasks with `Set-SamplerTaskVariable`

Use `Set-SamplerTaskVariable` for proper initialization of build variables:

```powershell
# .build/GuestConfigurationTasks.ps1
param (
    [Parameter()]
    [System.String]
    $OutputDirectory = (property OutputDirectory (Join-Path $BuildRoot 'output')),

    [Parameter()]
    [System.String]
    $BuiltModuleSubdirectory = (property BuiltModuleSubdirectory ''),

    [Parameter()]
    [System.String]
    $ModuleVersion = (property ModuleVersion ''),

    [Parameter()]
    [System.Collections.Hashtable]
    $BuildInfo = (property BuildInfo @{ })
)

task build_guestconfiguration_packages_from_MOF -if (
    $PSVersionTable.PSEdition -eq 'Core'
) {
    # Initialize standard task variables
    . Set-SamplerTaskVariable -AsNewBuild

    $mofPath = Join-Path -Path $OutputDirectory -ChildPath $MofOutputFolder
    $mofFiles = Get-ChildItem -Path $mofPath -Filter '*.mof' -Recurse

    foreach ($mofFile in $mofFiles) {
        $NewGCPackageParams = @{
            Configuration = $mofFile.FullName
            Name          = $mofFile.BaseName
            Path          = $GCPackageOutput
            Force         = $true
            Version       = $ModuleVersion
            Type          = 'AuditAndSet'
        }
        New-GuestConfigurationPackage @NewGCPackageParams
    }
}
```

#### MOF Encoding Conversion Task

```powershell
# .build/ConvertMofFilesToUnicode.ps1
task ConvertMofFilesToUnicode {
    $path = Join-Path -Path $OutputDirectory -ChildPath $MofOutputFolder
    Get-ChildItem -Path $path -Recurse -Filter *.mof | ForEach-Object {
        Write-Host "Converting file $($_.FullName) to Unicode encoding." -ForegroundColor DarkGray
        $content = Get-Content $_.FullName -Encoding UTF8
        $content | Out-File -FilePath $_.FullName -Encoding unicode
    }
}
```

### TaskHeader Formatting

Customize the terminal output decoration for build tasks:

```yaml
TaskHeader: |
  param($Path)
  ""
  "=" * 79
  Write-Build Cyan "`t`t`t$($Task.Name.replace("_"," ").ToUpper())"
  Write-Build DarkGray  "$(Get-BuildSynopsis $Task)"
  "-" * 79
  Write-Build DarkGray "  $Path"
  Write-Build DarkGray "  $($Task.InvocationInfo.ScriptName):$($Task.InvocationInfo.ScriptLineNumber)"
  ""
```

### PullRequestConfig for Azure DevOps

Configure automated changelog PR creation for Azure DevOps Server:

```yaml
PullRequestConfig:
  BranchName: updateChangelogAfterv{0}
  Title: Updating Changelog since release of v{0} +semver:skip
  Description: Updating Changelog since release of v{0} +semver:skip
  Instance: mydevops:8080
  Collection: AutomatedLab
  Project: DscConfig.Demo
  RepositoryID: DscConfig.Demo
  Debug: false
```

---

## VSCode Integration

### Setting Up the Environment

Before running or debugging tests in VSCode, ensure the session is configured:

```powershell
# In the PowerShell Integrated Console:
./build.ps1 -Tasks noop
```

This bootstraps the environment without building or testing. The `noop` task only runs the bootstrap and sets up `$env:PSModulePath`.

### .vscode/settings.json

```json
{
    "powershell.codeFormatting.autoCorrectAliases": true,
    "powershell.codeFormatting.useCorrectCasing": true,
    "powershell.codeFormatting.pipelineIndentationStyle": "IncreaseIndentationForFirstPipeline",
    "powershell.codeFormatting.openBraceOnSameLine": true,
    "powershell.codeFormatting.newLineAfterOpenBrace": true,
    "powershell.codeFormatting.newLineAfterCloseBrace": true,
    "powershell.codeFormatting.whitespaceBeforeOpenBrace": true,
    "powershell.codeFormatting.whitespaceBeforeOpenParen": true,
    "powershell.codeFormatting.whitespaceAroundOperator": true,
    "powershell.codeFormatting.whitespaceAfterSeparator": true,
    "powershell.codeFormatting.whitespaceBetweenParameters": false,
    "powershell.scriptAnalysis.settingsPath": ".vscode/analyzersettings.psd1",
    "files.trimTrailingWhitespace": true,
    "files.insertFinalNewline": true,
    "files.associations": {
        "*.ps1xml": "xml"
    }
}
```

### .vscode/analyzersettings.psd1

```powershell
@{
    CustomRulePath      = @(
        './output/RequiredModules/Indented.ScriptAnalyzerRules'
    )
    IncludeDefaultRules = $true
    IncludeRules        = @(
        # Default rules from PSScriptAnalyzer
        'PSAvoidDefaultValueForMandatoryParameter'
        'PSAvoidDefaultValueSwitchParameter'
        'PSAvoidGlobalAliases'
        'PSAvoidGlobalFunctions'
        'PSAvoidGlobalVars'
        'PSAvoidInvokingEmptyMembers'
        'PSAvoidUsingCmdletAliases'
        'PSAvoidUsingComputerNameHardcoded'
        'PSAvoidUsingPlainTextForPassword'
        'PSAvoidUsingWMICmdlet'
        'PSMissingModuleManifestField'
        'PSProvideCommentHelp'
        'PSUseApprovedVerbs'
        'PSUseShouldProcessForStateChangingFunctions'
        'PSUseSingularNouns'

        # Custom rules
        'Measure-*'
    )
}
```

#### DSC-Specific Analyzer Rules

DSC projects should use `DscResource.AnalyzerRules` instead of (or alongside) `Indented.ScriptAnalyzerRules`:

```powershell
@{
    CustomRulePath      = '.\output\RequiredModules\DscResource.AnalyzerRules'
    includeDefaultRules = $true
    IncludeRules        = @(
        # Standard PSScriptAnalyzer rules
        'PSAvoidDefaultValueForMandatoryParameter'
        'PSAvoidUsingCmdletAliases'
        'PSAvoidUsingEmptyCatchBlock'
        'PSAvoidUsingInvokeExpression'
        'PSAvoidUsingPositionalParameters'
        'PSAvoidUsingWriteHost'
        'PSMissingModuleManifestField'
        'PSProvideCommentHelp'
        'PSUseApprovedVerbs'
        'PSUseCmdletCorrectly'
        'PSUseOutputTypeCorrectly'
        'PSAvoidGlobalVars'
        'PSAvoidUsingConvertToSecureStringWithPlainText'
        'PSUseDeclaredVarsMoreThanAssignments'
        'PSUsePSCredentialType'

        # DSC-specific rules
        'PSDSCReturnCorrectTypesForDSCFunctions'
        'PSDSCStandardDSCFunctionsInResource'
        'PSDSCUseIdenticalMandatoryParametersForDSC'
        'PSDSCUseIdenticalParametersForDSC'
        'PSDSCUseVerboseMessageInDSCResource'

        # Custom Measure-* rules from DscResource.AnalyzerRules
        'Measure-*'
    )
}
```

### .vscode/tasks.json

Define build and test tasks with problem matchers for Pester test failures:

```jsonc
{
    "version": "2.0.0",
    "_runner": "terminal",
    "windows": {
        "options": {
            "shell": {
                "executable": "C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe",
                "args": ["-NoProfile", "-ExecutionPolicy", "Bypass", "-Command"]
            }
        }
    },
    "linux": {
        "options": {
            "shell": {
                "executable": "/usr/bin/pwsh",
                "args": ["-NoProfile", "-Command"]
            }
        }
    },
    "tasks": [
        {
            "label": "build",
            "type": "shell",
            "command": "&${cwd}/build.ps1",
            "args": [],
            "presentation": {
                "echo": true,
                "reveal": "always",
                "focus": true,
                "panel": "new",
                "clear": false
            },
            "problemMatcher": [
                {
                    "owner": "powershell",
                    "fileLocation": ["absolute"],
                    "severity": "error",
                    "pattern": [
                        {
                            "regexp": "^\\s*(\\[-\\]\\s*.*?)(\\d+)ms\\s*$",
                            "message": 1
                        },
                        { "regexp": "(.*)", "code": 1 },
                        { "regexp": "" },
                        {
                            "regexp": "^.*,\\s*(.*):\\s*line\\s*(\\d+).*",
                            "file": 1,
                            "line": 2
                        }
                    ]
                }
            ]
        },
        {
            "label": "test",
            "type": "shell",
            "command": "&${cwd}/build.ps1",
            "args": ["-AutoRestore", "-Tasks", "test"],
            "presentation": {
                "echo": true,
                "reveal": "always",
                "focus": true,
                "panel": "dedicated"
            },
            "problemMatcher": [
                {
                    "owner": "powershell",
                    "fileLocation": ["absolute"],
                    "severity": "error",
                    "pattern": [
                        {
                            "regexp": "^\\s*(\\[-\\]\\s*.*?)(\\d+)ms\\s*$",
                            "message": 1
                        },
                        { "regexp": "(.*)", "code": 1 },
                        { "regexp": "" },
                        {
                            "regexp": "^.*,\\s*(.*):\\s*line\\s*(\\d+).*",
                            "file": 1,
                            "line": 2
                        }
                    ]
                }
            ]
        }
    ]
}
```

### Additional VSCode Settings for DSC Projects

DSC projects benefit from additional settings for the bundled modules path and spelling dictionary:

```json
{
    "powershell.developer.bundledModulesPath": "${cwd}/output/RequiredModules",
    "powershell.codeFormatting.preset": "Custom",
    "powershell.codeFormatting.alignPropertyValuePairs": true,
    "files.trimFinalNewlines": true,
    "[markdown]": {
        "files.trimTrailingWhitespace": false,
        "files.encoding": "utf8"
    },
    "cSpell.words": [
        "gitversion",
        "keepachangelog",
        "pscmdlet",
        "steppable"
    ]
}
```

---

## Common Pitfalls and Troubleshooting

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
# Fix: Run noop to bootstrap the environment
./build.ps1 -Tasks noop
Import-Module -Name 'MyModule' -Force
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

## Migration from Legacy Build Systems

### Migration Checklist

| Phase | Action | Details |
|---|---|---|
| 1 | **Analyze** | Inventory manifest, functions, tests, CI config |
| 2 | **Restructure source** | Move to `source/Public/`, `source/Private/` layout |
| 3 | **Create build files** | `build.ps1`, `build.yaml`, `RequiredModules.psd1`, `Resolve-Dependency.*`, `GitVersion.yml` |
| 4 | **Configure CI/CD** | `azure-pipelines.yml` with Build/Test/Deploy stages |
| 5 | **Port tests** | Migrate to Pester 5 syntax, create QA tests |
| 6 | **Add community files** | CHANGELOG, CONTRIBUTING, CODE_OF_CONDUCT, SECURITY |
| 7 | **Remove legacy files** | Delete `appveyor.yml`, `PSDepend.build.psd1`, `Deploy.PSDeploy.ps1`, old `*.build.ps1` |
| 8 | **Verify** | `./build.ps1 -ResolveDependency -Tasks test` succeeds |

### Pester 4 to Pester 5 Migration

| Pester 4 | Pester 5 |
|---|---|
| `Should Be $value` | `Should -Be $value` |
| Top-level `$variable` | `BeforeAll { $script:variable }` |
| `$TestDrive` in `Describe` | `$TestDrive` in `It` (via `BeforeAll`) |
| `Mock` in `Describe` | `Mock` in `BeforeAll` or `BeforeEach` |
| `-TestCases @{...}` | `-ForEach @{...}` or `-TestCases @{...}` |
| Discovery + Run mixed | `BeforeDiscovery` vs `BeforeAll` separation |

### Key Migration Rules

1. **Preserve the module GUID** — it is the PowerShell Gallery identity
2. **Explicit `FunctionsToExport`** — never use wildcards (`'*'`)
3. **Remove `#Requires`** from source files — use manifest `RequiredModules` instead
4. **Copy `build.ps1` and `Resolve-Dependency.*`** verbatim from a reference project
5. **Start with `CodeCoverageThreshold: 0`** — increase after baseline established

---

## Community and Configuration Files

### Required Files

| File | Purpose |
|---|---|
| `CHANGELOG.md` | [Keep a Changelog 1.1.0](https://keepachangelog.com) format, imperative mood |
| `CONTRIBUTING.md` | Contribution guidelines |
| `CODE_OF_CONDUCT.md` | Link to `https://opensource.microsoft.com/codeofconduct/` |
| `SECURITY.md` | Security vulnerability reporting policy |
| `README.md` | Project documentation with badges |
| `LICENSE` | License text (typically MIT for OSS modules) |

### Required Configuration Files

| File | Purpose |
|---|---|
| `.gitignore` | Must include `output/` |
| `.gitattributes` | Line ending configuration |
| `.markdownlint.json` | Markdown linting rules |
| `codecov.yml` | Codecov integration settings |

### Essential .gitignore Entries

```gitignore
output/
.kitchen/
.vagrant/
Modules/
*.dsc.temp
*.tmp
```

### Locally Patching Third-Party Modules

When a third-party module from the PSGallery has a bug that blocks your project, use this pattern to patch it locally without losing changes on clean builds:

1. **Comment out in `RequiredModules.psd1`** — add a comment explaining the patch:
   ```powershell
   #RemoteDesktopServicesDsc     = '4.0.0' # Patched locally: replaced Assert-Module with Import-Module -Global for CDXML module
   #ConfigMgrCBDsc               = '4.0.0' # Patched locally for 2509 support
   #OfficeOnlineServerDsc        = '1.5.0' # Patched: added -WorkingDirectory to Start-Process
   ```

2. **Add a `.gitignore` exception** so the patched module is tracked in source control:
   ```gitignore
   # In .gitignore — the standard pattern:
   !output/RequiredModules           # Keep the folder
   output/RequiredModules/*          # Ignore everything inside
   !output/RequiredModules/MyPatchedModule  # Except the patched module
   ```

3. **Apply the patch** directly to the module files in `output/RequiredModules/<ModuleName>/`.

4. **The build will use the git-tracked copy** — since `Resolve-Dependency` only downloads modules listed in `RequiredModules.psd1`, commenting out the entry prevents overwriting the patched version.

> **Important**: When the upstream fix is released, uncomment the entry in `RequiredModules.psd1`, remove the `.gitignore` exception, delete the local copy, and run `-ResolveDependency` to get the fixed version.

#### Known Patched Modules (ProjectDagger)

| Module | Version | Patch Description |
|---|---|---|
| `RemoteDesktopServicesDsc` | 4.0.0 | Replaced `Assert-Module -ImportModule` with `Import-Module -Global` in all 9 `DSC_RD*.psm1` resources — CDXML proxy commands not visible in DSC WMI host (`wmiprvse.exe`) |
| `ConfigMgrCBDsc` | 4.0.0 | Added SCCM 2509 support, scheduled task for `SetupWpf.exe` mutex |
| `OfficeOnlineServerDsc` | 1.5.0 | Added `-WorkingDirectory` to `Start-Process` in Install resources (exit code 30066 on Server 2025) |
| `cScom` | 1.0.5 | Multiple bug fixes |
| `HyperVDsc` | 4.1.5 | Combines PRs 208, 209, 210 |

---

## Build Task Variables Reference

These variables influence build task behavior. Set via command line, environment variable, parent scope, or `build.yaml`.

| Variable | Default | Description |
|---|---|---|
| `OutputDirectory` | `output` | Base directory for all build output |
| `BuiltModuleSubdirectory` | (empty) | Subdirectory under `OutputDirectory` for built module |
| `BuildModuleOutput` | `OutputDirectory` + `BuiltModuleSubdirectory` | Full path where module is built |
| `ModuleVersion` | GitVersion `NuGetVersionV2` | Module version for the build |
| `ProjectPath` | `$BuildRoot` | Root path of the project |
| `ProjectName` | Module manifest `BaseName` | Project/module name |
| `SourcePath` | Auto-detected | Path to `source/` or `src/` folder |
| `ReleaseNotesPath` | `OutputDirectory/ReleaseNotes.md` | Path to release notes output |

---

## Sampler Commands Reference

### Project Commands

| Command | Purpose |
|---|---|
| `New-SampleModule` | Scaffold a new module project from a template |
| `Add-Sample` | Add functions, classes, DSC resources to existing project |
| `Invoke-SamplerGit` | Execute git commands with error handling |

### Build Task Helper Commands

| Command | Purpose |
|---|---|
| `Set-SamplerTaskVariable` | Set common task variables (dot-source in build tasks) |
| `Get-SamplerProjectName` | Get project name from module manifest |
| `Get-SamplerSourcePath` | Get source folder path |
| `Get-BuiltModuleVersion` | Get version of built module |
| `Get-SamplerBuiltModuleBase` | Get built module base path |
| `Get-SamplerBuiltModuleManifest` | Get built module manifest path |
| `Get-SamplerModuleInfo` | Load manifest hashtable (cross-edition safe) |
| `Get-SamplerModuleRootPath` | Get root module path from manifest |
| `Get-SamplerAbsolutePath` | Resolve absolute path (cross-platform) |
| `Split-ModuleVersion` | Parse SemVer string into components |
| `Get-CodeCoverageThreshold` | Get configured coverage threshold |
| `Get-OperatingSystemShortName` | Get platform identifier (Windows/Linux/MacOS) |
| `Get-PesterOutputFileFileName` | Generate Pester output filename |

### Code Coverage Commands

| Command | Purpose |
|---|---|
| `New-SamplerJaCoCoDocument` | Create JaCoCo XML from Pester results |
| `Merge-JaCoCoReport` | Merge two JaCoCo reports |
| `Update-JaCoCoStatistic` | Update statistics in merged JaCoCo report |
| `Out-SamplerXml` | Write XML document to file |
| `Get-SamplerCodeCoverageOutputFile` | Get coverage output path from config |
| `Get-SamplerCodeCoverageOutputFileEncoding` | Get coverage encoding from config |
| `Convert-SamplerHashtableToString` | Convert hashtable to string representation |

---

## Summary Checklist

Use this checklist when creating or auditing a Sampler-based project:

### Standard Module Projects

1. [ ] Project scaffolded with `New-SampleModule` or equivalent structure
2. [ ] Source code in `source/Public/` and `source/Private/` (one function per file)
3. [ ] Module manifest at `source/<ModuleName>.psd1` with explicit exports
4. [ ] Empty `source/<ModuleName>.psm1` placeholder
5. [ ] `build.ps1` and `Resolve-Dependency.*` present (standard, unmodified)
6. [ ] `build.yaml` configured with correct workflows and Pester `Script` key
7. [ ] `RequiredModules.psd1` lists all build and runtime dependencies
8. [ ] `GitVersion.yml` configured for your branching strategy
9. [ ] `ModuleBuildTasks` includes both `Sampler` and `Sampler.GitHubTasks`
10. [ ] Tests in `tests/QA/`, `tests/Unit/`, and optionally `tests/Integration/`
11. [ ] Tests use Pester 5 syntax with `BeforeAll`/`BeforeDiscovery` separation
12. [ ] CI/CD pipeline with Build, Test (multi-edition), and Deploy stages
13. [ ] `Agent.Source.Git.ShallowFetchDepth: 0` in CI configuration
14. [ ] Deploy conditions include org-name filter
15. [ ] Pipeline secrets configured (`GitHubToken`, `GalleryApiToken`)
16. [ ] `output/` in `.gitignore`
17. [ ] Community files present (CHANGELOG, CONTRIBUTING, CODE_OF_CONDUCT, SECURITY)
18. [ ] README with badges (build status, gallery version, coverage)
19. [ ] `.vscode/` settings and `tasks.json` configured for PSScriptAnalyzer
20. [ ] First build succeeds: `./build.ps1 -ResolveDependency -Tasks test`
21. [ ] Code coverage threshold set appropriately (start at 0, increase over time)
22. [ ] Module GUID preserved from any prior publication

### DSC / Datum Configuration Data Projects (Additional)

23. [ ] `source/Datum.yml` defines resolution precedence and merge strategies
24. [ ] Node definitions in `source/AllNodes/<Environment>/<NodeName>.yml`
25. [ ] Role definitions in `source/Roles/<Role>.yml`
26. [ ] Baseline configurations in `source/Baselines/`
27. [ ] `RequiredModules.psd1` includes Datum, DSC resources, and composite resource modules
28. [ ] `ModuleBuildTasks` includes `Sampler.DscPipeline`, `DscResource.Test`, `DscResource.DocGenerator`
29. [ ] `Sampler.DscPipeline.DscCompositeResourceModules` configured in `build.yaml`
30. [ ] `SetPSModulePath` configured with `RemovePersonal: true` and `RemoveProgramFiles: true`
31. [ ] `BuiltModuleSubDirectory: Module` set in `build.yaml`
32. [ ] PowerShell5Compatibility task present in `.build/` for cross-edition builds
33. [ ] `tests/ConfigData/` validates YAML structure and composite resource dependencies
34. [ ] `tests/Acceptance/` verifies MOF artifacts post-build
35. [ ] HQRM tests configured via `DscTest` section in `build.yaml`
36. [ ] Pipeline publishes separate artifacts (MOF, MetaMOF, CompressedModules, RSOP)
37. [ ] Build workflow includes DSC tasks (LoadDatumConfigData, CompileDatumRsop, CompileRootConfiguration)

---

## References

- [Sampler GitHub Repository](https://github.com/gaelcolas/Sampler)
- [Sampler on PowerShell Gallery](https://www.powershellgallery.com/packages/Sampler/)
- [ModuleBuilder](https://github.com/PoshCode/ModuleBuilder)
- [InvokeBuild](https://github.com/nightroman/Invoke-Build)
- [GitVersion Documentation](https://gitversion.net/docs/)
- [Pester 5 Documentation](https://pester.dev/)
- [PSScriptAnalyzer](https://github.com/PowerShell/PSScriptAnalyzer)
- [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
- [DSC Community Style Guidelines](https://dsccommunity.org/styleguidelines/)
- [PSResourceGet](https://github.com/PowerShell/PSResourceGet)
- [ModuleFast](https://github.com/JustinGrote/ModuleFast)
- [DscWorkshop](https://github.com/dsccommunity/DscWorkshop) — Blueprint for DSC projects using Sampler + Datum
- [Datum](https://github.com/gaelcolas/Datum) — Hierarchical configuration data management for DSC
- [Sampler.DscPipeline](https://github.com/gaelcolas/Sampler.DscPipeline) — DSC pipeline build tasks for Sampler
- [DscConfig.Demo](https://github.com/raandree/DscConfig.Demo) — DSC composite resource collection with YAML reference documentation
- [DscResource.Test](https://github.com/dsccommunity/DscResource.Test) — HQRM testing for DSC resources
- [The Release Pipeline Model (Whitepaper)](https://github.com/dsccommunity/DscWorkshop/blob/main/Exercises/TheReleasePipelineModel.pdf)
