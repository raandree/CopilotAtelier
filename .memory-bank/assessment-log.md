---
status: current
last-verified: 2026-10-02
owner: security-reviewer
source: security assessments of this repository
---

# Assessment log

Episodic record of completed security assessments. One entry per assessment:
date, scope, verdict, and the findings that outlived the review. Retain two
years; archive older entries to a dated Memory Bank topic.

## 2026-10-01 contributor calibration Phase 1 and its private eval tooling

Scope: round 1 reviewed `a592832..6b00681` on `ai/contributor-calibration` — the
always-on `contributor-calibration` Instruction, the `/simpler` and `/deeper`
Prompts, the `grill-me`, `software-architect`, `gilb-requirements-engineering`,
and `memory-bank` edits, Decision 0027, the Glossary terms, README, CHANGELOG,
and `tests/ContributorCalibration.Tests.ps1` — plus two private helper scripts
outside the repository that mine local chat history and redact it. Round 2
reviewed the fixes and added the private eval runner, which sends approved,
anonymised prompts to the model backend and now carries a pinned LLM judge.

Verdict: round 1 **Fail**, zero Blocker and four Major. Round 2 **Pass**, zero
Blocker and zero Major, with eleven Minor and two Nit raised against the fixes
and the runner. The Majors were an injection surface and an excessive-agency
path in the always-on Instruction, and two redaction defects in the helpers.
Every finding is resolved. Round 2 verified each round-1 fix by re-running its
original reproduction rather than by reading the diff; the round-2 findings
were fixed afterwards and verified by the author's own tests — the private
self-check, the runner's Check and Calibrate modes, and the Pester suite — and
F-03, last to close on 2026-10-02, by a side-by-side measurement. No third
review round followed.
Full record, finding by finding, in
[docs/SECURITY-REVIEW.md](../docs/SECURITY-REVIEW.md).

Residual risk, with no finding left open:

- The behavior eval stays outside the repository because its cases come from
  personal chats, so none of its numbers can be reproduced here. The committed
  tests assert the wording, not the behavior, and model language drift between
  runs was disclosed rather than verified.
- Redaction in the private helpers does not cover personal names outside paths
  or postal addresses. The limitation is documented; a human read before
  anything leaves the machine is the only control.
- The delegation, provenance, and authorization bounds are model-layer rules.
  The deterministic hook covers remote mutation and hard reset, not every
  irreversible action.
- A familiarity level lives only in the conversation, so a compaction resets it
  to the default. Accepted until the Phase 2 profile exists.
- The always-on Instruction sits at 3,811 of its 4,096-character test cap, so
  the next rule added to it needs a trade.

## 2026-09-07 uncommitted feature review: validation, learning inbox, adapters

Scope: the uncommitted working tree at `35fa926` — the `changed-file-validation`
and `reviewed-learning-inbox` Skills, the client adapter and its build task, the
footprint, profile, and Skill-health commands, and the installation-profile
changes to planning, install, update, and the Deployment record.

Verdict: **Approve.** Zero Blocker, zero Major. No network egress, no
`Invoke-Expression`, no dynamic script block, and no credential handling exists
anywhere in the new code, so the lethal trifecta has no outbound leg.

