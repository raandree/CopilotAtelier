---
description: "Brief 01: add a retry to the report exporter"
agent: software-engineer
---

# 01 - Add a retry to the report exporter

review: needs input

Brief 01 of 3. Read [00-README.md](00-README.md)
first; its shared rules, report contract, and ledger apply.

## Preconditions

Stop with status `Blocked` when one fails.

- Own row: read ledger row 01. Continue existing work only while the row is
  not `Done`; when it is `Done`, stop with a report instead of repeating the work.
- Dependency rows: none.
- The report-tools repository has a clean working tree, on a new branch from main.

## Evidence

Verified on needs input by needs input. Re-check
each item before relying on it; report a mismatch under Evidence corrections in
the report instead of forcing the change.

- The exporter gives up on the first network error.

## Ask first

none

## Tasks

The exporter gives up on the first network error. Retry up to three times with a
one-second pause, then fail with the last error.

## Validation

- The exporter tests pass.

## Finish

- Commit `fix(export): retry transient failures` with the trailers the README
  names.
- Write the report to `reports/01-export-retry.report.md` from the report
  template.
- Update ledger row 01 only, and add every decision you made to Rulings,
  marked with who decided it.
- Reply in chat with the status, the commits, a one-line test summary, and
  concerns only.
