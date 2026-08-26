# Module Manifest Conventions

Extracted from `Skills/sampler-framework/SKILL.md` to keep the main skill body under Anthropic's 500-line budget.

## Contents

- Manifest Rules

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

