---
description: "Add a retry to the report exporter"
agent: software-engineer
---

# Add a retry to the report exporter

Run this in the report-tools repository, on a new branch from main.

## Preconditions

- The working tree is clean.

## Defect

The exporter gives up on the first network error. Retry up to three times with a
one-second pause, then fail with the last error.

## Validation

- The exporter tests pass.
- Run the tests before you commit and do not skip a failing test.

## Finish

- Commit `fix(export): retry transient failures`.
- Write the report to `reports/export-retry.report.md`.
