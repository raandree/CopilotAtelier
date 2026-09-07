---
status: current
last-verified: 2026-09-07
owner: software-engineer
source: current task evidence
---

# Active context

## Current focus

Client-specific adapters (task 06, correction round 2). Read-only
`Get-CopilotAtelierClientAdapter` over private
`Get-CopilotAtelierClientContract`, `ConvertFrom-`/`ConvertTo-`
`CopilotAtelierAgentFrontmatter`, `ConvertTo-CopilotAtelierClientAgent`,
`Export-CopilotAtelierClientAdapterArtifact`, plus the build task.

**Discovery is not parity, and the mismatch is specific.** The shipped profiles
are authored in the VS Code shape. The published custom agents configuration the
Copilot CLI follows documents one model string, a closed set of tool aliases,
and no subagent allow-list, handoff, or argument hint — and it *ignores* an
unrecognized tool name. `software-engineer` declares 45 tool identifiers; 5 map.
Scope is VS Code and the CLI; no cloud client is claimed.

The VS Code files stay the only source; only frontmatter is rewritten. Four
rules are tests, not prose: every mapping is explicit and an unmapped identifier
is an error; frontmatter is a strict YAML subset that rejects an unknown or
duplicate field rather than dropping it; **an `execute/` prefix is a namespace,
not execution authority** — only `execute/runInTerminal` may reach the execute
alias, so `execute/getTerminalOutput`, `runTests`, task runners, and `useMcp`
stay unsupported; and a restriction that cannot be expressed removes what it
guards, so the variant loses the `agent` tool. Every other mapping stays inside
its capability class. A mandatory capability or workflow that cannot be provided
fails the composition and emits nothing.

**`review: on` and `cycle: full` are refused, not degraded.** The composed file
carries an additive limitation section, between explicit markers with the shared
body's SHA-256 in the end marker, telling the agent to refuse those modes and
return to VS Code. The body stays byte-identical and last.

Neither client is runtime verified: no receipt is bound to an artifact, so both
are `StructurallyChecked`. The VS Code 1.136.1 observation is kept as historical
source-profile evidence. The CLI is **not installed**;
`docs/client-adapter-evals.md` carries the authored, unexecuted cases.

Variants land in `output/clientAdapters/<client>/` and are **never deployed**.
The build task owns that directory through a manifest and removes only what it
generated; an unowned directory, a reserved build name, a non-child path, or a
reparse point is refused rather than deleted.

**Round 2 hardened the exporter, and only the exporter.** Every path component —
output root, artifact directory, manifest, client directory, generated file,
destination — goes through `Assert-CopilotAtelierRegularPath`, because a link
*between* root and leaf redirects a delete just as well as one at either end.
The whole operation is validated before the first mutation, so a late unsafe
manifest entry no longer arrives after a valid earlier one was already deleted.
Ownership is proved by content: schema 2 records a SHA-256 per generated file,
so an edited generated file, an unowned destination collision — identical
content included — and a names-only `schema 1` manifest are all refused.

Red 46/103 before round 1, then 103/103. Round 2 red 15/121, then 121/121 with
no skips (elevated, so the link cases ran). Uncommitted; `review: off` —
recommend `review: on` for the permission mapping and the ownership model.

## Previous focus: changed-file validation

Task 05 added the `changed-file-validation` Skill: an opt-in, bounded validation
pass over one work batch, collected manually because no documented hook event
reports an edit contract this implementation has verified. Validators read an
isolated snapshot under a generated name, and a receipt binds to those bytes
plus a plan identity hashing the linter entry point and the shipped checker
code. Parse and PSScriptAnalyzer run in an owned child worker with a wall clock
and inline settings. `Markdown.NativeStructure` is `coverage=partial` and never
stands in for markdownlint. 12 regressions red, then 85/0/0.

## Previous focus: Skill health report

Task 04 added read-only `Get-CopilotAtelierSkillHealth` plus private
`Import-CopilotAtelierSkillObservation`, `Measure-CopilotAtelierSkillHealth`,
and the shared `Get-CopilotAtelierBoundedFile` enumerator.

The client-event contract is **verified, not asserted**: each of the eight
documented hook events is checked against the deployed authoring Instruction,
and the report publishes `VerificationState` and `VerificationScope` — *no
reliable Skill-activation contract verified for this implementation*. No capture
is implemented, it is off by default, and missing telemetry is unknown, not
zero. Evaluation evidence is read in the shapes `agent-evals` defines: run
output counts only through a validated provenance sidecar, a graded summary only
when it reconciles exactly with the bounded verdicts in `assertion_results`, and
disagreeing copies surface as `ConflictingRun`. `RetirementReview` needs an
explicit `coverage` declaration and is never raised for a mandatory Skill.
Focused suites red 29 then green 81/0; canonical `build, test` green at 1492
passed, 0 failed (`%TEMP%\ca-sh2-final2.log`).

## Previous focus: reviewed learning inbox

Task 03 added `reviewed-learning-inbox`: an on-demand, project-scoped review
queue whose store at `.memory-bank/learning-inbox/candidates.json` sits outside
the routed base, every Skill description, and the deployed tree. A selected
artifact is an untrusted observation, never a directive; one content rule runs
at intake and again at promotion. Promotion is append-only and hash-gated —
`-Approve` plus the preview SHA-256 — and round 1 added parent-chain reparse
guards, evidence binding, a byte-preserving exclusive append, an atomic locked
store, and verified-block repeat handling. Red 18 of 62 then 62/0/0.

## Previous focuses

