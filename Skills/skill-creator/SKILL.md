---
name: skill-creator
description: >-
  Use this skill when authoring, auditing, or improving `Skills/**/SKILL.md`
  files against the Agent Skills open standard: progressive disclosure (body
  ≤ 500 lines, references one level deep), the six-step authoring frame,
  category-level imperative descriptions with train/validation trigger evals,
  the 1024-char description cap, gotchas sections, degrees-of-freedom
  calibration, output evals, and cross-skill overlap audits.
  Use it even when the user does not say "skill" — a request to package,
  reuse, or fix a repeatable workflow is in scope.
  USE FOR: authoring or revising a skill, diagnosing why one is not selected,
  description and discoverability work, frontmatter and budget conformance,
  restructuring an oversized body into references, capturing environment
  gotchas, and resolving overlap between adjacent skills.
  DO NOT USE FOR: writing `Instructions/*.instructions.md`,
  `Agents/*.agent.md`, or prompts; configuring MCP servers; running an eval
  harness end to end (use agent-evals).
---

# Skill Creator

Author and iteratively improve `Skills/**/SKILL.md` files for CopilotAtelier against the [Agent Skills open standard](https://agentskills.io/): the [specification](https://agentskills.io/specification), [best practices for skill creators](https://agentskills.io/skill-creation/best-practices), [optimizing skill descriptions](https://agentskills.io/skill-creation/optimizing-descriptions), and [evaluating skill output quality](https://agentskills.io/skill-creation/evaluating-skills). The same loop applies to brand-new skills, skills that under-trigger, and skills whose body has grown past the 500-line budget.

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

When a skill depends on MCP tools, name them **fully qualified** as `ServerName:tool_name` wherever they appear - in `allowed-tools`, in the dependency list, and in the body. A bare `tool_name` is ambiguous once two servers expose the same verb, and the permission match silently fails.

## Writing the description

The `description` is the **only** thing the auto-selector sees. Body text never influences triggering. How the selector matches is not publicly documented, so write for both possibilities: name categories rather than betting on lexical overlap or on semantics.

Rules, in order of impact:

1. **Use imperative phrasing.** Frame the description as an instruction to the agent — "Use this skill when the user has a CSV and wants to explore or transform the data" — not as a self-description ("This skill processes CSV files"). The agent is deciding whether to act, so tell it when to act.
2. **Describe user intent, not implementation.** The selector matches against what the user asked for, not against your internal mechanics.
3. **Be pushy about scope.** Explicitly name the contexts where the skill applies, including the ones where the user will not say the magic word: "even if they don't explicitly mention 'CSV' or 'analysis'". Under-triggering is the more common failure.
4. **Keep `USE FOR:` at the level of categories, not phrasings.** This repo's house convention gives the selector a compact scope list. Populate it with the general classes of request the skill serves. Do **not** paste in the verbatim wording of queries that failed to trigger — that is overfitting, and it produces a description that works on those exact strings and nothing near them. Find the category the failed queries represent and name that instead.
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

Do not tune a description by intuition. Build a labelled query set and measure.

1. **Write ~20 queries** — 8–10 that should trigger, 8–10 that should not, each labelled `should_trigger`.
   - **Positives** vary along phrasing (formal, casual, typos), explicitness (some name the domain, some only describe the need), detail (terse and context-heavy), and complexity (single-step and multi-step). The most useful positives are the ones where the skill helps but the connection is not obvious from the query.
   - **Negatives must be near-misses.** "Write a fibonacci function" tests nothing. "Update the formulas in my Excel budget spreadsheet" shares concepts with a CSV-analysis skill but needs something else — that is a real test of precision.
   - Make them realistic: file paths, personal context ("my manager asked me to"), specific column and company names, abbreviations.
2. **Split 60/40 into train and validation**, each with a proportional mix of positives and negatives. Shuffle once and keep the split fixed across iterations.
3. **Run each query 3 times** and compute a trigger rate. A positive passes above 0.5; a negative passes below it. Model behaviour is nondeterministic — one run is noise.
4. **Iterate on train-set failures only.** Keep validation results out of the revision process entirely.
   - Positives failing → the description is too narrow. Broaden the scope or add context about when the skill is useful.
   - Negatives firing → the description is too broad. Add specificity about what the skill does *not* do, or sharpen `DO NOT USE FOR:`.
   - Stuck after several rounds → try a structurally different framing rather than another incremental tweak.
   - Watch the 1024-char cap; descriptions grow during optimisation.
5. **Select by validation pass rate, not by recency.** The best description is often not the last one you wrote — a later iteration may have overfitted the train set. Five iterations is usually enough; if nothing improves, the queries are the problem (too easy, too hard, or mislabelled), not the description.
6. **Sanity-check with fresh queries.** Write 5–10 new labelled queries that were never part of optimisation and run them for an honest generalisation check.

[`agent-evals`](../agent-evals/SKILL.md) owns the harness and the file layout.

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

## Degrees of freedom

Match the level of specificity in your instructions to the task's fragility. Most skills mix all three; calibrate each part independently.

| Freedom | When to use | Pattern |
|---|---|---|
| **High** | Multiple approaches valid; decisions depend on context | Prose checklist: "Analyse the code structure, check for edge cases, suggest improvements." |
| **Medium** | A preferred pattern exists; some variation acceptable | Pseudocode or script with parameters: `generate_report(data, format="markdown")`. |
| **Low** | Operations are fragile; consistency critical; specific sequence required | Exact command: `python scripts/migrate.py --verify --backup`. "Do not modify the command." |

The analogy: a narrow bridge with cliffs on both sides needs guardrails (low freedom); an open field needs only a general direction (high freedom). Database migrations are bridges; code reviews are fields.

### Explain the why on flexible instructions

Where the instruction is high or medium freedom, reasoning beats directive: "Do X because Y tends to cause Z" outperforms "ALWAYS do X, NEVER do Y". An agent that understands the purpose makes better context-dependent decisions. This is not in tension with the prohibitions in [Behavioural enforcement](#behavioural-enforcement-rationalizations-red-flags-evidence) below — those exist for discipline failures on fragile, low-freedom steps, where there is nothing to reason about and the only job is closing a shortcut. Classify the failure first (see [Match the form to the failure](#match-the-form-to-the-failure)), then pick the register.

### Favor procedures over declarations

Teach the agent *how to approach* a class of problems, not *what to produce* for one instance. "Read the schema from `references/schema.yaml`, join on the `_id` convention, apply the user's filters as WHERE clauses" generalises; "join `orders` to `customers` on `customer_id` and sum `amount`" does not. Specific details still belong in a skill — output templates, constraints like "never output PII", tool-specific commands — but the *approach* must generalise.

## Pattern catalogue

Reach for these before inventing structure. Not every skill needs all of them.

### Pattern 1 — Gotchas section

Usually the highest-value content in a skill. A gotcha is an environment-specific fact that defies a reasonable assumption — a concrete correction to a mistake the agent will otherwise make. It is not general advice.

```markdown
## Gotchas

- The `users` table uses soft deletes. Queries must include `WHERE deleted_at IS NULL` or results include deactivated accounts.
- The identifier is `user_id` in the database, `uid` in the auth service, and `accountId` in the billing API. All three are the same value.
- `/health` returns 200 whenever the web server is up, even with the database down. Use `/ready` for real health.
```

Keep gotchas in SKILL.md, where the agent reads them *before* hitting the situation. A separate reference file works only if you state the load condition — and for a non-obvious issue the agent will not recognise the trigger, which defeats it.

**Grow the list from corrections.** Every time you have to correct the agent mid-task, that correction is a gotcha. Adding it is the single most direct way to improve a skill iteratively.

### Pattern 2 — High-level guide + references

SKILL.md gives quick-start. Each domain or advanced topic lives in `references/<topic>.md`. Use when the skill covers one tool with multiple sub-areas (e.g. `pdf-processing` with `forms.md`, `tables.md`, `merging.md`).

### Pattern 3 — Domain-organised references

SKILL.md is a navigation map; references are split by domain (`finance.md`, `sales.md`, `product.md`). Use when the skill spans multiple independent data sets or topics where any one task only needs one.

### Pattern 4 — Conditional workflow

SKILL.md describes a decision tree; each branch points to a reference or script. Use when the workflow forks early on input type ("creating new doc → follow A; editing existing → follow B").

### Pattern 5 — Workflow checklist

For complex multi-step tasks, provide a copyable checklist the agent tracks across the conversation. Most valuable when steps have dependencies or validation gates.

```markdown
Task Progress:
- [ ] Step 1: Analyse the form (run `scripts/analyze_form.py`)
- [ ] Step 2: Create field mapping (edit `fields.json`)
- [ ] Step 3: Validate mapping (run `scripts/validate_fields.py`)
- [ ] Step 4: Fill the form
- [ ] Step 5: Verify output
```

### Pattern 6 — Feedback loop

`run → validate → fix → repeat`. Document the validator (script or rubric), the loop, and the exit condition. This pattern dramatically improves output quality on quality-critical tasks (form filling, XML edits, document generation). A reference document can serve as the validator: instruct the agent to check its work against it before finalising.

### Pattern 7 — Output template

When output must take a specific shape, provide a template rather than describing the format in prose — agents pattern-match against concrete structures far more reliably. Short templates live inline; long or conditionally-needed ones go in `assets/` and load on demand.

### Pattern 8 — Examples (input → output pairs)

When output quality depends on style, include two or three input/output pairs in SKILL.md. Examples beat descriptions when the user wants a specific shape.

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

## Scripts: solve, don't punt

When a skill bundles executable code (`scripts/`):

- **Handle errors explicitly.** Catch `FileNotFoundError`, `PermissionError`, etc. and either recover with a documented default or fail with a specific actionable message. Do not let the script crash and leave the agent to guess.
- **No voodoo constants.** Every numeric literal (`TIMEOUT = 47`, `MAX_RETRIES = 5`) needs a one-line comment justifying it. "Why 47?" must have an answer.
- **Use forward slashes** in all paths (`scripts/helper.py`, not `scripts\helper.py`). Windows paths break on Unix.
- **Make execution intent explicit**: "Run `analyse_form.py` to extract fields" (execute) vs "See `analyse_form.py` for the extraction algorithm" (read as reference). Default to execute.
- **Extract anything ≥ ~30 lines** of executable code from SKILL.md into `scripts/<name>.ps1` (or `.py` / `.mjs`). SKILL.md keeps a 5-line invocation example.
- **Bundle what the agent keeps reinventing.** If execution traces across eval runs show the agent independently rewriting the same chart builder, parser, or validator each time, write it once and ship it in `scripts/`.

## Plan-validate-execute

For batch or destructive operations (updating 50 form fields, applying tracked changes to a document, rewriting a config across a fleet), use the plan-validate-execute pattern:

1. The agent analyses input and writes a structured plan file (`changes.json`).
2. A validator script checks the plan against the target (`validate.py changes.json`).
3. Only on validation pass does the agent execute the plan.

Verbose error messages from the validator are critical: `"Field 'signature_date' not found. Available fields: customer_name, order_total, signature_date_signed"` lets the agent fix the plan; `"Validation failed"` does not.

## Evaluation-driven development

The strongest and most-skipped recommendation: **build evaluations before writing extensive documentation.** Trigger evals (above) prove the skill fires; output evals prove it helps.

1. **Identify gaps.** Run the agent on representative tasks **without** the skill. Document every failure or missing context.
2. **Write 2–3 test cases** — the exact phrasing a real user would use, plus a human-readable description of what success looks like, plus any input files. Do not over-invest before the first round of results.
3. **Establish baseline.** Keep the without-skill outputs. When improving an existing skill, snapshot the previous version and use that as the baseline instead.
4. **Write minimal SKILL.md** — just enough to fix the documented gaps.
5. **Re-run with the skill loaded**, in a clean context per run. Verify the skill triggered (PRE-FLIGHT line names it). Compare with-skill against without-skill on pass rate, tokens, and duration.
6. **Add assertions after the first run**, once you know what good output looks like, and grade each with concrete evidence.
7. **Iterate.** Under-triggered → tighten the description. Triggered but wrong → tighten the body or references.

[`agent-evals`](../agent-evals/SKILL.md) owns the file layout, assertion and grading formats, and the benchmark deltas.

### Reading the results

- **Assertions that always pass in both arms** measure nothing — the model handles them unaided. Remove or replace them; they inflate the with-skill pass rate without reflecting value.
- **Assertions that always fail in both arms** are broken, or the test case is too hard. Fix before the next iteration.
- **Assertions that pass with the skill and fail without** are where the value is. Understand *which* instruction made the difference.
- **High variance across runs** means the eval is flaky or the instruction is ambiguous enough to be read differently each time. Add an example or sharpen the wording.
- **Time and token outliers** warrant reading the execution transcript for the bottleneck.

### Keep the skill lean — and know when to remove

Fewer, better instructions often outperform exhaustive rules. If transcripts show wasted work — unnecessary validation, unneeded intermediate output — remove those instructions. **If pass rates plateau while you keep adding rules, the skill is probably over-constrained: delete instructions and check whether results hold or improve.** Adding is the reflex; subtracting is the fix more often than authors expect.

Generalise every fix. The skill runs against many prompts, not just the test cases — address the underlying issue rather than patching the specific example.

## Claude-A / Claude-B iteration

Use two instances when refining a skill:

- **A** — helps you author and refine. Sees the SKILL.md, asks "is this too verbose?", suggests reorganisations, splits references.
- **B** — uses the skill on real tasks in a fresh chat, with no authoring context. Reveals where the agent actually struggles, ignores files, or misses connections.

Observe B's behaviour and bring concrete observations back to A: "When B asked for a regional sales report, it forgot to filter test accounts even though the skill mentions this rule. Make the rule more prominent." This loop catches problems no static review finds, because the failure mode is "what an LLM actually does with this skill", not "what a human thinks the skill says".

### Test across model tiers

Run the skill on the weakest and strongest models it will realistically meet — Haiku, Sonnet, and Opus. Instructions that a stronger model infers from context, a weaker one needs stated. A skill that only works on the top tier is under-specified, not elegant; a skill that a weak model follows correctly will not confuse a strong one. Where the tiers diverge, the divergence names the implicit assumption to write down.

For comparing two versions, try **blind comparison**: present both outputs to a judge without revealing which came from which version, and let it score organisation, formatting, and polish on its own rubric. Two outputs can pass identical assertions and still differ sharply in quality.

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

- **Description written as self-description.** "This skill converts files." Frame it as an instruction: "Use this skill when...".
- **Description tuned to verbatim failed queries.** Overfitting. Name the category those queries represent instead.
- **Body holds the trigger.** Invisible to the selector. Move triggers into the description.
- **Skill generated from the model's general knowledge.** Produces generic procedure. Ground it in project artifacts.
- **Time-sensitive info in main content.** "After August 2025, use the new API." Will be wrong. Put legacy guidance in a `<details><summary>Old patterns</summary>` block.
- **Inconsistent terminology.** Pick one term ("API endpoint" or "URL", not both) and use it throughout.
- **Offering too many options.** "You can use pypdf, pdfplumber, PyMuPDF, or pdf2image." Pick a default; mention alternatives only as escape hatches with a clear "use X instead when Y".
- **Deeply nested references.** SKILL.md → `advanced.md` → `details.md` → `more.md`. Flatten.
- **Reference pointer with no load condition.** "See `references/` for details." State when to read it.
- **SKILL.md tries to be a tutorial.** It is reference material for an LLM that already knows the domain. Cut introductions ("PDFs are a common file format...").
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
- [ ] Description ≤ 1024 chars, imperative ("Use this skill when..."), category-level `USE FOR:`, and `DO NOT USE FOR:` where adjacent skills exist.
- [ ] Body ≤ 500 lines (`(Get-Content SKILL.md).Count`).
- [ ] Content grounded in real project artifacts, not model-generated generalities.
- [ ] Gotchas section present where the domain has assumption-defying facts, and kept in SKILL.md.
- [ ] Baseline failure classified and the guidance form matches it — discipline, shaping, omission, or conditional.
- [ ] Flexible instructions explain the why; rigid directives reserved for fragile low-freedom steps.
- [ ] Behavioural enforcement present where the skill encodes a skippable discipline: anti-rationalization table + red-flags list + verification/evidence close (skip only for purely subjective-output skills).
- [ ] Deep material in `references/<topic>.md`, one level deep, each pointer stating its load condition.
- [ ] Reference files > 100 lines start with a `## Contents` TOC.
- [ ] Scripts ≥ ~30 lines extracted to `scripts/`; forward slashes; no voodoo constants.
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
