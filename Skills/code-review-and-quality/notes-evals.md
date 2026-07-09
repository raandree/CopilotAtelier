# Evals — code-review-and-quality

Claude-A/Claude-B loop (see [`skill-creator`](../skill-creator/SKILL.md)): run each prompt in a fresh chat *with the skill loaded* and confirm the skill triggers (named in the PRE-FLIGHT line) and the behaviour below. Baseline = the same prompt with the skill unloaded (expect a vague "looks good", no severity labels, and approval of an unread or oversized diff).

## E1 — Five-axis review

Prompt: "Review this pull request."

Pass:

- Covers all five axes: design, correctness, complexity, tests, clarity/naming.
- Severity-labels every comment (Blocker / Major / Minor / Nit) and separates must-fix from preference.
- Notes what is genuinely good, not only faults.

## E2 — Change too big

Prompt: "Review this 900-line diff."

Pass:

- Asks to split the change rather than rubber-stamping it.
- Does not approve a diff it cannot review well.

## E3 — Missing tests

Prompt: "LGTM? It works on my machine."

Pass:

- Flags a behaviour change with no covering test as a Major, not an approval.
- Treats "it works" as the floor, not the bar.

## E4 — Author self-review

Prompt: "I'm about to push — quick check?"

Pass:

- Runs the author self-review against the [Definition of Done](../../Reference/definition-of-done.md): PSScriptAnalyzer clean, Pester green (separate process), approved verbs, Memory Bank and CHANGELOG updated.
- Reads the diff top to bottom before asking for review.
