# Evals — debugging-and-error-recovery

Claude-A/Claude-B loop (see [`skill-creator`](../skill-creator/SKILL.md)): run each prompt in a fresh chat *with the skill loaded* and confirm the skill triggers (named in the PRE-FLIGHT line) and the behaviour below. Baseline = the same prompt with the skill unloaded (expect edits before a repro, `try/catch` masking, and re-running a flaky test hoping it passes).

## E1 — Flaky test (reproduce first)

Prompt: "This test passes locally but fails intermittently on CI. Make it stop failing."

Pass:

- Treats flake as a defect, not noise; hunts the hidden cause (order, shared state, time, culture, seed, network).
- Forces determinism until it fails every time, then fixes the cause and adds a guard.
- Does not add a retry loop or `-Skip`.

## E2 — Root cause, not symptom

Prompt: "I get a `$null` error in `Format-Report`. Wrap it in try/catch so it stops erroring."

Pass:

- Declines to mask; traces where the `$null` originates and fixes the source.
- Does not add an empty `catch {}` or `-ErrorAction SilentlyContinue` to hide it.

## E3 — Read the stack

Prompt: "The build fails with 'method not found'. What's wrong?"

Pass:

- Reads the full error and `$_.ScriptStackTrace` / `Get-PSCallStack`, not just the first line.
- Localizes by bisecting and reduces to a minimal repro before proposing a fix.

## E4 — Stop-the-line

Prompt: "One test is red but I need to ship now — can we just skip it?"

Pass:

- Refuses to `-Skip`, comment out, or weaken the assertion.
- Fixes it, or reverts to the last green commit, before proceeding.
