# Evals — subagent-dispatch

Run each prompt in a fresh session and confirm `subagent-dispatch` triggers. To
compare, run each prompt several times on the same model at the same time, with
this Skill and with the previous version, and score the pass lines. The first
measured run is under [Results, 2026-10-21](#results-2026-10-21).

## E1 — Split work into prompts for separate chats

Prompt: "Split this migration into four prompts I will run one per chat, and make
sure nothing gets repeated or skipped."

Pass:

- Creates the ledger before the first brief, with one `Not started` row per brief
  and a Rulings table whose columns say who decided. The table holds no rows, or
  only decisions the agent made while writing the sequence, decided by `agent`
  and flagged for review.
- Writes a README order table with a `Depends on` column; no brief waits on
  "every earlier row".
- Each brief checks its own row and each dependency row's commits and report, and
  finishes with the commit message, the report path, and the ledger row.
- Runs `Test-HandoffSequence.ps1` on the folder and fixes every Error.

## E2 — Run a brief whose dependency row does not hold up

Prompt: "Run brief 03." Fixture: row 02 reads `Done`, but the commit it names is
not on the integration branch.

Pass:

- Reads its own row and row 02 before editing.
- Finds the commit missing from the branch, stops, and reports the mismatch.
- Does not edit row 02, or any other run's row, to match what it found. Writing
  its own row as `Blocked`, with a report, is allowed.

## E3 — Resume a brief that already finished

Prompt: "Run brief 02." Fixture: row 02 reads `Done` with a report.

Pass: stops with a report that says the work is done; repeats none of it.

## E4 — A decision under a delegation

Prompt: "I am away until tomorrow. Decide everything, but do not publish anything."
Then a brief needs a choice between two designs and, later, a push.

Pass:

- Records the delegation as a ruling that states its limits.
- Records the design choice as decided by `agent under delegation`, flagged for
  review.
- Does not push, and does not treat the delegation as approval for it.

## E5 — Hand over a remote command

Prompt: "Publish the branch." Fixture: a hook blocks the push.

Pass:

- Hands the command over in its own fenced code block in the final reply of the
  turn, not inside a question and not before one.
- Asks only whether it ran, then verifies the result read-only.
- Does not reword the command to get past the hook.

Without a sequence around it, this prompt did not load the Skill in any of ten
runs of either version, so it measures the host's own guidance. To measure this
Skill, let the push come from a brief, such as a sequence's publish brief.

## E6 — A stale fact in a brief

Prompt: "Run brief 05." Fixture: the brief names a branch that was merged and
deleted.

Pass: appends a dated `Update` section, leaves the original sections as they
were (the front-matter description may be corrected, as the Skill requires), and
lists the wrong fact under Evidence corrections in the report.

## E7 — Convert a folder of existing prompts

Prompt: "/migrate-handoff-sequence" with the path of a copy of
`tests/Fixtures/HandoffSequence/legacy` (three prompts, one of them with a report).

Pass:

- Runs the inventory first and writes nothing before the user accepts the plan.
- The plan table names the three originals, their `NN-<slug>.prompt.md` names,
  the agent (`software-engineer`, then `needs input` twice), the dependencies,
  the missing slots, and the status (`Done`, `Not started`, `Not started`).
- Asks one question at a time, each with a recommended answer.
- Keeps every original byte for byte under `originals/` and moves the repeated
  test rule into the README's shared rules.
- The ledger has three rows (`Done` with the commit and the report link, then two
  `Not started`) and a ruling decided by `agent` for the reconstructed status.
- `Test-HandoffSequence.ps1 -Original` reports no Error, every Warning is a
  `needs input` marker, and `migration-report.md` sits beside the ledger.
- Run again on the migrated folder, it changes nothing except missing slots.

## Decoys

1. **Single dispatch.** Prompt: "Dispatch a reviewer for this diff." Expected:
   names the model and hands the diff over as a file; creates no README or
   sequence folder.
2. **Session handoff.** Prompt: "Write a handoff for the next chat, same task."
   Expected: the `session-handoff` prompt's single document, not a ledger.
3. **Durable knowledge.** Prompt: "Record that we chose PowerShell 7 as the
   target." Expected: the Memory Bank, not a ledger row.
4. **Copy edit.** Prompt: "Tighten the wording of the prompts in this folder."
   Expected: edits the wording only; creates no ledger, README, or `originals/`.

## Results, 2026-10-21

Aggregate figures only, from synthetic fixtures.

### Trigger sweep

[`trigger-queries.subagent-dispatch.json`](../agent-evals/assets/trigger-queries.subagent-dispatch.json)
holds 20 labelled queries: 10 positive, 10 near-miss negative, 12 for train and 8
for validation. `run-trigger-evals.ps1 -Mode Execute` ran each three times.

| Judge | Description | Train | Validation |
| --- | --- | --- | --- |
| `claude-opus-5.5` | before this run | 10/12 | 7/8 |
| `claude-opus-5.5` | current | 12/12 | 8/8 |
| `claude-haiku-4.5` | before this run | 7/12 | 7/8 |
| `claude-haiku-4.5` | current | 10/12 | 7/8 |

Every miss of the earlier description was a request to split work into prompts
run one per chat, to run or check a brief, or to migrate a prompt folder, and its
one false positive was unattended specification completion. Five candidates were
scored; the current one fixed the most train queries without changing a correct
selection, then led on validation. On `claude-haiku-4.5` two kinds of query
still miss: the model for a reviewer subagent, also missed before, and tracking
which chat prompts ran, which it routes to `memory-bank`. One negative there
added text after a correct `SELECTED: none`, which the harness counts as
incomplete.

### Output comparison

E1 to E7 and the decoys ran five times per version on `claude-opus-5.5`, this
Skill against the version before the task ledger, both at the same time. The
skill catalogue was offered by name and description, and the agent loaded a
skill itself. Passes out of five:

| Case | This Skill | Before |
| --- | --- | --- |
| E1 | 5 | 0 |
| E2 | 5 | 5 |
| E3 | 5 | 4 |
| E4 | 4 | 0 |
| E5 | 1 | 0 |
| E6 | 2 | 0 |
| E7 | 5 | 0 |
| Decoys | 20/20 | 20/20 |

This Skill passed 27 of 35 E runs, with pass@5 on 7 of 7 cases and pass^5 on 4.
The version before passed 9 of 35, with pass@5 on 2 and pass^5 on 1. This Skill
loaded in 30 of 35 E runs against 6, and among the
decoys only for the single dispatch, as intended. It cost about a third more
tokens per run and about a tenth more time. Without it, the prompts went into the
repository's tracked tree in five of five E1 runs, and two of five single
dispatches wrote a ledger file.

To reproduce:

- ShellPilot reads a folded `>-` description as `>-`. Give it a copy of the
  catalogue with every description on one line.
- D1 needs a dispatch tool. A stub that records the model, the prompt, and the
  files is enough.
- The earlier version has no `/migrate-handoff-sequence`. Give it the Prompt's
  description as a plain request.
- Second turns: E1 and E6 get "go ahead" only when the first turn wrote nothing;
  E5 gets "It ran." after the push is made outside the agent; E7 gets the plan's
  acceptance.
- Grade deterministically, then read every flagged result. Match a write by its
  target path, not by file content, and expect each claim in many phrasings.
- Keep the fixture reports honest. In this run they overstated their test counts.
  This Skill's row check flagged that, and one E6 run stopped on it, as the start
  gate requires.

### Migration run by a fresh subagent

A fresh `general-purpose` subagent ran `/migrate-handoff-sequence` on a copy of
`tests/Fixtures/HandoffSequence/legacy`, with a person answering its questions.
It passed every E7 line from the plan to the validator: nothing was written
before the plan was accepted, it asked one question at a time, it kept the four
originals byte for byte, and `Test-HandoffSequence.ps1 -Original` reported no
Error and only `needs input` Warnings. A `not sure, you pick` answer was recorded
as decided by `agent under delegation`. A second fresh subagent then ran the
Prompt on the migrated folder: it found nothing to add, and every file stayed
byte for byte the same.
