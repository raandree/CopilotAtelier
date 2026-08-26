# Formal eval artifact schema

The artifact shapes below follow the open Agent Skills standard,
<https://agentskills.io/skill-creation/evaluating-skills.md>. They are the
*quality* half of evaluation — does the skill produce good output — and sit
alongside the pass@k / pass^k *reliability* harness described in
[`SKILL.md`](../SKILL.md).

One file is hand-authored: `evals.json`. Everything else (`grading.json`,
`timing.json`, `benchmark.json`, `feedback.json`) is produced during a run, by a
script, by the agent, or by the human reviewer.

## Directory layout

The skill directory holds only the authored input. Results go to a sibling
workspace directory, one directory per pass through the loop:

```text
xlsx-to-markdown/
  SKILL.md
  evals/
    evals.json
    files/                        # input fixtures referenced by evals.json
xlsx-to-markdown-workspace/
  iteration-1/
    eval-summary-sheet/
      with_skill/
        outputs/                  # files the run produced
        timing.json
        grading.json
      without_skill/
        outputs/
        timing.json
        grading.json
    eval-merged-cells/
      with_skill/ ...
      without_skill/ ...
    benchmark.json
    feedback.json
  iteration-2/ ...
```

Keep the workspace out of version control — it is regenerable. When improving an
existing skill, snapshot the current version first and point the baseline arm at
the snapshot, writing to `old_skill/` instead of `without_skill/`. That answers
"did my edit help", where `without_skill/` answers "does the skill help at all".

## `evals.json` — the authored input

```json
{
  "skill_name": "xlsx-to-markdown",
  "evals": [
    {
      "id": 1,
      "prompt": "I have a workbook of monthly sales in data/sales_2025.xlsx. Convert the summary sheet to a markdown table I can paste into the release notes.",
      "expected_output": "A markdown table of the summary sheet with a header row, aligned columns, and the month values preserved in chronological order.",
      "files": ["evals/files/sales_2025.xlsx"],
      "assertions": [
        "The output contains a markdown table with a header separator row",
        "All 12 months appear in the table",
        "Months are in chronological order, not alphabetical"
      ]
    }
  ]
}
```

| Field | Required | Meaning |
|---|---|---|
| `skill_name` | yes | The skill under test; matches the `name` in its frontmatter. |
| `evals[].id` | yes | Stable identifier for the case. |
| `evals[].prompt` | yes | A realistic user message, in the phrasing a user would actually type. |
| `evals[].expected_output` | yes | Human-readable description of success. Not a matcher. |
| `evals[].files` | no | Input fixtures the run needs, relative to the skill directory. |
| `evals[].assertions` | no on the first pass | Objectively checkable statements, added after the first round of outputs. |

Authoring rules that matter:

- **Start with 2-3 cases.** Do not over-invest before the first results land.
- **Vary phrasing** — some casual, some precise — and include at least one edge
  case, such as a malformed input or a request the instructions leave ambiguous.
- **Write `assertions` second.** You usually cannot tell what "good" looks like
  until the skill has run once.
- Good assertions are verifiable, specific, or countable. `"The output file is
  valid JSON"` is gradeable; `"The output is good"` is not, and `"uses exactly
  the phrase 'Total Revenue: $X'"` is brittle enough to fail correct output.
- Not everything needs an assertion. Style, layout, and "does it feel right"
  belong in `feedback.json`, not in a pass/fail check.

Sample: [`assets/evals.output.sample.json`](../assets/evals.output.sample.json).

## `timing.json` — cost of the run

Written per run arm, next to that arm's `outputs/`:

```json
{
  "total_tokens": 84852,
  "duration_ms": 23332
}
```

Capture these values the moment the run finishes; in most runners they are not
persisted anywhere else. Without them the with/without comparison shows only
quality and hides the price paid for it.

## `grading.json` — assertion results

One per run arm. Every assertion gets a verdict *and* evidence that quotes or
references the actual output:

