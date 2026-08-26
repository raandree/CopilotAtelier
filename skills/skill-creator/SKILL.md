---
name: skill-creator
description: >-
  Use this skill when authoring, auditing, or improving `Skills/**/SKILL.md`
  files against the Agent Skills open standard: progressive disclosure (body
  ≤ 500 lines, references one level deep), the six-step authoring frame,
  category-level descriptions with train/validation trigger evals, the
  1024-char description cap, and cross-skill overlap audits.
  Use it even when the user does not say "skill" — a request to package,
  reuse, or fix a repeatable workflow is in scope.
  USE FOR: authoring or revising a skill, building one out of existing
  material, deciding whether something deserves a skill at all and whether it
  is one skill, two, or a reference instead, diagnosing why one is not
  selected, description and discoverability work, frontmatter and budget
  conformance, and restructuring an oversized body into references.
  DO NOT USE FOR: writing `Instructions/*.instructions.md`,
  `Agents/*.agent.md`, or prompts; configuring MCP servers; running an eval
  harness end to end (use agent-evals).
---

# Skill Creator

Author and iteratively improve `Skills/**/SKILL.md` files for CopilotAtelier against the [Agent Skills open standard](https://agentskills.io/): the [specification](https://agentskills.io/specification), [best practices for skill creators](https://agentskills.io/skill-creation/best-practices), [optimizing skill descriptions](https://agentskills.io/skill-creation/optimizing-descriptions), [evaluating skill output quality](https://agentskills.io/skill-creation/evaluating-skills), and [using scripts in skills](https://agentskills.io/skill-creation/using-scripts). The same loop applies to brand-new skills, skills that under-trigger, and skills whose body has grown past the 500-line budget.

For a condensed two-page primer with links to the canonical external sources, see [`Reference/howto-write-skills.md`](../../Reference/howto-write-skills.md).

## When to Use

- The user says "turn this into a skill", "save this workflow", "package this for reuse", "why isn't this skill triggering", or "this skill is too long".
- A SKILL.md exceeds 500 lines or has no `references/` directory but covers multiple sub-topics.
- A repeated workflow has emerged across recent sessions (check `.memory-bank/progress.md` and `.memory-bank/promptHistory.md`).
- Two skills compete for the same triggers and you need an overlap audit.

## Philosophy: less is more

A small, well-described, properly split skill library outperforms a large one. Every skill's `description` is always loaded; with hundreds of generic skills installed, the auto-selector picks the wrong one or none at all. Curate ruthlessly. Prefer fixing an existing skill over adding a new one.

## Start from real expertise, not from the model

The most common way to produce a worthless skill is to ask an LLM to write one from its general training knowledge. The output is generic procedure — "handle errors appropriately", "follow best practices" — instead of the specific API patterns, edge cases, and project conventions that make a skill worth loading. Ground every skill in project-specific material:

- **Extract from a hands-on task.** Complete the real task in conversation first, then harvest the reusable pattern. Pay attention to the steps that worked, the corrections you had to make, the input/output formats, and the project facts the agent did not already know.
- **Synthesize from existing artifacts.** Runbooks, style guides, schemas, code-review comments, issue trackers, and version-control history (especially fixes) encode real failure modes. A skill built from your incident reports beats one built from a generic best-practices article.

## SKILL.md anatomy

```
Skills/<kebab-name>/
├── SKILL.md         (required — frontmatter + body, ≤ 500 lines)
├── references/      (optional — deep docs loaded on demand, one level deep)
├── scripts/         (optional — executable helpers; .ps1 preferred)
├── assets/          (optional — templates, sample inputs, expected outputs)
└── evals/           (optional — evals.json + input files; see agent-evals)
```

Folder name MUST match the `name:` field. Anything beyond `SKILL.md` is opt-in.

## Interaction style

When interviewing the user about a new or existing skill (scope, triggers, dependencies, edge cases), follow the shared convention in [`Reference/interactive-questions.md`](../../Reference/interactive-questions.md): prefer `vscode_askQuestions` over markdown checkboxes when the tool is available.

## The six-step authoring frame

Use this frame before writing a single line of SKILL.md. If any step is unclear, the skill scope is wrong — stop and refine.

1. **Name.** Short kebab-case label that describes the activity. Gerund form (`processing-pdfs`) is the upstream recommendation; noun phrases (`pdf-processing`) are acceptable and dominate this repo. Max 64 chars. No `claude` or `anthropic`.
2. **Trigger.** The `description` the selector reads to decide whether to load the skill. Get this wrong and the skill never activates. See [Writing the description](#writing-the-description) below.
3. **Outcome.** Define what "done" looks like in one sentence before writing instructions. If you cannot, the skill is two skills.
4. **Dependencies.** Every tool, MCP server, reference file, script, or asset the skill needs. List them up front; surprises mid-execution are a quality bug.
5. **Step-by-step.** Exact instructions the agent follows in order, with explicit human-in-the-loop points where applicable.
6. **Edge cases.** What happens when input is vague, missing, oversized, or unexpected. Robust skills handle failure gracefully; brittle ones silently produce wrong output.

## Design coherent units

Scoping a skill is like scoping a function: it should encapsulate one coherent unit of work that composes with other skills. Too narrow and several skills must load for one task, risking overhead and conflicting instructions. Too broad and it cannot be activated precisely. Querying a database and formatting the results is one unit; adding database administration to the same skill is two.

## Frontmatter

```yaml
---
name: kebab-case-id        # matches folder name; max 64 chars
description: >-            # block scalar; ≤ 1024 chars total
  Use this skill when <user intent>. Covers <the concrete capabilities>.
  Applies even when the user does not name the domain explicitly.
  USE FOR: the general categories of request this skill serves.
  DO NOT USE FOR: adjacent skill (use other-skill instead), near-miss
  request that belongs elsewhere.
---
```

Hard limits: `name` ≤ 64 chars; `description` ≤ 1024 chars, non-empty, no XML tags. The GitHub Copilot CLI silently drops skills whose description exceeds 1024 chars; the VS Code surface is more forgiving but still penalises long descriptions in selection accuracy.

Verify length:

```powershell
$desc = (Get-Content SKILL.md -Raw -Encoding utf8 | Select-String -Pattern 'description:\s*>-\s*(.+?)(?=\n---)' -AllMatches).Matches[0].Groups[1].Value
$desc.Length
```

The reference validator from the open standard checks frontmatter and naming mechanically:

```powershell
skills-ref validate ./Skills/<skill-name>
```

The template above shows the two required fields. Optional ones the standard and the VS Code surface also accept — `compatibility`, `license`, `metadata`, `allowed-tools`, `argument-hint`, `user-invocable`, `disable-model-invocation`, `context` — are listed with their constraints in [`rules/copilot-authoring.instructions.md`](../../com.github.copilot/rules/copilot-authoring.instructions.md). Declare `compatibility` whenever the skill needs a specific operating system, runtime, module, or external binary. `context: fork` is a GitHub Copilot field the open standard does not define, so a skill that sets it fails `skills-ref` and belongs on the divergence baseline in [`tests/SkillsRefValidate.Tests.ps1`](../../tests/SkillsRefValidate.Tests.ps1).

When a skill depends on MCP tools, name them **fully qualified** as `ServerName:tool_name` wherever they appear - in `allowed-tools`, in the dependency list, and in the body. A bare `tool_name` is ambiguous once two servers expose the same verb, and the permission match silently fails.

## Writing the description

The `description` is the **only** thing the auto-selector sees. Body text never influences triggering. How the selector matches is not publicly documented, so write for both possibilities: name the categories the skill serves *and* carry their vocabulary, rather than betting on lexical overlap or on semantics alone.

Rules, in order of impact:

1. **Use imperative phrasing.** Frame the description as an instruction to the agent — "Use this skill when the user has a CSV and wants to explore or transform the data" — not as a self-description ("This skill processes CSV files"). The agent is deciding whether to act, so tell it when to act.
2. **Describe user intent, not implementation.** The selector matches against what the user asked for, not against your internal mechanics.
3. **Be pushy about scope.** Explicitly name the contexts where the skill applies, including the ones where the user will not say the magic word: "even if they don't explicitly mention 'CSV' or 'analysis'". Under-triggering is the more common failure.
4. **Keep the domain vocabulary; drop the failed-query wording.** These are not the same thing, and conflating them costs triggering. The specification asks for "specific keywords that help agents identify relevant tasks", so name the formats, tools, error strings, and domain terms a user would plausibly type. What overfits is narrower: pasting in the verbatim phrasing of eval queries that failed, which yields a description that works on those exact strings and nothing near them. Name the category those queries represent, and keep the vocabulary that belongs to it. This repo's `USE FOR:` is that compact scope list.
5. **Use `DO NOT USE FOR:` to draw the boundary.** Name the adjacent skill that should win. This is the single highest-leverage anti-cannibalisation tool when two skills overlap, and it is what upstream means by "clarify the boundary between this skill and adjacent capabilities".
6. **Never write a vague description.** "Helps with documents" and "Does stuff with files" are auto-selector poison.

Neither first nor second person belongs in a description aimed at the *user* ("I can help you...", "You can use this to..."); the imperative in rule 1 is addressed to the agent, which is a different thing.

### Third person vs. imperative: the sources disagree, the fix does not

Two live upstream guides state different rules, and an author reading only one of them will think this skill is wrong:

- Anthropic's [best-practices guide](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices) says **always write in third person** ("Analyzes CSV files...").
- The open standard's [optimizing-descriptions guide](https://agentskills.io/skill-creation/optimizing-descriptions.md) says **use imperative phrasing** ("Use this skill when...").

Neither is stale, and they are not actually in conflict — they describe different clauses of the same sentence. Write **third-person voice for the capability, imperative for the trigger**, which is what the worked examples in both guides do:

> Analyses CSV and Excel files for statistics, filtering, and visualisation. Use this skill when the user has a spreadsheet and wants to explore or transform the data, even if they do not say "CSV" or "analysis".

Do not write the skill as a first-person actor ("I analyse CSV files") and do not address the user ("You can use this to..."). Both violate every version of the rule.

### Why a perfect description still may not fire

Agents typically consult a skill only for tasks that need knowledge or capability beyond what they can already handle. A one-step request like "read this PDF" may not trigger a PDF skill however well the description matches, because the agent can just do it. Before rewriting a description, check that the eval query is actually hard enough to warrant a skill.

## Trigger evals: prove the description works

Do not tune a description by intuition. Build a labelled query set and measure: roughly 20 queries split 8–10 positive and 8–10 **near-miss** negative, a fixed 60/40 train/validation split, 3 runs per query against a 0.5 trigger-rate threshold, iteration driven by train-set failures only, and selection by validation pass rate rather than by recency. A negative like "write a fibonacci function" tests nothing; the useful ones share vocabulary with the skill and still belong elsewhere.

In this repository the query set is a committed asset at `Skills/agent-evals/assets/trigger-queries.<name>.json`, and [`tests/SkillTriggerCoverage.Tests.ps1`](../../tests/SkillTriggerCoverage.Tests.ps1) fails when a shipped skill has neither a query set nor a documented baseline entry. For the full six-step procedure read [`references/scripts-and-evaluation.md`](references/scripts-and-evaluation.md); [`agent-evals`](../agent-evals/SKILL.md) owns the harness and the file layout.

## Progressive disclosure: point, don't dump

Three loading tiers. Respect them or the skill bloats context on every invocation. Progressive disclosure is **context engineering** applied to skills — curate what reaches the model's finite context window and when, paying the token cost of a body or reference only when the task needs it.

| Tier | What loads | When | Budget |
|---|---|---|---|
| Metadata | `name` + `description` | Always | ~100 tokens per skill |
| Body | SKILL.md text | When skill triggers | ≤ 500 lines (~5k tokens) |
| References / scripts / assets | Files in subfolders | On demand by the assistant | Effectively unlimited |

**Point, don't dump.** The SKILL.md body is the standard operating procedure — the process. Deep knowledge (XML schemas, API tables, long examples, large code blocks) belongs in `references/<topic>.md`, linked with a pointer that says *when* to load it:

```markdown
If the API returns a non-200 status, read [`references/api-errors.md`](references/api-errors.md).
```

A generic "see `references/` for details" is close to useless; the trigger condition is what makes on-demand loading work.

When the body crosses 500 lines, extract self-contained topics into references. The SKILL.md body becomes a navigation map: When-To-Use, recipes summarised in two or three sentences each, pointers to deep references.

## Spend context on what the agent lacks

Every token in the body competes for attention with the conversation, the system context, and every other active skill. For each piece of content ask: *would the agent get this wrong without this instruction?* If no, cut it. Do not explain what a PDF is, how HTTP works, or what a migration does. Write project-specific conventions, domain procedures, non-obvious edge cases, and which tool to use.

Aim for moderate detail. Exhaustive documentation hurts: the agent struggles to find the relevant part and may pursue unproductive paths triggered by instructions that do not apply to the current task. Concise stepwise guidance with one working example beats a manual. If the agent already handles the whole task well without the skill, the skill is not adding value — delete it.

## References: one level deep

When references link to further references, agents often preview them with `head -100` instead of reading them fully, producing incomplete information.

- All reference files link directly from SKILL.md.
- Never link `references/foo.md` → `references/bar.md` → `references/baz.md`.
- Reference files longer than 100 lines must start with a `## Contents` table-of-contents so the agent sees the full scope even from a partial preview.

## Calibrating how prescriptive to be

Match the specificity of an instruction to the task's fragility: exact commands for fragile low-freedom steps, general direction for open-ended ones, and reasoning rather than directives wherever the agent has a real choice to make. Classify the failure first against [Match the form to the failure](#match-the-form-to-the-failure), then pick the register. The freedom table, the bridge-versus-field analogy, and the procedures-over-declarations rule are in [`references/authoring-patterns.md`](references/authoring-patterns.md); read it when you are unsure how tightly to constrain a step.

## Gotchas: usually the highest-value section

A gotcha is an environment-specific fact that defies a reasonable assumption — a concrete correction to a mistake the agent will otherwise make. It is not general advice.

```markdown
## Gotchas

- The `users` table uses soft deletes. Queries must include `WHERE deleted_at IS NULL` or results include deactivated accounts.
- The identifier is `user_id` in the database, `uid` in the auth service, and `accountId` in the billing API. All three are the same value.
- `/health` returns 200 whenever the web server is up, even with the database down. Use `/ready` for real health.
```

Keep gotchas in SKILL.md, where the agent reads them *before* hitting the situation. A separate reference file works only if you state the load condition — and for a non-obvious issue the agent will not recognise the trigger, which defeats it.

**Grow the list from corrections.** Every time you have to correct the agent mid-task, that correction is a gotcha. Adding it is the single most direct way to improve a skill iteratively.

For the seven remaining structural patterns — guide-plus-references, domain-organised references, conditional workflow, workflow checklist, feedback loop, output template, and input/output examples — read [`references/authoring-patterns.md`](references/authoring-patterns.md) before inventing a structure of your own.

## Match the form to the failure

Before writing a line of guidance, classify the baseline failure you actually observed. The form that fixes one failure type measurably backfires on another, so this classification decides the shape of everything below it.

| Baseline failure | Right form | Wrong form |
|---|---|---|
| Knows the rule, skips it under pressure | Prohibition, plus an anti-rationalization table and red flags | Soft guidance ("prefer", "consider") |
| Complies, but the output has the wrong shape | A positive recipe: state what the output **is** — its parts, in order | A list of prohibitions |
| Omits a required element from output it already produces | A structural REQUIRED slot in the template it fills in | Prose reminders near the template |
| Behaviour should depend on a condition | A conditional keyed to an observable predicate | An unconditional rule plus exemption clauses |

Prohibitions work on discipline failures because the agent already knows the right answer and only needs the shortcut closed. They backfire on shaping failures: given a competing incentive, an agent negotiates with "don't do X" and can produce more of the unwanted content than no guidance at all. A recipe leaves nothing to negotiate — the output either matches the stated shape or it does not.

Two rules hold whichever form you pick:

- **No nuance clauses.** "Don't do X unless it matters" reopens the negotiation. Express a real exception as its own conditional on an observable predicate.
- **Exemption clauses do not scope.** "This limit does not apply to code blocks" still suppresses code blocks. If part of the output must be exempt, restructure so the rule cannot reach it.

Classify from observed behaviour, not from intuition. A micro-test settles it in minutes.

## Behavioural enforcement: rationalizations, red flags, evidence

Structural patterns keep a skill readable; these three sections keep the *agent on process* when the shortest path tempts it to skip a step. They are the discipline-failure form from the table above: add them to a skill that encodes a step an agent abandons under pressure — tests, security checks, verification, destructive-operation guards. Do not reach for them on a shaping failure, where a recipe or a required slot is the correct instrument, and skip them entirely for skills with purely subjective output (writing style, summarisation) where there is no step to enforce.

### Anti-rationalization table

Agents invent plausible excuses to drop the expensive step. Pre-empt each one so that when the model reaches for the excuse, the rebuttal is already on the page. Two columns: the excuse, and why it does not hold in this skill's context.

| Rationalization | Reality |
|---|---|
| "I'll add the tests afterwards." | Untested code is unverified code. Write the test in the same change or the behaviour is unproven. |
| "This edit is too small to verify." | Small edits cause outsized breakage. Run the check regardless of diff size. |
| "The check is slow, skip it this once." | A missed defect costs more than the check. Speed is not a waiver. |

Keep entries specific to the skill's real failure modes; generic platitudes cost tokens without changing behaviour.

### Red flags

A short list of observable symptoms that the skill is going wrong *right now*, so the agent or a reviewer catches drift before it ships. Phrase each as a symptom, not a rule.

- About to report success without having run the verification step.
- Editing the canonical artifact directly instead of a working copy for a destructive operation.
- Switching tools because the first one "seems" broken, with no error message captured.

The instruction when a red flag fires is to stop and re-enter the process, never to push through.

### Evidence / verification (non-negotiable close)

Every skill with a checkable output ends with an explicit evidence requirement. "Looks right" is never enough — name the artifact that proves it and the check that produces it: passing test output, a clean parse, a `Test-Path` result, a rendered file, a byte count. State the command and what a pass looks like.

```markdown
## Verification

Confirm before reporting done:

- `markdownlint-cli2 SKILL.md` → 0 errors.
- `(Get-Content SKILL.md).Count` → ≤ 500.
- Skill triggered by name on the PRE-FLIGHT line of a fresh eval run.
```

This mirrors the repo's turn-level post-flight gate at the skill level: the skill refuses to declare success without proof.

## Scripts, batch operations, and evaluation

When the skill will ship anything under `scripts/`, performs batch or destructive operations, or is ready for its output evals, read [`references/scripts-and-evaluation.md`](references/scripts-and-evaluation.md). It covers solve-don't-punt error handling, the non-interactive caller interface (never prompt, structured stdout, bounded output, distinct exit codes), plan-validate-execute for destructive batches, the full trigger-eval procedure, evaluation-driven development, and how to read the results.

Two rules from it are load-bearing often enough to state here: extract anything ≥ ~30 lines of executable code into `scripts/`, leaving a 5-line invocation example in the body; and build the evaluations *before* writing extensive documentation, because an eval written afterwards tests what you wrote rather than what was missing.

For iteration technique — the Claude-A / Claude-B loop and testing across model tiers — see [`references/authoring-patterns.md`](references/authoring-patterns.md).

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

For each overlapping pair, add the other skill's scope boundary to `DO NOT USE FOR:` on both sides. Example: `outlook-email-export` and `outlook-calendar-export` cross-reference each other. Then confirm the fix with near-miss negatives in the trigger eval set — a `DO NOT USE FOR:` line that was never measured is a guess.

## Anti-patterns

The two that cost the most here: a **description written as self-description** ("This skill converts files") never competes well against a sibling that says when to act, and a **skill generated from the model's general knowledge** produces generic procedure that fails the only test that matters — whether the agent does better with it than without. The full list, including time-sensitive content, nested references, pointers with no load condition, and folder-name mismatch, is in [`references/authoring-patterns.md`](references/authoring-patterns.md).

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
- [ ] Description ≤ 1024 chars, imperative ("Use this skill when..."), category-level `USE FOR:`, and `DO NOT USE FOR:` where adjacent skills exist.
- [ ] Body ≤ 500 lines (`(Get-Content SKILL.md).Count`).
- [ ] Content grounded in real project artifacts, not model-generated generalities.
- [ ] Gotchas section present where the domain has assumption-defying facts, and kept in SKILL.md.
- [ ] Baseline failure classified and the guidance form matches it — discipline, shaping, omission, or conditional.
- [ ] Flexible instructions explain the why; rigid directives reserved for fragile low-freedom steps.
- [ ] Behavioural enforcement present where the skill encodes a skippable discipline: anti-rationalization table + red-flags list + verification/evidence close (skip only for purely subjective-output skills).
- [ ] Deep material in `references/<topic>.md`, one level deep, each pointer stating its load condition.
- [ ] Reference files > 100 lines start with a `## Contents` TOC.
- [ ] Scripts ≥ ~30 lines extracted to `scripts/`; forward slashes; no voodoo constants; non-interactive, with `--help`, documented exit codes, and bounded output.
- [ ] No time-sensitive language in main content (legacy guidance in `<details>` blocks).
- [ ] Consistent terminology throughout.
- [ ] No maintenance footer; no `Last Updated` / `Maintained By`.
- [ ] Cross-skill overlap audited; `DO NOT USE FOR:` cross-references added where adjacent skills exist.
- [ ] Trigger evals run with a fixed 60/40 train/validation split; the shipped description selected by validation pass rate.
- [ ] Output evals run with a without-skill (or previous-version) baseline; the delta justifies the skill's token cost.

## Register the skill

No registration step. The `~/.copilot/skills` junction created by [`Setup-CopilotSettings.ps1`](../../Setup-CopilotSettings.ps1) exposes the folder to VS Code Copilot chat and the GitHub Copilot CLI automatically. Commit and the next session sees it.

## Splitting an oversized SKILL.md

Mechanical recipe when a body exceeds 500 lines:

1. **Identify topic boundaries.** Most large SKILL.md files have natural `## ` H2 sections that are self-contained recipes or topic areas.
2. **Group sections by audience need.** Sections that always fire together stay in SKILL.md; sections that only fire for specific sub-tasks move to references. Gotchas always stay.
3. **Extract each large section** into `references/<topic-slug>.md`. The slug should match the noun a user would type ("ooxml", "tracked-changes", "form-filling").
4. **Replace the inline section** in SKILL.md with a two-line pointer that states the load condition:
   ```markdown
   ### Tracked changes
   When the document requires revision marks, read [`references/tracked-changes.md`](references/tracked-changes.md) for the `<w:ins>` / `<w:del>` elements with author and timestamp.
   ```
5. **Add `## Contents` TOC** to each reference > 100 lines.
6. **Verify SKILL.md ≤ 500 lines** and references are one level deep from SKILL.md.
7. **Re-run the evals.** The description is unchanged so triggering itself is unaffected, but post-trigger behaviour may shift.
