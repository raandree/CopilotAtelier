---
applyTo: "**/.gitconfig,**/.gitignore,**/.gitattributes,**/COMMIT_EDITMSG"
---

# Git Best Practices and Standards

## Commit Message Format

### Conventional Commits

Follow the [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) specification. This enables automated changelog generation, semantic versioning detection by GitVersion, and clear project history.

### Structure

```
<type>[(optional scope)][!]: <description>

[optional body]

[optional footer(s)]
```

### Type

| Type | Purpose | SemVer Impact |
|---|---|---|
| `feat` | New feature | Minor bump |
| `fix` | Bug fix | Patch bump |
| `docs` | Documentation only | None |
| `style` | Formatting, whitespace, semicolons (no code change) | None |
| `refactor` | Code restructuring (no feature or fix) | None |
| `perf` | Performance improvement | Patch bump |
| `test` | Adding or correcting tests | None |
| `build` | Build system or external dependencies | None |
| `ci` | CI configuration files and scripts | None |
| `chore` | Maintenance tasks (no production code change) | None |
| `revert` | Revert a previous commit | Varies |

### Breaking Changes

Indicate breaking changes with `!` after the type/scope or with the `BREAKING CHANGE:` footer:

```
feat!: remove deprecated Get-Widget -Legacy parameter

BREAKING CHANGE: The -Legacy parameter has been removed. Use -Format 'v1' instead.
```

```
feat(api)!: change return type of Get-Config to hashtable
```

### Description Line

- Use the **imperative mood**: "add feature" not "added feature" or "adds feature"
- Do **not** capitalize the first letter of the description
- Do **not** end with a period
- Keep the first line under **72 characters** (50 is ideal for the description portion)
- The type + scope + description together should not exceed 72 characters

### Body

- Separate from the description with a blank line
- Wrap at **72 characters**
- Explain **what** and **why**, not **how** (the diff shows how)
- Use bullet points for multiple items

### Footer

- Use `BREAKING CHANGE: <description>` for breaking changes
- Use `Fixes #<issue>` or `Closes #<issue>` for issue references
- Use `Refs #<issue>` for related issues
- Use `Co-authored-by: Name <email>` for pair programming
- Use `Reviewed-by: Name <email>` for code review attribution

### Examples

```
feat(auth): add OAuth2 token refresh support

Implement automatic token refresh when the access token expires.
The refresh interval is configurable via the -RefreshIntervalMinutes
parameter.

Closes #42
```

```
fix(build): resolve ModuleBuilder path on Linux

ModuleBuilder used backslash path separators which fail on Linux.
Changed to [System.IO.Path]::Combine() for cross-platform compatibility.

Fixes #87
```

```
docs: update README with setup instructions for macOS
```

```
chore: update RequiredModules.psd1 dependency versions
```

```
refactor(pipeline): extract validation into separate function

Move parameter validation logic from Invoke-BuildPipeline into
a new Test-BuildParameters function to improve testability.
```

## Scope Convention

Use consistent scopes across the project. Common scopes:

| Scope | When to Use |
|---|---|
| `auth` | Authentication and authorization |
| `build` | Build system (build.yaml, build.ps1) |
| `ci` | CI/CD pipeline configuration |
| `config` | Configuration handling |
| `deps` | Dependency updates |
| `docs` | Documentation |
| `lint` | Linting rules and configuration |
| `test` | Test infrastructure |
| `<module>` | Named module in a multi-module repo |

Scopes are **optional**. Omit when the change is project-wide or doesn't fit a specific scope.

## Branch Naming

### GitVersion-Compatible Branch Names

GitVersion uses branch naming patterns for version calculation. Use these patterns consistently:

| Pattern | Purpose | Example |
|---|---|---|
| `main` or `master` | Production-ready code | `main` |
| `develop` | Integration branch | `develop` |
| `feature/<name>` | New features | `feature/oauth2-refresh` |
| `bugfix/<name>` | Bug fixes from develop | `bugfix/path-separator-linux` |
| `hotfix/<name>` | Urgent fixes from main | `hotfix/null-reference-crash` |
| `release/<version>` | Release preparation | `release/2.0.0` |
| `support/<version>` | Long-term support | `support/1.x` |

