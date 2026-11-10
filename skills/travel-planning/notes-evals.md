# Travel Planning Evaluation Notes

How the `travel-planning` Skill was measured before it shipped, and the cases
to replay when it changes. The rules come from corrections an owner made while
planning real trips; the cases below are four of those corrections, replayed
on a private trip repository at the state before the correction.

## Cases

| Case | Kind | Request, in neutral words | What a correct answer does |
| --- | --- | --- | --- |
| P2 | Advice only | Would a domestic flight back to the arrival city beat a five-to-seven-hour drive with the rental car on the second-last day? Compare only. | Leaves the plan unchanged; keeps a timetable pattern apart from a date's seats and fares; keeps the night before the international flight; landside only; totals fare, baggage, one-way fee, fuel, and tolls with unknowns left open; exact airport codes. |
| P3 | Research only | Which temple on a rock is linked by tradition to a historical figure, and is the link documented? Do not change the plan. | Names a likely place as an assumption; keeps a documented visit to the city apart from an unsupported visit to the temple; cites the passage; labels the attribution as unresolved. |
| U3 | Update | The travellers eat only breakfast and dinner and want no scheduled breaks. | Removes every scheduled lunch and hotel break; records the preference; updates time blocks; leaves unaffected days alone; keeps travel and safety allowances. |
| U7 | Update | Replace the drive back with the last evening domestic flight before the international return. Book nothing. | Keeps the international flight; dates an arrival after midnight; keeps the hotel night with a late-arrival confirmation; implies no protected connection; moves the car return to the departure airport with the fee open; changes only the affected days. |

## Comparison of 2026-11-10

One fresh general-purpose subagent per arm, the two arms of a case run at the
same time, each in its own scratch clone of the same commit. The with-arm read
this Skill first; the without-arm had every other installed Skill. The parent
agent graded each answer against a fixed checklist of 4 to 7 items per case;
each failed item counts as one correction. Tool calls, failed tool runs, and
HTTP 429 responses come from the session's event log.

| Case | Corrections with / without | Tool calls with / without | Failed runs with / without |
| --- | --- | --- | --- |
| P2 | 0 / 0 | 103 / 144 | 13 / 17 |
| P3 | 0 / 0 | 41 / 50 | 1 / 3 |
| U3 | 0 / 1 | 78 / 81 | 1 / 2 |
| U7 | 0 / 1 | 120 / 119 | 8 / 11 |
| Total | 0 / 2 | 342 / 394 | 23 / 33 |

- The without-arm rewrote a day the request did not touch (U3), and gave an
  arrival after midnight without its calendar date (U7). Both are rules in this
  Skill.
- No arm met an HTTP 429. Agent time was 72 minutes with the Skill and 88
  without.
- Decision: keep. The owner's rule keeps a Skill whose with-arms need no more
  corrections than the without-arms and are better on at least one of
  corrections, a quarter fewer tool calls, or fewer failed runs and 429s.

## Limitations

- In-sample: the four cases are among the corrections the rules were distilled
  from. The comparison shows that the rules take effect, not that they
  generalize to new trips.
- One run per arm: the numbers are indicative, not a reliability measurement
  (see `agent-evals`, pass@k and pass^k).
- The scratch clones first kept the repository's later history. Two
  without-arms and one with-arm listed later commit subjects before it was
  removed; none read later file contents.
- The checklists were applied by the agent that wrote the Skill. An
  independent grader would remove that bias.
