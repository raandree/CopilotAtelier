#Requires -Version 7
<#
.SYNOPSIS
    Latency Meter of Decision record 0028 for the calibration hooks.
.DESCRIPTION
    Measures SessionStart.AddedLatency and PostToolUse.CallLatency as rulings
    A1 to A3 amended them: in launches of a fixed no-op hook through the same
    launcher and spawn, never in absolute milliseconds. Each host's exact spawn
    runs with process start included: the VS Code spawn runs a hook's windows
    command under powershell.exe, the SDK spawn its powershell command under
    pwsh.

    A replicate runs every cell once, back to back, in an order rotated by one
    place per replicate; -WarmUp replicates run first and are discarded, then
    -Replicates are measured. Ratios are taken inside each replicate before
    the nearest-rank p95, through tests/Helpers/CalibrationMeter.ps1:

    - SessionStart added: the time with declared Knowledge areas minus the
      time without a declaration, divided by the no-op launch. Gated for a
      profile with one entry and for no profile, at Budget 0.5 and Fail 1.0
      launch; reported for two entries, where the identity rule runs git.
    - PostToolUse: one call with nothing pending divided by the no-op launch,
      gated at Budget 1.1 and Fail 1.25 launch.
    - The push guard on a benign tool call divided by the no-op launch:
      reported beside the unit, never used as it.

    Thresholds are inclusive. A verdict above Budget or Fail counts only when
    a second Meter run reproduces it, so -Repeat runs the whole Meter that many
    times and merges each gated cell to its least severe verdict; with -Repeat
    1 such a verdict stays unconfirmed.

    The scripts of this working tree are staged in the deployed layout under a
    scratch home, with profiles behind a Canonical target, so the Meter never
    reads the contributor's own profile or git configuration. SessionStart
    writes its session clock to the real per-user application data folder,
    which the host spawn cannot redirect; the Meter deletes every clock that
    names its scratch folder.
.PARAMETER Replicates
    Measured replicates per run. With 20, p95 is the 19th smallest ratio.
.PARAMETER WarmUp
    Replicates run first and discarded.
.PARAMETER Repeat
    Whole Meter runs whose verdicts merge: a verdict above Budget or Fail
    counts only when every run reproduces it.
.EXAMPLE
    pwsh -NoProfile -File tests/Fixtures/Measure-CalibrationLatency.ps1 |
        Format-Table -AutoSize

    Runs the Meter twice on this machine and prints every run and the
    reproduced verdicts.
.NOTES
    Windows only: the VS Code spawn is the Windows one. Not run by the test
    suite; record its results in Decision record 0028. A change to a launcher
    in hooks.json changes the unit, so re-run the Meter and re-baseline the
    latency levels then (Decision record 0016).
#>
[CmdletBinding()]
param
(
    [Parameter()]
    [ValidateRange(3, 200)]
    [System.Int32]
    $Replicates = 20,

    [Parameter()]
    [ValidateRange(0, 20)]
    [System.Int32]
    $WarmUp = 2,

    [Parameter()]
    [ValidateRange(1, 5)]
    [System.Int32]
    $Repeat = 2
)

$ErrorActionPreference = 'Stop'
if (-not $IsWindows)
{
    throw 'The latency Meter measures the Windows host spawns and runs on Windows only.'
}

$repositoryRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
. (Join-Path -Path $repositoryRoot -ChildPath 'tests/Helpers/ContributorProfileFixture.ps1')
. (Join-Path -Path $repositoryRoot -ChildPath 'tests/Helpers/CalibrationMeter.ps1')

# The unit of every latency level (ruling A1): a hook that reads its payload
# the way the shipped hooks do and does nothing else. Keep it fixed; changing
# it changes every ratio.
$noOpHookText = @'
$reader = [IO.StreamReader]::new([Console]::OpenStandardInput(), [Text.UTF8Encoding]::new($false))
try {
    $null = $reader.ReadToEnd()
} finally {
    $reader.Dispose()
}

exit 0
'@

