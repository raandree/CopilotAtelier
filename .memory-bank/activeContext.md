---
status: current
last-verified: 2026-08-14
owner: software-engineer
source: current task evidence
---

# Active context

## Current focus

Packaged a repeated workflow as a Skill. A project brand identity was produced
by hand twice in one session, and the second run rediscovered the same failures
as the first, which is the signal that a procedure belongs in a Skill rather
than in a conversation.

## Implemented

- `Skills/brand-logo-system/SKILL.md` — 192 lines. Carries the eleven-slot
  shared-library layout, the rule that a mark is recovered from a project's
  existing artwork by pixel count before anything is designed, the
  dark-mode-means-reversed convention, and a verification gate that is measured
  rather than eyeballed.
- `Skills/brand-logo-system/scripts/Export-BrandLogoSet.ps1` — composes all
  eleven slots from one `.psd1` definition plus two or three glyph fragments,
  so a project's only bespoke artwork is its glyph. Rasterizes through headless
  Microsoft Edge.
- `Skills/agent-evals/assets/trigger-queries.brand-logo-system.json` — ten
  positives and ten near-miss negatives, both splits populated. The negatives
  come from sibling Skills that share vocabulary but not intent:
  `windows-gui-screenshot-capture`, `marp-slide-overflow`, `sampler-framework`
  ("add an IconUri"), `pswritehtml-reporting`, and a rendering bug that belongs
  to `debugging-and-error-recovery`.
- `README.md` and `CHANGELOG.md` — the remaining two artifacts of the Skill
  atomic change set.
- `Prompts/brand-logo.prompt.md` — starts the process the Skill executes. It
  searches for an existing mark before asking anything, then interviews in two
  `vscode_askQuestions` clusters (subject, treatment, character; colour source,
  wordmark split, delivery target) and proposes 256 px concept proofs before any
  asset set is built.

## Focused evidence

- `SkillFrontmatter`, `SkillsRefValidate`, `CustomizationFrontmatter`,
  `SkillTriggerCoverage`, `TriggerEvalHarness`, `SecretScan`: 438 passed,
  0 failed, 60 skipped, run detached.
- The first run of that set failed exactly one test,
  `brand-logo-system has a trigger-query set`. The atomic-change-set gate fired
  on its own author, which is the strongest evidence the gate works.
- End-to-end proof against `C:\Git\AutomatedLab`: eleven assets rendered, slot
  numbers matching a sibling project, canvases exactly 1536x1024 or 1254x1254,
  corner alpha 0 on the six transparent slots and 255 on the five opaque ones,
  no transparent slot touching its canvas edge, horizontal skew within 3 %.
- The AutomatedLab palette and gear-and-flask mark were recovered from that
  project's own 2025 logo by counting pixels, not invented. Five colours carry
  percentage-level shares; everything else is anti-aliasing.

## Open findings

- **The query set is authored but unmeasured.** Same caveat as the five sets
  before it: the gate proves the queries exist, not that the description
  triggers. It has not been through `run-trigger-evals.ps1`.
- **The board's cell numbering does not match the file slot numbering.** Cells
  order dark variants first, then light; files pair dark and light per type.
  Every sibling board in the library shares the quirk, so it was kept for family
  consistency rather than corrected.
- **`WindowsAccessControl` was rendered by a repository-local script, not by
  this Skill**, and its slots 1 and 2 use the older ink-variant reading of
  dark/light rather than reversed-for-dark. Two sets in one library therefore
  disagree on what "dark mode" means. Migrating it to a brand definition would
  settle it.
- The README *Available Skills* table still has no gate. This change added its
  row because the atomic checklist says so, not because CI would have caught the
  omission.
- `Skills/german-employment-law/` is still an empty untracked folder shipping no
  `SKILL.md`.
- **The `skill-creator` description edit is still not proven.** Train climbed to
  100 % while validation fell, which is the overfitting signal. It remains for
  the owner to accept or revert.

## Next step

Sweep `brand-logo-system` through `run-trigger-evals.ps1` together with the five
unmeasured sets, and decide the `WindowsAccessControl` migration — it is the
only thing keeping two definitions of "dark mode" in one library.
