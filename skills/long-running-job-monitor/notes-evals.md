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

## E10 — Live proof launch, domain vocabulary only (trigger rate)

Prompt: "Kick off the full Hyper-V proof against the lab host — the whole run
takes about 45 minutes."

The prompt names no mechanism: it never says "monitor", "heartbeat", or
"background". Vivarium's glossary makes *proof* the canonical word for a live
integration run, so the skill has to be selected from the description's domain
vocabulary alone. Measure trigger rate over 3 runs against the 0.5 threshold.

Pass:

- The skill is named in the PRE-FLIGHT line of at least 2 of the 3 runs.
- The proof is launched through the canonical detached launcher, not a
  hand-rolled `Start-Process` plus `WaitForExit` that blocks the chat until the
  run finishes.
- A cadence tick is armed in the same turn as the launch — 45 minutes exceeds
  the cadence interval — and the turn then ends without polling.

Fail:

- The skill does not load, the launch is hand-rolled, and the chat stays silent
  until the user asks whether anything is running.

## E11 — Trigger set from the RdsFarmManager session (with/without delta)

Labelled query set:
[`trigger-queries.long-running-job-monitor.json`](../agent-evals/assets/trigger-queries.long-running-job-monitor.json).
Every case is a real phrasing from the 2026-09-04 `C:\git\RdsFarmManager`
session in which `./test.ps1` — a twenty-minute Pester suite — was run five
times and this skill was never loaded. The two cases that matter most are
`pos-01`, where the agent starts the verification run on its own and the user
never asks for one, and `pos-05`, where the user asks an unrelated question
while the run is in flight and the reply still owes the status line.

Run it with the `agent-evals` harness:

```powershell
$workDir = Join-Path $env:TEMP 'trigger-evals/long-running-job-monitor'
./skills/agent-evals/scripts/run-trigger-evals.ps1 -Mode Prepare `
  -QueryFile ./skills/agent-evals/assets/trigger-queries.long-running-job-monitor.json `
  -TargetSkill long-running-job-monitor -SkillRoot ./skills -WorkDir $workDir -Repetitions 3
```

### Recorded result — 2026-09-04

Paired arms against the same 47-skill catalogue, `claude-haiku-4.5` as the
judge in a fresh context per call, threshold 0.5. `before` is the description
at `HEAD` prior to this change; `after` is the widened one. Positives ran 3
repetitions; negatives ran 1, because every negative was unanimous and the
question they answer — did the added build/test vocabulary start
over-triggering — is answered by any hit at all.

| Arm | train | validation | false positives | false negatives |
|---|---|---|---|---|
| before | 5/7 (71 %) | 4/5 (80 %) | 0 | `pos-01` 0/3, `pos-02` 1/3, `pos-05` 0/3 |
| after | 6/7 (86 %) | 4/5 (80 %) | 0 | `pos-01` 0/3, `pos-05` 1/3 |

Delta: train +15 pp, driven entirely by `pos-02` ("run the full test suite")
going 0.33 → 1.00. Validation is flat at the split level, but `pos-05` moved
0.00 → 0.33 — still under threshold. No negative flipped, so widening into
test-and-build vocabulary did not buy positives by over-triggering; the
`DO NOT USE FOR` lines naming `sampler-build-debug` and `pester-patterns` hold
`neg-01` and `neg-02` at zero.

The `after` arm was measured at 977 characters, before `live proof` was
restored. Fitting the 1000-character soft cap cost `proof harness`,
`hour-long run`, `chat heartbeat`, `report every N minutes`, `log tail`,
`timestamped status`, and `periodic status`; `live proof`, `proof run`,
`long-running job`, and `keep me posted` carry those concepts, and E10 remains
the guard on the proof vocabulary. A one-repetition confirmation sweep on the
exact shipped 989-character text returned the same selection for all twelve
queries — train 6/7, validation 4/5, 0 false positives — so the numbers above
describe what ships.

`pos-01` stays at 0/3 in both arms, and that is the finding rather than a
defect to iterate away. Nothing in "fix the null reference in Get-RdsFarm.ps1
and make sure nothing else regressed" is about monitoring; the twenty-minute
run only exists because the agent decided to verify. No description can be
matched against a decision the agent has not made yet, which is why the load
trigger belongs in
[`powershell-execution-safety.instructions.md`](../../com.github.copilot/rules/powershell-execution-safety.instructions.md),
which auto-applies by `applyTo` and is in context before the launch. Treat a
future `pos-01` hit as a bonus, not as the fix.

Caveats on the number: the judge was dispatched one subagent per call rather
than through ShellPilot, so temperature was not pinned and negatives carry a
single sample. Re-run through `-Mode Execute -Temperature 0` when a backend is
available before quoting these figures as a baseline to beat.
