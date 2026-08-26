---
applyTo: "{com.github.copilot/rules/*.instructions.md,com.github.copilot/commands/*.prompt.md,skills/**/SKILL.md,com.github.copilot/agents/*.agent.md,com.github.copilot/hooks/*.json}"
description: "Authoring rules and frontmatter schemas for Copilot Customization files. Use when creating, reviewing, or choosing between an Instruction, Prompt, Skill, Custom agent, or Hook."
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
- Reference a tool in body text as `#tool:<tool-name>` (for example `#tool:web/fetch`). Applies to Instructions, Prompts, and Agents.
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

Each file type uses a distinct frontmatter shape. Values must be strings unless noted. Where a key is marked *required here*, the platform treats it as optional and this repository's tests do not.

### Instructions (`Instructions/*.instructions.md`)

- `applyTo` (required here): comma-separated glob string. Narrowest pattern that covers the intended files. Never an array. Never `**/*` when a specific path suffices. Without it the file never auto-applies and is reachable only by manual attachment.
- `description` (required here): one line. VS Code also activates an Instruction by semantic match of the description against the current task, so a glob alone never covers the real trigger.
- `name` (optional): display name in the Chat view. Defaults to the file name.
- The Claude-format equivalent in `.claude/rules` uses `paths` (array of globs, default `**`) in place of `applyTo`.

### Prompts (`Prompts/*.prompt.md`)

- `description` (required): one-line summary shown in the prompt picker.
- `agent` (optional): `ask`, `agent`, `plan`, or a Custom agent name. Defaults to the active agent, or to `agent` when `tools` is set.
- `name` (optional): slash-command name. Defaults to the file name.
- `argument-hint` (optional): placeholder prompt shown to the user.
- `tools` (optional): array of allowed tool names. Omit to inherit the caller's toolset. Prompt tools outrank the referenced agent's tools.
- `model` (optional): model identifier, e.g. `Claude Opus 5 (copilot)`.
- Prompts run only in the VS Code extension host. Agent Host, the Copilot CLI, and the cloud agent ignore them. Author a Skill instead when the workflow must be portable.

### Agents (`Agents/*.agent.md`)

- `name` (required here): kebab-case identifier used for handoffs.
- `description` (required here): one-line summary for the agent picker.
- `model` (required here): array of model identifiers in priority order. The first available model wins, so always declare a GA fallback.
- `argument-hint` (optional): placeholder prompt shown to the user.
- `tools` (optional): array of allowed tool names, tool sets, or `<mcp-server>/*`.
- `agents` (optional): array of agent names this agent may use as subagents. `*` allows all; `[]` forbids subagents; omitting the key allows every agent. Declaring it requires the `agent` tool in `tools`, and self-reference requires `chat.subagents.allowInvocationsFromSubagents`.
- `disable-model-invocation` (optional): `true` keeps the agent in the picker but stops other agents selecting it as a subagent. Set it on domain specialists whose descriptions overlap. An agent named explicitly in another agent's `agents` array overrides this.
- `user-invocable` (optional): `false` hides the agent from the picker while leaving it available as a subagent.
- `handoffs` (optional): array of `{label, agent, prompt, send, model}` objects surfaced as UI handoff buttons. `model` takes the qualified `Model Name (vendor)` form.
- `target` (optional): `vscode` or `github-copilot`. Declare it only when the agent is authored for one harness.
- `mcp-servers` (optional): MCP server configuration for `target: github-copilot`. Ignored in VS Code.
- `hooks` (optional): agent-scoped hook commands, same shape as `Hooks/*.json`, gated on `chat.useCustomAgentHooks`. Prefer shared hooks in `Hooks/`; use this only for behavior that must not apply to other agents.
- Never use `infer`. It is deprecated in favor of `user-invocable` and `disable-model-invocation`.

### Skills (`Skills/**/SKILL.md`)

