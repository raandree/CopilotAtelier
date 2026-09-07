#Requires -Version 5.1

<#
    .SYNOPSIS
        Runs the PowerShell checks for one snapshot inside an owned child process.

    .DESCRIPTION
        Not a user entry point. Invoke-ChangedFilePowerShellCheck starts this
        script in a separate process so that parsing and static analysis carry a
        wall-clock bound and can be stopped, and reads the single JSON document
        it writes to standard output.

        The request arrives on standard input rather than on a command line, and
        the file to check is named relative to the working directory the parent
        set, so no project text is ever composed into an argument.

        The file is read, never run: nothing here dot-sources, imports, or
        invokes the snapshot, and PSScriptAnalyzer is given an inline settings
        hashtable so it neither discovers a project settings file nor loads a
        custom rule module.

    .OUTPUTS
        System.String
#>
[CmdletBinding()]
param ()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Write-WorkerReport
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable]$Report
    )

    [Console]::Out.Write(($Report | ConvertTo-Json -Depth 8 -Compress))
    [Console]::Out.Flush()
}

function New-WorkerDiagnostic
{
    [CmdletBinding()]
    [OutputType([hashtable])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'Builds an in-memory diagnostic record and changes nothing.'
    )]
    param
    (
        [Parameter()]
        [int]$Line = 0,

        [Parameter()]
        [int]$Column = 0,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Severity,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$RuleId,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Message
    )

    return @{
        line = $Line
        column = $Column
        severity = $Severity
        ruleId = $RuleId
        message = $Message
    }
}

$request = [Console]::In.ReadToEnd() | ConvertFrom-Json
$fileName = [string]$request.fileName
$failOnSeverity = [string]$request.failOnSeverity
$maxDiagnostic = [int]$request.maxDiagnostic

$fullPath = [IO.Path]::Combine((Get-Location).ProviderPath, $fileName)

$parseError = $null
$null = [Management.Automation.Language.Parser]::ParseFile($fullPath, [ref] $null, [ref] $parseError)
$found = @($parseError)

$parse = @{
    errorCount = $found.Count
    diagnostics = @(
        foreach ($item in ($found | Select-Object -First $maxDiagnostic))
        {
            New-WorkerDiagnostic `
                -Line $item.Extent.StartLineNumber `
                -Column $item.Extent.StartColumnNumber `
                -Severity 'Error' `
                -RuleId ([string]$item.ErrorId) `
                -Message ([string]$item.Message)
        }
    )
}

$module = Get-Module -Name PSScriptAnalyzer -ListAvailable -ErrorAction SilentlyContinue |
    Sort-Object -Property Version -Descending |
    Select-Object -First 1

$analyzer = if ($null -eq $module)
{
    @{ available = $false; reason = 'ModuleNotAvailable'; version = ''; failingCount = 0; diagnostics = @() }
}
else
{
    try
    {
        Import-Module -Name PSScriptAnalyzer -RequiredVersion $module.Version -ErrorAction Stop

        # -Path accepts wildcards, so even a generated literal name is escaped.
        # -Settings takes an inline hashtable, which is what stops the analyzer
        # discovering a PSScriptAnalyzerSettings.psd1 anywhere near the input.
        $finding = @(
            Invoke-ScriptAnalyzer `
                -Path ([Management.Automation.WildcardPattern]::Escape($fullPath)) `
                -Settings @{ Severity = @('Error', 'Warning') } `
                -ErrorAction Stop
        )

        $failing = @(
            $finding | Where-Object -FilterScript {
                [string]$_.Severity -eq 'Error' -or
                ($failOnSeverity -eq 'Warning' -and [string]$_.Severity -eq 'Warning')
            }
        )

        @{
            available = $true
            reason = ''
            version = $module.Version.ToString()
            failingCount = $failing.Count
            diagnostics = @(
                foreach ($item in ($finding | Select-Object -First $maxDiagnostic))
                {
                    New-WorkerDiagnostic `
                        -Line ([int]$item.Line) `
                        -Column ([int]$item.Column) `
                        -Severity ([string]$item.Severity) `
                        -RuleId ([string]$item.RuleName) `
                        -Message ([string]$item.Message)
                }
            )
        }
    }
    catch
    {
        @{
            available = $false
            reason = 'InvocationFailed'
            version = $module.Version.ToString()
            failingCount = 0
            diagnostics = @()
        }
    }
}

Write-WorkerReport -Report @{ parse = $parse; analyzer = $analyzer }
exit 0
