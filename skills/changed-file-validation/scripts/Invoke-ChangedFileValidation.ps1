#Requires -Version 5.1

<#
    .SYNOPSIS
        Validates the files collected in one changed-file batch.

    .DESCRIPTION
        The explicit entry point for changed-file validation. It runs the
        repository's own checks over each collected file that is supported,
        present, and not already covered by a receipt for exactly the bytes on
        disk, then records what was checked.

        A receipt names the validator, its version, its configuration identity,
        the SHA-256 of the content that was actually read, the outcome, the exit
        status, and the diagnostic locations. The file is hashed again once the
        validators finish: a receipt is always bound to the bytes it covered, so
        an edit made during or after validation leaves the entry Stale instead
        of inheriting the old result.

        Missing tools, refused input, and time-bound violations are recorded as
        unavailable, timed-out, or failed checks. None of them ever produces a
        verified entry.

    .PARAMETER Path
        The selected project root.

    .PARAMETER SessionId
        The batch to validate.

    .PARAMETER Force
        Revalidate entries whose receipt already covers the current content.

    .PARAMETER TimeoutSecond
        The wall-clock bound for a single validator child process. Parsing and
        static analysis run in an owned worker, so the bound covers them too.

    .PARAMETER ExecutionWaitSecond
        How long to wait for the session execution lock before giving up. One
        validation run per session executes at a time.

    .PARAMETER MaxFileKilobyte
        The input-size bound. A larger file is recorded as unavailable and is
        never read or hashed.

    .PARAMETER MaxFileCount
        The bound on how many files one run validates.

    .PARAMETER FailOnSeverity
        The lowest PSScriptAnalyzer severity that fails a check. Findings below
        it are still recorded as diagnostics. It is part of the validation plan
        identity, so changing it invalidates an earlier receipt.

    .PARAMETER MarkdownLintPath
        A markdownlint executable. Without one the Markdown.Lint check is
        recorded as unavailable and the markdown entry stays unverified: the
        native structure check covers four rules and is not markdownlint.

    .PARAMETER MarkdownLintInterface
        The command-line interface the executable is expected to implement. Only
        an interface this implementation has verified is used; any other value
        makes the check unavailable rather than guessed at.

    .OUTPUTS
        PSCustomObject

    .EXAMPLE
        ./Invoke-ChangedFileValidation.ps1 -Path $PWD.Path |
            Format-Table RelativePath, Action, ValidationState

        Validates the default batch and reports what each entry now stands at.
#>
[CmdletBinding()]
[OutputType([PSCustomObject])]
param
(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Path,

    [Parameter()]
    [AllowEmptyString()]
    [string]$SessionId = 'default',

    [Parameter()]
    [switch]$Force,

    [Parameter()]
    [ValidateRange(1, 600)]
    [int]$TimeoutSecond = 60,

    [Parameter()]
    [ValidateRange(0, 600)]
    [int]$ExecutionWaitSecond = 30,

    [Parameter()]
    [ValidateRange(1, 102400)]
    [int]$MaxFileKilobyte = 2048,

    [Parameter()]
    [ValidateRange(1, 500)]
    [int]$MaxFileCount = 200,

    [Parameter()]
    [ValidateSet('Error', 'Warning')]
    [string]$FailOnSeverity = 'Error',

    [Parameter()]
    [AllowEmptyString()]
    [string]$MarkdownLintPath = '',

    [Parameter()]
    [ValidateSet('markdownlint-cli', 'markdownlint-cli2')]
    [string]$MarkdownLintInterface = 'markdownlint-cli'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'ChangedFileValidationCommon.ps1')

$context = Resolve-ChangedFileContext -Path $Path
$session = Assert-ChangedFileSessionId -SessionId $SessionId

$store = Read-ChangedFileStore -Context $context
if ($null -eq $store)
{
    return
}

$collected = @(Get-ChangedFileSessionEntry -Store $store -SessionId $session)
if ($collected.Count -eq 0)
{
    return
}

