# How to Write Skills — Condensed Guide

A two-page primer for authoring `Skills/**/SKILL.md` files in this repository. The full operating manual lives in [`Skills/skill-creator/SKILL.md`](../Skills/skill-creator/SKILL.md); this page is the short version with links to the canonical external sources.

## What a Skill is

A folder with a `SKILL.md` (YAML frontmatter + markdown body) plus optional `references/`, `scripts/`, and `assets/`. Claude pre-loads only the `name` + `description` from every installed skill; it reads the body when the skill triggers, and reads `references/` files only when the body points to them. This is the **progressive disclosure** model — three loading tiers, three context-cost tiers.

Progressive disclosure is the skills-level application of **context engineering** — the discipline of curating what enters the model's finite context window and when, so the agent sees exactly the information a step needs and nothing more. On-demand reference loading, tight descriptions, and the 500-line body cap are all context engineering: they keep dozens of skills available at a near-zero idle cost and pay the token price only when a skill actually fires.

```text
Skills/<kebab-name>/
├── SKILL.md         (required — ≤ 500 lines, description ≤ 1024 chars)
├── references/      (loaded on demand, one level deep from SKILL.md)
├── scripts/         (executed via shell; code never enters context)
└── assets/          (templates, sample inputs, expected outputs)
```

## The six-step frame

Use this before writing a single line of SKILL.md. If any step is unclear, the skill scope is wrong — refine, then start.

1. **Name** — kebab-case, ≤ 64 chars, no `claude` / `anthropic`.
2. **Trigger** — the `description` Claude reads to decide whether to load. Get this wrong and the skill never activates.
3. **Outcome** — what "done" looks like, in one sentence.
4. **Dependencies** — every tool, MCP server, reference, script, or asset the skill needs.
5. **Step-by-step** — the exact instructions Claude follows in order, with human-in-the-loop checkpoints where applicable.
6. **Edge cases** — what happens when input is vague, missing, oversized, or unexpected.

## Five high-leverage rules

1. **Description is the only thing the selector sees.** Body text never influences triggering. When a skill under-triggers, fix the description first.
2. **Third person, always.** `"Extracts text from PDF files."` — not `"I can help you..."` or `"You can use this to..."`. POV-inconsistent text breaks discovery.
3. **Point, don't dump.** SKILL.md is the standard operating procedure. Deep knowledge (XML schemas, API tables, long examples) belongs in `references/<topic>.md`. When the body crosses 500 lines, split.
4. **References one level deep.** Claude often previews nested references with `head -100` and gets incomplete content. All references link directly from SKILL.md.
5. **Pick a default.** Don't offer five libraries — pick one and mention alternatives only as documented escape hatches ("use X instead when Y").

## Hard limits

| Limit | Value | Failure mode |
|---|---|---|
| `name` length | ≤ 64 chars | Skill silently rejected |
| `description` length | ≤ 1024 chars | GitHub Copilot CLI silently drops the skill |
| SKILL.md body | ≤ 500 lines | Context bloat; degraded selection accuracy |
| Reference file with TOC required | > 100 lines | Partial reads miss content |

Verify description length:

```powershell
(Get-Content SKILL.md -Raw -Encoding utf8 |
    Select-String -Pattern 'description:\s*>-\s*(.+?)(?=\n---)' -AllMatches
).Matches[0].Groups[1].Value.Length
```

## The description shape that triggers reliably

```yaml
description: >-
  One-sentence third-person summary of what the skill does, plus when to use it.
  USE FOR: exact phrase a user would type, alternative phrasing, error message
  pasted verbatim, tool names, bilingual terms (EN/DE).
  DO NOT USE FOR: adjacent skill (use other-skill instead), false-positive trigger.
```

`USE FOR:` is a keyword list, not prose — the selector matches lexical overlap, not semantics. `DO NOT USE FOR:` is the single highest-leverage anti-cannibalisation tool when two skills overlap.

## Degrees of freedom

Match the level of specificity to the task's fragility.

| Freedom | When | Pattern |
|---|---|---|
| **High** | Multiple approaches valid | Prose checklist |
| **Medium** | Preferred pattern exists | Pseudocode or parameterised script |
| **Low** | Fragile / destructive / must be exact | Exact command, "do not modify" |

Analogy: narrow bridge with cliffs → guardrails (low freedom); open field → general direction (high freedom). Database migrations are bridges; code reviews are fields.

## Evaluation-driven development (the part most people skip)

