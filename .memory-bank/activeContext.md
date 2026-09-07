---
status: current
last-verified: 2026-09-07
owner: software-engineer
source: current task evidence
---

# Active context

## Current focus

GitHub Actions repair `0367ce3` is committed and pushed on `main`, as explicitly
requested. Run [#76](https://github.com/raandree/CopilotAtelier/actions/runs/34163989373)
completed successfully at 2026-09-07 21:54 UTC: packaging, Linux, Windows,
macOS, and deployment all passed. The full development cycle and independent
review stayed off; no paid evaluations were run.

- The uploaded `output` artifact omitted
  `.copilot-atelier-adapter-manifest.json`. All three test jobs failed ownership
  checks. Enable `include-hidden-files` only on the scoped `output/` upload;
  the rebuilt output contains no other hidden file. The workflow regression
  failed with the option absent, then passed: 5 tests, zero failures.
- Windows used the `RUNNER~1` temp alias; macOS used the `/var` symlink.
  Canonicalize the five failing filesystem suites' fixture roots with
  `realpathSync.native`. Production containment and link rejection are unchanged.
  A new linked-temp regression reproduces the failures on Windows and passes
  after the repair. Clear inherited `NODE_TEST_CONTEXT` in the nested runner
  and require a nonzero test count to prevent a skipped run returning success.
- Node unit tests: 165 passed, zero failed or skipped. PowerShell AST and
  PSScriptAnalyzer checks pass. Clean-checkout `build,test`: 1,777 passed,
  zero failed, 116 skipped, 90.72% coverage using the failed run's dependencies
  and exact module version. Final Memory Bank/workflow checks: 12 passed.
  Markdown lint passed. The known simulated-backend warning remains.
- The actual GitHub output artifact contains the schema-2 ownership manifest;
  its generated file's SHA-256 matches. Existing setup-uv cache-glob warnings
  remain non-fatal. No production path or security guard was changed.

## Previous plan-review work

PR-01 through PR-09 and the CONDITIONAL review's heading-verifier coverage gap
are resolved in the integrated tree. The verifier is mandatory and every server
read is checked by the dependency-free gate; excessive JSON nesting is refused.
Per-launch sessions, bounded state, ownership locks, parser-verified anchors,
source rechecks, immutable assets, and revision-scoped drafts remain intact.
The guide, threat model, and `assessment-log.md` retain the full contracts and
original findings. Browser feedback never grants chat sign-off authority.

Earlier local evidence: Windows gate 1,775/0/116 at 90.72% coverage; Node 255;
Edge 42. This did not prove the failing cross-platform artifact transfer.
No fresh independent review of the combined HTTP and persistence corrections
is claimed; `review: on` remains recommended for those earlier changes.

## Previous focuses

- **Client-specific adapters (task 06, `288a4ad`).** VS Code profiles remain the
  source; the adapter rewrites strictly parsed frontmatter through explicit
  capability mappings, rejects unsupported grants, and preserves the body bytes.
  CLI `review: on` and `cycle: full` are refused in the generated variant.
  Neither client is runtime verified; authored cases sit in
  `docs/client-adapter-evals.md`. Generated variants are undeployed artifacts
  under `output/clientAdapters`, owned through a schema 2 manifest recording
  SHA-256 that refuses an unowned or modified collision. Round 2: 121 passed.
- **Changed-file validation (task 05).** An opt-in, bounded validation pass over
  one work batch, collected manually because no documented hook event reports an
  edit contract this implementation has verified. Validators read an isolated
  snapshot, and a receipt binds to those bytes plus a plan identity hashing the
  linter entry point and the shipped checker code. Parse and PSScriptAnalyzer
  run in an owned child worker. `Markdown.NativeStructure` is `coverage=partial`
  and never stands in for markdownlint. 12 red, then 85/0/0.
- **Skill health report (task 04).** Read-only `Get-CopilotAtelierSkillHealth`
  with private import and measure helpers. The client-event contract is
  verified, not asserted, and the report publishes *no reliable Skill-activation
  contract verified for this implementation*. Missing telemetry is unknown, not
  zero: output counts only through a validated provenance sidecar, and
  disagreeing copies surface as `ConflictingRun`. Red 29 then 81/0.
- **Reviewed learning inbox (task 03).** An on-demand, project-scoped review
  queue whose store sits outside the routed base and the deployed tree. A
  selected artifact is an untrusted observation, never a directive; one content
  rule runs at intake and again at promotion, which is append-only and hash-gated
  on `-Approve` plus the preview SHA-256. Red 18 of 62 then 62/0/0.
- **Installation profiles (task 02).** `-InstallationProfile` plus
  `-IncludeSkill`/`-ExcludeSkill` on Install, Update, and Setup, with
  `Get-CopilotAtelierProfile`. Only Skills are selectable; `memory-bank`,
  `long-running-job-monitor`, and `agent-security-review` are mandatory because
  deployed Instructions and shipped agents load them by name. The selection is
  an additive optional `Selection` field inside schema 1.
- **Footprint reporting (task 01), CI run 34061934611, and Agent Plugins 1.0.**
  `Get-CopilotAtelierFootprint` reports potential loading contingent on
  discovery, guards every mapped root, and fails closed on ambiguous
  frontmatter. The CI fix landed at `35fa926` and the deployment review's M1-M5
  and L1-L6 at `5acb69d` with zero Blocker or Major findings, per-ID detail in
  `assessment-log.md`. VS Code documents all four Copilot-only component paths
  under `com.github.copilot/`, so only the accepted cross-type-link mismatch
  remains open against Decision 0023.

## Environment hazard — scripted bulk writes corrupt file content

Two bulk PowerShell read-modify-write passes over this working tree replaced
whole file contents with a monoalphabetic substitution cipher (`instructions`
→ `nnkteuotnonk`, `applyTo` → `aeelyTo`), 129 files each time. Both were caught
and restored from git; no corruption reached a commit. It is asynchronous: the
script's own byte-exact read-back passed and `git diff` showed it afterwards, so
a verify-after-write loop cannot detect it. Edit through the editor tooling and
treat any scripted bulk rewrite as unsafe; `git grep -l -e nnkteuotnon -e
aeelyTo` detects it.

## Blocked, not deferred

ShellPilot and `Invoke-ShpBatch` are absent here, so `-Mode Execute` is
unavailable for both eval harnesses. The 75 prepared route-selection prompts
cannot be answered and the authored trigger-query sets cannot be swept. Both
need ShellPilot plus a paid model backend and an explicit go-ahead.

## Open findings

- **High:** `software-engineer-contoso` claims no egress while retaining an
  unrestricted terminal and mandating a generic `security-reviewer` delegate
  with web, GitHub, MCP, and terminal tools. Eleven older agents likewise
  combine workspace and private-data access, untrusted web content, arbitrary
  execution, and broad MCP access. Prose is not enforced containment, especially
  on native Windows without terminal sandboxing; replace copied omnibus tool
  lists with role-specific least-privilege surfaces.
- **Major:** `career-coach` (35,672 chars), `research-analyst` (43,376),
  `security-reviewer` (43,772), and `technical-writer` (35,018) exceed GitHub's
  30,000-character Custom agent prompt limit. The new test prevents growth; the
  separate Session handoff owns the refactor below the limit.
- **Major:** every profile omits `target` but declares a VS Code model-priority
  array and mostly VS Code-qualified tool IDs. Copilot CLI documents one model
  string plus CLI tool names; product-specific profiles or a shared compatible
  subset remain open.
- **Medium:** Security Reviewer and Technical Writer delegate research to the
  full `research-analyst` profile, and twelve agents expose `browser` while only
  Software Engineer carries an explicit ephemeral-loopback,
  shared-authentication, and user-confirmation contract.
- **Medium:** no executed agent behavioral eval set exists; the semantic tests
  catch structural regressions only. Under Windows PowerShell 5.1,
  `Get-FileHash` is unresolvable inside a script invoked from a Pester `It`,
  which the untouched `MemoryBankRoleMigration` suite reproduces — a harness
  anomaly, not a code defect.
- **Low:** three test files parse agent frontmatter with independent regular
  expressions; one shared `powershell-yaml` parser plus malformed nested
  fixtures would reduce false greens. The deployment review's M1-M5 and L1-L6
  are approved on the verified scope; macOS and live cloud sync stay disclosed.

## Carried forward

`Invoke-MemoryBankRouteSelectionEval.ps1` has offline `Prepare` and `Grade`
modes covering prompt isolation, label leakage, fallback, strict shape,
reliability aggregation, and failure accounting. The first stage infers routes
and fallback only; the resolver still receives human labels. Context cost,
latency, and answer quality under routed versus full loading remain unmeasured,
and no precision floor is set. `WindowsAccessControl` slots 1 and 2 use the
older ink-variant reading of dark/light; `brand-logo-system` integration was
measured on one project only; and the `skill-creator` description edit remains
unproven — train reached 100 % while validation fell.

## Next step

The requested repair and GitHub monitoring are complete. No build blocker
remains. The records-only follow-up commit skips CI to avoid another release;
all executable changes are covered by successful run #76 at `0367ce3`.
