---
name: memory-bank
description: >-
  Initializes, repairs, checks, and safely migrates a repository Memory Bank
  with a minimal canonical file set, routed loading, evidence-based templates,
  retention rules, and additive role-specific extensions. Preserves existing
  files and migrates legacy role records by verified copy, never silent moves.
  USE FOR: initialize memory bank, create .memory-bank, missing memory bank,
  bootstrap project memory, create index.md, create projectbrief.md, create
  productContext.md, create activeContext.md, create techContext.md, create
  progress.md, create systemPatterns.md, create promptHistory.md, repair
  incomplete memory bank, check memory bank health, stale project memory,
  migrate legacy memory bank, namespace career/legal/tax records, old deadlines
  or session-log files, role-record migration.
  DO NOT USE FOR: read-only questions, clarifications, transient session notes,
  replacing an existing complete Memory Bank, VS Code native memory.
---

# Memory Bank

Initialize or repair version-controlled project knowledge without replacing
anything the repository already knows.

## Outcome

The repository has a minimal `.memory-bank/` base whose files are factual,
small, and ready for the shared Pre-flight and Post-flight Instructions. Any
role-specific schema defined by the active Custom agent remains additive.

## Trigger boundary

Use this Skill for either workflow:

1. **Initialization or repair:** durable repository work needs a missing
  `.memory-bank/` or canonical base file.
2. **Role-record migration:** the user asks to namespace legacy role records,
  or Career, Legal, or Tax finds a legacy direct-child file before creating a
  missing namespaced record.

Do not initialize a Memory Bank for Q&A, clarification, read-only investigation,
or transient work outside the repository. Do not create one merely because the
workspace was opened. Never run role migration from Customization installation
or update, and never scan OneDrive, the user profile, or another repository.

## Canonical base

| File | Purpose | Retention |
|---|---|---|
| `index.md` | Loading mode, authority order, and task routes | Stable; revise when routing changes |
| `projectbrief.md` | Purpose, scope, stakeholders, acceptance criteria | Stable; revise when project scope changes |
| `productContext.md` | User problem, workflows, experience goals | Stable; revise when product intent changes |
| `activeContext.md` | Current focus, evidence, next step | Overwrite; do not append history |
| `techContext.md` | Stack, environment, constraints, validation commands | Current facts only |
| `progress.md` | Recent milestones, stable capabilities, open work | Keep recent state; curate the oldest milestones on a `LineBudgetNearLimit` warning; use git/changelog for history |
| `systemPatterns.md` | Compact architecture map and Decision record index | Curate in place; store durable choices under `decisions/` |
| `promptHistory.md` | Optional local Substantive-turn intent log | Append; trim entries older than 90 days; may be gitignored |

`glossary.md` is optional. Create it only when the project needs an explicit
Ubiquitous Language; never invent Canonical terms merely to fill a template.
The initializer creates all eight table entries for a durable turn. Repository
health requires the seven version-controlled files; an absent local
`promptHistory.md` is valid in a clean checkout.

## Initialization workflow

1. Inspect the smallest reliable project anchors: root README, manifests,
   configuration, and current git state. Do not map the whole repository.
2. Create the canonical base by executing the bundled initializer from the
  repository root:

  ```powershell
  & "$HOME/.copilot/skills/memory-bank/scripts/Initialize-MemoryBank.ps1" -Path $PWD.Path
  ```

  The script supports `-WhatIf`, writes UTF-8 without BOM, reports each file as
  `Created` or `Preserved`, and never rewrites an existing file.
3. Create `.memory-bank/` only when the trigger boundary is met.
4. Create only missing canonical base files. Never overwrite, truncate, rename,
  or reformat an existing Memory Bank file during initialization.
5. Populate facts supported by repository evidence. Mark unresolved facts as
   `To confirm`; never infer stakeholders, requirements, or architecture.
6. If the active Custom agent defines role-specific Memory Bank files, treat
   that list as an additive schema. Create only files needed by the current
   durable role workflow. Do not initialize every agent's schema.
