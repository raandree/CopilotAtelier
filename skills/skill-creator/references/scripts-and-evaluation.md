# Scripts and evaluation

Bundled executable code, and the measurement loop that proves a skill earns its context cost. Read this when a skill will ship anything under `scripts/`, when it performs batch or destructive operations, or when you are building the trigger and output evals for it. The harness, file layout, assertion formats, and benchmark deltas belong to [`agent-evals`](../../agent-evals/SKILL.md); this file covers the authoring decisions that feed it.

## Contents

- Scripts: solve, don't punt
- Designing the interface for a non-interactive caller
- Plan-validate-execute
- Trigger evals in detail
- Evaluation-driven development
- Reading the results
- Keeping the skill lean, and knowing when to remove

## Scripts: solve, don't punt

When a skill bundles executable code (`scripts/`):

- **Handle errors explicitly.** Catch `FileNotFoundError`, `PermissionError`, etc. and either recover with a documented default or fail with a specific actionable message. Do not let the script crash and leave the agent to guess.
- **No voodoo constants.** Every numeric literal (`TIMEOUT = 47`, `MAX_RETRIES = 5`) needs a one-line comment justifying it. "Why 47?" must have an answer.
- **Use forward slashes** in all paths (`scripts/helper.py`, not `scripts\helper.py`). Windows paths break on Unix.
- **Make execution intent explicit**: "Run `analyse_form.py` to extract fields" (execute) vs "See `analyse_form.py` for the extraction algorithm" (read as reference). Default to execute.
- **Extract anything ≥ ~30 lines** of executable code from SKILL.md into `scripts/<name>.ps1` (or `.py` / `.mjs`). SKILL.md keeps a 5-line invocation example.
- **Bundle what the agent keeps reinventing.** If execution traces across eval runs show the agent independently rewriting the same chart builder, parser, or validator each time, write it once and ship it in `scripts/`.

## Designing the interface for a non-interactive caller

The agent decides what to do next from stdout and stderr, and it cannot answer a prompt.

- **Never prompt.** Agents run in non-interactive shells, so a TTY prompt, password dialog, or confirmation menu blocks until the harness gives up. Take every input from a parameter, an environment variable, or stdin, and fail with a usage line instead.
- **Document the interface with `--help`** (comment-based help for PowerShell). It is how the agent learns the parameters. Keep it short; the output lands in the context window.
- **Say what to try next in an error.** `--format must be one of json, csv, table. Received "xml"` costs one turn. `Validation failed` costs several.
- **Structured data to stdout, diagnostics to stderr.** Emit JSON, CSV, or objects the agent can pipe, and keep progress and warnings out of that stream.
- **Bound the output.** Harnesses truncate tool output somewhere around 10-30 KB and the remainder is simply lost. Default to a summary and offer an output path or paging for the full result.
- **Use distinct exit codes** for not-found, bad arguments, and auth failure, and document them where `--help` shows them.
- **Be idempotent, and reversible where it matters.** The agent retries: prefer create-if-absent over fail-on-duplicate, and give a destructive operation `-WhatIf` or `--dry-run`.
- **Declare dependencies inside the script** — PEP 723 inline metadata run with `uv run script.py`, or `#Requires -Module` in PowerShell. A prerequisite stated only in prose is one the agent may never read.

## Plan-validate-execute

For batch or destructive operations (updating 50 form fields, applying tracked changes to a document, rewriting a config across a fleet), use the plan-validate-execute pattern:

1. The agent analyses input and writes a structured plan file (`changes.json`).
2. A validator script checks the plan against the target (`validate.py changes.json`).
3. Only on validation pass does the agent execute the plan.

Verbose error messages from the validator are critical: `"Field 'signature_date' not found. Available fields: customer_name, order_total, signature_date_signed"` lets the agent fix the plan; `"Validation failed"` does not.

## Trigger evals in detail

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

## Evaluation-driven development

The strongest and most-skipped recommendation: **build evaluations before writing extensive documentation.** Trigger evals prove the skill fires; output evals prove it helps.

1. **Identify gaps.** Run the agent on representative tasks **without** the skill. Document every failure or missing context.
2. **Write 2–3 test cases** — the exact phrasing a real user would use, plus a human-readable description of what success looks like, plus any input files. Do not over-invest before the first round of results.
3. **Establish baseline.** Keep the without-skill outputs. When improving an existing skill, snapshot the previous version and use that as the baseline instead.
4. **Write minimal SKILL.md** — just enough to fix the documented gaps.
5. **Re-run with the skill loaded**, in a clean context per run. Verify the skill triggered (PRE-FLIGHT line names it). Compare with-skill against without-skill on pass rate, tokens, and duration.
6. **Add assertions after the first run**, once you know what good output looks like, and grade each with concrete evidence.
7. **Iterate.** Under-triggered → tighten the description. Triggered but wrong → tighten the body or references.

## Reading the results

- **Assertions that always pass in both arms** measure nothing — the model handles them unaided. Remove or replace them; they inflate the with-skill pass rate without reflecting value.
- **Assertions that always fail in both arms** are broken, or the test case is too hard. Fix before the next iteration.
- **Assertions that pass with the skill and fail without** are where the value is. Understand *which* instruction made the difference.
- **High variance across runs** means the eval is flaky or the instruction is ambiguous enough to be read differently each time. Add an example or sharpen the wording.
- **Time and token outliers** warrant reading the execution transcript for the bottleneck.

## Keeping the skill lean, and knowing when to remove

Fewer, better instructions often outperform exhaustive rules. If transcripts show wasted work — unnecessary validation, unneeded intermediate output — remove those instructions. **If pass rates plateau while you keep adding rules, the skill is probably over-constrained: delete instructions and check whether results hold or improve.** Adding is the reflex; subtracting is the fix more often than authors expect.

Generalise every fix. The skill runs against many prompts, not just the test cases — address the underlying issue rather than patching the specific example.
