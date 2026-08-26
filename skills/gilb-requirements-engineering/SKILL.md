---
name: gilb-requirements-engineering
description: >-
  Quantified requirements engineering with Tom and Kai Gilb's method:
  gives every quality a Planguage Scale and Meter with benchmarks and
  numeric targets, ranks design ideas in an Impact Estimation Table,
  plans delivery as measurable Evo steps, and inspects specifications
  with Specification Quality Control.
  USE FOR: Gilb method, Tom Gilb, Kai Gilb, Planguage, Competitive
  Engineering, quantify a requirement, unmeasurable requirement, Scale
  and Meter, Goal Fail Stretch Wish, Past Record Trend, non-functional
  requirement, requirements engineering, Anforderungsmanagement,
  Anforderungen quantifizieren, Lastenheft, impact estimation table,
  IET, Evo, evolutionary project management, Specification Quality
  Control, SQC, majors per page.
  DO NOT USE FOR: unquantified requirements interview (use grill-me),
  code review (use code-review-and-quality), prose drafting (use
  doc-coauthoring), source verification (use citation-integrity).
---

# Gilb Requirements Engineering

Turn stakeholder wishes into requirements that carry a unit of measure, a
measuring procedure, and numbers — then choose designs by estimated impact
rather than by argument, deliver in measurable increments, and refuse to
release a specification whose defect density is unknown.

## The one rule

A quality requirement without a `Scale`, a `Meter`, and at least one numeric
level is not a requirement. It is a wish with a noun in it.

"User-friendly", "robust", "scalable", "performant", "secure", "intuitive",
"benutzerfreundlich" and "hochverfügbar" are all placeholders for a number
nobody has written down yet. The method's whole leverage is refusing to let
those words survive into a specification.

## When to use

- A requirement, `Lastenheft`, epic, or acceptance criterion contains an
  unquantified quality word.
- Two or more design options must be compared and someone is about to decide
  by seniority or enthusiasm.
- A project needs delivery increments that prove value rather than report
  percentage complete.
- A specification is about to be signed off and nobody knows its defect
  density.

## Artifacts and where the detail lives

| Artifact | Answers | Deep reference |
|---|---|---|
| Planguage requirement | How much, measured how, by when, for whom | [`references/planguage-keywords.md`](references/planguage-keywords.md) |
| Impact Estimation Table | Which design idea buys the most value per unit of cost | [`references/impact-estimation.md`](references/impact-estimation.md) |
| Evo step plan | What ships next week and what value it proves | [`references/evo-planning.md`](references/evo-planning.md) |
| SQC measurement | Whether the specification is fit to be used at all | [`references/spec-quality-control.md`](references/spec-quality-control.md) |

Read a reference when the task reaches that stage. Do not load all four up
front.

## Protocol

### 1. Classify every statement before writing anything

Sort each sentence of the input into exactly one bucket. Misclassification is
the most common and most expensive error in the method.

| Bucket | Test | Example |
|---|---|---|
| Function | What the system does. Binary — present or absent. No scale. | "Authenticates the user" |
| Quality (performance) | How well it does it. Varies along a scale. More is better. | "Authentication completes in under 800 ms" |
| Resource | What it consumes. Varies along a scale. Less is better. | "Under 4 developer-months" |
| Design | A means, not an end. Answers *how*. | "Use Redis for the session cache" |
| Condition | A constraint or assumption bounding the solution space | "Must run on-premises" |

Anything in the Design bucket is removed from the requirements and parked as a
candidate design idea for step 6. A requirement that names a technology has
smuggled a solution in and pre-empted the decision.

### 2. Give every quality and resource a Scale and a Meter

`Scale` is the unit of measure. `Meter` is the practical procedure that
produces a number on that Scale — who measures, with what, when, on what
sample.

A Scale with no Meter is untestable. A Meter with no Scale is a ritual.

Write the Scale with `[qualifiers]` so one requirement covers several
populations, places, or moments instead of being copy-pasted five times:

```planguage
Scale: Mean seconds for a [User Type] to complete [Task] using [Device].
Meter: 20 randomly sampled sessions per quarter, measured from telemetry
       event auth.start to auth.complete.
```

### 3. State benchmarks before targets

Benchmarks come first, because a target chosen without knowing today's level is
guesswork.

| Keyword | Meaning |
|---|---|
| `Past` | Measured level today, or in a comparable system |
| `Record` | Best level known anywhere, by anyone |
| `Trend` | Where the level goes if nothing is done |

Then, and only then, the levels the project commits to or aspires to:

| Keyword | Meaning |
|---|---|
| `Goal` | Committed target for a quality. Success is reaching it |
| `Budget` | Committed target for a resource |
| `Stretch` | Motivating level, not committed |
| `Wish` | Stakeholder's dream level, no commitment implied |
| `Fail` | Level at which the requirement is considered failed |
| `Survival` | Level beyond which the system is unusable at all |