function Initialize-MeterHome
{
    param ([string] $Root, [string] $Name, [string] $ProfileText)

    $userHome = Join-Path -Path $Root -ChildPath "home-$Name"
    $target = Join-Path -Path $Root -ChildPath "target-$Name"
    $null = New-Item -ItemType Directory -Force -Path (Join-Path $target 'hooks/scripts'), (Join-Path $target 'skills'), (Join-Path $userHome '.copilot')
    Set-Content -LiteralPath (Join-Path $target '.copilotatelier.json') -Value '{}' -Encoding ascii
    Copy-Item -Path (Join-Path $repositoryRoot 'com.github.copilot/hooks/scripts/*.ps1') -Destination (Join-Path $target 'hooks/scripts')
    Set-Content -LiteralPath (Join-Path $target 'hooks/scripts/Invoke-NoOpHook.ps1') -Value $noOpHookText -Encoding ascii
    Copy-Item -Path (Join-Path $repositoryRoot 'skills/contributor-profile') -Destination (Join-Path $target 'skills') -Recurse
    foreach ($folder in 'hooks', 'skills')
    {
        $null = New-Item -ItemType Junction -Path (Join-Path $userHome ".copilot/$folder") -Target (Join-Path $target $folder)
    }

    if ($ProfileText)
    {
        Write-ContributorFixture -Case @{ Text = $ProfileText } -Path (Join-Path $target 'contributor/profile.json')
    }

    return $userHome
}

function Measure-HookRun
{
    param ($Spawn, [string] $Command, [string] $Payload, [string] $UserHome, [string] $GitConfig)

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new($Spawn.Executable)
    foreach ($argument in $Spawn.Prefix)
    {
        $startInfo.ArgumentList.Add($argument)
    }

    $startInfo.ArgumentList.Add($Command)
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.EnvironmentVariables['USERPROFILE'] = $UserHome
    $startInfo.EnvironmentVariables['HOME'] = $UserHome
    $startInfo.EnvironmentVariables['GIT_CONFIG_GLOBAL'] = $GitConfig
    $startInfo.EnvironmentVariables['GIT_CONFIG_NOSYSTEM'] = '1'
    $startInfo.EnvironmentVariables.Remove('PLUGIN_ROOT')

    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    $process = [System.Diagnostics.Process]::Start($startInfo)
    try
    {
        $output = $process.StandardOutput.ReadToEndAsync()
        $null = $process.StandardError.ReadToEndAsync()
        $process.StandardInput.Write($Payload)
        $process.StandardInput.Close()
        $process.WaitForExit()
        $watch.Stop()

        return [pscustomobject] @{
            Milliseconds = $watch.Elapsed.TotalMilliseconds
            ExitCode     = $process.ExitCode
            Output       = $output.Result
        }
    }
    finally
    {
        $process.Dispose()
    }
}

