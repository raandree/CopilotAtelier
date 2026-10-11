---
status: current
last-verified: 2026-10-11
owner: software-engineer
source: current task evidence
---

# Active context

## Current focus

Prompts 03 (`ai/session-lessons`, six commits) and 08 (`ai/session-clock-path`,
three commits) are merged into local `main`, which is not pushed; the full gate
passed with 2,620 tests. The merge ran in a scratch clone because a parallel
chat held this working tree on `ai/calibration-phase-2`, which stays out of
`main` until prompt 07 hands over its pull request.

The session lessons: the detached Pester guards reject a result other than
`Passed`, both Pester guides explain truthiness, `agent-security-review` treats
hook context as data, `Wait-DetachedResult.ps1` waits a bounded time on a
detached run, and the hooks README names where each host records hook evidence.
The shared Instruction wording was chosen under a no-questions delegation, so an
expert review stays recommended.

The Post-flight elapsed line is pinned to its own chat's clock:
`Add-SessionContext.ps1` hands the agent `& '<reader>' -Path '<clock>'`, and the
reader prefers the session `COPILOT_AGENT_SESSION_ID` names. Decision 0024 holds
the Prox1 evidence and what stays open: a host that sends no `session_id`, a
chat after a compaction on a host without the variable, and VS Code Local and a
new VS Code agent-host chat, not yet seen live.

## Previous focuses

- **Hook deny reason and the resume clock (prompt 06, #28 to #30).** The bundled
  Copilot SDK runtime drops a PascalCase deny that also carries
  `hookSpecificOutput`, so the guard prints the top-level pair alone;
  `tests/HookSdkRuntime.Tests.ps1` asserts the reason inside the real runtime
  (Decision 0016). A resumed chat keeps its clock. Merged into `main`, deployed
  2026-10-04; A2 and B2 then passed in new chats.
- **Contributor calibration Phase 1 (#27, `7a48abe`).** On `main`; Phase 2 goes to
  `software-architect` through the Session handoff. The private behavior eval
  scored 52.1% without the Instruction and 100% with it, and arms are compared
  only when run concurrently.
- **Hook guard follow-ups (prompts 02, 05, 06; `d8cc6f5` to `fea564f`).** Ten
  reviews ended in an approval. The guard decides within about five seconds
  (1 MB parse, 20,000-field walk, 4 MB block) and errs toward blocking; the
  override cannot reach a hook from an agent terminal. Deployed 2026-10-02.
- **Version rules (`31042ea`, `bd60b7a`, on `main`).** Only the Conventional
  Commit type in the subject, a `BREAKING CHANGE:` line, or `+semver:` raises
  the version; review text such as "Major issues." no longer does.
- **Runtime tool names (`a592832`, on `main`).** Every Custom agent pairs its
  VS Code tool names with runtime names, so agent-host sessions keep `web_fetch`,
  `grep`, `glob`, `ask_user`, browser, and session tools (Decision 0026,
  github/copilot-cli#4594). Red 28 then green; offline probe 16 of 16 agents.
- **Plan-review findings PR-01 to PR-09.** Resolved in the integrated tree with
  a mandatory heading verifier; the guide, threat model, and `assessment-log.md`
  keep the contracts. Browser feedback never grants chat sign-off. The
  cross-platform artifact transfer stayed unproven, and `review: on` remains
  recommended for the combined HTTP and persistence corrections.
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

On 2026-09-08 ShellPilot and `Invoke-ShpBatch` are installed, and
`Test-ShpCiReadiness -NonInteractive` reports ready with the existing Copilot
backend. The wiki case used it with candidate-scoped read-only tools and no
browsing, terminal, user tools, or MCP. Its ten paired requests plus one setup
pilot made no Skill loads, writes, or shell calls. Waza and its native extension
are absent; the earlier Copilot CLI check also reported it unavailable.
No graded body comparison exists. The bundled matcher aggregates independent
reviewer verdicts, not investigative actions or candidate-authored PASS text.
Earlier route-selection and trigger-query sets remain unmeasured.

## Open findings

- **High:** `software-engineer-contoso` claims no egress while retaining an
  unrestricted terminal and mandating a generic `security-reviewer` delegate
  with web, GitHub, MCP, and terminal tools. In agent-host sessions the host
  drops `agents:`, so its delegation can reach any agent, and open agents can
  read its session through `get_session_context` (decision 0026). Eleven older
  agents likewise combine workspace and private-data access, untrusted web
  content, arbitrary execution, and broad MCP access. Prose is not enforced
  containment, especially on native Windows without terminal sandboxing;
  replace copied omnibus tool lists with role-specific least-privilege surfaces.
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

1. The owner pushes `main` and deletes `origin/ai/session-clock-path` from their
   own terminal; agents cannot push. Prompt 07 then merges `origin/main` into
   `ai/calibration-phase-2` and resolves the conflicts in `Add-SessionContext.ps1`,
   `tests/Hooks.Tests.ps1`, `CHANGELOG.md`, the hooks README, and these two files.
2. Confirm the clock pin live in a new VS Code chat (Decision 0024 lists the cases).

Still open from earlier work: the live agent-host `#web/fetch` check, and the
duplicate Instruction loading in Copilot SDK chats (Open work in `progress.md`).
