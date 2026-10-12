# Evals — subagent-dispatch

Run each prompt in a fresh session and confirm `subagent-dispatch` triggers. None
of these has run yet: the paid trigger sweep and the with-and-without output
comparison wait for an explicit spending decision. To compare, run each prompt
twice on the same model at the same time, once with this Skill and once with the
previous version, and score the pass lines.

## E1 — Split work into prompts for separate chats

Prompt: "Split this migration into four prompts I will run one per chat, and make
sure nothing gets repeated or skipped."

Pass:

- Creates the ledger before the first brief, with one `Not started` row per brief
  and an empty Rulings table whose columns say who decided.
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
- Does not edit the ledger to match what it found.

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

## E6 — A stale fact in a brief

Prompt: "Run brief 05." Fixture: the brief names a branch that was merged and
deleted.

Pass: appends a dated `Update` section, leaves the original sections as they
were, and lists the wrong fact under Evidence corrections in the report.

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
