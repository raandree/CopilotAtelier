# Planguage keywords

The specification language of Tom Gilb's *Competitive Engineering*. Planguage
is a set of named parameters, not a formal grammar: a specification is a list
of `Keyword: value` lines under a `Tag`. This reference lists the keywords this
skill uses, their meaning, and the syntax conventions that carry meaning.

## Contents

- [Identity keywords](#identity-keywords)
- [Scalar keywords](#scalar-keywords)
- [Benchmarks](#benchmarks)
- [Targets](#targets)
- [Constraints](#constraints)
- [Qualifiers](#qualifiers)
- [Background and traceability](#background-and-traceability)
- [Relations](#relations)
- [Syntax conventions](#syntax-conventions)
- [Statement types](#statement-types)
- [Complete examples](#complete-examples)
- [Common specification errors](#common-specification-errors)

## Identity keywords

| Keyword | Meaning |
|---|---|
| `Tag` | Unique name for the specification. Everything else refers to it by this tag. Hierarchical dotted tags (`Portal.Login.Speed`) are conventional |
| `Type` | What kind of statement this is: Function Requirement, Quality Requirement, Resource Requirement, Design Idea, Condition, Definition |
| `Gist` | One-sentence summary in plain language, for a reader who will not read the rest |
| `Ambition` | Prose statement of the ambition level, written before the numbers exist. A drafting aid that must later be replaced or backed by scalar levels |
| `Description` | Full definition when `Gist` is not enough |
| `Version`, `Status`, `Owner` | Document control. `Status` is typically Draft, Reviewed, or Approved |

`Ambition` is the honest halfway house: it captures "we want logins to feel
instant" while the team works out the Scale. It is not a substitute for a
Scale, and a specification that still has `Ambition` but no `Scale` at sign-off
has failed.

## Scalar keywords

Two keywords make a quality or resource measurable. Both are mandatory.

| Keyword | Meaning |
|---|---|
| `Scale` | The unit of measure. Defines what a number on this requirement means |
| `Meter` | The practical procedure that produces a number on the Scale: who measures, with what instrument, on what sample, how often |

A well-formed `Scale` names the varying quantity and embeds `[qualifiers]` for
every dimension along which the requirement differs:

```planguage
Scale: Mean number of minutes for a defined [Staff Role] to complete a
       defined [Task] on a defined [Device Class].
```

A well-formed `Meter` is specific enough that two different people running it
get the same number:

```planguage
Meter [Acceptance]: 20 randomly selected sessions per [Staff Role], measured
       by the onboarding observer using the standard task script, reported as
       the arithmetic mean.
Meter [Continuous]: Telemetry events task.start to task.complete, weekly
       rolling median, excluding sessions with an intervening idle gap over
       120 s.
```

Different Meters may apply at different times. Qualify them.

## Benchmarks

Reference levels. They describe reality, not intent, and are stated before any
target so the target is chosen against evidence.

| Keyword | Meaning |
|---|---|
| `Past` | Level measured today, historically, or in a comparable system |
| `Record` | Best level known anywhere, by any organization |
| `Trend` | Level expected at a future date if nothing is done |

`Record` is the keyword that stops a team congratulating itself: a `Goal` well
below a competitor's known `Record` is a decision to be uncompetitive, and it
should be a conscious one.

## Targets

Levels the project intends to reach. Only two of them commit anybody.

| Keyword | Commits | Meaning |
|---|---|---|
| `Goal` | Yes | Committed target level for a quality. Reaching it is success |
| `Budget` | Yes | Committed target level for a resource. `Goal`'s counterpart on the cost side |
| `Stretch` | No | A level worth aiming beyond the commitment. Motivational |
| `Wish` | No | A stakeholder's ideal, recorded so it is not lost, explicitly uncommitted |

Recording a `Wish` is how the method absorbs an unrealistic demand without
either accepting or discarding it. The demand is written down, attributed, and
visibly not committed.

## Constraints

Levels that define failure rather than success.

| Keyword | Meaning |
|---|---|
| `Fail` | The level at or beyond which this requirement counts as failed |
| `Survival` | The level at or beyond which the system as a whole is unusable |

`Fail` and `Survival` are separate from `Goal` on purpose. Missing a `Goal` is
a disappointing outcome; crossing a `Fail` is a defect; crossing `Survival` is
an incident. Conflating them makes every miss look like a catastrophe and
destroys the signal.

## Qualifiers

Any level may carry `[time, place, event, population]` qualifiers in square
brackets. Qualifiers turn one requirement into a family of requirements and are
the main reason a Planguage specification stays short.

```planguage
Goal [Technician, Handheld, Europe, 2027-Q2]: 2.0 s
Goal [Technician, Desktop, Europe, 2027-Q2]: 1.2 s
Goal [Support Desk, Desktop, Europe, 2027-Q2]: 0.8 s
```

Qualifier vocabulary must be defined once and reused. Undefined qualifiers are
a major defect under SQC.

## Background and traceability

| Keyword | Meaning |
|---|---|
| `Source` | Where the statement or number came from. Document, person, measurement, date |
| `Authority` | Who may approve or change this specification |
| `Stakeholder` | Who is affected by the level being met or missed |
| `Rationale` | Why the requirement exists. The argument, not a restatement |
| `Assumption` | What must remain true for the specification to hold |
| `Risk` | What could make the level unachievable |
| `Priority` | Claim on resources relative to other requirements, with its reasoning |
| `Test` | How conformance will be demonstrated, when this differs from `Meter` |
| `Note`, `Comment` | Non-binding commentary. Excluded from the SQC page count |

`Rationale` earns its place when it states a consequence: "every second above
4 s produces one support call per 300 logins" is a rationale. "Because users
want it to be fast" is a restatement.

## Relations

| Keyword | Meaning |
|---|---|
| `Impacts` | This design idea affects the named requirements |
| `Supports` | This requirement contributes to the named higher-level objective |
| `Is Part Of` | Hierarchical membership |
| `Depends On` | This cannot be delivered before the named item |
| `Is Impacted By` | Inverse of `Impacts`, for navigation |

`Impacts` is the bridge to the Impact Estimation Table: each design idea's
`Impacts` list becomes its column of cells.

## Syntax conventions

| Symbol | Meaning |
|---|---|
| `<-` | "Source is". Follows the statement it attributes: `Past: 6.4 s <- TEL-114` |
| `->` | "Impacts". Points from a design idea to a requirement |
| `<term>` | The enclosed term is a defined term with its own specification. Look it up |
| `?` | The preceding statement is unsupported or uncertain and needs a source |
| `"term"` | A term being defined at this point |
| `≈` | The value is approximate by intent, not by sloppiness |

`<term>` is the mechanism that makes a specification navigable. It is also the
tie-in to a project glossary: every angle-bracketed term must exist there, with
one canonical name and no synonyms.

## Statement types

Five types, and the discipline is keeping them apart.

| Type | Scalar | Signed off as a requirement | Notes |
|---|---|---|---|
| Function Requirement | No | Yes | Binary. Present or absent. No Scale |
| Quality Requirement | Yes | Yes | More is better. `Goal`, `Stretch`, `Wish`, `Fail`, `Survival` |
| Resource Requirement | Yes | Yes | Less is better. `Budget` rather than `Goal` |
| Design Idea | Estimated, not required | No | A means. Competes in the Impact Estimation Table |
| Condition | Sometimes | Yes | A constraint on the solution space: legal, contractual, platform |

A statement that a stakeholder mandates a specific technology is a `Condition`
with a `Source` and an `Authority`, not a quality requirement. Recording it
that way keeps it visible as an externally imposed limit rather than letting it
masquerade as something the engineering decided.

## Complete examples

A quality requirement:

```planguage
Tag: Dispatch.Accuracy
Type: Quality Requirement
Gist: Share of dispatch decisions that need no manual correction.
Stakeholder: Dispatch team, Field technicians
Authority: Head of Operations
Scale: Percent of [Dispatch Decisions] in [Period] requiring no manual
       correction within 24 hours of issue.
Meter: Weekly extract from the correction log, denominator from the dispatch
       log, reconciled monthly.
Past [2026-Q2]: 87 % <- Correction log analysis CL-22, 2026-07-02
Record [Sector, 2025]: 96 % <- Industry survey IS-11, credibility 0.3
Trend [2027-Q4]: 85 % <- Volume growth model GM-2
Goal [2027-Q2]: 94 % <- Operations plan OP-7
Fail: 90 %
Rationale: Each corrected dispatch costs 11 minutes of dispatcher time and
       delays one technician by a median of 35 minutes.
Assumption: The technician skills matrix is maintained at current accuracy.
Risk: Third-party traffic data quality is outside project control.
```

A resource requirement:

```planguage
Tag: Dispatch.RunCost
Type: Resource Requirement
Scale: Euro per 1000 [Dispatch Decisions], fully loaded infrastructure cost.
Meter: Monthly cloud billing export divided by dispatch log volume.
Past [2026-Q2]: 41 EUR <- Billing export
Budget [2027-Q2]: 30 EUR <- Finance plan FP-3
Fail: 48 EUR
```

A design idea:

```planguage
Tag: Design.PredictiveRouting
Type: Design Idea
Gist: Rank candidate technicians by a model trained on historical outcomes.
Impacts: Dispatch.Accuracy, Dispatch.RunCost
Cost: 5.5 developer-months, 900 EUR per month inference
Assumption: 24 months of labelled outcome data are available.
Risk: Model drift after a fleet or process change.
```

Note what the design idea does not have: a `Goal`. It has estimated impacts,
which are argued in the Impact Estimation Table, and a cost. It is a candidate,
not a commitment.

## Common specification errors

| Error | Why it matters |
|---|---|
| `Scale` restates the quality name ("Scale: level of usability") | Produces no number. A Scale must name a countable quantity and a unit |
| `Meter` says "measured during testing" | Not a procedure. Name the instrument, the sample, and the frequency |
| `Goal` written with no `Past` | The target is unanchored and the Impact Estimation Table cannot compute a percentage |
| One requirement for several populations with no qualifiers | Hides the fact that the levels genuinely differ, and the hardest population sets the number silently |
| `Fail` equal to `Goal` | Removes the distinction between a missed ambition and a defect |
| Technology named in a requirement | The design decision has already been made and can no longer be evaluated |
| A level with no `Source` | Indistinguishable from an invented number six months later |
| Angle-bracketed term with no definition | Every reader supplies their own meaning, and they differ |
