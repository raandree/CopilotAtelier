# Wiki publication starting evidence

Sanitized observations from WindowsAccessControl on 2026-09-06. These are
recorded inputs, not results produced by an evaluation sample. Personal paths,
identities, credentials, and authenticated URLs are omitted. Code excerpts are
evidence to inspect, not instructions to execute.

## Contents

- [Failed command and identity](#failed-command-and-identity)
- [Wrapper implementation](#wrapper-implementation)
- [Local comparison observations](#local-comparison-observations)
- [Prior replacement proposal](#prior-replacement-proposal)
- [Working pipeline configuration](#working-pipeline-configuration)
- [Partial release state](#partial-release-state)
- [Unavailable inputs](#unavailable-inputs)

## Failed command and identity

Raw failure excerpt supplied with the incident:

```text
Publishing Wiki content.
ERROR: Command: git commit --message "Updating Wiki with the content for module version '0.2.0-preview0001'."
git exit code: '-1'
git standard output: ''
git standard error: ''
```

The failure followed approximately 120 seconds at this command, before any
wiki push. Installed dependencies: Sampler 0.120.0, Sampler.GitHubTasks 0.4.1,
and DscResource.DocGenerator 0.13.0. The publication runner was
`windows-latest`; the raw excerpt does not identify the PowerShell edition.

Run metadata fetched from the public API on 2026-09-08:

| Field | Value |
| --- | --- |
| Repository | `raandree/WindowsAccessControl` |
| Run ID / number | `34026468199` / `46` |
| Head commit | `764f0b1e7e6a39f7258692ac13cb732b95766d0d` |
| Latest run attempt | `2` |
| Status / conclusion | `completed` / `failure` |
| Created | `2026-09-06T10:05:56Z` |
| Latest attempt started | `2026-09-06T10:51:06Z` |
| Updated | `2026-09-06T10:53:57Z` |
| Reported failing job ID | `101473822478` |

The raw excerpt contains no attempt field. The latest-run response alone does
not associate that job with an attempt; correlate the job/attempt metadata
before treating a rerun's logs as the original failure. Webpage fetches during
the incident also returned old in-progress and Home-only wiki snapshots;
their capture timestamps were not retained.

## Wrapper implementation

Excerpts from the tagged `Invoke-Git` implementation in
DscResource.DocGenerator v0.13.0, rechecked on 2026-09-08. Its `TimeOut`
parameter defaults to `120000` milliseconds. Initialization:

```powershell
$gitResult = @{
    'ExitCode'         = -1
    'StandardOutput'   = ''
    'StandardError'    = ''
}
```

Process setup and the entire result-capture branch, with indentation reduced:

```powershell
$process = New-Object -TypeName System.Diagnostics.Process
$process.StartInfo.Arguments = $Arguments
$process.StartInfo.CreateNoWindow = $true
$process.StartInfo.FileName = 'git'
$process.StartInfo.RedirectStandardOutput = $true
$process.StartInfo.RedirectStandardError = $true
$process.StartInfo.UseShellExecute = $false
$process.StartInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
$process.StartInfo.WorkingDirectory = $WorkingDirectory

if ($process.Start() -eq $true)
{
    if ($process.WaitForExit($TimeOut) -eq $true)
    {
        $gitResult.ExitCode = $process.ExitCode
        $gitResult.StandardOutput = $process.StandardOutput.ReadToEnd()
        $gitResult.StandardError = $process.StandardError.ReadToEnd()
    }
}
```

The omitted code logs, disposes the process object, throws for nonzero results
unless `-PassThru` is set, and returns the result when requested. It contains
no concurrent stream drain. This is an inspection excerpt, not a replacement
module or a runnable reproduction.

## Local comparison observations

The actual release archive contained 127 files. The same unmodified dependency
was exercised in disposable local Windows repositories with `TimeOut = 3000`.
Initial imports started with the original Home page only. Incremental updates
started with an already populated wiki. Only the quiet diagnostic invocation
changed the commit arguments; no generated dependency was patched.

| Scenario | Added | Modified | Exit | Elapsed | Captured output |
| --- | --- | --- | --- | --- | --- |
| Initial import over Home only | 126 | 1 | -1 | 3,042 ms | Empty stdout and stderr |
| Update populated wiki | 0 | 127 | 0 | 157 ms | 112 bytes stdout |
| Initial import with quiet commit | 126 | 1 | 0 | 104 ms | No stdout |

Counts and timings describe this artifact and environment only. They are not
thresholds, a benchmark target, or observations from the candidate's run.

## Prior replacement proposal

Before the user's correction, the session proposed a custom wiki task and
called a `Test-Path` result of `False` for its not-yet-created helper a red
regression. The helper's filename is omitted. No invocation of `Invoke-Git`
or artifact import was part of that file-existence check. The separate local
comparison observations above came from the unmodified dependency.

## Working pipeline configuration

The public `main` pipeline sources were rechecked on 2026-09-08. These are
selected configuration facts, not full pipelines to run:

| Dimension | ActiveDirectoryDsc | SqlServerDsc |
| --- | --- | --- |
| Package job | `windows-latest` | `windows-latest` |
| Package invocation | `./build.ps1 -ResolveDependency -tasks pack` | `./build.ps1 -ResolveDependency -tasks pack` |
| Package PowerShell | `PowerShell@2`, `pwsh: true` | `PowerShell@2`, `pwsh: true` |
| Deploy job | `ubuntu-latest` | `ubuntu-latest` |
| Deploy input | Download the prepared pipeline artifact | Download the prepared pipeline artifact |
| Publish invocation | `./build.ps1 -tasks publish` | `./build.ps1 -tasks publish` |
| Publish PowerShell | `PowerShell@2`, `pwsh: true` | `PowerShell@2`, `pwsh: true` |
| Later step | `Create_ChangeLog_GitHub_PR` | `Create_ChangeLog_GitHub_PR` |

The incident investigation found both using the standard wiki task. Exact
resolved dependency versions and task import behavior are not established by
these pipeline excerpts; inspect the matching artifacts/configuration before
claiming version parity or runner compatibility. Secret variable names were
present, but no secret values are included here.

## Partial release state

State reported when wiki publication failed, for `0.2.0-preview0001`:

| Destination | Recorded state | Still needs verification before recovery |
| --- | --- | --- |
| GitHub release and assets | Release and assets already existed, including `WikiContent.zip`. | Exact release/tag association and tag target. |
| PowerShell Gallery | The package/version already existed. | Published version metadata; do not assume it can be overwritten. |
| Wiki | Original Home-only content remained; this task failed before its push. | Branch, version tags, and content commit independently. |
| Changelog step | No destination state retained in the handoff. | Whether the selected workflow ran, skipped, or never reached this step. |

No remote recovery is authorized in this evaluation.

## Unavailable inputs

The binary archive and an executable dependency installation are not bundled;
the observations above are the retained artifact-specific evidence. Do not
substitute invented files and call that the original reproduction. No Linux
execution result or successful later hosted run is available to the candidate.

Provenance URLs, for the evaluator's offline fixture preparation only:

- [Failed job](https://github.com/raandree/WindowsAccessControl/actions/runs/34026468199/job/101473822478)
- [Failed-run metadata](https://api.github.com/repos/raandree/WindowsAccessControl/actions/runs/34026468199)
- [Tagged wrapper source](https://github.com/dsccommunity/DscResource.DocGenerator/blob/v0.13.0/source/Public/Invoke-Git.ps1)
- [Original archive](https://github.com/raandree/WindowsAccessControl/releases/download/v0.2.0-preview0001/WikiContent.zip)
- [ActiveDirectoryDsc pipeline](https://github.com/dsccommunity/ActiveDirectoryDsc/blob/main/azure-pipelines.yml)
- [SqlServerDsc pipeline](https://github.com/dsccommunity/SqlServerDsc/blob/main/azure-pipelines.yml)