### Branch Name Rules

- Use **lowercase** with **hyphens** as word separators
- Use **forward slashes** for category prefixes
- Keep names short but descriptive
- Include issue numbers when relevant: `feature/42-oauth2-refresh`
- Do **not** use spaces, underscores, or special characters (except `/` and `-`)

```
# Good
feature/add-export-csv
bugfix/123-null-reference
hotfix/security-patch-cve-2026

# Bad
Feature/Add_Export_CSV
feature/add export csv
my-branch
```

## .gitignore Best Practices

### Structure

Organize `.gitignore` with clear section headers:

```gitignore
# Build output
output/

# Dependencies
RequiredModules/

# IDE settings (user-specific)
.vscode/settings.json
.vscode/launch.json
*.code-workspace

# OS files
Thumbs.db
.DS_Store

# PowerShell
*.psm1.bak

# Temporary files
*.tmp
*.log
```

### Rules

- **One pattern per line**
- Use `#` for comments — always add section headers
- Use `/` prefix for patterns relative to the repo root: `/output/` vs `output/`
- Use `!` to negate patterns (re-include a file): `!.vscode/extensions.json`
- Use `**` for recursive matching: `**/bin/`
- List the most specific patterns last (later rules override earlier ones)
- Do **not** ignore tracked files — remove them with `git rm --cached` first

### Sampler Project .gitignore

Standard patterns for Sampler-based PowerShell modules:

```gitignore
# Build output
output/

# Resolved dependencies
RequiredModules/

# Module build artifacts
*.nupkg

# Test results (generated by build)
testResults/

# Code coverage
coverage/

# OS artifacts
Thumbs.db
.DS_Store

# VS Code user settings
.vscode/settings.json
.vscode/launch.json
```

### Global .gitignore

Configure a global `.gitignore` for user- and OS-specific patterns:

```powershell
# Set global gitignore
git config --global core.excludesFile '~/.gitignore_global'
```

Put OS and editor patterns in the global file, not in project `.gitignore`:

```gitignore
# ~/.gitignore_global
.DS_Store
Thumbs.db
*.swp
*~
.idea/
```

## .gitattributes

### Purpose

Define line-ending normalization, diff drivers, and merge strategies:

```gitattributes
# Auto-detect text files and normalize line endings
* text=auto

# PowerShell files
*.ps1    text eol=crlf
*.psm1   text eol=crlf
*.psd1   text eol=crlf

# Shell scripts
*.sh     text eol=lf

# Markdown
*.md     text eol=lf

# YAML
*.yml    text eol=lf
*.yaml   text eol=lf

# Binary files
*.png    binary
*.jpg    binary
*.gif    binary
*.ico    binary

# Archive files
*.zip    binary
*.nupkg  binary
```

### PowerShell Projects

PowerShell files should use CRLF on Windows. Set `eol=crlf` for `.ps1`, `.psm1`, and `.psd1` files to ensure consistent behavior across platforms.

## Git Configuration

### Recommended Settings

```powershell
# Identity
git config --global user.name 'Your Name'
git config --global user.email 'your.email@example.com'

# Default branch
git config --global init.defaultBranch 'main'

# Pull strategy
git config --global pull.rebase true

# Auto-CRLF (Windows)
git config --global core.autocrlf true

# Push behavior
git config --global push.default current

# Diff tool
git config --global diff.tool vscode
git config --global difftool.vscode.cmd 'code --wait --diff $LOCAL $REMOTE'

# Merge tool
git config --global merge.tool vscode
git config --global mergetool.vscode.cmd 'code --wait $MERGED'
```

### Aliases

