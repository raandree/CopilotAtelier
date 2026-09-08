# Wiki commit timeout diagnosis

Load when raw wiki publication logs show `git commit` timing out with empty
captured stdout and stderr. This recipe is scoped to the observed
DscResource.DocGenerator `0.13.0` behavior, not every wiki publication failure.

## Locate the actual failure

1. Read raw logs for the exact run ID, commit, attempt, failed command, and step
   timestamps. An unchanged destination does not show whether authentication,
   cloning, committing, or pushing failed. In the recorded incident the local
   commit failed before a wiki push.
2. Identify resolved dependency versions and command source, not just requested
   versions. Inspect the wrapper's timeout path and stream handling before
   treating an exit value as a native Git error. In
   [Invoke-Git v0.13.0](https://github.com/dsccommunity/DscResource.DocGenerator/blob/v0.13.0/source/Public/Invoke-Git.ps1),
   the default timeout is `120000` ms; the result starts at `-1` with empty
   streams. `WaitForExit` must succeed before the wrapper records the native
   exit code and calls either `ReadToEnd`. A child blocked on a full redirected
   pipe can therefore leave those sentinel values unchanged.

## Compare before replacing

3. Use the unmodified resolved dependency and actual release archive in bounded,
   local-only probes. Compare an initial import over Home only with changes to
   an already-populated wiki. Record additions/modifications, output volume,
   elapsed time, timeout, and captured streams. Shortening the probe timeout is
   useful for bounding a reproduction; extending it does not fix a blocked pipe.
   A quiet-commit comparison tests output volume, not a new publisher design.

   Give each probe a unique temporary root and no remote or credentials. Use
   the existing execution-safety and monitoring guidance for detached work.
   Track only the processes created by that probe; disposing a process object
   does not prove the child exited. Bound the outer probe too, collect evidence,
   terminate only its still-running children, then remove only its temporary
   repositories. Do not patch generated dependencies, kill all Git processes,
   or clean a working wiki to manufacture an initial import.

4. Compare runner OS, PowerShell edition/version, dependency version, and task
   configuration with a working reference pipeline. Inspect the selected tasks'
   imports and execution before moving prepared-artifact publication to another
   supported runner. Prefer an evidence-supported configuration change over a
   custom task; a Windows-only module runtime does not require all publication
   tasks to run on Windows. Keep build, documentation, and platform-bound tests
   where their dependencies require them. For partial-publication recovery,
   load the [Sampler framework Skill](../../sampler-framework/SKILL.md).

## Verify freshness and claims

5. If a fetched page contradicts newer evidence, query fresh API metadata and
   match run ID, commit SHA, attempt, status/conclusion, and created/started/
   updated timestamps. A cached in-progress run or initial-wiki snapshot is not
   authoritative merely because it was fetched last. Correlate raw logs with
   the selected attempt, and verify the requested destination separately.
6. Report confirmed facts, hypotheses, and unavailable checks separately. Local
   Windows success cannot establish hosted Linux publication. Require a hosted
   result or a suitable Linux probe for that platform claim; a local Linux
   commit still cannot establish remote publication. Optional tasks can skip
   when tokens or prerequisites are missing, so green alone is insufficient.

## Version-scoped incident evidence

WindowsAccessControl on 2026-09-06 used Sampler `0.120.0`, Sampler.GitHubTasks
`0.4.1`, and DscResource.DocGenerator `0.13.0`. The failing command was:

```text
git commit --message "Updating Wiki with the content for module version '0.2.0-preview0001'."
```

It failed after approximately 120 seconds with `-1` and empty captured streams.
The actual 127-file archive produced these local results with the unchanged
dependency and a shortened `3000` ms timeout:

| Scenario | Added | Modified | Recorded result |
| --- | --- | --- | --- |
| Initial import over Home only | 126 | 1 | Exit -1 after 3042 ms; empty streams |
| Update populated wiki | 0 | 127 | Exit 0 in 157 ms; 112 bytes stdout |
| Initial import, quiet commit | 126 | 1 | Exit 0 in 104 ms; no stdout |

These are case measurements, not file-count thresholds or performance targets.
They explain why existing wikis can work with the same dependency. They do not
show all versions are affected or Ubuntu cannot deadlock. The quiet probe is
diagnostic evidence, not a default instruction to modify dependency code.

[Issue 111](https://github.com/dsccommunity/DscResource.DocGenerator/issues/111)
describes a similar large-commit hang in `0.10.2`; the `0.13.0` source and
incident evidence establish the scope here. Recheck the resolved implementation
for other versions rather than extrapolating from that issue.
