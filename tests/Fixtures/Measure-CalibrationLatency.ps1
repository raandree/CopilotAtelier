#Requires -Version 7
<#
.SYNOPSIS
    Latency Meter of Decision record 0028 for the calibration hooks.
.DESCRIPTION
    Measures SessionStart.AddedLatency and PostToolUse.CallLatency as rulings
    A9 and A17 amended them: in frozen references, never in absolute
    milliseconds. Each host's exact spawn runs with process start included: the
    VS Code spawn runs a hook's windows command under powershell.exe, the SDK
    spawn its powershell command under pwsh. The no-op hook and the frozen
    reference, tests/Fixtures/ReferenceHook, run through the same launcher and
    spawn as the measured hooks. The reference's driver runs one fixed
    calibration on its own fixture with a frozen copy of the calibration
    reader, so the unit is the SessionStart calibration step's kind of work.

    A replicate runs every cell once, back to back, in an order rotated by one
    place per replicate; -WarmUp replicates run first and are discarded, then
    -Replicates are measured. Every cell's step is its time net of the same
    replicate's no-op hook, and the unit is the reference's step in the same
    replicate. Ratios are taken inside each replicate before the nearest-rank
    p95, through tests/Helpers/CalibrationMeter.ps1:

    - SessionStart added: the time with declared Knowledge areas minus the
      time without a declaration. Gated for a profile with one entry and for
      no profile, with a stop line at a step p95 of 1,000 ms; reported for two
      entries, where the identity rule runs git.
    - PostToolUse common path: a call in a session that SessionStart armed for
      the backstop, with nothing due, so the hook evaluates both backstop
      signals and injects nothing. Gated, with a stop line at a step p95 of
      400 ms.
    - PostToolUse inject path: a call on which a closed turn makes the backstop
      due, so the hook rereads the declaration and the profile, records the
      injection, and emits the sentence. Reported, never gated (ruling A12).
    - The push guard on a benign tool call: reported beside the PostToolUse
      hook (ruling A11).

    Every cell also reports its absolute and its step milliseconds, and the
    reference reports its own step, the unit's calibration. Each gated cell
    is judged against the Budget and Fail of Get-CalibrationMeterBudget,
    which the re-baseline rule set on 2026-10-08, one w per tag (ruling A16);
    a gated cell without a level reads 'no level (A10)'. Thresholds are
    inclusive, and a verdict above Budget or Fail counts only when a second
    Meter run reproduces it: -Repeat runs the whole Meter that many times, and
    each gated cell's reproduced row names its lower run, the input of the
    re-baseline rule, and the run-to-run spread, its higher run divided by its
    lower.

    The scripts of this working tree are staged in the deployed layout under a
    scratch home, with profiles behind a Canonical target, so the Meter never
    reads the contributor's own profile or git configuration. Both editions
    resolve LocalApplicationData through the scratch home's USERPROFILE, and
    Windows PowerShell falls back to the temp directory when that folder is
    missing, so the Meter creates it: every hook keeps its session clock and
    calibration state there, and the Meter writes the state the PostToolUse
    cells start from beside them.
.PARAMETER Replicates
    Measured replicates per run. With 20, p95 is the 19th smallest ratio.
.PARAMETER WarmUp
    Replicates run first and discarded.
.PARAMETER Repeat
    Whole Meter runs whose verdicts merge: a verdict above Budget or Fail
    counts only when every run reproduces it.
.PARAMETER OutputDirectory
    Folder that receives calibration-meter-<computer>-<UTC time>.csv with
    every row, each stamped with the computer, the start time, the reference
    hash, and the versions of both editions and of git, and a -failures.csv
    beside it when a launch failed. Defaults to the temp folder, outside every
    working tree. The CSV keeps the columns a narrow console's table drops.
.EXAMPLE
    pwsh -NoProfile -Command '& ./tests/Fixtures/Measure-CalibrationLatency.ps1 | Format-Table -AutoSize'

    Runs the Meter twice on this machine and prints every run and the
    reproduced rows as one table, then names the CSV that holds every column.
    Format inside the Meter's process: a parent shell receives a child's
    output as text, which Format-Table cannot lay out.
