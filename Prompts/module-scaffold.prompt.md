---
agent: software-engineer
description: Scaffold a new PowerShell module project using the Sampler build framework.
---

# Sampler Module Scaffold

Scaffold a new PowerShell module project using the Sampler build framework with all
standard conventions and configurations pre-applied.

## Instructions

Generate a complete Sampler-based PowerShell module project structure with all required
files and configurations. Follow each phase in order.

## Phase 1 — Gather Information

Ask for the following if not provided:
- **Module name** (PascalCase, e.g., `NetworkTools`)
- **Description** (one sentence)
- **Author name** (default: Git `user.name`)
- **License** (default: MIT)
- **Minimum PowerShell version** (default: 5.1)

## Phase 2 — Create Directory Structure

```
<ModuleName>/
├── .github/
│   └── PULL_REQUEST_TEMPLATE.md
├── .vscode/
│   ├── settings.json
│   └── tasks.json
├── source/
│   ├── Public/
│   │   └── .gitkeep
│   ├── Private/
│   │   └── .gitkeep
│   ├── Classes/
│   │   └── .gitkeep
│   ├── Enum/
│   │   └── .gitkeep
│   └── <ModuleName>.psd1
├── tests/
│   ├── QA/
│   │   └── module.tests.ps1
│   └── Unit/
│       ├── Public/
│       │   └── .gitkeep
│       └── Private/
│           └── .gitkeep
├── .gitignore
├── .gitattributes
├── build.ps1
├── build.yaml
├── CHANGELOG.md
├── GitVersion.yml
├── LICENSE
├── README.md
├── RequiredModules.psd1
└── Resolve-Dependency.psd1
```

## Phase 3 — Generate Core Files

#### `build.yaml`

```yaml
---
CopyPaths:
  - en-US
Encoding: UTF8
VersionedOutputDirectory: true

####################################################
# Resolve-Dependency parameters
####################################################
Prefix: ''
AvailablePSModuleScope: CurrentUser
PSModuleScope: CurrentUser

####################################################
# ModuleBuilder parameters
####################################################
SourcePath: ./source
BuiltModuleSubdirectory: builtModule
CopyPaths:
  - en-US

####################################################
# Pester parameters
####################################################
Pester:
  Configuration:
    Run:
      Path:
        - tests/QA
        - tests/Unit
    Output:
      Verbosity: Detailed
    CodeCoverage:
      Enabled: true
      OutputFormat: JaCoCo
      CoveragePercentTarget: 80
    TestResult:
      Enabled: true
      OutputFormat: NUnitXml

####################################################
# Build tasks
####################################################
BuildWorkflow:
  '.':
    - build
    - test

  build:
    - Clean
    - Build_Module_ModuleBuilder
    - Build_NestedModules_ModuleBuilder
    - Create_changelog_release_output

  pack:
    - build
    - package_module_nupkg

  test:
    - Pester_Tests_Stop_On_Fail
    - Pester_if_Code_Coverage_Under_Threshold

  publish:
    - publish_module_to_gallery
```

#### `RequiredModules.psd1`

```powershell
@{
    PSDependOptions  = @{
        AddToPath  = $true
        Target     = 'output\RequiredModules'
        Parameters = @{
            Repository = 'PSGallery'
        }
    }

    InvokeBuild           = 'latest'
    PSScriptAnalyzer      = 'latest'
    Pester                = 'latest'
    Plaster               = 'latest'
    ModuleBuilder         = 'latest'
    MarkdownLinkCheck     = 'latest'
    ChangelogManagement   = 'latest'
    Sampler               = 'latest'
    'Sampler.GitHubTasks' = 'latest'
    'DscResource.Test'    = 'latest'
}
```

#### `GitVersion.yml`

```yaml
---
assembly-versioning-scheme: MajorMinorPatch
assembly-file-versioning-scheme: MajorMinorPatch
mode: ContinuousDelivery
major-version-bump-message: 'breaking\s*:'
minor-version-bump-message: 'feat\s*[:(]'
patch-version-bump-message: 'fix\s*[:(]'
next-version: 0.1.0
branches:
  main:
    mode: ContinuousDelivery
    tag: ''
    increment: Patch
    prevent-increment-of-merged-branch-version: true
  feature:
    mode: ContinuousDelivery
    tag: alpha
    increment: Minor
  hotfix:
    mode: ContinuousDelivery
    tag: beta
    increment: Patch
```

#### `Resolve-Dependency.psd1`

```powershell
@{
    Gallery         = 'PSGallery'
    AllowPrerelease = $false
    WithYAML        = $true
}
```

#### Module Manifest (`source/<ModuleName>.psd1`)

Generate a standard module manifest using `New-ModuleManifest` parameters:
- `RootModule` = `<ModuleName>.psm1`
- `ModuleVersion` = `0.0.1`
- `GUID` = (generate new)
- `PowerShellVersion` = user-specified minimum
- `Description` = user-provided description
- `FunctionsToExport` = `@()` (ModuleBuilder will auto-populate)
- `CmdletsToExport` = `@()`
- `VariablesToExport` = `@()`
- `AliasesToExport` = `@()`
- `PrivateData.PSData.Tags` = relevant tags
- `PrivateData.PSData.LicenseUri` = license URL
- `PrivateData.PSData.ProjectUri` = repository URL

#### `CHANGELOG.md`

```markdown
# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Initial module scaffolding using Sampler framework
```

#### `.gitignore`

```gitignore
output/
RequiredModules/
*.nupkg
Thumbs.db
.DS_Store
```

#### `.gitattributes`

```gitattributes
* text=auto
*.ps1  text eol=crlf
*.psm1 text eol=crlf
*.psd1 text eol=crlf
*.md   text eol=lf
*.yml  text eol=lf
*.yaml text eol=lf
```

#### QA Tests (`tests/QA/module.tests.ps1`)

Generate the standard Sampler QA test file that validates:
- Module manifest is valid
- GUID is not empty
- Exported functions use approved verbs
- All exported functions have help with synopsis, description, and examples

#### `README.md`

Generate a README with:
- Module name and description
- Installation instructions (`Install-Module`)
- Quick start example
- Build instructions (`.\build.ps1 -ResolveDependency`)
- Link to CHANGELOG.md

## Phase 4 — Initialize Git Repository

```powershell
Set-Location <ModuleName>
git init
git add .
git commit -m 'feat: initial Sampler module scaffold'
```

## Phase 5 — Summary

After scaffolding, print:
- The directory structure created
- How to build: `.\build.ps1 -ResolveDependency -Tasks build`
- How to test: `.\build.ps1 -Tasks test`
- Next steps: add functions to `source/Public/`, add tests to `tests/Unit/Public/`