Controls confirmed by reading, not by comment: validators only ever see a
snapshot copied under a generated name, so no project text reaches a command
line; PSScriptAnalyzer runs with an inline settings hashtable, so no project
settings file or custom rule module loads; the external-tool host uses
`UseShellExecute = $false`, a deadline, output caps, and `Kill($true)`; promoted
learning text passes a printable-prose allow-list that excludes `<`, `` ` ``,
`$`, and backslash, so a block marker cannot be forged, and a capability-key
denylist blocks `tools`, `model`, `agents`, and `applyTo`; promotion requires
`-Approve` plus the SHA-256 of the reviewed preview rather than a blind prompt,
and appends through an exclusive handle that restores the original bytes when
verification fails; mandatory lifecycle and security Skills cannot be excluded
from an installation profile, and Instructions and Hooks are never narrowed.

Retained findings, none blocking:

| ID | Severity | Finding |
|---|---|---|
| CFV-1 | Withdrawn | Hypothesised that `Remove-ChangedFileSnapshot` could delete through a link planted in the snapshot directory. Measured on every supported host instead of assumed: Windows PowerShell 5.1.26100, PowerShell 7.6.5 on Windows, and PowerShell 7.4.6 on Linux all remove the link and leave the target intact. The scenario cannot happen, so no guard was written. |
| RLI-1 | Resolved | The learning inbox documented its storage and a conditional ignore rule but never said what becomes of a saved proposal. The Skill now states that a proposal is working state to delete once applied or abandoned, and that promoted or rejected candidates are pruned with `Remove-LearningCandidate.ps1`. |
| RLI-2 | Informational | Promotion may append to auto-applied Instructions, which steers every later session. Accepted by design and well gated; the gate is the only thing standing between a candidate and global behaviour. |
| CFV-2 | Informational | The markdownlint executable resolves through `Get-Command -CommandType Application`, so a bare name follows PATH order. Caller-supplied and documented. |
| Q-1 | Minor | `ChangedFileValidationCommon.ps1` (90 KB) and `Measure-CopilotAtelierSkillHealth.ps1` (63 KB) are large enough that no single review pass holds either whole. |

Evidence: `review-compliance-1d4a231cff0248afab4b15f2eb87b9c0.log` (617 passed;
its 39 failures and 2 container errors were caused by the harness pre-importing
`powershell-yaml`, not by the code) and
`review-compliance2-*.log` (39 passed, zero failures on the clean re-run of
`CustomizationSecurity` and `Workflows`). Skill frontmatter and budgets, README
catalogue, trigger coverage, Customization frontmatter, secret scan, and Memory
Bank health all pass.

Unverified and disclosed: no build ran, so the new commands, the
`Build_Client_Adapter_Variants` task, and roughly 330 KB of new unit tests are
unexecuted here; a rebuild would have collided with concurrent work in this
worktree. Non-Windows was not exercised. The tree changed during the review.

## 2026-09-06 remediation and independent re-review

The user's remediation request is the acceptance contract. Earlier
"accepted residual risk" wording in other records was not explicit user
acceptance and is superseded. The historical review below remains intact.
M4 includes explicit traversal rejection; M5 is the Glossary item omitted from
that historical assessment's list. The original IDs are retained here.

| ID | Current disposition | Regression evidence | Independent review |
|---|---|---|---|
| M1 | Resolved: hook drift is an error; commands and required script bytes match the loaded module, including untracked scripts. | Initial 10 red cases plus two altered-record/untracked cases; final integrity/configuration/serialization slice 65 passed, one POSIX skip. | Approved; four-event maintenance observation below. |
| M2 | Resolved: explicit `-Repair`, no untracked ownership or overwrite. Modified content is replaced without backup by explicit request. | Six red repair cases; 43/43 green install tests, also covered by final gates. | Approved. |
| M3 | Resolved: recoverable per-file records, verified staging state, and local coordination; abandoned staging and concurrent matching untracked files are preserved. | Initial interruption/coordination failures, staging-preservation failure, and two matching-untracked race failures reproduced; latest recovery/install slice 69/69. | Approved; not a filesystem or cloud-sync transaction. |
| M4 | Resolved: one portable segment validator for planning and record reading, including `.` and `..`. | Seven confirmed red planner cases; combined path/install/removal gate 79 passed, four POSIX skips. | Approved; real non-Windows execution unavailable. |
| M5 | Resolved: Glossary rows for Owned file and Deployment plan; record definition reconciled. | Both rows absent before edit; Markdown lint and rendered Glossary rows pass. | Approved. |
| L1 | Resolved within the documented uniform filesystem policy: target-native comparison shared by planning, reading, recovery, and removal. | Three red mock cases; combined gate 124 passed, five native POSIX skips. Native Windows exercised. | Approved; fail-closed probe prerequisite documented. |
| L2 | Resolved: TargetPath through Install, Update, and Setup; public resolution never prompts; repair forwarded. | Eight red cases; 59/59 green install/update checks. | Approved; live OneDrive not exercised. |
| L3 | Resolved: retained capitalized trees reported only when distinct; no cleanup. | Red mocked legacy-tree case and inspection-root guard; 45 passed, six native POSIX skips in combined slice. | Approved; real case-sensitive tree check unavailable. |
| L4 | Resolved: preserve ordinary members, restore copied type data and prior build-exit callback on success/failure; isolate expected fixture failures from parent accounting. | Custom-policy, member-loss, nested cleanup, and parent-error failures reproduced. Six green checks under preexisting overrides and on 5.1. | Approved; final parent build has zero errors. |
| L5 | Resolved: ConvertFrom-Json hook loader with shape checks. Checker stays test-local: directly exercised and no public consumer warrants extraction. | YAML-only JSON fixture failed before fix; strict JSON and existing adversarial fixtures pass. | Approved; no new public API. |
| L6 | Resolved: built-in/implicit nonempty overrides rejected as unverifiable; named Custom agent subsets retained. | Six red cases; combined configuration/frontmatter gate 148/148, also covered by final gates. | Approved; static configuration only, not runtime containment. |

Logs are under `$env:TEMP`, with matching `.exit` completion evidence:

- `atelier-remediation-M1-green-7cc0e40a329345bd9a2942bda168bfdd.log`
- `atelier-remediation-M2-green-35d1776a2eed4192bda90ce114233698.log`
- `atelier-remediation-M4-red-confirmed-018b78a691234c09ad3d535ba750e3fb.log`
- `atelier-remediation-M4-green-75f4db74ee424f85a94fd6dd07b33453.log`
- `atelier-remediation-M3-red-confirmed-e3888011056f41c8ae6847661140f16a.log`
- `atelier-remediation-M3-green-atomic-974442b7147c446581634d3ae6c763a9.log`
- `atelier-remediation-recovery-preservation-green-c6addf44e2f34960b88e6a4d41d12a47.log`
- `atelier-remediation-L1-green-027f658a724d48f488968a9771497126.log`
- `atelier-remediation-L2-green-711110288a1f4588ada0b6004be6ae08.log`
- `atelier-remediation-L3-green-3c95f55b48504231b41e65a967fd1110.log`
- `atelier-remediation-L4-green-4d6968f0a5e841d7af80608d679f4f35.log`
- `atelier-remediation-L6-green-6944e2fa01ad4f759562498cc474fe8e.log`
- `atelier-remediation-integrity-review-green-3b814621e620424f8fe432f3167d7f80.log`
- `atelier-remediation-pinned-reference-30906e76a2a1429d8972af56c8d2e890.log`
- `atelier-remediation-L4-existing-override-green-0d8dfdfe498d430490a45a02d85f2436.log`
- `atelier-remediation-recovery-race-green-d2cd18e348db4aafbf5e72bead860d6a.log`
- `atelier-remediation-L4-parent-accounting-green-17ca73ff459249cdafe78b777751ec45.log`
- `atelier-remediation-accepted-native-3f0a5aabbd5e44ba950515462431a893.log`
- `atelier-remediation-final-ps51-8c4a635a55a84eafb78b453ef05e27e6.log`
- `atelier-remediation-serialization-final-ps51-308b11a773144e1b85058bfd599c647e.log`
- `atelier-remediation-final-records-b54dc69c28f14d9da77abccae35175f3.log`

The first full remediation gate exposed removed FileInfo members; the second
exposed test cleanup passing a string array to scalar `Remove-TypeData`.
Neither failed run is a passing gate. Both defects were corrected without
weakening assertions. A real Windows PowerShell 5.1.26100.7462 run passed
470 checks with nine explicit skips, but predates the last recovery-race fix.
The subsequent native run passed 1,233 tests with 66 skips and 87.8% coverage,
but two intentionally failing nested fixture builds polluted its parent error
count, so it was not counted as a clean build. A dedicated failing regression
led to module-scoped fixture invocation; all six serialization checks now pass,
including zero parent errors. Final evidence:

- `./build.ps1 -Tasks build, test`, detached with pinned uv on the child PATH:
  1,234 passed, zero failures, 66 skips; 87.8% coverage against 65%; 20 build
  tasks, zero build errors, one existing simulated-backend negative-fixture
  warning. NUnit artifact: `output/testResults/NUnitXml_CopilotAtelier.xml`.
- Windows PowerShell 5.1.26100.7462: 473 passed, zero failures, nine skips;
  final fixture-only compatibility run: six passed, zero failures/skips.
- Final native AST and PSScriptAnalyzer: 22 changed scripts, no findings.
  The 5.1 run parsed/analyzed the 21 scripts then present; the added parent
  fixture executed successfully in the final six-test 5.1 run and passed a
  separate real 5.1 AST/PSScriptAnalyzer check with an isolated analysis cache.
- Final Memory Bank health/routing checks: 15 passed, zero failures/skips;
  final Markdown lint/render and diff whitespace checks passed. The temporary
  PowerShell ModuleAnalysisCache created in the working tree was removed.
- Native skips: 17 existing Skill size-budget cases, 37 existing uncovered
  trigger sets, three deliberate sample-trigger cases, two documented
  reference-specification divergences, and seven non-Windows filesystem cases.
  The nine 5.1 skips are those seven filesystem cases and two divergences.
- Pinned uv 0.8.15 in an isolated Python 3.12 environment: 47 reference checks
  executed, two documented divergence skips. No missing-tool skips remain.

Independent `security-reviewer` re-review: **Approve**, zero Blocker/Major,
two Minor, three Nit observations. Full source/diff trace, editor diagnostics,
and the final native gate were checked; no model-backed behavior was inferred.
The local report is `session/handoff-deployment-remediation-review.md`.

Non-blocking dispositions: document the filename probe's fail-closed
precondition instead of guessing a filesystem default; retain the current
four-event hook-check list as a maintenance observation (all currently shipped
events are checked). Readability indentation, a retained empty coordination
file, and over-serialization of case-only sibling targets remain Nits. No
observation is represented as explicit user risk acceptance.

No WSL distributions, Docker, or Podman are installed. Real non-Windows
filesystem and live OneDrive sync checks remain blocked. Mocked POSIX entries
do not substitute for those runs. Those checks require an isolated non-Windows
host and an authorized OneDrive test account respectively. Model-backed
behavioral evaluations require a supported runner and spending authorization;
neither is established. No Customization body/tool declaration changed. These
unexecuted checks are not passed gates. All work remains uncommitted by request;
no real deployment profile, native plugin cache, or remote was changed.

## 2026-09-06 — deployment lifecycle and configuration gates (`8353cef`)

**Scope.** `Install-CopilotAtelier` ownership rewrite, new `Test-CopilotAtelier`
and `Uninstall-CopilotAtelier`, three new private deployment helpers,
`Add-SessionContext.ps1` context budget, the Customization configuration gate,
and the Sampler result-serialization task.

**Verdict: CONDITIONAL.** No Critical or High findings. The change set removes a
real destructive-overwrite path and adds path, ownership, and conflict
validation. Five Medium findings remain; two of them bear directly on publishing
the removal and diagnostic commands.

**Findings that outlived the review.**

- Drift of a deployed security control is reported as a non-failing `Warning`.
  Deleting `Block-RemoteMutation.ps1` is an `Error`; neutering its body is not,
  and `IsHealthy` stays true. `InvalidHookConfiguration` only asserts that the
  four event keys are truthy, so a repointed hook command also passes.
- Conservative ownership has no repair path. A drifted owned file blocks its own
  reinstallation and `-Force` deliberately does not override, so a tampered hook
  script cannot be restored by supported means.
- Apply is not transactional. Settings are written before the file loop and the
  Deployment record after it, so a mid-loop throw leaves record and disk
  disagreeing. A later payload downgrade turns that into a permanent conflict.
- Record write-side and read-side validation are asymmetric. The plan accepts
  POSIX-legal names that the record reader later rejects, which can make a
  successful deployment permanently unreadable.
- Traversal rejection in the record reader depends implicitly on the
  trailing-dot segment rule rather than an explicit `..` check.

**Carried forward, not introduced here.** The twelve agents with unrestricted
MCP access are now baselined by the configuration gate but not contained; the
`software-engineer-contoso` egress claim and the broad omnibus tool surfaces
recorded in `activeContext.md` remain open.

**Not exercised.** Live OneDrive sync, non-Windows hosts, concurrent
install/uninstall, and any behavioral eval of the shipped Customizations.

## 2026-09-07 independent review: plan-review local review surface

Scope: `tools/plan-review` at pinned `3d115a3` (base `555c260`) — the loopback
HTTP surface, containment and path handling, Markdown/Mermaid rendering, section
and revision identity, feedback store, CLI lifetime, the browser assets,
`tests/PlanReview.Tests.ps1`, both plan-review documents, and the architect
sign-off reference. Report:
`…/atelier-security-review-20260907-0831/report.md`.

**Verdict: CONDITIONAL.** Zero Blocker, one Major, six Minor, two Nit.

**Process condition — the review baseline did not hold.** The brief pinned a
clean worktree at `3d115a3`. Mid-review, six files under `tools/plan-review`
were modified and three new test files appeared, with mtimes from 08:35 to
08:39 UTC; `src/server.mjs` was rewritten three seconds before the query that
observed it. The reviewed feature was being hardened while the single
authorized independent review of it ran. All findings were re-derived from
`git show 3d115a3:…` extracted into a temp fixture, so they are valid for the
pinned commit only. The delta to whatever is eventually committed is
unreviewed. Re-pin before treating this as a verdict on shipped code.

**Findings that outlived the review.**

- `splitSections` recognises only column-0 ATX headings, while the renderer it
  feeds honours setext and 1–3-space-indented headings. Three rendered headings
  collapsed to one section in a reproduction, so comments anchor to the
  preceding section and per-section revision state degrades to per-document.
  This falsifies the feature's own "never silently attaches comments to
  unrelated text" guarantee. Neither heading form is covered by a test.
- `serveStatic` pipes without an error listener; an async read failure escapes
  the request `try/catch` and terminates the process. The documented rollback
  ("delete `node_modules`") is itself a reachable trigger for the vendor routes.
- `cli.mjs` awaits `server.listen()` outside its error handling and invokes
  `main()` with no `.catch()`, so `EADDRINUSE` prints a Node stack trace instead
  of the file's own `refused to start:` message.
- `openVerdictDialog` dereferences `state.revision` unguarded, so a verdict
  button clicked after a failed first load throws instead of reporting.
- `store.removeComment` is exported, unreachable, untested, and — alone among
  the store mutations — not bound to a document hash.
- The PowerShell trust-boundary suite asserts that gate functions are *defined*
  in `security.mjs`, not that `guardMutation` calls them. Dropping a gate from
  the array would keep the repository gate green; behavioural coverage exists
  only in the Node integration suite, which the gate does not run.
- Documentation drift on the load-bearing boundary: the threat model quotes a
  UI label ("Reviewer feedback — not sign-off") that the interface never
  renders, and describes the `Origin` check as conditional when the code
  requires it unconditionally.

**Controls confirmed by reading and probing, not by comment.** Approval
authority holds end to end — feedback persists as `local-http-feedback` under
`chat-sign-off-required`, no endpoint writes a Decision record or triggers a
handoff, `--state` inside `.memory-bank/decisions` is refused, and the architect
frontmatter grants are untouched. The lethal trifecta is broken at the outbound
leg structurally: no server-side `fetch`, no `child_process`, no `vm`, CSP
`default-src 'none'`, images rendered as alt text. Containment re-checks
realpath and every ancestor reparse point at read time, not only at launch.
Mutations clear Host, Origin, `Sec-Fetch-Site`, content type, session cookie,
and a constant-time double-submit CSRF token before the body is read; Host is
checked on every route, which also closes DNS rebinding. `build.yaml` carries no
`tools` entry, so a Gallery install cannot ship the package.

**Not exercised.** Desktop and mobile screenshots (gitignored, absent from the
diff, so the layout and console-error criteria are unverified by this review),
the browser suite, the full PowerShell and Node suites, and the npm audit — all
named as already run and deliberately not repeated. `package-lock.json` contents
were not reviewed. The same-user local attacker and the `lstat`/`realpath`
TOCTOU remain accepted, disclosed residual risks.

## 2026-09-07 review: plan-review correction integration (`f933946`)

Scope: the integration commit `3d115a3..f933946` — 32 files, +3,423/-500 —
covering the PR-01…PR-09 corrections merged onto the concurrent hardening.

**Verdict: CONDITIONAL.** Zero Blocker, one Major, two Minor, two Nit. No new
vulnerability: every trust boundary the previous review confirmed still holds,
and the Major is a missing regression guard rather than a defect in shipped
behavior.

**Major — the fail-closed heading check is invisible to the gate that runs.**
`tests/PlanReview.Tests.ps1` discovers `test/unit/*.test.mjs` only, and its
single Node execution case runs that list. The behavioral proof of the PR-01
fix lives in `test/integration/heading-verification.test.mjs` and
`heading-agreement.test.mjs`, both of which need `markdown-it` and therefore
never run in the repository gate or CI. A search of the gate file for
`verifyHeadings`, `createHeadingVerifier`, or `heading-structure` returns
nothing, so there is no source tripwire either. Deleting the verifier wiring
from `readDocument` leaves `./build.ps1 -Tasks test` green. This is the defect
PR-07 raised about the mutation gate, which was closed with both a
dependency-free behavioral test and a composition tripwire; the heading control
received neither. Remediation is the same shape and costs one `It`.

**Minor — the control is fail-open at its own API.** `verifyHeadings` defaults
to `null` in `loadDocument` and `loadDocumentSync`, so an omitted argument
silently skips verification. Safe today only because `server.mjs` funnels four
reads through `readDocument` and the fifth through `descriptorIdentity`.
Nothing enforces that, which is what makes the missing tripwire load-bearing.

**Minor — `f933946` landed directly on `main`.** Post-flight prefers a topic
branch. Consistent with this series and with the user's standing instruction,
recorded as a deviation rather than a defect.

**Nit.** `assertNoForbiddenKey` stops silently at depth 8; defence in depth
only, since no downstream sink merges or assigns the parsed body. The queued-
lock regression patches `fs.mkdirSync` process-wide through
`syncBuiltinESMExports`; capture-before, always-delegate, restore-in-`finally`
and per-file process isolation make it sound, but the patch is worth knowing.

**Controls confirmed by reading the source, not the comments.** The corrected
prototype-pollution rationale is now accurate: the raw-text regex is bypassable
with `\u005f` escapes, but `assertNoForbiddenKey` walks `Object.keys()` against
`FORBIDDEN_KEY` and catches the escaped form, so PR-08 is properly closed. The
lethal trifecta stays broken at the outbound leg — `headings.mjs` adds a
`markdown-it` import and nothing else, with no network, `child_process`, or
`vm` anywhere in the package. A stored file still cannot promote itself:
`verdict.authority === FEEDBACK_AUTHORITY` is enforced on read and
`approvalAuthority: 'chat-sign-off-required'` is repeated on every response.
Refusal was verified to write no state at launch, on read, and inside the
serialized mutation, and the queued-write regression is genuinely
discriminating.

**Not exercised.** The full gates were read from this session's completed runs
rather than re-run; macOS, current Linux PowerShell, live OneDrive, `npm audit`,
and any performance benchmark of the now-doubled parse remain unmeasured.

## 2026-10-02 independent review: conventional version bumps and atomic heartbeat state (`09e2798..31042ea`)

Scope: two local, unpushed commits on `ai/conventional-version-bumps` — 8
files, +234/-6 — reviewed before `main`, where a push publishes a Gallery
preview. `bff3ac4` replaces the in-place heartbeat state write with a rename;
`31042ea` replaces the Sampler word-matching GitVersion bump patterns with
Conventional Commit markers.

**Verdict: APPROVE.** Zero Blocker, zero Major, five Minor, four Nit. Both
commits do what they claim, verified against the real toolchain rather than
against their own descriptions.

**Verified, not assumed.** GitVersion 5.12.0 (SHA-256 `F80AEA48…76071`) on
throwaway clones reproduces the regression and the fix: merging this branch
into `main` yields `7.0.0-preview0001` under the old patterns and
`6.0.1-preview0001` under the new ones. A 32-message synthetic matrix, read
with `main: increment: None` so the branch default cannot mask the matched
pattern, confirms all 15 authored QA expectations against the real binary, and
confirms the engine assumptions the test models: whole message including body,
case-insensitive, major→minor→patch→none, inline `(?m-i:)` honored. The
patterns are linear — 75,000-character pathological inputs match in under 9 ms.
A `feat:` reached through a `--no-ff` merge commit still counts, so merge
workflows do not under-version. The heartbeat guard is real: against the old
`Save-HeartbeatState` it produces 1–4 torn reads and 15–21 failed writes of 25
on PowerShell 7 and 780–1846 torn reads on Windows PowerShell 5.1; against the
new one, zero of both on both runtimes across three runs each. Ten of the 15 QA
cases fail against the old patterns.

**Minor — a `BREAKING CHANGE:` line anywhere at column 0 forces a major.**
`GitVersion.yml` `(?m-i:^BREAKING[ -]CHANGE:)` is not footer-scoped:
`docs: quote a changelog` with that line in the body measured 2.0.0. The same
prose-becomes-a-release class the commit set out to close, narrowed but open.
Partly by design — Conventional Commits treats the footer as authoritative.

**Minor — the rename retry loop retries permanent failures.**
`FileNotFoundException`, `DirectoryNotFoundException`, and
`PathTooLongException` all derive from `IOException`, so a vanished temporary
file or a read-only state file is retried for the full five seconds before
rethrowing: measured 5.00 s and 5.01 s. Narrowing the catch must use
`$_.Exception.InnerException` — PowerShell wraps a static .NET method failure
in `MethodInvocationException` — and must not key on `HResult`, because the
Windows PowerShell 5.1 `Microsoft.VisualBasic` path rebuilds the exception and
loses the Win32 code.

**Minor — the Windows PowerShell 5.1 branch has no CI coverage.** The test
matrix is ubuntu/macOS/windows, all `shell: pwsh`. The new
`Add-Type -AssemblyName Microsoft.VisualBasic` plus `FileSystem.MoveFile`
fallback only runs where the three-argument `File.Move` is absent, so the
runtime where the bug was worst is the one the pipeline never exercises.
Verified correct by hand; nothing guards it.

**Minor — the QA model omits GitVersion's branch-default floor.**
`DetermineIncrementedField` raises a message increment to the branch default
when it is lower, so `+semver:skip` on `main` measures 1.0.1, not "no bump",
and `fix:` on an `ai/**` branch measures 1.1.0. `Get-MessageIncrement` models
which pattern matched, not the increment taken, while the Context and It names
promise the latter. Every assertion in it is correct as pattern classification.

**Minor — README and AGENTS overstate "only … raises the version".** A
marker-free `docs:` subject on `main` still measures 1.0.1 from the branch
default, and prose containing the literal `+semver: major` token measures
2.0.0.

**Nit.** The temporary file leaks when the armed process is killed mid-write —
reproduced deterministically by holding the state file open and issuing the
`Stop-Process -Force` that `-Stop` itself performs, leaving one orphaned
`state.json.<guid>.tmp`; the new test asserts cleanliness only on the graceful
path. The comment justifying the choice over `File.Replace` is wrong about why
(`ReplaceFile` keeps the destination name present; the real reason is that it
requires the destination to exist). `[hotfix] fix:`, `fixup!`, `squash!`, and
revert subjects silently take the branch default — under-versioning, benign.
Both new branches are blocked under Constrained Language Mode where
`Set-Content` was not; narrow, and not empirically verified.

**Controls confirmed.** The rename replaces a symlink at the destination rather
than writing through it, so the change reduces a redirection risk the old
`Set-Content` carried. The temporary name carries a 128-bit GUID and cannot be
pre-planted. The state file still stores no executable content and the `-Stop`
PID-plus-start-time guard is untouched. No credentials in the diff. No
catastrophic backtracking in any of the four patterns. Both commits classify
themselves correctly as patches.

**Not exercised.** No build or test run in the repository or its worktree, by
constraint. Linux and macOS behavior of the rename, the Pester suite under
Pester 5, and GitVersion versions other than 5.12.0 remain unmeasured.

## 2026-10-02 post-release review of the hook launcher fix (0ed6c0e, 225c190)

Scope: `git diff 2de317d 225c190` — the `PLUGIN_ROOT` / `HOME` / `USERPROFILE` /
`GetFolderPath('UserProfile')` resolution chain and `-ExecutionPolicy Bypass` in
`com.github.copilot/hooks/hooks.json`, the unreadable-payload change in
`Block-RemoteMutation.ps1`, and the new `tests/HookLauncher.Tests.ps1`. Both
commits reached `main` without a pull request and shipped in v6.0.0, so this is
a post-release review. Read-only: no fix, no commit, no redeploy.

Verdict: **Fail** — one Blocker, five Major, six Minor. The deployed tree
hash-matches source on all seven hook files, so there is no deployment drift.

**Blocker.** The `PreToolUse` guard does not block in VS Code Local on Windows.
Both launchers nest a second interpreter, and an outer PowerShell `-Command`
collapses every non-zero native exit code to 1 — measured for `powershell.exe`
5.1 and for `pwsh` 7. VS Code treats 2 as a block and any other non-zero as a
non-blocking warning, so the guard degrades to a warning in the primary local
harness. The Copilot SDK host still denies, because it denies on any non-zero.
This shape is pre-existing, not introduced by the diff, but v6.0.0 shipped it
and the new test certifies it as correct.

**Major.** `0ed6c0e` put `HOME` ahead of `USERPROFILE` in the Windows launcher,
which previously consulted `PLUGIN_ROOT` then `USERPROFILE` only; a script
planted under a `HOME` that Git for Windows, MSYS, or a roaming profile sets now
outranks the deployed guard and was observed running in its place. `225c190`
turned an invalid-JSON payload into exit 0, and JSON nested past the
interpreter's limit — over 100 levels on Windows PowerShell 5.1, over 1024 on
pwsh 7 — reaches that path and lets a push through. A `HOME` on an unreachable
UNC path took 21.7 s against the 20 s timeout, and a timeout fails open.
`Get-CommandText` stops recursing past depth 4, so a command field nested six
levels deep is never inspected. `tests/HookLauncher.Tests.ps1` encodes the
exit-code collapse as the expected result and justifies it with a claim that no
launcher text can prevent it; appending `; exit $LASTEXITCODE` to the launcher
preserves the block in both spawn modes, so the claim is false and CI cannot
see the Blocker.

**Controls confirmed.** No launcher carries `$`, a backtick, `%`, `!`, `\`,
`<`, `>`, or `^`; the only `&` and `|` sit inside the quoted `-Command` region,
so cmd.exe and sh pass the text through unchanged. `-LiteralPath` does not glob,
and the `PadLeft(1, '*')` sentinel for an unset variable yields a path that
cannot exist on Windows. Payload size is not a fail-open: 12 MB still blocks. A
lone surrogate still blocks. The tests rename the script to a per-case GUID stub
before staging, so no behavioral case can reach a real deployed hook script, and
nothing is written outside `TestDrive`.

**Not exercised.** No build or Pester run, by constraint. POSIX behavior of the
resolution chain, the Copilot SDK host's own spawn path, and reachability of the
nesting fail-open through a specific shipped tool schema remain unmeasured.

## 2026-10-02 re-review of the hook launcher fixes (d8cc6f5, 8f2cb56, 68d07cc)

Scope: `git diff bd60b7a 68d07cc` on `ai/hook-launcher-review` — the three fixes
for the Blocker and the five Major findings raised the same day. Read-only; the
worktree was not built or tested, and the diff was read from git objects.

Verdict: **Fail** — zero Blocker, one new Major. Four of the six findings are
resolved and verified; SEC-03 and SEC-05 are only partly closed.

**Resolved.** The `windows` launchers now end with a pass-through statement that
the outer shell runs, and a block survives as 2 in all four spawn modes — VS
Code's exact spawn, `cmd.exe`, an outer `pwsh`, and a direct start — while an
allow still reports 0. The `+ 2` fallback is fail-closed: `$LASTEXITCODE` does
not exist in a fresh `-Command` session in either interpreter, so the empty
array plus 2 yields 2 when the inner interpreter never runs. An unresolvable
script still exits 2 in every mode. Reordering the candidates to `PLUGIN_ROOT`,
`USERPROFILE`, `HOME`, profile folder stops a planted `HOME` from winning, and
an unreachable `HOME` now costs 0.9 s instead of 21.7 s. The tests gained the
real VS Code spawn, assert 2 for the `windows` branch everywhere, and correct
the false claim that no launcher text could pass the code on.

**New Major.** The raw-text scan that backs the 64-level walk misses a command
written as a JSON array of words. `{"args":["git","push",...]}` nested past the
walk depth is allowed at 70 and 2100 levels on both interpreters, while the
same payload at 3 levels is blocked, because the walk joins array elements with
spaces and the raw text does not: the `(?=\s)` lookahead after the verb cannot
match a comma. The bypass is the same class the fix was written to close, and
no test covers the array form.

**Minor, not fixed.** A benign edit that merely documents a push is blocked when
its payload is unreadable or nested past the walk — fail-closed, an availability
cost only. The unreachable-UNC stall is moved rather than removed: a dead
`PLUGIN_ROOT` still costs 21.7 s against the 20 s budget, measured with a fresh
unroutable address, and the fix works because `Select-Object -First 1`
short-circuits the pipeline before later candidates are probed, an invariant no
test pins. Under `cmd.exe` with no inner interpreter on `PATH` the hook exits 1,
which VS Code treats as a warning; the pass-through cannot help there because
cmd folds it into the interpreter's own arguments.

**Correction to the earlier entry.** The echo-and-exit-0 behaviour reported as
SEC-11 does not reproduce when `cmd.exe` receives the launcher as the raw
`/d /s /c "..."` string the hosts and the repository tests use. The earlier
observation came from the review harness escaping the inner quotes, and the
finding is withdrawn.

**Not exercised.** No build or Pester run, by constraint, so the reported pass
counts are unverified. POSIX spawn paths and the `command` launcher under a
non-Windows VS Code remain unmeasured.

## 2026-10-02 third review of the hook fixes (8f03b08, 04b791b, 9b03078)

Scope: `git diff 68d07cc 9b03078` — the override guidance rewrite, the new
`powershell` launcher key with a JSON deny object on standard output, and the
argument-array fix for SEC-13. Read-only; the `ca-hooks` worktree was neither
built nor tested and the diff was read from git objects.

Verdict: **Fail** — zero Blocker, one new Major. SEC-13 is closed and the two
host-mechanics commits do what they claim.

**Resolved.** An argument array now blocks at 6, 70 and 2100 levels on both
interpreters, and the punctuation-free copy stays on the raw-scan path: three
readable shallow probes, one carrying a literal two-element array of the verb
and the subcommand inside documentation text, were all allowed. On a block the
guard writes exactly one parseable JSON object of 821 bytes with
`hookSpecificOutput.permissionDecision` set to deny, and writes nothing at all
on an allow. Stdout cannot turn a block into an allow in VS Code: its
precedence map is `{deny:2, ask:1, allow:0}`, the deny branch is unconditional,
a later allow cannot outrank a deny, and the error path forces deny anyway. The
new `powershell` key changes nothing outside the Copilot SDK host on Windows,
because VS Code's launcher selector has no branch for it and its config
normalizer copies known keys instead of rejecting unknown ones. The SDK spawn
now reports 2 where the old `command` key reported 1.

**New Major.** The pattern set is quadratic in the length of the scanned text,
and a hook timeout fails open. Measured: 4 KB of payload costs 0.15 s, 8 KB
0.54 s, 16 KB 1.42 s, 32 KB 5.69 s, and 64 KB **21.54 s** against a 20 s
budget. The raw-scan path newly exposes it, because it concatenates four copies
of the payload: the same deeply nested 64 KB payload returned in 0.4 s under
v6.0.0 and is still running after 75 s now. A long readable command string hits
the same wall in both versions, so that half is pre-existing and latent. The
fix for the nesting bypass therefore traded it for a size bypass reachable by
the same actor.

**Minor, new.** The claim that an agent cannot set the override is overstated.
User-scope values under `HKCU\Environment` are inherited by brand-new
processes — verified by reading one and seeing a freshly started interpreter
report the same value — so an override persisted that way survives until the
next host start. The `command` key still carries no pass-through, so a host
that wraps it in an outer PowerShell sees 1 rather than 2 and loses the
standard-output reason.

**Carried forward unfixed.** SEC-14 and SEC-16 are now documented. SEC-15
stands: an unreachable `PLUGIN_ROOT` still costs 21.7 s.

**Not exercised.** No build or Pester run, by constraint, so the reported pass
counts are unverified. The override-persistence path was reasoned from a
read-only check of the inheritance mechanism; setting the variable would have
mutated the user's environment and was out of scope.

## 2026-10-02 fourth review of the hook fixes (caaf9a5)

Scope: `git diff 9b03078 caaf9a5`, the time limit for SEC-17 and the override
wording for SEC-18. Read-only, with crafted payloads run against the guard
under both interpreters.

Verdict: **Fail**, with zero Blocker and one new Major. The reviewer numbered
its findings SEC-19 to SEC-21; they are recorded here as SEC-20 to SEC-22,
because SEC-19 already names the `command` key without the pass-through
(accepted).

**Resolved.** SEC-18: every document now says a value persisted with `setx`
reaches every host started later and must never be persisted. The original
SEC-17 attack is fixed: 64 KB of git words now blocks at 5.3 to 5.6 s. The
timeout exception is caught, and the labeled `break` from inside `catch`
works on both interpreters.

**New Major (SEC-20).** The clock is only read inside the regex loop, after
`ConvertFrom-Json` and the field walk have run unbounded. Neither can be
interrupted. A 2.9 MB payload of about 300,000 small objects, with the push
in `command`, had not exited after 20.9 s under pwsh, so the hook timeout
allowed it. At 1.95 MB the parse took 1.2 s and the walk 19.9 s; under
Windows PowerShell the whole run took 38.7 s.

**Minor (SEC-21).** The same walk blocks ordinary calls. 50,000 objects
around `git status --short` were blocked as not inspected in time after
6.5 s.

**Nit (SEC-22).** A `-TimeLimitSecond` outside `ValidateRange` exits 1, which
VS Code treats as a warning. Not reachable, because `hooks.json` passes no
arguments.

**Fix (`c02a784`).**

- A payload over 4 MB is blocked unscanned.
- A payload over 1 MB is not parsed and goes straight to the time-limited raw
  text scan.
- The walk stops after 20,000 values or half the time limit, and the raw text
  scan covers what it skipped.
- `-TimeLimitSecond` is clamped into range instead of validated.

Six new cases went red, then green. The three hook test files ran 540 passed,
0 failed. Under Windows PowerShell 5.1 and pwsh 7, the 2.9 MB payload now
blocks in 1.4 and 2.3 s, and no shape tried takes more than 5.7 s.

## 2026-10-02 fifth review of the hook fixes (c02a784)

Scope: `git diff caaf9a5 c02a784`. Read-only, with crafted payloads run on both
interpreters.

Verdict: **Fail**, with two new Majors. SEC-20 and SEC-22 are resolved: the
2.9 MB attack blocks in 2.6 s under pwsh and 1.5 s under Windows PowerShell,
every payload under 1 MB that was tried decided in 0.4 to 3.1 s, and an
out-of-range limit is clamped. 96 MB of standard input still blocks at 15.9 s.

**SEC-23 (Major).** Skipping the walk lost the one thing only the walk does:
it joins a command split across fields. `{"command":"git","args":["push"]}`
was allowed on both shells when padded past 1 MB, or when 60,000 values came
first, because the raw text keeps `"args":` between `git` and `push`.

**SEC-24 (Major, a regression).** Under pwsh one pattern scan of 3 MB takes
about 210 ms, against 23 ms under Windows PowerShell. So a benign write over
about 2.3 MB, with no command and no git text, was blocked as not inspected in
time. It had been allowed in 0.95 s at `caaf9a5`.

**SEC-25 (Nit).** A `-TimeLimitSecond` that is not a number still exits 1.

**Fix (`5009559`).**

- The raw text scan pulls the command-bearing fields out of the payload and
  joins them the way the walk does: as written with each value decoded, and
  from the decoded text for a key spelled with escapes.
- A text with neither `git` nor `gh` is not scanned.
- The decoded copy is made only when the payload holds an escape.
- The parameter is parsed leniently.

Six cases went red, then green, and the hook files ran 546 passed, 0 failed.

## 2026-10-02 sixth review of the hook fixes (5009559)

Verdict: **Approve.** SEC-23, SEC-24, and SEC-25 are resolved, and the diff
adds no Blocker or Major.

- The split push blocks at 1.14 MB, after 60,000 values, with fields between
  the parts, across nested objects, and with an escaped value.
- Benign writes of 2.3 to 3.9 MB pass in 1.4 to 1.6 s.
- The prefilter drops no text that a pattern could match.
- The field join fails closed on both of its timeout paths.
- No input tried caused catastrophic backtracking.

**SEC-26 (Major, pre-existing).** The walk and the raw join both join in
document order, so `{"args":["push","origin","main"],"command":"git"}` read as
`push origin main git` and was allowed even at 0.1 KB. A serializer that sorts
its keys writes that order, which makes this an accidental path, not an
evasion.

**SEC-27 (Nit).** The linear passes after the join never read the clock, so a
3.89 MB payload took 6.34 s.

**SEC-28 (Nit).** `"args":[["push"]]` cannot be joined; the walk misses it too.

**Residuals accepted.** Each is documented with the reviewer's wording:

- **(a)** A payload over 1 MB that names git on most lines can run out of time
  and be blocked. It fails closed, and no model writes a tool call that large.
- **(b)** A key spelled with escapes, combined with a value that hides the
  program behind an escaped quote, still evades the join. It is listed among
  the known evasions, with SEC-28.
- **(c)** Reading standard input is linear: about 120 MB would outlast the
  timeout.

**Fix (`97129d4`).** The walk and the raw join collect values in document
order and by kind. Both are scanned three ways: as written, executables before
arguments, and in reverse. The help lists the known evasions. The comments
bound the overrun at about 1.5 s and the standard-input read at about 120 MB.

## 2026-10-02 seventh review of the hook fixes (97129d4)

Verdict: **Fail**, with one new Major. SEC-26 is resolved: an args-first push
blocks walked, past the parse cap, and past the visit cap, and every earlier
block still holds. SEC-27, SEC-28, and the residuals are documented as asked.

**SEC-29 (Major, a regression).** The executables-first and reversed joins
were built from lists covering the whole payload. They paired one entry's
`git` with another entry's arguments, so ordinary batches were blocked with a
false reason. Examples:

- `[{docker,[push,myimage]},{git,[status,--short]}]` was blocked as a push.
- `[{make,[clean,-f,Makefile]},{git,[status]}]` was blocked as a forced clean.
- `[{npm,[test,--no-verify]},{git,[log,-1]}]` was blocked as a hook bypass.

All three were allowed at `5009559`.

**SEC-30 (Nit).** Three joins make a payload dense with git words reach the
quadratic patterns about 1.5 times sooner.

**Fix (`7ef639d`).**

- The walk joins each object's executables first on its own and keeps the
  payload-wide document-order join.
- The raw join starts a new object at a brace between two fields.
- The per-object joins are scanned as one text, kept apart by a line no
  pattern crosses.
- The reversed join is gone.

The three false blocks, plus one padded past 1 MB, went red, then green. The
hook files ran 555 passed, 0 failed.

Under pwsh, a 1.43 MB flood of 100,000 command fields now runs out of time and
is blocked (5.4 s); Windows PowerShell allows it in 1.2 s. The README documents
this beside residual (a).

## 2026-10-02 eighth review of the hook fixes (7ef639d)

Verdict: **Fail**, with one new Major. SEC-29 is resolved: all three batches
are allowed again, and SEC-26 holds for plain shapes.

**SEC-31 (Major, a regression).** The raw join started a new object at any
brace between two fields. A nested value or a brace inside a string looks the
same, so `{"args":["push","origin","main"],"x":{},"command":"git"}` was
allowed once the walk was skipped, past 1 MB or past the 20,000-value cap.
`97129d4` blocked it. This fails open on a push.

**SEC-32 (Nit).** A per-object join that ends in `-c` let `-c\s+\S+` swallow the
separator and reach the next entry.

**Residual accepted.** The pwsh flood is accepted as a fail-closed residual,
provided the README states the shell asymmetry and the batch size at which
pwsh starts blocking.

**Fix (`f897c75`).**

- The raw path also joins the fields across the whole payload, executables
  first and in reverse, because a brace in raw text cannot show reliably where
  an object ends. That errs toward blocking, like the rest of the raw path,
  and can pair one entry's executable with another entry's arguments. It
  applies only to payloads the walk cannot cover; walked payloads keep exact
  per-object joins.
- Each per-object join ends in `;`, which no option pattern can consume.

The README now states the measured threshold. Under pwsh, 16,000
`{command,args}` entries pass at 5.2 s and 32,000 are blocked at 5.4 s, while
Windows PowerShell allows 64,000 in 2.5 s. Four new cases went red, then green.

## 2026-10-02 ninth review of the hook fixes (f897c75)

Verdict: **Fail**, with one new Major. SEC-31 is resolved: all three brace
shapes block on both shells. SEC-32 is closed for the args-first spelling. The
command-first spelling still blocks through the document-order join, which has
blocked it since `5009559`; the reviewer kept that as a Nit, and it is
accepted. The reviewer accepted the raw-path design in principle, but not the
condition for entering that path.

**SEC-33 (Major, a regression).** The walk's cap counted every element of a
plain list. A 0.44 MB payload with two ordinary steps beside a 25,000-item file
list therefore fell onto the raw path, and its join across entries read
`docker git push myimage status`. It was blocked as a push on both shells,
although `7ef639d` had allowed it.

**Fix (`fea564f`).** Only fields and nested objects count toward the cap. Plain
values in arrays never hold a command field and are bounded by the walk's
clock alone. 400,000 numbers beside the batch are walked and allowed in 1.0 s
on Windows PowerShell and 1.2 s on pwsh. The new case went red, then green.

## 2026-10-02 tenth review of the hook fixes (fea564f)

Verdict: **Approve.** SEC-33 is resolved: the file-list batch is walked and
allowed on both shells, and an args-first push hidden in a 0.9 MB or 3.1 MB
payload of plain values still blocks. No change in the diff fails open, and
the heaviest payload of plain values tried, 480,000 numbers, finished in
4.27 s under pwsh.

**SEC-34 (Minor, open, introduced at `f897c75`).** The same listing written as
objects still exhausts the cap. A two-step batch beside 25,000
`{"p":...,"s":...}` records (0.74 MB) falls onto the raw path, where the join
across entries blocks it as a push that does not exist. The reviewer advised
against another round on the counting. Options for later:

- Make the raw brace scan depth-aware, so object boundaries are exact and the
  joins across the whole payload can go.
- Report a match from those joins with its own reason, so the user can tell a
  fabricated match from a real one.
