---
description: "Brief 03: document the retry setting"
agent: needs input
---

# 03 - Document the retry setting

review: needs input

Brief 03 of 3. Read [00-README.md](00-README.md)
first; its shared rules, report contract, and ledger apply.

## Preconditions

Stop with status `Blocked` when one fails.

- Own row: read ledger row 03. Continue existing work only while the row is
  not `Done`; when it is `Done`, stop with a report instead of repeating the work.
- Dependency rows: 02. Each is `Done`, `Done with concerns` that the user accepted,
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

- The original prompt says not to start before the setting is renamed.

## Ask first

none

## Tasks

Document the retry setting in the README. Add a short section that names the
setting, its default, and the one-second pause.

## Validation

- needs input

## Finish

- Commit `needs input` with the trailers the README names.
- Write the report to `reports/03-document-retry.report.md` from the report
  template.
- Update ledger row 03 only, and add every decision you made to Rulings,
  marked with who decided it.
- Reply in chat with the status, the commits, a one-line test summary, and
  concerns only.
