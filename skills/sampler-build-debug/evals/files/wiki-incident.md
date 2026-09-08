# Wiki publication incident fixtures

Sanitized evidence from WindowsAccessControl, collected on 2026-09-06.
These are observations and source excerpts, not recovery commands. No tokens,
credential-bearing URLs, personal paths, or publication access are included.
The actual release archive bytes are not bundled: a new reproduction needs that
archive, not generated files chosen to match its count.

## Failed command and run

Run `34026468199`, attempt `2`, job `101473822478`; the commit SHA and exact
step timestamps are not supplied. Consult raw logs and fresh metadata before
correlating another attempt. Publication used `windows-latest` and `pwsh`;
the exact PowerShell version is not supplied. Dependencies: Sampler `0.120.0`,
Sampler.GitHubTasks `0.4.1`, DscResource.DocGenerator `0.13.0`.

```text
Publishing Wiki content.
ERROR: Command: git commit --message "Updating Wiki with the content for module version '0.2.0-preview0001'."
git exit code: '-1'
git standard output: ''
git standard error: ''
```

The failure occurred after approximately 120 seconds, before any wiki push.

## Wrapper implementation

Read-only excerpt of `Invoke-Git` in DscResource.DocGenerator `v0.13.0`, with
intervening setup and diagnostics omitted. Rechecked against the tagged source
on 2026-09-08. The `TimeOut` parameter defaults to `120000` milliseconds.

```powershell
$gitResult = @{
    'ExitCode'         = -1
    'StandardOutput'   = ''
    'StandardError'    = ''
}

$process.StartInfo.RedirectStandardOutput = $true
$process.StartInfo.RedirectStandardError = $true
$process.StartInfo.UseShellExecute = $false

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

The function's `finally` disposes the process object. A nonzero result throws
unless `PassThru` was requested; `PassThru` returns the result table. The excerpt
does not demonstrate that a timed-out child was terminated.

## Local probe outcomes

The original probe used the unmodified dependency on Windows, the actual
127-file `WikiContent.zip` release archive, disposable local repositories, and
a shortened `3000` ms wrapper timeout. These are incident results, not new
evaluation measurements or universal thresholds.

| Scenario | Added | Modified | Exit | Elapsed ms | Captured output |
| --- | --- | --- | --- | --- | --- |
| Initial import over Home only | 126 | 1 | -1 | 3042 | Empty stdout and stderr |
| Update populated wiki | 0 | 127 | 0 | 157 | 112 bytes stdout |
| Initial import, quiet commit | 126 | 1 | 0 | 104 | No stdout |

## Working-pipeline configuration

Pipeline source rechecked on 2026-09-08; configuration evidence is not a fresh
hosted publication test. Dependency versions are not pinned in these pipeline
excerpts; compare the actual resolved artifacts separately.

| Configuration | ActiveDirectoryDsc | SqlServerDsc | Failing publication |
| --- | --- | --- | --- |
| Build runner | windows-latest | windows-latest | windows-latest |
| Build edition | PowerShell@2, pwsh true | PowerShell@2, pwsh true | pwsh |
| Publish runner | ubuntu-latest | ubuntu-latest | windows-latest |
| Publish edition | PowerShell@2, pwsh true | PowerShell@2, pwsh true | pwsh |
| Prepared artifact | DownloadPipelineArtifact@2, output | DownloadPipelineArtifact@2, output | Downloaded build output |
| Publish invocation | ./build.ps1 -tasks publish | ./build.ps1 -tasks publish | ./build.ps1 -Tasks publish |

The incident investigation found both references using the standard
`Publish_GitHub_Wiki_Content` task without the proposed custom workaround.
The pipeline invokes `publish`; its expansion belongs to build configuration
and the resolved dependency, not the runner label.

## Partial release state

Observed after the failed attempt, not a claim about current live state:

| Destination | Observation |
| --- | --- |
| GitHub release/tag | Release `v0.2.0-preview0001` and its two assets existed; verify the tag target before recovery. |
| Gallery | Package `0.2.0-preview0001` already published; an immutable-version conflict could prevent a blanket retry reaching the wiki. |
| Wiki | Original Home page only, no release tag; failure before wiki push. |
| Changelog | Completion not established here; inspect separately if applicable. |

Fetched webpage status later contradicted newer evidence in the incident.
Treat page snapshots as potentially stale; no later outcome is supplied here.
