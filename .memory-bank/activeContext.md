---
status: current
last-verified: 2026-09-02
owner: software-engineer
source: current task evidence
---

# Active context

## Current focus

The elapsed duration now lands inside the agent's own POST-FLIGHT block instead
of beside it. The first arrangement had the `Stop` hook print the line, and the
user rejected it on sight: VS Code renders a hook `systemMessage` as a detached,
collapsed *Warning from Stop hook* box, so the number the checklist was supposed
to carry sat next to the checklist, one click from invisible. Decision 0024 had
accepted that as a "cosmetic split" and flagged the rendering as the one thing
still unverified. It was neither cosmetic nor safe to assume.

The two constraints are hard and opposed: a hook can measure but cannot write
inside the model's output; the model can write there but cannot read a clock. The
only arrangement satisfying both is to keep the clock on disk and have the model
*read* it rather than recall it. `Get-SessionElapsed.ps1` does that — the agent
runs it as its last action and copies its single line verbatim. It costs one
command per turn, which the user chose deliberately over a free line in a
collapsed box.

`Add-SessionContext.ps1` hands over the reader's absolute path, because the agent
cannot resolve it across both deployment layouts. `Write-SessionClose.ps1` keeps
the `Stop` hook, since the turn counter still has to advance somewhere, but now
reports nothing unless the clock is unreadable — the one case where the agent's
own line could not be measured either. The reader is read-only and derives the
turn in progress as one past the closed count.

The general lesson is worth more than the fix: where a hook's output is
*rendered* is part of its contract. Verify it before designing around it.

## Previously: the session clock itself

A model has no clock, so both the opening timestamp and the duration are measured
by hooks and written to
`<LocalApplicationData>/CopilotAtelier/sessions/session-<key>.json` — on disk, so
they survive compaction. `UserPromptSubmit` cannot inject context (common output
format only, no `additionalContext`, the same limitation recorded for `PreCompact`
in decision 0021), and `PreToolUse` would spend tokens on every call. The clock
avoids `/tmp` (world-writable on Linux) and `.memory-bank/` (machinery, not
knowledge, and it must work without a Memory Bank).

The formatter shipped with a bug the tests caught: `[int]1.5` rounds in
PowerShell, so 90 minutes reported `2h 30m`. It floors explicitly now, and five
durations sitting where rounding and truncation disagree are pinned.

Deploying it surfaced a second `Stop` hook nobody remembered: `.github/hooks/`
held a smoke-test probe from 2026-08-10 whose `windows` override hardcoded
`D:\Git\CopilotAtelier\...`, the drive the repository sat on when it was
written. It had been erroring on every turn since. Both files are deleted; the
finding they were built to produce already lives in the hooks README.

The reason it survived is the part worth keeping. `Hooks.Tests.ps1` asserts
exactly this failure — that a hook command resolves to a script that exists —
but the suite is scoped to `com.github.copilot/hooks/hooks.json`. A second hook
file one directory away sat outside every gate the repository owns. The suite
now enumerates every tracked `*.json` directly inside a folder named `hooks` and
requires the shipped configuration to be the only one; the guard was proven by
planting a second file and watching it go red.

## Previously: the `long-running-job-monitor` discovery failure

A 45-minute live Hyper-V proof ran in another workspace with
`long-running-job-monitor` never loaded. The agent hand-rolled `Start-Process`
plus `WaitForExit` instead of the canonical detached launcher, armed no cadence
tick, left the chat silent for thirty minutes, and answered two mid-job turns
with no status line. Every rule it broke was already written down correctly. A
Skill that is never selected cannot be followed, so the defect is discovery,
not content.

The description carried "live test" and "integration test"; that workspace's
glossary makes *proof* the canonical term for a live integration run, so the
words the user actually typed matched nothing. The `USE FOR:` list now names
`live proof`, `proof harness`, `proof run`, and `hour-long run`, at 961
characters against the 1000-character soft cap. A "log log tail" typo in the
same list went with it.

The second defect generalises. Arming the cadence tick was described in the
*Chat heartbeat* section and in a checklist item prefixed "For unattended
cadence", so nothing on the launch path required it — an agent could follow
step 2 exactly, detach correctly, and end the turn with no tick armed. Guidance
that sits downstream of the step it constrains does not bind that step. Step 2
now carries the imperative, and the checklist item is unconditional.

E10 in `notes-evals.md` measures what structure cannot: a live-proof launch in
that workspace's vocabulary that never says "monitor", "heartbeat", or
"background", so the Skill must be selected on the description alone. It is a
notes-file eval, not a query set — `long-running-job-monitor` stays on the
`SkillTriggerCoverage` uncovered baseline, which shrinks only with a paid sweep.

## Earlier: the runaway `cycle: full` chain

