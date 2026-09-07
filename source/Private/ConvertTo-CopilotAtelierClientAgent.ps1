function ConvertTo-CopilotAtelierClientAgent
{
    <#
        .SYNOPSIS
            Composes one Custom agent profile for a Copilot client from the
            authoritative VS Code source file.

        .DESCRIPTION
            The file under com.github.copilot/agents stays the only source of
            the shared workflow. This function reads it, keeps the body byte for
            byte, rewrites the frontmatter through the allow-listed mapping in
            Get-CopilotAtelierClientContract, and prepends an additive
            client-limitation section that states what the client cannot do.
            Nothing is copied into a second catalog, so a variant cannot drift
            from the profile it came from.

            The boundary between composed presentation and authoritative content
            is explicit. The limitation section sits between two HTML comment
            markers, the end marker carries the SHA-256 of the shared body that
            follows it, and the body is the last thing in the file. A reader, a
            test, or a reviewer can therefore tell the two apart without
            trusting this function.

            For the authoritative client the composition is the identity: the
            source content is returned unchanged apart from line-ending
            normalization, which is what keeps the working VS Code profile out
            of reach of this code path.

            The composition fails rather than degrades. Frontmatter is parsed as
            a strict subset, so an unknown or ambiguous field is rejected and no
            tool list is ever partially mapped. A tool identifier with no entry
            in the mapping is an error. An identifier that would reach the
            shell-execution alias without being a declared execution tool is an
            error. A capability or a workflow mode the caller declares required
            but the client cannot provide is an error, and nothing is emitted,
            because a variant that shipped anyway would promise work it cannot
            perform. A field that expresses a restriction and cannot be
            expressed withholds the tool it guards, so a client never gains an
            unrestricted version of a capability the source deliberately
            bounded.

        .PARAMETER Path
            The authoritative .agent.md file to compose from.

        .PARAMETER Client
            The client to compose for.

        .PARAMETER RequiredCapability
            Client tool aliases the composed variant must end up with. Anything
            missing raises a terminating error naming it.

        .PARAMETER RequiredWorkflow
            Workflow modes the composed variant must be able to run, such as
            bounded-default, review:on or cycle:full. An unsupported one raises
            a terminating error instead of producing deployable content.

        .OUTPUTS
            System.Management.Automation.PSCustomObject

        .EXAMPLE
            ConvertTo-CopilotAtelierClientAgent -Path ./software-engineer.agent.md -Client copilot-cli

            Composes the Copilot CLI variant of the representative profile.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $Path,

        [Parameter(Mandatory)]
        [ValidateSet('vscode', 'copilot-cli')]
        [System.String]
        $Client,

        [Parameter()]
        [System.String[]]
        $RequiredCapability = @(),

        [Parameter()]
        [System.String[]]
        $RequiredWorkflow = @()
    )

    $ErrorActionPreference = 'Stop'

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf))
    {
        throw "The Custom agent profile '$Path' does not exist."
    }

    $contract = Get-CopilotAtelierClientContract
    $clientContract = $contract.Client[$Client]

    # Composition is line-ending neutral so a checkout on either platform emits
    # the same bytes and a determinism check cannot pass by accident.
    $normalized = [System.IO.File]::ReadAllText($Path) -replace "`r`n", "`n"
    $fileName = [System.IO.Path]::GetFileName($Path)

    $parsed = ConvertFrom-CopilotAtelierAgentFrontmatter -Content $normalized `
        -KnownField $contract.KnownField -Source "the Custom agent profile '$Path'"

    $source = $parsed.Field
    $body = $parsed.Body

    $hashProvider = [System.Security.Cryptography.SHA256]::Create()

    try
    {
        $sharedBodyHash = [System.BitConverter]::ToString(
            $hashProvider.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($body))).Replace('-', '').ToLowerInvariant()
    }
    finally
    {
        $hashProvider.Dispose()
    }

    $sourceTool = @(
        if ($source.Contains('tools'))
        {
            if ($source['tools'].Type -ne 'Sequence')
            {
                throw "The tools field in '$Path' is '$($source['tools'].Type)' rather than a list, so it cannot be mapped."
            }

            $source['tools'].Value
        }
    )

    $agentName = if ($source.Contains('name'))
    {
        [System.String] $source['name'].Value
    }
    else
    {
        $fileName -replace '\.agent\.md$', ''
    }

    $workflowCapability = @(
        foreach ($workflow in $clientContract.Workflow.Keys)
        {
            $clientContract.Workflow[$workflow]
        }
    )

    $unsupportedWorkflow = @(
        $workflowCapability |
            Where-Object -FilterScript { $_.Status -ne 'Supported' } |
            ForEach-Object -Process { $_.Workflow }
    )

    $refusedWorkflow = @(
        $RequiredWorkflow |
            Where-Object -FilterScript { $_ -in $unsupportedWorkflow }
    )

    if ($refusedWorkflow)
    {
        throw "The '$Client' variant of '$agentName' cannot run the required workflow: $($refusedWorkflow -join ', '). Nothing is composed, because a variant that shipped anyway would carry a body promising a workflow this client refuses."
    }

    if ($clientContract.IsAuthoritativeSource)
    {
        $frontmatter = [ordered] @{}

        foreach ($name in $source.Keys)
        {
            $frontmatter[$name] = $source[$name].Value
        }

        return [pscustomobject] @{
            Name                  = $agentName
            Client                = $Client
            SourcePath            = $Path
            FileName              = $fileName
            Frontmatter           = $frontmatter
            Preamble              = ''
            Body                  = $body
            SharedBodyHash        = $sharedBodyHash
            Content               = $normalized
            Tool                  = $sourceTool
            WithheldTool          = @()
            UnsupportedCapability = @()
            WorkflowCapability    = $workflowCapability
            UnsupportedWorkflow   = $unsupportedWorkflow
        }
    }

    $unsupported = [System.Collections.Generic.List[psobject]]::new()
    $withheld = [System.Collections.Generic.List[string]]::new()
    $alias = [System.Collections.Generic.List[string]]::new()

    foreach ($identifier in $sourceTool)
    {
        if (-not $clientContract.ToolMap.Contains($identifier))
        {
            throw "The tool identifier '$identifier' in '$Path' has no entry in the '$Client' tool mapping. Add an explicit mapping or an explicit unsupported entry; an unmapped identifier is never assumed safe to drop."
        }

        $mapped = $clientContract.ToolMap[$identifier]

        if ($mapped)
        {
            if ($mapped -eq 'execute' -and $identifier -notin $clientContract.ExecutionSourceTool)
            {
                throw "The tool identifier '$identifier' would reach the '$Client' shell-execution alias without being a declared execution tool. Correct the contract instead of widening the grant."
            }

            if (-not $alias.Contains($mapped))
            {
                $alias.Add($mapped)
            }

            continue
        }

        $reason = if ($clientContract.ToolUnsupportedReason.Contains($identifier))
        {
            $clientContract.ToolUnsupportedReason[$identifier]
        }
        else
        {
            "No documented '$Client' tool alias corresponds to this identifier."
        }

        $unsupported.Add(
            [pscustomobject] @{
                Capability   = $identifier
                Kind         = 'Tool'
                Reason       = $reason
                WithholdTool = $null
            }
        )
    }

    foreach ($fieldName in $clientContract.UnsupportedField.Keys)
    {
        if (-not $source.Contains($fieldName))
        {
            continue
        }

        $entry = $clientContract.UnsupportedField[$fieldName]
        $unsupported.Add($entry)

        if ($entry.WithholdTool -and $alias.Contains($entry.WithholdTool))
        {
            $alias.Remove($entry.WithholdTool) | Out-Null
            $withheld.Add($entry.WithholdTool)
        }
    }

    $emittedTool = @($alias | Sort-Object)

    $missingCapability = @(
        $RequiredCapability |
            Where-Object -FilterScript { $_ -notin $emittedTool }
    )

    if ($missingCapability)
    {
        throw "The '$Client' variant of '$agentName' cannot provide the required capability: $($missingCapability -join ', '). The shared workflow body depends on it, so the variant is refused rather than shipped without it."
    }

    $field = [ordered] @{}

    foreach ($name in $clientContract.EmittedField)
    {
        if ($name -eq 'target')
        {
            if ($clientContract.TargetValue)
            {
                $field['target'] = [pscustomobject] @{ Type = 'String'; Value = $clientContract.TargetValue }
            }

            continue
        }

        if ($name -eq 'tools')
        {
            $field['tools'] = [pscustomobject] @{ Type = 'Sequence'; Value = $emittedTool }

            continue
        }

        if ($source.Contains($name))
        {
            # Rendered from the decoded value, so the emitted quoting matches
            # the value rather than inheriting the source style.
            $field[$name] = $source[$name]
        }
    }

    $frontmatterText = ConvertTo-CopilotAtelierAgentFrontmatter -Field $field

    $limitation = [System.Collections.Generic.List[string]]::new()
    $limitation.Add("<!-- copilot-atelier:client-limitations:begin client=$Client -->")
    $limitation.Add('')
    $limitation.Add("## Client limitations: $($clientContract.DisplayName)")
    $limitation.Add('')
    $limitation.Add("CopilotAtelier composed this file from the authoritative VS Code Copilot Chat profile ``$fileName``. The shared workflow body below is unchanged. This section is additive and it wins: where that body assumes something named here as unsupported, this section overrides it.")
    $limitation.Add('')
    $limitation.Add('### Unsupported workflow modes')
    $limitation.Add('')

    foreach ($workflow in $unsupportedWorkflow)
    {
        $entry = $clientContract.Workflow[$workflow]
        $limitation.Add("- ``$($workflow -replace ':', ': ')`` is not available on this client. $($entry.Reason) $($entry.ClientInstruction)")
    }

    $limitation.Add('')
    $limitation.Add('If one of those modes is requested, refuse it and say why. Do not run a reduced substitute and report it as the mode that was asked for.')
    $limitation.Add('')
    $limitation.Add('### Supported')
    $limitation.Add('')

    foreach ($entry in @($workflowCapability | Where-Object -FilterScript { $_.Status -eq 'Supported' }))
    {
        $limitation.Add("- ``$($entry.Workflow -replace ':', ': ')``. $($entry.Reason)")
    }

    $limitation.Add('')
    $limitation.Add('### Capabilities this variant does not have')
    $limitation.Add('')
    $limitation.Add("- Tools available here: $($emittedTool -join ', ').")

    if ($withheld.Count -gt 0)
    {
        $limitation.Add("- Withheld on purpose: $(($withheld | Sort-Object) -join ', '). The source profile bounds that capability with a restriction this client cannot express, so the capability is removed rather than inherited unrestricted.")
    }

    $limitation.Add("- $($unsupported.Count) source capabilities have no counterpart here. Run ``Get-CopilotAtelierClientAdapter -Name $agentName -Client $Client`` for the full list and the reason for each.")
    $limitation.Add('')
    $limitation.Add("<!-- copilot-atelier:client-limitations:end client=$Client sharedBodySha256=$sharedBodyHash -->")
    $limitation.Add('')

    $preamble = ($limitation -join "`n") + "`n"
    $content = "---`n" + $frontmatterText + "`n---`n" + $preamble + $body

    <#
        The emitted block is reparsed under the same strict rules before it is
        returned. Frontmatter that does not round-trip is invalid generated
        YAML, and it must never reach a file.
    #>
    $verified = ConvertFrom-CopilotAtelierAgentFrontmatter -Content $content `
        -KnownField $contract.KnownField -Source "the composed '$Client' variant of '$agentName'"
    $unit = [System.String] [System.Char] 31

    if ((@($verified.Field.Keys) -join ',') -ne (@($field.Keys) -join ','))
    {
        throw "The composed '$Client' variant of '$agentName' does not reparse to the fields it was composed from."
    }

    foreach ($name in $field.Keys)
    {
        if ((@($verified.Field[$name].Value) -join $unit) -ne (@($field[$name].Value) -join $unit))
        {
            throw "The composed '$Client' variant of '$agentName' does not reparse to the value it was composed from for the field '$name'."
        }
    }

    if ($verified.Body -ne ($preamble + $body))
    {
        throw "The composed '$Client' variant of '$agentName' does not carry the shared body unchanged after its limitation section."
    }

    $frontmatter = [ordered] @{}

    foreach ($name in $field.Keys)
    {
        $frontmatter[$name] = $field[$name].Value
    }

    return [pscustomobject] @{
        Name                  = $agentName
        Client                = $Client
        SourcePath            = $Path
        FileName              = $fileName
        Frontmatter           = $frontmatter
        Preamble              = $preamble
        Body                  = $body
        SharedBodyHash        = $sharedBodyHash
        Content               = $content
        Tool                  = $emittedTool
        WithheldTool          = @($withheld)
        UnsupportedCapability = @($unsupported)
        WorkflowCapability    = $workflowCapability
        UnsupportedWorkflow   = $unsupportedWorkflow
    }
}
