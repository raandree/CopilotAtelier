---
status: current
last-verified: 2026-08-11
owner: software-engineer
source: CHANGELOG.md and git history
---

# Progress

## Project status

Copilot Atelier is released at `v1.1.0`. The next release is `2.0.0`, the first
published to the PowerShell Gallery. Incremental work is tracked under
`[Unreleased]` in `CHANGELOG.md`.

## Recent milestones

- **2026-08-11**: Audited the Agent Skills guidance refresh and remediated it.
  The content held up — no truncation, no encoding drift, both upstream sources
  re-verified — but the process did not: committed and pushed against a standing
  "do not commit", no Memory Bank or changelog entry, and a harness run left 108
  scratch files inside the published `Skills/` payload that `Copy-Item -Recurse`
  would have shipped to the Gallery. The `skills-ref` gate was real locally and
  inert in CI, because nothing installed `uv` there. Now closed: scratch is
  ignored and pruned, CI installs `uv` and the gate throws rather than skips, a
  negative fixture proves it rejects a bad `name`, and `agent-evals` declares
  the dependencies it had silently acquired. The handoff's "CHANGELOG.md does
  not parse" premise was false throughout — all four supposed pre-existing
  failures pass under `build.ps1` and appear only under a bare `Invoke-Pester`.

- **2026-08-11**: Returned `main` to green after two of three CI matrix legs
  failed. The heartbeat cancellation test used `Start-Process -WindowStyle`,
  which raises `NotSupportedException` on non-Windows PowerShell, so no local
  Windows run could reproduce it; the shipped launcher had guarded the same
  parameter from the start. The standing risk is the preceding failure: the
  routing gate reported `49.57 %` against its `50 %` floor with roughly 1 KB of
  headroom, because `activeContext.md` is routed into 23 of 25 baseline cases.

- **2026-08-11**: Corrected `windows-gui-screenshot-capture`, prompted by a live
  "screenshot the Edge window" request the Skill answered wrongly twice. Its
  "GPU-composited content returns solid black" verdict had generalised a
  measurement of a hosted WebView2 control to all of Chromium; measured on
  Windows `10.0.26200` with Edge `151.0.4129.72`, `PW_RENDERFULLCONTENT`
  painted a full 2560x1540 frame on the first attempt. Step 2 now separates a
  hosted control from an application's own top-level frame and prescribes
  attempt, validate, escalate. The Skill also had no branch for a window the
  user already had open, where nothing may be launched or closed;
  `scripts/WindowCapture.ps1` implements it as the inverse-lifecycle sibling of
  `DialogCapture.ps1`, with 13 new tests.

- **2026-08-10**: `long-running-job-monitor` gained an unprompted chat
  heartbeat. Measured that an async command's completion notification spawns an
  agent turn with no user input, disproving the Skill's own claim that the agent
  cannot self-schedule. `Start-JobHeartbeat.ps1` arms one tick and emits a
  measured summary, backed by a metadata-only state file that stores no probe
  scriptblock because it is re-read and acted on at every wake. Live smoke tests
  proved the wake chain and exposed a missing cancel, so `-Stop` now kills a
  pending tick after matching the recorded process start time.

- **2026-08-07**: `pandoc-docx-export` now carries the grey shading Word drops
  silently. Pandoc maps block quotes to `BlockText` and inline code to
  `VerbatimChar` correctly, but neither style has a fill in the stock reference
  document, so the preview's distinction is lost without warning. Recipe 3
  gained both `w:shd` patches and an output-side count of the two styles;
  gotcha #6 records that `w:pPr` and `w:rPr` are ordered sequences, that `[xml]`
  parsing cannot catch an order violation, and that only a headless LibreOffice
  conversion to PDF proves the file opens.

- **2026-08-06**: `subagent-dispatch` gained the mirror image of its
  no-pre-judging rule: never hand a re-performer the answer. A "sealed" section
  at the end of the same brief is not a barrier — the brief arrives as one text,
  so expected values go in a separate file the reviewer opens deliberately, and
  agreement under exposure counts weaker than disagreement.

- **2026-08-04**: Added `Skills/gilb-requirements-engineering`, the first
  Customization covering Tom and Kai Gilb's method: Planguage `Scale` and
  `Meter` quantification, Impact Estimation Tables, Evo step planning, and
  Specification Quality Control, in a 322-line body plus four references.
  `grill-me` elicits; this Skill quantifies, and both cross-reference the other.

