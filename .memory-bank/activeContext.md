---
status: current
last-verified: 2026-09-07
owner: software-engineer
source: current task evidence
---

# Active context

## Current focus

The saved plan-review corrections are integrated on `main`, preserving both
existing hardening rounds. The independent review covered `3d115a3` and found
no Blocker, one Major, six Minor, and two Nit findings. PR-01 through PR-09 are
resolved by implementation and regression evidence; the combined corrections
have not received another independent review. `assessment-log.md` retains the
original findings. Remote mutation and paid model evaluations remain off.

- Section anchors support indented ATX and setext headings and preserve literal
  trailing hashes. `headings.mjs` checks parser tokens against section levels,
  text, and source lines at authorization and every read, including the locked
  precondition and post-commit observation. Unsupported structures fail closed.
  The dependency-free splitter retains CommonMark fences and globally unique
  keys, including duplicate headings colliding with numbered siblings.
- Per-launch cookie names allow concurrent loopback servers; authorities follow
  the bound IPv4 or IPv6 address. Mutation gates require Host, exact Origin,
  JSON content type, session, CSRF, and valid Fetch Metadata when supplied.
- Feedback reads and serialized writes share a 2 MiB bound and strict hashes
  and authority validation. Refused files remain intact. Locks name their owner,
  refuse live owners, reclaim only provably dead owners non-recursively, and
  reject a write after ownership loss. Source revisions are rechecked inside
  the lock and after commit; a last-window change reports `superseded`.
- Immutable asset snapshots replace request-time streams. Stale drafts and
  pending verdict notes survive refusals; generation-guarded loads cannot render
  under another selection. CLI bind failures and verdict actions without a
  loaded revision have explicit diagnostics. Unused deletion was removed.

Combined evidence: Windows build/test 1,774 passed, zero failed, 116 skipped,
90.72% coverage; Node 248 passed on Windows and Linux Node 22; dependency-free
unit suite 157 passed; Edge desktop/mobile 42 passed; focused Pester 43 passed.
Syntax checks cover 32 files; AST, PSScriptAnalyzer, and guide markdownlint are
clean. The controller inspected screenshots and reran 42 focused regressions.
The queued-write regression now observes a lock attempt: a disposable mutation
matrix proves the old timing-based test could miss a removed in-lock check.

The tool remains absent from `CustomizationDirectory` and `source/`; npm
dependencies stay opt-in. The repository gate runs dependency-free Node tests
when available and never installs npm packages. Browser verdicts remain
`local-http-feedback` under `chat-sign-off-required`, never Decision records,
handoffs, or commands. A state root inside `.memory-bank/decisions` is refused.
Ancestor reparse checks, raw-HTML disabling, DOMPurify, strict Mermaid, no image
loads, and restrictive CSP remain in place; the guide and threat model own detail.

Nested blockquote/list headings and parser disagreements are intentionally
unreviewable, not silently mis-anchored; all 213 tracked Markdown files passed
the corpus check. Same-user filesystem races are detected, not eliminated.
macOS, current Linux PowerShell gates, live OneDrive, performance benchmarks,
and paid model evaluations remain unverified. A fresh `review: on` is recommended
for the combined HTTP, persistence, and approval boundaries.

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
- **Footprint reporting (task 01).** `Get-CopilotAtelierFootprint` reports
  potential automatic loading contingent on discovery, never "always loaded",
  guards every mapped root, and fails closed on ambiguous frontmatter.
- **CI run 34061934611 and the deployment review.** Fixed on `main` at
  `35fa926`; M1-M5 and L1-L6 landed at `5acb69d` with zero Blocker/Major
  findings; the per-ID ledger stays in `assessment-log.md`.
- **Agent Plugins 1.0.** VS Code's documentation confirms all four Copilot-only
  component paths under `com.github.copilot/`, so Decision 0023's layout is
  documented upstream; only the accepted cross-type-link mismatch remains.

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

Integration and validation are complete. Keep publication and remote mutation
behind a separate explicit request. The original review is not approval of the
combined corrections; a fresh review remains available on request.
