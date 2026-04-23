---
applyTo: "**/GitVersion.yml,**/*.psd1,**/CHANGELOG.md"
---

# Versioning Best Practices and Standards

## Semantic Versioning

### Overview

Follow [Semantic Versioning 2.0.0](https://semver.org/) for all module and project versioning.

**Version Format**: `MAJOR.MINOR.PATCH[-PRERELEASE][+BUILD]`

**Version Components:**
- **MAJOR**: Incompatible API changes (breaking changes)
- **MINOR**: Backwards-compatible new functionality
- **PATCH**: Backwards-compatible bug fixes
- **PRERELEASE**: Optional pre-release identifier (alpha, beta, rc)
- **BUILD**: Optional build metadata

### Version Increment Rules

**Increment MAJOR version when:**
- ✅ Making incompatible API changes
- ✅ Removing features or functionality
- ✅ Changing behavior that breaks existing implementations
- ✅ Renaming or removing parameters
- ✅ Changing default values that affect behavior
- ✅ Requiring higher minimum PowerShell version
- ✅ Breaking changes in data structures or schemas

**Increment MINOR version when:**
- ✅ Adding new features in a backwards-compatible manner
- ✅ Adding new functions, cmdlets, or resources
- ✅ Adding new parameters with default values
- ✅ Deprecating features (but not removing them yet)
- ✅ Substantial internal improvements that add value

**Increment PATCH version when:**
- ✅ Making backwards-compatible bug fixes
- ✅ Fixing issues that don't change functionality
- ✅ Correcting typos in error messages
- ✅ Performance improvements without API changes
- ✅ Updating dependencies to patch versions

**Do NOT increment version for:**
- ❌ Documentation-only changes
- ❌ Comment updates
- ❌ Code formatting/style changes
- ❌ Test-only changes (unless fixing test bugs)
- ❌ CI/CD pipeline changes

### Pre-release Versions

Use pre-release identifiers for versions not yet ready for production:

```plaintext
1.0.0-alpha.1    # Early testing, unstable
1.0.0-beta.1     # Feature complete, testing
1.0.0-rc.1       # Release candidate, final testing
1.0.0            # Stable release
```

**Pre-release Guidelines:**
- Alpha: Early development, expect breaking changes
- Beta: Feature complete, stabilizing
- RC (Release Candidate): Final testing, no new features
- Use numeric suffixes for iterations: `alpha.1`, `alpha.2`, etc.

### Initial Development (0.y.z)

Major version zero (`0.y.z`) has special semantics in SemVer:

- **0.y.z is for initial development** — anything MAY change at any time
- The public API SHOULD NOT be considered stable
- Breaking changes MAY occur in MINOR or PATCH increments
- Start initial development at `0.1.0` and increment MINOR for each release
- Transition to `1.0.0` when the public API is stable and used in production

**When to Release 1.0.0:**
- Software is used in production
- Users depend on a stable API
- You are actively managing backward compatibility
- You need to communicate breaking vs. non-breaking changes clearly

> **Tip:** If you are worrying about backward compatibility, you should probably already be at `1.0.0`.

### Build Metadata

Build metadata is appended after a `+` sign following the patch or pre-release version:

```plaintext
1.0.0+20240115.sha.abc1234
1.0.0-beta.1+build.42
1.2.3+exp.sha.5114f85
```

**Rules:**
- Build metadata MUST be ignored when determining version precedence
- Two versions that differ only in build metadata have **equal** precedence
- Identifiers MUST comprise only ASCII alphanumerics and hyphens `[0-9A-Za-z-]`
- Use for traceability — embed commit SHA, build number, or timestamp
- Do NOT rely on build metadata for ordering or uniqueness

### Version Precedence (Comparison / Sort Order)

Precedence determines how versions are compared when ordered:

1. Separate version into MAJOR, MINOR, PATCH, and pre-release identifiers (build metadata is excluded)
2. Compare MAJOR, MINOR, PATCH **numerically** from left to right
3. When MAJOR.MINOR.PATCH are equal, a **pre-release** version has **lower** precedence than the normal version
4. Pre-release identifiers are compared dot-segment by dot-segment:
   - Numeric identifiers are compared as integers
   - Alphanumeric identifiers are compared lexically (ASCII sort order)
   - Numeric identifiers always have lower precedence than alphanumeric
   - A larger set of fields has higher precedence when all preceding fields are equal

**Complete Precedence Example:**

```plaintext
1.0.0-alpha < 1.0.0-alpha.1 < 1.0.0-alpha.beta < 1.0.0-beta
< 1.0.0-beta.2 < 1.0.0-beta.11 < 1.0.0-rc.1 < 1.0.0
```

### SemVer Validation Regex

Use the official regex from semver.org to validate version strings:

```regex
^(?P<major>0|[1-9]\d*)\.(?P<minor>0|[1-9]\d*)\.(?P<patch>0|[1-9]\d*)(?:-(?P<prerelease>(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?(?:\+(?P<buildmetadata>[0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?$
```

**PowerShell validation:**

```powershell
$semverPattern = '^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-((?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?(?:\+([0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?$'
if ($version -notmatch $semverPattern) {
    throw "Invalid SemVer: $version"
}
```

### Tag Prefix Convention

> **"v1.2.3" is NOT a semantic version.** The semantic version is `1.2.3`. The `v` prefix is a common convention for Git tag names but is not part of SemVer.

- Git tags: use `v` prefix (`v1.2.3`) — this is a tag name, not a version
- Module manifests: use bare version (`1.2.3`) — no `v` prefix
- GitVersion `tag-prefix` defaults to `[vV]?` and strips the prefix automatically
- Be consistent within a project; never mix `v1.2.3` and `1.2.3` tags

## Alternative Versioning Schemes

### Calendar Versioning (CalVer)

[CalVer](https://calver.org/) uses the project's release calendar instead of arbitrary numbers.

**Common CalVer Formats:**

| Token | Meaning | Example |
|-------|---------|--------|
| `YYYY` | Full year | 2024 |
| `YY` | Short year (relative to 2000) | 24 |
| `0Y` | Zero-padded year | 24 |
| `MM` / `0M` | Short / zero-padded month | 1 / 01 |
| `DD` / `0D` | Short / zero-padded day | 5 / 05 |
| `MINOR` | Incremented number | 3 |
| `MICRO` | Patch-level increment | 1 |

**Notable CalVer Users:**

| Project | Scheme | Example |
|---------|--------|---------|
| Ubuntu | `YY.0M` | `24.04` |
| pip | `YY.MINOR.MICRO` | `24.0.1` |
| Unity | `YYYY.MINOR.MICRO` | `2024.1.0` |
| Stripe API | `YYYY-MM-DD` | `2024-01-15` |

**When to Consider CalVer:**
- Large systems with constantly-changing scope (frameworks, OSes)
- Time-sensitive projects (security certificates, timezone databases)
- When external changes (not code changes) drive releases
- When support schedules are tied to release dates

**When to Prefer SemVer Over CalVer:**
- Libraries with a clear public API
- When consumers need to know if an update is safe (non-breaking)
- PowerShell modules published to PSGallery (SemVer is the convention)

### Hybrid Schemes

Some projects combine CalVer with SemVer:

```plaintext
YY.MM.MINOR   # Calendar major, incremented minor
YYYY.MINOR.PATCH  # Year-based major, semantic minor/patch
```

> **Recommendation for PowerShell modules:** Use SemVer. CalVer is better suited for platforms, operating systems, and API versioning.

## GitVersion

### What is GitVersion?

GitVersion is an automated versioning tool that:
- Calculates semantic versions based on Git history
- Uses branch names and commit messages to determine version increments
- Integrates with CI/CD pipelines
- Ensures consistent versioning across artifacts
- Eliminates manual version management

### GitVersion Workflows

GitVersion ships with three built-in workflow templates. Specify one in your `GitVersion.yml`:

| Workflow | Value | Use Case |
|----------|-------|----------|
| **GitFlow** | `GitFlow/v1` | Projects with develop, release, and hotfix branches |
| **GitHubFlow** | `GitHubFlow/v1` | Simpler flow — feature branches merge to main |
| **Trunk-Based** | `TrunkBased/preview1` | Continuous integration; short-lived branches only |

```yaml
workflow: GitHubFlow/v1     # or GitFlow/v1 or TrunkBased/preview1
```

> Run `gitversion /showConfig` to view the effective configuration (defaults + overrides).

### GitVersion Deployment Modes

Each branch can operate in one of three deployment modes:

| Mode | Behaviour | Typical Branch |
|------|-----------|----------------|
| `ManualDeployment` | Version stays on the same pre-release until explicitly deployed/tagged | release, hotfix, feature |
| `ContinuousDelivery` | Pre-release counter increments on every commit; stable version only after tagging | develop, pull-request |
| `ContinuousDeployment` | Every commit produces a unique, deployable version; no tagging needed | main (trunk-based) |

```yaml
branches:
  main:
    mode: ContinuousDeployment    # every merge increments automatically
  develop:
    mode: ContinuousDelivery      # counter increments; tag to release
  feature:
    mode: ManualDeployment        # version stays stable during development
```

### Basic GitVersion Configuration

Create `GitVersion.yml` in repository root:

```yaml
workflow: GitHubFlow/v1
branches:
  main:
    label: ''
  feature:
    label: '{BranchName}'
ignore:
  sha: []
```

**Key Settings:**
- `workflow` - Base template (GitFlow/v1, GitHubFlow/v1, TrunkBased/preview1)
- `mode` - Deployment mode per branch (ManualDeployment, ContinuousDelivery, ContinuousDeployment)
- `label` - Pre-release label for versions (empty string `''` = stable release)
- `increment` - Which part to bump: Major, Minor, Patch, Inherit, None
- `branches` - Per-branch versioning strategies
- `ignore` - Commits or paths to exclude from versioning

### Advanced GitVersion Configuration (DSC Community Standard)

For PowerShell modules following DSC Community patterns:

```yaml
mode: Mainline
assembly-versioning-scheme: MajorMinorPatch
assembly-file-versioning-scheme: MajorMinorPatch
next-version: 1.0.0
major-version-bump-message: '\+semver:\s?(breaking|major)'
minor-version-bump-message: '\+semver:\s?(feature|minor)'
patch-version-bump-message: '\+semver:\s?(fix|patch)'
no-bump-message: '\+semver:\s?none'
legacy-semver-padding: 4
build-metadata-padding: 4
commits-since-version-source-padding: 4

branches:
  main:
    tag: ''
    regex: ^master$|^main$
    source-branches: ['develop', 'release']
    is-release-branch: true
    
  develop:
    tag: 'preview'
    regex: ^dev(elop)?(ment)?$
    source-branches: []
    is-release-branch: false
    
  feature:
    tag: 'preview'
    regex: ^features?[/-]
    source-branches: ['develop']
    increment: Minor
    
  pull-request:
    tag: 'PR'
    regex: ^(pull|pull\-requests|pr)[/-]
    source-branches: ['develop', 'main', 'release', 'feature', 'hotfix']
    tag-number-pattern: '[/-](?<number>\d+)'
    
  hotfix:
    tag: 'fix'
    regex: ^hotfix(es)?[/-]
    source-branches: ['main']
    
  release:
    tag: ''
    regex: ^releases?[/-]
    source-branches: ['develop']
    is-release-branch: true

ignore:
  sha: []
```

**Configuration Explained:**
- **assembly-versioning-scheme**: How assembly versions are calculated
- **next-version**: Starting version for new repositories
- **bump-message patterns**: Regex to detect version increment from commits
- **padding**: Zero-padding for version components
- **Branch strategies**: Different versioning per branch type

## Commit Message Conventions

### Conventional Commits

Use [Conventional Commits](https://www.conventionalcommits.org/) format:

```plaintext
<type>(<scope>): <description>

[optional body]

[optional footer(s)]
```

**Common Types:**
- `feat`: New feature (increments MINOR)
- `fix`: Bug fix (increments PATCH)
- `docs`: Documentation only
- `style`: Code style/formatting
- `refactor`: Code restructuring
- `test`: Adding/updating tests
- `chore`: Maintenance tasks
- `perf`: Performance improvements
- `ci`: CI/CD changes
- `build`: Build system changes

**Breaking Changes:**
Add `BREAKING CHANGE:` in footer or `!` after type:

```plaintext
feat!: remove legacy API endpoint

BREAKING CHANGE: The /api/v1/legacy endpoint has been removed.
Use /api/v2/resource instead.
```

### SemVer Hints in Commit Messages

Override GitVersion's default behavior with `+semver:` hints:

```plaintext
feat: add new caching layer +semver: minor
fix: correct parameter validation +semver: patch
refactor: restructure authentication +semver: major
docs: update README +semver: none
```

**SemVer Hint Options:**
- `+semver: major` or `+semver: breaking` - Force major increment
- `+semver: minor` or `+semver: feature` - Force minor increment
- `+semver: patch` or `+semver: fix` - Force patch increment
- `+semver: none` - Skip version increment

### Commit Message Examples

**Feature Addition:**
```plaintext
feat(user-management): add password reset functionality

Implements password reset via email verification.
Includes new Send-PasswordResetEmail function.

Closes #123
```

**Bug Fix:**
```plaintext
fix(validation): correct email regex pattern

The previous regex allowed invalid email formats.
Updated to RFC 5322 compliant pattern.

Fixes #456
```

**Breaking Change:**
```plaintext
feat(api)!: change authentication to OAuth 2.0

BREAKING CHANGE: Basic authentication is no longer supported.
All clients must migrate to OAuth 2.0.

Migration guide: docs/oauth-migration.md
```

**Documentation Update:**
```plaintext
docs: update installation instructions +semver: none

Added troubleshooting section for common installation issues.
```

## Branch-Based Versioning Strategies

### Main/Master Branch

**Purpose**: Production-ready code
**Versioning**: Stable releases without pre-release tags
**Example**: `1.2.3`

**Workflow:**
1. All merges to main create release versions
2. Tagged automatically in CI/CD
3. Published to PowerShell Gallery
4. Changelog updated with release date

### Develop Branch

**Purpose**: Integration branch for features
**Versioning**: Preview versions with `-preview` tag
**Example**: `1.3.0-preview.4`

**Workflow:**
1. Feature branches merge here
2. CI/CD builds preview versions
3. Can be published to PSGallery as prerelease
4. Merged to main when stable

### Feature Branches

**Purpose**: New feature development
**Versioning**: Preview versions with branch name
**Example**: `1.3.0-feature-caching.12`

**Workflow:**
1. Branch from develop: `feature/caching`
2. Commits increment preview counter
3. Merge to develop when complete
4. Branch deleted after merge

### Pull Request Branches

**Purpose**: Code review and validation
**Versioning**: PR-specific preview versions
**Example**: `1.2.1-PR123.5`

**Workflow:**
1. Created from feature or develop
2. Version includes PR number
3. CI/CD validates all checks
4. Merged after approval

### Hotfix Branches

**Purpose**: Critical production fixes
**Versioning**: Patch increment with `-fix` tag
**Example**: `1.2.4-fix.1`

**Workflow:**
1. Branch from main: `hotfix/critical-bug`
2. Immediate patch version increment
3. Merged to both main and develop
4. Tagged and released quickly

### Release Branches

**Purpose**: Release preparation and stabilization
**Versioning**: Release candidate versions
**Example**: `2.0.0-rc.1`

**Workflow:**
1. Branch from develop: `release/2.0.0`
2. Only bug fixes and documentation
3. No new features
4. Merged to main when stable
5. Tagged with final version

### Monorepo Versioning

GitVersion supports monorepos via `ignore.paths` — commits touching only excluded paths are skipped in version calculations:

```yaml
# Only consider commits affecting ProjectA or shared library
ignore:
  paths:
    - '^(?!\/ProjectA\/|\/SharedLib\/).*'
```

**Monorepo Guidelines:**
- Each sub-project gets its own `GitVersion.yml` with appropriate `ignore.paths`
- Use negative lookahead regex to include only relevant paths
- A commit is ignored **only** if all changed paths match the ignore patterns
- Paths are case-sensitive; use `(?i)` prefix on Windows for case-insensitive matching
- Consider separate Git tags per sub-project (e.g., `projectA/v1.2.3`)

## Version Synchronization

### Critical Requirement

**All version numbers MUST be synchronized across:**
1. Module manifest (`.psd1`) - `ModuleVersion` property
2. Changelog (`CHANGELOG.md`) - Latest `[Unreleased]` or version header
3. Git tags - Annotated tag matching release version
4. PowerShell Gallery metadata - Published version

### Module Manifest (.psd1)

**Update ModuleVersion:**

```powershell
@{
    ModuleVersion = '1.2.3'

    PrivateData = @{
        PSData = @{
            # Prerelease string — results in 1.2.3-preview on PSGallery
            Prerelease = 'preview'
        }
    }
}
```

**PowerShell Gallery Prerelease Requirements:**
- `ModuleVersion` MUST be 3-part (`Major.Minor.Build`) when using a Prerelease string
- The `Prerelease` property lives in `PrivateData.PSData`, **not** at the manifest root
- PowerShell Gallery supports **SemVer v1.0.0 only** — dots (`.`) and plus (`+`) are **not** allowed in the Prerelease string (unlike SemVer v2.0.0)
- Valid prerelease strings: `alpha`, `alpha1`, `beta`, `rc1`, `preview0045`
- Invalid prerelease strings: `alpha.1` (dot), `beta+build` (plus)
- Consumers must pass `-AllowPrerelease` to `Find-Module`, `Install-Module`, `Update-Module`, and `Save-Module`
- Side-by-side prerelease installation is **not** supported — `2.5.0-alpha` and `2.5.0-beta` share the same `2.5.0` folder

**Automated Update in CI/CD:**

```powershell
# PowerShell script to update manifest
$manifestPath = './MyModule/MyModule.psd1'
$version = $env:GitVersion_MajorMinorPatch
$prerelease = $env:GitVersion_PreReleaseTag

Update-ModuleManifest -Path $manifestPath -ModuleVersion $version
if ($prerelease) {
    Update-ModuleManifest -Path $manifestPath -Prerelease $prerelease
}
```

### Version Constraints in RequiredModules

Specify version constraints in module manifests to declare dependencies:

```powershell
@{
    RequiredModules = @(
        # Minimum version (inclusive)
        @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

        # Exact version
        @{ ModuleName = 'PSFramework'; RequiredVersion = '1.10.318' }

        # Maximum version (PowerShell 5.1+ only)
        @{ ModuleName = 'Az.Accounts'; ModuleVersion = '2.0.0'; MaximumVersion = '2.99.99' }

        # GUID for disambiguation
        @{ ModuleName = 'MyInternalLib'; GUID = 'abc12345-...'; ModuleVersion = '1.0.0' }
    )
}
```

**Best Practices:**
- Always set a minimum `ModuleVersion` for dependencies
- Use `RequiredVersion` sparingly — it prevents minor/patch upgrades
- Pin major version with `MaximumVersion` (e.g., `2.99.99`) to allow non-breaking updates
- Include the module GUID when multiple modules share a name

### PowerShell Version Types

PowerShell has two version types — understand the difference:

| Type | Parts | Supports Pre-release | Use Case |
|------|-------|---------------------|----------|
| `[System.Version]` | 4 (`Major.Minor.Build.Revision`) | No | `$PSVersionTable.PSVersion`, `ModuleVersion` manifest property |
| `[semver]` (PS 6+) | 3 + labels (`Major.Minor.Patch-Pre+Build`) | Yes | SemVer-aware comparison, manually parsed versions |

```powershell
# System.Version — 4-part, no pre-release
[version]'1.2.3'          # → 1.2.3 (Build = -1, Revision = -1)
[version]'1.2.3.0'        # → 1.2.3.0

# SemVer — 3-part, pre-release aware (PowerShell 7+ only)
[semver]'1.2.3-alpha.1'   # → Major=1, Minor=2, Patch=3, PreReleaseLabel=alpha.1
[semver]'1.2.3' -gt [semver]'1.2.3-alpha'   # → True (release > pre-release)
```

**Gotcha:** `[System.Version]` has **4** components and compares numerically; SemVer has **3** components with string-based pre-release ordering. Never mix them in the same comparison.

### Changelog (CHANGELOG.md)

**Version Header Format:**

```markdown
## [Unreleased]

### Added
- New feature descriptions

## [1.2.3] - 2024-01-15

### Fixed
- Bug fix descriptions
```

**Automated Update:**

```powershell
# Update changelog with version and date
$changelog = Get-Content -Path './CHANGELOG.md' -Raw
$version = $env:GitVersion_SemVer
$date = Get-Date -Format 'yyyy-MM-dd'

$updated = $changelog -replace '\[Unreleased\]', "[$version] - $date`n`n## [Unreleased]"
Set-Content -Path './CHANGELOG.md' -Value $updated
```

### Git Tags

**Tagging Strategy:**

```bash
# Annotated tag with message
git tag -a v1.2.3 -m "Release version 1.2.3"

# Push tag to remote
git push origin v1.2.3
```

**Automated Tagging in CI/CD:**

```yaml
# Azure Pipelines
- task: Bash@3
  inputs:
    targetType: 'inline'
    script: |
      git tag -a "v$(GitVersion.SemVer)" -m "Release $(GitVersion.SemVer)"
      git push origin "v$(GitVersion.SemVer)"
```

### Validation Requirements

**Pre-release Checklist:**
- [ ] Module manifest version matches GitVersion calculation
- [ ] CHANGELOG.md has entry for new version with date
- [ ] Git tag exists for version
- [ ] All tests pass with new version
- [ ] Documentation references correct version
- [ ] Breaking changes documented if MAJOR increment

**Automated Validation Script:**

```powershell
# Validate version synchronization
$manifestVersion = (Import-PowerShellDataFile './MyModule/MyModule.psd1').ModuleVersion
$changelogVersion = (Select-String -Path './CHANGELOG.md' -Pattern '## \[(\d+\.\d+\.\d+)\]').Matches[0].Groups[1].Value
$gitTag = git describe --tags --abbrev=0

if ($manifestVersion -ne $changelogVersion -or "v$manifestVersion" -ne $gitTag) {
    Write-Error "Version mismatch detected!"
    Write-Host "Manifest: $manifestVersion"
    Write-Host "Changelog: $changelogVersion"
    Write-Host "Git Tag: $gitTag"
    exit 1
}
```

## Automated Versioning Workflow

### Azure Pipelines Integration

**Install and Run GitVersion:**

```yaml
trigger:
  branches:
    include:
      - main
      - develop
      - feature/*
      - hotfix/*

pool:
  vmImage: 'windows-latest'

steps:
- task: gitversion/setup@0
  displayName: 'Install GitVersion'
  inputs:
    versionSpec: '5.x'

- task: gitversion/execute@0
  displayName: 'Calculate Version'
  inputs:
    useConfigFile: true
    configFilePath: 'GitVersion.yml'

- task: PowerShell@2
  displayName: 'Update Module Manifest'
  inputs:
    targetType: 'inline'
    script: |
      $version = "$(GitVersion.SemVer)"
      Update-ModuleManifest -Path './MyModule/MyModule.psd1' -ModuleVersion $version
      Write-Host "Updated manifest to version: $version"

- task: PowerShell@2
  displayName: 'Display Version Info'
  inputs:
    targetType: 'inline'
    script: |
      Write-Host "SemVer: $(GitVersion.SemVer)"
      Write-Host "Major: $(GitVersion.Major)"
      Write-Host "Minor: $(GitVersion.Minor)"
      Write-Host "Patch: $(GitVersion.Patch)"
      Write-Host "PreReleaseTag: $(GitVersion.PreReleaseTag)"
```

### GitHub Actions Integration

**GitVersion Workflow:**

```yaml
name: Version and Build

on:
  push:
    branches:
      - main
      - develop
  pull_request:

jobs:
  version:
    runs-on: windows-latest
    
    steps:
    - name: Checkout
      uses: actions/checkout@v3
      with:
        fetch-depth: 0  # Required for GitVersion
    
    - name: Install GitVersion
      uses: gittools/actions/gitversion/setup@v0
      with:
        versionSpec: '5.x'
    
    - name: Determine Version
      id: gitversion
      uses: gittools/actions/gitversion/execute@v0
      with:
        useConfigFile: true
        configFilePath: GitVersion.yml
    
    - name: Display Version
      run: |
        echo "SemVer: ${{ steps.gitversion.outputs.semVer }}"
        echo "Major: ${{ steps.gitversion.outputs.major }}"
        echo "Minor: ${{ steps.gitversion.outputs.minor }}"
        echo "Patch: ${{ steps.gitversion.outputs.patch }}"
    
    - name: Update Module Manifest
      shell: pwsh
      run: |
        $version = "${{ steps.gitversion.outputs.semVer }}"
        Update-ModuleManifest -Path './MyModule/MyModule.psd1' -ModuleVersion $version
        Write-Host "Updated to version: $version"
```

### CI/CD Version Variables

**Available GitVersion Variables:**

| Variable | Description | Example |
|----------|-------------|---------|
| `GitVersion.SemVer` | Full semantic version | `1.2.3-preview.4` |
| `GitVersion.Major` | Major version number | `1` |
| `GitVersion.Minor` | Minor version number | `2` |
| `GitVersion.Patch` | Patch version number | `3` |
| `GitVersion.PreReleaseTag` | Pre-release identifier | `preview.4` |
| `GitVersion.BuildMetaData` | Build metadata | `5.Branch.develop` |
| `GitVersion.FullSemVer` | Complete version string | `1.2.3-preview.4+5` |
| `GitVersion.InformationalVersion` | Informational version | `1.2.3-preview.4+5.Branch.develop.Sha.abc123` |

## Function-Level Versioning

### Internal Version Tracking

Track version metadata within functions for debugging and compatibility:

```powershell
function Get-UserData {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$UserId
    )
    
    # Function metadata
    $functionVersion = '1.2.0'
    $moduleVersion = $MyInvocation.MyCommand.Module.Version
    
    Write-Verbose "Function Version: $functionVersion"
    Write-Verbose "Module Version: $moduleVersion"
    
    # Function implementation
    # ...
}
```

### Version Attributes

Use PowerShell custom attributes for version documentation:

```powershell
class VersionAttribute : System.Attribute {
    [string]$Version
    [string]$Since
    [string]$Deprecated
    
    VersionAttribute([string]$version) {
        $this.Version = $version
    }
}

[Version("1.2.0")]
function Get-UserData {
    # Implementation
}
```

## Version Validation and Testing

### Pre-commit Validation

**Git Hook for Version Checks:**

```powershell
# .git/hooks/pre-commit
#!/usr/bin/env pwsh

$manifest = Import-PowerShellDataFile './MyModule/MyModule.psd1'
$changelog = Get-Content './CHANGELOG.md' -Raw

if ($changelog -notmatch "\[Unreleased\]") {
    Write-Error "CHANGELOG.md must have [Unreleased] section"
    exit 1
}

Write-Host "✓ Version validation passed"
exit 0
```

### CI/CD Validation

**Automated Version Validation:**

```yaml
- task: PowerShell@2
  displayName: 'Validate Versioning'
  inputs:
    targetType: 'inline'
    script: |
      # Validate manifest exists
      $manifestPath = './MyModule/MyModule.psd1'
      if (-not (Test-Path $manifestPath)) {
          Write-Error "Module manifest not found"
          exit 1
      }
      
      # Validate changelog format
      $changelog = Get-Content './CHANGELOG.md' -Raw
      if ($changelog -notmatch '## \[\d+\.\d+\.\d+\]') {
          Write-Error "CHANGELOG.md missing version entries"
          exit 1
      }
      
      # Validate SemVer format
      $version = (Import-PowerShellDataFile $manifestPath).ModuleVersion
      if ($version -notmatch '^\d+\.\d+\.\d+$') {
          Write-Error "Invalid semantic version: $version"
          exit 1
      }
      
      Write-Host "✓ All version validations passed"
```

## Deprecation and End-of-Life Policy

### Deprecation Lifecycle

Follow a structured process when removing or replacing functionality:

1. **Announce Deprecation** (MINOR release)
   - Mark functions with `[Obsolete()]` attribute or `Write-Warning` on first use
   - Add `### Deprecated` entry in CHANGELOG.md
   - Document migration path and replacement API

2. **Maintain Deprecated API** (at least one MINOR release cycle)
   - Keep full backward compatibility
   - Emit warnings but do not break callers
   - Update documentation with recommended alternatives

3. **Remove Deprecated API** (MAJOR release only)
   - Remove the deprecated code
   - Document the removal as a `BREAKING CHANGE`
   - Increment MAJOR version

```powershell
# Deprecation warning pattern
function Get-LegacyData {
    [CmdletBinding()]
    param()
    Write-Warning 'Get-LegacyData is deprecated and will be removed in v3.0.0. Use Get-DataV2 instead.'
    # ... existing implementation ...
}
```

### Support Policy Template

Define how long each major version receives support:

| Version | Status | Support Until | Notes |
|---------|--------|---------------|-------|
| 3.x | Current | Active | Latest features and fixes |
| 2.x | Maintenance | 2025-06-30 | Security and critical bug fixes only |
| 1.x | End of Life | 2024-01-01 | No further updates |

## Best Practices Summary

### Version Management

**DO:**
- ✅ Use GitVersion for automated version calculation
- ✅ Follow semantic versioning strictly
- ✅ Synchronize versions across manifest, changelog, and tags
- ✅ Use conventional commit messages
- ✅ Validate versions in CI/CD pipelines
- ✅ Tag releases with annotated Git tags
- ✅ Document breaking changes clearly
- ✅ Use pre-release versions for non-production releases
- ✅ Start at `0.1.0` for initial development; move to `1.0.0` when the API is stable
- ✅ Use the `v` prefix only on Git tags, never in manifest `ModuleVersion`
- ✅ Use `[semver]` type (PS 7+) for version comparisons that involve pre-release labels
- ✅ Define a deprecation period before any breaking change
- ✅ Set minimum version constraints in `RequiredModules`
- ✅ Prefer `label` over deprecated `tag` property in GitVersion v6

**DON'T:**
- ❌ Manually edit version numbers without updating all artifacts
- ❌ Skip version increments for significant changes
- ❌ Use inconsistent versioning across branches
- ❌ Forget to update CHANGELOG.md with version details
- ❌ Tag commits without proper validation
- ❌ Release breaking changes as MINOR or PATCH versions
- ❌ Use generic commit messages that skip version metadata
- ❌ Use dots or plus signs in PSGallery `Prerelease` strings (SemVer v1 only)
- ❌ Compare `[System.Version]` and `[semver]` objects directly — they are incompatible types
- ❌ Stay on `0.y.z` indefinitely when the API is already stable and used in production
- ❌ Place the `Prerelease` property at the manifest root — it belongs in `PrivateData.PSData`
- ❌ Use `RequiredVersion` in dependencies unless you truly need an exact pin

### Commit Message Best Practices

**DO:**
- ✅ Write clear, descriptive commit messages
- ✅ Use conventional commit format
- ✅ Include `+semver:` hints when needed
- ✅ Reference issue numbers
- ✅ Explain the "why" in commit body
- ✅ Mark breaking changes explicitly

**DON'T:**
- ❌ Write vague messages like "fix stuff" or "update"
- ❌ Commit without considering version impact
- ❌ Mix multiple unrelated changes in one commit
- ❌ Forget to add `+semver: none` for docs-only changes

### Release Process

**Preparation:**
1. Ensure all tests pass
2. Update CHANGELOG.md with release notes
3. Validate version synchronization
4. Review breaking changes documentation
5. Test in pre-release environment

**Execution:**
1. GitVersion calculates version from Git history
2. CI/CD updates module manifest automatically
3. Automated tests run with new version
4. Git tag created for release
5. Publish to PowerShell Gallery
6. Update CHANGELOG.md with release date

**Post-release:**
1. Verify published version on PSGallery
2. Update documentation links
3. Create GitHub release with notes
4. Announce release in appropriate channels

### Changelog Integration

Versioning and changelog management are tightly coupled:

- **Version increments** must have corresponding CHANGELOG.md entries
- **Breaking changes** in commits must appear in CHANGELOG.md
- **Release dates** in CHANGELOG.md must match Git tag dates
- **Version headers** in CHANGELOG.md must match module manifest versions

See `markdown.instructions.md` for detailed changelog management practices.

## Common Versioning Scenarios

### Scenario 1: Adding a New Feature

**Situation:** Adding a new `Export-Report` function to the module.

**Steps:**
1. Create feature branch: `git checkout -b feature/export-report`
2. Implement function with tests
3. Commit with conventional message:
   ```
   feat(reports): add Export-Report function
   
   Implements PDF and Excel export capabilities for reports.
   Includes comprehensive parameter validation and error handling.
   
   Closes #234
   ```
4. GitVersion calculates: `1.3.0-feature-export-report.1`
5. Merge to develop: Version becomes `1.3.0-preview.X`
6. Update CHANGELOG.md:
   ```markdown
   ## [Unreleased]
   
   ### Added
   - New `Export-Report` function for PDF and Excel export (#234)
   ```
7. Merge to main: Version becomes `1.3.0`
8. Tag release: `git tag -a v1.3.0 -m "Release 1.3.0"`

**Result:** MINOR version increment (new functionality, backwards-compatible)

### Scenario 2: Fixing a Bug

**Situation:** Fixing null reference error in `Get-UserData`.

**Steps:**
1. Create hotfix branch from main: `git checkout -b hotfix/null-reference`
2. Fix bug and add regression test
3. Commit with message:
   ```
   fix(users): handle null values in Get-UserData
   
   Previously threw NullReferenceException when user had no email.
   Now returns empty string with proper warning.
   
   Fixes #456
   ```
4. GitVersion calculates: `1.2.1-fix.1`
5. Merge to main: Version becomes `1.2.1`
6. Tag and release immediately
7. Merge back to develop to keep branches in sync

**Result:** PATCH version increment (bug fix, backwards-compatible)

### Scenario 3: Breaking Change

**Situation:** Renaming parameter from `-UserName` to `-Identity` for consistency.

**Steps:**
1. Create feature branch: `git checkout -b feature/rename-username-param`
2. Update function signature and all references
3. Update documentation and examples
4. Commit with breaking change marker:
   ```
   feat(users)!: rename UserName parameter to Identity
   
   BREAKING CHANGE: The -UserName parameter has been renamed to -Identity
   for consistency across all user-related functions.
   
   Migration: Replace all instances of -UserName with -Identity in scripts.
   ```
5. Update CHANGELOG.md with migration guide:
   ```markdown
   ## [Unreleased]
   
   ### BREAKING CHANGES
   - **User Functions**: Renamed `-UserName` parameter to `-Identity` across all functions
     - **Migration**: Update all scripts using `-UserName` to use `-Identity`
     - **Reason**: Consistency with Active Directory and other PowerShell modules
   ```
6. Merge to develop, then to main
7. GitVersion calculates: `2.0.0` (MAJOR increment)

**Result:** MAJOR version increment (breaking API change)

### Scenario 4: Multiple Changes in One Release

**Situation:** Release includes features, fixes, and documentation.

**Commits:**
```
feat(auth): add OAuth 2.0 support
fix(logging): correct timestamp format in logs
docs: update authentication examples +semver: none
test: add integration tests for OAuth +semver: none
```

**CHANGELOG.md:**
```markdown
## [Unreleased]

### Added
- OAuth 2.0 authentication support (#567)

### Fixed
- Timestamp format in log output now uses ISO 8601 (#589)

### Documentation
- Updated authentication examples with OAuth patterns
```

**Result:** MINOR version increment (highest impact is new feature)

## Summary Checklist

Before releasing or reviewing version-related changes, verify:

- [ ] Version follows SemVer `MAJOR.MINOR.PATCH` format
- [ ] MAJOR incremented for any breaking / incompatible change
- [ ] MINOR incremented for new backward-compatible features
- [ ] PATCH incremented for backward-compatible bug fixes
- [ ] Pre-release label is SemVer v1 compliant for PSGallery (no dots or plus)
- [ ] `Prerelease` string is in `PrivateData.PSData`, not manifest root
- [ ] Module manifest `ModuleVersion` matches calculated version
- [ ] CHANGELOG.md has an entry for the new version with a date
- [ ] Git tag exists with `v` prefix and matches the release version
- [ ] Conventional commit messages used with appropriate `+semver:` hints
- [ ] Breaking changes documented in CHANGELOG.md and commit footer
- [ ] Deprecated APIs have migration guides and at least one MINOR release grace period
- [ ] `RequiredModules` version constraints are set and tested
- [ ] CI/CD pipeline validates version synchronization across all artifacts
- [ ] GitVersion workflow and mode are appropriate for the branching strategy
- [ ] `0.y.z` projects promoted to `1.0.0` when API is stable and in production
- [ ] Build metadata (if used) does not affect version precedence
- [ ] All tests pass with the new version
- [ ] Documentation references correct version numbers
- [ ] Tag prefix convention (`v`) is consistent across all releases

## Resources and References

### Official Documentation

- **Semantic Versioning**: [https://semver.org/](https://semver.org/)
- **Calendar Versioning**: [https://calver.org/](https://calver.org/)
- **GitVersion**: [https://gitversion.net/](https://gitversion.net/)
- **Conventional Commits**: [https://www.conventionalcommits.org/](https://www.conventionalcommits.org/)
- **Keep a Changelog**: [https://keepachangelog.com/](https://keepachangelog.com/)

### PowerShell Specific

- **Prerelease Module Versions**: [Microsoft Docs](https://learn.microsoft.com/en-us/powershell/gallery/concepts/module-prerelease-support)
- **Module Manifest (psd1)**: [about_Module_Manifests](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_module_manifests)
- **Update-ModuleManifest**: [Command Reference](https://learn.microsoft.com/en-us/powershell/module/powershellget/update-modulemanifest)
- **[semver] Type Accelerator**: Available in PowerShell 6.1+ for SemVer-aware comparisons

### DSC Community Standards

- **DSC Community Guidelines**: [https://dsccommunity.org/](https://dsccommunity.org/)
- **Sample GitVersion Configurations**: [DSC Community Repos](https://github.com/dsccommunity)
- **ComputerManagementDsc**: Reference implementation example
- **SqlServerDsc**: Advanced versioning patterns

### CI/CD Integration

- **Azure Pipelines GitVersion Task**: [GitTools Extension](https://marketplace.visualstudio.com/items?itemName=gittools.gittools)
- **GitHub Actions GitVersion**: [GitTools Actions](https://github.com/GitTools/actions)
- **GitVersion Configuration Reference**: [Configuration](https://gitversion.net/docs/reference/configuration)
- **GitVersion Versioning Modes**: [Modes](https://gitversion.net/docs/reference/modes)

### Version Management Tools

- **GitVersion CLI**: Command-line version calculation tool
- **PSFramework**: PowerShell framework with versioning utilities
- **Pester**: Testing framework for version validation
- **PSScriptAnalyzer**: Static analysis for PowerShell code quality
