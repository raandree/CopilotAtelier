---
name: agent-evals
description: >-
  Builds evaluations for your own Copilot skills, prompts, and agents so changes
  are measured, not vibed. Starts from the native VS Code tooling (Chat
  Customizations Evaluations analysis and the Waza eval runner) and falls back
  to a bundled run-evals.ps1 harness. Covers capability vs regression eval sets,
  grader types (deterministic / LLM-as-judge / human), pass@k vs pass^k, and
  eval-driven development. Rule of thumb: start from 20-50 real failures, not
  synthetic prompts.
  USE FOR: evaluate agent, evaluate skill, evaluate prompt, eval harness, build
  evals, Waza, analyze-prompt, Chat Customizations Evaluations, LLM-as-judge,
  grader, capability eval, regression eval, pass@k, pass^k, eval-driven
  development, does my skill work, test a prompt, measure agent quality,
  run-evals.
  DO NOT USE FOR: authoring the skill itself (use skill-creator), MCP server
  eval questions (use mcp-builder Phase 4), unit-testing PowerShell code (use
  pester-patterns), security review of an agent (use agent-security-review).
---

# Agent Evals

Build evaluations for your own agents, skills, and prompts so a change to a
`SKILL.md`, an agent body, or a prompt is judged by a measured pass rate, not by
a vibe check on one lucky run. This is the machinery behind the eval-driven
development that [`skill-creator`](../skill-creator/SKILL.md) prescribes.

## When to Use

- "Is this skill/prompt/agent actually working?" or "did my edit make it worse?"
- Before and after tightening a skill description or rewriting an agent section.
- A workflow keeps *mostly* working but fails intermittently — you need a reliability number, not an anecdote.
- You want a regression gate that fails a change when a previously-solved task breaks.

## Native tooling first

VS Code ships two evaluation surfaces. Reach for them before hand-rolling anything.

