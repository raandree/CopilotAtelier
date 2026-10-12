<#
    Arithmetic of the calibration latency Meter, Decision record 0028, rulings
    A9, A10, A16, A17, and A19. Latency counts in frozen references: every replicate
    runs each cell back to back in rotated order through the same launcher and
    spawn, a cell's time is taken net of the same replicate's no-op hook, and
    the unit is that replicate's frozen reference, a fixed calibration run with
    a frozen copy of the reader, net of the same no-op hook, so machine speed,
    shell edition, and load cancel to first order. Ratios are taken inside a
    replicate before any percentile. A failed launch runs again once; a run
    and spawn with one in a measured replicate is evidence only (A19).
    tests/Fixtures/Measure-CalibrationLatency.ps1 measures; tests/CalibrationMeter.Tests.ps1
    proves this file.
#>

function Get-CalibrationMeterBudget
{
    <#
        The latency levels of the gated cells, in frozen references (rulings
        A9 and A17), and the composite SHA-256 of the frozen reference they
        were set against. The re-baseline rule set them on 2026-10-08, one w
        per tag (ruling A16), from the Prox1 pair of 2026-10-07 15:30 UTC and
        the RAANDREE3 pair of 2026-10-08 09:42 UTC, both spawns, replacing the
        launch-unit levels ruling A10 withdrew. Changing any file of the
        reference changes every ratio: re-baseline both latency tags in the
        commit that changes ReferenceSha256.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param ()

    @{
        ReferenceSha256 = '30fb3229afc003e248371b378883b2164a8ed00338c9f7647b40acfab2d29c79'
        Level           = @{
            'SessionStart, one entry'  = @{ Budget = 2.0; Fail = 4.0 }
            'SessionStart, no profile' = @{ Budget = 2.0; Fail = 4.0 }
            'PostToolUse, common path' = @{ Budget = 0.75; Fail = 1.5 }
        }
    }
}

function Get-CalibrationMeterReferenceHash
{
    <#
        One SHA-256 over the whole frozen reference folder (ruling A17): for
        every file under it, in ascending ordinal order of its relative path
        with forward slashes, the relative path, the length of its LF text,
        and that text, each followed by a NUL character, encoded as UTF-8. LF
        text keeps the line endings a checkout gives a file from moving the
        pin; the path and the length keep a renamed, added, or removed file
        from passing unnoticed. .NET enumerates dot folders on every OS.
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Path
    )

    if (-not [System.IO.Directory]::Exists($Path))
    {
        throw "The frozen reference is a folder, and '$Path' is not one."
    }

    $root = [System.IO.Path]::GetFullPath($Path).TrimEnd([char[]] @([char] 92, [char] 47))
    $relative = [System.String[]] @(
        foreach ($file in [System.IO.Directory]::GetFiles($root, '*', [System.IO.SearchOption]::AllDirectories))
        {
            $file.Substring($root.Length + 1).Replace('\', '/')
        }
    )
    [System.Array]::Sort($relative, [System.StringComparer]::Ordinal)

    $content = [System.Text.StringBuilder]::new()
    foreach ($name in $relative)
    {
        $text = [System.IO.File]::ReadAllText([System.IO.Path]::Combine($root, $name)).Replace("`r`n", "`n")
        $null = $content.Append($name).Append([char] 0).Append($text.Length).Append([char] 0).Append($text).Append([char] 0)
    }

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try
    {
        $digest = $sha.ComputeHash([System.Text.UTF8Encoding]::new($false).GetBytes($content.ToString()))
    }
    finally
    {
        $sha.Dispose()
    }

    return -join ($digest | ForEach-Object -Process { $_.ToString('x2') })
}

function Get-CalibrationMeterOrder
{
    <#
        The cell order of one replicate: the list rotated by one place per
        replicate, so no cell always runs first or always follows the same
        neighbour.
    #>
    [CmdletBinding()]
    [OutputType([System.String[]])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String[]]
        $Cell,

        [Parameter(Mandatory = $true)]
        [ValidateRange(0, 2147483647)]
        [System.Int32]
        $Replicate
    )

    $offset = $Replicate % $Cell.Count
    return [System.String[]] @(
        for ($index = 0; $index -lt $Cell.Count; $index++)
        {
            $Cell[($index + $offset) % $Cell.Count]
        }
    )
}

