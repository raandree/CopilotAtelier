<#
    Arithmetic of the calibration latency Meter, Decision record 0028, rulings
    A1 to A3. Latency counts in launches of a fixed no-op hook through the same
    launcher and spawn: every replicate runs each cell back to back in rotated
    order, and ratios are taken inside a replicate before any percentile.
    tests/Fixtures/Measure-CalibrationLatency.ps1 measures; tests/CalibrationMeter.Tests.ps1
    proves this file.
#>

function Get-CalibrationMeterBudget
{
    <#
        Budget and Fail of every gated cell, in no-op hook launches: rulings A2
        (SessionStart.AddedLatency) and A3 (PostToolUse.CallLatency). The
        two-entry cell and the push guard are reported, not gated.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param ()

    @{
        'SessionStart, one entry'      = @{ Budget = 0.5; Fail = 1.0 }
        'SessionStart, no profile'     = @{ Budget = 0.5; Fail = 1.0 }
        'PostToolUse, nothing pending' = @{ Budget = 1.1; Fail = 1.25 }
    }
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
        the added time: the subject's milliseconds, minus the baseline's in the
        same replicate when one is named, divided by that replicate's no-op
        hook launch.
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
        $Baseline,

        [Parameter()]
        [System.String]
        $Unit = 'noop'
    )

    foreach ($sample in $Replicate)
    {
        $time = [System.Double] $sample[$Subject]
        if (-not [System.String]::IsNullOrEmpty($Baseline))
        {
            $time -= [System.Double] $sample[$Baseline]
        }

        $time / [System.Double] $sample[$Unit]
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
