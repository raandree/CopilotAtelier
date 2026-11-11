# Travel Handbook Evaluation Notes

How the `travel-handbook` Skill was measured before it shipped, and the tasks
to replay when it changes. Both tasks come from a private two-language trek
handbook, replayed at the state before it had charts or photos.

## Tasks

| Task | Request, in neutral words | Checklist (each failed item is one correction) |
| --- | --- | --- |
| T1 | Add a per-night temperature chart to the weather chapter: night low and day high at each night's place and altitude, from the last ten years of the trip's dates, in both languages, with source and method. | Shown in both chapters; every night present; corrected to altitude and plausible; source, years, and window stated with a link; second-language labels and number format; twins parallel; no broken links; legible chart; chart, table, and prose agree. |
| T2 | Add freely licensed photos of six named places to the highlights chapter in both languages, with a credits table. | One photo per place in both chapters; each shows its place; each licence is CC0, public domain, CC BY, or CC BY-SA; credits name author, licence link, and source page in both languages; ShareAlike stated for an edited image; at most about 600 KB and 2,000 px wide; no broken links; captions in the second language. |

## Comparison of 2026-11-10

One fresh general-purpose subagent per arm, the two arms of a task run at the
same time, each in its own scratch clone of the same commit with no later
history. The with-arm read this Skill first; the without-arm had every other
installed Skill. The parent agent graded each answer against the checklist.
Tool calls and failed tool runs come from the session's event log; HTTP 429
answers from the arms' reports and the scripts' summaries.

### First run: the toolkit before the fixes

| Task | Corrections with / without | Tool calls with / without | Failed runs with / without | HTTP 429 with / without |
| --- | --- | --- | --- | --- |
| T1 | 1 / 0 | 105 / 124 | 2 / 1 | 0 / 0 |
| T2 | 0 / 0 | 117 / 164 | 0 / 5 | 0 / 1 |

- The with-arm's chart hid night values behind the next bar, and whiskers
  crossed the altitude labels: one correction for legibility.
- Outside the checklist, the first without-arm found that Open-Meteo's default
  archive blend runs warm at night. A three-year check at a valley station
  confirmed it: the blend's nights ran about 5 °C above the station's normals,
  ERA5 alone within about 1 °C.
- By the owner's rule this run meant drop: the with-arms needed one correction
  more.

### Fixes, test-first

- Every night value stays in its own slot, inside its bar or under its
  whisker, and the altitude moved into the tick label. A layout test renders a
  dense 24-night chart and fails on the old layout.
- The archive request names ERA5 alone. A test fails without it.

### Rerun of T1 on the fixed toolkit

The owner approved two more runs: T1 again, both arms at the same time; T2
unchanged.

| Task | Corrections with / without | Tool calls with / without | Failed runs with / without | HTTP 429 with / without |
| --- | --- | --- | --- | --- |
| T1 (rerun) | 0 / 0 | 142 / 123 | 6 / 3 | 0 / 0 |
| T2 | 0 / 0 | 117 / 164 | 0 / 5 | 0 / 1 |
| Total | 0 / 0 | 259 / 287 | 6 / 8 | 0 / 1 |

- Decision: keep, narrowly. The owner's rule keeps a Skill whose with-arms need
  no more corrections and are better on at least one of corrections, a quarter
  fewer tool calls, or fewer failed runs and 429s; here 6 against 9 failed runs
  and 429s. Agent time was 49 minutes with the Skill and 60 without.
- Expected failures count too: the temperature check exits 1 until the table
  is pasted into the chapter, by design.

## Limitations

- One run per arm: the numbers are indicative, not a reliability measurement.
- The rerun repeats the task that exposed the defects, so it shows that the
  fixes hold, not how the Skill does on a new handbook.
- The checklists were applied by the agent that built the Skill.
- Two with-arms wrote the owner's e-mail address into `user_agent`; the Skill
  now asks for a project URL instead.
