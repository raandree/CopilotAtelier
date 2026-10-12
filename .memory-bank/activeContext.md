---
status: current
last-verified: 2026-10-12
owner: software-engineer
source: current task evidence
---

# Active context

## Current focus

**Decision 0028 is merged and released.** Pull request #32 (`807b572`, 2026-10-12)
closed it out (Desktop prompt 07, Prox1), and #33 to #36 followed one at a time:
`main` is `e393875` at `6.1.0-preview0009` (CI runs #139 to #142 green; GitHub
Releases and the Gallery verified). Criteria 1 to 20 and 22 to 30 are met, with the
evidence named in the record's *Close-out, 2026-10-11* matrix. **Criterion 21 is not
met**, worded exactly as A39 fixes it: persistence 83.3 % at both Positions, the
sentence still +30.6 points on the paired cases, `expert` terseness unreliable, the
provider terms UNVERIFIED, and no further run. TBD-2 is the one question carried
forward. The independent review of the hand-merged hook scripts approved with
changes: `ddf5430` fixed M-01 and M-02, #33 tested M-03, M-05, and M-06 (M-06 was not
a gap), and M-04 (a `.familiarity` name collision) stays open.

The other merged branches: #34 corrects the `automatedlab-deployment` Skill
(`Remove-LabVMSnapshot` also removes the newer checkpoints; P7); #35 hands a command
the user runs over in its own fenced code block (P3); #36 adds the task ledger and
the `/migrate-handoff-sequence` Prompt to `subagent-dispatch` (P8). P3 and P8 are
not live until the owner redeploys, because `~/.copilot/skills` is a junction to
the installed copy. P8 was decided under a no-questions delegation, so its base
`origin/main`, the absence of a paid or external eval (the Skill description and
the trigger sweep stay open), and its single independent review are assumptions
flagged for the owner.

Prompt 06c ran on 2026-10-12 (`docs/SECURITY-REVIEW.md`): four review rounds over
the eval kit's egress code, 2 Blockers and 7 Majors fixed test-first in the kit;
the Desktop `LEDGER.md` and `HANDOFF-2026-10-12.md` list what is open.

Prompts 03 and 08 are on `main`: the detached Pester guards reject a result other
than `Passed`, the Pester guides explain truthiness, `Wait-DetachedResult.ps1`
waits a bounded time, and the Post-flight elapsed line is pinned to its own
chat's clock (`Add-SessionContext.ps1` hands the agent `& '<reader>' -Path
'<clock>'`). The shared Instruction wording was chosen under a no-questions
delegation, so an expert review stays recommended. Decision 0024 holds the Prox1
evidence and what stays open (a host that sends no `session_id`, a chat after a
compaction on a host without the variable, VS Code Local and a new agent-host chat,
not yet seen live). The longer reader line leaves the calibration sentence fewer
characters under the session context budget, so one test in
`tests/ContributorProfileHooks.Tests.ps1` squeezes at 1,400 characters.

## Previous focuses

- **Prompts 04 to 06b and 05c (2026-10-09 to 2026-10-11).** The criterion 21 eval
  chain: Amendments 5 to 7, one fresh run (83.3 % at both Positions), and the
  record-only ruling that criterion 21 ships as not met (`progress.md`; the
  Decision's Confirmation). Prompt 06c reviewed the egress code on 2026-10-12.
- **Decision 0028, steps 7.1 to 7.5 (2026-10-06 to 2026-10-08).** The design
  (`b568c8c`, signed off after 26 questions), Amendments 1 to 4 (A1 to A19), the
  A12 backstop (`23a861a`), the hash-pinned frozen reference (`30fb3229…9c79`,
  A17), the latency levels (`3bef6b9`: `SessionStart.AddedLatency` Budget 2.0,
  `PostToolUse.CallLatency` Budget 0.75), and the VS Code Local backstop proved
  live (`b05efe3`). The RAANDREE3 `FailFast` is a .NET 10.0.6 runtime fault on
  PowerShell 7.6.1, not this repository's code. Evidence: the record's Confirmation.
- **Hook deny reason and the resume clock (prompt 06, #28 to #30).** The bundled
  Copilot SDK runtime drops a PascalCase deny that also carries
  `hookSpecificOutput`, so the guard prints the top-level pair alone;
  `tests/HookSdkRuntime.Tests.ps1` asserts the reason inside the real runtime
  (Decision 0016). A resumed chat keeps its clock. Merged into `main`, deployed
  2026-10-04; A2 and B2 then passed in new chats.
- **Contributor calibration Phase 1 (#27, `7a48abe`).** On `main`, as is Phase 2
  (Decision 0028). The private behavior eval scored 52.1% without the Instruction
  and 100% with it, and arms are compared only when run concurrently.
- **Hook guard follow-ups (prompts 02, 05, 06; `d8cc6f5` to `fea564f`).** Ten
  reviews ended in an approval. The guard decides within about five seconds
  (1 MB parse, 20,000-field walk, 4 MB block) and errs toward blocking; the
  override cannot reach a hook from an agent terminal. Deployed 2026-10-02.
- **Runtime tool names (`a592832`, on `main`).** Every Custom agent pairs its
  VS Code tool names with runtime names, so agent-host sessions keep `web_fetch`,
  `grep`, `glob`, `ask_user`, browser, and session tools (Decision 0026,
  github/copilot-cli#4594). Red 28 then green; offline probe 16 of 16 agents.
- **Plan-review findings PR-01 to PR-09.** Resolved in the integrated tree with
  a mandatory heading verifier; the guide, threat model, and `assessment-log.md`
  keep the contracts. Browser feedback never grants chat sign-off. The
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

1. The owner redeploys for P3 and P8 (`git switch main`, `git pull --ff-only origin
   main`, `./Setup-CopilotSettings.ps1`) and checks in a new chat that a prepared
   `git push` ends with a code block and no dialog. Agents cannot push, and the
   deployed copy under `~/.copilot` is the owner's to refresh.
2. The owner rules on the local queue (Desktop `LEDGER.md`): P5 stays unmerged until
   the architect fixes the verifier's trust model (then a fix prompt with the
   reviewer's tests and a second review); P1 and P2 need the owner; the 06c choices
   (E-08, E-09), the P6 labels, and the three P8 assumptions need a ruling.
3. Confirm the clock pin live in a new VS Code chat (Decision 0024 lists the
   cases).
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
