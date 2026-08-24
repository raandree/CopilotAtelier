# AGENTS.md — House rules for CopilotAtelier

Portable operating rules for any AI agent or agentic tool (GitHub Copilot, Claude Code, Codex, Cursor, Copilot CLI, and other AGENTS.md-aware harnesses) working in this repository. This file is the tool-neutral entry point; the authoritative, auto-loaded detail lives in [`Instructions/`](Instructions/) and [`.memory-bank/`](.memory-bank/).

CopilotAtelier is a portable GitHub Copilot customization toolkit distributed as a PowerShell module: custom agents ([`Agents/`](Agents/)), auto-applied coding instructions ([`Instructions/`](Instructions/)), on-demand skills ([`Skills/`](Skills/)), prompt templates ([`Prompts/`](Prompts/)), and lifecycle hooks ([`Hooks/`](Hooks/)), deployed by `Install-CopilotAtelier` or, from a clone, by [`Setup-CopilotSettings.ps1`](Setup-CopilotSettings.ps1).

## Every turn: pre-flight, then post-flight

This repo enforces a discovery-first, close-out-clean contract on every substantive turn.

**Pre-flight** (before the first tool call) — see [`Instructions/preflight.instructions.md`](Instructions/preflight.instructions.md):

1. Probe for `.memory-bank/` (`list_dir` / `file_search` / `Test-Path`). The workspace summary is not authoritative for dotfolders — do not conclude "no Memory Bank" without probing.
2. Read `.memory-bank/index.md`, then apply its task routes. Only the index is unconditional; `promptHistory.md` is local ephemera limited to interaction-history analysis and Memory Bank evals. Fail open to the complete available base when the index says `loading-mode: full` or routing is unsafe. Seven files are required and version-controlled; include local `promptHistory.md` and optional `glossary.md` when present. For durable writes, load the `memory-bank` Skill and create only missing files before the first project edit. Never overwrite existing files. Do not initialize for Q&A, clarification, read-only work, or transient preferences.
3. Match `Instructions/*.instructions.md` by `applyTo` against files you will touch; read each match.
4. Match `Skills/**/SKILL.md` by description against the task; read each match.
5. Do not append `promptHistory.md` at pre-flight. Post-flight owns the append for substantive turns; routine pre-flight does not read it.
6. Open the reply with a UTC timestamp `[YYYY-MM-DD HH:mm UTC]` plus a one-line PRE-FLIGHT acknowledgment.

**Post-flight** (before ending the reply) — see [`Instructions/postflight.instructions.md`](Instructions/postflight.instructions.md):

Classify the turn first. A **non-impacting** turn (pure Q&A, read-only investigation, a self-documenting git commit/merge) skips steps 1–4 and emits only `POST-FLIGHT: n/a — non-impacting turn (<reason>)`. A **substantive** turn (a file changed, a durable decision emerged, the user asked to record, a bug was found, or a tag was cut) runs all steps:

1. Verify the change (parse / lint / build / tests). Markdown-only edits: state "no executable verification required."
2. Update the Memory Bank (`activeContext.md`, `progress.md`, `promptHistory.md`).
3. Update `CHANGELOG.md` under `[Unreleased]` for any user-visible change.
4. Commit locally on an `ai/<slug>` branch with a conventional-commit message plus a `Co-authored-by: AI Assistant <ai@example.com>` trailer, unless the user explicitly requested uncommitted changes.
5. Clear the deployed Definition of Done gate: acceptance criteria, role-specific gates, focused/final validation, self-review, risk-triggered independent review, security, and residual-risk reporting.
6. Emit a `[x]/[ ]` POST-FLIGHT checklist.

## Never push

**Never run `git push`** (or any remote-mutating git operation) unless the user explicitly asks in the current turn. Local commits and branches are fine; pushing, force-pushing, and PR creation require explicit per-turn authorization. Do not bypass hooks (for example `--no-verify`).

This rule is backed by a deterministic guardrail, not only by trust. The `PreToolUse` hook in [`Hooks/`](Hooks/) blocks push, `--no-verify`, `git reset --hard`, forced clean, and GitHub CLI resource mutation with exit code 2. It matches patterns in the command string, so treat it as defense in depth that removes the accidental path rather than as a containment boundary — the rule above still binds you. When the user authorizes a remote mutation, set `COPILOT_ATELIER_ALLOW_REMOTE=1` for that command and unset it afterwards. Never rewrite a command to evade the check.

## Build

