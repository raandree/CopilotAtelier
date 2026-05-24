# Versioning with GitVersion

Extracted from `Skills/sampler-framework/SKILL.md` to keep the main skill body under Anthropic's 500-line budget.

## Contents

- GitVersion.yml Configuration
- How Version is Determined (Priority Order)
- Releasing with Git Tags
- GitVersion Modes
- Commit Message Conventions

Sampler uses [GitVersion](https://gitversion.net/) for automatic semantic versioning based on git history. This replaces manual version management.

### GitVersion.yml Configuration

```yaml
mode: ContinuousDelivery
next-version: 1.0.0
major-version-bump-message: '(breaking\schange|breaking|major)\b'
minor-version-bump-message: '(adds?|features?|minor)\b'
patch-version-bump-message: '\s?(fix|patch)'
no-bump-message: '\+semver:\s?(none|skip)'
assembly-informational-format: '{NuGetVersionV2}+Sha.{Sha}.Date.{CommitDate}'
branches:
  main:
    tag: preview
    increment: Minor
  pull-request:
    tag: PR
  feature:
    tag: useBranchName
    increment: Minor
    regex: f(eature(s)?)?[\/-]
    source-branches: ['main']
  hotfix:
    tag: fix
    increment: Patch
    regex: (hot)?fix(es)?[\/-]
    source-branches: ['main']
ignore:
  sha: []
merge-message-formats: {}
```

### How Version is Determined (Priority Order)

1. **`ModuleVersion` parameter** — passed directly to build task
2. **`$env:ModuleVersion`** or parent-scope `$ModuleVersion` — environment variable
3. **GitVersion `NuGetVersionV2`** — computed from git history (most common)
4. **Module manifest** — `ModuleVersion` + `PrivateData.PSData.Prerelease` from source
5. **`SemVer` key in `build.yaml`** — overrides all of the above

### Releasing with Git Tags

```powershell
# Tag a release (triggers version calculation)
git tag -a v1.0.0 -m "Release v1.0.0"
git push origin v1.0.0
```

### GitVersion Modes

| Mode | Description | Use Case |
|---|---|---|
| `ContinuousDelivery` | Tags mark releases; commits after tag get prerelease suffix | **Recommended** for OSS modules |
| `ContinuousDeployment` | Every commit gets a unique version | Automated deployment pipelines |
| `ManualDeployment` | Version only changes on tag | Strict release control |

### Commit Message Conventions

```text
# Bump major (breaking change): 1.0.0 → 2.0.0
git commit -m "breaking change: Removed Get-OldWidget"

# Bump minor (new feature): 1.0.0 → 1.1.0
git commit -m "feature: Added Get-NewWidget"

# Bump patch (bug fix): 1.0.0 → 1.0.1
git commit -m "fix: Corrected widget parsing"

# No version bump
git commit -m "+semver: none - Documentation update"
```

---

