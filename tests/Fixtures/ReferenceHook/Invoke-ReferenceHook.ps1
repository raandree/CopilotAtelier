<#
.SYNOPSIS
    Frozen reference of the calibration latency Meter.
.DESCRIPTION
    The unit of SessionStart.AddedLatency and PostToolUse.CallLatency, Decision
    record 0028, rulings A9 and A17. It reads its payload exactly as the no-op
    hook does and applies the primitives the shipped hooks use on it, then
    dot-sources the frozen copy of the calibration reader beside it and runs one
    fixed calibration on the frozen fixture: the same kind of work as the
    SessionStart calibration step, by construction. Never shipped: the Meter
    stages this folder outside every git working tree and launches this driver
    through the same launcher and spawn as the measured hooks.
.NOTES
    Frozen. tests/CalibrationMeter.Tests.ps1 pins one SHA-256 over every file of
    this folder: changing any of them changes every latency ratio, so re-baseline
    both latency tags in the same commit.

    Writes nothing and emits nothing. Exits 0 only when the fixed calibration
    returns levels and a sentence, and 1 otherwise, so a fixture that stops
    producing levels fails the Meter instead of silently shrinking the unit. Run
    in place inside the repository it exits 1 by design: the reader refuses a
    profile inside a git working tree.
#>
$reader = [IO.StreamReader]::new([Console]::OpenStandardInput(), [Text.UTF8Encoding]::new($false))
try {
    $inputJson = $reader.ReadToEnd()
} finally {
    $reader.Dispose()
}

$payload = $inputJson | ConvertFrom-Json -ErrorAction Stop
$sessionMatch = [regex]::Match($inputJson, '"session_id"\s*:\s*"([^"\\]*)"')
$briefExists = [IO.File]::Exists([IO.Path]::Combine([string]$payload.cwd, '.memory-bank', 'projectbrief.md'))

# An explicit location: the unit never resolves ~/.copilot, never depends on the
# Meter cell's scratch home, and never reads a contributor's real profile.
$fixture = [IO.Path]::Combine($PSScriptRoot, 'fixture')
. ([IO.Path]::Combine($PSScriptRoot, 'ContributorProfileReader.ps1'))
$location = Resolve-ContributorProfileLocation -UserHome $fixture -LocalApplicationData $fixture
$calibration = Get-ContributorCalibration -WorkspacePath ([IO.Path]::Combine($fixture, 'workspace')) -Location $location -SkipGitForSingleEntry -TimeoutMilliseconds 3000
$sentence = Format-ContributorCalibrationSentence -Calibration $calibration

if ($calibration.State -eq 'levels' -and $sentence) {
    exit 0
}

exit 1
