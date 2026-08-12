#requires -Version 5.1
using namespace System.Management.Automation.Language

<#
    .SYNOPSIS
        Reports Pester v4 constructs that change behaviour under the Pester 5
        two-phase engine.

    .DESCRIPTION
        Scans Pester test files and emits one object per construct that either
        fails outright under Pester 5 or, worse, still passes while testing
        something other than what it claims.

        The scan is a report, not a gate. Several findings are legal Pester 5 -
        discovery-time code feeding -ForEach is the obvious one - so a human
        adjudicates each finding rather than the script rewriting it.

        Detected constructs:

          LegacyShould          Should Be x, Should Throw x (no dash)
          LegacyMockAssertion   Assert-MockCalled, Assert-VerifiableMock(s)
          InModuleScopeWrapper  Describe/Context/It wrapped in InModuleScope
          LegacyPathDiscovery   $MyInvocation.MyCommand.Path/Definition
          TopLevelCommand       a command running at file top level
          BlockBodyCommand      a command in a Describe/Context body
          DeprecatedParameter   Invoke-Pester -Script/-TestName/-Show/...
          ParseError            the file does not parse at all

    .PARAMETER Path
        File or directory to scan. Directories are searched recursively.
        Defaults to the current location.

    .PARAMETER Filter
        Wildcard applied when Path is a directory. Defaults to *.Tests.ps1.

    .EXAMPLE
        ./Find-PesterV4Pattern.ps1 -Path ./tests

        Lists every v4 construct under ./tests.

    .EXAMPLE
        ./Find-PesterV4Pattern.ps1 -Path ./tests |
            Group-Object -Property Construct |
            Sort-Object -Property Count -Descending

        Sizes the migration before starting it.

    .OUTPUTS
        PSCustomObject with Path, Line, Column, Construct, Detail, Guidance.
#>
[CmdletBinding()]
[OutputType([pscustomobject])]
param
(
    [Parameter(Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string]$Path = '.',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$Filter = '*.Tests.ps1'
)

$ErrorActionPreference = 'Stop'

# Legal directly inside a Describe or Context body under Pester 5.
$script:blockCommand = @(
    'Describe'
    'Context'
    'It'
    'BeforeAll'
    'AfterAll'
    'BeforeEach'
    'AfterEach'
    'BeforeDiscovery'
)

# Legal at file top level. It and the *Each blocks are not: they have no
# containing block to attach to.
$script:topLevelCommand = @(
    'Describe'
    'BeforeAll'
    'AfterAll'
    'BeforeDiscovery'
)

function New-Finding
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param
    (
        [Parameter(Mandatory)]
        [string]$FilePath,

        [Parameter(Mandatory)]
        [AllowNull()]
        [IScriptExtent]$Extent,

        [Parameter(Mandatory)]
        [string]$Construct,

        [Parameter(Mandatory)]
        [string]$Detail,

        [Parameter(Mandatory)]
        [string]$Guidance
    )

    [pscustomobject]@{
        Path      = $FilePath
        Line      = if ($Extent) { $Extent.StartLineNumber } else { 0 }
        Column    = if ($Extent) { $Extent.StartColumnNumber } else { 0 }
        Construct = $Construct
        Detail    = $Detail
        Guidance  = $Guidance
    }
}

<#
    Returns the CommandAst a statement invokes, or $null when the statement is
    not a single bare command. A command call arrives as a PipelineAst wrapping
    one CommandAst, so testing the statement itself never matches.
#>
function Resolve-StatementCommand
{
    [CmdletBinding()]
    [OutputType([CommandAst])]
    param
    (
        [Parameter(Mandatory)]
        [StatementAst]$Statement
    )

    if ($Statement -is [CommandAst])
    {
        return $Statement
    }

    if ($Statement -is [PipelineAst] -and
        $Statement.PipelineElements.Count -eq 1 -and
        $Statement.PipelineElements[0] -is [CommandAst])
    {
        return $Statement.PipelineElements[0]
    }

    return $null
}

<#
    Emits a finding for every statement that runs a command where only Pester
    block commands belong. A pure assignment is left alone: it executes during
    Discovery, which is how -ForEach data is legitimately built.
