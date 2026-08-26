#requires -Version 7.0
<#
.SYNOPSIS
    Minimal offline eval harness: grades pre-generated agent/skill/prompt outputs
    and reports pass@k (best-of-k) and pass^k (all-of-k) per case and per set.

.DESCRIPTION
    Reads an eval file (JSON) and a directory of sampled outputs — one subfolder
    per case id, each holding k `sample-*.txt` files — then grades every sample
    deterministically against the case's expected value and reports pass@k and
    pass^k. Capability cases are gated on pass@k; regression cases on pass^k.

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
    Expected samples per case. pass^k requires all K samples to pass; cases with
    fewer than K samples cannot satisfy the regression gate.

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
        'contains' { return $Output -like "*$Expect*" }
        'regex'    { return $Output -match $Expect }
    }
}

try {
    $eval = Get-Content -LiteralPath $EvalFile -Raw -Encoding utf8 | ConvertFrom-Json
}
catch {
    throw "Failed to parse eval file '$EvalFile': $($_.Exception.Message)"
}

if (-not $eval.cases) {
    throw "Eval file '$EvalFile' has no 'cases' array."
}

$rows = foreach ($case in $eval.cases) {
    $caseDir = Join-Path -Path $OutputsDir -ChildPath $case.id
    $matchMode = if ($case.match) { $case.match } else { 'contains' }

    if (Test-Path -LiteralPath $caseDir -PathType Container) {
        $samples = @(Get-ChildItem -LiteralPath $caseDir -Filter 'sample-*.txt' -File)
    }
    else {
        Write-Warning "No outputs for case '$($case.id)' (expected '$caseDir')."
        $samples = @()
    }

    $passes = @(
        $samples | Where-Object {
            $text = [string](Get-Content -LiteralPath $_.FullName -Raw -Encoding utf8)
            Test-EvalMatch -Output $text -Expect $case.expect -Match $matchMode
        }
    ).Count

    $n = $samples.Count

    [pscustomobject]@{
        Id       = $case.id
        Set      = $case.set
        Samples  = $n
        Passes   = $passes
        'Pass@k' = ($n -gt 0 -and $passes -ge 1)
        'Pass^k' = ($n -ge $K -and $passes -eq $n)
    }
}

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
