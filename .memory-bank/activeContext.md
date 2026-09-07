---
status: current
last-verified: 2026-09-07
owner: software-engineer
source: current task evidence
---

# Active context

## Current focus

Completed the seven-task series on `main`. Tasks 01-06 are committed at
`c0c7166`, `8e40815`, `09416a4`, `bb66d41`, `e04345e`, and `288a4ad`; the
records commit is `555c260`. The earlier CI fix is `35fa926`. The user requested
the dependency ignore rule, completion of task 07, and final integration.
Remote mutation, paid model evaluations, and independent review remain off.

Task 07 (`tools/plan-review`) is committed in `3b04d46`. Integration fixed npm
commands, ambiguous duplicate-heading anchors, linked feedback roots, missing
launch-time input checks, invalid UTF-8, mobile stale-status overflow, document
selection, unsent drafts, connection failures, and stale verdict-dialog identity.
Final evidence: Windows combined gate 1,810 passed/67 skips, 90.72% coverage;
Linux Unit/QA gate 1,707 passed/114 skips/56 tag exclusions, 90.42% coverage.
Node tests: 133 passed on each OS; Edge desktop/mobile: 30 passed. All have
zero failures. Focused repository checks passed 158; native AST, ScriptAnalyzer,
syntax, and dependency audit checks passed. Memory budgets are within limits.
Existing simulated-backend and near-budget warnings remain. macOS, live
OneDrive, and paid model-backed evaluation are not verified by these runs.

**It is opt-in in the strong sense.** It is absent from `CustomizationDirectory`
so the built module never carries it, no file under `source/` mentions it, and
its dependencies are installed by hand in `tools/plan-review`. The repository
gate runs `tests/PlanReview.Tests.ps1`, which asserts the packaging isolation
and the trust-boundary invariants from the source and executes the
dependency-free half of the Node suite when `node` is present — it never runs
`npm install`, so `npm` is not imposed on an ordinary install.

**A browser verdict is feedback, not sign-off.** An HTTP request proves a
content hash was posted, not who posted it. Verdicts are stored as
`authority: "local-http-feedback"` under
`approvalAuthority: "chat-sign-off-required"`, the header is repeated on the
response and shown above the document, and there is no endpoint that writes a
Decision record, fires a handoff, or runs a command. A `--state` root inside
`.memory-bank/decisions` is refused at launch. The architect agent body points
at the tool and says it does not replace the sign-off; its frontmatter is
untouched, so the task-06 strict parser still accepts it.

Identity is content. A revision is the SHA-256 of the bytes; a section key is
its heading slug plus an occurrence ordinal. A comment reloads as *current*,
*revised*, or *orphaned*, and an orphaned comment is listed separately and never
re-anchored by heading text. A verdict whose hash no longer matches is reported
as invalidated, and a post against a stale hash is refused with `409`. Loopback
is a reachability reduction, not authorization. A non-loopback bind is
refused; every mutation needs Host, exact Origin, `Sec-Fetch-Site`, JSON content
type, the per-launch session cookie, and a matching CSRF token, so a cookie from
an earlier launch fails against the next one even on the same store. Documents
are authorized at launch and addressed by an opaque id; paths are realpath
checked with ancestor reparse rejection at read time, not only at launch. Raw
HTML is off at `markdown-it` with DOMPurify after it, images are never fetched,
Mermaid runs `securityLevel: 'strict'`, and the CSP is `default-src 'none'` with
`script-src 'self'`. Earlier task-07 results were 124 Node tests and 22 browser
checks; they are historical evidence, not the final integration results.
Recommend `review: on` for the local HTTP, persistence, and approval boundaries.

## Previous focus: client-specific adapters

Task 06 is committed in `288a4ad`. VS Code profiles remain the source;
the adapter rewrites strictly parsed frontmatter through explicit capability
mappings, rejects unsupported grants, and preserves the body bytes. CLI
`review: on` and `cycle: full` are refused in the generated variant. Neither
client is runtime verified; authored cases remain in `docs/client-adapter-evals.md`.
Generated variants are undeployed build artifacts under `output/clientAdapters`.
The exporter preflights every path, rejects linked ancestors and unowned or
modified collisions, and records SHA-256 ownership in schema 2. Round 2 passed
121 focused regressions; the changelog retains earlier correction evidence.