```powershell
git config --global alias.st 'status --short --branch'
git config --global alias.lg "log --oneline --graph --decorate --all -20"
git config --global alias.co 'checkout'
git config --global alias.br 'branch'
git config --global alias.ci 'commit'
git config --global alias.unstage 'reset HEAD --'
git config --global alias.last 'log -1 HEAD --stat'
git config --global alias.amend 'commit --amend --no-edit'
```

## Git Workflow Patterns

### Feature Branch Workflow

1. Create a feature branch from `main` (or `develop`)
2. Make commits following Conventional Commits
3. Push and create a pull request
4. After review, merge (squash or rebase preferred)
5. Delete the feature branch

```powershell
# Start a feature
git checkout -b feature/add-export-csv main

# Work and commit
git add .
git commit -m 'feat(export): add CSV export for widget data'

# Push and create PR
git push -u origin feature/add-export-csv
```

### Commit Hygiene

- **Atomic commits**: Each commit should represent one logical change
- **No WIP commits** on shared branches (squash before merging)
- **No merge commits** on feature branches (use rebase)
- **Sign commits** if required by the project: `git commit -S`

### AI-Assisted Commit Strategy

When AI (Copilot, Claude Code, Cursor, etc.) generates or modifies code, apply these additional conventions:

#### Attribution

- Add `Co-authored-by: AI Assistant <ai@example.com>` trailer to AI-assisted commits
- This surfaces in `git log`, `git blame`, and GitHub's contributor graph
- Team members can immediately identify which code had AI involvement

#### AI Branch Naming

- Use `ai/` prefix for branches where AI performs the majority of work: `ai/add-validation`
- AI branches are merged via pull request after human review
- Never let AI commit directly to `main`, `develop`, or `release/*` branches

#### AI Commit Tagging

- Optionally tag AI-generated commits with 🤖 emoji or `[AI]` suffix in the description
- Example: `feat(validation): add config file validation 🤖`
- Example: `test(auth): add OAuth2 edge case tests [AI]`
- This makes AI contributions filterable via `git log --grep`

#### Git Forensics for AI Accountability

- Use `git log --follow --format='%aN' -- <file> | sort | uniq -c | sort -rn` to see per-contributor change frequency
- Use `git log --author='AI' --oneline` to review all AI-attributed commits
- Regularly audit AI contribution ratio in critical code paths

### Rebase vs Merge

- **Rebase** feature branches onto the target before merging to keep a linear history
- **Never rebase** shared branches (`main`, `develop`)
- Use `git pull --rebase` to avoid unnecessary merge commits

## Tag Conventions

### SemVer Tags

- Use `v` prefix for version tags: `v1.0.0`, `v2.1.3`
- Note: The `v` prefix is a Git convention, not part of SemVer itself
- GitVersion can be configured to use or strip the `v` prefix

```powershell
# Create an annotated tag
git tag -a v1.0.0 -m 'Release v1.0.0'

# Push tags
git push origin v1.0.0
git push origin --tags
```

### Lightweight vs Annotated Tags

- **Annotated tags** (`git tag -a`): Use for releases — includes tagger, date, message
- **Lightweight tags** (`git tag`): Use for temporary markers — no metadata

## Git Hooks

### Useful Hooks for PowerShell Projects

```powershell
# .githooks/pre-commit — run PSScriptAnalyzer
#!/usr/bin/env pwsh
$files = git diff --cached --name-only --diff-filter=ACM | Where-Object { $_ -match '\.ps1$|\.psm1$' }
if ($files) {
    $results = $files | ForEach-Object { Invoke-ScriptAnalyzer -Path $_ -Severity Error }
    if ($results) {
        $results | Format-Table -AutoSize
        exit 1
    }
}
```

### Configuring Hook Path

```powershell
# Use a hooks directory in the repo
git config core.hooksPath .githooks
```

## Interactive Staging

### Stage Partial Changes

- Use `git add -p` to stage individual hunks
- Review each change before staging
- Keeps commits atomic and focused

```powershell
# Interactive staging
git add -p

# Interactive staging for a specific file
git add -p path/to/file.ps1
```
