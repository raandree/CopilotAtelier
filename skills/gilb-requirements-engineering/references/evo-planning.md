# Evo step planning

Evolutionary project management: deliver the system in small increments, each
of which puts something real in front of a real stakeholder and produces a
measurement on a requirement's `Scale`. The measurement, not the completion of
the work, is what makes a step finished.

Evo predates and differs from timeboxed iteration. A sprint is a container for
work. An Evo step is a delivery of value with a number attached.

## Contents

- [What makes a step a step](#what-makes-a-step-a-step)
- [Step sizing](#step-sizing)
- [Selection order](#selection-order)
- [Step specification](#step-specification)
- [The measurement loop](#the-measurement-loop)
- [Backroom and frontroom](#backroom-and-frontroom)
- [When a step misses](#when-a-step-misses)
- [Reporting](#reporting)
- [Relationship to sprints](#relationship-to-sprints)
- [Anti-patterns](#anti-patterns)

## What makes a step a step

Three tests. A candidate step that fails any of them is not an Evo step.

1. **A real stakeholder receives something they can use.** Not a demo, not a
   staging environment nobody works in, not a merged branch.
2. **It moves a named requirement along its `Scale`.** The step names the
   requirement and the expected movement before it starts.
3. **The movement will be measured with that requirement's `Meter`,** on a
   stated date, by a named person.

"Refactor the data layer", "complete the API", "finish sprint 4", and "migrate
the schema" all fail test 1 or 2. They may be necessary work; they are not
steps, and they are not what progress is reported in.

## Step sizing

Small. Gilb's guidance is roughly weekly delivery, and around 2 % of total
project budget or time per step, with 5 % as an upper bound.

The reasons for the small size are economic, not aesthetic:

- A step that fails costs at most 2 % of the project.
- Feedback arrives while the design decision that produced it is still
  reversible.
- Estimation error compounds with duration; a week's estimate is wrong by less
  than a quarter's.
- Frequent delivery makes the delivery mechanism itself reliable through use.

When a step cannot be made small, the usual cause is that value has been
defined too coarsely. Ask which stakeholder would benefit from a fraction of
it, and deliver that fraction to them.

## Selection order

Order steps by the credibility-adjusted value-to-cost ratio from the Impact
Estimation Table, highest first. Deviate for three reasons only, and record
which one applies:

- **Dependency.** The step cannot physically be built before another.
- **Evidence purchase.** A cheap step that raises the credibility of a large,
  poorly evidenced estimate can be worth more than its own direct value,
  because it changes which design wins the next comparison.
- **Risk retirement.** A step that would invalidate the whole plan if it
  failed is worth doing early even at a poor ratio.

Front-loading value is the default because a project may be stopped at any
point, and the question that matters is what has been delivered by then, not
what remains planned.

## Step specification

```planguage
Step: 14
Tag: Step.RulesRefinement.Region3
Delivers: Refined dispatch rules for [Region 3] technicians.
Stakeholder: Region 3 dispatch team, 11 dispatchers
Design Idea: Design.RulesRefinement
Impacts: Dispatch.Accuracy
Estimated impact: 87 % -> 90 %, that is 43 % of the Past-to-Goal span
Credibility: 0.7 <- Pilot report PR-4
Cost estimate: 4 developer-days
Meter: Weekly correction-log extract for Region 3
Measured on: 2026-09-14, by the dispatch data analyst
Actual impact: <TBD>
Rollback: Rule set reverts to version 8.2; no data migration involved
```

`Actual impact` is filled in after measurement. A step whose `Actual impact`
stays `<TBD>` has not finished, however much of its code has shipped.

## The measurement loop

Each step runs the same cycle:

1. **Estimate.** Take the expected impact from the Impact Estimation Table.
2. **Deliver.** Put the increment in the stakeholder's hands.
3. **Measure.** Run the `Meter`. Record the actual level on the `Scale`.
4. **Compare.** Actual against estimate, as a ratio.
5. **Feed back.** Update the design idea's credibility, correct the remaining
   estimates in the table, and reorder the remaining steps if the ordering
   changed.

Step 5 is the one teams drop, and dropping it turns Evo into ordinary
incremental delivery. The table is a forecast that gets better only if it is
corrected against outcomes.

Watch the ratio of actual to estimated across steps. A team whose estimates run
consistently at 60 % of the claim has a calibration factor, and applying it to
future estimates is more valuable than any single step's result.

## Backroom and frontroom

Not every week produces a stakeholder-visible delivery, and pretending
otherwise produces theatre.

- **Backroom**: development, integration, and internal work in progress. No
  external commitment, no measurement.
- **Frontroom**: delivery to the stakeholder, followed by measurement.

Work may sit in the backroom across several cycles. Only frontroom deliveries
count as steps and only they appear in progress reporting. The distinction
prevents both the fiction of weekly value and the drift into quarterly
delivery.

## When a step misses

A step whose measured impact falls materially short of the estimate is a
result, not a failure of the method. Diagnose in this order:

1. **Was the delivery actually used?** An unused increment measures nothing.
   Fix adoption before concluding anything about the design.
2. **Was the `Meter` run as specified?** A different sample or window explains
   many surprises.
3. **Was the estimate wrong?** Lower the design idea's credibility and correct
   the remaining cells in its column.
4. **Was the design idea wrong?** Stop pouring steps into it. The 2 % step size
   exists precisely so this costs 2 %.

Roll back when the step made a requirement worse. Every step specification
names its rollback in advance, because deciding how to undo something under
pressure produces bad decisions.

## Reporting

Report movement on the `Scale`:

> Dispatch.Accuracy: 87.0 % → 90.2 % after step 14. Goal 94 % by 2027-Q2.
> Estimate was 90.0 %; actual 90.2 %; ratio 1.03. Remaining span 3.8 points
> across 6 planned steps.

Do not report percentage complete, story points burned, or tasks closed. Those
numbers measure activity, and a project can produce all of them while every
requirement stays at its `Past` level.

## Relationship to sprints

Evo and timeboxed agile methods are compatible; they answer different
questions. A sprint answers "what will we work on for the next two weeks". An
Evo step answers "what value will a stakeholder measurably receive, and by how
much will the number move".

Running both means a sprint contains one or more Evo steps, and the sprint
review reports measured movement on the `Scale` rather than a demonstration.
The `Meter` supplies the acceptance criterion, so the definition of done for a
step includes its measurement.

## Anti-patterns

| Anti-pattern | Why it breaks the method |
|---|---|
| Steps defined by architecture layer | "Build the service layer" delivers value to nobody and can be measured against nothing |
| Steps sized by team capacity | Capacity determines how much fits in a step, not what a step is |
| Estimates never compared to actuals | The Impact Estimation Table never improves and credibility ratings stay fictional |
| Measuring only at the end of the project | The feedback arrives after every decision it could have informed |
| Steps chosen by build order | Value ordering is abandoned in favour of what happens to be convenient |
| Rollback improvised when needed | The step becomes irreversible in practice, which removes the reason it was kept small |
| Reporting activity instead of levels | Progress looks healthy while every requirement sits at `Past` |
