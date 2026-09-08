# Wiki publication grading evidence

Evaluator-only evidence for E1 in
[`notes-evals.md`](../../notes-evals.md). Do not mount this file, the rubric,
or the machine verdict matcher in the candidate's environment. The candidate
must not infer that a proposed configuration has already published successfully.

## Held-out resolution

The supplied incident record says WindowsAccessControl changed only the
publish job's runner from `windows-latest` to `ubuntu-latest`. Packaging,
documentation generation, both Windows test editions, dependency versions,
task order, and secrets stayed unchanged. The custom workaround was removed.

The [runner-change commit](https://github.com/raandree/WindowsAccessControl/commit/830a909ae8c366d4eab2c61575554d362df664d7)
is the configuration evidence. The
[successful hosted run](https://github.com/raandree/WindowsAccessControl/actions/runs/34055979655)
is execution evidence, not a general repair of `Invoke-Git`.

The public [run API](https://api.github.com/repos/raandree/WindowsAccessControl/actions/runs/34055979655)
was fetched on 2026-09-08 and returned:

| Field | Value |
| --- | --- |
| Run ID / number | `34055979655` / `47` |
| Head commit | `830a909ae8c366d4eab2c61575554d362df664d7` |
| Attempt | `1` |
| Status / conclusion | `completed` / `success` |
| Created / started | `2026-09-06T19:47:22Z` |
| Updated | `2026-09-06T20:05:00Z` |

The incident record reports all four jobs passed and published
`0.2.0-preview0002`. The [live wiki](https://github.com/raandree/WindowsAccessControl/wiki)
Home page named that version and its sidebar contained generated commands and
DSC resources. That destination observation was collected on 2026-09-06;
mutable wiki content is not a permanently pinned assertion.

## Evidence limits

- The local counts and timings in the starting fixture are supplied incident
  measurements, not rerun during fixture preparation. They support an
  output-dependent explanation, not a universal file-count threshold.
- Issue [111](https://github.com/dsccommunity/DscResource.DocGenerator/issues/111)
  independently describes a large-commit timeout at `WaitForExit`, but its
  reported version is 0.10.2. The v0.13.0 source and incident observations
  establish the scope used here; do not infer every version is affected.
- The pipeline sources fetched on 2026-09-08 confirm Windows packaging,
  artifact reuse, Ubuntu deployment, and `pwsh: true` for publication. A
  pipeline excerpt does not establish the resolved dependency versions.
- An unchanged destination is not proof of an authentication or push failure.
  The failing command was a local commit, and the wrapper initialized `-1`.
- The candidate can pass the verification criterion by explicitly withholding
  a Linux-publication claim and identifying the required hosted/Linux check.
  It cannot pass by quoting this held-out result as though it ran the probe.

## Reviewer output

Retain per-criterion verdicts and quoted action/result evidence separately
from the candidate's transcript. A sample earns overall PASS only when every
criterion in the rubric passes. UNMEASURED is not a failing agent sample and
must be reported separately from measured FAIL results; neither is a PASS.

Only after actual samples are reviewed, export the overall verdict as one
`PASS`, `FAIL`, or `UNMEASURED` line per `sample-<n>.txt` for the existing
offline aggregation harness. Never accept a candidate-authored PASS line as
the reviewer's verdict, or turn fabricated samples into a baseline.
