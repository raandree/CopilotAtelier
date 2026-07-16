---
name: long-running-job-monitor
description: >-
  Monitors long-running live tests, integrations, installations, and
  deployments with timestamped logs, heartbeats, terminal markers,
  out-of-band target probes, and WORKING/STALLED/DONE/FAILED classification.
  Preserves remote jobs across control-channel drops and treats restarts as new
  readiness epochs. USE FOR: live test, integration test, deployment,
  installation, long-running job, monitor progress, heartbeat, is it stuck,
  still running, background job, watch deployment, timestamped status, log
  tail, out-of-band verification, remote job, SSH, WinRM, elapsed time.
  DO NOT USE FOR: root-cause diagnosis of AutomatedLab Proxmox provisioning
  (use automatedlab-proxmox), generic WinRM connectivity/configuration diagnosis
  (use winrm-troubleshooting), short commands, skill authoring (use
  skill-creator), agent evals (use agent-evals).
---

# Long-Running Job Monitor

Runs, monitors, and reports on jobs that take many minutes to tens of minutes — live tests, integration suites, installers, deployments — and that typically buffer stdout and print only at the end. Turns an opaque "it is running" into a stream of **timestamped, verifiable** status the user can read as "still working" versus "stuck".

## When to use

- The agent kicks off a live/integration test run, an installer, or a deployment that will not return promptly.
- The user asks "is it done?", "is it stuck?", "still running?", "watch the deployment", or "tell me when it finishes".
- A job's own output is silent or buffered and the agent needs an independent read on progress.
- Skip for short commands that return in seconds — the overhead is not worth it.

## Extends the execution foundation

This skill is the monitoring layer on top of the terminal execution contract.
For sync versus async execution, passive completion notifications, stream
redirection, and interactive prompts, read
[`Instructions/powershell-execution-safety.instructions.md`](../../Instructions/powershell-execution-safety.instructions.md).

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
[YYYY-MM-DD HH:mm UTC] elapsed=Xm | phase=… | last-progress=… | progress=… | status=WORKING|STALLED|DONE|FAILED | next=…
```

That is the minimum opener; the complete form adds heartbeat age, liveness,
and the target summary. See [Reporting format](#reporting-format).

**Supersedes the generic opener.** While a job is in flight this status line replaces any plain per-turn timestamp — a bare `[YYYY-MM-DD HH:mm UTC]` is not sufficient. Extend that same opening timestamp into the full status line.

**Per-turn trigger — the real failure mode.** The rule fires on every turn the job is still running, not only on status turns. When the user's turn is about something else, still open with the status line, then answer their question. Silence between turns — or "it's still going" with no timestamp and no elapsed — is a missing heartbeat, not "waiting correctly".

**Make leading with status nearly free.** Pin the start time once from the log's
`START` line. When the `.status` sidecar exists, read its latest line as evidence
for `last-progress`, `progress`, heartbeat, liveness, and target summary. Then
construct the complete opener with UTC date, phase, status, and next milestone;
never copy the sidecar line verbatim as the reply opener.

### STATUS LINE — every in-flight reply

Enforce this the way pre/post-flight is enforced. Before sending any reply while the job runs:

- [ ] Opens with a UTC timestamp `[YYYY-MM-DD HH:mm UTC]`.
- [ ] States `elapsed` since the pinned START — not "a while", not omitted.
- [ ] Names the current `phase` and a `status` of WORKING / STALLED / DONE / FAILED.
- [ ] States the current `ProgressToken` and age since it last advanced.
- [ ] Names the `next` milestone.
- [ ] Separates target summary/liveness from out-of-band progress evidence.

## Workflow

### 1. Instrument the job into a self-describing, timestamped log

Wrap the job so the log — not the agent's memory — is the source of truth. Emit a `START` line, a line per phase, periodic heartbeats during long silent phases, and a unique terminal marker (`<JOB>-DONE` / `<JOB>-FAILED`). Tee stdout+stderr to a persistent file so nothing is lost if the terminal detaches.

```powershell
$runId = [guid]::NewGuid().ToString('N')
$jobName = "deploy-vm01-$runId"
$log = Join-Path $env:TEMP "job-$jobName.log"
$statusPath = Join-Path $env:TEMP "job-$jobName.status"
"[{0}] START {1}" -f (Get-Date -f 'HH:mm:ss'), $jobName | Tee-Object $log
# ... each step emits "[HH:mm:ss] <phase>" ...
# ... during a long silent phase a background heartbeat emits "[HH:mm:ss] still <phase>…" ...
"[{0}] {1}-DONE" -f (Get-Date -f 'HH:mm:ss'), $jobName | Tee-Object $log -Append
```

Rationale: orchestrators and installers buffer stdout and print only at the end.
The wrapper preserves evidence, and heartbeats prove monitor liveness. Only a
phase-specific `ProgressToken` advancement proves work progress.

### 2. Run it so it survives and self-notifies — never busy-wait

- **Use sync with no timeout for ordinary one-shot commands.** The terminal tool
  returns full output on completion and can surface background/input state.
- **Always detach Pester and builds.** `Invoke-Pester`, `Invoke-Build`, and build
  entry points run through the canonical launcher (`Start-Process` on Windows,
  `nohup` on non-Windows) with process/log/result metadata because their module
  loading and output can freeze VS Code when attached to the terminal or PowerShell
  Extension host.
- The implementation is
  [`scripts/Start-DetachedPowerShell.ps1`](scripts/Start-DetachedPowerShell.ps1).
- **Use async only for truly indefinite processes** (servers, watchers, the monitor sidecar in step 4).
- **Never `Start-Sleep` in the agent's own foreground command to "wait 5 minutes"**, and never hand-roll a poll loop. The agent cannot self-schedule a timer; it relies on the completion notification and on-demand checks.
- Read background output only when the tool says a command moved to background, timed out, or needs input — not as a polling loop.

### 3. Verify progress OUT OF BAND against the target (read-only)

The job's own output lags or buffers, so confirm progress with a phase-specific,
read-only target probe. This separates genuine progress from liveness and
volatile activity.

```powershell
# on-demand liveness + log tail (agent runs this when asked / when notified)
$alive = [bool](Get-CimInstance Win32_Process -Filter "Name='pwsh.exe'" |
                Where-Object CommandLine -match 'job-deploy-vm01')