.NOTES
    Windows only: the VS Code spawn is the Windows one. Not run by the test
    suite; record its results in Decision record 0028. Refuses to run when any
    file of the frozen reference no longer matches its pinned composite
    SHA-256. A change to a launcher in hooks.json changes the launch the unit
    is measured through, so re-run the Meter and re-baseline the latency
    levels then (Decision record 0016).

    A launch that exits non-zero measured no hook time. Its exit code and
    standard error are warned about at once and kept in the failures CSV, and
    the launch runs once more in the same position; a second failure in a row
    stops the Meter. The rows of an incomplete run are still written.
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
    $Repeat = 2,

    [Parameter()]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
    [System.String]
    $OutputDirectory = [System.IO.Path]::GetTempPath()
)

$ErrorActionPreference = 'Stop'
if (-not $IsWindows)
{
    throw 'The latency Meter measures the Windows host spawns and runs on Windows only.'
}

$repositoryRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
. (Join-Path -Path $repositoryRoot -ChildPath 'tests/Helpers/ContributorProfileFixture.ps1')
. (Join-Path -Path $repositoryRoot -ChildPath 'tests/Helpers/CalibrationMeter.ps1')

# The unit of every latency level (rulings A9 and A17) is the frozen
# reference's step over the no-op hook. Any other reference would make every
# ratio incomparable with the levels recorded against the pinned one.
$referenceFolder = Join-Path -Path $PSScriptRoot -ChildPath 'ReferenceHook'
$referenceHash = Get-CalibrationMeterReferenceHash -Path $referenceFolder
$meterLevels = Get-CalibrationMeterBudget
if ($referenceHash -ne $meterLevels.ReferenceSha256)
{
    throw "The frozen reference has composite SHA-256 $referenceHash, not the pinned $($meterLevels.ReferenceSha256). Re-baseline both latency tags before measuring with it."
}

Write-Information -MessageData ('{0}, {1:yyyy-MM-dd HH:mm} UTC, frozen reference {2}' -f $env:COMPUTERNAME, [System.DateTime]::UtcNow, $referenceHash) -InformationAction Continue

$startedUtc = [System.DateTime]::UtcNow
$resultsPath = Join-Path -Path $OutputDirectory -ChildPath ('calibration-meter-{0}-{1:yyyyMMdd-HHmmss}.csv' -f $env:COMPUTERNAME, $startedUtc)
$failuresPath = [System.IO.Path]::ChangeExtension($resultsPath, $null).TrimEnd('.') + '-failures.csv'
$rows = [System.Collections.Generic.List[object]]::new()
$failures = [System.Collections.Generic.List[object]]::new()

# The tools' versions travel with every CSV row, because a crash or a shift
# in the unit can be a property of one build: both editions, and git, which
# the identity rule runs in the two-entry cell.
$editionVersion = @{ Pwsh = $null; WindowsPowerShell = $null; Git = $null }
$pwshCommand = Get-Command -Name 'pwsh' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if ($pwshCommand)
{
    $editionVersion.Pwsh = ([string] (Get-Item -LiteralPath $pwshCommand.Source).VersionInfo.ProductVersion -split ' ')[0]
}