7. Read `index.md` and apply its routes before editing project artifacts. Read
  the complete base only when the index selects `loading-mode: full` or its
  fail-open conditions apply.

## Role-record migration

Migration is explicit, repository-scoped, and copy-only. The bundled map
classifies unambiguous files; `deadlines.md`, `session-log.md`, and
`documents-produced.md` return `NeedsAssignment` until the user chooses
`career`, `legal`, `tax`, `ManualSplit`, or `Skip`.

1. Generate an in-memory plan before creating an empty namespaced replacement:

  ```powershell
  $skillRoot = "$HOME/.copilot/skills/memory-bank"
  $planner = "$skillRoot/scripts/New-MemoryBankRoleMigrationPlan.ps1"
  $plan = & $planner -Path $PWD.Path
  ```

2. Ask the user to resolve every `NeedsAssignment` entry. Pass the resulting
  decisions as a hashtable and save the metadata-only plan:

  ```powershell
  $plan = & $planner -Path $PWD.Path -Assignment @{
     'deadlines.md' = 'tax'
     'session-log.md' = 'ManualSplit'
  } -SavePlan
  ```

3. Preview the complete plan. A conflict, changed source, path escape, reparse
  point, or unresolved assignment blocks every copy:

  ```powershell
  $applicator = "$skillRoot/scripts/Invoke-MemoryBankRoleMigration.ps1"
  & $applicator -Path $PWD.Path -PlanPath $plan.PlanPath -WhatIf
  ```

4. Apply only after explicit confirmation. The applicator uses exclusive,
  byte-exact copies, verifies SHA-256, preserves every source, and is
  idempotent. It has no deletion mode.

  ```powershell
  & $applicator -Path $PWD.Path -PlanPath $plan.PlanPath -Confirm:$false
  ```

Saved plans live under `.memory-bank/session/role-record-migration-<UTC>.json`
and contain paths, hashes, sizes, classifications, and decisions, never record
contents. Review `Unknown`, `ManualSplit`, and `Skipped` entries separately;
the migration leaves them untouched.

## Minimal templates

### `projectbrief.md`

```markdown
# Project brief

## Purpose

<Evidence-based purpose or `To confirm`.>

## Scope

- In scope: <known scope>
- Out of scope: <known boundary>

## Stakeholders

- <Known stakeholder or `To confirm`>

## Acceptance criteria

1. <Observable project outcome or `To confirm`>
```

### `productContext.md`

```markdown
# Product context

## Problem

<User problem supported by repository evidence or `To confirm`.>

## Users

- <Known user group or `To confirm`>

## Core workflows

1. <Known workflow or `To confirm`>

## Experience goals

- <Known goal or `To confirm`>
```

### `activeContext.md`

```markdown
# Active context

## Current focus

<Current task or `No active implementation task`.>

## Evidence

- <Known evidence>

## Next step

<One concrete next action or `Await the next task`.>
```

### `techContext.md`

```markdown
# Tech context

## Stack

- <Verified technology or `To confirm`>

## Environment

- <Verified runtime/tooling or `To confirm`>

## Constraints

- <Verified constraint or `To confirm`>

## Validation

- `<Known check>`
```

### `progress.md`

```markdown
# Progress

## Current status

<Evidence-based status or `To confirm`.>

## Recent milestones

- <Dated milestone when known>

## Stable capabilities

- <Verified capability>

## Open work

- <Known next item>
```

### `systemPatterns.md`

```markdown
# System patterns

## Architecture

<Verified architecture or `To confirm`.>

## Decisions

### Decision 1: Memory Bank initialized

- Choice: Use the canonical Memory Bank base.
- Rationale: Preserve durable project context across sessions.
```

### `promptHistory.md`

```markdown
# Prompt history

Substantive turns only. Format:
`YYYY-MM-DD HH:mm UTC | <agent-name> | <one-line intent>`.
Trim entries older than 90 days.
```

## Role-specific extensions

The active Custom agent may define domain files such as case registries,
incident logs, threat models, investigation dossiers, article registries, or
training module registries. Preserve that schema exactly. Base files are shared;
role files are owned according to the active agent's isolation rules.