"[{0}] alive={1}" -f (Get-Date -f 'HH:mm:ss'), $alive
Get-Content $log -Tail 15
```

Pick the target probe per domain: hypervisor/cloud API, guest agent, SSH/WinRM,
database query, HTTP health endpoint, or Kubernetes status. Every probe returns
exactly one object with `Summary`, `Liveness`, and `ProgressToken`. Store the
token and the time it last advanced; never compare `Summary` or `Liveness` to
classify progress. For examples, read
[`references/out-of-band-verification.md`](references/out-of-band-verification.md).

### Readiness epochs and dependency probes

A restart invalidates readiness established during the prior boot. Start a new
readiness epoch at the restart timestamp and re-probe every dependency used by
the next phase.

Probe the required service, not a convenient proxy:

- VM `running` proves only hypervisor state.
- Ping proves only ICMP and part of the guest network stack.
- An open TCP port proves a listener, not protocol or authentication success.
- `Test-WSMan`, an SSH handshake, HTTP health response, or database query proves
  the corresponding service boundary.

Model each required transition as a `ProgressToken`, such as `vm-running`,
`tcp-5985-open`, then `wsman-ready`. Classify `WORKING` only while elapsed time
since the last token advancement remains within the phase-sized threshold. Do
not run remoting-dependent repair merely because ping returned before WinRM or
SSH.

### Remote jobs (SSH / WinRM / PowerShell Direct)

When the real work runs on a remote machine (lab VM, cloud host) reached over SSH, WinRM, or PowerShell Direct, apply techniques 1–3 **on the remote side** and treat the control channel as separate from the job:

- **Detach the job on the remote so it outlives the channel.** SSH: `ssh host 'nohup ./install.sh >/var/tmp/job.log 2>&1 &'` (or `setsid` / `systemd-run` / `tmux`). WinRM or PowerShell Direct: prefer a scheduled task whose action writes the persistent remote log. For WSMan, a persistent PSSession may run the job only when the session is explicitly disconnected and later reconnected. Never use bare `Start-Job` inside a temporary `Invoke-Command`; closing that session cancels the job.
- **Keep the instrumented log on the remote** at a persistent path (remote `$env:TEMP`, `/var/tmp`), not the control node. Fetch its tail on demand over the channel: `ssh host 'tail -n 15 /var/tmp/job.log'` or `Invoke-Command { Get-Content $using:log -Tail 15 }`.
- **Run the liveness probe on the remote**, not locally: `Invoke-Command { Get-CimInstance Win32_Process -Filter "..." }` or `ssh host 'pgrep -af install'`.
- **Channel death is not job death.** If the SSH/WinRM connection drops, do **not** report FAILED — reconnect and re-read the remote `<JOB>-DONE`/`-FAILED` marker and the remote process state. Only the remote marker plus the remote process are authoritative; the connection is just a viewport.
- **Prefer a second, independent control plane for the out-of-band check** (hypervisor API, HTTP health) so a dead channel does not blind the agent. The sidecar's `-GetTargetState` can be any remote probe (`{ Invoke-Command ... }` / `{ ssh ... }`) — no script change needed.

### 4. Optional monitor sidecar for unattended 5-minute sampling

For hands-off sampling, launch a separate background watcher that appends the
structured probe, heartbeat age, and age since `ProgressToken` advancement to a
`.status` file. The agent reads that file on demand or when notified. A
backgrounded self-sleeping sidecar is fine; the agent itself must not block.

```powershell
$probeText = @'
$state = Invoke-RestMethod 'http://host/healthz'
[pscustomobject]@{
  Summary       = $state.status
  Liveness      = $true
  ProgressToken = $state.generation
}
'@
$encodedProbe = [Convert]::ToBase64String(
  [Text.Encoding]::Unicode.GetBytes($probeText)
)
$monitorScript = Join-Path $HOME (
  '.copilot/skills/long-running-job-monitor/scripts/Start-JobMonitor.ps1'
)
if (-not (Test-Path -LiteralPath $monitorScript -PathType Leaf)) {
  throw "Monitor sidecar not found: $monitorScript"
}
$escapedMonitorScript = $monitorScript.Replace("'", "''")
$escapedJobName = $jobName.Replace("'", "''")
$escapedLogPath = $log.Replace("'", "''")
$escapedStatusPath = $statusPath.Replace("'", "''")
$launcherPayload = @"
& '$escapedMonitorScript' -JobName '$escapedJobName' -DurationMinutes 30 -LogPath '$escapedLogPath' -StatusPath '$escapedStatusPath' -GetTargetStateBase64 '$encodedProbe'
"@
$encodedLauncher = [Convert]::ToBase64String(
  [Text.Encoding]::Unicode.GetBytes($launcherPayload)
)
$launcherPath = Join-Path $HOME (
  '.copilot/skills/long-running-job-monitor/scripts/Start-DetachedPowerShell.ps1'
)
$launch = & $launcherPath -EncodedCommand $encodedLauncher

