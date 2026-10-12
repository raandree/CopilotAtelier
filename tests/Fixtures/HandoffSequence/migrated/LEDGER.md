# Ledger

Each brief updates only its own row when it finishes. After a context
compaction, trust this file and the git history over chat memory.

Statuses: `Not started`, `Done`, `Done with concerns`, `Needs context`, `Blocked`.
A brief that is running still reads `Not started`.

| # | Status | Commits on needs input | Validation | Open findings | Report |
| --- | --- | --- | --- | --- | --- |
| 01 | Done | `3f2a9c1` | 12 passed, 0 failed | none | [01](reports/01-export-retry.report.md) |
| 02 | Not started | | | | |
| 03 | Not started | | | | |

Add one row per planned brief before the first brief runs. A finished row names
its commits (`none` when it commits nothing), the validation that proved the
work, what stays open, and a link to its report.

## Rulings

One row per decision. `Decided by` is `user`, `agent` (flagged for the user's
review), or `agent under delegation` (flagged the same way). A later ruling that
changes an earlier one says "Supersedes" and names it; the earlier row stays as
it was.

| Date | Brief | Question | Decided by | Answer |
| --- | --- | --- | --- | --- |
| 2026-01-15 | 01 | The original report says Done and names commit 3f2a9c1: record 01 as Done? | agent | Yes, reconstructed from the original report. The commit was not checked against a repository. Flagged for your review. |
| 2026-01-15 | all | In which order do the briefs run? | agent | 01, 02, 03, from the P1 to P3 prefixes of the original names; 02 depends on 01 and 03 on 02, from their wording. Flagged for your review. |

## After the last row

Work that ran after the last brief, such as a release, goes here. Its decisions
go in Rulings under the brief `after 03`.

| Date | Work | Outcome | Evidence |
| --- | --- | --- | --- |