Do not create role files for agents that are not active. Do not merge unrelated
role records into `progress.md` or `systemPatterns.md`.

## Memory Bank topics

The optional `.memory-bank/topics/` directory holds durable task-specific or
role-specific knowledge that no canonical or active role file owns. Create a
Memory Bank topic only when an index route or active Custom agent can select it
explicitly. Require `status`, `last-verified`, `owner`, and `source` metadata;
never load the directory wholesale or duplicate repository source.

## Safeguards

- Never overwrite or silently normalize an existing file.
- Never move, merge, split, or delete a legacy role record during migration.
- Never put role-record contents in a migration plan or tool argument.
- Never store passwords, tokens, private keys, or unredacted secrets.
- Keep sensitive legal, tax, career, security, and personal data scoped to the
  repository and follow the active agent's retention rules.
- Keep curated Memory Bank knowledge version-controlled. Local ephemera such as `promptHistory.md` and session handoff files may be excluded by repository policy; initialization must not alter existing ignore rules.
- Initialization is not permission to rewrite stale content. Report conflicts
  and handle curation as a separate, evidence-backed change.

## Red flags

- About to create a Memory Bank during a read-only task.
- About to replace an existing file with a generic template.
- Filling unknown fields with plausible but unsupported claims.
- Creating every role-specific schema in one repository.
- Recording secrets or personal data beyond the repository's stated need.

When a red flag fires, stop initialization and preserve the repository state.

## Verification

Run the health check before reporting initialization complete, and again after
any turn that edits a Memory Bank file. The append mandated by the shared
Post-flight gate is the path that breaches a line budget, so an initialization
gate alone never sees it:

```powershell
& "$HOME/.copilot/skills/memory-bank/scripts/Test-MemoryBankHealth.ps1" -Path $PWD.Path
```

Routing has two separate checks. `Test-MemoryBankRouting.ps1` proves that
human-labelled routes resolve the required files without losing the compactness
benefit. `Invoke-MemoryBankRouteSelectionEval.ps1` tests the prior question:
whether a fresh model infers those routes from the natural-language task.

```powershell
$workDir = Join-Path $env:TEMP 'memory-bank-route-selection'
$evalFile = './Skills/memory-bank/evals/routing-cases.json'
$script = './Skills/memory-bank/scripts/Invoke-MemoryBankRouteSelectionEval.ps1'

& $script -Mode Prepare -Path $PWD.Path -EvalFile $evalFile `
  -WorkDir $workDir -Repetitions 3
# Run each *.prompt.txt in a fresh context and save its exact JSON reply as
# the matching *.out.json file.
& $script -Mode Grade -Path $PWD.Path -EvalFile $evalFile `
  -WorkDir $workDir -Repetitions 3
```

Prepare mode never sends a model request. Grade mode requires strict JSON and
splits the verdict from the cost. A reply is safe when it misses no labelled
route, so a superset costs context rather than correctness — the same criterion
the deterministic resolver uses when it counts critical-file misses. `Passed =
True` means every repetition of every case selected safely.

Safety alone is gameable: a reply naming every route never misses. Read
`PrecisionPercent` and `ExtraRouteCount` next to `Passed`, because that is where
the degenerate strategy shows up. `RecallPercent` reports how much of the
labelled context survived, and `ExactReplies` counts the replies that matched
the label with nothing added.

- All seven required files exist and are non-empty; local `promptHistory.md`
  exists when the initializer ran for the current durable turn.
- The health result reports `Passed = True` and no error findings.
- A `LineBudgetNearLimit` warning is a curation task, not noise. Trim that file
  in the same turn; the next append turns the warning into a failing build.
- Files that existed before initialization are byte-for-byte unchanged.
- New content contains no unresolved template angle brackets.
- Role-specific files match only the active agent's schema.
- `git status --short` lists only the intended new files.
- The shared Post-flight Definition of Done gate is satisfied.

The templates above show field intent. The bundled initializer writes
evidence-safe `To confirm` values, not angle-bracket placeholders.