$editionVersion.WindowsPowerShell = [string] (Get-Item -LiteralPath (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe')).VersionInfo.ProductVersion
$gitCommand = Get-Command -Name 'git' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if ($gitCommand)
{
    $editionVersion.Git = (& $gitCommand.Source --version 2>$null | Select-Object -First 1) -replace '\Agit version ', ''
}

# The hooks resolve their session files under each scratch home. Should one
# fall back to the real folder or to the temp directory, the cleanup removes
# the files of every session the Meter ran there too.
$fallbackSessionRoots = @(
    Join-Path -Path ([System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::LocalApplicationData)) -ChildPath 'CopilotAtelier/sessions'
    Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath 'CopilotAtelier/sessions'
)
$sessionIds = [System.Collections.Generic.List[string]]::new()

# The origin of every step: a hook that reads its payload the way the shipped
# hooks do and does nothing else. Keep it fixed; changing it changes every
# ratio.
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
    # Both editions resolve LocalApplicationData through USERPROFILE, and
    # Windows PowerShell falls back to the temp directory when that folder is
    # missing, so create it: every hook then keeps its session files here.
    $null = New-Item -ItemType Directory -Force -Path (Join-Path $target 'hooks/scripts'), (Join-Path $target 'skills'), (Join-Path $userHome '.copilot'), (Join-Path $userHome 'AppData/Local')
    Set-Content -LiteralPath (Join-Path $target '.copilotatelier.json') -Value '{}' -Encoding ascii
    Copy-Item -Path (Join-Path $repositoryRoot 'com.github.copilot/hooks/scripts/*.ps1') -Destination (Join-Path $target 'hooks/scripts')
    Set-Content -LiteralPath (Join-Path $target 'hooks/scripts/Invoke-NoOpHook.ps1') -Value $noOpHookText -Encoding ascii
    # The whole reference folder, so the driver finds its reader copy and its
    # fixture beside it, outside every git working tree.
    Copy-Item -LiteralPath $referenceFolder -Destination (Join-Path $target 'hooks/scripts/ReferenceHook') -Recurse -Force
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

function Set-MeterSessionState
{
    <#
        The session a PostToolUse cell runs in: a clock whose closed turn count
        is Turns, and a calibration state that SessionStart armed at LastTurn a
        moment ago, so only a closed turn can make the backstop due. Written
        where the hooks resolve their session files under the cell's home.
    #>
    param ([string] $UserHome, [string] $SessionId, [string] $Workspace, [int] $Turns, [int] $LastTurn)

    $sessions = Join-Path -Path $UserHome -ChildPath 'AppData/Local/CopilotAtelier/sessions'
    $null = New-Item -ItemType Directory -Force -Path $sessions
    $now = [System.DateTime]::UtcNow
    $clock = [ordered] @{ startedUtc = $now.AddMinutes(-10).ToString('o'); workspace = $Workspace; turns = $Turns } | ConvertTo-Json -Compress
    $state = '{{"schemaVersion":1,"compactions":0,"injected":0,"lastTurn":{0},"lastInjectionUtc":"{1}","characters":300}}' -f $LastTurn, $now.ToString('o')
    [System.IO.File]::WriteAllText((Join-Path -Path $sessions -ChildPath "session-$SessionId.json"), $clock, [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllText((Join-Path -Path $sessions -ChildPath "session-$SessionId.familiarity.json"), $state, [System.Text.UTF8Encoding]::new($false))
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
        $errorText = $process.StandardError.ReadToEndAsync()
        $process.StandardInput.Write($Payload)
        $process.StandardInput.Close()
        $process.WaitForExit()
        $watch.Stop()

        return [pscustomobject] @{
            Milliseconds = $watch.Elapsed.TotalMilliseconds
            ExitCode     = $process.ExitCode
            Output       = $output.Result
            Error        = $errorText.Result
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
    $reference = @{}
    foreach ($key in 'windows', 'powershell')
    {
        # The same launcher and spawn as the measured hooks, only the script differs.
        $noOp[$key] = $sessionStart.$key.Replace('Add-SessionContext.ps1', 'Invoke-NoOpHook.ps1')
        $reference[$key] = $sessionStart.$key.Replace('Add-SessionContext.ps1', 'ReferenceHook/Invoke-ReferenceHook.ps1')
        if ($noOp[$key] -ceq $sessionStart.$key)
        {
            throw "The SessionStart $key launcher no longer names Add-SessionContext.ps1, so the no-op hook and the reference cannot share it."
        }
    }

    $spawns = @(
        @{ Host = 'VS Code'; Key = 'windows'; Executable = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'; Prefix = @('-ExecutionPolicy', 'Bypass', '-NoProfile', '-NoLogo', '-Command') }
        @{ Host = 'SDK'; Key = 'powershell'; Executable = (Get-Command -Name 'pwsh' -CommandType Application | Select-Object -First 1).Source; Prefix = @('-nop', '-nol', '-c') }
    )
    $postToolUse = @($template.PostToolUse)[0]
    $cells = [ordered] @{
        noop      = @{ Name = 'No-op hook'; Gate = 'origin'; Entry = $noOp; Event = 'SessionStart'; Workspace = $plain; Home = $oneEntryHome; Expect = $null }
        reference = @{ Name = 'Frozen reference'; Gate = 'unit'; Entry = $reference; Event = 'SessionStart'; Workspace = $plain; Home = $oneEntryHome; Expect = $null }
        baseline  = @{ Name = 'SessionStart, no declaration'; Gate = 'reported'; Entry = $sessionStart; Event = 'SessionStart'; Workspace = $plain; Home = $oneEntryHome; Expect = $null }
        one       = @{ Name = 'SessionStart, one entry'; Gate = 'gated'; Added = $true; StopLineMs = 1000; Entry = $sessionStart; Event = 'SessionStart'; Workspace = $declared; Home = $oneEntryHome; Expect = '"Kerberos" new' }
        none      = @{ Name = 'SessionStart, no profile'; Gate = 'gated'; Added = $true; StopLineMs = 1000; Entry = $sessionStart; Event = 'SessionStart'; Workspace = $declared; Home = $noProfileHome; Expect = 'No contributor profile levels' }
        two       = @{ Name = 'SessionStart, two entries'; Gate = 'reported'; Added = $true; Entry = $sessionStart; Event = 'SessionStart'; Workspace = $declaredGit; Home = $twoEntryHome; Expect = '"Pester" familiar' }
        post      = @{ Name = 'PostToolUse, common path'; Gate = 'gated'; StopLineMs = 400; Entry = $postToolUse; Event = 'PostToolUse'; Workspace = $declared; Home = $oneEntryHome; Session = @{ Turns = 1; LastTurn = 1 }; Silent = $true }
        inject    = @{ Name = 'PostToolUse, inject path'; Gate = 'reported'; Entry = $postToolUse; Event = 'PostToolUse'; Workspace = $declared; Home = $oneEntryHome; Session = @{ Turns = 2; LastTurn = 1 }; Expect = 'Current familiarity levels' }
        guard     = @{ Name = 'Push guard, benign tool'; Gate = 'reported'; Entry = @($hooks.PreToolUse)[0]; Event = 'PreToolUse'; Workspace = $declared; Home = $oneEntryHome; Expect = $null }
    }

    $cellKeys = [System.String[]] @($cells.Keys)
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
                    # Each attempt starts its own session, so a retry never meets
                    # the state a failed attempt left behind.
                    $launch = {
                        $sessionId = [guid]::NewGuid().ToString()
                        $sessionIds.Add($sessionId)
                        $payload = [ordered] @{ hook_event_name = $cell.Event; session_id = $sessionId; cwd = $cell.Workspace; source = 'new' }
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

                        if ($cell.Session)
                        {
                            Set-MeterSessionState -UserHome $cell.Home -SessionId $sessionId -Workspace $cell.Workspace -Turns $cell.Session.Turns -LastTurn $cell.Session.LastTurn
                        }

                        Measure-HookRun -Spawn $spawn -Command $cell.Entry.($spawn.Key) -Payload ($payload | ConvertTo-Json -Compress -Depth 5) -UserHome $cell.Home -GitConfig $gitConfig
                    }

                    $measurement = Invoke-CalibrationMeterLaunch -Launch $launch -Failure $failures -Context @{ Run = $run; Host = $spawn.Host; Cell = $cell.Name; Replicate = $replicate + 1 }

                    if ($cell.Expect)
                    {
                        $context = try { [string] ($measurement.Output | ConvertFrom-Json).additionalContext } catch { [string] $measurement.Output }
                        if (-not $context.Contains($cell.Expect))
                        {
                            throw "$($spawn.Host) '$($cell.Name)' did not emit '$($cell.Expect)'."
                        }
                    }

                    if ($cell.Silent -and -not [System.String]::IsNullOrWhiteSpace($measurement.Output))
                    {
                        throw "$($spawn.Host) '$($cell.Name)' emitted output, so it did not measure the common path."
                    }

                    $times[$key] = $measurement.Milliseconds
                }

                if ($replicate -ge $WarmUp)
                {
                    $samples.Add($times)
                }
            }

            # A replicate in which the reference ran no slower than the no-op
            # hook leaves no unit, so that run takes no ratio at all; its
            # milliseconds stay reported as the evidence.
            $unmeasurable = @($samples | Where-Object -FilterScript { $_['reference'] -le $_['noop'] }).Count
            if ($unmeasurable -gt 0)
            {
                Write-Warning -Message ('Run {0}, {1}: the frozen reference ran no slower than the no-op hook in {2} of {3} replicates, so this run takes no ratio.' -f $run, $spawn.Host, $unmeasurable, $samples.Count)
            }

            foreach ($key in $cellKeys)
            {
                $cell = $cells[$key]
                $absolute = [System.Double[]] @($samples | ForEach-Object -Process { $_[$key] })
                $ratio = $null
                $step = $null
                if ($key -ne 'noop')
                {
                    $origin = if ($cell.Added) { 'baseline' } else { 'noop' }
                    $step = [System.Double[]] @($samples | ForEach-Object -Process { $_[$key] - $_[$origin] })
                    if ($key -ne 'reference' -and $unmeasurable -eq 0)
                    {
                        $ratio = [System.Double[]] @(Get-CalibrationMeterRatio -Replicate $samples.ToArray() -Subject $key -Baseline $origin)
                    }
                }

                $level = $meterLevels.Level[$cell.Name]
                $ratioP95 = if ($ratio) { Get-CalibrationMeterRank -Value $ratio -Percent 95 } else { $null }
                $stepP95 = if ($step) { Get-CalibrationMeterRank -Value $step -Percent 95 } else { $null }
                $verdict = if ($unmeasurable -gt 0 -and $key -ne 'noop')
                {
                    'unit unmeasurable'
                }
                elseif ($level)
                {
                    Get-CalibrationMeterVerdict -Value $ratioP95 -Budget $level.Budget -Fail $level.Fail
                }
                elseif ($cell.Gate -eq 'gated')
                {
                    'no level (A10)'
                }
                else
                {
                    $cell.Gate
                }

                $row = [pscustomobject] @{
                    Run       = $run
                    Host      = $spawn.Host
                    Cell      = $cell.Name
                    Gate      = $cell.Gate
                    RatioP50  = if ($ratio) { [System.Math]::Round((Get-CalibrationMeterRank -Value $ratio -Percent 50), 2) } else { $null }
                    RatioP95  = if ($ratio) { [System.Math]::Round($ratioP95, 2) } else { $null }
                    LowerP95  = $null
                    Spread    = $null
                    Budget    = if ($level) { $level.Budget } else { $null }
                    Fail      = if ($level) { $level.Fail } else { $null }
                    Verdict   = $verdict
                    P50Ms     = [System.Math]::Round((Get-CalibrationMeterRank -Value $absolute -Percent 50), 0)
                    P95Ms     = [System.Math]::Round((Get-CalibrationMeterRank -Value $absolute -Percent 95), 0)
                    StepP50Ms = if ($step) { [System.Math]::Round((Get-CalibrationMeterRank -Value $step -Percent 50), 0) } else { $null }
                    StepP95Ms = if ($step) { [System.Math]::Round($stepP95, 0) } else { $null }
                    StopLine  = if ($cell.StopLineMs) { if ($stepP95 -gt $cell.StopLineMs) { 'crossed' } else { 'clear' } } else { $null }
                }

                $rows.Add($row)
                $row
            }
        }
    }

    # A verdict above Budget or Fail counts only when every run reproduces it.
    # The lower run of each gated cell is what the re-baseline rule reads, one
    # w per tag, and the spread is its step 8: the higher run over the lower.
    $reproduced = foreach ($spawn in $spawns)
    {
        foreach ($key in $cellKeys)
        {
            $cell = $cells[$key]
            if ($cell.Gate -ne 'gated')
            {
                continue
            }

            $runRows = @($rows | Where-Object -FilterScript { $_.Host -eq $spawn.Host -and $_.Cell -eq $cell.Name })
            $ratios = @($runRows | Where-Object -FilterScript { $null -ne $_.RatioP95 } | ForEach-Object -Process { $_.RatioP95 } | Sort-Object)
            $crossed = @($runRows | Where-Object -FilterScript { $_.StopLine -eq 'crossed' }).Count
            $complete = $ratios.Count -eq $runRows.Count
            [pscustomobject] @{
                Run       = 'reproduced'
                Host      = $spawn.Host
                Cell      = $cell.Name
                Gate      = $cell.Gate
                RatioP50  = $null
                RatioP95  = if ($ratios.Count -gt 1) { '{0} to {1}' -f $ratios[0], $ratios[-1] } elseif ($ratios.Count -eq 1) { $ratios[0] } else { $null }
                LowerP95  = if ($complete) { $ratios[0] } else { $null }
                Spread    = if ($complete -and $ratios.Count -gt 1 -and $ratios[0] -gt 0) { [System.Math]::Round($ratios[-1] / $ratios[0], 2) } else { $null }
                Budget    = $runRows[0].Budget
                Fail      = $runRows[0].Fail
                Verdict   = if (-not $complete) { 'unit unmeasurable in {0} of {1} runs' -f ($runRows.Count - $ratios.Count), $runRows.Count } elseif ($runRows[0].Budget) { Merge-CalibrationMeterVerdict -Verdict @($runRows | ForEach-Object -Process { $_.Verdict }) } else { 'no level (A10)' }
                P50Ms     = $null
                P95Ms     = $null
                StepP50Ms = $null
                StepP95Ms = $null
                StopLine  = if ($crossed -gt 0) { 'crossed in {0} of {1} runs' -f $crossed, $runRows.Count } else { 'clear' }
            }
        }
    }

    foreach ($row in $reproduced)
    {
        $rows.Add($row)
        $row
    }
}
finally
{
    # Every column a narrow console's table drops, and the rows of an
    # incomplete run, survive in the CSV.
    $stamp = [ordered] @{
        Computer                 = $env:COMPUTERNAME
        StartedUtc               = $startedUtc.ToString('o')
        ReferenceSha256          = $referenceHash
        PwshVersion              = $editionVersion.Pwsh
        WindowsPowerShellVersion = $editionVersion.WindowsPowerShell
        GitVersion               = $editionVersion.Git
    }

    foreach ($set in @(@{ Items = $rows; Path = $resultsPath; Name = 'rows' }, @{ Items = $failures; Path = $failuresPath; Name = 'failed launches' }))
    {
        if ($set.Items.Count -eq 0)
        {
            continue
        }

        try
        {
            $set.Items | ForEach-Object -Process {
                $record = [ordered] @{}
                foreach ($name in $stamp.Keys) { $record[$name] = $stamp[$name] }
                foreach ($property in $_.PSObject.Properties) { $record[$property.Name] = $property.Value }
                [pscustomobject] $record
            } | Export-Csv -LiteralPath $set.Path -NoTypeInformation -Encoding utf8
            Write-Information -MessageData ('Wrote {0} {1} to {2}' -f $set.Items.Count, $set.Name, $set.Path) -InformationAction Continue
        }
        catch
        {
            Write-Warning -Message ('Could not write {0} to {1}: {2}' -f $set.Name, $set.Path, $_.Exception.Message)
        }
    }

    if ($failures.Count -gt 0)
    {
        Write-Warning -Message ('{0} launches failed and ran again; their exit codes and standard error are in {1}.' -f $failures.Count, $failuresPath)
    }

    foreach ($sessionId in $sessionIds)
    {
        foreach ($sessionRoot in $fallbackSessionRoots)
        {
            foreach ($suffix in '.json', '.familiarity.json', '.familiarity.lock')
            {
                $sessionFile = Join-Path -Path $sessionRoot -ChildPath "session-$sessionId$suffix"
                if ([System.IO.File]::Exists($sessionFile))
                {
                    [System.IO.File]::Delete($sessionFile)
                }
            }
        }
    }

    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