Fifteen complete `software-engineer` ↔ `security-reviewer` round trips in one
autopilot session, 30 MB against a ~600 KB norm. Both handoff legs
auto-submitted and the only bound was prose — "after two rounds, stop the
cycle" — a cap neither side could count, because a handoff starts the receiving
agent with fresh context. The bound is now structural: *Fix Issues Found* sets
`send: false`, so a requested cycle still reaches the reviewer unattended while
re-entering implementation costs a deliberate click. Any ring of `send: true`
handoffs is unbounded by construction, so `tests/DevelopmentCycle.Tests.ps1`
walks the whole graph and fails on one. `cycle: full` and `review: on` / `auto`
/ `off` are both user-set and both default to off; only the final stage of a
cycle closes out, and `cycle: off` ends the chain at whichever stage holds the
work. The rules sit in the four agent bodies, not a Skill, and state passes
through `.memory-bank/decisions/` because a conversation does not survive a
compaction and a subagent never sees one.

## Still open from the 1.0 migration

The plugin package moved to Agent Plugins 1.0, and the package is now the
primary layout rather than a second view of the module payload. `plugin.json`
declares the canonical `$schema`, the legacy `agents` and `skills` path fields
are gone, `Skills/` is root `skills/`, and all four Copilot-specific component
types live under `com.github.copilot/{agents,rules,commands,hooks}`. The module
deployment is preserved by translation: the installer maps deployed name to
source path, so `~/.copilot/{agents,instructions,skills,prompts,hooks}` is
unchanged. Decision 0023 records the trade-off it accepts — cross-type relative
links are now correct in the package view and wrong in the deployed view.

Unverified and deliberately so: no documentation states whether
`.instructions.md` and `.prompt.md` register from `com.github.copilot/rules`
and `com.github.copilot/commands`. The bet is one-sided, since the module path
delivers both regardless. Confirming it needs one empirical test — install from
source and check whether the instructions and prompts appear.

## Environment hazard — scripted bulk writes corrupt file content

Two bulk PowerShell read-modify-write passes over this working tree replaced
whole file contents with a monoalphabetic substitution cipher (`instructions`
→ `nnkteuotnonk`, `applyTo` → `aeelyTo`), 129 files each time. Both were caught
and fully restored from git; no corruption reached a commit.

- It is asynchronous. The script's own byte-exact read-back verification passed
  for all 175 files, and `git diff` showed the corruption afterwards, so the
  rewrite lands after the write returns. A verify-after-write loop cannot
  detect it.
- A single-file scripted write was clean, so it correlates with volume.
- Every `replace_string_in_file` edit was clean, across roughly forty files.

Until the cause is found, edit files through the editor tooling, and treat any
scripted bulk rewrite of this tree as unsafe. `git grep -l -e nnkteuotnon -e\naeelyTo` detects it in one pass.

## Blocked, not deferred

The ShellPilot module and `Invoke-ShpBatch` are absent on this machine, so
`-Mode Execute` is unavailable for both eval harnesses. That blocks the two
measurement items outright rather than by choice of priority:

- The 75 prepared route-selection prompts cannot be answered, so no
  pass@k or pass^k result exists yet.
- The seven authored trigger-query sets cannot be swept, so `german-tax-research`
  and the other 37 baselined Skills stay unmeasured for discovery.

Both need ShellPilot plus a paid model backend, and a sweep costs money, so the
run needs an explicit go-ahead rather than an assumption.

## Open findings

- No trigger-query set was authored for `german-tax-research`. Adding one would
  flip its coverage test from skipped to enforced while the sweep that gives it
  meaning cannot run, growing the "authored but never measured" debt the seven
  existing sets already represent. Author it with the sweep, not before.
- The development cycle ships unmeasured for the same reason: the tests prove
  its structure, not that four live stages actually hand over correctly.

## Carried forward from the route-selection eval

- `Invoke-MemoryBankRouteSelectionEval.ps1` has offline `Prepare` and `Grade`
  modes, and `MemoryBankRouteSelection.Tests.ps1` covers prompt isolation, label
  leakage, fallback, strict shape, reliability aggregation, and failure
  accounting.
- The first stage infers routes and fallback only; the deterministic resolver
  still receives human labels for `durableWrite`, role files, and Decision
  records.
- Context-window cost, latency, and answer quality under routed versus full
  loading remain unmeasured. Safety is gameable on its own \u2014 a reply naming
  every route never misses \u2014 and no precision floor is set, so `Passed = True`
  at low precision is not yet a failing build.

## Carried forward from earlier focuses

- `WindowsAccessControl` slots 1 and 2 use the older ink-variant reading of
  dark/light, so two sets in one shared library disagree on "dark mode". That
  repository is not in this workspace.
- The `brand-logo-system` integration step was measured on one project only.
- The `skill-creator` description edit remains unproven: train reached 100 %
  while validation fell, which is the overfitting signal.

## Next step

Redeploy. Deployed Customizations are copies under the Canonical target, not
links to this worktree, so the fixed `long-running-job-monitor` description and
the `security-reviewer.agent.md` fail leg — still `send: true` there — take
effect only after `Install-CopilotAtelier` or `Setup-CopilotSettings.ps1` runs.
Then get a decision on the paid sweeps. With a go-ahead: install ShellPilot,
answer the 75 route-selection prompts against one pinned model in fresh
contexts, grade them, sweep the seven trigger-query sets, and author
`german-tax-research`'s set in the same pass. Without one, the unblocked work is
splitting the nine over-budget Skill bodies, starting with
`german-legal-research` at 780 lines.