```json
{
  "assertion_results": [
    {
      "text": "The output contains a markdown table with a header separator row",
      "passed": true,
      "evidence": "Line 3 of summary.md is '|---|---|---|'"
    },
    {
      "text": "Months are in chronological order, not alphabetical",
      "passed": false,
      "evidence": "Rows run April, August, December - alphabetical order"
    }
  ],
  "summary": { "passed": 1, "failed": 1, "total": 2, "pass_rate": 0.5 }
}
```

Grading principles:

- **Require concrete evidence for a PASS.** A section titled "Summary"
  containing one vague sentence fails an assertion asking for a summary: the
  label is present, the substance is not.
- **Use a script wherever a check is mechanical** — valid JSON, row counts, file
  exists, image dimensions. Scripts beat LLM judgment on those and are reusable
  across iterations. Reserve the LLM judge for assertions that need reading.
- **Grade the assertions too.** Note any that always pass, always fail, or
  cannot be checked from the output alone, and fix them before the next
  iteration.
- For version-to-version comparison, add a **blind comparison**: show both
  outputs to a judge without saying which is which, and let it score holistic
  qualities. Two outputs can pass identical assertions and still differ in
  polish.

## `benchmark.json` — aggregated per iteration

Written once per `iteration-N/`, after every arm is graded:

```json
{
  "run_summary": {
    "with_skill": {
      "pass_rate": { "mean": 0.83, "stddev": 0.06 },
      "time_seconds": { "mean": 45.0, "stddev": 12.0 },
      "tokens": { "mean": 3800, "stddev": 400 }
    },
    "without_skill": {
      "pass_rate": { "mean": 0.33, "stddev": 0.1 },
      "time_seconds": { "mean": 32.0, "stddev": 8.0 },
      "tokens": { "mean": 2100, "stddev": 300 }
    },
    "delta": { "pass_rate": 0.5, "time_seconds": 13.0, "tokens": 1700 }
  }
}
```

**The `delta` block is the whole point of the exercise.** It reports what the
skill buys on `pass_rate` and what it costs on `time_seconds` and `tokens`. A
skill that adds 13 seconds and 1700 tokens for 50 points of pass rate is worth
loading; one that doubles token usage for two points is not. A skill must be
justified on all three axes, not on pass rate alone.

`stddev` is only meaningful once each case runs several times. With 2-3 cases
and one run each, read the raw pass counts and the delta and ignore the spread.

## `feedback.json` — the human pass

One entry per eval directory, written by a human after reading the outputs
alongside the grades:

```json
{
  "eval-summary-sheet": "Months are alphabetical rather than chronological, and the numeric column lost its decimals.",
  "eval-merged-cells": ""
}
```

An empty string means the output survived review. Specific complaints drive the
next iteration; `"looks bad"` does not. This is the channel that catches what
nobody thought to write an assertion for — output that is technically correct
and still misses the point.

## Reading the results

- Remove assertions that pass in **both** arms; the model handles those without
  the skill and they inflate the with-skill number.
- Investigate assertions that fail in **both** arms — usually a broken
  assertion, a case that is too hard, or a check aimed at the wrong thing.
- Study assertions that pass with the skill and fail without, and work out
  *which* instruction made the difference.
- High `stddev` across runs means either a flaky case or instructions ambiguous
  enough to be read differently each time. Add an example before adding a rule.
- Read the transcript for any case that takes several times longer than its
  peers.

## The iteration loop

1. Give the failed assertions, human feedback, transcripts, and the current
   `SKILL.md` to a model and ask for proposed changes.
2. Review and apply them. Generalize rather than patching the specific case;
   keep the skill lean; explain the *why* behind an instruction rather than
   issuing ALWAYS/NEVER directives; and bundle into `scripts/` any helper that
   several runs wrote independently.
3. Re-run every case into a fresh `iteration-N/`.
4. Grade and aggregate.
5. Review with a human, then repeat.

Stop when feedback is consistently empty or successive iterations stop moving
the delta. If pass rates plateau while rules keep being added, the skill is
likely over-constrained — remove instructions and check whether results hold.

## Isolation

Every run starts from a clean context, so the run follows the `SKILL.md` and
nothing else. Where subagents exist, each child task is already isolated;
otherwise use a separate session per run. A session that helped author the skill
must never grade it.
