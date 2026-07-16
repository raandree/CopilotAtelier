# Evals — long-running-job-monitor

Claude-A/Claude-B loop (see `skill-creator`): run each prompt in a fresh chat
with the skill loaded and confirm the skill triggers in the PRE-FLIGHT line.
Baseline is the same prompt with the skill unloaded: the global execution rules
still prohibit busy-waiting, but skill-specific instrumentation, heartbeat
classification, and out-of-band progress evidence should be absent.

## E1 — Deploy and tell me when it is done (happy path)

Prompt: "Deploy the stack to the test VM and tell me when it's done."

Pass:

- Wraps the deploy in a self-timestamping log (`START`, per-phase, `<JOB>-DONE`), tee'd to `$env:TEMP`.
- Runs it sync-no-timeout (or async + sidecar); no agent-side `Start-Sleep` / poll loop.
- On the completion notification: reads the full log, verifies the end-state on the target, reports a timestamped pass, and cleans up throwaway resources.

## E2 — Is the deployment stuck? (classification)

Prompt: "Is the deployment stuck?"

Pass:

- Reports timestamp, elapsed, `ProgressToken`, last-progress age, heartbeat age,
  liveness, and target summary as separate fields.
- Classifies WORKING vs STALLED only from time since `ProgressToken` advancement
  against a phase-sized threshold, not a global constant.
- If STALLED, surfaces it explicitly instead of silently continuing to wait.

## E3 — Buffered stdout (prints only at the end)

Setup: a job that emits nothing until it finishes.

Pass:

- Does not treat silence as stuck.
- Reports real progress through a phase-specific milestone or monotonic work
  product such as provisioning phase, readiness transition, job-owned database
  row count, or rollout generation.
- Treats static hypervisor power state, repeated HTTP 200, process existence,
  uptime, CPU, and memory as liveness/context rather than continuing progress.

## E4 — Job dies mid-run

Setup: the job process exits before printing a DONE marker.

Pass:

- Detects process-dead-without-DONE (liveness false + no terminal marker).
- Classifies FAILED and surfaces the log tail plus the target's error surface, not a generic "it stopped".

## E5 — Remote job over SSH/WinRM, control channel drops

Setup: the job runs on a remote host (lab VM / cloud) reached over SSH or WinRM, detached with its log on the remote; the control connection drops mid-run while the remote job keeps running.

Pass:

- Applies techniques 1–3 on the remote side (instrumented remote log, remote liveness probe, out-of-band check via an independent control plane).
- Rejects bare `Start-Job` inside a temporary `Invoke-Command` because session
  closure cancels it.
- Uses a scheduled task for channel-independent Windows work, or a persistent
  WSMan PSSession that is explicitly disconnected and later reconnected.
- On the dropped connection, does **not** report FAILED — reconnects and re-reads the remote `<JOB>-DONE`/`-FAILED` marker + remote process state before classifying.
- Distinguishes channel death from job death and resumes WORKING/DONE reporting once reconnected.

## E6 — Reboot returns ping before WinRM

Setup: a Windows VM deliberately restarts during deployment. The hypervisor
reports running, then ping succeeds, while TCP 5985 and `Test-WSMan` still fail
for the expected service-start interval.

Pass:

- Starts a new readiness epoch at the reboot and discards pre-reboot checks.
- Reports the staged target evidence without calling the job failed.
- Probes TCP 5985 and `Test-WSMan` because the next phase uses WinRM.
- Keeps remoting-dependent work waiting until current-boot WinRM readiness.
- Uses a phase-sized timeout before classifying the service startup as stalled.

## E7 — Fresh heartbeat but no target progress

Setup: a sidecar emits a fresh heartbeat every minute and volatile target
telemetry changes, but `ProgressToken` remains unchanged beyond twice the
expected phase time.

Pass:

- Treats heartbeat freshness as monitor liveness, not work progress.
- Classifies the job as STALLED despite continuing synthetic heartbeats.
- Reports time since the last real target or phase change.
- Investigates the target error surface instead of extending the timeout from
  each heartbeat.

## E8 — Sidecar line is evidence, not the reply opener

Setup: the latest `.status` line contains local `HH:mm:ss`, elapsed,
last-progress, token, heartbeat, liveness, and target summary, but no UTC date,
phase, classification, or next milestone.

Pass:

- Reads the sidecar line as evidence rather than copying it verbatim.
- Constructs the reply's first line with full UTC date/time, elapsed, phase,
  last-progress, progress token, status, and next milestone.
- Adds heartbeat, liveness, and target summary only as supporting fields.
- Treats a verbatim sidecar line as a process violation because mandatory
  opener fields are absent.

## E9 — Encoded probe body

Setup: launch the detached sidecar with a UTF-16LE Base64 probe.

Pass:

- Encodes the probe body without surrounding script-block braces.
- Produces one object with `Summary`, `Liveness`, and `ProgressToken`.
- Rejects an outer-braced probe with a targeted format error instead of
  reporting a misleading missing-property failure.
