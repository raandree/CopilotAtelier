---
status: current
last-verified: 2026-10-14
owner: software-engineer
source: current task evidence
---

# Active context

## Current focus

**P2, per-command remote approval, is built, reviewed, deployed, and accepted live on
`ai/hook-ask-remote-approval`, which is pull request #38 (opened by the owner on
2026-10-14); the owner pushes and merges.** A Grant marker the user types in their own
prompt (for example `[[allow-remote: git push, gh pr create]]`) makes the new
`UserPromptSubmit` hook `Add-RemoteGrant.ps1` record a short-lived, session-bound grant
that `Block-RemoteMutation.ps1` consumes: each named operation once (`x2` twice, a loop
or function needs `x20`, `--all`, `--tags`, and force pushes need `git push --force`),
until the next prompt or 15 minutes. The guard stays a hard block and never prints
`allow` (a hook `ask` is auto-approved in the Agent Host); `COPILOT_ATELIER_ALLOW_REMOTE`
is removed; `git reset --hard`, `git clean -f`, and `--no-verify` have no marker. The
same change fixes the string-literal false positive: the guard reads PowerShell as a
syntax tree and blanks a string only when everything it flows into treats it as data.
Seven independent review passes (three rejections, an approval with changes, two more
rejections the owner asked for, and a last bounded pass whose one finding was narrowed
and approved in a delta check) left no Blocker or Major; each finding is a test that
failed first. Decision 0016 and the Desktop `LEDGER.md` hold the evidence.

State: the final gate passed on the final tree (4,295 passed, 0 failed, 145 skipped,
90.84 % coverage) and `~/.copilot` is redeployed (257 files match the clone). **Live
acceptance passed on 2026-10-13** on the earlier guard (`B6DFAD99…`; the shipped one is
`E94968A0…`) in four new chats against a throwaway repository with a local bare remote
(the Agent Host, VS Code Local, Copilot CLI 1.0.96 as usual and under `--yolo`): no marker
meant a denial, a marker let one push run, auto-approval and `--yolo` did not lift the
block, and the bare repository held only the three branches that the marked prompts
pushed. The CLI's `COPILOT_ALLOW_ALL=1` does approve shell commands in the working folder.
Accepted residuals (hooks README, Residual risks): a forged grant file, a script written
and run in one command, a quote that PowerShell and a POSIX shell read differently, and a
push beside a loop (asks for x20).

**CI of #38 (run 38528625293, 2026-10-14):** Ubuntu and macOS passed; the Windows
PowerShell 7 job failed one test of 4,251 through a runner stall (the guard blocked as
designed but named the time limit). The two new suites now start the guard with
`-TimeLimitSecond 10`, as `Hooks.Tests.ps1` does for slow runners; the guard did not
change. One local commit, for the owner to push (CI then re-runs).

**Decision 0028 is merged and released** (#32 to #36; `main` is `e393875` at
`6.1.0-preview0009`). Criteria 1 to 20 and 22 to 30 are met; **criterion 21 is not
met**, worded as A39 fixes it, and TBD-2 is carried forward. M-04 (a `.familiarity`
name collision) stays open. #34 to #36 (P7, P3, P8) are not live until the owner
redeploys; P8's base, its missing external eval, and its single review are flagged
assumptions. Prompt 06c (`docs/SECURITY-REVIEW.md`) fixed 2 Blockers and 7 Majors in
the eval kit; the Desktop `LEDGER.md` lists what is open. Prompts 03 and 08 pin the
Post-flight elapsed line to its own chat's clock (Decision 0024 lists the cases not
yet seen live); the longer reader line leaves the calibration sentence fewer
characters, so one test in `tests/ContributorProfileHooks.Tests.ps1` squeezes at 1,400.

## Previous focuses