## Previous focus: changed-file validation

Task 05 added the `changed-file-validation` Skill: an opt-in, bounded validation
pass over one work batch, collected manually because no documented hook event
reports an edit contract this implementation has verified. Validators read an
isolated snapshot, and a receipt binds to those bytes plus a plan identity
hashing the linter entry point and the shipped checker code. Parse and
PSScriptAnalyzer run in an owned child worker with a wall clock and inline
settings. `Markdown.NativeStructure` is `coverage=partial` and never stands in
for markdownlint. 12 regressions red, then 85/0/0.

## Previous focus: Skill health report

Task 04 added read-only `Get-CopilotAtelierSkillHealth` plus private
`Import-CopilotAtelierSkillObservation`, `Measure-CopilotAtelierSkillHealth`,
and the shared `Get-CopilotAtelierBoundedFile` enumerator. The client-event
contract is **verified, not asserted**: each documented hook event is checked
against the deployed authoring Instruction, and the report publishes *no
reliable Skill-activation contract verified for this implementation*. Missing
telemetry is unknown, not zero. Run output counts only through a validated
provenance sidecar, a graded summary only when it reconciles exactly with
`assertion_results`, and disagreeing copies surface as `ConflictingRun`. Red 29
then 81/0; canonical `build, test` 1492 passed, 0 failed.

## Previous focus: reviewed learning inbox

Task 03 added `reviewed-learning-inbox`: an on-demand, project-scoped review
queue whose store at `.memory-bank/learning-inbox/candidates.json` sits outside
the routed base and the deployed tree. A selected artifact is an untrusted
observation, never a directive; one content rule runs at intake and again at
promotion, which is append-only and hash-gated on `-Approve` plus the preview
SHA-256. Red 18 of 62 then 62/0/0.

## Previous focuses

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
  `35fa926`; M1-M5 and L1-L6 landed at `5acb69d` with zero Blocker/Major findings;
  the per-ID ledger stays in `assessment-log.md`. macOS and live OneDrive remain
  unverified locally.
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

- **Medium:** under Windows PowerShell 5.1, `Get-FileHash` is unresolvable
  inside a script invoked from a Pester `It`, though it resolves in a bare `It`
  and in a plain 5.1 child. The untouched `MemoryBankRoleMigration` suite fails
  identically, so it is a harness anomaly, not a code defect.
- **Deployment review:** M1-M5 and L1-L6 are implemented and independently
    approved on the verified scope; macOS and live cloud-sync execution remain
    disclosed, not waived.
- **High:** `software-engineer-contoso` claims no egress while retaining an
  unrestricted terminal and mandating a generic `security-reviewer` delegate
  with web, GitHub, MCP, and terminal tools. Eleven older agents likewise
  combine workspace and private-data access, untrusted web content, arbitrary
  execution, and broad MCP access. Prose is not enforced containment, especially
  on native Windows without terminal sandboxing; replace copied omnibus tool
  lists with role-specific least-privilege surfaces.
- **Medium:** Security Reviewer and Technical Writer delegate research to the
    full `research-analyst` profile, and twelve agents expose `browser` while
    only Software Engineer carries an explicit ephemeral-loopback,
    shared-authentication, and user-confirmation contract.
- **Major:** `career-coach` (35,672 chars), `research-analyst` (43,376),
  `security-reviewer` (43,772), and `technical-writer` (35,018) exceed GitHub's
  30,000-character Custom agent prompt limit. The new test prevents growth; the
  separate Session handoff owns the refactor below the limit.
- **Major:** every profile omits `target` but declares a VS Code model-priority
  array and mostly VS Code-qualified tool IDs. Copilot CLI documents one model
  string plus CLI tool names; product-specific profiles or a shared compatible
  subset remain open.
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
and no precision floor is set. `WindowsAccessControl` slots 1 and 2 use the
older ink-variant reading of dark/light; `brand-logo-system` integration was
measured on one project only; and the `skill-creator` description edit remains
unproven — train reached 100 % while validation fell.

## Next step

The seven-task implementation and integration are complete. Keep publication
and any remote mutation behind a separate explicit request. Independent review
of the new local HTTP, persistence, and approval boundaries remains recommended.
