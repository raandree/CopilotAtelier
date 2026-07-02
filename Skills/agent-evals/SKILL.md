---
name: agent-evals
description: >-
  Builds evaluations for your own Copilot skills, prompts, and agents so changes
  are measured, not vibed. Covers capability eval sets (can it do the task?) vs
  regression eval sets (did a change break it?), grader types (deterministic /
  LLM-as-judge / human), pass@k vs pass^k for non-deterministic runs,
  eval-driven development, and a minimal run-evals.ps1 harness. Rule of thumb:
  start from 20–50 real failures, not synthetic prompts.
  USE FOR: evaluate agent, evaluate skill, evaluate prompt, eval harness, build
  evals, LLM-as-judge, LLM as a judge, grader, capability eval, regression eval,
  pass@k, pass^k, eval-driven development, does my skill work, test a prompt,
  measure agent quality, run-evals.
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

## Eval-driven development

Write the eval before the extensive documentation, not after. The loop:

1. **Collect real failures.** Run the current agent/skill/prompt on real tasks and save the ones that fail or disappoint.
2. **Turn each into an eval case** — the exact phrasing a real user typed, plus what a correct result must contain.
3. **Establish a baseline.** Score the current version. That number is what you must beat.
4. **Make the change** (edit the skill body, tighten the description, rewrite the agent section).
5. **Re-run the evals.** Compare to baseline. Confirm the skill actually triggered (the PRE-FLIGHT line names it) — a "bad output" is often really a "skill never loaded."
6. **Iterate.** Under-triggered → fix the description. Triggered but wrong → fix the body/references.

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

## Minimal harness

Generating samples and grading them are two steps. **Generate** by running the agent/skill/prompt **k** times on each case's prompt and saving each run to `<OutputsDir>/<case-id>/sample-<n>.txt` (Copilot has no stable non-interactive PowerShell entry point, so this step is manual or wired to whatever runner you have). **Grade** with the bundled runner, which computes pass@k and pass^k per case and per set and exits non-zero when a gate fails:

```powershell
pwsh Skills/agent-evals/scripts/run-evals.ps1 -EvalFile evals.json -OutputsDir out -K 5
```

Read [`scripts/run-evals.ps1`](scripts/run-evals.ps1) for the grading and gate logic (deterministic graders; capability gated on pass@k, regression on pass^k).

## Wiring into this repo

- Save eval prompts to `notes-evals.md` in the skill or agent folder, as `skill-creator` already recommends.
- A capability eval doubles as proof the skill triggers: if the skill is not named in the PRE-FLIGHT acknowledgment, the failure is discovery (fix the `description`), not behaviour.
- For MCP servers, use [`mcp-builder`](../mcp-builder/SKILL.md) Phase 4's 10-question rubric instead — it is the same idea specialised for tool-calling.

## References

- Anthropic — Building evals / eval-driven development (Agent Skills best practices): <https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices>
- OpenAI — Evals and LLM-as-a-judge guidance: <https://platform.openai.com/docs/guides/evals>
