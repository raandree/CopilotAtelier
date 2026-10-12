# Migration report

Migrated the folder of three prompts on 2026-01-15. Status: done with concerns,
because the facts marked `needs input` are still open.

## Inventory

| Original | Migrated as | Agent | Depends on | Status | Slots added |
| --- | --- | --- | --- | --- | --- |
| `P1-export-retry.prompt.md` | `01-export-retry.prompt.md` | `software-engineer` | none | Done | the README pointer, the own-row and dependency-row checks, Evidence, Ask first, Tasks, the ledger row in Finish |
| `P2-rename-setting.md` | `02-rename-setting.prompt.md` | needs input | 01 | Not started | all of them |
| `P3-document-retry.txt` | `03-document-retry.prompt.md` | needs input | 02 | Not started | all of them |

## Decisions

Both decisions are rulings in `LEDGER.md`, decided by the agent and flagged for
your review: the status of 01 is reconstructed from its report, and the order and
dependencies come from the original names and wording.

## Needs input

- The integration branch, the model tier and review switch of every brief, and
  the decisions that are yours.
- The agent for 02 and 03.
- The validation for 03, and the commit message for 02 and 03.
- The date and the way each brief's evidence was checked.

## Moved rules

The line "Run the tests before you commit and do not skip a failing test." was
repeated in P1 and P2. It is now a shared rule in `00-README.md` and is gone from
the briefs.

## Validation

`Test-HandoffSequence.ps1` reports no Error. Every Warning is a `needs input`
marker.

## Originals

Every original is kept byte for byte under `originals/`, including the report.
The report is also copied as `reports/01-export-retry.report.md`. The SHA-256 is
that of the stored text with LF line endings.

| Original | SHA-256 |
| --- | --- |
| `P1-export-retry.prompt.md` | `4F66352CE0E65ECCCAC51AD463D4B0D265768A38B9E1CE3066F1447374219086` |
| `P2-rename-setting.md` | `2992E88F3247DF99C922CD20D178A297A9B98E312298852175082D6DCE2EF205` |
| `P3-document-retry.txt` | `02F10E73DA4082C98FD705A83338CA34ACE9BE5EFD3ABBD3E0F36AE97E462681` |
| `reports/export-retry.report.md` | `131ED8B416F38ACBFB21BCB01165F108060E0A65745F99D33418DC09E9320080` |
