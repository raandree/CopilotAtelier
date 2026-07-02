---
name: skill-creator
description: >-
  Authors, audits, and improves `Skills/**/SKILL.md` files following
  Anthropic's canonical Agent Skills guidance: progressive disclosure
  (body ≤ 500 lines, references one level deep), the six-step authoring
  frame (Name / Trigger / Outcome / Dependencies / Step-by-step / Edge
  cases), trigger-keyword descriptions, the 1024-char description cap,
  third-person rule, degrees-of-freedom calibration, evaluation-driven
  development with the Claude-A / Claude-B loop, and cross-skill overlap
  audits.
  USE FOR: create a new skill, write SKILL.md, improve a skill, audit a
  skill, why is my skill not triggering, skill description optimisation,
  skill triggering, skill keywords, progressive disclosure, skill body
  too long, description over 1024 chars, split skill into references,
  eval a skill, skill auto-selection, skill overlap audit, point dont
  dump, six step skill framework.
  DO NOT USE FOR: writing `Instructions/*.instructions.md`,
  `Agents/*.agent.md`, or prompts; configuring MCP servers.
---

# Skill Creator

Author and iteratively improve `Skills/**/SKILL.md` files for CopilotAtelier following Anthropic's canonical [Agent Skills overview](https://platform.claude.com/docs/en/agents-and-tools/agent-skills) and [authoring best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices). The same loop applies to brand-new skills, skills that under-trigger, and skills whose body has grown past the 500-line budget.

For a condensed two-page primer with links to the canonical external sources, see [`Reference/howto-write-skills.md`](../../Reference/howto-write-skills.md).

## When to Use

- The user says "turn this into a skill", "save this workflow", "package this for reuse", "why isn't this skill triggering", or "this skill is too long".
- A SKILL.md exceeds 500 lines or has no `references/` directory but covers multiple sub-topics.
- A repeated workflow has emerged across recent sessions (check `.memory-bank/progress.md` and `.memory-bank/promptHistory.md`).
- Two skills compete for the same triggers and you need an overlap audit.

## Philosophy: less is more

Anthropic's own guidance and field reports converge on the same point: a small, well-described, properly split skill library outperforms a large one. Every skill's `description` is always loaded; with hundreds of generic skills installed, the auto-selector picks the wrong one or none at all. Curate ruthlessly. Prefer fixing an existing skill over adding a new one.

## SKILL.md anatomy

```
Skills/<kebab-name>/
├── SKILL.md         (required — frontmatter + body, ≤ 500 lines)
├── references/      (optional — deep docs loaded on demand, one level deep)
├── scripts/         (optional — executable helpers; .ps1 preferred)
└── assets/          (optional — templates, sample inputs, expected outputs)
```

Folder name MUST match the `name:` field. Anything beyond `SKILL.md` is opt-in.

## Interaction style

When interviewing the user about a new or existing skill (scope, triggers, dependencies, edge cases), follow the shared convention in [`Reference/interactive-questions.md`](../../Reference/interactive-questions.md): prefer `vscode_askQuestions` over markdown checkboxes when the tool is available.

## The six-step authoring frame

Use this frame before writing a single line of SKILL.md. If any step is unclear, the skill scope is wrong — stop and refine.