if ($collected.Count -gt $MaxFileCount)
{
    throw "Session '$session' holds $($collected.Count) changed files, which is more than the requested bound of $MaxFileCount. Raise MaxFileCount deliberately or clear the batch."
}

$maxByte = [long]$MaxFileKilobyte * 1024
$result = [Collections.Generic.List[PSCustomObject]]::new()
$writtenReceipt = @{}

$reportArgument = @{
    Context = $context
    SessionId = $session
    FailOnSeverity = $FailOnSeverity
    MarkdownLintPath = $MarkdownLintPath
    MarkdownLintInterface = $MarkdownLintInterface
}

# One validation run per session. Two runs over one batch would start two sets
# of children and race on the same receipts.
$executionLock = Enter-ChangedFileExecutionLock `
    -Context $context `
    -SessionId $session `
    -TimeoutMillisecond ($ExecutionWaitSecond * 1000)

try
{
    foreach ($entry in $collected)
    {
        $relativePath = [string]$entry['path']

        # The guard runs again immediately before the read: the batch may have
        # been collected minutes ago, and a link could have appeared since.
        $fullPath = Assert-ChangedFileRegularPath `
            -LiteralPath (Join-Path $context.RepositoryRoot ($relativePath -replace '/', [IO.Path]::DirectorySeparatorChar)) `
            -RepositoryRoot $context.RepositoryRoot `
            -Field 'A collected changed path'

        $plan = Resolve-ChangedFileValidationPlan `
            -Context $context `
            -RelativePath $relativePath `
            -FailOnSeverity $FailOnSeverity `
            -MarkdownLintPath $MarkdownLintPath `
            -MarkdownLintInterface $MarkdownLintInterface

        $validatorName = @($plan.Validator)
        $item = Get-Item -LiteralPath $fullPath -Force -ErrorAction SilentlyContinue

        if ($validatorName.Count -eq 0 -or $null -eq $item -or $item.PSIsContainer)
        {
            $result.Add((
                Get-ChangedFileEntryReport @reportArgument -Entry $entry -Action 'Skipped' -Plan $plan
            ))
            continue
        }

        # The size bound comes before every content read: an oversized input is
        # refused without hashing it and without writing a receipt about it.
        if ($item.Length -gt $maxByte)
        {
            $oversized = @(
                foreach ($planned in $plan.Check)
                {
                    New-ChangedFilePlannedCheck -Plan $planned -Outcome 'Unavailable' -Reason 'InputTooLarge'
                }
            )

            $result.Add((
                Get-ChangedFileEntryReport @reportArgument -Entry $entry -Action 'Skipped' -Plan $plan `
                    -TransientCheck $oversized -TransientState 'Incomplete' -TransientReason 'InputTooLarge'
            ))
            continue
        }

        $contentHash = Get-ChangedFileContentHash -LiteralPath $fullPath
        $receipt = if ($entry.ContainsKey('receipt')) { $entry['receipt'] } else { $null }
        $verdict = Test-ChangedFileReceipt -Receipt $receipt -Plan $plan -CurrentSha256 $contentHash

        if (-not $Force.IsPresent -and $verdict.IsCurrent)
        {
            $result.Add((
                Get-ChangedFileEntryReport @reportArgument -Entry $entry -Action 'Reused' -Plan $plan
            ))
            continue
        }

        $stopwatch = [Diagnostics.Stopwatch]::StartNew()
        $check = [Collections.Generic.List[hashtable]]::new()

        $configPath = if ($null -ne $plan.MarkdownConfig) { $plan.MarkdownConfig.FullPath } else { '' }
        $snapshot = New-ChangedFileSnapshot -Context $context -FullPath $fullPath -ConfigPath $configPath

        try
        {
            if ($validatorName -contains 'PowerShell.Parse')
            {
                foreach ($produced in (
                        Invoke-ChangedFilePowerShellCheck `
                            -WorkingDirectory $snapshot.Directory `
                            -FileName $snapshot.FileName `
                            -FailOnSeverity $FailOnSeverity `
                            -TimeoutSecond $TimeoutSecond
                    ))
                {
                    $check.Add($produced)
                }
            }

            if ($validatorName -contains 'Markdown.NativeStructure')
            {
                $check.Add((
                    Invoke-ChangedFileMarkdownStructure `
                        -Plan (
                            $plan.Check |
                                Where-Object -FilterScript { $_['Validator'] -eq 'Markdown.NativeStructure' } |
                                Select-Object -First 1
                        ) `
                        -FullPath $snapshot.FullPath
                ))
            }

            if ($validatorName -contains 'Markdown.Lint')
            {
                $check.Add((
                    Invoke-ChangedFileMarkdownLint `
                        -Plan (
                            $plan.Check |
                                Where-Object -FilterScript { $_['Validator'] -eq 'Markdown.Lint' } |
                                Select-Object -First 1
                        ) `
                        -Context $context `
                        -Snapshot $snapshot `
                        -SourceFullPath $fullPath `
                        -MarkdownLintPath $MarkdownLintPath `
                        -MarkdownLintInterface $MarkdownLintInterface `
                        -MarkdownConfig $plan.MarkdownConfig `
                        -TimeoutSecond $TimeoutSecond
                ))
            }
        }
        finally
        {
            Remove-ChangedFileSnapshot -Directory $snapshot.Directory
        }

        $stopwatch.Stop()

        # Hash the file again. The receipt covers the snapshot the validators
        # read, so content that moved underneath the run leaves it stale.
        $afterHash = if (Test-Path -LiteralPath $fullPath -PathType Leaf)
        {
            Get-ChangedFileContentHash -LiteralPath $fullPath
        }
        else
        {
            $null
        }

        $newReceipt = @{
            contentSha256 = $snapshot.Sha256
            contentByte = $snapshot.Byte
            planIdentity = $plan.PlanIdentity
            completedUtc = [datetime]::UtcNow.ToString('o')
            durationMillisecond = [int]$stopwatch.Elapsed.TotalMilliseconds
            outcome = Get-ChangedFileWorstOutcome -Outcome @($check | ForEach-Object { [string]$_['outcome'] })
            contentChangedDuringValidation = $afterHash -ne $snapshot.Sha256
            checks = $check.ToArray()
        }

        $entry['receipt'] = $newReceipt
        $writtenReceipt[$relativePath] = $newReceipt

        $result.Add((
            Get-ChangedFileEntryReport @reportArgument -Entry $entry -Action 'Validated' -Plan $plan
        ))
    }

    if ($writtenReceipt.Count -gt 0)
    {
        $lock = Enter-ChangedFileLock -Context $context

        try
        {
            # Re-read under the lock and merge onto whatever the batch looks like
            # now, so a receipt is never written onto a file another session or a
            # concurrent clear has already removed from the batch.
            $current = Read-ChangedFileStore -Context $context
            if ($null -ne $current)
            {
                $entries = @(Get-ChangedFileSessionEntry -Store $current -SessionId $session)

                foreach ($entry in $entries)
                {
                    $relativePath = [string]$entry['path']
                    if ($writtenReceipt.ContainsKey($relativePath))
                    {
                        $entry['receipt'] = $writtenReceipt[$relativePath]
                    }
                }

                if ($entries.Count -gt 0)
                {
                    $current['sessions'][$session]['entries'] = $entries
                    $current['sessions'][$session]['updatedUtc'] = [datetime]::UtcNow.ToString('o')
                    Write-ChangedFileStore -Context $context -Store $current
                }
            }
        }
        finally
        {
            Exit-ChangedFileLock -Handle $lock
        }
    }
}
finally
{
    Exit-ChangedFileLock -Handle $executionLock
}

$result