1. Run Claude on three representative tasks **without** the skill. Document every failure.
2. Write three eval prompts in the user's exact phrasing. Save to `notes-evals.md` in the skill folder.
3. Establish baseline output.
4. Write minimal SKILL.md — just enough to fix the documented gaps.
5. Re-run with the skill loaded. Verify it triggered (PRE-FLIGHT line names it).
6. Iterate. Under-triggered → fix description. Triggered but bad output → fix body or references.

## Anti-patterns

- Description full of prose, not keywords. (Selector matches lexical overlap.)
- Body holds the trigger. (Body is invisible to the selector.)
- Time-sensitive language in main content. (Use `<details><summary>Old patterns</summary>` blocks.)
- Inconsistent terminology. (Pick one term and use it throughout.)
- Offering too many options. (Pick a default.)
- Deeply nested references. (SKILL.md → `a.md` → `b.md` → `c.md`. Flatten.)
- SKILL.md as tutorial. (It is reference material for an LLM that knows the domain. Cut introductions.)
- Folder name mismatches `name:` field. (CLI silently ignores the skill.)

## Canonical references

External sources, in order of authority:

1. **Anthropic — Agent Skills overview.** Architecture, three-tier loading, how Claude reads SKILL.md via bash, security model. <https://platform.claude.com/docs/en/agents-and-tools/agent-skills>
2. **Anthropic — Skill authoring best practices.** Description writing, gerund naming, degrees of freedom, progressive disclosure patterns, eval-driven development, Claude-A/Claude-B iteration loop, anti-patterns. <https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices>
3. **Anthropic — The Complete Guide to Building Skills for Claude (PDF).** Marketing PDF that mirrors the docs in linear form. Good for offline reading. <https://resources.anthropic.com/hubfs/The-Complete-Guide-to-Building-Skill-for-Claude.pdf>
4. **Anthropic — Equipping agents for the real world with Agent Skills (engineering blog).** Design rationale, real-world deployment patterns. <https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills>
5. **Anthropic — Claude apps Skills launch announcement.** Product-level framing, plugin marketplace context. <https://claude.com/blog/skills>
6. **anthropics/skills (GitHub).** Anthropic's own reference skills (`pptx`, `xlsx`, `docx`, `pdf`, Claude API). Reading these is the fastest way to see canonical structure in practice. <https://github.com/anthropics/skills>
7. **Agent Skills as an open standard.** Cross-platform skill portability spec (originally developed by Anthropic, released open). <https://agentskills.io/>
8. **Agentic AI Foundation (AAIF).** Vendor-neutral [Linux Foundation](https://www.linuxfoundation.org/) initiative consolidating stewardship of open agent standards (skills, tools, protocols). Sits alongside the agentskills.io spec as the neutral home for cross-tool agent portability. Search "Agentic AI Foundation" for the current project page.
9. **Simon Scrapes — "The 1% way to use Claude Skills" (video).** Source of the six-step authoring frame summarised above; argues that 20–30 well-built curated skills beat 500 generic ones. <https://www.youtube.com/watch?v=6-D3fg3JUL4>

## In-repo references

- [`Skills/skill-creator/SKILL.md`](../Skills/skill-creator/SKILL.md) — full operating manual; load via prompt "create a skill", "audit a skill", etc.
- [`Instructions/copilot-authoring.instructions.md`](../Instructions/copilot-authoring.instructions.md) — schema and style rules for SKILL.md, agent, instruction, and prompt files. Auto-loaded when editing any of them.
- [`Skills/sampler-framework/`](../Skills/sampler-framework/), [`Skills/automatedlab-deployment/`](../Skills/automatedlab-deployment/), [`Skills/datum-configuration/`](../Skills/datum-configuration/) — worked examples of the SKILL.md-as-navigation-map + `references/` pattern after Pass-B split (May 2026).

## When in doubt — skill, instruction, agent, or prompt?

| Pick | When |
|---|---|
| **Skill** | Bounded workflow with concrete recipes. Loads on demand. Verifiable output. |
| **Instruction** | Coding-style or formatting rule that must apply to every edit of matching files. Always loaded for matching paths. |
| **Agent** | A persona with its own model, toolset, and multi-step methodology. The user explicitly switches into it. |
| **Prompt** | A one-shot template the user invokes from the picker. |

If two fit, prefer the lighter one. A skill is lighter than an agent; an instruction is lighter than a skill *only when the rule must always apply*.
