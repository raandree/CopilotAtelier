---
applyTo: "{Instructions/*.instructions.md,Prompts/*.prompt.md,Skills/**/SKILL.md,Agents/*.agent.md}"
---

# AI Instruction Authoring

Rules for authoring files that Copilot loads into its context: instructions, prompts, skills, and agents. Goal: reduce tokens, eliminate conflicts, keep guidance precise.

## Scope

Two tiers. Strict rules apply to AI-only files. Relaxed rules apply to human-and-AI files.

- Strict — `Instructions/*.instructions.md`, `Prompts/*.prompt.md`. Optimize for token efficiency; humans rarely read these end-to-end.
- Relaxed — `Agents/*.agent.md`, `Skills/**/SKILL.md`. Humans select, audit, and edit these; readability matters.

## Rules — All Files

- Write short imperative directives. Prefer bullet lists over prose.
- Remove filler words, redundant qualifiers, and repeated context.
- Check existing instructions before adding rules. Update on conflict; never duplicate.
- Start each file with YAML frontmatter. Required keys depend on file type (see Frontmatter Schemas below). Exception: `README.md` and top-level `AGENTS.md` / `copilot-instructions.md` equivalents.
- Use `##`/`###` headings, `-` bullets, backticks for code tokens, fenced blocks for multi-line examples.
- Do not add maintenance footers (`Last Updated`, `Maintained By`, version banners). Git history is the source of truth.
- Do not include tutorials or introductory explanations of the subject matter. Link to authoritative external docs instead.

## Rules — Strict Tier (Instructions, Prompts)

- Omit *why* unless the reason changes behavior. If the rule is "use `-ErrorAction Stop`", do not explain what `-ErrorAction` does.
- No conversational tone. No "please", "you should consider", "it is recommended that".
- No decorative emphasis. See the emphasis rule below.
- No redundant examples. One example per rule, only when the rule is ambiguous without it.

## Rules — Relaxed Tier (Agents, Skills)

- Rationale is allowed when it helps a human pick the right agent or skill, or audit its behavior.
- Workflow prose is allowed (phase descriptions, methodology explanations).
- Still bound by: no filler, no duplication, narrow scope, no maintenance footers.

## Frontmatter Schemas

Each file type uses a distinct frontmatter shape. Values must be strings unless noted.

### Instructions (`Instructions/*.instructions.md`)

- `applyTo` (required): comma-separated glob string. Narrowest pattern that covers the intended files. Never an array. Never `**/*` when a specific path suffices.

### Prompts (`Prompts/*.prompt.md`)

- `agent` (required): `agent` or `ask`.
- `description` (required): one-line summary shown in the prompt picker.
- `tools` (optional): array of allowed tool names. Omit to inherit the caller's toolset.
- `model` (optional): model identifier, e.g. `Claude Opus 4.6 (fast mode) (copilot)`.

### Agents (`Agents/*.agent.md`)

- `name` (required): kebab-case identifier used for handoffs.
- `description` (required): one-line summary for the agent picker.
- `model` (required): model identifier.
- `argument-hint` (optional): placeholder prompt shown to the user.
- `tools` (optional): array of allowed tool names.
- `agents` (optional): array of agent names this agent may hand off to.
- `handoffs` (optional): array of `{label, agent}` objects surfaced as UI handoff buttons.

### Skills (`Skills/**/SKILL.md`)

- `name` (required): kebab-case identifier matching the folder name.
- `description` (required): block scalar. Start with a one-paragraph summary, then `USE FOR:` keyword list, then optional `DO NOT USE FOR:` list. Keywords drive skill auto-selection.

## Emphasis Rule (All Files)

Bold and italics carry signal only when used sparingly. Overuse destroys the signal.

- Use `**bold**` only for:
  - Destructive-action warnings (`**NEVER PUSH**`, `**DO NOT**` in safety contexts).
  - Non-obvious gotchas a reviewer must not miss.
  - Section-level keywords in tables or definition lists.
- Do not bold every imperative. The imperative mood already carries the weight.
- Do not use italics for emphasis. Reserve `*italics*` for terminology on first introduction and for titles of external works where backticks are inappropriate.
- Do not use ALL CAPS for emphasis except for established acronyms (MUST, SHOULD per RFC 2119 is acceptable; arbitrary SHOUTING is not).

## Token Hygiene

- Prefer `must` over `**must**` (saves 2 tokens per occurrence).
- Prefer `Do X` over `You should do X` or `It is recommended to do X`.
- Collapse multi-sentence rules into one sentence when possible.
- Delete sections that only restate the file's title or purpose.

## Authoring Checklist

Before committing changes to an AI-loaded file:

- [ ] Frontmatter matches the schema for the file type (Instructions/Prompts/Agents/Skills).
- [ ] For instructions: `applyTo` is the narrowest glob that covers the intended files.
- [ ] No rule duplicates an existing rule in another instruction file.
- [ ] No filler phrases (`in order to`, `it is important to note that`, `please ensure`).
- [ ] Emphasis used only per the emphasis rule above.
- [ ] No maintenance footer added.
- [ ] File compiles cleanly with markdownlint if `markdown.instructions.md` applies.