1. **Name.** Short kebab-case label that describes the activity. Anthropic recommends gerund form (`processing-pdfs`); noun phrases (`pdf-processing`) are acceptable and dominate this repo. Max 64 chars. No `claude` or `anthropic`.
2. **Trigger.** The `description` Claude reads to decide whether to load the skill. Get this wrong and the skill never activates. See [Writing the description](#writing-the-description) below.
3. **Outcome.** Define what "done" looks like in one sentence before writing instructions. If you cannot, the skill is two skills.
4. **Dependencies.** Every tool, MCP server, reference file, script, or asset the skill needs. List them up front; surprises mid-execution are a quality bug.
5. **Step-by-step.** Exact instructions Claude follows in order, with explicit human-in-the-loop points where applicable.
6. **Edge cases.** What happens when input is vague, missing, oversized, or unexpected. Robust skills handle failure gracefully; brittle ones silently produce wrong output.

## Frontmatter

```yaml
---
name: kebab-case-id        # matches folder name; max 64 chars
description: >-            # block scalar; ≤ 1024 chars total
  One-paragraph third-person summary of what the skill does and when it
  triggers.
  USE FOR: keyword1, keyword2, exact phrase a user would type,
  alternative phrasing, German term, English term, error message users
  paste verbatim.
  DO NOT USE FOR: adjacent skill (use other-skill instead), false-
  positive trigger.
---
```

Hard limits per Anthropic: `name` ≤ 64 chars; `description` ≤ 1024 chars, non-empty, no XML tags. The GitHub Copilot CLI silently drops skills whose description exceeds 1024 chars; the VS Code surface is more forgiving but still penalises long descriptions in selection accuracy.

Verify length:

```powershell
$desc = (Get-Content SKILL.md -Raw -Encoding utf8 | Select-String -Pattern 'description:\s*>-\s*(.+?)(?=\n---)' -AllMatches).Matches[0].Groups[1].Value
$desc.Length
```

## Writing the description

The `description` is the **only** thing the auto-selector sees. Body text never influences triggering.

Five rules, in order of impact:

1. **Third person, always.** Anthropic explicitly warns against first- and second-person voice — the description is injected into the system prompt and POV-inconsistent text causes discovery failures.
   - Good: `"Extracts text and tables from PDF files, fills forms, merges documents."`
   - Bad: `"I can help you process Excel files."`
   - Bad: `"You can use this to process Excel files."`
2. **Lead with one concrete sentence** stating what the skill does. Then a sentence stating when to use it.
3. **Add `USE FOR:`** — exhaustive comma-separated keyword list. Include casual phrasings ("the xlsx in my downloads"), error messages users paste verbatim, tool names, command names, and bilingual terms (EN/DE) where the repo's user base mixes both.
4. **Add `DO NOT USE FOR:`** — explicit anti-triggers naming adjacent skills. This is the single highest-leverage anti-cannibalisation tool when two skills overlap.
5. **No vague descriptions.** `"Helps with documents"` and `"Does stuff with files"` are auto-selector poison.

A description that contains the exact phrase the user typed gets selected. A description full of nouns the user did not type does not. When a skill under-triggers, update the description first — the body is never the cause.

## Progressive disclosure: point, don't dump

Three loading tiers. Respect them or the skill bloats context on every invocation. Progressive disclosure is **context engineering** applied to skills — curate what reaches the model's finite context window and when, paying the token cost of a body or reference only when the task needs it.

| Tier | What loads | When | Budget |
|---|---|---|---|
| Metadata | `name` + `description` | Always | ~100 tokens per skill |
| Body | SKILL.md text | When skill triggers | ≤ 500 lines (~5k tokens) |
| References / scripts / assets | Files in subfolders | On demand by the assistant | Effectively unlimited |

**Point, don't dump.** The SKILL.md body is the standard operating procedure — the process. Deep knowledge (XML schemas, API tables, long examples, large code blocks) belongs in `references/<topic>.md`, linked with a one-line pointer:

```markdown
For the OOXML XML schema, read [`references/ooxml.md`](references/ooxml.md).
```

When the body crosses 500 lines, extract self-contained topics into references. The SKILL.md body becomes a navigation map: When-To-Use, recipes summarised in two or three sentences each, pointers to deep references.

## References: one level deep

Anthropic's field observation: when references link to further references, Claude often previews them with `head -100` instead of reading them fully, producing incomplete information.

- All reference files link directly from SKILL.md.
- Never link `references/foo.md` → `references/bar.md` → `references/baz.md`.
- Reference files longer than 100 lines must start with a `## Contents` table-of-contents so Claude sees the full scope even from a partial preview.

## Degrees of freedom

Match the level of specificity in your instructions to the task's fragility.

| Freedom | When to use | Pattern |
|---|---|---|
| **High** | Multiple approaches valid; decisions depend on context | Prose checklist: "Analyse the code structure, check for edge cases, suggest improvements." |
| **Medium** | A preferred pattern exists; some variation acceptable | Pseudocode or script with parameters: `generate_report(data, format="markdown")`. |
| **Low** | Operations are fragile; consistency critical; specific sequence required | Exact command: `python scripts/migrate.py --verify --backup`. "Do not modify the command." |

The analogy: a narrow bridge with cliffs on both sides needs guardrails (low freedom); an open field needs only a general direction (high freedom). Database migrations are bridges; code reviews are fields.

## Pattern catalogue

Reach for these before inventing structure.

### Pattern 1 — High-level guide + references

SKILL.md gives quick-start. Each domain or advanced topic lives in `references/<topic>.md`. Use when the skill covers one tool with multiple sub-areas (e.g. `pdf-processing` with `forms.md`, `tables.md`, `merging.md`).

### Pattern 2 — Domain-organised references

SKILL.md is a navigation map; references are split by domain (`finance.md`, `sales.md`, `product.md`). Use when the skill spans multiple independent data sets or topics where any one task only needs one.

### Pattern 3 — Conditional workflow

SKILL.md describes a decision tree; each branch points to a reference or script. Use when the workflow forks early on input type ("creating new doc → follow A; editing existing → follow B").

### Pattern 4 — Workflow checklist

For complex multi-step tasks, provide a copyable checklist Claude tracks across the conversation:

```markdown
Task Progress:
- [ ] Step 1: Analyse the form
- [ ] Step 2: Create field mapping
- [ ] Step 3: Validate mapping
- [ ] Step 4: Fill the form
- [ ] Step 5: Verify output
```

### Pattern 5 — Feedback loop

`run → validate → fix → repeat`. Document the validator (script or rubric), the loop, and the exit condition. This pattern dramatically improves output quality on quality-critical tasks (form filling, XML edits, document generation).

### Pattern 6 — Examples (input → output pairs)

When output quality depends on style or format, include two or three input/output pairs in SKILL.md. Examples beat descriptions when the user wants a specific shape.

## Scripts: solve, don't punt

When a skill bundles executable code (`scripts/`):

- **Handle errors explicitly.** Catch `FileNotFoundError`, `PermissionError`, etc. and either recover with a documented default or fail with a specific actionable message. Do not let the script crash and leave Claude to guess.
- **No voodoo constants.** Every numeric literal (`TIMEOUT = 47`, `MAX_RETRIES = 5`) needs a one-line comment justifying it. "Why 47?" must have an answer.
- **Use forward slashes** in all paths (`scripts/helper.py`, not `scripts\helper.py`). Windows paths break on Unix.
- **Make execution intent explicit**: "Run `analyse_form.py` to extract fields" (execute) vs "See `analyse_form.py` for the extraction algorithm" (read as reference). Default to execute.
- **Extract anything ≥ ~30 lines** of executable code from SKILL.md into `scripts/<name>.ps1` (or `.py` / `.mjs`). SKILL.md keeps a 5-line invocation example.

## Plan-validate-execute

For batch or destructive operations (updating 50 form fields, applying tracked changes to a document, rewriting a config across a fleet), use the plan-validate-execute pattern:

1. Claude analyses input and writes a structured plan file (`changes.json`).
2. A validator script checks the plan against the target (`validate.py changes.json`).
3. Only on validation pass does Claude execute the plan.

Verbose error messages from the validator are critical: `"Field 'signature_date' not found. Available fields: customer_name, order_total, signature_date_signed"` lets Claude fix the plan; `"Validation failed"` does not.

## Evaluation-driven development

Anthropic's strongest recommendation, often skipped: **build evaluations before writing extensive documentation.**

The lightweight loop that fits this repo:

1. **Identify gaps.** Run Claude on three representative tasks **without** the skill. Document every failure or missing context.
2. **Write three eval prompts** — the exact phrasing a real user would use. Save them to `notes-evals.md` in the skill folder.
3. **Establish baseline.** What did Claude produce without the skill? Keep the outputs.
4. **Write minimal SKILL.md** — just enough to fix the documented gaps.
5. **Re-run the evals with the skill loaded.** Verify the skill triggered (PRE-FLIGHT line names it). Compare outputs to the baseline.
6. **Iterate.** If the skill under-triggered → tighten the description. If it triggered but produced bad output → tighten the body or references.

Skip evals only for skills with subjective outputs (writing style, summarisation). Always eval skills with verifiable outputs (file conversion, parsing, code generation).

## Claude-A / Claude-B iteration

Use two Claude instances when refining a skill:

- **Claude A** — helps you author and refine the skill. Sees the SKILL.md, asks "is this too verbose?", suggests reorganisations, splits references.
- **Claude B** — uses the skill on real tasks in a fresh chat (no authoring context). Reveals where Claude actually struggles, ignores files, or misses connections.

Observe Claude B's behaviour. Bring concrete observations back to Claude A: "When Claude B asked for a regional sales report, it forgot to filter test accounts even though the skill mentions this rule. Make the rule more prominent."

This loop catches problems no static review finds, because the failure mode is "what an LLM actually does with this skill", not "what a human thinks the skill says".

## Cross-skill overlap audit

When two skills could plausibly fire on the same prompt, the auto-selector picks one inconsistently and outputs vary. Audit:

```powershell
# List all skill descriptions
Get-ChildItem Skills -Recurse -Filter SKILL.md | ForEach-Object {
    $name = $_.Directory.Name
    $desc = (Get-Content $_.FullName -Raw) -replace '(?s).*?description:\s*>-\s*(.+?)\n---.*', '$1'
    [PSCustomObject]@{ Name = $name; Length = $desc.Length; First120 = $desc.Substring(0, [Math]::Min(120, $desc.Length)) }
} | Sort-Object Name | Format-Table -AutoSize
```

For each overlapping pair, add the other skill's core nouns to `DO NOT USE FOR:` on both sides. Example: `outlook-email-export` and `outlook-calendar-export` cross-reference each other in their `DO NOT USE FOR:` lists.

## Anti-patterns

- **Description full of prose, not keywords.** The selector matches on lexical overlap, not semantics. Add the noun the user actually typed.
- **Body holds the trigger.** Invisible to the selector. Move triggers into the description.
- **Time-sensitive info in main content.** "After August 2025, use the new API." Will be wrong. Put legacy guidance in a `<details><summary>Old patterns</summary>` block.
- **Inconsistent terminology.** Pick one term ("API endpoint" or "URL", not both) and use it throughout.
- **Offering too many options.** "You can use pypdf, pdfplumber, PyMuPDF, or pdf2image." Pick a default; mention alternatives only as escape hatches with a clear "use X instead when Y".
- **Deeply nested references.** SKILL.md → `advanced.md` → `details.md` → `more.md`. Flatten.
- **SKILL.md tries to be a tutorial.** It is reference material for an LLM that already knows the domain. Cut introductions ("PDFs are a common file format..."). Assume Claude knows what a PDF is.
- **Folder name mismatches `name:`.** The CLI silently ignores the skill.

## Skill vs. instruction vs. agent

| Pick | When |
|---|---|
| **Skill** | A bounded workflow with concrete recipes. Loads on demand. Has a verifiable output. |
| **Instruction** (`Instructions/*.instructions.md`) | A coding-style or formatting rule that must apply to every edit of matching files. Always loaded for matching paths. |
| **Agent** (`Agents/*.agent.md`) | A persona with its own model, toolset, and multi-step methodology. The user explicitly switches into it. |
| **Prompt** (`Prompts/*.prompt.md`) | A one-shot template the user invokes from the picker. |

If two fit, prefer the lighter one. A skill is lighter than an agent; an instruction is lighter than a skill *only when the rule must always apply*.

## Authoring checklist

Before committing a skill:

- [ ] Folder name == `name:` (kebab-case, ≤ 64 chars, no `anthropic`/`claude`).
- [ ] Description ≤ 1024 chars, third-person, contains `USE FOR:` and (where adjacent skills exist) `DO NOT USE FOR:`.
- [ ] Body ≤ 500 lines (`(Get-Content SKILL.md).Count`).
- [ ] Deep material in `references/<topic>.md`, one level deep from SKILL.md.
- [ ] Reference files > 100 lines start with a `## Contents` TOC.
- [ ] Scripts ≥ ~30 lines extracted to `scripts/`.
- [ ] Forward slashes in all paths.
- [ ] No voodoo constants in scripts.
- [ ] No time-sensitive language in main content (legacy guidance in `<details>` blocks).
- [ ] Consistent terminology throughout.
- [ ] No maintenance footer; no `Last Updated` / `Maintained By`.
- [ ] Cross-skill overlap audited; `DO NOT USE FOR:` cross-references added where adjacent skills exist.
- [ ] At least three eval prompts written (in `notes-evals.md` or chat history); skill triggered by name in PRE-FLIGHT for each.

## Register the skill

No registration step. The `~/.copilot/skills` junction created by [`Setup-CopilotSettings.ps1`](../../Setup-CopilotSettings.ps1) exposes the folder to VS Code Copilot chat and the GitHub Copilot CLI automatically. Commit and the next session sees it.

## Splitting an oversized SKILL.md

Mechanical recipe when a body exceeds 500 lines:

1. **Identify topic boundaries.** Most large SKILL.md files have natural `## ` H2 sections that are self-contained recipes or topic areas.
2. **Group sections by audience need.** Sections that always fire together stay in SKILL.md; sections that only fire for specific sub-tasks move to references.
3. **Extract each large section** into `references/<topic-slug>.md`. The slug should match the noun a user would type ("ooxml", "tracked-changes", "form-filling").
4. **Replace the inline section** in SKILL.md with a two-line pointer:
   ```markdown
   ### Tracked changes
   For inserting `<w:ins>` / `<w:del>` elements with author and timestamp, read [`references/tracked-changes.md`](references/tracked-changes.md).
   ```
5. **Add `## Contents` TOC** to each reference > 100 lines.
6. **Verify SKILL.md ≤ 500 lines** and references are one level deep from SKILL.md.
7. **Re-run the evals.** Splitting can break triggering if it strips keywords from SKILL.md that Claude was relying on; the description is unchanged so triggering itself is unaffected, but post-trigger behaviour may shift.
