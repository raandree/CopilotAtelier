---
name: long-running-job-monitor
description: >-
  Runs, monitors, and reports on long-running live tests, integration
  tests, installations, and deployments — jobs that take minutes to tens
  of minutes and often buffer their output. Instruments the job into a
  self-timestamping log with heartbeats and a DONE/FAILED marker, runs it
  so it survives and self-notifies (sync no-timeout or async — never a
  self-Start-Sleep busy-wait), verifies real progress out-of-band against
  the target system, samples status on a ~5-minute cadence, and
  classifies WORKING/STALLED/DONE/FAILED with timestamps and elapsed time.
  USE FOR: live test, integration test, deployment, installation,
  long-running job, monitor progress, poll status, heartbeat, is it stuck,
  still running, still working, background job, watch deployment, report
  progress, timestamped status, tail log, out-of-band verification,
  remote job, ssh, winrm, elapsed time.
  DO NOT USE FOR: short or fast commands that return promptly; authoring
  other skills (use skill-creator); building evals (use agent-evals).
---

# Long-Running Job Monitor

Runs, monitors, and reports on jobs that take many minutes to tens of minutes — live tests, integration suites, installers, deployments — and that typically buffer stdout and print only at the end. Turns an opaque "it is running" into a stream of **timestamped, verifiable** status the user can read as "still working" versus "stuck".

## When to use

- The agent kicks off a live/integration test run, an installer, or a deployment that will not return promptly.
- The user asks "is it done?", "is it stuck?", "still running?", "watch the deployment", or "tell me when it finishes".
- A job's own output is silent or buffered and the agent needs an independent read on progress.
- Skip for short commands that return in seconds — the overhead is not worth it.

## Extends the execution foundation

This skill is the **monitoring layer** on top of the repo's execution model. Do not re-derive the basics here:

- Sync-no-timeout vs async, and the never-self-`Start-Sleep` / never-busy-wait rule — see `.memory-bank/systemPatterns.md` Decision 10 ("Long-running command execution").
- The VS Code-freeze-avoidance detached-`Start-Process` pattern for Sampler/Pester — see [`Instructions/powershell-execution-safety.instructions.md`](../../Instructions/powershell-execution-safety.instructions.md).

What this skill adds: self-timestamping instrumented logs, heartbeats, out-of-band target verification, a ~5-minute status cadence, a stuck-vs-working heuristic, and completion/cleanup.

## Outcome

Whenever the agent starts a long job, it:

1. runs the job so it **survives and is observable**,
2. reports **timestamped** status (so "still working" is distinguishable from "stuck"),
3. checks progress on a **~5-minute** cadence, and
4. **verifies the real end-state** on the target and cleans up throwaway resources on completion.

## The one rule (non-negotiable)

> [!IMPORTANT]
> While a monitored job is in flight, the **first line of every reply** — at start, on every turn while waiting, on completion, and whenever asked — MUST be the status line below. A reply that touches the job but does not open with it is a **process violation**.

```text
[YYYY-MM-DD HH:mm UTC] elapsed=Xm | phase=… | status=WORKING|STALLED|DONE|FAILED | next=…
```

