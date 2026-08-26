# Definition of Done

The standing quality bar every change in this repository clears before it counts as complete — independent of *what* the change is. It is distinct from a task's **acceptance criteria**, which describe when one specific goal is met. A change ships only when it satisfies **both** its acceptance criteria **and** this Definition of Done.

This repository reference explains the deployed [Post-flight Definition of Done gate](../com.github.copilot/rules/postflight.instructions.md#definition-of-done-gate). The Post-flight Instruction is authoritative because it is copied to the Canonical target; this file must not define a competing checklist.

## Definition of Done vs acceptance criteria

| Aspect | Definition of Done | Acceptance criteria |
|---|---|---|
| Scope | Every change, project-wide | One specific task |
| Stability | A standing team standard; changes rarely | Written fresh per task |
| Answers | "Is this change fit to ship at all?" | "Did this task meet its goal?" |
| Example | markdownlint clean, Memory Bank updated, committed locally | "the export skill handles recurring appointments" |

Neither replaces the other. A feature that meets its acceptance criteria but skips verification, or lints clean but was never recorded in the Memory Bank, is **not done**.

## The standing bar

### 1. Process — every turn

- [ ] **Pre-flight** complete: `.memory-bank/` probed; canonical base read or safely initialized for durable writes; matching Instructions and Skills loaded once; reply opened with a UTC timestamp and acknowledgment. Read-only turns do not initialize. See [`preflight.instructions.md`](../com.github.copilot/rules/preflight.instructions.md).
- [ ] **Post-flight** complete: acceptance criteria and role-specific gates satisfied; focused/final validation and self-review complete; independent review performed when risk requires it; Memory Bank and changelog updated; version-control constraints honored; residual risks reported. See [`postflight.instructions.md`](../com.github.copilot/rules/postflight.instructions.md#definition-of-done-gate).

### 2. Verification — proof, not "looks right"

Name the artifact that proves the change works. By file type:

- **PowerShell** (`.ps1` / `.psm1` / `.psd1`): AST parses without error; PSScriptAnalyzer reports no warnings; only approved verbs (`Get-Verb`); Pester tests written alongside the change and passing, run in a separate process. See [`powershell.instructions.md`](../com.github.copilot/rules/powershell.instructions.md), [`pester.instructions.md`](../com.github.copilot/rules/pester.instructions.md), [`powershell-execution-safety.instructions.md`](../com.github.copilot/rules/powershell-execution-safety.instructions.md).
- **Markdown** (`.md`): `markdownlint-cli2` reports 0 violations under the repo [`.markdownlint.jsonc`](../.markdownlint.jsonc).
- **YAML / JSON**: parses; validates against a schema where one exists.
- **C#** (`.cs`): compiles; analyzers clean.
- **Doc-only or conversational turns**: state "no executable verification required" with the reason instead of skipping silently.

### 3. Authored content — Skills, Instructions, Agents, Prompts

- **Skills**: folder name matches `name:`; `description` ≤ 1024 chars, third-person summary with an imperative trigger clause, category-level `USE FOR:` stated in the domain's own vocabulary and (where adjacent skills exist) `DO NOT USE FOR:`; body ≤ 500 lines; references one level deep; bundled scripts non-interactive with documented exit codes; behavioural-enforcement sections present where the skill encodes a skippable discipline. See [`skill-creator`](../Skills/skill-creator/SKILL.md).
- **Instructions**: `applyTo` is the narrowest glob that covers the intended files; no rule duplicates one in another instruction file.
- **All authored files**: frontmatter matches the schema for the type; emphasis used sparingly per the emphasis rule; no maintenance footers. See [`copilot-authoring.instructions.md`](../com.github.copilot/rules/copilot-authoring.instructions.md).

### 4. Repository hygiene

- [ ] Memory Bank updated: `activeContext.md` (current focus), `progress.md` (dated line), `promptHistory.md` (per-turn line).
- [ ] `CHANGELOG.md` `[Unreleased]` updated for any user-visible change (skip for pure refactors, memory-bank-only edits, trivial turns).
- [ ] Committed locally on an `ai/<slug>` branch with a conventional-commit message and a `Co-authored-by: AI Assistant <ai@example.com>` trailer, unless the user requested uncommitted changes.
- [ ] **Never push** unless the user explicitly asked this turn. Never bypass hooks (`--no-verify`).

### 5. Security

- No secrets in plaintext; credentials use `[PSCredential]` / `SecureString`.
- Input validated at system boundaries; no OWASP Top 10 regressions.
- For agents, LLM-backed features, or MCP servers: run the lethal-trifecta test and the OWASP LLM Top 10 screen. See [`agent-security-review`](../Skills/agent-security-review/SKILL.md).

### 6. Ubiquitous Language

- Where a `glossary.md` exists, use only its canonical terms in code, comments, tests, docs, and commit messages. See [`ubiquitous-language.instructions.md`](../com.github.copilot/rules/ubiquitous-language.instructions.md).

## When a criterion does not apply

Not every turn touches every gate. Skipping one is fine **when stated with a reason** — for example "n/a: doc-only edit, no executable verification". Silent skipping is a process violation. The POST-FLIGHT checklist is where each item is marked done or `n/a` with its reason.

## Using this file

Deployed Customizations point to the authoritative Instruction, not this
repository-only reference:

```markdown
Before reporting done, confirm the change clears the [Definition of Done gate](../com.github.copilot/rules/postflight.instructions.md#definition-of-done-gate).
```

The shared Post-flight Instruction enforces and owns the full bar.