- **Prompts 04 to 06b and 05c (2026-10-09 to 2026-10-11).** The criterion 21 eval chain:
  Amendments 5 to 7, one fresh run (83.3 % at both Positions), and the record-only
  ruling that criterion 21 ships as not met (`progress.md`; the Decision's Confirmation).
- **Decision 0028, steps 7.1 to 7.5 (2026-10-06 to 2026-10-08).** The design
  (`b568c8c`, signed off after 26 questions), Amendments 1 to 4 (A1 to A19), the
  A12 backstop (`23a861a`), the hash-pinned frozen reference (`30fb3229…9c79`,
  A17), the latency levels (`3bef6b9`: `SessionStart.AddedLatency` Budget 2.0,
  `PostToolUse.CallLatency` Budget 0.75), and the VS Code Local backstop proved
  live (`b05efe3`). The RAANDREE3 `FailFast` is a .NET 10.0.6 runtime fault on
  PowerShell 7.6.1, not this repository's code. Evidence: the record's Confirmation.
- **Hook guard and deny reason (prompts 02 to 06, #28 to #30; `d8cc6f5` to `fea564f`).**
  Ten reviews ended in an approval. The guard decides within about five seconds and errs
  toward blocking. The bundled SDK runtime drops a PascalCase deny that also carries
  `hookSpecificOutput`, so the guard prints the top-level pair alone
  (`tests/HookSdkRuntime.Tests.ps1`; Decision 0016). Deployed 2026-10-04.
- **Contributor calibration Phases 1 and 2 (#27, `7a48abe`; Decision 0028).** On `main`.
  The private behavior eval scored 52.1% without the Instruction and 100% with it.
- **Runtime tool names (`a592832`, on `main`; Decision 0026).** Every Custom agent
  pairs its VS Code tool names with runtime names (github/copilot-cli#4594).
- **Plan-review findings PR-01 to PR-09.** Resolved in the integrated tree with a
  mandatory heading verifier; browser feedback never grants chat sign-off, the
  cross-platform artifact transfer stayed unproven, and `review: on` remains
  recommended for the combined HTTP and persistence corrections.

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

1. P2 is accepted live and committed locally. The owner pushes `ai/hook-ask-remote-approval`
   and opens the pull request; the PR title needs `feat(hooks):` and a line on the
   removed `COPILOT_ATELIER_ALLOW_REMOTE`. This machine's `~/.copilot` already carries the
   branch's scripts, so after CI and the merge the owner only needs item 2's redeploy to
   make it follow `main`.
2. The owner redeploys for P3 and P8 (`git switch main`, `git pull --ff-only origin
   main`, `./Setup-CopilotSettings.ps1`) and checks in a new chat that a prepared
   `git push` ends with a code block and no dialog. Agents cannot push, and the
   deployed copy under `~/.copilot` is the owner's to refresh.
3. The owner rules on the local queue (Desktop `LEDGER.md`): P5 stays unmerged until
   the architect fixes the verifier's trust model (then a fix prompt with the
   reviewer's tests and a second review); P1 needs the owner; the 06c choices
   (E-08, E-09), the P6 labels, and the three P8 assumptions need a ruling.
4. A further eval run needs a new amendment, TBD-11 closed with source and date,
   the owner's term file, and a freeze digest recorded outside the kit
   (`docs/SECURITY-REVIEW.md`, *Before the next freeze*; A34, A38); none is
   authorized.
5. Recommended to the owner, not required: update PowerShell 7 on RAANDREE3 from
   7.6.1, and delete the empty scratch folder on Prox1 (its profile entry,
   registration, and files were removed on 2026-10-08). Never set the
   summarization threshold below about 1.3 times the base prompt (*Compactions*).
6. Optional: report upstream that the GitHub hooks reference describes the
   exit-2 stdout merge without its `hookSpecificOutput` condition.

Still open from earlier work (Open work in `progress.md`): the live agent-host
`#web/fetch` check and the duplicate Instruction loading in Copilot SDK chats.
