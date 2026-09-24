#requires -Version 7.0
<#
.SYNOPSIS
    Minimal offline eval harness: grades pre-generated agent/skill/prompt outputs
    and reports observed pass@k (best-of-k) and pass^k (all-of-k) per case.

.DESCRIPTION
    Reads an eval file (JSON) and a directory of sampled outputs — one subfolder
    per case id, each holding sample-1.txt through sample-K.txt — then grades every sample
    deterministically against the case's expected value and reports pass@k and
    pass^k per case. Capability cases are gated on pass@k; regression cases on
    pass^k. Both gates require exactly the K named samples and valid case definitions.

    Generate the samples first by running the agent/skill/prompt k times on each
    case prompt and saving each run to <OutputsDir>/<case-id>/sample-<n>.txt.
    This harness only grades; it does not call the model, because Copilot has no
    stable non-interactive PowerShell entry point.

.PARAMETER EvalFile
    Path to the eval JSON. Schema:
    { "cases": [ { "id", "set", "prompt", "expect", "match" } ] }
    where set is 'capability' or 'regression' and match is 'exact' | 'contains' | 'regex'.

.PARAMETER OutputsDir
    Directory holding one subfolder per case id, each with k sample-*.txt files.

.PARAMETER K
    Expected samples per case. Missing, additional, or misnumbered sample files
    fail either gate. pass^k additionally requires all K samples to pass.

.EXAMPLE
    ./run-evals.ps1 -EvalFile evals.json -OutputsDir out -K 5
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string] $EvalFile,

    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
    [string] $OutputsDir,

    # Default 5: enough samples to expose non-determinism without heavy cost.
    [ValidateRange(1, 100)]
    [int] $K = 5
)

$ErrorActionPreference = 'Stop'

function Test-EvalMatch {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [AllowNull()]
        [string] $Output = '',

        [Parameter(Mandatory)]
        [string] $Expect,

        [ValidateSet('exact', 'contains', 'regex')]
        [string] $Match = 'contains'
    )

    switch ($Match) {
        'exact'    { return $Output.Trim() -eq $Expect.Trim() }
        'contains' { return $Output.IndexOf($Expect, [StringComparison]::OrdinalIgnoreCase) -ge 0 }
        'regex'    {
            # Bound backtracking so one sampled reply cannot stall the entire gate.
            return [regex]::IsMatch($Output, $Expect, [Text.RegularExpressions.RegexOptions]::IgnoreCase,
                [TimeSpan]::FromSeconds(1))
        }
    }
}

try {
    $eval = Get-Content -LiteralPath $EvalFile -Raw -Encoding utf8 | ConvertFrom-Json -NoEnumerate
}
catch {
    throw "Failed to parse eval file '$EvalFile': $($_.Exception.Message)"
}

if ($eval -isnot [pscustomobject] -or $eval.cases -isnot [array] -or $eval.cases.Count -eq 0) {
    throw "Eval file '$EvalFile' must contain a nonempty 'cases' array."
}

$ids = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($case in $eval.cases) {
    if ($case -isnot [pscustomobject]) { throw 'Each eval case must be an object.' }
    if ($case.id -isnot [string] -or $case.id -cnotmatch '\A[A-Za-z0-9][A-Za-z0-9_-]{0,127}\z') {
        throw 'Each case id must be a path-safe identifier (1-128 letters, digits, underscores or hyphens).'
    }
    if (-not $ids.Add($case.id)) { throw "Duplicate case id '$($case.id)'." }
    if ($case.set -isnot [string] -or $case.set -cnotin 'capability', 'regression') {
        throw "Case '$($case.id)' has an invalid set; use capability or regression."
    }
    if ($case.prompt -isnot [string] -or [string]::IsNullOrWhiteSpace($case.prompt)) {
        throw "Case '$($case.id)' must have a nonempty prompt string."
    }
    if ($case.expect -isnot [string] -or [string]::IsNullOrEmpty($case.expect)) {
        throw "Case '$($case.id)' must have a nonempty expect string."
    }
    if ($case.PSObject.Properties.Name -contains 'match') {
        if ($case.match -isnot [string] -or $case.match -cnotin 'exact', 'contains', 'regex') {
            throw "Case '$($case.id)' has an invalid match; use exact, contains or regex."
        }
    }
    if ($case.match -eq 'regex') {
        try {
            $null = [regex]::new($case.expect, [Text.RegularExpressions.RegexOptions]::IgnoreCase,
                [TimeSpan]::FromSeconds(1))
        }
        catch {
            throw "Case '$($case.id)' has an invalid regex: $($_.Exception.Message)"
        }
    }
}

$expectedNames = @(1..$K | ForEach-Object { "sample-$_.txt" })
$rows = @(foreach ($case in $eval.cases) {
    $caseDir = Join-Path -Path $OutputsDir -ChildPath $case.id
    $matchMode = if ($case.match) { $case.match } else { 'contains' }

    if (Test-Path -LiteralPath $caseDir -PathType Container) {
        $samples = @(Get-ChildItem -LiteralPath $caseDir -Filter 'sample-*.txt' -File -Force)
    }
    else {
        Write-Warning "No outputs for case '$($case.id)' (expected '$caseDir')."
        $samples = @()
    }

    $missing = @($expectedNames | Where-Object { $_ -cnotin $samples.Name })
    $unexpected = @($samples.Name | Where-Object { $_ -cnotin $expectedNames })
    if ($missing.Count -gt 0) {
        Write-Warning "Case '$($case.id)' missing samples: $($missing -join ', ')."
    }
    if ($unexpected.Count -gt 0) {
        Write-Warning "Case '$($case.id)' unexpected samples: $($unexpected -join ', ')."
    }
    $complete = $missing.Count -eq 0 -and $unexpected.Count -eq 0
    $passes = @(
        $samples | Where-Object { $_.Name -cin $expectedNames } | Where-Object {
            $text = [string](Get-Content -LiteralPath $_.FullName -Raw -Encoding utf8)
            Test-EvalMatch -Output $text -Expect $case.expect -Match $matchMode
        }
    ).Count

    [pscustomobject]@{
        Id       = $case.id
        Set      = $case.set
        Samples  = $samples.Count
        Complete = $complete
        Passes   = $passes
        'Pass@k' = ($complete -and $passes -ge 1)
        'Pass^k' = ($complete -and $passes -eq $K)
    }
})

$rows | Format-Table -AutoSize

# Gate: capability sets require pass@k; regression sets require pass^k.
$failed = @(
    $rows | Where-Object {
        ($_.Set -eq 'capability' -and -not $_.'Pass@k') -or
        ($_.Set -eq 'regression' -and -not $_.'Pass^k')
    }
)

if ($failed.Count -gt 0) {
    Write-Host "FAIL: $($failed.Count) eval case(s) failed the gate: $($failed.Id -join ', ')" -ForegroundColor Red
    exit 1
}

Write-Host 'PASS: all eval cases met their gate.' -ForegroundColor Green
exit 0
