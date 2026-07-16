<#
.SYNOPSIS
    Starts an encoded PowerShell payload as a fully detached process.
.DESCRIPTION
    Uses Start-Process on Windows. On non-Windows systems, uses nohup through
    sh so the child survives the launching shell. The payload owns its output
    logging; this launcher returns process and result metadata.
.EXAMPLE
    $encodedCommand = [Convert]::ToBase64String(
        [Text.Encoding]::Unicode.GetBytes("'hello'")
    )
    ./Start-DetachedPowerShell.ps1 -EncodedCommand $encodedCommand
#>
[CmdletBinding()]
[OutputType([pscustomobject])]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [ValidatePattern('^[A-Za-z0-9+/]+={0,2}$')]
    [string] $EncodedCommand,

    [ValidateNotNullOrEmpty()]
    [string] $ResultPath = (Join-Path $env:TEMP (
        'detached-{0}.exit' -f [guid]::NewGuid().ToString('N')
    ))
)

$ErrorActionPreference = 'Stop'
if (Test-Path -LiteralPath $ResultPath) {
    throw "ResultPath already exists: $ResultPath"
}

$resultDirectory = Split-Path -Path $ResultPath -Parent
if (-not (Test-Path -LiteralPath $resultDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $resultDirectory -Force | Out-Null
}

$escapedResultPath = $ResultPath.Replace("'", "''")
$innerEncodedCommand = $EncodedCommand
$wrapper = @"
`$ErrorActionPreference = 'Stop'
try {
    `$innerPwsh = (Get-Command -Name pwsh -ErrorAction Stop).Source
    & `$innerPwsh -NoProfile -NonInteractive -EncodedCommand '$innerEncodedCommand'
    `$innerExitCode = `$LASTEXITCODE
    `$resultValue = if (`$innerExitCode -eq 0) { '0' } else { '1' }
    [IO.File]::WriteAllText('$escapedResultPath', `$resultValue)
    exit `$innerExitCode
}
catch {
    [IO.File]::WriteAllText('$escapedResultPath', '1')
    throw
}
"@
$EncodedCommand = [Convert]::ToBase64String(
    [Text.Encoding]::Unicode.GetBytes($wrapper)
)

$pwshPath = (Get-Command -Name pwsh -ErrorAction Stop).Source
$isWindowsPlatform = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT

if ($isWindowsPlatform) {
    $process = Start-Process -FilePath $pwshPath -ArgumentList @(
        '-NoProfile'
        '-NonInteractive'
        '-EncodedCommand'
        $EncodedCommand
    ) -WindowStyle Hidden -PassThru

    [pscustomobject]@{
        ProcessId = $process.Id
        Platform  = 'Windows'
        Detached  = $true
        ResultPath = $ResultPath
    }
    return
}

$nohupPath = (Get-Command -Name nohup -ErrorAction Stop).Source
$shellPath = (Get-Command -Name sh -ErrorAction Stop).Source

function ConvertTo-PosixSingleQuoted
{
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $Value
    )

    $singleQuote = [string][char]39
    $doubleQuote = [string][char]34
    $embeddedSingleQuote = "$singleQuote$doubleQuote$singleQuote$doubleQuote$singleQuote"
    $singleQuote + $Value.Replace($singleQuote, $embeddedSingleQuote) + $singleQuote
}

$quotedNohup = ConvertTo-PosixSingleQuoted -Value $nohupPath
$quotedPwsh = ConvertTo-PosixSingleQuoted -Value $pwshPath
$shellCommand = @(
    $quotedNohup
    $quotedPwsh
    '-NoProfile'
    '-NonInteractive'
    '-EncodedCommand'
    $EncodedCommand
    '</dev/null'
    '>/dev/null'
    '2>&1'
    '&'
    'echo $!'
) -join ' '

$processIdText = (& $shellPath -c $shellCommand | Select-Object -Last 1).Trim()
if ($LASTEXITCODE -ne 0 -or $processIdText -notmatch '^\d+$') {
    throw "Failed to start detached PowerShell through nohup. Output: '$processIdText'."
}

[pscustomobject]@{
    ProcessId = [int]$processIdText
    Platform  = 'Unix'
    Detached  = $true
    ResultPath = $ResultPath
}