**Static analysis — [Chat Customizations Evaluations](https://marketplace.visualstudio.com/items?itemName=ms-vscode.vscode-chat-customizations-evaluations)** (preview, published separately). Works on `SKILL.md`, `*.agent.md`, `*.instructions.md`, and `*.prompt.md`. Run `Chat Customizations Evaluations: Analyze` from the Command Palette, or `/analyze-prompt` in chat, to surface logical and format contradictions, ambiguous wording with suggested rewrites, conflicting persona traits, excessive cognitive load from nested conditions, missing error paths, and conflicts with linked files. Findings land in the Problems panel with line and column locations; `Implement Suggestions` applies them.

**Behavioural evaluation — [Waza](https://github.com/microsoft/waza)**, wired into the same extension for skill files:

1. `Chat Customizations Evaluations: Download Waza Binary`
2. `Chat Customizations Evaluations: Create Waza Eval Scaffold` with the skill open
3. `Chat Customizations Evaluations: Run Waza Evaluation`

Waza is the missing non-interactive runner: it executes the eval set for you, which the bundled PowerShell harness cannot do on its own.

Use the concepts below — capability vs regression sets, pass@k vs pass^k, grader choice, 20-50 real failures — to decide *what* goes into the Waza scaffold. Fall back to the bundled harness only when Waza is unavailable, when the artifact is not a skill file, or when a grader needs logic Waza cannot express.

## Eval-driven development

Write the eval before the extensive documentation, not after. The loop:

1. **Collect real failures.** Run the current agent/skill/prompt on real tasks and save the ones that fail or disappoint.
2. **Turn each into an eval case** — the exact phrasing a real user typed, plus what a correct result must contain.
3. **Establish a baseline.** Score the current version. That number is what you must beat.
4. **Make the change** (edit the skill body, tighten the description, rewrite the agent section).
5. **Re-run the evals.** Compare to baseline. Confirm the skill actually triggered (the PRE-FLIGHT line names it) — a "bad output" is often really a "skill never loaded."
6. **Iterate.** Under-triggered → fix the description. Triggered but wrong → fix the body/references.

## Micro-test the wording first

A full eval run is the final gate, but it is slow and expensive per iteration. When the change is a wording change — a tightened rule, a reworded description, a new constraint — settle the wording first with a cheap micro-test.

1. **One fresh-context sample per call.** The system prompt is the realistic context the guidance will live in (the whole skill or prompt, never the guidance in isolation); the user message is a task that tempts the failure.
2. **Always run a no-guidance control arm.** If the control does not exhibit the failure, there is nothing to fix — stop, and do not author the guidance. Guidance against a failure that does not occur burns tokens and can teach the model a problem it did not have.
3. **Five or more repetitions per variant.** A single sample is noise in exactly the way one lucky run is noise for a full eval.
4. **Read every flagged match yourself.** Score programmatically if you like, but template echoes and quoted counter-examples register as hits, so automated counts overstate both failure and success.
5. **Treat variance as a metric.** When guidance lands, repetitions converge on the same shape. Five different interpretations across five repetitions means the wording is not binding — tighten the form before adding words.

Micro-tests settle wording. They do not replace the capability and regression sets below for a Customization that enforces a discipline.

## Start from 20–50 real failures

Do not hand-write synthetic prompts. Start from **20–50 real failures** pulled from actual sessions (check `.memory-bank/promptHistory.md` and `progress.md` for what was actually attempted). Real failures encode the phrasing, edge cases, and messy inputs that synthetic prompts miss. Twenty is enough to expose a pattern; fifty gives a stable pass rate. Grow the set every time a new failure mode appears in production.

## Two eval sets: capability vs regression

Keep two sets with different gates.

| Set | Question | Gate | When it fails |
|-----|----------|------|---------------|
| **Capability** | *Can* it do the task at all? | `pass@k` (best of k) | The skill/agent cannot solve a task it is supposed to |
| **Regression** | Did a change *break* something that worked? | `pass^k` (all of k) | A previously-reliable task became flaky or wrong |

Capability sets grow as you add features. Regression sets grow every time you fix a bug — add the failing case so it can never silently return.

## pass@k vs pass^k

Agents are non-deterministic, so a single run is noise. Sample each case **k** times (k = 3–10) and score two ways:

- **pass@k** — the case passes if **at least one** of the k samples is correct. Measures *capability / best case*: can it ever do this? Use for capability sets.
- **pass^k** ("pass-hat-k") — the case passes only if **all k** samples are correct. Measures *reliability / worst case*: can it do this every time? Use for regression sets and production-readiness gates.

A skill at pass@5 = 100% but pass^5 = 40% *can* do the task but only 2-in-5 times — fine for an exploratory helper, unacceptable for an unattended pipeline. Report both.

## Graders

Pick the cheapest grader that fits the output.

- **Deterministic** (first choice). Exact match, substring, regex, JSON-field equality, file-exists, exit-code. Cheap, stable, reproducible. Use whenever the correct answer is verifiable — file conversion, parsing, code generation, structured output.
- **LLM-as-judge** (for open-ended quality: writing, explanations, tone). A separate model call scores the output against a rubric. Rules that keep it honest:
  - **Pin the judge model** and version it — a judge upgrade shifts every score.
  - **Give a rubric and a 1–5 (or pass/fail) scale**, ask for a score **and** a one-line justification, and few-shot it with a labelled good and bad example.
  - **Calibrate against human labels** on a sample before trusting it. Watch for known judge biases: position, verbosity ("longer = better"), and self-preference (a model favours its own style).
  - Use a *different* model as judge than the one under test where practical.
- **Human** (gold standard, expensive). Use to label the initial failure set and to calibrate the LLM judge — not for every run.

## Eval file format

One JSON file, one array of cases. Keep it in the skill/agent folder next to a `notes-evals.md`.

```json
{
  "cases": [
    { "id": "pdf-basic",   "set": "capability", "prompt": "convert report.pdf to markdown", "expect": "## ",        "match": "contains" },
    { "id": "pdf-german",  "set": "regression", "prompt": "extract text from Bescheid.pdf", "expect": "Grüße|Straße", "match": "regex" }
  ]
}
```

`set` is `capability` or `regression`; `match` is `exact`, `contains`, or `regex`. See [`assets/evals.sample.json`](assets/evals.sample.json).

## Fallback harness

When Waza is unavailable, generating samples and grading them are two separate steps. **Generate** by running the agent/skill/prompt **k** times on each case's prompt and saving each run to `<OutputsDir>/<case-id>/sample-<n>.txt` — this step is manual or wired to whatever runner you have, which is exactly the gap Waza closes. **Grade** with the bundled runner, which computes pass@k and pass^k per case and per set and exits non-zero when a gate fails:

```powershell
pwsh Skills/agent-evals/scripts/run-evals.ps1 -EvalFile evals.json -OutputsDir out -K 5
```

Read [`scripts/run-evals.ps1`](scripts/run-evals.ps1) for the grading and gate logic (deterministic graders; capability gated on pass@k, regression on pass^k).

## Wiring into this repo

- Save eval prompts to `notes-evals.md` in the skill or agent folder, as `skill-creator` already recommends.
- Run `/analyze-prompt` on every changed Customization before measuring behaviour; a contradiction found statically is cheaper than a failed eval run.
- A capability eval doubles as proof the skill triggers: if the skill is not named in the PRE-FLIGHT acknowledgment, the failure is discovery (fix the `description`), not behaviour.
- For MCP servers, use [`mcp-builder`](../mcp-builder/SKILL.md) Phase 4's 10-question rubric instead — it is the same idea specialised for tool-calling.

## References

- VS Code — Evaluate and improve customization files: <https://code.visualstudio.com/docs/agent-customization/overview>
- Waza evaluation framework: <https://github.com/microsoft/waza>
- Anthropic — Building evals / eval-driven development (Agent Skills best practices): <https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices>
- OpenAI — Evals and LLM-as-a-judge guidance: <https://platform.openai.com/docs/guides/evals>
