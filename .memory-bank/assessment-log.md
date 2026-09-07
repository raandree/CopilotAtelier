---
status: current
last-verified: 2026-09-07
owner: security-reviewer
source: security assessments of this repository
---

# Assessment log

Episodic record of completed security assessments. One entry per assessment:
date, scope, verdict, and the findings that outlived the review. Retain two
years; archive older entries to a dated Memory Bank topic.

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
