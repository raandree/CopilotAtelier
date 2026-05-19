---
name: skill-creator
description: >-
  Author, audit, and iteratively improve `Skills/**/SKILL.md` files in
  CopilotAtelier. Covers SKILL.md anatomy (frontmatter + `scripts/` +
  `references/` + `assets/`), the progressive-disclosure pattern (body ≤
  500 lines, deep material in references), the trigger-keyword description
  pattern that drives auto-selection in VS Code Copilot and `gh copilot`,
  the 1024-char description cap, and a lightweight eval workflow (3-5 real
  prompts, with/without the skill). Includes a description-tightening loop
  for under- or over-triggering skills.
  USE FOR: create a new skill, write SKILL.md, improve an existing skill,
  audit a skill, why is my skill not triggering, skill description
  optimisation, skill triggering, skill keywords, progressive disclosure for
  skills, skill body too long, skill description over 1024 chars, eval a
  skill, test a skill, skill auto-selection.
  DO NOT USE FOR: writing `Instructions/*.instructions.md`, writing
  `Agents/*.agent.md`, writing prompts.
---

# Skill Creator

Author and iteratively improve `Skills/**/SKILL.md` files for CopilotAtelier. The same loop applies whether you are creating a brand-new skill or revising one that under-triggers.

## When to Use

- The user says "turn this into a skill", "save this workflow", "why isn't this skill triggering", or "package this for reuse".
- An existing skill is too long, too vague, or its description fails the 1024-char CLI cap (memory bank notes that 11 skills hit this in May 2026).
- A repeated workflow has emerged across recent sessions (check `.memory-bank/progress.md`).

## SKILL.md anatomy

```
Skills/<kebab-name>/
├── SKILL.md         (required — frontmatter + body, < 500 lines)
├── references/      (optional — deep docs loaded on demand)
├── scripts/         (optional — executable helpers; .ps1 preferred)
└── assets/          (optional — templates, sample inputs, expected outputs)
```

Folder name MUST match the `name:` field. Anything beyond `SKILL.md` is opt-in.

## Frontmatter — the only fields that matter

```yaml
---
name: kebab-case-id        # must match folder name
description: >-            # block scalar; ≤ 1024 chars total
  One-paragraph summary of what the skill does and when it triggers.
  USE FOR: keyword1, keyword2, exact phrase a user would type, alternative phrasing, German term, English term.
  DO NOT USE FOR: adjacent skill, false-positive trigger.
---
```

- The `description` is the **only** thing the auto-selector sees. Body text never influences triggering.
- Lead with one concrete sentence. Follow with `USE FOR:` then `DO NOT USE FOR:`. Both lists are comma-separated keyword strings — keywords beat prose.
- Include synonyms, error messages users paste verbatim, and bilingual terms (EN/DE) when relevant. CopilotAtelier skills routinely mix both.
- Keep the total under 1024 characters or the GitHub Copilot CLI silently drops the skill. Verify with `(Get-Content SKILL.md -Raw -Encoding utf8 | Select-String -Pattern 'description:\s*>-\s*(.+?)(?=\n---)' -AllMatches).Matches[0].Groups[1].Value.Length`.

## Progressive disclosure

Three loading tiers. Respect them or the skill bloats context for every invocation.

| Tier | What loads | Size budget |
|---|---|---|
| Frontmatter | `name` + `description` only | ~150 words, always in context |
| SKILL.md body | Loaded when skill triggers | ≤ 500 lines |
| References / scripts / assets | Read on demand by the assistant | unlimited |

When the body crosses 500 lines, extract topic-bounded sections into `references/<topic>.md` and link from SKILL.md with a one-line pointer like "For the OOXML XML schema, read [`references/ooxml.md`](references/ooxml.md)."

## Trigger-keyword description pattern

Three-part shape used by every well-triggering CopilotAtelier skill:

1. **Summary sentence** — what the skill does, in one line.
2. **`USE FOR:`** — exhaustive keyword list. Include casual phrasings ("the xlsx in my downloads"), error messages users paste, tool names, and bilingual terms.
3. **`DO NOT USE FOR:`** — explicit anti-triggers, especially adjacent skills ("DO NOT USE FOR: creating DOCX files (use pandoc-docx-export skill)").

A description that includes the exact phrase the user typed gets selected. A description full of nouns the user did not type does not. Update the description, not the body, when a skill under-triggers.

## Body style — relaxed-tier rules from `copilot-authoring.instructions.md`

- Rationale is allowed when it helps a human pick the right skill or audit it.
- Workflow prose is allowed (phase descriptions, recipes, decision trees).
- Use `## When to Use`, `## Approach Decision Tree`, `## Recipe N: <name>` as standard section names.
- Emphasise only destructive warnings and non-obvious gotchas. The imperative mood already carries weight.
- No maintenance footer (no `Last Updated`, no `Maintained By`). Git history is the source of truth.

