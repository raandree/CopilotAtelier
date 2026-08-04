# Impact Estimation Tables

The decision instrument of Gilb's method. An Impact Estimation Table (IET)
places design ideas in columns and quantified requirements in rows, and forces
every claim that a design helps to be stated as a number with evidence, a
source, and a credibility rating.

Its output is not the winning number. Its output is that a bad idea can no
longer hide behind confident prose.

## Contents

- [Preconditions](#preconditions)
- [Table structure](#table-structure)
- [Computing a cell](#computing-a-cell)
- [Credibility ratings](#credibility-ratings)
- [Cost rows](#cost-rows)
- [Summary rows and the decision](#summary-rows-and-the-decision)
- [Safety margin](#safety-margin)
- [Worked example](#worked-example)
- [Reading the result](#reading-the-result)
- [Failure modes](#failure-modes)

## Preconditions

Do not build the table until all of these hold:

- At least two quantified requirements, each with a `Past` and a `Goal`.
- At least two design ideas, each with a `Gist` and a cost estimate.
- Design ideas that are genuinely alternative or combinable, not one idea
  restated at three levels of detail.

A table with one design idea measures nothing; it merely documents a decision
already taken.

## Table structure

```text
                        | Design A | Design B | Design C |
Req1  87 % -> 94 %      |   57 %   |   29 %   |  -14 %   |
Req2  6.4 s -> 2.0 s    |   11 %   |   80 %   |   45 %   |
Req3  41 EUR -> 30 EUR  |    0 %   |  -18 %   |   64 %   |
------------------------|----------|----------|----------|
Development cost        |   25 %   |   40 %   |   15 %   |
Operating cost          |   10 %   |    5 %   |   30 %   |
------------------------|----------|----------|----------|
Sum of impacts          |   68 %   |   91 %   |   95 %   |
Sum of costs            |   35 %   |   45 %   |   45 %   |
Value/cost ratio        |   1.94   |   2.02   |   2.11   |
```

Every cell in the impact block also carries, in the full working table,
four attributes that the summary view above omits: uncertainty, evidence,
source, and credibility. Keep them in the working table; they are the reason
the numbers can be challenged.

## Computing a cell

For a requirement with `Past` = P and `Goal` = G, the span G − P is 100 %.

A design idea estimated to move the level to L contributes:

$$\text{impact} = \frac{L - P}{G - P} \times 100\,\%$$

Worked: `Past` 87 %, `Goal` 94 %, design estimated to reach 91 % →
(91 − 87) / (94 − 87) = 4 / 7 = **57 %**.

Three consequences that surprise people:

- A cell can exceed 100 %. A design that overshoots the `Goal` is allowed to
  say so, and the surplus is real information.
- A cell can be negative. A design that improves speed by damaging accuracy
  gets a negative cell in the accuracy row. This is the single most valuable
  thing the table produces, because prose arguments almost never surface it.
- A cell of 0 % is a legitimate, informative answer. Most designs affect most
  requirements not at all.

State uncertainty alongside the estimate, as a range or a `±` figure:
`57 % ±20 %`. An estimate with no uncertainty claims a precision nobody has.

## Credibility ratings

Every estimate carries a credibility rating from 0.0 to 1.0. Gilb's published
scale runs in 0.1 steps; these anchors are enough in practice.

| Rating | Basis for the estimate |
|---|---|
| 0.0 | A guess. Nothing supports it |
| 0.1 | Someone, somewhere, is believed to have done this |
| 0.2 | One measurement exists, from an unrelated context |
| 0.3 | Several measurements exist in the estimated range |
| 0.4 | The measurements come from a genuinely comparable system |
| 0.5 | The measurement method itself is considered reliable |
| 0.6 | This design idea has been used on this project |
| 0.7 | Reliable measurements of this design idea exist on this project |
| 0.8 | Substantial measured experience with it on this project |
| 0.9 | Reliable measurements in many closely comparable cases |
| 1.0 | Contractually guaranteed, long-term, measured, and unlikely to change |

Ratings above 0.6 require project-local evidence. A vendor benchmark is 0.2 to
0.4 territory no matter how confidently it is presented; a vendor's claim about
their own product with no independent measurement does not exceed 0.2.

Multiply each impact by its credibility to get the credibility-adjusted impact.
A 90 % impact at credibility 0.2 adjusts to 18 % and loses to a 40 % impact at
credibility 0.7, which adjusts to 28 %. That reordering is the point: the
method systematically prefers the option that is known to work over the option
that would be spectacular if it worked.

## Cost rows

Costs are expressed as a percentage of the available budget, on the same
0 %–100 % basis as impacts, so the two blocks are comparable.

- Split development cost from operating cost. A design that is cheap to build
  and expensive to run behaves very differently over time, and a single blended
  number hides it.
- Use the `Budget` levels from the resource requirements as the denominators.
- Calendar time is a cost row when the deadline binds.

Where a resource requirement already exists as a proper Planguage requirement,
it belongs in the impact block, not the cost block. Do not count it twice.

## Summary rows and the decision

| Row | Computation |
|---|---|
| Sum of impacts | Sum of the impact cells in the column |
| Sum of credibility-adjusted impacts | Sum of impact × credibility |
| Sum of costs | Sum of the cost cells in the column |
| Value/cost ratio | Sum of impacts ÷ sum of costs |
| Adjusted value/cost ratio | Credibility-adjusted impacts ÷ sum of costs |

The adjusted ratio decides. Quote it, and quote the raw ratio next to it — a
large gap between the two says the option depends on evidence nobody has yet,
which is itself a finding worth reporting.

Summing across requirements assumes they matter equally. When they do not,
weight the rows by stakeholder priority and say so explicitly; an unstated
weighting is a hidden decision.

## Safety margin

Estimates in this method are optimistic in aggregate, consistently and
predictably. Selecting a set of designs whose impacts sum to exactly 100 % of
each `Goal` therefore plans for failure at the first estimate that proves
generous.

Plan a margin: select design ideas until the estimated sum comfortably exceeds
100 % per requirement. Gilb's guidance is to aim for roughly double. Track the
achieved margin as the Evo steps deliver real measurements, and let it shrink
only as credibility rises.

## Worked example

Requirement `Dispatch.Accuracy`, `Past` 87 %, `Goal` 94 %.

| Attribute | Design A: rules refinement | Design B: predictive routing |
|---|---|---|
| Estimated level | 91 % | 96 % |
| Impact | 57 % | 129 % |
| Uncertainty | ±15 % | ±60 % |
| Evidence | Same rule change measured in the pilot region | Vendor case study in a different sector |
| Source | Pilot report PR-4, 2026-03 | Vendor white paper VW-2 |
| Credibility | 0.7 | 0.2 |
| Adjusted impact | 40 % | 26 % |
| Development cost | 12 % | 45 % |

Raw impact says predictive routing wins by more than two to one. Credibility
adjustment reverses it, and cost widens the gap: 40/12 = 3.3 against 26/45 =
0.6. The table's recommendation is to ship the rules refinement first and, if
predictive routing still looks attractive, spend a small Evo step buying
evidence for it — which is exactly what raises its credibility from 0.2 to
something that could win the next comparison.

## Reading the result

- The highest adjusted ratio is the recommendation, not the verdict. A decision
  may legitimately override it for reasons the table does not model, and the
  override belongs in the record with its reasoning.
- A column of near-zero impacts means the design idea solves a problem nobody
  wrote a requirement for. Either a requirement is missing, or the idea is.
- A row where every column is near zero means no proposed design addresses that
  requirement at all. This is the table's best early warning.
- Negative cells are findings. Report them explicitly rather than netting them
  off in the sum.

## Failure modes

| Failure mode | Symptom | Correction |
|---|---|---|
| Estimates without sources | Every cell is a round number and no `Source` is filled in | Set credibility to 0.0 and treat the column as unevaluated |
| Credibility inflation | Most cells sit at 0.8–0.9 with no project-local measurement | Re-rate against the anchor table; project-local evidence or nothing |
| Requirement without `Past` | The percentage cannot be computed | Establish the benchmark before estimating |
| Design ideas that are not alternatives | Three columns describe one approach in increasing detail | Merge them; compare against a genuinely different approach |
| The table is built after the decision | Every cell favours the chosen column | Discard it. A ratifying table is worse than none, because it launders a decision as analysis |
| Requirements weighted silently | The sum implies equal importance nobody agreed to | State the weighting or state that it is uniform |