[pscustomobject]@{
  ProcessId  = $launch.ProcessId
  LogPath    = $log
  StatusPath = $statusPath
  Platform   = $launch.Platform
  ResultPath = $launch.ResultPath
}
# later, on demand:
Get-Content -LiteralPath $statusPath -Tail 5
```

Encode the probe body as shown; do not wrap it in surrounding script-block
braces because `ScriptBlock.Create()` already creates that outer block.

The sidecar is [`scripts/Start-JobMonitor.ps1`](scripts/Start-JobMonitor.ps1);
launch it through
[`scripts/Start-DetachedPowerShell.ps1`](scripts/Start-DetachedPowerShell.ps1)
and pass a read-only probe from step 3.

### 5. Stuck-vs-working heuristic + strict timestamps

Every status report opens with the mandatory status line ([The one rule](#the-one-rule-non-negotiable)), then classifies:

At phase start, record the initial `ProgressToken` and timestamp. Reset that
timestamp only when the token changes to another valid phase-specific value.

| Status | Definition | Agent action |
|---|---|---|
| **WORKING** | Time since `ProgressToken` advancement is within the phase threshold. | Report token, age, and next milestone. |
| **STALLED** | `ProgressToken` has not advanced within the phase threshold, regardless of changing summary, liveness, telemetry, or heartbeat. | Report token, last-progress age, and target error surface. |
| **DONE** | Terminal marker present AND expected end-state verified on the target. | Read full log, report timestamped pass, clean up. |
| **FAILED** | Process exited without the DONE marker, or an error marker is present. | Read the log tail and the target's error surface; report. |

A heartbeat proves only that the monitor or controller can still emit output; it
is not target progress and never resets `last-progress`. Set the `STALLED`
threshold to ~2x the expected time of the current phase, not a global constant.

## Reporting format

The complete status line adds heartbeat age, liveness, and summary to the
mandatory `ProgressToken` fields:

```text
[YYYY-MM-DD HH:mm UTC] elapsed=Xm | phase=… | last-progress=Ns ago | progress=<token> | last-heartbeat=Ns ago | liveness=<value> | target=<summary> | status=WORKING|STALLED|DONE|FAILED | next=<milestone>
```

Worked example:

```text
[2026-07-07 14:32 UTC] elapsed=12m | phase=guest-provisioning | last-progress=40s ago | progress=guest-agent-ready | last-heartbeat=15s ago | liveness=true | target=VM 101 running, guest-agent responding | status=WORKING | next=service-up on :443
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
[2026-07-07 14:37 UTC] elapsed=17m | phase=service-start | last-progress=20s ago | progress=http-ready | last-heartbeat=15s ago | liveness=true | target=HTTP 200 on :443 | status=WORKING | next=smoke tests
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