function Get-CalibrationMeterRatio
{
    <#
        One ratio per replicate, taken before any percentile, because the
        difference of two independently sampled p95 values is not the p95 of
        the added time. The numerator is the subject's milliseconds minus the
        baseline's in the same replicate, the no-op hook unless another cell
        is named; the unit is that replicate's frozen reference minus its
        no-op hook (rulings A9 and A17).
    #>
    [CmdletBinding()]
    [OutputType([System.Double])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Object[]]
        $Replicate,

        [Parameter(Mandatory = $true)]
        [System.String]
        $Subject,

        [Parameter()]
        [System.String]
        $Baseline = 'noop',

        [Parameter()]
        [System.String]
        $Reference = 'reference',

        [Parameter()]
        [System.String]
        $NoOp = 'noop'
    )

    foreach ($sample in $Replicate)
    {
        $unit = [System.Double] $sample[$Reference] - [System.Double] $sample[$NoOp]
        if ($unit -le 0)
        {
            throw ('The frozen reference took {0:N0} ms against {1:N0} ms for the no-op hook in one replicate, so the unit cannot be measured.' -f $sample[$Reference], $sample[$NoOp])
        }

        ([System.Double] $sample[$Subject] - [System.Double] $sample[$Baseline]) / $unit
    }
}

function Get-CalibrationMeterRank
{
    <#
        Nearest-rank percentile: the smallest value that at least Percent of
        the values do not exceed. With 20 replicates p95 is the 19th smallest.
    #>
    [CmdletBinding()]
    [OutputType([System.Double])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Double[]]
        $Value,

        [Parameter(Mandatory = $true)]
        [ValidateRange(0, 100)]
        [System.Double]
        $Percent
    )

    $sorted = [System.Double[]] @($Value | Sort-Object)
    $rank = [System.Math]::Max(1, [System.Math]::Ceiling($Percent / 100 * $sorted.Count))
    return $sorted[$rank - 1]
}

function Get-CalibrationMeterVerdict
{
    <#
        Inclusive thresholds: a value at or below Budget meets it, a value
        above Fail fails, and anything between is over budget.
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Double]
        $Value,

        [Parameter(Mandatory = $true)]
        [System.Double]
        $Budget,

        [Parameter(Mandatory = $true)]
        [System.Double]
        $Fail
    )

    if ($Value -gt $Fail)
    {
        return 'fail'
    }

    if ($Value -gt $Budget)
    {
        return 'over budget'
    }

    return 'within budget'
}

function Merge-CalibrationMeterVerdict
{
    <#
        A verdict above Budget or Fail counts only when a second Meter run
        reproduces it, so several runs merge to their least severe verdict, and
        a single run above Budget stays unconfirmed.
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateSet('within budget', 'over budget', 'fail')]
        [System.String[]]
        $Verdict
    )

    $severity = @{ 'within budget' = 0; 'over budget' = 1; 'fail' = 2 }
    $least = @($Verdict | Sort-Object -Property { $severity[$_] })[0]
    if ($Verdict.Count -lt 2 -and $severity[$least] -gt 0)
    {
        return ('{0} (unconfirmed)' -f $least)
    }

    return $least
}

function Get-CalibrationMeterRebaseline
{
    <#
        Steps 2 and 3 of the re-baseline rule of ruling A9: w is the largest of
        one tag's gated cells' lower-run p95 values, in frozen references,
        across both machines and spawns, so call it once per tag (ruling A16);
        Budget is the smallest multiple of 0.25 that is at least 1.75 times w,
        and Fail is twice Budget. Taking the lower run is what reproduced means
        in Decision record 0028, and the factor exceeds the 1.65 run-to-run
        spread of the 2026-10-06 runs, so the Budget still holds on the higher
        run.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateScript({ $_ -gt 0 })]
        [System.Double[]]
        $LowerRunP95
    )

    $w = ($LowerRunP95 | Measure-Object -Maximum).Maximum
    # Rounded before the ceiling, so a product that floating point puts a
    # rounding error above a step does not take the next step.
    $steps = [System.Math]::Ceiling([System.Math]::Round(1.75 * $w / 0.25, 9))

    [pscustomobject] @{
        W      = $w
        Budget = $steps * 0.25
        Fail   = 2 * $steps * 0.25
    }
}

