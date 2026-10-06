#Requires -Version 7
<#
.SYNOPSIS
    Latency Meter of Decision record 0028 for the calibration hooks.
.DESCRIPTION
    Measures SessionStart.AddedLatency and PostToolUse.CallLatency through
    each host's exact spawn, process start included: the VS Code spawn runs the
    hook's windows command under powershell.exe, the SDK spawn runs its
    powershell command under pwsh. Each cell runs twice to warm up and then
    -Runs times measured, every run with a new session id.

    The scripts of this working tree are staged in the deployed layout under a
    scratch home, with a profile behind a Canonical target, so the meter never
    reads the contributor's own profile or git configuration. Cells:

    - SessionStart without declared Knowledge areas, the baseline.
    - SessionStart with declared areas and a profile; must carry the levels.
    - SessionStart with declared areas and no profile; must carry the unrated
      sentence.
    - PostToolUse with nothing pending, the common path of the re-sent levels.
    - The push guard on a benign tool call: the same-day proxy that the
      PostToolUse budget was derived from.

    SessionStart writes its session clock to the real per-user application
    data folder, which the host spawn cannot redirect; the meter deletes every
    clock that names its scratch folder.
.PARAMETER Runs
    Measured runs per cell. p95 uses the nearest rank, so with 10 runs it is the
    slowest run.
.EXAMPLE
    pwsh -NoProfile -File tests/Fixtures/Measure-CalibrationLatency.ps1 |
        Format-Table -AutoSize

    Measures every cell on this machine and prints the verdicts.
.NOTES
    Windows only: the VS Code spawn is the Windows one. Not run by the test
    suite; record its results in Decision record 0028.
#>
[CmdletBinding()]
param
(
    [Parameter()]
    [ValidateRange(3, 100)]
    [System.Int32]
    $Runs = 10
)

$ErrorActionPreference = 'Stop'
if (-not $IsWindows)
{
    throw 'The latency Meter measures the Windows host spawns and runs on Windows only.'
}

$repositoryRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
. (Join-Path -Path $repositoryRoot -ChildPath 'tests/Helpers/ContributorProfileFixture.ps1')