- **Buffered stdout (prints only at the end)** — do not trust silence. Use
  out-of-band target or real phase changes for progress; use heartbeats only to
  show that the monitor remains alive.
- **Process dies mid-run** — liveness false and no DONE marker means FAILED. Surface the log tail and the target error, not a generic "it stopped".
- **Control channel drops (remote jobs)** — an SSH/WinRM disconnect is not a job failure. Reconnect and re-check the remote marker + remote process before classifying; a job detached on the remote keeps running while the channel is down.
- **No target API available** — fall back to process liveness + heartbeat age; state the reduced confidence explicitly (liveness is not progress).
- **Legitimately long silent phase** — size the threshold to the phase and
  choose an out-of-band change detector. Heartbeats prevent confusion with a
  dead monitor but do not prevent `STALLED` when real progress stops.
- **Target restarted** — discard readiness from the prior boot and probe the
  exact service required by the next phase; VM-running or ping alone is not
  readiness.
- **Log in a build output folder** — never; Sampler's Clean wipes `output/`. Use `$env:TEMP` (see the execution-safety instruction).

## Evals

Regression prompts live in [`notes-evals.md`](notes-evals.md), including
buffered output, mid-run death, remote channel loss, restart-scoped readiness,
and synthetic-heartbeat stall detection.

## Checklist

- [ ] Job wrapped to emit `START`, per-phase lines, heartbeats, and a `<JOB>-DONE`/`-FAILED` marker.
- [ ] stdout+stderr tee'd to a persistent `$env:TEMP` log.
- [ ] Run ordinary one-shot commands synchronously, Pester/builds detached, and
  indefinite services asynchronously; no agent-side `Start-Sleep`/poll loop.
- [ ] Detached Pester/build runs expose `ResultPath`; read `0`/`1` and the log
  only on demand.
- [ ] An out-of-band, read-only target probe is chosen for step 3.
- [ ] After any restart, prior readiness is discarded and the next phase's
  actual protocol is re-probed.
- [ ] Remote jobs: detached on the remote, log + liveness on the remote, and a channel drop is treated as reconnect-and-recheck (not FAILED).
- [ ] Every in-flight reply opens with the mandatory status line — timestamp + elapsed + phase + status + next + out-of-band evidence ([The one rule](#the-one-rule-non-negotiable)); a bare `[… UTC]` opener is not sufficient.
- [ ] On completion: full log read, end-state verified on target, throwaway resources cleaned up.
