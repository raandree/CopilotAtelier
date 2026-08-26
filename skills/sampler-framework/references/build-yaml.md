# Build Configuration (build.yaml)

Extracted from `Skills/sampler-framework/SKILL.md` to keep the main skill body under Anthropic's 500-line budget.

## Contents

- Minimal build.yaml
- Key build.yaml Sections

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