That is the minimum opener; the complete form (heartbeat age + the out-of-band target read) lives in [Reporting format](#reporting-format) and also satisfies the rule.

**Supersedes the generic opener.** While a job is in flight this status line replaces any plain per-turn timestamp — a bare `[YYYY-MM-DD HH:mm UTC]` is not sufficient. Extend that same opening timestamp into the full status line.

**Per-turn trigger — the real failure mode.** The rule fires on every turn the job is still running, not only on status turns. When the user's turn is about something else, still open with the status line, then answer their question. Silence between turns — or "it's still going" with no timestamp and no elapsed — is a missing heartbeat, not "waiting correctly".

**Make leading with status nearly free.** Pin the start time once from the log's `START` line (step 1); `elapsed` is now-minus-START, never recomputed from scratch. When the `.status` sidecar (step 4) exists, copy its latest line straight into the reply — leading with status then costs one file read, not a fresh investigation.

### STATUS LINE — every in-flight reply

Enforce this the way pre/post-flight is enforced. Before sending any reply while the job runs:

- [ ] Opens with a UTC timestamp `[YYYY-MM-DD HH:mm UTC]`.
- [ ] States `elapsed` since the pinned START — not "a while", not omitted.
- [ ] Names the current `phase` and a `status` of WORKING / STALLED / DONE / FAILED.
- [ ] Names the `next` milestone.
- [ ] Cites out-of-band evidence — a target probe (step 3), not just "still running" from the log.

## Workflow

### 1. Instrument the job into a self-describing, timestamped log

Wrap the job so the log — not the agent's memory — is the source of truth. Emit a `START` line, a line per phase, periodic heartbeats during long silent phases, and a unique terminal marker (`<JOB>-DONE` / `<JOB>-FAILED`). Tee stdout+stderr to a persistent file so nothing is lost if the terminal detaches.

```powershell
$log = "$env:TEMP\job-deploy-vm01.log"
"[{0}] START deploy-vm01" -f (Get-Date -f 'HH:mm:ss') | Tee-Object $log
# ... each step emits "[HH:mm:ss] <phase>" ...
# ... during a long silent phase a background heartbeat emits "[HH:mm:ss] still <phase>…" ...
"[{0}] deploy-vm01-DONE" -f (Get-Date -f 'HH:mm:ss') | Tee-Object $log -Append
```

Rationale: orchestrators and installers buffer stdout and print only at the end. A self-timestamping wrapper plus heartbeats make working-vs-stuck legible from the log alone.

### 2. Run it so it survives and self-notifies — never busy-wait

- **Prefer sync with no timeout.** The terminal tool blocks, returns full output on completion, and auto-degrades to a background id plus a completion notification if it exceeds the internal cap. The agent is notified next turn — it does not poll.
- **Use async only for truly indefinite processes** (servers, watchers, the monitor sidecar in step 4).
- **Never `Start-Sleep` in the agent's own foreground command to "wait 5 minutes"**, and never hand-roll a poll loop. The agent cannot self-schedule a timer; it relies on the completion notification and on-demand checks.
- Read background output only when the tool says a command moved to background, timed out, or needs input — not as a polling loop.

### 3. Verify progress OUT OF BAND against the target (read-only)

The job's own output lags or buffers, so confirm real progress by querying the target system directly and read-only. This is what separates "genuinely progressing" from "hung".

```powershell
# on-demand liveness + log tail (agent runs this when asked / when notified)
$alive = [bool](Get-CimInstance Win32_Process -Filter "Name='pwsh.exe'" |
                Where-Object CommandLine -match 'job-deploy-vm01')
"[{0}] alive={1}" -f (Get-Date -f 'HH:mm:ss'), $alive
Get-Content $log -Tail 15
```

Pick the target probe per domain — hypervisor/cloud API, guest agent, SSH/WinRM, DB query, HTTP health endpoint, `kubectl get`, `az`/`aws` status. Each probe returns a one-line target-state summary plus a change-detector value. For ready snippets per domain, read [`references/out-of-band-verification.md`](references/out-of-band-verification.md).

### Remote jobs (SSH / WinRM / PowerShell Direct)

When the real work runs on a remote machine (lab VM, cloud host) reached over SSH, WinRM, or PowerShell Direct, apply techniques 1–3 **on the remote side** and treat the control channel as separate from the job:

- **Detach the job on the remote so it outlives the channel.** SSH: `ssh host 'nohup ./install.sh >/var/tmp/job.log 2>&1 &'` (or `setsid` / `systemd-run --scope` / `tmux`). WinRM: an `Invoke-Command` that launches a detached remote process, a scheduled task, or a remote `Start-Job` writing to a persistent remote log. A job tied to the channel dies when the channel closes.
- **Keep the instrumented log on the remote** at a persistent path (remote `$env:TEMP`, `/var/tmp`), not the control node. Fetch its tail on demand over the channel: `ssh host 'tail -n 15 /var/tmp/job.log'` or `Invoke-Command { Get-Content $using:log -Tail 15 }`.
- **Run the liveness probe on the remote**, not locally: `Invoke-Command { Get-CimInstance Win32_Process -Filter "..." }` or `ssh host 'pgrep -af install'`.
- **Channel death is not job death.** If the SSH/WinRM connection drops, do **not** report FAILED — reconnect and re-read the remote `<JOB>-DONE`/`-FAILED` marker and the remote process state. Only the remote marker plus the remote process are authoritative; the connection is just a viewport.
- **Prefer a second, independent control plane for the out-of-band check** (hypervisor API, HTTP health) so a dead channel does not blind the agent. The sidecar's `-GetTargetState` can be any remote probe (`{ Invoke-Command ... }` / `{ ssh ... }`) — no script change needed.

### 4. Optional monitor sidecar for unattended 5-minute sampling

For hands-off sampling, launch a **separate background** watcher that every 300 s appends a timestamped status line (target-state summary + heartbeat age) to a `.status` file for the job's expected duration. The agent reads that file on demand or when notified. A backgrounded self-sleeping sidecar is fine — the prohibition is only on the *agent* blocking itself.

```powershell
Start-Process pwsh -WindowStyle Hidden -ArgumentList @(
    '-NoProfile', '-File', 'scripts/Start-JobMonitor.ps1',
    '-JobName', 'deploy-vm01',
    '-DurationMinutes', '30',
    '-GetTargetState', "{ (Invoke-RestMethod 'http://host:8006/api2/json/cluster/resources').data }"
)
# later, on demand:
Get-Content "$env:TEMP\job-deploy-vm01.status" -Tail 5
```

The sidecar is [`scripts/Start-JobMonitor.ps1`](scripts/Start-JobMonitor.ps1); pass a read-only `-GetTargetState` probe from step 3.

### 5. Stuck-vs-working heuristic + strict timestamps

Every status report opens with the mandatory status line ([The one rule](#the-one-rule-non-negotiable)), then classifies:

| Status | Definition | Agent action |
|---|---|---|
| **WORKING** | Heartbeat or target state changed within threshold. | Report and continue; name the next milestone. |
| **STALLED** | No heartbeat and no target change for > threshold (e.g. 2x the expected phase time). | Surface it explicitly — do not silently keep waiting. Report heartbeat age + last target state. |
| **DONE** | Terminal marker present AND expected end-state verified on the target. | Read full log, report timestamped pass, clean up. |
| **FAILED** | Process exited without the DONE marker, or an error marker is present. | Read the log tail and the target's error surface; report. |

Set the STALLED threshold to ~2x the expected time of the current phase, not a global constant.

## Reporting format

The **complete status line** — the mandatory opener from [The one rule](#the-one-rule-non-negotiable) with heartbeat age and the out-of-band target read added. Prefer this fuller form; it satisfies the gate:

```text
[YYYY-MM-DD HH:mm UTC] elapsed=Xm | phase=… | last-heartbeat=Ns ago | target: <one-line> | status=WORKING|STALLED|DONE|FAILED | next=<milestone>
```

Worked example:

```text
[2026-07-07 14:32 UTC] elapsed=12m | phase=guest-provisioning | last-heartbeat=40s ago | target: VM 101 running, guest-agent responding | status=WORKING | next=service-up on :443
```

### Anti-patterns to match against

❌ Answering an unrelated question mid-job with no status line at all:

```text
Sure — to rename the branch, run: git branch -m new-name
```

❌ A status update with no timestamp and no elapsed:

```text
It's still going, looks fine so far.
```

✅ Lead with the status line, then answer the unrelated question:

```text
[2026-07-07 14:37 UTC] elapsed=17m | phase=service-start | last-heartbeat=15s ago | target: HTTP 200 on :443 | status=WORKING | next=smoke tests
To rename the branch, run: git branch -m new-name
```

### 6. Completion + cleanup

On the completion notification or the DONE marker:

1. Read the **full** log (not just the tail).
2. Verify the expected end-state on the target one more time (service up, HTTP 200, row present, pod Ready).
3. Report a timestamped pass/fail summary in the format above.
4. Tear down throwaway test resources (temp VMs, scratch DBs, temp files, the `.status`/log if no longer needed).

If the process exited without a DONE marker, treat it as FAILED: read the log tail and the target's error surface before reporting.

## Edge cases

- **Buffered stdout (prints only at the end)** — do not trust silence. Rely on out-of-band target queries (step 3) and log heartbeats for real progress.
- **Process dies mid-run** — liveness false and no DONE marker means FAILED. Surface the log tail and the target error, not a generic "it stopped".
- **Control channel drops (remote jobs)** — an SSH/WinRM disconnect is not a job failure. Reconnect and re-check the remote marker + remote process before classifying; a job detached on the remote keeps running while the channel is down.
- **No target API available** — fall back to process liveness + heartbeat age; state the reduced confidence explicitly (liveness is not progress).
- **Legitimately long silent phase** — heartbeats prevent a false STALLED; size the threshold to the phase, not a global value.
- **Log in a build output folder** — never; Sampler's Clean wipes `output/`. Use `$env:TEMP` (see the execution-safety instruction).

## Evals

Four eval prompts (Claude-A/Claude-B loop) live in [`notes-evals.md`](notes-evals.md): a "deploy and tell me when done" happy path, an "is it stuck?" classification, a buffered-stdout job that only out-of-band checks reveal, and a mid-run death detected as process-dead-without-DONE.

## Checklist

- [ ] Job wrapped to emit `START`, per-phase lines, heartbeats, and a `<JOB>-DONE`/`-FAILED` marker.
- [ ] stdout+stderr tee'd to a persistent `$env:TEMP` log.
- [ ] Run sync-no-timeout (or async if indefinite); no agent-side `Start-Sleep`/poll loop.
- [ ] An out-of-band, read-only target probe is chosen for step 3.
- [ ] Remote jobs: detached on the remote, log + liveness on the remote, and a channel drop is treated as reconnect-and-recheck (not FAILED).
- [ ] Every in-flight reply opens with the mandatory status line — timestamp + elapsed + phase + status + next + out-of-band evidence ([The one rule](#the-one-rule-non-negotiable)); a bare `[… UTC]` opener is not sufficient.
- [ ] On completion: full log read, end-state verified on target, throwaway resources cleaned up.
