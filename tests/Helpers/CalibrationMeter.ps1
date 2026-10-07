<#
    Arithmetic of the calibration latency Meter, Decision record 0028, rulings
    A9 and A10. Latency counts in frozen reference scripts: every replicate
    runs each cell back to back in rotated order through the same launcher and
    spawn, a cell's time is taken net of the same replicate's no-op hook, and
    the unit is that replicate's frozen reference script net of the same no-op
    hook, so machine speed, shell edition, and load cancel to first order.
    Ratios are taken inside a replicate before any percentile.
    tests/Fixtures/Measure-CalibrationLatency.ps1 measures; tests/CalibrationMeter.Tests.ps1
    proves this file.
#>

function Get-CalibrationMeterBudget
{
    <#
        The latency levels of the gated cells, in frozen reference scripts
        (ruling A9), and the SHA-256 of the reference script they were set
        against. Ruling A10 withdrew the launch-unit levels of rulings A2 and
        A3, and the re-baseline rule sets the new ones from the first Meter run
        under the new unit, so Level stays empty until then. Changing the
        reference script changes every ratio: re-baseline both latency tags in
        the commit that changes ReferenceSha256.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param ()

    @{
        ReferenceSha256 = '269b070a3964a2b51129dade3c63b1e412528928280c52d17421a613a1d4d798'
        Level           = @{}
    }
}

function Get-CalibrationMeterReferenceHash
{
    <#
        SHA-256 of the frozen reference script, taken over its text with LF
        line endings, so the line endings a checkout gives the file do not
        move the pin.
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Path
    )

    $text = [System.IO.File]::ReadAllText($Path).Replace("`r`n", "`n")
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try
    {
        $digest = $sha.ComputeHash([System.Text.UTF8Encoding]::new($false).GetBytes($text))
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
        is named; the unit is that replicate's frozen reference script minus
        its no-op hook (ruling A9).
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
            throw ('The frozen reference script took {0:N0} ms against {1:N0} ms for the no-op hook in one replicate, so the unit cannot be measured.' -f $sample[$Reference], $sample[$NoOp])
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
        the gated cells' lower-run p95 values, in frozen reference scripts;
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
        (TBD-6): ReferenceRatio is the frozen reference script's RAANDREE3 time
        divided by its Prox1 time, StepRatio the same ratio for the measured
        step, per spawn. The unit cancels machine speed only when the two
        differ by at most 1.3 times in either direction.
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
