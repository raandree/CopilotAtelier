---
status: current
last-verified: 2026-10-11
owner: software-engineer
source: current task evidence
---

# Active context

## Current focus

**Decision 0028 was closed out on 2026-10-11 (Desktop prompt 07,
`software-engineer`, Prox1) and waits for the owner to push.** Criteria 1 to 20
and 22 to 30 are met, with the evidence named in the record's *Close-out,
2026-10-11* matrix. **Criterion 21 is not met**, worded exactly as A39 fixes it:
persistence 83.3 % at both Positions, the sentence still +30.6 points on the
paired cases, `expert` terseness unreliable, the provider terms UNVERIFIED, and no
further run. Criterion 23's gaps are fixed in the README, the hooks README, the
CHANGELOG, and the Glossary check, and TBD-2 is the one question carried forward.
`origin/main` (`9b6a341`) is an ancestor of `ai/calibration-phase-2`, so no merge
was needed. The full gate: 3,165 passed, 0 failed, 129 skipped (none in a suite
the matrix cites), coverage 90.84 %. The pull request title and body were drafted
in chat; the owner runs the push and `gh pr create` from their own terminal.
Nothing is pushed by an agent.

Still open, in the owner's order (Desktop `LEDGER.md`, `HANDOFF-2026-10-11.md`):
prompt 06c, an optional independent review of the eval kit's egress code and a
precondition of any further run; and the integration with `main`. The owner merged
`ai/session-lessons` and `ai/session-clock-path` into `main` locally on 2026-10-11
(`6286ad4`, 12 commits ahead of `origin/main`, not pushed), and `git merge-tree`
forecasts 9 conflicting files with this branch, three of them hook scripts. After
`main` is pushed, merge `origin/main` into this branch and rerun
`tests/ContributorProfileHooks.Tests.ps1`, because a longer reader line leaves
the calibration sentence fewer characters under the session context budget.

## Previous focuses

- **Prompts 04 to 06b and 05c (2026-10-09 to 2026-10-11).** A privacy review of
  the eval kit (four rounds; criterion 28 as scoped by `docs/SECURITY-REVIEW.md`);
  Amendment 5 (judge 2b, 39 of 40) and its first run (77.8 % and 72.2 %);
  Amendment 6 (A25 to A32) and its one fresh run (83.3 % at both Positions,
  held-out check 10 of 12 against 11, 5.92 USD); Amendment 7 (A33 to A39),
  record-only: criterion 21 ships as not met, no further run, 06c and TBD-11
  first.
- **Decision 0028, steps 7.1 to 7.5 (2026-10-06 to 2026-10-08).** The design
  (`b568c8c`, signed off after 26 questions), Amendments 1 to 4 (A1 to A19), the
  A12 backstop (`23a861a`), the hash-pinned reader-shaped frozen reference
  (`30fb3229…9c79`, A17), the latency levels (`3bef6b9`: `SessionStart.AddedLatency`
  Budget 2.0, `PostToolUse.CallLatency` Budget 0.75, one `w` per tag), and the
  VS Code Local backstop proved live (`b05efe3`, TBD-7 closed). The RAANDREE3
  `FailFast` is a .NET 10.0.6 runtime fault on PowerShell 7.6.1, not this
  repository's code. Evidence: the record's Confirmation.
- **Prompt 06 close-out (#29 `9b6a341`, #30 `25d8233`).** CI run 112 published
  `6.1.0-preview0003`. The SDK runtime drops a PascalCase `preToolUse` deny that
  carries `hookSpecificOutput` (Decision 0016); `tests/HookSdkRuntime.Tests.ps1`
  probes the runtime without a model. Phase 1 (#27, `7a48abe`) scored 52.1%
  without the Instruction and 100% with it in the private behavior eval.
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

1. The owner pushes `ai/calibration-phase-2` and opens the pull request from their
   own terminal, with the title and body drafted in chat; agents cannot push.
   After the merge, delete the merged remote branches and confirm that the CI
   release run publishes the next `6.1.0` prerelease.
2. Push `main` (`6286ad4`: the session lessons and the clock fix), then merge
   `origin/main` into this branch, resolve the conflicts that *Close-out,
   2026-10-11* forecasts, and rerun the affected suites.
3. A further eval run needs a new amendment, TBD-11 closed with source and date,
   and prompt 06c's independent review of the kit's egress code first (A34, A38);
   none is authorized.
4. Recommended to the owner, not required: update PowerShell 7 on RAANDREE3 from
   7.6.1, and delete the empty scratch folder on Prox1 (its profile entry,
   registration, and files were removed on 2026-10-08). Never set the
   summarization threshold below about 1.3 times the base prompt (*Compactions*).
5. Optional: report upstream that the GitHub hooks reference describes the
   exit-2 stdout merge without its `hookSpecificOutput` condition.

Still open from earlier work (Open work in `progress.md`): the live agent-host
`#web/fetch` check, the duplicate Instruction loading in Copilot SDK chats, and
deleting the merged remote branch `copilot/dgthths`.