## Authoring loop

1. **Capture intent.** Note the exact phrasings the user would type. Save them — they become eval prompts.
2. **Draft the frontmatter first.** Description before body. If you can't write a tight description, the skill scope is wrong.
3. **Draft the body.** Lead with `## When to Use`. Recipes second. Anti-patterns / gotchas last.
4. **Extract scripts.** Anything longer than ~30 lines of executable code goes into `scripts/<name>.ps1` (or `.py` / `.mjs` when the runtime is non-PowerShell). SKILL.md keeps a 5-line invocation example.
5. **Audit length.** `(Get-Content SKILL.md).Count` should be ≤ 500. Description ≤ 1024 chars.
6. **Eval.** See next section.

## Lightweight eval workflow

Full benchmark/grading harnesses are overkill for this repo. The 80/20 substitute:

1. Write 3-5 realistic test prompts — the exact phrasing a real user would use (paste into `notes-evals.md` in the skill folder, gitignored optional).
2. For each prompt, in a fresh chat:
   - Run **with** the skill (verify trigger by name in the PRE-FLIGHT line).
   - Run **without** (rename the skill folder temporarily, or use a chat where the skill isn't loaded).
3. Compare outputs by hand. Look for: did the skill actually fire? did the output meet the prompt? did the skill add value vs. the baseline?
4. If the skill under-triggered, the description is wrong → tighten keywords. If it triggered but produced bad output, the body is wrong → tighten recipes.

Skip eval for skills with subjective outputs (writing style, summarisation). Always eval skills with verifiable outputs (file conversion, parsing, code generation).

## Description-tightening loop

When a skill under-triggers:

1. Collect the user phrasings that should have fired the skill (from `.memory-bank/promptHistory.md` or chat history).
2. Add the exact verbatim phrasings to `USE FOR:`.
3. Add competing skills' core nouns to `DO NOT USE FOR:` to break ambiguity.
4. If the description exceeds 1024 chars, drop adjective-heavy clauses, keep nouns and verbs.

When a skill over-triggers:

1. Identify the false-positive prompts.
2. Add their distinguishing nouns to `DO NOT USE FOR:`.
3. Remove the over-broad keywords from `USE FOR:`.

## Skill vs. instruction vs. agent — when in doubt

| Pick | When |
|---|---|
| Skill | A bounded workflow with concrete recipes. Loads on demand. Has a verifiable output. |
| Instruction (`Instructions/*.instructions.md`) | Coding-style or formatting rule that must apply to every edit of matching files. Always loaded for matching paths. |
| Agent (`Agents/*.agent.md`) | A persona with its own model, toolset, and multi-step methodology. The user explicitly switches into it. |
| Prompt (`Prompts/*.prompt.md`) | A one-shot template the user invokes from the picker. |

If two of these fit, prefer the lighter one. A skill is lighter than an agent; an instruction is lighter than a skill *for rules that must always apply*.

## Authoring checklist

Mirror of `copilot-authoring.instructions.md` + skill-specific items:

- [ ] Folder name == `name:`.
- [ ] Description ≤ 1024 chars; contains `USE FOR:` and (where useful) `DO NOT USE FOR:`.
- [ ] Body ≤ 500 lines; deep material extracted to `references/`.
- [ ] Scripts ≥ ~30 lines extracted to `scripts/`.
- [ ] No maintenance footer.
- [ ] No duplication of rules covered by an existing instruction file.
- [ ] `Setup-CopilotSettings.ps1` does not need to be touched — the skill is auto-discovered via the `~/.copilot/skills` junction.
- [ ] Eval ran for at least one real prompt; the PRE-FLIGHT line confirms the skill triggered by name.

## Register the skill

No registration step. The `~/.copilot/skills` junction created by [`Setup-CopilotSettings.ps1`](../../Setup-CopilotSettings.ps1) exposes the folder to VS Code Copilot chat and the GitHub Copilot CLI automatically. Just commit and the next session sees it.

## Common pitfalls

- **Description over 1024 chars.** Silent drop in the CLI. The skill still appears in VS Code but not in `gh copilot`. Audit with the one-liner above.
- **Description full of prose, not keywords.** Auto-selector matches on lexical overlap, not semantics. Add the noun the user actually typed.
- **Body holds the trigger info.** Body text is invisible to the selector. Move triggers into the description.
- **Folder name mismatches `name:`.** The CLI silently ignores the skill.
- **Two skills both claim the same trigger.** Disambiguate with `DO NOT USE FOR:` cross-references on both sides.
- **SKILL.md tries to be a tutorial.** It is reference material for an LLM that already knows the domain. Cut introductions.
