<#
.SYNOPSIS
    Renders a Markdown cover sheet to PDF via pandoc and headless Microsoft Edge.

.DESCRIPTION
    Edge silently produces no file while still returning exit code 0 unless it is
    started with --headless=new, a private --user-data-dir, and waited for as a
    process. This wrapper enforces all three and throws when the output is absent.

.EXAMPLE
    .\Build-EvidencePackage.ps1 -MarkdownPath .\cover.md -CssPath .\pdf-print.css -OutputPath .\cover.pdf
#>
[CmdletBinding()]
param
(
    [Parameter(Mandatory = $true)]
    [string]
    $MarkdownPath,

    [Parameter()]
    [string]
    $CssPath,

    [Parameter(Mandatory = $true)]
    [string]
    $OutputPath,

    [Parameter()]
    [string]
    $PageTitle = 'Anlage',

    [Parameter()]
    [string]
    $EdgePath = 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command pandoc -ErrorAction SilentlyContinue))
{
    throw 'pandoc not found on PATH.'
}

if (-not (Test-Path -LiteralPath $EdgePath))
{
    throw "Microsoft Edge not found at '$EdgePath'."
}

$htmlPath = Join-Path $env:TEMP ('cover-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.html')

$pandocArgs = @($MarkdownPath, '-s', '--embed-resources', '--metadata', "pagetitle=$PageTitle", '-o', $htmlPath)
if ($CssPath)
{
    $pandocArgs += @('--css', $CssPath)
}

# Pandoc resolves a relative --css against its working directory, so run it next to the Markdown.
Push-Location (Split-Path -Parent (Resolve-Path -LiteralPath $MarkdownPath))
try
{
    pandoc @pandocArgs
}
finally
{
    Pop-Location
}

if (Test-Path -LiteralPath $OutputPath)
{
    Remove-Item -LiteralPath $OutputPath -Force
}

$profileDir = Join-Path $env:TEMP ('edgepdf-' + [guid]::NewGuid().ToString('N').Substring(0, 8))

$edgeArgs = @(
    '--headless=new'
    '--disable-gpu'
    '--no-first-run'
    '--no-default-browser-check'
    "--user-data-dir=$profileDir"
    '--virtual-time-budget=10000'
    '--no-pdf-header-footer'
    "--print-to-pdf=$OutputPath"
    ('file:///' + ($htmlPath -replace '\\', '/'))
)

$process = Start-Process -FilePath $EdgePath -ArgumentList $edgeArgs -PassThru -Wait -WindowStyle Hidden

Remove-Item -LiteralPath $profileDir -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $htmlPath -Force -ErrorAction SilentlyContinue

if (-not (Test-Path -LiteralPath $OutputPath))
{
    throw "Edge exited with code $($process.ExitCode) but wrote no PDF to '$OutputPath'."
}

Get-Item -LiteralPath $OutputPath