$root = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('calibration-meter-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
try
{
    $twoEntries = New-ContributorFixtureProfile -Entry @(
        (New-ContributorFixtureEntry -Default 'true')
        (New-ContributorFixtureEntry -Id (New-ContributorFixtureId -Number 2) -Aliases '["bob@example.com"]' -Areas '{"Pester":{"level":"familiar","updatedUtc":"2026-10-01T08:00:00Z"}}')
    )
    $oneEntryHome = Initialize-MeterHome -Root $root -Name 'one-entry' -ProfileText (New-ContributorFixtureProfile)
    $noProfileHome = Initialize-MeterHome -Root $root -Name 'no-profile'
    $twoEntryHome = Initialize-MeterHome -Root $root -Name 'two-entries' -ProfileText $twoEntries
    $areas = 'Kerberos', 'PowerShell DSC', 'Pester'
    $declared = New-ContributorTestWorkspace -Path (Join-Path $root 'declared') -Area $areas
    # With two entries the identity rule runs git; this workspace's address selects the second entry.
    $declaredGit = New-ContributorTestWorkspace -Path (Join-Path $root 'declared-git') -Area $areas
    $null = New-ContributorGitRepository -Path $declaredGit -Email 'bob@example.com'
    $plain = New-ContributorTestWorkspace -Path (Join-Path $root 'plain')
    $gitConfig = Join-Path -Path $root -ChildPath 'empty.gitconfig'
    Set-Content -LiteralPath $gitConfig -Value '' -Encoding ascii

    $hooks = (Get-Content -LiteralPath (Join-Path $repositoryRoot 'com.github.copilot/hooks/hooks.json') -Raw | ConvertFrom-Json).hooks
    $template = (Get-Content -LiteralPath (Join-Path $repositoryRoot 'skills/contributor-profile/assets/contributor-profile.hooks.json') -Raw | ConvertFrom-Json).hooks
    $sessionStart = @($hooks.SessionStart)[0]
    $noOp = @{}
    foreach ($key in 'windows', 'powershell')
    {
        # The same launcher and spawn as the measured hooks, only the script differs.
        $noOp[$key] = $sessionStart.$key.Replace('Add-SessionContext.ps1', 'Invoke-NoOpHook.ps1')
        if ($noOp[$key] -ceq $sessionStart.$key)
        {
            throw "The SessionStart $key launcher no longer names Add-SessionContext.ps1, so the no-op hook cannot share it."
        }
    }

    $spawns = @(
        @{ Host = 'VS Code'; Key = 'windows'; Executable = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'; Prefix = @('-ExecutionPolicy', 'Bypass', '-NoProfile', '-NoLogo', '-Command') }
        @{ Host = 'SDK'; Key = 'powershell'; Executable = (Get-Command -Name 'pwsh' -CommandType Application | Select-Object -First 1).Source; Prefix = @('-nop', '-nol', '-c') }
    )
    $cells = [ordered] @{
        noop     = @{ Name = 'No-op hook'; Gate = 'unit'; Entry = $noOp; Event = 'SessionStart'; Workspace = $plain; Home = $oneEntryHome; Expect = $null }
        baseline = @{ Name = 'SessionStart, no declaration'; Gate = 'reported'; Entry = $sessionStart; Event = 'SessionStart'; Workspace = $plain; Home = $oneEntryHome; Expect = $null }
        one      = @{ Name = 'SessionStart, one entry'; Gate = 'gated'; Added = $true; Entry = $sessionStart; Event = 'SessionStart'; Workspace = $declared; Home = $oneEntryHome; Expect = '"Kerberos" new' }
        none     = @{ Name = 'SessionStart, no profile'; Gate = 'gated'; Added = $true; Entry = $sessionStart; Event = 'SessionStart'; Workspace = $declared; Home = $noProfileHome; Expect = 'No contributor profile levels' }
        two      = @{ Name = 'SessionStart, two entries'; Gate = 'reported'; Added = $true; Entry = $sessionStart; Event = 'SessionStart'; Workspace = $declaredGit; Home = $twoEntryHome; Expect = '"Pester" familiar' }
        post     = @{ Name = 'PostToolUse, nothing pending'; Gate = 'gated'; Entry = @($template.PostToolUse)[0]; Event = 'PostToolUse'; Workspace = $declared; Home = $oneEntryHome; Expect = $null }
        guard    = @{ Name = 'Push guard, benign tool'; Gate = 'reported'; Entry = @($hooks.PreToolUse)[0]; Event = 'PreToolUse'; Workspace = $declared; Home = $oneEntryHome; Expect = $null }
    }

    $cellKeys = [System.String[]] @($cells.Keys)
    $budgets = Get-CalibrationMeterBudget
    $rows = [System.Collections.Generic.List[object]]::new()
    for ($run = 1; $run -le $Repeat; $run++)
    {
        foreach ($spawn in $spawns)
        {
            $samples = [System.Collections.Generic.List[hashtable]]::new()
            for ($replicate = 0; $replicate -lt ($WarmUp + $Replicates); $replicate++)
            {
                Write-Verbose -Message ('Run {0}, {1}, replicate {2} of {3}' -f $run, $spawn.Host, ($replicate + 1), ($WarmUp + $Replicates))
                $times = @{}
                foreach ($key in (Get-CalibrationMeterOrder -Cell $cellKeys -Replicate $replicate))
                {
                    $cell = $cells[$key]
                    $payload = [ordered] @{ hook_event_name = $cell.Event; session_id = [guid]::NewGuid().ToString(); cwd = $cell.Workspace; source = 'new' }
                    if ($cell.Event -ne 'SessionStart')
                    {
                        $payload.tool_name = 'view'
                        $payload.tool_input = @{ path = 'README.md' }
                    }

                    if ($cell.Event -eq 'PostToolUse')
                    {
                        # A realistic tool result: the hook must find session_id without parsing it.
                        $payload.tool_result = @{ result_type = 'success'; text_result_for_llm = ('line of file text ' * 400) }
                    }

                    $measurement = Measure-HookRun -Spawn $spawn -Command $cell.Entry.($spawn.Key) -Payload ($payload | ConvertTo-Json -Compress -Depth 5) -UserHome $cell.Home -GitConfig $gitConfig
                    if ($measurement.ExitCode -ne 0)
                    {
                        throw "$($spawn.Host) '$($cell.Name)' exited with $($measurement.ExitCode)."
                    }

                    if ($cell.Expect)
                    {
                        $context = try { [string] ($measurement.Output | ConvertFrom-Json).additionalContext } catch { [string] $measurement.Output }
                        if (-not $context.Contains($cell.Expect))
                        {
                            throw "$($spawn.Host) '$($cell.Name)' did not emit '$($cell.Expect)'."
                        }
                    }

                    $times[$key] = $measurement.Milliseconds
                }

                if ($replicate -ge $WarmUp)
                {
                    $samples.Add($times)
                }
            }

            foreach ($key in $cellKeys)
            {
                $cell = $cells[$key]
                $absolute = [System.Double[]] @($samples | ForEach-Object -Process { $_[$key] })
                $ratio = $null
                $added = $null
                if ($cell.Added)
                {
                    $ratio = [System.Double[]] @(Get-CalibrationMeterRatio -Replicate $samples.ToArray() -Subject $key -Baseline 'baseline')
                    $added = [System.Double[]] @($samples | ForEach-Object -Process { $_[$key] - $_['baseline'] })
                }
                elseif ($key -ne 'noop')
                {
                    $ratio = [System.Double[]] @(Get-CalibrationMeterRatio -Replicate $samples.ToArray() -Subject $key)
                }

                $budget = $budgets[$cell.Name]
                $ratioP95 = if ($ratio) { Get-CalibrationMeterRank -Value $ratio -Percent 95 } else { $null }
                $row = [pscustomobject] @{
                    Run        = $run
                    Host       = $spawn.Host
                    Cell       = $cell.Name
                    Gate       = $cell.Gate
                    RatioP50   = if ($ratio) { [System.Math]::Round((Get-CalibrationMeterRank -Value $ratio -Percent 50), 2) } else { $null }
                    RatioP95   = if ($ratio) { [System.Math]::Round($ratioP95, 2) } else { $null }
                    Budget     = if ($budget) { $budget.Budget } else { $null }
                    Fail       = if ($budget) { $budget.Fail } else { $null }
                    Verdict    = if ($budget) { Get-CalibrationMeterVerdict -Value $ratioP95 -Budget $budget.Budget -Fail $budget.Fail } else { $cell.Gate }
                    P50Ms      = [System.Math]::Round((Get-CalibrationMeterRank -Value $absolute -Percent 50), 0)
                    P95Ms      = [System.Math]::Round((Get-CalibrationMeterRank -Value $absolute -Percent 95), 0)
                    AddedP95Ms = if ($added) { [System.Math]::Round((Get-CalibrationMeterRank -Value $added -Percent 95), 0) } else { $null }
                }

                $rows.Add($row)
                $row
            }
        }
    }

    # A verdict above Budget or Fail counts only when every run reproduces it.
    foreach ($spawn in $spawns)
    {
        foreach ($key in $cellKeys)
        {
            $cell = $cells[$key]
            if ($cell.Gate -ne 'gated')
            {
                continue
            }

            $runRows = @($rows | Where-Object -FilterScript { $_.Host -eq $spawn.Host -and $_.Cell -eq $cell.Name })
            $ratios = @($runRows | ForEach-Object -Process { $_.RatioP95 } | Sort-Object)
            [pscustomobject] @{
                Run        = 'reproduced'
                Host       = $spawn.Host
                Cell       = $cell.Name
                Gate       = $cell.Gate
                RatioP50   = $null
                RatioP95   = if ($ratios.Count -gt 1) { '{0} to {1}' -f $ratios[0], $ratios[-1] } else { $ratios[0] }
                Budget     = $runRows[0].Budget
                Fail       = $runRows[0].Fail
                Verdict    = Merge-CalibrationMeterVerdict -Verdict @($runRows | ForEach-Object -Process { $_.Verdict })
                P50Ms      = $null
                P95Ms      = $null
                AddedP95Ms = $null
            }
        }
    }
}
finally
{
    $sessions = Join-Path -Path ([System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::LocalApplicationData)) -ChildPath 'CopilotAtelier/sessions'
    $marker = [regex]::Escape($root.Replace('\', '\\'))
    Get-ChildItem -LiteralPath $sessions -Filter 'session-*.json' -File -ErrorAction SilentlyContinue |
        Where-Object -FilterScript { (Get-Content -LiteralPath $_.FullName -Raw -ErrorAction SilentlyContinue) -match $marker } |
        Remove-Item -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