- The repository is a [Sampler](https://github.com/gaelcolas/Sampler) project. Module sources live in `source/`; the customization directories stay at the repository root and are copied into the built module by the `Copy_Customizations_To_Output` task in [`.build/`](.build/).
- Build and test with `./build.ps1 -Tasks build` and `./build.ps1 -Tasks test`, always through the detached launcher. Add `-ResolveDependency` on the first run.
- Versioning is GitVersion via [`GitVersion.yml`](GitVersion.yml). Never hand-edit `ModuleVersion` in [`source/CopilotAtelier.psd1`](source/CopilotAtelier.psd1); the build replaces it.
- Add a new public command as `source/Public/<Verb-Noun>.ps1`, list it in `FunctionsToExport`, give it full comment-based help, and add `tests/Unit/Public/<Verb-Noun>.Tests.ps1`. The QA suite in [`tests/QA/module.tests.ps1`](tests/QA/module.tests.ps1) enforces all four.
- CI runs in GitHub Actions ([`.github/workflows/ci.yml`](.github/workflows/ci.yml)) and follows the same build/test/deploy shape as the other Sampler repositories. Deployment needs the `GitHubToken` and `GalleryApiToken` repository secrets.

## PowerShell

- **Approved verbs only.** Every function uses a verb from `Get-Verb` (`Get`, `Set`, `New`, `Test`, `Invoke`, `Remove`, and so on). No `Retrieve` / `Delete` / `Change`.
- `[CmdletBinding()]` on advanced functions; validate parameters (`[ValidateNotNullOrEmpty()]`, `[ValidateSet()]`, `[ValidatePattern()]`).
- `-ErrorAction Stop` plus try/catch for anything that must not silently fail; `[PSCredential]` / `SecureString` for secrets, never plaintext.
- Full detail: [`Instructions/powershell.instructions.md`](Instructions/powershell.instructions.md) and [`Instructions/powershell-execution-safety.instructions.md`](Instructions/powershell-execution-safety.instructions.md).

## Pester-first

- Tests are **Pester 5**. Write or update the test alongside the code — do not ship script changes without covering tests.
- Run Pester through the fully detached cross-platform launcher to avoid freezing the editor (see [`Instructions/powershell-execution-safety.instructions.md`](Instructions/powershell-execution-safety.instructions.md)); helper functions used inside `It` live in `BeforeAll`.
- Patterns: [`Skills/pester-patterns/`](Skills/pester-patterns/); conventions: [`Instructions/pester.instructions.md`](Instructions/pester.instructions.md).

## Authoring agents, skills, instructions, prompts

- Follow [`Instructions/copilot-authoring.instructions.md`](Instructions/copilot-authoring.instructions.md): correct frontmatter per file type, narrow `applyTo`, purposeful emphasis, no maintenance footers.
- New skills follow the `skill-creator` skill: third-person `description` ≤ 1024 chars with `USE FOR:` / `DO NOT USE FOR:`, body ≤ 500 lines, references one level deep, folder name matching the `name:` field. Declare `compatibility` whenever the skill needs a specific OS, runtime, module, or binary.
- Encode a rule as a hook when it must hold regardless of what the model decides; leave judgement calls in Instructions.
- When building agents, LLM features, or MCP servers, run the `agent-security-review` skill (lethal-trifecta test, OWASP Top 10 for LLM Applications, containment-first); measure skill/prompt/agent changes with the `agent-evals` skill.
- Markdown must lint clean (see [`Instructions/markdown.instructions.md`](Instructions/markdown.instructions.md)).
- If a `glossary.md` exists in `.memory-bank/`, use only its canonical terms (Ubiquitous Language).

## Atomic change sets

A Customization is not one file. Ship the whole set in a single commit — a
half-added Skill leaves the catalogue, the trigger coverage, and the changelog
disagreeing with each other, and only some of that drift is caught by CI.

**Adding a Skill:**

1. `Skills/<name>/SKILL.md` — folder name matching the `name:` field.
2. `Skills/agent-evals/assets/trigger-queries.<name>.json` — labelled positives
   plus near-miss negatives taken from *sibling Skills*, both splits populated.
   If it will not be measured yet, add the Skill to `$uncoveredSkillBaseline`
   in [`tests/SkillTriggerCoverage.Tests.ps1`](tests/SkillTriggerCoverage.Tests.ps1)
   instead, and say why.
3. `README.md` — a row in the *Available Skills* table.
4. `CHANGELOG.md` — an entry under `[Unreleased]`.

**Adding a Custom agent:**

1. `Agents/<Name>.agent.md` — `name`, `description`, and a `model` priority
   array whose last entry is a GA model.
2. [`tests/SharedLifecycle.Tests.ps1`](tests/SharedLifecycle.Tests.ps1) — the
   per-agent expectation map.
3. `Agents/README.md` and `CHANGELOG.md`.

**What CI enforces**, so you find the drift before review does:

| Gate | Test |
|---|---|
| Skill name, description cap, body budget | [`tests/SkillFrontmatter.Tests.ps1`](tests/SkillFrontmatter.Tests.ps1) |
| Skill conformance against the open specification | [`tests/SkillsRefValidate.Tests.ps1`](tests/SkillsRefValidate.Tests.ps1) |
| Trigger coverage, query schema, orphaned query sets | [`tests/SkillTriggerCoverage.Tests.ps1`](tests/SkillTriggerCoverage.Tests.ps1) |
| README catalogue rows against shipped Skills | [`tests/SkillCatalogue.Tests.ps1`](tests/SkillCatalogue.Tests.ps1) |
| Agent, Instruction, and Prompt frontmatter | [`tests/CustomizationFrontmatter.Tests.ps1`](tests/CustomizationFrontmatter.Tests.ps1) |
| Plugin manifest shape and version | [`tests/PluginManifest.Tests.ps1`](tests/PluginManifest.Tests.ps1) |
| Committed credentials | [`tests/SecretScan.Tests.ps1`](tests/SecretScan.Tests.ps1) |

## Model

Agents declare `model` as a priority array: `['Claude Opus 5 (copilot)', 'Claude Opus 4.8 (copilot)']`. The first available model wins, so the last entry must always be a GA model. When bumping models, update every agent frontmatter and reflect the change in the Memory Bank.
