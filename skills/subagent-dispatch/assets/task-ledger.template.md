# Ledger

Each brief updates only its own row when it finishes. After a context
compaction, trust this file and the git history over chat memory.

Statuses: `Not started`, `Done`, `Done with concerns`, `Needs context`, `Blocked`.
A brief that is running still reads `Not started`.

| # | Status | Commits on {{integration-branch: the branch every brief commits to}} | Validation | Open findings | Report |
| --- | --- | --- | --- | --- | --- |
| {{nn: brief number, two digits}} | Not started | | | | |

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

## After the last row

Work that ran after the last brief, such as a release, goes here. Its decisions
go in Rulings under the brief `after {{nn}}`.

| Date | Work | Outcome | Evidence |
| --- | --- | --- | --- |
