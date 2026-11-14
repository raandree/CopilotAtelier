<#
    Test helper: the rule of the model-free cases C1 and C2 of
    docs/client-adapter-evals.md.

    tests/ClientAdapterRuntime.Tests.ps1 applies it to each run on a runtime and,
    in process, to the observation each committed receipt records and to
    variations of it. So the rule that decides a case is the rule its tests
    assert, and a receipt whose recorded outcome its own observation refutes
    fails on every system, also where no runtime is installed.

    Each check decides a case, states what the smoke suite expects of the client,
    or both. A case passes only while every check that decides it holds, and the
    suite fails on every check it requires that does not hold.

    C2 fails closed on delegation. A delegation tool offered with the profile
    selected can reach any agent unless something shows that it stays inside the
    profile's agents: allow-list, and nothing the run records can show that. So
    C2 fails while one is offered, whatever the runtime warns about the fields it
    read: on the VS Code client the receipt records that failure, and the
    composed Copilot CLI variant withholds delegation, so there the suite fails
    as well. Every other tool offered must be one the file's entries can enable
    on the client's runtime or one that runtime offers by itself.
#>

function Get-ClientAdapterCaseVerdict
{
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory)]
        [ValidateSet('vscode', 'copilot-cli')]
        [System.String] $Client,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.String[]] $DeclaredTool,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.Object] $Observation
    )

    foreach ($property in 'ListedAsUserAgent', 'LoadError', 'LoadWarning', 'LoadedTool', 'OfferedWithoutAgent', 'OfferedWithAgent')
    {
        if ($property -notin $Observation.PSObject.Properties.Name)
        {
            throw "The observation records no '$property', so the cases cannot be decided."
        }
    }

    $loadError = @($Observation.LoadError | Where-Object -FilterScript { $_ })
    $loadWarning = @($Observation.LoadWarning | Where-Object -FilterScript { $_ })
    $loadedTool = @($Observation.LoadedTool | Where-Object -FilterScript { $_ } | Sort-Object)
    $offeredWithout = @($Observation.OfferedWithoutAgent | Where-Object -FilterScript { $_ })
    $offeredWith = @($Observation.OfferedWithAgent | Where-Object -FilterScript { $_ })
    $declared = @($DeclaredTool | Where-Object -FilterScript { $_ } | Sort-Object)

    # The runtime names of read, edit, execute, search, fetch, and ask_user on Windows.
    $workflowTool = @('view', 'edit', 'create', 'powershell', 'grep', 'glob', 'web_fetch', 'ask_user')

    # The tools through which a selected agent reaches other agents, matched in any case.
    $delegationTool = @('task', 'list_agents', 'read_agent', 'write_agent')

    <#
        Everything the file's entries can enable on the client's runtime apart
        from delegation, plus the tools that runtime offers by itself: skill and
        sql on Copilot CLI 1.0.96, sql alone on the agent-host runtime 1.0.108-0.
        Matched exactly, so a tool outside the list fails C2 and the suite until
        a review adds it.
    #>
    $executionTool = @('powershell', 'read_powershell', 'write_powershell', 'list_powershell', 'stop_powershell')
    $allowedTool = @{
        'copilot-cli' = @('ask_user', 'view', 'edit', 'create', 'grep', 'glob', 'web_fetch', 'update_todo', 'skill', 'sql') + $executionTool
        'vscode'      = @('ask_user', 'view', 'edit', 'create', 'grep', 'glob', 'web_fetch', 'update_todo', 'sql') + $executionTool
    }

    # The fields the source profile carries for local VS Code chat only; the agent-host runtime warns that it ignores them.
    $expectedIgnoredField = @{
        'copilot-cli' = @()
        'vscode'      = @('agents', 'argument-hint', 'handoffs')
    }

    $ignoredField = [System.Collections.Generic.List[string]]::new()
    $unexpectedWarning = [System.Collections.Generic.List[string]]::new()

    foreach ($warning in $loadWarning)
    {
        if ($warning -match 'unknown fields? ignored:\s*(?<field>.+)$')
        {
            $field = @($Matches['field'] -split ',' | ForEach-Object -Process { $_.Trim() } | Where-Object -FilterScript { $_ })
            $ignoredField.AddRange([string[]] $field)

            if (@($field | Where-Object -FilterScript { $_ -cnotin $expectedIgnoredField[$Client] }).Count -gt 0)
            {
                $unexpectedWarning.Add($warning)
            }
        }
        else
        {
            $unexpectedWarning.Add($warning)
        }
    }

    $notIgnoredField = @($expectedIgnoredField[$Client] | Where-Object -FilterScript { $_ -cnotin $ignoredField })
    $missingWorkflowTool = @($workflowTool | Where-Object -FilterScript { $_ -cnotin $offeredWith })
    $delegationOffered = @($offeredWith | Where-Object -FilterScript { $_ -in $delegationTool })
    $beyondAllowList = @($offeredWith | Where-Object -FilterScript { $_ -notin $delegationTool -and $_ -cnotin $allowedTool[$Client] })
    $extraTool = @($loadedTool | Where-Object -FilterScript { $_ -notin $declared })
    $droppedTool = @($declared | Where-Object -FilterScript { $_ -notin $loadedTool })
    $declaredDetail = 'the runtime kept {0} beyond the tools the file declares, and dropped {1}' -f @(
        $(if ($extraTool.Count -gt 0) { $extraTool -join ', ' } else { 'nothing' })
        $(if ($droppedTool.Count -gt 0) { $droppedTool -join ', ' } else { 'nothing' })
    )

    $warningDetail = @(
        if ($unexpectedWarning.Count -gt 0)
        {
            'the runtime warned {0}, which the suite does not expect of this client' -f (($unexpectedWarning | ForEach-Object -Process { "'$_'" }) -join ' and ')
        }

        if ($notIgnoredField.Count -gt 0)
        {
            'the runtime no longer warns that it ignores {0}, which the suite expects of this client' -f ($notIgnoredField -join ', ')
        }
    )

    $sessionDetail = @(
        if ('probe_tool' -notin $offeredWithout)
        {
            'the session did not offer its own probe_tool before the selection'
        }

        if ('probe_tool' -in $offeredWith)
        {
            'the selection kept the session''s own probe_tool, which the file does not declare'
        }
    )

    $check = [System.Collections.Generic.List[object]]::new()

    $check.Add([pscustomobject] @{
            Case     = 'C1'
            Name     = 'Listed'
            Holds    = ($Observation.ListedAsUserAgent -is [bool]) -and $Observation.ListedAsUserAgent
            Required = $true
            Detail   = 'the runtime did not list the profile once, from the scratch agents directory, as a user agent'
        })

    $check.Add([pscustomobject] @{
            Case     = 'C1'
            Name     = 'LoadError'
            Holds    = $loadError.Count -eq 0
            Required = $true
            Detail   = 'the runtime reported load errors: {0}' -f ($loadError -join ' | ')
        })

    # C1 is strict: any warning fails it. The suite fails only on a warning it does not expect of the client.
    $check.Add([pscustomobject] @{
            Case     = 'C1'
            Name     = 'Warning'
            Holds    = $loadWarning.Count -eq 0
            Required = $false
            Detail   = 'the runtime warned: {0}' -f ($loadWarning -join ' | ')
        })

    $check.Add([pscustomobject] @{
            Case     = $null
            Name     = 'ExpectedWarning'
            Holds    = $warningDetail.Count -eq 0
            Required = $true
            Detail   = $warningDetail -join '; '
        })

    $check.Add([pscustomobject] @{
            Case     = 'C2'
            Name     = 'DeclaredTool'
            Holds    = ($loadedTool -join ',') -eq ($declared -join ',')
            Required = $true
            Detail   = $declaredDetail
        })

    $check.Add([pscustomobject] @{
            Case     = 'C2'
            Name     = 'SessionFilter'
            Holds    = $sessionDetail.Count -eq 0
            Required = $true
            Detail   = $sessionDetail -join '; '
        })

    $check.Add([pscustomobject] @{
            Case     = 'C2'
            Name     = 'WorkflowTool'
            Holds    = $missingWorkflowTool.Count -eq 0
            Required = $true
            Detail   = 'the runtime did not offer {0}, which the workflow needs' -f ($missingWorkflowTool -join ', ')
        })

    $check.Add([pscustomobject] @{
            Case     = 'C2'
            Name     = 'AllowList'
            Holds    = $beyondAllowList.Count -eq 0
            Required = $true
            Detail   = 'the runtime offered {0}, beyond the tools this client allows' -f ($beyondAllowList -join ', ')
        })

    # Required only of the composed variant: on the VS Code client the failure of C2 is what the receipt records.
    $check.Add([pscustomobject] @{
            Case     = 'C2'
            Name     = 'Delegation'
            Holds    = $delegationOffered.Count -eq 0
            Required = $Client -eq 'copilot-cli'
            Detail   = 'the runtime offered {0}, delegation that nothing shows to stay inside the profile''s agents: allow-list' -f ($delegationOffered -join ', ')
        })

    if ($Client -eq 'copilot-cli')
    {
        $identifier = @($loadedTool | Where-Object -FilterScript { $_ -match '/' -or $_ -in @('web', 'search') })

        $check.Add([pscustomobject] @{
                Case     = 'C2'
                Name     = 'ClientIdentifier'
                Holds    = $identifier.Count -eq 0
                Required = $true
                Detail   = 'the variant kept {0}, which enable no tool on this client' -f ($identifier -join ', ')
            })
    }

    foreach ($entry in $check)
    {
        if ($entry.Holds)
        {
            $entry.Detail = $null
        }
    }

    $outcome = [ordered] @{}

    foreach ($case in 'C1', 'C2')
    {
        $outcome[$case] = if (@($check | Where-Object -FilterScript { $_.Case -eq $case -and -not $_.Holds }).Count -eq 0) { 'Passed' } else { 'Failed' }
    }

    return [pscustomobject] @{
        Outcome   = $outcome
        Check     = @($check)
        Violation = @($check | Where-Object -FilterScript { $_.Required -and -not $_.Holds })
    }
}
