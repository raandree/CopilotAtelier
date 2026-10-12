---
description: "Brief 02: rename the timeout setting"
agent: needs input
---

# 02 - Rename the timeout setting

review: needs input

Brief 02 of 3. Read [00-README.md](00-README.md)
first; its shared rules, report contract, and ledger apply.

## Preconditions

Stop with status `Blocked` when one fails.

- Own row: read ledger row 02. Continue existing work only while the row is
  not `Done`; when it is `Done`, stop with a report instead of repeating the work.
- Dependency rows: 01. Each is `Done`, `Done with concerns` that the user accepted,
  or covered by a ruling that lets this brief proceed without it. Before building
  on a row another run wrote, check that every commit it names is on the
  integration branch and that its report file exists:

  ```powershell
  git cat-file -e '<sha>^{commit}'
  git merge-base --is-ancestor <sha> <integration-branch>
  Test-Path -LiteralPath 'reports/<NN>-<slug>.report.md'
  ```

  A mismatch stops this brief for a ruling. Never correct the ledger yourself.
- The repository state is needs input.

## Evidence

Verified on needs input by needs input. Re-check
each item before relying on it; report a mismatch under Evidence corrections in
the report instead of forcing the change.

- The original prompt says to run it after the retry prompt has finished.

## Ask first

none

## Tasks

Rename the Timeout setting to TimeoutSeconds everywhere it is read, and keep the
old name working for one version with a warning.

1. Add the new name and map the old one to it.
2. Update the tests and the sample configuration.

## Validation

- The configuration tests pass.

## Finish

- Commit `needs input` with the trailers the README names.
- Write the report to `reports/02-rename-setting.report.md` from the report
  template.
- Update ledger row 02 only, and add every decision you made to Rulings,
  marked with who decided it.
- Reply in chat with the status, the commits, a one-line test summary, and
  concerns only.