`Past` and `Goal` together define the 0 %–100 % scale used by the Impact
Estimation Table in step 7. Skipping `Past` makes the table uncomputable.

### 4. Attach traceability to every number

Each level carries `Source` (where the number came from), and the requirement
carries `Rationale` (why it exists), `Stakeholder` (who cares), `Authority`
(who may change it), plus `Assumption` and `Risk` where they exist.

A number with no `Source` is invented. Mark it `Source: <TBD>` rather than
letting it pass as fact — an explicit gap is cheap, a fabricated benchmark is
not. Where a claimed benchmark cites an external document, verify it with
`citation-integrity` before it enters the specification.

### 5. Emit the requirement in the required shape

Every scalar requirement produced by this skill has these slots, in this order.
Omitting a slot is allowed only by writing the slot with an explicit `<TBD>` or
`Not applicable` value, never by deleting the line.

```planguage
Tag: Login.Speed
Type: Quality Requirement
Gist: How quickly a returning user gets authenticated.
Stakeholder: Field technicians, Support desk
Scale: Mean seconds for a [User Type] to complete login on [Device].
Meter: Telemetry, 20 sessions per [User Type] per week, rolling mean.
Past [Technician, Handheld, 2026-Q1]: 6.4 s <- Telemetry export TEL-114
Record [Industry, 2025]: 1.1 s <- Vendor benchmark VB-9, credibility 0.4
Trend [2027]: 7.0 s <- Growth model GM-2
Goal [Technician, Handheld, 2027-Q2]: 2.0 s <- Service target SLA-3
Stretch: 1.2 s
Fail [Technician, Handheld]: 4.0 s <- Support escalation threshold
Rationale: Every second above 4 s produces one support call per 300 logins.
Assumption: Device fleet is not replaced before 2027-Q2.
Risk: Identity provider latency is outside project control.
```

`<-` marks the source of the preceding statement. Terms in angle brackets are
defined terms that must appear in the glossary. For the complete keyword set
and syntax, read
[`references/planguage-keywords.md`](references/planguage-keywords.md).

### 6. Collect design ideas separately

Everything filtered out in step 1, plus any new proposal, becomes a design idea
with its own `Tag`, `Gist`, and a cost estimate. Design ideas are never
requirements and are never signed off as such. They compete.

### 7. Compare designs in an Impact Estimation Table

Build the table only when there are at least two design ideas and at least two
quantified requirements. Each cell estimates how far a design idea moves a
requirement from `Past` to `Goal`, as a percentage, with evidence, source, and
a credibility rating between 0.0 and 1.0. Costs go in their own rows; the
decision is driven by the credibility-adjusted value-to-cost ratio, not by the
raw percentages.

For table construction, the credibility scale, uncertainty handling, and the
arithmetic, read
[`references/impact-estimation.md`](references/impact-estimation.md).

### 8. Plan delivery as Evo steps

Sequence the winning design ideas into small increments, each of which delivers
measurable value to a real stakeholder and each of which is followed by
measurement against the estimate. The estimate is a hypothesis; the measurement
is the result. Feed the difference back into the table.

For step sizing, selection order, and the estimate-versus-actual loop, read
[`references/evo-planning.md`](references/evo-planning.md).

### 9. Measure the specification before anyone relies on it

Sample the specification, count major defects against the rule set, compute
majors per logical page, and compare against the numeric exit criterion. A
specification that fails exit is returned to its author, not reviewed harder.

For the rule set, defect classification, sampling, and exit arithmetic, read
[`references/spec-quality-control.md`](references/spec-quality-control.md).

## Worked transformation

Input, as a stakeholder writes it:

> The new portal must be significantly faster and more reliable than the old
> one, and easy to learn for new staff.

Output, after steps 1–5 — three requirements, because the input contained
three, plus one design idea that was hiding as a requirement:

```planguage
Tag: Portal.ResponseTime
Scale: 95th percentile seconds to render [Page Class] for [User Type].
Meter: Real-user monitoring, weekly rolling window.
Past [Dashboard, Staff, 2026-Q2]: 4.8 s <- RUM export
Goal [Dashboard, Staff, 2027-Q1]: 1.5 s <- Steering group 2026-05-14
Fail: 3.0 s

Tag: Portal.Availability
Scale: Percent of [Business Hours] in which [Core Function] is usable.
Meter: Synthetic probe every 60 s, monthly aggregate.
Past [2026-Q2]: 99.1 % <- Incident log
Goal [2027-Q1]: 99.8 % <- Steering group 2026-05-14
Survival: 98.0 %

Tag: Portal.Learnability
Scale: Minutes for a [New Staff Member] with no training to complete
       [Core Task] without assistance.
Meter: Observed onboarding session, 8 participants per quarter.
Past: 41 min <- Onboarding study OB-3
Goal [2027-Q1]: 12 min <- Support cost model
```

