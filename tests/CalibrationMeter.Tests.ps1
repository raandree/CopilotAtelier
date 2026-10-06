<#
    Arithmetic of the calibration latency Meter (Decision record 0028,
    rulings A1 to A3): rotated cell order, ratios taken per replicate against
    a no-op hook launch, nearest-rank percentiles, inclusive thresholds, the
    signed-off Budget and Fail levels, and the rule that a verdict above
    Budget or Fail counts only when a second Meter run reproduces it. The
    measurement itself runs only by hand: tests/Fixtures/Measure-CalibrationLatency.ps1.
#>

BeforeAll {
    . (Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'tests/Helpers/CalibrationMeter.ps1')
}

Describe 'Calibration Meter arithmetic' -Tag 'Unit' {
    It 'rotates the cell order by one place per replicate, so every cell takes every position' {
        $cells = 'noop', 'baseline', 'one', 'none', 'two', 'post', 'guard'

        $orders = foreach ($replicate in 0..6) { , (Get-CalibrationMeterOrder -Cell $cells -Replicate $replicate) }

        $orders[0] | Should -Be $cells
        $orders[1] | Should -Be @('baseline', 'one', 'none', 'two', 'post', 'guard', 'noop')
        Get-CalibrationMeterOrder -Cell $cells -Replicate 7 | Should -Be $cells
        foreach ($position in 0..6)
        {
            @($orders | ForEach-Object -Process { $_[$position] } | Sort-Object -Unique).Count | Should -Be 7
        }
    }

    It 'takes the ratio inside each replicate, before any percentile' {
        $replicates = @(
            @{ noop = 800.0; baseline = 800.0; one = 1200.0 }
            @{ noop = 1600.0; baseline = 1600.0; one = 1700.0 }
        )

        $added = @(Get-CalibrationMeterRatio -Replicate $replicates -Subject 'one' -Baseline 'baseline')
        $alone = @(Get-CalibrationMeterRatio -Replicate $replicates -Subject 'one')

        $added | Should -Be @(0.5, 0.0625)
        $alone | Should -Be @(1.5, 1.0625)
    }

    It 'reads the nearest rank, so p95 of 20 replicates is the 19th smallest value and p50 the 10th' {
        $values = [double[]] (20..1)

        Get-CalibrationMeterRank -Value $values -Percent 95 | Should -Be 19
        Get-CalibrationMeterRank -Value $values -Percent 50 | Should -Be 10
        Get-CalibrationMeterRank -Value @(7.0) -Percent 95 | Should -Be 7
    }

    It 'meets a value at or below Budget and fails only a value above Fail' -ForEach @(
        @{ Value = 0.5; Expected = 'within budget' }
        @{ Value = 0.51; Expected = 'over budget' }
        @{ Value = 1.0; Expected = 'over budget' }
        @{ Value = 1.01; Expected = 'fail' }
    ) {
        Get-CalibrationMeterVerdict -Value $Value -Budget 0.5 -Fail 1.0 | Should -BeExactly $Expected
    }

    It 'counts a verdict above Budget or Fail only when another run reproduces it' -ForEach @(
        @{ Verdict = @('fail', 'fail'); Expected = 'fail' }
        @{ Verdict = @('fail', 'over budget'); Expected = 'over budget' }
        @{ Verdict = @('over budget', 'within budget'); Expected = 'within budget' }
        @{ Verdict = @('within budget', 'within budget'); Expected = 'within budget' }
        @{ Verdict = @('fail'); Expected = 'fail (unconfirmed)' }
        @{ Verdict = @('within budget'); Expected = 'within budget' }
    ) {
        Merge-CalibrationMeterVerdict -Verdict $Verdict | Should -BeExactly $Expected
    }

    It 'gates the signed-off cells at the levels of rulings A2 and A3, in no-op hook launches' {
        $budget = Get-CalibrationMeterBudget

        @($budget.Keys | Sort-Object) | Should -Be @('PostToolUse, nothing pending', 'SessionStart, no profile', 'SessionStart, one entry')
        $budget['SessionStart, one entry'].Budget | Should -Be 0.5
        $budget['SessionStart, one entry'].Fail | Should -Be 1.0
        $budget['SessionStart, no profile'].Budget | Should -Be 0.5
        $budget['SessionStart, no profile'].Fail | Should -Be 1.0
        $budget['PostToolUse, nothing pending'].Budget | Should -Be 1.1
        $budget['PostToolUse, nothing pending'].Fail | Should -Be 1.25
    }
}