function Initialize-MeterHome
{
    param ([string] $Root, [string] $Name, [switch] $WithProfile)

    $userHome = Join-Path -Path $Root -ChildPath "home-$Name"
    $target = Join-Path -Path $Root -ChildPath "target-$Name"
    $null = New-Item -ItemType Directory -Force -Path (Join-Path $target 'hooks/scripts'), (Join-Path $target 'skills'), (Join-Path $userHome '.copilot')
    Set-Content -LiteralPath (Join-Path $target '.copilotatelier.json') -Value '{}' -Encoding ascii
    Copy-Item -Path (Join-Path $repositoryRoot 'com.github.copilot/hooks/scripts/*.ps1') -Destination (Join-Path $target 'hooks/scripts')
    Copy-Item -Path (Join-Path $repositoryRoot 'skills/contributor-profile') -Destination (Join-Path $target 'skills') -Recurse
    foreach ($folder in 'hooks', 'skills')
    {
        $null = New-Item -ItemType Junction -Path (Join-Path $userHome ".copilot/$folder") -Target (Join-Path $target $folder)
    }

    if ($WithProfile)
    {
        Write-ContributorFixture -Case @{ Text = (New-ContributorFixtureProfile) } -Path (Join-Path $target 'contributor/profile.json')
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

function Get-NearestRank
{
    param ([double[]] $Value, [double] $Percent)

    $sorted = @($Value | Sort-Object)
    $rank = [System.Math]::Max(0, [System.Math]::Ceiling($Percent / 100 * $sorted.Count) - 1)
    return [System.Math]::Round($sorted[$rank], 0)
}

$root = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('calibration-meter-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
try
{
    $profileHome = Initialize-MeterHome -Root $root -Name 'profile' -WithProfile
    $noProfileHome = Initialize-MeterHome -Root $root -Name 'no-profile'
    $declared = New-ContributorTestWorkspace -Path (Join-Path $root 'declared') -Area 'Kerberos', 'PowerShell DSC', 'Pester'
    $plain = New-ContributorTestWorkspace -Path (Join-Path $root 'plain')
    $gitConfig = Join-Path -Path $root -ChildPath 'empty.gitconfig'
    Set-Content -LiteralPath $gitConfig -Value '' -Encoding ascii

    $hooks = (Get-Content -LiteralPath (Join-Path $repositoryRoot 'com.github.copilot/hooks/hooks.json') -Raw | ConvertFrom-Json).hooks
    $template = (Get-Content -LiteralPath (Join-Path $repositoryRoot 'skills/contributor-profile/assets/contributor-profile.hooks.json') -Raw | ConvertFrom-Json).hooks
    $spawns = @(
        @{ Host = 'VS Code'; Key = 'windows'; Executable = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'; Prefix = @('-ExecutionPolicy', 'Bypass', '-NoProfile', '-NoLogo', '-Command'); ToolBudget = 600 }
        @{ Host = 'SDK'; Key = 'powershell'; Executable = (Get-Command -Name 'pwsh' -CommandType Application | Select-Object -First 1).Source; Prefix = @('-nop', '-nol', '-c'); ToolBudget = 900 }
    )
    $cells = @(
        @{ Name = 'SessionStart, no declaration'; Entry = @($hooks.SessionStart)[0]; Event = 'SessionStart'; Workspace = $plain; Home = $profileHome; Expect = $null }
        @{ Name = 'SessionStart, declared areas and profile'; Entry = @($hooks.SessionStart)[0]; Event = 'SessionStart'; Workspace = $declared; Home = $profileHome; Expect = 'Contributor familiarity levels' }
        @{ Name = 'SessionStart, declared areas, no profile'; Entry = @($hooks.SessionStart)[0]; Event = 'SessionStart'; Workspace = $declared; Home = $noProfileHome; Expect = 'No contributor profile levels' }
        @{ Name = 'PostToolUse, nothing pending'; Entry = @($template.PostToolUse)[0]; Event = 'PostToolUse'; Workspace = $declared; Home = $profileHome; Expect = $null }
        @{ Name = 'Proxy: push guard, benign tool'; Entry = @($hooks.PreToolUse)[0]; Event = 'PreToolUse'; Workspace = $declared; Home = $profileHome; Expect = $null }
    )

    foreach ($spawn in $spawns)
    {
        $measured = [ordered] @{}
        foreach ($cell in $cells)
        {
            $samples = for ($index = 0; $index -lt ($Runs + 2); $index++)
            {
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

                $run = Measure-HookRun -Spawn $spawn -Command $cell.Entry.($spawn.Key) -Payload ($payload | ConvertTo-Json -Compress -Depth 5) -UserHome $cell.Home -GitConfig $gitConfig
                if ($run.ExitCode -ne 0)
                {
                    throw "$($spawn.Host) '$($cell.Name)' exited with $($run.ExitCode)."
                }

                if ($cell.Expect -and $run.Output -notmatch [regex]::Escape($cell.Expect))
                {
                    throw "$($spawn.Host) '$($cell.Name)' did not emit '$($cell.Expect)'."
                }

                if ($index -ge 2)
                {
                    $run.Milliseconds
                }
            }

            $measured[$cell.Name] = [pscustomobject] @{
                P50 = Get-NearestRank -Value $samples -Percent 50
                P95 = Get-NearestRank -Value $samples -Percent 95
                Max = [System.Math]::Round(($samples | Measure-Object -Maximum).Maximum, 0)
            }
        }

        $baseline = $measured['SessionStart, no declaration']
        foreach ($name in $measured.Keys)
        {
            $value = $measured[$name]
            $added = $null
            $addedMedian = $null
            $budget = $null
            $fail = $null
            $verdict = 'reference'

            if ($name -like 'SessionStart, declared*')
            {
                # p95 of few runs is the slowest run; the median difference shows whether one outlier moved it.
                $added = $value.P95 - $baseline.P95
                $addedMedian = $value.P50 - $baseline.P50
                $budget = 100
                $fail = 250
            }
            elseif ($name -like 'PostToolUse*')
            {
                $budget = $spawn.ToolBudget
                $fail = 1000
            }

            if ($null -ne $budget)
            {
                $scale = if ($null -ne $added) { $added } else { $value.P95 }
                $verdict = if ($scale -gt $fail) { 'fail' } elseif ($scale -gt $budget) { 'over budget' } else { 'within budget' }
            }

            [pscustomobject] @{
                Host     = $spawn.Host
                Cell     = $name
                P50      = $value.P50
                P95      = $value.P95
                Max      = $value.Max
                AddedP95 = $added
                AddedP50 = $addedMedian
                Budget   = $budget
                Fail     = $fail
                Verdict  = $verdict
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
