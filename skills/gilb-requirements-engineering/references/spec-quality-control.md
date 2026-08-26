# Specification Quality Control

Specification Quality Control (SQC) measures whether a specification is fit to
be used. It is a measurement procedure with a numeric exit criterion, not a
review meeting, not proofreading, and not a sign-off ceremony.

The insight that makes it economical: a defective specification does not need
to be fully corrected, it needs to be identified as defective as cheaply as
possible and sent back to its author. Measuring two sampled pages answers that
question. Reading forty pages does not answer it any better and costs twenty
times more.

## Contents

- [Major and minor defects](#major-and-minor-defects)
- [The logical page](#the-logical-page)
- [Rule set](#rule-set)
- [Checking rate](#checking-rate)
- [Sampling](#sampling)
- [Detection effectiveness](#detection-effectiveness)
- [Exit criterion](#exit-criterion)
- [Procedure](#procedure)
- [Worked example](#worked-example)
- [Reporting](#reporting)
- [Anti-patterns](#anti-patterns)

## Major and minor defects

A defect is a violation of a rule. Only its downstream cost determines its
class.

| Class | Definition | Counts toward exit |
|---|---|---|
| Major | If it survives into use, it will probably cost substantially more to fix later than to fix now — the usual working assumption is roughly an order of magnitude | Yes |
| Minor | Cosmetic, editorial, or otherwise cheap to fix at any time | No |

An ambiguous `Scale` is major: every downstream measurement, test, and
acceptance decision inherits the ambiguity. A misspelled stakeholder name is
minor. A missing `Source` on a `Goal` is major, because the number becomes
unchallengeable once its origin is forgotten.

Classify by consequence, not by how annoying the defect is to read. Counting
minors toward the exit decision inflates the density with noise and destroys
the criterion's meaning.

## The logical page

Defect density needs a stable denominator, and physical pages vary wildly with
formatting.

A logical page is **300 words of non-commentary text**. Non-commentary means
the binding specification: keywords and their values. Explicitly commentary
material — `Note`, `Comment`, background prose, examples marked as such — is
excluded from the count, because a defect there does not propagate.

Count the words of the sampled section, divide by 300, and use that as the
denominator. Rounding a 210-word section to one page understates density by
30 %; use the fraction.

## Rule set

Checkers check against explicit rules. The rules must be short enough to hold
in mind — a set of about ten. A workable set for Planguage requirements:

| Rule | Statement |
|---|---|
| R1 | Unambiguous to the intended readership |
| R2 | Clear enough to test: a reader can say what measurement would settle it |
| R3 | No design. Requirements state ends, not means |
| R4 | All scalar attributes quantified with `Scale` and `Meter` |
| R5 | Every substantial statement and every number carries a `Source` |
| R6 | Defined terms used consistently and defined exactly once |
| R7 | No unexplained abbreviation, jargon, or undefined qualifier |
| R8 | Benchmarks stated before targets |
| R9 | Constraints (`Fail`, `Survival`) distinguished from targets (`Goal`) |
| R10 | No requirement contains two requirements |

Rules must be agreed before checking starts. A defect is a violation of a rule
that existed beforehand; anything else is an opinion, and logging opinions as
defects is how SQC loses credibility with authors.

## Checking rate

Checking effectiveness collapses with speed. Gilb's published optimum is
roughly **one logical page per hour**, with the best rate for dense
specification material sometimes lower still.

This number is counter-intuitive enough that teams routinely ignore it and then
conclude SQC does not work. Checking at five pages per hour does not find a
fifth of the defects — it finds a small fraction of them, because finding a
major defect requires cross-checking a statement against rules, against other
statements, and against sources. That work does not compress.

The practical consequence is not to spend a week checking. It is to check very
little, very carefully. Sampling exists to make that affordable.

## Sampling

Do not check the whole document.

- Select one to three representative pages. Include at least one section that
  matters most downstream.
- Prefer pages the team believes are good. A sample chosen for suspected
  weakness cannot be extrapolated.
- Check each sampled page at the optimum rate.
- Extrapolate the measured density to the document.

Two carefully checked pages produce a defensible density estimate for a
sixty-page specification, at a cost of a few hours. That estimate is what the
exit decision needs.

## Detection effectiveness

A single checker finds roughly **one third** of the major defects present in
the material they check. Multiple independent checkers overlap heavily but
still find more in total.

Estimate the true density from what was found:

$$\text{estimated majors} \approx \frac{\text{majors found}}{0.3}$$

Skipping this correction is the most common arithmetic error in SQC, and it
understates the problem by a factor of three. A document that measures at the
exit criterion on found defects is roughly three times over it in reality.

Recalibrate the 0.3 factor against a team's own history once it has enough
measurements to do so.

## Exit criterion

The classic criterion: **at most 1.0 estimated major defect per logical page**
remaining. Set it explicitly for the project before checking, and set it lower
where downstream cost is high — a specification feeding a safety case or a
fixed-price contract justifies a stricter number.

Calibration for expectations: specification material that has never been
through SQC commonly measures in the tens of estimated majors per logical page,
and figures well above a hundred are documented. A first measurement of 40
majors per page is not a sign that the checking was hostile. It is the normal
starting point, and it is precisely the information that makes the sign-off
decision different from a guess.

A specification that fails exit is **returned to its author** for rewriting. It
is not reviewed more thoroughly, and the defects found are not fixed one by one
in a meeting. At 40 majors per page there are hundreds of defects in the
document; correcting the handful that were found leaves it defective and
creates the illusion that it is not.

## Procedure

1. **Entry check.** Confirm the document has an author, a version, and a rule
   set. Confirm sources referenced by the document are available to checkers.
   A document failing entry is not checked.
2. **Plan.** Choose the sample, the rules, the checkers, and the exit
   criterion. State the checking rate.
3. **Check.** Each checker works alone against the rules at the planned rate,
   logging rule violations with location and rule number.
4. **Log.** Consolidate. Classify each as major or minor. Deduplicate.
5. **Measure.** Majors ÷ logical pages in the sample, corrected by detection
   effectiveness, extrapolated to the document.
6. **Decide.** Compare against the exit criterion. Pass or return to author.
7. **Improve the process.** Where a rule was violated repeatedly, the cause is
   usually a missing template, an unclear rule, or an untrained author. Fixing
   that prevents the next hundred defects; fixing the individual instances
   prevents none.

## Worked example

Sample: two sections, 640 words of non-commentary text.

| Quantity | Value |
|---|---|
| Logical pages | 640 ÷ 300 = 2.13 |
| Majors found | 19 |
| Minors found | 31 (recorded, not counted toward exit) |
| Density of found majors | 19 ÷ 2.13 = 8.9 per page |
| Estimated true density | 8.9 ÷ 0.3 = 29.7 per page |
| Exit criterion | 1.0 per page |
| Decision | Fails exit by roughly a factor of 30. Return to author |

Extrapolated to the full 22-page specification, the estimate is approximately
650 major defects. That number, not the 19 found, is what the sign-off decision
is about, and it is why the correct response is a rewrite rather than a fix
list.

## Reporting

State four numbers, always together:

- Majors found, and pages sampled.
- Density of found majors per logical page.
- Estimated density after the detection-effectiveness correction.
- The exit criterion it was compared against.

Never report "the specification was reviewed and looks good". SQC exists to
replace that sentence with a number.

## Anti-patterns

| Anti-pattern | Effect |
|---|---|
| Checking the whole document | Cost rises to the point where SQC is abandoned, with no better decision than sampling gave |
| Counting minors toward exit | The density is dominated by typography and the criterion stops meaning anything |
| Skipping the 0.3 correction | Density is understated threefold and failing documents pass |
| Fixing the found defects and shipping | Hundreds of unfound defects remain, now with a false quality signal attached |
| Checking at reading speed | Almost nothing is found, and the low count is read as high quality |
| Logging opinions as defects | Authors reject the process, correctly |
| Rules invented during checking | Nothing is measurable, because the denominator of "rule violations" keeps changing |
| Using SQC to evaluate the author | Defects go unreported, and the measurement becomes worthless |