- **2026-08-01**: Bounded the append that keeps breaking CI. The Post-flight
  Instruction mandates a `progress.md` append every substantive turn and set no
  limit, so the file grew until the health check errored — twice. Step 2 now
  requires curating the oldest entries in the same edit when the file is at or
  near its budget, `Skills/memory-bank/SKILL.md` runs the health check after any
  Memory Bank edit rather than only after initialization, and
  `sampler-build-debug` gained a "Reproduce a CI-Only Failure" section: derive
  the built commit from the GitVersion `+n` suffix, test a clean clone, and
  never hard-code a version sentinel that can equal Sampler's `0.0.1` fallback.

- **2026-08-01**: Hardened the release path after three related failures. The
  `2.0.0` release was rejected with `422 body is too long` because Sampler sends
  the `[Unreleased]` section as the body and it had reached 143697 of GitHub's
  125000 characters; `tests/QA/module.tests.ps1` now fails at 100000. The
  Gallery then rejected `3.0.0-preview0001` with HTTP 409 because the release
  that shipped it was never tagged: `Publish_Release_To_GitHub` writes the tag
  the version anchors on and skips itself when `GitHubToken` is empty, while the
  Gallery publish still runs. The deploy job now verifies both secrets, and
  `GitHubToken` still has to be added to the repository. The third was this file
  reaching 220 of its 200 budgeted lines, so `Test-MemoryBankHealth.ps1` now
  warns at 90 percent of any budget rather than failing CI at 100.

- **2026-08-01**: Audited `german-tax-research` against the statutory text in
  force, correcting the `§ 237 AO` AdV interest rate, the `Art. 97 § 36 EGAO`
  overrides for VZ 2020 to 2024, the `§ 238 Abs. 1c AO` interval, and the VZ
  2025 childcare rule. Every cited BFH docket verified clean.

- **2026-07-30**: Added `evidence-package-assembly` and `subagent-dispatch`
  (Skill count 40 → 41), dropped the Windows PowerShell 5.1 CI leg, and
  migrated the repository to a Sampler-built PowerShell module distributed
  through the PowerShell Gallery (Decision 18). Detail in `CHANGELOG.md`; CI
  rules live in `techContext.md`.

## Stable capabilities

- Deterministic lifecycle hooks that block remote mutation and prove Memory Bank
  presence without relying on model compliance.
- Screenshot documentation for modifiable Windows applications, existing or
  third-party executables without source access, and windows the user already
  has open.
- One-command, idempotent Setup script with Windows, macOS, and Linux path
  handling.
- One Canonical target exposed through `~/.copilot` Discovery links, with
  opt-in Claude Code and Agent Skills links.
- Agent plugin packaging for installation from a Git URL.
- Role-specific Custom agents with Agent-to-agent handoffs, model priority
  arrays, and explicit subagent eligibility.
- File-scoped Instructions and on-demand Skills with declared environment
  requirements.
- Prompt templates for repeatable development, research, legal, and operations
  workflows.
- Detached Pester and build execution with persistent completion evidence.
- Test-first behavior changes, regression guards, risk-scaled review, and
  agentic-security checks.
- Routed Memory Bank loading with deterministic non-inferiority, health,
  provenance, compactness, and rollback checks.

## Open work

- Split the ten Skills on the `SkillFrontmatter` over-budget baseline into
  bodies under 500 lines plus one-level references, removing each from the
  baseline as it lands.
- Continue splitting oversized auto-applied Instructions into concise enforced
  rules plus on-demand Skill references where that can be done without losing
  behavior.
- Keep Custom agent bodies within explicit prompt budgets and add deterministic
  regression checks for other frequently used agents.
- Extend the routing eval set when real retrieval failures are observed.
- Add Markdown linting to continuous integration when the required runtime is
  available.
- Review model identifiers when Copilot model availability changes; the last
  entry of every agent `model` array must stay GA.
- Evaluate the remaining VS Code surfaces that no Customization covers yet:
  the agent host and its harness selection, `chat.assistedPermissions.enabled`,
  and organization-level instructions and agents.
- Address the deferred Minor review findings in `Set-CustomizationLink`: the
  `Read-Host` prompt hangs an unattended run, a child present in both source and
  target is discarded rather than compared, and `Copy-Item -Recurse` may follow
  a child reparse point.
- Curate `techContext.md` and `systemPatterns.md` when either approaches its
  line budget. `techContext.md`'s per-test-file inventory duplicates `tests/`
  and conflicts with the file's own "do not duplicate changing inventories"
  rule.

## Retention policy

This file keeps current state and recent milestones only. `CHANGELOG.md` and git
history are the authoritative sources for older implementation detail, release
history, and superseded decisions.

Curate the oldest milestones as soon as `Test-MemoryBankHealth.ps1` reports
`LineBudgetNearLimit` for this file. Waiting for `LineBudgetExceeded` means the
breach is discovered by a red CI build rather than by a local run.
