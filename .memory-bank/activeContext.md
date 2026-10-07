---
status: current
last-verified: 2026-10-06
owner: software-engineer
source: current task evidence
---

# Active context

## Current focus

Decision 0028 Amendment 1 (A1 to A8) is implemented on `ai/calibration-phase-2`
(`b7e6502`, pushed by the owner). On 2026-10-06 an independent
`security-reviewer` pass found no Critical, High, or Medium issue; its five Low
findings and six test gaps are fixed test-first (hash-gated registration
delete, linear SessionStart pre-check inside the step cap, bounded registration
reads, Uninstall holding the profile lock through its removal, link-aware
working-tree guard). The two reported `Calibration.Delivery` cells are measured
in the SDK runtime and Copilot CLI. Criterion 22's manual compactions ran on
Prox1 in `C:\Users\install\Documents\calibration-check` (branch deployed): the
CLI passes; VS Code Local cannot show it, as Copilot Chat 0.68.0 runs no
PreCompact hook for a manual or a background compaction. VS Code's agent host
re-sent the levels after three automatic compactions, and the model saw them.
Criterion 21's unpaid groundwork sits in the private kit: the runner's `arms`
and `profile` fields and `Preview` mode, `evals-phase2.json` (8 draft cases),
and `evals-phase1-guard.json`. Criterion 20 is not met and is back with
`software-architect`: one cell over Budget and within Fail on each machine
(Prox1 VS Code SessionStart, RAANDREE3 SDK PostToolUse), and TBD-5 answered no,
because RAANDREE3's VS Code launch is 2.4 times Prox1's and a hook costs 2 s
there (Decision 0028, *Returned to software-architect, second round*).

## Previous focuses

- **Amendment 1 rulings (`b72ac98`).** `software-architect` and the owner ruled
  A1 to A8 on the five returned questions and seven interpretations; latency
  counts in no-op hook launches over 20 paired replicates.
- **Phase 2 implementation (`dc6c26a` to `279c07e`).** Built test-first; the
  SDK delivery probe passes in both runtimes. The latency Meter failed both
  budgets on Prox1 (+349 to +380 ms p95 SessionStart in the VS Code spawn), and
  five results went back to `software-architect`; ruled in Amendment 1.
- **Phase 2 design (Decision 0028, `b568c8c`).** Signed off 2026-10-06 after 26
  questions; the per-call PostToolUse cost applies only to machines with an
  active Contributor profile.
- **Prompt 06 close-out (#29 `9b6a341`, #30 `25d8233`).** CI run 112 published
  `6.1.0-preview0003`. The SDK runtime drops a PascalCase `preToolUse` deny that
  carries `hookSpecificOutput` (Decision 0016); `tests/HookSdkRuntime.Tests.ps1`
  probes the runtime without a model. Phase 1 (#27, `7a48abe`) scored 52.1%
  without the Instruction and 100% with it in the private behavior eval.
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
- **Plugin manifest rollover (`6367e68`, on `main`).** `Update_PluginManifest_Version`
  rewrites `plugin.json` before `Create_ChangeLog_GitHub_PR`, so a rollover no
  longer fails its own manifest guard (CI run 36549550887).
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
- **Tasks 02 to 04.** Installation profiles (`-InstallationProfile`,
  `-IncludeSkill`/`-ExcludeSkill`; mandatory Skills stay), the reviewed
  learning inbox (append-only, hash-gated promotion), and the read-only Skill
  health report (missing telemetry is unknown, not zero); see `CHANGELOG.md`.

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

1. `software-architect` rules on the second-round return of Decision 0028
   (five questions): the launch unit (TBD-5), criterion 20's two over-Budget
   cells, the 2 s per-call cost in VS Code on RAANDREE3, VS Code Local running
   no PreCompact for a manual or background compaction, and persistence cases
   that no machine's history can supply. The 70,000-token threshold in the
   scratch workspace caused a compaction loop (2,001 requests, 99 background
   summarizations) and is removed; never set it below about 1.3 times the base
   prompt. Redeploy `main` on Prox1 with `Setup-CopilotSettings.ps1` once the
   owner closes the checks. For criterion 21, RAANDREE3's full history still
   needs a run of the extended finder; then build the persistence cases as
   ruled, add grader fixtures, define the offer and safety groups (the
   Decision names them only), and get the owner's approval and budget before
   any paid run.
2. The user runs prompt 04 on the hand-patched machine and deletes the merged
   remote branch `copilot/dgthths`; agents cannot push.
3. Optional: report upstream that the GitHub hooks reference describes the
   exit-2 stdout merge without its `hookSpecificOutput` condition.

Still open from earlier work: the live agent-host `#web/fetch` check, and the
duplicate Instruction loading in Copilot SDK chats (Open work in `progress.md`).