- `name` (required): kebab-case identifier matching the folder name. Max 64 characters, lowercase alphanumerics and single hyphens only, no leading, trailing, or consecutive hyphen. No namespace prefix — a prefix makes the Skill fail to load silently. A plugin supplies its own `/<plugin>:<skill>` prefix.
- `description` (required): block scalar. Start with a one-paragraph summary, then a `USE FOR:` list naming the general categories of request the Skill serves, then an optional `DO NOT USE FOR:` list naming adjacent Skills and near-miss requests. The description is the only text the auto-selector sees. Keep `USE FOR:` at category level, but state those categories in the domain's own vocabulary — the specification asks for specific keywords that help an agent identify relevant tasks. What overfits is pasting in the verbatim wording of queries that failed to trigger, not the domain terms themselves. Max 1024 characters.
- `compatibility` (optional): max 500 characters. Required whenever the Skill needs a specific operating system, runtime, module, or external binary. State the hard requirement, not a preference.
- `context` (optional): `fork` runs the Skill in a dedicated subagent and returns only its result. Use it for Skills that ingest large volumes of untrusted external content or run long investigations whose intermediate detail must not reach the parent conversation. Requires `github.copilot.chat.skillTool.enabled`.
- `license`, `metadata`, `allowed-tools` (optional): agentskills.io fields. `metadata` is a string-to-string map. `allowed-tools` is a space-separated string, not an array, and is experimental with client-varying support.
- `argument-hint`, `user-invocable`, `disable-model-invocation` (optional): control slash-command presentation and whether the model may load the Skill on its own.
- For authoring guidance see [`Reference/howto-write-skills.md`](../Reference/howto-write-skills.md) (condensed primer + canonical Anthropic links) and [`Skills/skill-creator/SKILL.md`](../Skills/skill-creator/SKILL.md) (full operating manual).

### Hooks (`Hooks/*.json`)

- One `hooks` object mapping event names to arrays of command objects. Events: `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PreCompact`, `SubagentStart`, `SubagentStop`, `Stop`.
- Every command declares `type: "command"`, a `timeout` in seconds (default 30), a POSIX `command`, and a `windows` override. `cwd`, `env`, `linux`, and `osx` are also accepted.
- VS Code spawns the command without a shell, so `%VAR%` and `$VAR` are never expanded. Let the interpreter resolve its own path and propagate the exit code: `-Command "& (Join-Path $env:USERPROFILE '...'); exit $LASTEXITCODE"`.
- Exit `0` to allow, `2` to block with the reason on standard error, any other code for a non-blocking warning.
- On exit `0`, stdout is parsed as JSON. Common fields: `continue` (`false` stops the whole session), `stopReason`, `systemMessage`. Event-specific control goes in `hookSpecificOutput`. The most restrictive signal wins.
- Only `PreToolUse`, `PostToolUse`, `SessionStart`, and `SubagentStart` can inject `additionalContext`. `UserPromptSubmit` and `PreCompact` support the common output only, so no hook can add text to a post-compaction context.
- `Stop` and `SubagentStop` must check `stop_hook_active` before returning `decision: "block"`. Every blocked stop costs another billed turn.
- Treat `transcript_path` as unstable. Prefer the documented input fields (`tool_name`, `tool_input`, `prompt`).
- Fail open on an unreadable payload. A hook that cannot parse its input must not block every tool call.
- Do not rely on a Claude-format `matcher`: VS Code parses it and ignores it. Filter inside the script, and read tool input in camelCase (`tool_input.filePath`), not Claude's snake_case.
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
- [ ] For instructions: `applyTo` is the narrowest glob that covers the intended files, no pattern in the list is subsumed by another, and `description` is declared.
- [ ] For prompts: the workflow is genuinely VS Code-only, otherwise it is authored as a Skill.
- [ ] For agents: `model` is a priority array whose last entry is a GA model.
- [ ] For skills: `compatibility` is present whenever the Skill needs a specific OS, runtime, module, or binary.
- [ ] No rule duplicates an existing rule in another instruction file.
- [ ] No filler phrases (`in order to`, `it is important to note that`, `please ensure`).
- [ ] Emphasis used only per the emphasis rule above.
- [ ] No maintenance footer added.
- [ ] File compiles cleanly with markdownlint if `markdown.instructions.md` applies.
