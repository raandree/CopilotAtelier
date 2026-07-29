---
applyTo: "{Instructions/*.instructions.md,Prompts/*.prompt.md,Skills/**/SKILL.md,Agents/*.agent.md,Hooks/*.json}"
---

# AI Instruction Authoring

Rules for authoring files that Copilot loads into its context: instructions, prompts, skills, agents, and hooks. Goal: reduce tokens, eliminate conflicts, keep guidance precise.

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
- `model` (optional): model identifier, e.g. `Claude Opus 5 (copilot)`.

### Agents (`Agents/*.agent.md`)

- `name` (required): kebab-case identifier used for handoffs.
- `description` (required): one-line summary for the agent picker.
- `model` (required): array of model identifiers in priority order. The first available model wins, so always declare a GA fallback.
- `argument-hint` (optional): placeholder prompt shown to the user.
- `tools` (optional): array of allowed tool names.
- `agents` (optional): array of agent names this agent may use as subagents. `[]` forbids subagents; omitting the key allows every agent.
- `disable-model-invocation` (optional): `true` keeps the agent in the picker but stops other agents selecting it as a subagent. Set it on domain specialists whose descriptions overlap. An agent named explicitly in another agent's `agents` array overrides this.
- `user-invocable` (optional): `false` hides the agent from the picker while leaving it available as a subagent.
- `handoffs` (optional): array of `{label, agent, prompt, send}` objects surfaced as UI handoff buttons.
- `hooks` (optional): agent-scoped hook commands. Prefer shared hooks in `Hooks/`; use this only for behavior that must not apply to other agents.
- Never use `infer`. It is deprecated in favor of `user-invocable` and `disable-model-invocation`.

### Skills (`Skills/**/SKILL.md`)

- `name` (required): kebab-case identifier matching the folder name. No namespace prefix — a prefix makes the Skill fail to load silently.
- `description` (required): block scalar. Start with a one-paragraph summary, then `USE FOR:` keyword list, then optional `DO NOT USE FOR:` list. Keywords drive skill auto-selection. Max 1024 characters.
- `compatibility` (optional): max 500 characters. Required whenever the Skill needs a specific operating system, runtime, module, or external binary. State the hard requirement, not a preference.
- `context` (optional): `fork` runs the Skill in a dedicated subagent and returns only its result. Use it for Skills that ingest large volumes of untrusted external content or run long investigations whose intermediate detail must not reach the parent conversation. Requires `github.copilot.chat.skillTool.enabled`.
- `license`, `metadata`, `allowed-tools` (optional): agentskills.io fields. `allowed-tools` is experimental and support varies by client.
- `argument-hint`, `user-invocable`, `disable-model-invocation` (optional): control slash-command presentation and whether the model may load the Skill on its own.
- For authoring guidance see [`Reference/howto-write-skills.md`](../Reference/howto-write-skills.md) (condensed primer + canonical Anthropic links) and [`Skills/skill-creator/SKILL.md`](../Skills/skill-creator/SKILL.md) (full operating manual).

### Hooks (`Hooks/*.json`)

- One `hooks` object mapping event names to arrays of command objects. Events: `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PreCompact`, `SubagentStart`, `SubagentStop`, `Stop`.
- Every command declares `type: "command"`, a `timeout`, a POSIX `command`, and a `windows` override.
- VS Code spawns the command without a shell, so `%VAR%` and `$VAR` are never expanded. Let the interpreter resolve its own path and propagate the exit code: `-Command "& (Join-Path $env:USERPROFILE '...'); exit $LASTEXITCODE"`.
- Exit `0` to allow, `2` to block with the reason on standard error, any other code for a non-blocking warning.
- Fail open on an unreadable payload. A hook that cannot parse its input must not block every tool call.
- Encode enforcement in a hook when the rule must hold regardless of what the model decides. Leave judgement calls in Instructions.

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

- [ ] Frontmatter matches the schema for the file type (Instructions/Prompts/Agents/Skills/Hooks).
- [ ] For instructions: `applyTo` is the narrowest glob that covers the intended files.
- [ ] For agents: `model` is a priority array whose last entry is a GA model.
- [ ] For skills: `compatibility` is present whenever the Skill needs a specific OS, runtime, module, or binary.
- [ ] No rule duplicates an existing rule in another instruction file.
- [ ] No filler phrases (`in order to`, `it is important to note that`, `please ensure`).
- [ ] Emphasis used only per the emphasis rule above.
- [ ] No maintenance footer added.
- [ ] File compiles cleanly with markdownlint if `markdown.instructions.md` applies.
