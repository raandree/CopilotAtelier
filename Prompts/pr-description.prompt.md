---
agent: software-engineer
description: Generate a comprehensive pull request description from the current branch's diff against the target branch.
---

# Pull Request Description Generator

Generate a comprehensive pull request description from the current branch's changes.

## Instructions

Analyze the current branch's diff against the target branch and produce a well-structured
PR description. Follow each phase in order.

## Phase 1 — Identify the target branch

Run `git log --oneline main..HEAD` (or `develop..HEAD`). If no commits are found against
`main`, try `develop`.

## Phase 2 — Gather context

- Run `git diff --stat main..HEAD` to get a summary of changed files.
- Run `git log --format='%s%n%b' main..HEAD` to collect all commit messages.
- Read the changed files to understand the scope of the changes.

## Phase 3 — Generate the PR description

Use this template:

````markdown
## Summary

<!-- One or two sentences describing the overall change -->

## Changes

<!-- Bullet list of changes grouped by category -->

### Added
- 

### Changed
- 

### Fixed
- 

## Testing

<!-- How the changes were tested -->

- [ ] Unit tests pass (`.\build.ps1 -Tasks test`)
- [ ] No PSScriptAnalyzer warnings
- [ ] Manual testing performed

## Related Issues

<!-- Reference related issues -->

Closes #

## Checklist

- [ ] Code follows project coding standards
- [ ] Tests added/updated for new functionality
- [ ] Documentation updated
- [ ] CHANGELOG.md updated
- [ ] No breaking changes (or documented in commit footer)
````

## Phase 4 — Adapt the template

- Remove sections that don't apply (e.g., if nothing was fixed, remove "Fixed").
- Add a "Breaking Changes" section if any commit contains `BREAKING CHANGE:` or `!:`.
- Fill in the summary based on the commit messages and diff content.
- Fill in the changes list from the actual modifications.
- Reference any issue numbers found in commit messages (`Fixes #`, `Closes #`, `Refs #`).

## Phase 5 — Present the description

Return the description as Markdown, ready to paste into a PR form.
