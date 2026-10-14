---
status: current
last-verified: 2026-10-14
owner: software-engineer
source: current task evidence
---

# Active context

## Current focus

**P5, the containment verifier and the ledger appender, is rebuilt and has been reviewed
nine times; the branch `ai/containment-fix-round` (on `origin/main` `1c1327e`, nothing
pushed) waits for the owner's push, pull request, and merge.** `Test-RunContainment.ps1`
measures, for the one identity it runs as, what the run can write, reach, and read;
`Invoke-LedgerAppender.ps1` is the pinned, append-only, hash-chained ledger service the
profile names, and `-Revalidate` reads the ledger back after the run. The first review
said Block (13 findings, C-01 to C-13). The fix round answered them. Every later pass
but the last said Approve with changes and left no Blocker, and each of those found
something new in what the previous round had added; the last, part F, said Approve:
pass 1 (R-01 to R-11), pass 2 over the whole branch (S-01 to S-11), pass 3 in parts
A to F (S-12 to S-33). All are in `docs/SECURITY-REVIEW.md` with their resolutions. The
claims shrank where a reviewer showed them too large (decision 0025, revision
2026-10-14): two proofs about writability, not "exact writable roots"; one identity per
run, in a fresh `pwsh -NoProfile -File` process; the Remote grant measured by what the
pinned `hooks.json` registers (`GrantRecorderUnregistered`, which replaced
`OverrideAbsent` on the owner's "not sure, you pick": an assumption flagged for expert
review), so egress and credentials stay the boundary; and the hook command line accepted
by one plain shape and not by a list of characters to refuse (a `#` is a comment to
PowerShell and not to `cmd.exe`). Written down as not done: R-04 (token privileges and
elevation, so the run identity must be a standard account), hook files a host finds
outside the pinned one, a run id on `-Revalidate`, a keyed chain, a two-account test, the
pinned line run under the PowerShell hosts and not only through `cmd.exe`, S-33 (a quoted
program path with a colon after the drive fails closed), and Ubuntu and macOS CI (not run
here). A contained profile pins hashes and a `hooks.json` that registers only the guard
(regenerate it after every deployment). Final gate on `d8eddb4`: 5,063 passed, 0 failed,
146 skipped, 90.84 % coverage.

P2, per-command remote approval, is merged (#38, squash `1c1327e`,
`6.1.0-preview0011`) and live on this machine: a Grant marker the user types in their own
prompt (`[[allow-remote: git push, gh pr create]]`) lets the guard allow each named
operation once, until the next prompt or 15 minutes. The guard stays a hard block, and
`COPILOT_ATELIER_ALLOW_REMOTE` is gone. Decision 0016 holds the final gate, the live
acceptance of 2026-10-13, and the accepted residuals; the Desktop `LEDGER.md` the queue.

**Decision 0028 is merged and released** (#32 to #36 as `6.1.0-preview0005` to `0009`).
Criteria 1 to 20 and 22 to 30 are met; **criterion 21 is not met**, worded as A39 fixes
it, and TBD-2 is carried forward. M-04 (a `.familiarity` name collision) stays open. #34
to #36 (P7, P3, P8) are live on this machine, which carries `main`'s content (257 files
match, verified 2026-10-14); P8's base, its missing external eval, and its single review
are flagged assumptions. Prompt 06c (`docs/SECURITY-REVIEW.md`) fixed 2 Blockers and 7 Majors in
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

1. P2 is merged and already live here. Optional: one short live re-check of the shipped
   guard (`E94968A0…`) in a new chat; the acceptance of 2026-10-13 ran on the earlier
   `B6DFAD99…` (a push without a marker is denied; with `[[allow-remote: git push]]` one
   push runs). P5 removed the last mentions of `COPILOT_ATELIER_ALLOW_REMOTE` from the
   controller agent (the security lint names the rule `ObsoleteRemoteOverride`).
2. The owner checks in a new chat that a prepared `git push` ends with a code block and
   no dialog (P3 and P8 are deployed with P2; `./Setup-CopilotSettings.ps1` after a
   `git pull --ff-only origin main` only refreshes the record). Agents cannot push; the
   deployed copy under `~/.copilot` is the owner's to refresh.
3. The owner pushes `ai/containment-fix-round`, opens its pull request, and merges it
   (it contains PR #39, the open docs-only P2 record: close #39 unmerged, because
   squash-merging #39 first would make this branch conflict), then rules on the P5
   follow-ups, R-04 first and then the pinned line run under the PowerShell hosts; P1
   needs the owner; the 06c choices (E-08, E-09), the P6 labels, and the three P8
   assumptions need a ruling (Desktop `LEDGER.md`).
4. A further eval run needs a new amendment, TBD-11 closed with source and date,
   the owner's term file, and a freeze digest recorded outside the kit
   (`docs/SECURITY-REVIEW.md`, *Before the next freeze*; A34, A38); none is authorized.
5. Recommended to the owner, not required: update PowerShell 7 on RAANDREE3 from
   7.6.1, and delete the empty scratch folder on Prox1 (its profile entry,
   registration, and files were removed on 2026-10-08). Never set the
   summarization threshold below about 1.3 times the base prompt (*Compactions*).
   Optional: report upstream that the GitHub hooks reference describes the exit-2
   stdout merge without its `hookSpecificOutput` condition.

Still open from earlier work (Open work in `progress.md`): the live agent-host
`#web/fetch` check and the duplicate Instruction loading in Copilot SDK chats.
