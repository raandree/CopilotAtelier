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

- **2026-08-11**: `run-trigger-evals.ps1 -Mode Execute` probes `Invoke-Shp` for
  `-Temperature` and throws once instead of failing 54 calls in the binder. It
  tests the parameter, not the version: `0.4.0-preview0003` reports `0.4.0`, so
  the Skill's own "0.4.0 or later" claim passed the build that fails. The
  machine now carries `0.4.0-preview0005`, built with `$env:ModuleVersion`
  because this host has no GitVersion and Sampler otherwise stamps `0.0.1`.

- **2026-08-11**: Audited the customization library against the live upstream
  sources and closed six gaps. The category-level `USE FOR:` rewrite had
  conflated two different upstream rules — the specification wants domain
  keywords, only failed-query wording overfits — which is what `pos-09` had been
  paying for; the rule now reads "keep the domain vocabulary, drop the
  failed-query wording" in all four files. `skill-creator` gained the fifth
  upstream authoring page it never cited, `using-scripts`, plus a pointer to the
  optional frontmatter fields. The primer's "third person, always"
  contradiction and its Anthropic-first source list are fixed. Three guards
  landed: `plugin.json` is validated for the first time, including version drift
  and the `$schema`-versus-capital-`Skills` trap, and the over-budget Skill
  baseline and the near-cap descriptions both became per-Skill high-water marks.

- **2026-08-11**: Pinned the trigger-eval judge and re-measured `skill-creator`.
  `run-trigger-evals.ps1` gained `-Temperature` (omit-or-send) plus 7 tests.
  Paired sweeps, same 44-skill catalogue and description: pinned at 0 gave train
  10/10 and validation 6/8; unpinned gave 10/10 and 5/8. So 13 points of
  validation was sampler noise — `pos-06` scored 1.00 pinned and 0.33 unpinned,
  and would have been "fixed" by editing a description that already worked. Two
  failures survive pinning: `pos-07` (a German request) at 0 of 3 and `pos-09`
  ("one skill or split into references?") at 1 of 3, both plausibly the cost of
  the category-level `USE FOR:` rewrite. Method findings: the installed
  ShellPilot `0.4.0` predates `Invoke-Shp -Temperature`, so import a newer build
  by path; `-Temperature 0` reduces but does not remove variance; and the grader
  scores a prose reply like a wrong selection. An earlier validation 7/8 figure
  is withdrawn — its `-SkillRoot` was the repository root, duplicating every
  skill via `output/`.

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
  routing gate reported `49.57 %` against its `50 %` floor, because
  `activeContext.md` is routed into 23 of 25 baseline cases.

- **2026-08-11**: Corrected `windows-gui-screenshot-capture`, prompted by a live
  "screenshot the Edge window" request the Skill answered wrongly twice. Its
  "GPU-composited content returns solid black" verdict had generalised a
  WebView2 measurement to all of Chromium; on Windows `10.0.26200` with Edge
  `151.0.4129.72`, `PW_RENDERFULLCONTENT` painted a full 2560x1540 frame first
  try. Step 2 now separates a hosted control from an application's own top-level
  frame and prescribes attempt, validate, escalate. `scripts/WindowCapture.ps1`
  adds the branch for a window the user already had open, with 13 new tests.

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
  in the same brief is no barrier, so expected values go in a separate file the
  reviewer opens deliberately; agreement under exposure counts weaker than
  disagreement.

- **2026-08-04**: Added `Skills/gilb-requirements-engineering`, covering Tom and
  Kai Gilb's method: Planguage `Scale` and `Meter` quantification, Impact
  Estimation Tables, Evo step planning, and Specification Quality Control.
  `grill-me` elicits; this Skill quantifies, and both cross-reference the other.

- **2026-08-01**: Hardened the release path and the `progress.md` append that
  had broken CI twice. `[Unreleased]` is capped before the GitHub release call,
  the deploy job verifies both secrets, a budget breach warns at 90 percent
  rather than failing at 100, and Post-flight curates the oldest entries in the
  same edit. `CHANGELOG.md` holds the three failures behind it. `GitHubToken`
  has since been added, and the release job has tagged every build from
  `v3.0.0-preview0003` on.

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
