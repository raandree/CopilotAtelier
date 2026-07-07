# Evals — long-running-job-monitor

Claude-A/Claude-B loop (see `skill-creator`): run each prompt in a fresh chat *with the skill loaded* and confirm the skill triggers (named in the PRE-FLIGHT line) and the behaviour below. Baseline = the same prompt with the skill unloaded (expect no instrumentation, no out-of-band check, and self-`Start-Sleep` / "I will wait" busy-waiting).

## E1 — Deploy and tell me when it is done (happy path)

Prompt: "Deploy the stack to the test VM and tell me when it's done."

Pass:

- Wraps the deploy in a self-timestamping log (`START`, per-phase, `<JOB>-DONE`), tee'd to `$env:TEMP`.
- Runs it sync-no-timeout (or async + sidecar); no agent-side `Start-Sleep` / poll loop.
- On the completion notification: reads the full log, verifies the end-state on the target, reports a timestamped pass, and cleans up throwaway resources.

## E2 — Is the deployment stuck? (classification)

Prompt: "Is the deployment stuck?"

Pass:

- Reports the current timestamp + elapsed, the heartbeat age, and the last target state.
- Classifies WORKING vs STALLED against a phase-sized threshold (~2x expected phase time), not a global constant.
- If STALLED, surfaces it explicitly instead of silently continuing to wait.

## E3 — Buffered stdout (prints only at the end)

Setup: a job that emits nothing until it finishes.

Pass:

- Does not treat silence as stuck.
- Reports real progress via an out-of-band, read-only target query (hypervisor power state, HTTP health, DB row count), not the job's own stdout.

## E4 — Job dies mid-run

Setup: the job process exits before printing a DONE marker.

Pass:

- Detects process-dead-without-DONE (liveness false + no terminal marker).
- Classifies FAILED and surfaces the log tail plus the target's error surface, not a generic "it stopped".

## E5 — Remote job over SSH/WinRM, control channel drops

Setup: the job runs on a remote host (lab VM / cloud) reached over SSH or WinRM, detached with its log on the remote; the control connection drops mid-run while the remote job keeps running.

Pass:

- Applies techniques 1–3 on the remote side (instrumented remote log, remote liveness probe, out-of-band check via an independent control plane).
- On the dropped connection, does **not** report FAILED — reconnects and re-reads the remote `<JOB>-DONE`/`-FAILED` marker + remote process state before classifying.
- Distinguishes channel death from job death and resumes WORKING/DONE reporting once reconnected.
