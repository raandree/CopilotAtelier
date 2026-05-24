# Dependency Resolution Configuration

Extracted from `Skills/sampler-framework/SKILL.md` to keep the main skill body under Anthropic's 500-line budget.

## Contents

- Resolve-Dependency.psd1
- Resolution Methods
- Priority When Multiple Methods Enabled
- Command-Line Override

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

