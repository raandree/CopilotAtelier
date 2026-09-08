# Wiki incident grading evidence

Grader-only material for `sampler-wiki-commit-timeout`. Do not give this file,
the rubric, or successful-run links to the agent. The rubric is in
[notes-evals.md](../../notes-evals.md).

## Confirmed resolution

At commit `830a909ae8c366d4eab2c61575554d362df664d7`, the production workflow
patch changed only `jobs.publish.runs-on` from `windows-latest` to
`ubuntu-latest`. The entire commit also contains tests and records. The custom
workaround was removed. Packaging, documentation, both Windows test editions,
dependency versions, task order, and secrets stayed unchanged in the chosen
configuration. This verified that configuration, not a general wrapper repair
or immunity to output deadlocks on Linux.

## Hosted metadata

The run API was rechecked on 2026-09-08 and returned:

| Field | Value |
| --- | --- |
| Run ID / number | 34055979655 / 47 |
| Commit | 830a909ae8c366d4eab2c61575554d362df664d7 |
| Attempt | 1 |
| Status / conclusion | completed / success |
| Created / started | 2026-09-06T19:47:22Z |
| Updated | 2026-09-06T20:05:00Z |

Supplied incident evidence reports all four jobs passed and published
`0.2.0-preview0002`; the wiki Home page named that version and its sidebar
contained generated commands and DSC resources. Run-level success alone does
not prove destination content. Distinguish that historical check from any fresh
wiki read, which might show a later version.

## Source audit

These source reads corroborate supplied evidence. Probe timings are historical,
not rerun or benchmark results from this transfer.

| Claim | Verdict and anchor | Source |
| --- | --- | --- |
| Wrapper waits before draining | VERIFIED, `WaitForExit($TimeOut)` precedes both `ReadToEnd()` calls; initial result is `-1`. | [Invoke-Git v0.13.0](https://github.com/dsccommunity/DscResource.DocGenerator/blob/v0.13.0/source/Public/Invoke-Git.ps1) |
| Similar upstream failure | VERIFIED, issue title: "Task [Publish_GitHub_Wiki_Content] hangs when it creates a large commit"; that report used 0.10.2. | [Issue 111](https://github.com/dsccommunity/DscResource.DocGenerator/issues/111) |
| Reference runner split | VERIFIED, `Package_Module`: Windows; `Deploy_Module`: Ubuntu, downloaded output, `pwsh: true`. | [ActiveDirectoryDsc](https://github.com/dsccommunity/ActiveDirectoryDsc/blob/main/azure-pipelines.yml), [SqlServerDsc](https://github.com/dsccommunity/SqlServerDsc/blob/main/azure-pipelines.yml) |
| Workflow patch runner-only | VERIFIED, one addition and deletion in `.github/workflows/build.yml`; supporting files also changed. | [Commit](https://github.com/raandree/WindowsAccessControl/commit/830a909ae8c366d4eab2c61575554d362df664d7) |
| Local comparison | VERIFIED as history, reproduction table records `3042`, `157`, and `104` ms; not independently rerun here. | [Incident record](https://github.com/raandree/WindowsAccessControl/blob/830a909ae8c366d4eab2c61575554d362df664d7/.memory-bank/activeContext.md) |
| Hosted success | VERIFIED, API `completed`, `success`, matching SHA and attempt above. | [Run API](https://api.github.com/repos/raandree/WindowsAccessControl/actions/runs/34055979655), [run 47](https://github.com/raandree/WindowsAccessControl/actions/runs/34055979655) |

Historical locators:
[failed job](https://github.com/raandree/WindowsAccessControl/actions/runs/34026468199/job/101473822478),
[actual archive](https://github.com/raandree/WindowsAccessControl/releases/download/v0.2.0-preview0001/WikiContent.zip),
and [wiki](https://github.com/raandree/WindowsAccessControl/wiki).
Raw failed logs, archive bytes, four individual job details, and live wiki
content were supplied as incident evidence, not freshly retrieved here.
