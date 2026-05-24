# Sampler Commands Reference

Extracted from `Skills/sampler-framework/SKILL.md` to keep the main skill body under Anthropic's 500-line budget.

## Contents

- Project Commands
- Build Task Helper Commands
- Code Coverage Commands

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