- **Installation profiles (task 02).** `-InstallationProfile` (`complete`
  default, `engineering`, `research`, `document-processing`) plus
  `-IncludeSkill`/`-ExcludeSkill` on Install, Update, and Setup, with
  `Get-CopilotAtelierProfile` and an `InstallationProfile` field on the
  `Test-CopilotAtelier` result. Only Skills are selectable; `memory-bank`,
  `long-running-job-monitor`, and `agent-security-review` are mandatory because
  deployed Instructions and shipped agents load them by name. The selection is
  an additive optional `Selection` field inside schema 1, omitted for a complete
  installation, and the plan filters whole top-level folders.
- **Footprint reporting (task 01).** `Get-CopilotAtelierFootprint` reports
  potential automatic loading contingent on discovery, never "always loaded",
  guards every mapped root, and fails closed on ambiguous frontmatter. The
  shared `Get-CopilotAtelierDirectoryMap` keeps installer and report aligned.
- **CI run 34061934611 and the deployment review.** Fixed on `main` at
  `5acb69d`, where M1-M5 and L1-L6 also landed with zero Blocker/Major findings;
  the per-ID ledger stays in `assessment-log.md`. Windows 1,266 passed, Linux
  1,172, 5.1 focused 120; macOS and live OneDrive remain unverified locally.
- **Agent Plugins 1.0.** VS Code's documentation confirms all four Copilot-only
  component paths under `com.github.copilot/`, so Decision 0023's layout is
  documented upstream; only the accepted cross-type-link mismatch remains.

## Environment hazard — scripted bulk writes corrupt file content

Two bulk PowerShell read-modify-write passes over this working tree replaced
whole file contents with a monoalphabetic substitution cipher (`instructions`
→ `nnkteuotnonk`, `applyTo` → `aeelyTo`), 129 files each time. Both were caught
and restored from git; no corruption reached a commit. It is asynchronous: the
script's own byte-exact read-back passed for all 175 files and `git diff` showed
it afterwards, so a verify-after-write loop cannot detect it. Until the cause is
found, edit through the editor tooling and treat any scripted bulk rewrite as
unsafe; `git grep -l -e nnkteuotnon -e aeelyTo` detects it.

## Blocked, not deferred

ShellPilot and `Invoke-ShpBatch` are absent here, so `-Mode Execute` is
unavailable for both eval harnesses. The 75 prepared route-selection prompts
cannot be answered and the authored trigger-query sets cannot be swept, so the
baselined Skills stay unmeasured for discovery. Both need ShellPilot plus a paid
model backend and an explicit go-ahead.

## Open findings

- **Medium:** under Windows PowerShell 5.1, `Get-FileHash` is unresolvable
  inside a script invoked from a Pester `It`, though it resolves in a bare `It`
  and in a plain 5.1 child. The untouched `MemoryBankRoleMigration` suite fails
  identically, so it is a harness anomaly, not a code defect.
- **Deployment review:** M1-M5 and L1-L6 are implemented and independently
  approved on the verified scope. macOS and live cloud-sync execution remain
  disclosed, not waived.
- **High:** `software-engineer-contoso` claims no egress while retaining an
  unrestricted terminal and mandating a generic `security-reviewer` delegate
  with web, GitHub, MCP, and terminal tools. Eleven older agents likewise
  combine workspace and private-data access, untrusted web content, arbitrary
  execution, and broad MCP access. Prose is not enforced containment, especially
  on native Windows without terminal sandboxing; replace copied omnibus tool
  lists with role-specific least-privilege surfaces.
- **Medium:** Security Reviewer and Technical Writer delegate research to the
  full `research-analyst` profile (edit, terminal, browser, GitHub, MCP), and
  twelve agents expose `browser` while only Software Engineer carries an
  explicit ephemeral-loopback, shared-authentication, and user-confirmation
  contract. Both need narrower role-specific surfaces.
- **Major:** `career-coach` (35,672 chars), `research-analyst` (43,376),
  `security-reviewer` (43,772), and `technical-writer` (35,018) exceed GitHub's
  30,000-character Custom agent prompt limit. The new test prevents growth; the
  separate Session handoff owns the refactor below the limit.
- **Major:** every profile omits `target` but declares a VS Code model-priority
  array and mostly VS Code-qualified tool IDs. Copilot CLI documents one model
  string plus CLI tool names such as `view`, `edit`, `powershell`, `grep`, and
  `task`; product-specific profiles or a shared compatible subset remain open.
- **Medium:** no executed agent behavioral eval set exists. The semantic tests
  catch structural regressions, but no live capability comparison was run.
- **Low:** three test files parse agent frontmatter with independent regular
  expressions; one shared `powershell-yaml` parser plus malformed nested
  fixtures would reduce false greens.

## Carried forward

`Invoke-MemoryBankRouteSelectionEval.ps1` has offline `Prepare` and `Grade`
modes covering prompt isolation, label leakage, fallback, strict shape,
reliability aggregation, and failure accounting. The first stage infers routes
and fallback only; the resolver still receives human labels. Context cost,
latency, and answer quality under routed versus full loading remain unmeasured,
and no precision floor is set, so `Passed = True` at low precision is not a
failing build. `WindowsAccessControl` slots 1 and 2 use the older ink-variant
reading of dark/light, so two sets in one shared library disagree on "dark
mode"; `brand-logo-system` integration was measured on one project only; and the
`skill-creator` description edit remains unproven — train reached 100 % while
validation fell, which is the overfitting signal.

## Next step

Leave independent review, publication, and any remote mutation to an explicit
user request.
