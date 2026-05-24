---
name: sampler-framework
description: >-
  Reference for the Sampler PowerShell module build framework: project structure, build.yaml, dependency management, build workflows and tasks, custom build tasks, testing patterns, GitVersion versioning, CI/CD pipelines (Azure Pipelines, GitHub Actions), DSC/Datum configuration data projects, VSCode integration, multi-module repositories, community files, troubleshooting, and command reference. USE FOR: Sampler, build.yaml, RequiredModules.psd1, Resolve-Dependency, ModuleBuilder, InvokeBuild, New-SampleModule, Add-Sample, Sampler project structure, PowerShell module build, GitVersion configuration, CI/CD pipeline, Azure Pipelines PowerShell, DSC Datum, DscWorkshop, Sampler.DscPipeline, custom build task, Pester configuration, code coverage threshold, NuGet, Publish-Module, PowerShell Gallery, Set-SamplerTaskVariable, multi-module repository, patched module. DO NOT USE FOR: debugging Sampler builds (sampler-build-debug), legacy migration (sampler-migration), Pester syntax, AutomatedLab.
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

Standard Sampler folder layout (``source/``, ``tests/``, ``output/``, ``RequiredModules.psd1``, ``build.yaml``, ``build.ps1``) and what each path is for — read [`references/project-structure.md`](references/project-structure.md).

## Module Manifest Conventions

Conventions for ``.psd1`` manifests under Sampler — ``ModuleVersion`` placeholder, ``FunctionsToExport``, ``PrivateData.PSData``, and how ModuleBuilder merges them — read [`references/module-manifest.md`](references/module-manifest.md).

## Build Configuration (build.yaml)

Full ``build.yaml`` schema, every key, code-coverage thresholds, file copy patterns, and worked examples — read [`references/build-yaml.md`](references/build-yaml.md).

## Dependency Management (RequiredModules.psd1)

``RequiredModules.psd1`` schema, version-pinning patterns, gallery vs local sources, and dependency-resolution configuration — read [`references/dependency-management.md`](references/dependency-management.md).

## Dependency Resolution Configuration

``Resolve-Dependency.psd1`` settings, gallery configuration, allow-pre-release, and proxy options — read [`references/dependency-resolution.md`](references/dependency-resolution.md).

## Bootstrap Process (build.ps1)

How ``build.ps1`` bootstraps dependencies, parameter handling, and customisation hooks — read [`references/bootstrap.md`](references/bootstrap.md).

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

Writing custom InvokeBuild tasks, ``Set-SamplerTaskVariable`` pattern, task dependencies, and integration with the default workflow — read [`references/custom-build-tasks.md`](references/custom-build-tasks.md).

## Testing Patterns

Pester 5 test scaffolding, Unit/Integration/QA folder conventions, code coverage configuration, mock patterns, and parametrised test recipes — read [`references/testing-patterns.md`](references/testing-patterns.md).

## Versioning with GitVersion

GitVersion.yml configuration, branch strategies, version source override, and ModuleVersion injection during build — read [`references/gitversion.md`](references/gitversion.md).

## CI/CD Integration

Azure Pipelines and GitHub Actions templates, build/test/publish stage layout, artefact handling, and gallery publishing — read [`references/ci-cd-pipelines.md`](references/ci-cd-pipelines.md).

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

Patterns for repositories that build multiple modules from one Sampler tree — read [`references/multi-module.md`](references/multi-module.md).

## DSC and Datum Configuration Data Projects

DscWorkshop/Sampler.DscPipeline structure, Datum hierarchy and merge strategies, role composition, MOF compilation pipeline, and reference-implementation walkthrough — read [`references/dsc-datum.md`](references/dsc-datum.md).

## VSCode Integration

VS Code tasks.json/launch.json templates, PowerShell extension settings, debugger configuration, and recommended extensions for Sampler projects — read [`references/vscode-integration.md`](references/vscode-integration.md).

## Common Pitfalls and Troubleshooting

Build failures, dependency resolution errors, version mismatch symptoms, GitVersion edge cases, and known Sampler bugs with workarounds — read [`references/troubleshooting.md`](references/troubleshooting.md).

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

CHANGELOG.md, CODE_OF_CONDUCT.md, CONTRIBUTING.md, SECURITY.md, issue/PR templates, and ``.editorconfig`` conventions — read [`references/community-files.md`](references/community-files.md).

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

Full reference for ``New-SampleModule``, ``Add-Sample``, ``Set-SamplerTaskVariable``, ``Invoke-SamplerTask``, and other Sampler cmdlets — read [`references/commands-reference.md`](references/commands-reference.md).

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