"Significantly faster" produced a number and a percentile. "More reliable"
split into availability, because that is what the stakeholder could measure.
"Easy to learn" became time-on-task. Nothing was invented: every level cites a
source, and any level without one would have carried `<TBD>`.

## Rationalizations to refuse

| Rationalization | Reality |
|---|---|
| "This quality genuinely cannot be measured." | Every quality that can be observed to differ between two systems can be scaled. If it cannot differ observably, it is not a requirement. |
| "The stakeholder does not know the number yet." | Then write the Scale and Meter now and `Goal: <TBD>` with an owner and a date. The unit of measure is the hard part; the number follows. |
| "We'll quantify it during implementation." | The purpose of the number is to choose the design. A number produced after the design is chosen only ratifies it. |
| "Everyone here knows what 'fast' means." | Then writing the number costs one minute. Disagreement surfaces exactly when it is cheap. |
| "The percentages in the table are guesses anyway." | That is why each carries a credibility rating and a source. A rated guess can be challenged and improved; an unrated opinion cannot. |
| "SQC is bureaucratic overhead." | SQC samples. Two pages measured beats forty pages skimmed, and produces a number the sign-off decision can use. |
| "The requirement says which technology to use because the customer asked for it." | Record it as a `Condition` with its source, or as a design idea with a mandate. Do not disguise a solution as a requirement. |

## Red flags

Stop and re-enter the protocol when any of these is true right now:

- A requirement is being written whose truth cannot be settled by a
  measurement.
- A `Goal` was written before a `Past` was established.
- A number was written without a `Source`, or with a source invented to fill
  the slot.
- A technology, product, framework, or architecture name appears in the
  requirements section.
- Design options are being compared in prose rather than in the table.
- An Evo step is defined by internal activity ("refactor the data layer")
  rather than by stakeholder-visible value.
- A specification is heading for sign-off with no measured defect density.

## Verification

Confirm before reporting the work done:

- Every quality and resource requirement has `Scale`, `Meter`, at least one
  benchmark, and at least one target or constraint.
- No requirement names a technology or a solution.
- Every numeric level has a `Source` or an explicit `<TBD>`.
- Every defined term used in angle brackets exists in the glossary. Where the
  repository has `.memory-bank/glossary.md`, Planguage tags and defined terms
  are the same canonical terms enforced by
  [`rules/ubiquitous-language.instructions.md`](../../com.github.copilot/rules/ubiquitous-language.instructions.md).
- If designs were compared: each cell carries evidence, source, and a
  credibility rating; the conclusion cites the credibility-adjusted ratio.
- If the specification was inspected: majors per logical page is stated as a
  number, next to the exit criterion it was compared against.

## Pairs with

- [`Skills/grill-me/SKILL.md`](../grill-me/SKILL.md) — run the adversarial
  interview first to discover what the stakeholders want, then quantify the
  answers here. Grill-me finds the requirements; this skill makes them
  measurable.
- [`Skills/citation-integrity/SKILL.md`](../citation-integrity/SKILL.md) —
  verify externally sourced benchmarks before they become `Past` or `Record`.
- [`Skills/devils-advocate-review/SKILL.md`](../devils-advocate-review/SKILL.md)
  — attack a `Goal` that looks aspirational rather than sourced.
- [`Skills/doc-coauthoring/SKILL.md`](../doc-coauthoring/SKILL.md) — draft the
  surrounding specification document once the requirements are quantified.
- [`Skills/test-driven-development/SKILL.md`](../test-driven-development/SKILL.md)
  — a `Meter` is an acceptance test that happens to return a number.

## Out of scope

- Functional decomposition and use-case modelling. Gilb's method deliberately
  says little about function; it concentrates on the qualities that decide
  whether a system is competitive.
- Estimating effort for a schedule. Resource requirements carry `Budget`
  levels; they are not a substitute for planning practice.
- Code-level review (use `code-review-and-quality`) and agentic-security review
  (use `agent-security-review`).

## Attribution

The method is Tom Gilb's and Kai Gilb's. Primary sources:

- Gilb, T. (2005). *Competitive Engineering: A Handbook For Systems
  Engineering, Requirements Engineering, and Software Engineering Using
  Planguage*. Elsevier Butterworth-Heinemann.
- Gilb, T. (1988). *Principles of Software Engineering Management*.
  Addison-Wesley.
- Gilb, T. & Graham, D. (1993). *Software Inspection*. Addison-Wesley.
- Gilb, T. & Gilb, K. Free papers and current material at <https://www.gilb.com>.

This skill is an independent restatement of the method for agent use. Numeric
defaults quoted in the references are Gilb's published figures and should be
recalibrated against a team's own measurements once it has them.
