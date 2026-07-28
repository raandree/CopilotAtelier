# AGENTS.md — House rules for CopilotAtelier

Portable operating rules for any AI agent or agentic tool (GitHub Copilot, Claude Code, Codex, Cursor, Copilot CLI, and other AGENTS.md-aware harnesses) working in this repository. This file is the tool-neutral entry point; the authoritative, auto-loaded detail lives in [`Instructions/`](Instructions/) and [`.memory-bank/`](.memory-bank/).

CopilotAtelier is a portable GitHub Copilot customization toolkit: custom agents ([`Agents/`](Agents/)), auto-applied coding instructions ([`Instructions/`](Instructions/)), on-demand skills ([`Skills/`](Skills/)), prompt templates ([`Prompts/`](Prompts/)), and lifecycle hooks ([`Hooks/`](Hooks/)), synced across machines by [`Setup-CopilotSettings.ps1`](Setup-CopilotSettings.ps1).

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

## Model

Agents declare `model` as a priority array: `['Claude Opus 5 (copilot)', 'Claude Opus 4.8 (copilot)']`. The first available model wins, so the last entry must always be a GA model. When bumping models, update every agent frontmatter and reflect the change in the Memory Bank.
