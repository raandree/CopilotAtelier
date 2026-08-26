# Project Structure

Extracted from `Skills/sampler-framework/SKILL.md` to keep the main skill body under Anthropic's 500-line budget.

## Contents

- Key Conventions

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

