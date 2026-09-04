---
status: current
last-verified: 2026-09-04
owner: software-engineer
source: current task evidence
---

# Active context

## Current focus

The Custom agent standards audit is now partly remediated. Security Reviewer
and Technical Writer can delegate explicitly to `research-analyst`; DevOps
Training Writer uses real coordinator/subagent composition instead of claiming
implicit inheritance; Research Analyst no longer exposes a targetless
pseudo-handoff to a Prompt. Career, legal, and tax records live under separate
`.memory-bank/<role>/` namespaces, with ambiguous legacy files preserved until
the user assigns them. Every formerly web-preview-only agent now exposes the
current `browser` tool; Contoso remains browser-free.

`tests/AgentBestPractices.Tests.ps1` adds semantic checks for those contracts,
every handoff target, the cross-client README caveat, and the 30,000-character
prompt limit. The four existing oversized bodies are a shrink-only baseline,
not an exemption. The test went red on all six defect classes before the fixes
and now passes 24/24. The full detached `build,test` gate passes 1,029 tests
with 0 failures, 61 skips, 0
inconclusive, and 78.51% coverage against 65%; AST parsing, PSScriptAnalyzer,
Markdown diagnostics, corruption markers, and whitespace checks are clean.

The prompt-budget refactor is deliberately separate. Its forward Session
handoff is `.memory-bank/session/handoff-2026-09-04T1000Z.md`. The user asked
that this work remain uncommitted.

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

## Agent Plugins 1.0 status

The latest VS Code Agent Plugins documentation confirms all four Copilot-only
component paths under `com.github.copilot/`, including `rules/` and `commands/`.
The source layout chosen in Decision 0023 is therefore documented upstream;
only the accepted cross-type-link mismatch in the translated module deployment
remains.

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

- **High:** `software-engineer-contoso` claims no egress while retaining an
  unrestricted terminal and mandating a generic `security-reviewer` delegate
  that can read the repository and use web, GitHub, MCP, and terminal tools.
  Prose does not enforce the boundary, especially on native Windows where VS
  Code terminal sandboxing is unavailable.
- **High:** eleven older agents combine workspace/private-data access,
  untrusted web content, arbitrary execution, and broad MCP access. Replace
  copied omnibus tool lists with role-specific least-privilege surfaces. The
  README now documents staged private intake, local transformation, minimized
  public research, and user-confirmed browser actions, but guidance is not
  enforced containment.
- **Major:** `career-coach` (35,672 chars), `research-analyst` (43,376),
  `security-reviewer` (43,772), and `technical-writer` (35,018) exceed GitHub's
  30,000-character Custom agent prompt limit. The new test prevents growth; the
  separate Session handoff owns the refactor below the limit.
- **Major:** every profile omits `target` but declares a VS Code model-priority
  array and mostly VS Code-qualified tool IDs. Copilot CLI documents one model
  string plus CLI tool names such as `view`, `edit`, `powershell`, `grep`, and
  `task`; the README now warns that discovery is not capability parity, but
  product-specific profiles or a shared compatible subset remain open.
- **Medium:** no executed agent behavioral eval set exists. The semantic tests
  catch structural regressions, but the Chat Customizations Evaluations
  extension is not installed and no live capability comparison was run.

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

Open the forward Session handoff in a fresh chat and refactor the four oversized
Custom agent bodies one at a time. Treat the Contoso no-egress contradiction
and capability-isolated sensitive-research workflow as a separate architecture
change: necessary web, local-file, OCR, and browser access must survive, while
private intake and attacker-controlled content must not share an unrestricted
outbound execution context. Do not commit the current tree unless the user
explicitly reverses the request.