function Test-CalibrationMeterTransfer
{
    <#
        Step 5 of the re-baseline rule of ruling A9, the unit transfer check
        (TBD-6), applied per tag (ruling A17): ReferenceRatio is the frozen
        reference's RAANDREE3 time divided by its Prox1 time, StepRatio the
        same ratio for the step of the cell that set that tag's w, per spawn.
        The unit cancels machine speed only when the two differ by at most 1.3
        times in either direction.
    #>
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateScript({ $_ -gt 0 })]
        [System.Double]
        $ReferenceRatio,

        [Parameter(Mandatory = $true)]
        [ValidateScript({ $_ -gt 0 })]
        [System.Double]
        $StepRatio
    )

    $spread = [System.Math]::Max($ReferenceRatio / $StepRatio, $StepRatio / $ReferenceRatio)
    return [System.Math]::Round($spread, 9) -le 1.3
}

function Get-CalibrationMeterFailureCount
{
    <#
        The failed launches recorded for one run and spawn (ruling A19). Every
        one counts against the run budget of Invoke-CalibrationMeterLaunch,
        warm-up replicates included; with -MeasuredOnly only those in measured
        replicates count, and any of them makes that run and spawn evidence
        only: it sets no w and decides no verdict.
    #>
    [CmdletBinding()]
    [OutputType([System.Int32])]
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[System.Object]]
        $Failure,

        [Parameter(Mandatory = $true)]
        [System.Int32]
        $Run,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $SpawnHost,

        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $MeasuredOnly
    )

    return @($Failure | Where-Object -FilterScript {
            $_.Run -eq $Run -and $_.Host -eq $SpawnHost -and ($_.Measured -or -not $MeasuredOnly)
        }).Count
}

function Invoke-CalibrationMeterLaunch
{
    <#
        One hook launch of the Meter. Launch returns an object with
        Milliseconds, ExitCode, Output, and Error. A launch that exits
        non-zero measured no hook time, but its exit code and standard error
        are a finding, so each is recorded in Failure, warned about at once,
        and run once more in the same position of the same replicate. Two
        stops end the Meter: a second failure in a row, naming both exit codes
        and the last standard error, and the third failed launch of one run
        and spawn, whether or not two fell together (ruling A19). A record
        carries Measured from the Context, true unless the Context says the
        replicate is a warm-up; a failure in a measured replicate makes its
        run and spawn evidence only (Get-CalibrationMeterFailureCount).
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.ScriptBlock]
        $Launch,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[System.Object]]
        $Failure,

        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]
        $Context
    )

    $measured = if ($Context.Contains('Measured')) { [System.Boolean] $Context.Measured } else { $true }
    $failedAttempts = [System.Collections.Generic.List[System.Object]]::new()
    for ($attempt = 1; $attempt -le 2; $attempt++)
    {
        $result = & $Launch
        if ($result.ExitCode -eq 0)
        {
            return $result
        }

        $errorText = ([string] $result.Error -replace '[\p{Cc}\p{Zl}\p{Zp}]', ' ' -replace '\s+', ' ').Trim()
        if ($errorText.Length -gt 2000)
        {
            $errorText = $errorText.Substring(0, 1997) + '...'
        }

        $record = [pscustomobject] @{
            Run         = $Context.Run
            Host        = $Context.Host
            Cell        = $Context.Cell
            Replicate   = $Context.Replicate
            Attempt     = $attempt
            Measured    = $measured
            ExitCode    = $result.ExitCode
            ExitCodeHex = '0x{0:X8}' -f $result.ExitCode
            Error       = $errorText
        }

        $Failure.Add($record)
        $failedAttempts.Add($record)
        Write-Warning -Message ("Run {0}, {1} '{2}', replicate {3}, attempt {4}: exited {5}. {6}" -f $record.Run, $record.Host, $record.Cell, $record.Replicate, $attempt, $record.ExitCodeHex, $errorText)

        $runFailure = @($Failure | Where-Object -FilterScript { $_.Run -eq $Context.Run -and $_.Host -eq $Context.Host })
        if ($runFailure.Count -ge 3)
        {
            throw ("{0} run {1} reached {2} failed launches, the budget of ruling A19: {3}. Last standard error: {4}" -f $Context.Host, $Context.Run, $runFailure.Count, (($runFailure | ForEach-Object -Process { "'{0}' replicate {1} attempt {2} exited {3}" -f $_.Cell, $_.Replicate, $_.Attempt, $_.ExitCodeHex }) -join '; '), $errorText)
        }
    }

    throw ("{0} '{1}' failed twice in run {2}, replicate {3}, exiting {4}. Last standard error: {5}" -f $Context.Host, $Context.Cell, $Context.Run, $Context.Replicate, (($failedAttempts | ForEach-Object -Process { $_.ExitCodeHex }) -join ' and '), $failedAttempts[-1].Error)
}
