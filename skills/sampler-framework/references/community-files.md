# Community and Configuration Files

Extracted from `Skills/sampler-framework/SKILL.md` to keep the main skill body under Anthropic's 500-line budget.

## Contents

- Required Files
- Required Configuration Files
- Essential .gitignore Entries
- Locally Patching Third-Party Modules

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

