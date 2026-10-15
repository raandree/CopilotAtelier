<#
    Test helper: loads functions from a standalone script without running it.

    A script such as Test-RunContainment.ps1 has mandatory parameters and runs its
    main flow when invoked, so it cannot be dot-sourced into a test. The helper
    reads the script's syntax tree and returns a script block that defines the
    named top-level functions as script-scoped functions, together with the
    script's top-level $script: assignments (the constants the functions read).
    Dot-source the result in a BeforeAll block:

        . (Get-ScriptFunctionDefinition -Path $script:verifierScript -Name 'Test-EgressPolicy')

    The functions then live in the test's own session state, so Pester's Mock
    works on the cmdlets they call, and a test can run them in-process with
    chosen inputs instead of starting a child process for every case.
#>

function Get-ScriptFunctionDefinition
{
    [CmdletBinding()]
    [OutputType([System.Management.Automation.ScriptBlock])]
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [System.String] $Path,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [System.String[]] $Name,

        [Parameter()]
        [System.Management.Automation.SwitchParameter] $WithoutScriptVariable
    )

    $tokens = $null
    $parseError = $null
    $tree = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref] $tokens, [ref] $parseError)

    if (@($parseError).Count -gt 0)
    {
        throw "'$Path' does not parse: $($parseError[0].Message)"
    }

    $statement = [System.Collections.Generic.List[System.String]]::new()

    if (-not $WithoutScriptVariable)
    {
        foreach ($node in $tree.EndBlock.Statements)
        {
            if ($node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                $node.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
                $node.Left.VariablePath.IsScript)
            {
                $statement.Add($node.Extent.Text)
            }
        }
    }

    $found = [System.Collections.Generic.HashSet[System.String]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($node in $tree.EndBlock.Statements)
    {
        if ($node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -in $Name)
        {
            $statement.Add("function script:$($node.Name) $($node.Body.Extent.Text)")
            $null = $found.Add($node.Name)
        }
    }

    $missing = @($Name | Where-Object -FilterScript { -not $found.Contains($_) })

    if ($missing.Count -gt 0)
    {
        throw "'$Path' defines no top-level function named: $($missing -join ', ')"
    }

    return [System.Management.Automation.ScriptBlock]::Create($statement -join [System.Environment]::NewLine)
}