#>
function Find-DisallowedStatement
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param
    (
        [Parameter(Mandatory)]
        [string]$FilePath,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [StatementAst[]]$Statement,

        [Parameter(Mandatory)]
        [string[]]$AllowedCommand,

        [Parameter(Mandatory)]
        [ValidateSet('TopLevelCommand', 'BlockBodyCommand')]
        [string]$Construct,

        [Parameter(Mandatory)]
        [string]$Guidance
    )

    foreach ($currentStatement in $Statement)
    {
        if ($currentStatement -is [FunctionDefinitionAst])
        {
            New-Finding -FilePath $FilePath -Extent $currentStatement.Extent -Construct $Construct `
                -Detail ('function {0}' -f $currentStatement.Name) `
                -Guidance 'Pester 5 runs each It in its own runspace; define helpers in BeforeAll.'
            continue
        }

        $statementCommand = Resolve-StatementCommand -Statement $currentStatement

        if ($statementCommand -and $statementCommand.GetCommandName() -in $AllowedCommand)
        {
            continue
        }

        $command = $currentStatement.FindAll(
            { param ($node) $node -is [CommandAst] },
            $true
        )

        foreach ($currentCommand in $command)
        {
            $commandName = $currentCommand.GetCommandName()

            if (-not $commandName -or $commandName -in $script:blockCommand)
            {
                continue
            }

            New-Finding -FilePath $FilePath -Extent $currentCommand.Extent -Construct $Construct `
                -Detail $commandName -Guidance $Guidance
            break
        }
    }
}

function Find-FilePattern
{
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param
    (
        [Parameter(Mandatory)]
        [string]$FilePath
    )

    $token = $null
    $parseError = $null
    $ast = [Parser]::ParseFile($FilePath, [ref]$token, [ref]$parseError)

    if ($parseError -and $parseError.Count -gt 0)
    {
        foreach ($currentError in $parseError)
        {
            New-Finding -FilePath $FilePath -Extent $currentError.Extent -Construct 'ParseError' `
                -Detail $currentError.Message `
                -Guidance 'Fix the syntax before migrating; the rest of this file was not scanned.'
        }

        return
    }

    $command = $ast.FindAll({ param ($node) $node -is [CommandAst] }, $true)

    foreach ($currentCommand in $command)
    {
        $commandName = $currentCommand.GetCommandName()

        if (-not $commandName)
        {
            continue
        }

        switch -Regex ($commandName)
        {
            '^Should$'
            {
                if ($currentCommand.CommandElements.Count -ge 2 -and
                    $currentCommand.CommandElements[1] -isnot [CommandParameterAst])
                {
                    New-Finding -FilePath $FilePath -Extent $currentCommand.Extent -Construct 'LegacyShould' `
                        -Detail $currentCommand.Extent.Text `
                        -Guidance 'Use the dashed form. Should -Throw matches with -like, so wrap the expected text in *.'
                }
            }

            '^Assert-(MockCalled|VerifiableMocks?)$'
            {
                $replacement = if ($commandName -eq 'Assert-MockCalled') { 'Should -Invoke' } else { 'Should -InvokeVerifiable' }

                New-Finding -FilePath $FilePath -Extent $currentCommand.Extent -Construct 'LegacyMockAssertion' `
                    -Detail $commandName `
                    -Guidance ('Replace with {0}; re-check -Times after the scope changes.' -f $replacement)
            }

            '^InModuleScope$'
            {
                $body = $currentCommand.CommandElements |
                    Where-Object -FilterScript { $_ -is [ScriptBlockExpressionAst] }

                foreach ($currentBody in $body)
                {
                    $wrapped = $currentBody.FindAll(
                        { param ($node) $node -is [CommandAst] -and $node.GetCommandName() -in @('Describe', 'Context', 'It') },
                        $true
                    )

                    if ($wrapped.Count -gt 0)
                    {
                        New-Finding -FilePath $FilePath -Extent $currentCommand.Extent -Construct 'InModuleScopeWrapper' `
                            -Detail ('wraps {0}' -f $wrapped[0].GetCommandName()) `
                            -Guidance 'Prefer Mock -ModuleName. Keep InModuleScope inside an It, never around a block.'
                    }
                }
            }

            '^Invoke-Pester$'
            {
                $deprecated = $currentCommand.CommandElements |
                    Where-Object -FilterScript {
                        $_ -is [CommandParameterAst] -and
                        $_.ParameterName -in @('Script', 'TestName', 'Show', 'PesterOption', 'Strict')
                    }

                foreach ($currentParameter in $deprecated)
                {
                    New-Finding -FilePath $FilePath -Extent $currentParameter.Extent -Construct 'DeprecatedParameter' `
                        -Detail ('-{0}' -f $currentParameter.ParameterName) `
                        -Guidance 'Move to New-PesterConfiguration; -Script becomes -Path and -TestName becomes -FullNameFilter.'
                }
            }
        }

        if ($commandName -in @('Describe', 'Context'))
        {
            $body = $currentCommand.CommandElements |
                Where-Object -FilterScript { $_ -is [ScriptBlockExpressionAst] } |
                Select-Object -Last 1

            if ($body -and $body.ScriptBlock.EndBlock)
            {
                Find-DisallowedStatement -FilePath $FilePath -Statement $body.ScriptBlock.EndBlock.Statements `
                    -AllowedCommand $script:blockCommand -Construct 'BlockBodyCommand' `
                    -Guidance 'Code in a block body runs during Discovery. Move setup to BeforeAll, -ForEach data to BeforeDiscovery.'
            }
        }
    }

    $member = $ast.FindAll({ param ($node) $node -is [MemberExpressionAst] }, $true)

    foreach ($currentMember in $member)
    {
        if ($currentMember.Extent.Text -match '\$MyInvocation\.MyCommand\.(Path|Definition)')
        {
            New-Finding -FilePath $FilePath -Extent $currentMember.Extent -Construct 'LegacyPathDiscovery' `
                -Detail $currentMember.Extent.Text `
                -Guidance 'Returns nothing inside a Pester 5 BeforeAll. Use $PSScriptRoot or $PSCommandPath.'
        }
    }

    if ($ast.EndBlock)
    {
        Find-DisallowedStatement -FilePath $FilePath -Statement $ast.EndBlock.Statements `
            -AllowedCommand $script:topLevelCommand -Construct 'TopLevelCommand' `
            -Guidance 'Runs during Discovery on every file. Legal only when it builds -ForEach data; otherwise move it into BeforeAll.'
    }
}

$resolvedPath = Resolve-Path -LiteralPath $Path | Select-Object -ExpandProperty Path

$targetFile = if (Test-Path -LiteralPath $resolvedPath -PathType Container)
{
    Get-ChildItem -LiteralPath $resolvedPath -Filter $Filter -File -Recurse
}
else
{
    Get-Item -LiteralPath $resolvedPath
}

if (-not $targetFile)
{
    Write-Warning -Message ("No file matching '{0}' found under '{1}'." -f $Filter, $resolvedPath)
    return
}

foreach ($currentFile in $targetFile)
{
    Write-Verbose -Message ('Scanning {0}' -f $currentFile.FullName)
    Find-FilePattern -FilePath $currentFile.FullName
}
