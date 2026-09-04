---
status: current
last-verified: 2026-09-04
owner: software-engineer
source: current task evidence
---

# Active context

## Current focus

The Software Engineer Custom agent now owns its web-application feedback loop
on branch `ai/software-engineer-browser-tools`. Its frontmatter replaces the
preview-only `openSimpleBrowser` entry with VS Code's built-in `browser` tool
set, and its body requires reproduce, inspect, fix, and repeat validation using
page content, console errors, screenshots, and affected desktop and mobile
viewports. Browser-session evidence complements repository regression tests.

The browser boundary defaults to agent-opened ephemeral sessions on loopback
application origins. Authenticated state is available only when the user
explicitly shares a browser tab, and credentials never travel through chat.
The Contoso overlay inherits the conditional workflow text but deliberately
omits `browser`, preserving its no-egress tool surface.

The change was test-first. The new Software Engineer contract failed on the
missing tool and workflow, then passed 11/11. Inheritance passed 4/4, shared
lifecycle passed 10/10, and frontmatter passed 113/113. The native
`build,test` workflow passed 1,005 tests with 0 failures, 61 skips, and 78.51%
coverage against 65%. AST parsing, PSScriptAnalyzer, editor diagnostics, and
diff checks are clean. The Chat Customizations Evaluations extension is not
installed, so `/analyze-prompt` was unavailable; no live browser task was run.

The validated tree was deployed with `Setup-CopilotSettings.ps1`; the installed
Software Engineer file is a byte-exact SHA-256 match. Reload VS Code or reselect
the Custom agent before expecting the new tool set in an existing session.

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

Deploying it surfaced a second `Stop` hook nobody remembered: a `.github/hooks/`
smoke-test probe from 2026-08-10 whose `windows` override hardcoded
`D:\Git\CopilotAtelier\...`, erroring on every turn since. Both files are
deleted. It survived because `Hooks.Tests.ps1` asserts exactly this failure but
was scoped to one path, so a hook file one directory away sat outside every gate.
The suite now enumerates every tracked `hooks/*.json` and requires the shipped
configuration to be the only one.

## Previously: the `long-running-job-monitor` discovery failure

A 45-minute live Hyper-V proof ran in another workspace with the Skill never
loaded: no cadence tick, thirty silent minutes, two mid-job turns with no status
line. Every rule it broke was already written down correctly, so the defect is
discovery, not content. Two lessons generalise. A `USE FOR:` list must carry the
words the user's own glossary uses — that workspace says *proof*, the list said
"live test". And guidance that sits downstream of the step it constrains does not
bind that step: arming the tick lived in a later section, so an agent could
follow the launch step exactly and still end the turn with nothing armed.

## Earlier: the runaway `cycle: full` chain

Fifteen complete `software-engineer` ↔ `security-reviewer` round trips in one
session, 30 MB against a ~600 KB norm. Both handoff legs auto-submitted and the
only bound was prose — a cap neither side could count, because a handoff starts
the receiving agent with fresh context. Any ring of `send: true` handoffs is
unbounded by construction, so *Fix Issues Found* now sets `send: false` and
`tests/DevelopmentCycle.Tests.ps1` walks the whole graph and fails on one.

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

- `elster-form-capture` requires Playwright browser automation against a page
  the taxpayer explicitly shares, but the Tax Researcher Custom agent exposes
  only `openSimpleBrowser`. Before the agent can drive Mein ELSTER, replace that
  entry with `browser` and pin the login, credential, and transmission bounds.
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

Align the Tax Researcher Custom agent with `elster-form-capture`, then reload or
reselect both changed agents and verify one local web journey plus one shared
ELSTER draft journey without transmitting. Never push or open a pull request
without a new explicit request.
