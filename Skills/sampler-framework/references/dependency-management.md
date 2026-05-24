# Dependency Management (RequiredModules.psd1)

Extracted from `Skills/sampler-framework/SKILL.md` to keep the main skill body under Anthropic's 500-line budget.

## Contents

- Standard RequiredModules.psd1
- Version Specification Syntax
- ModuleFast-Only Syntax (PowerShell 7.2+)

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

