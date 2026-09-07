function Get-CopilotAtelierClientAdapter
{
    <#
        .SYNOPSIS
            Reports how a shipped Custom agent profile is composed for each
            supported Copilot client, and what that client cannot do.

        .DESCRIPTION
            Custom agent files are discovered by more than one Copilot client,
            but discovery is not parity. The profiles in this library are
            authored in the VS Code shape, and the Copilot CLI contract differs:
            one model string instead of a priority array, a small set of tool
            aliases instead of product-qualified tool identifiers, and no
            subagent allow-list, handoff, or argument hint.

            This command makes that difference explicit and inspectable. For
            each requested profile and client it returns the composed
            frontmatter, the composed file content, the tools that survive the
            mapping, the tools deliberately withheld, the workflow modes the
            client cannot run, and every capability that is unsupported together
            with the reason. The VS Code profile is the authoritative source and
            is returned unchanged, so running this command can never be the
            thing that alters the working experience.

            A composed variant carries its own limitations. The content begins
            with an additive client-limitation section, bounded by explicit
            markers and bound to the shared body by its SHA-256, that refuses
            the workflow modes this client cannot honour. The shared body itself
            is byte for byte the authoritative one.

            The command reads files only. It does not contact the network, write
            anything, install a variant, or invoke a model, so it is safe to use
            as an offline smoke check of the compatibility mapping. The composed
            content is a build artifact for review and for the module and clone
            channels; it is not deployed into the discovery folders, because two
            profiles for one agent in a directory that several clients read is a
            duplicate discovery entry rather than a compatibility fix.

            Only profiles listed in the adapted rollout are composed for a
            non-authoritative client. Asking for any other profile is an error
            rather than an untested best effort.

        .PARAMETER Name
            One Custom agent profile to report. Without it, every adapted
            profile is returned.

        .PARAMETER Client
            One client to report. Without it, every supported client is returned
            with the authoritative client first.

        .PARAMETER ContentPath
            The directory that holds the customization directories. Defaults to
            the module base, or the repository root when the source files are
            dot-sourced during development.

        .PARAMETER RequiredWorkflow
            Workflow modes the caller depends on, such as bounded-default,
            review:on or cycle:full. A client that cannot run one of them raises
            a terminating error instead of returning content.

        .OUTPUTS
            System.Management.Automation.PSCustomObject

        .EXAMPLE
            Get-CopilotAtelierClientAdapter | Format-Table Name, Client, VerificationState, Tool

            Shows every adapted profile and the tools each client variant keeps.

        .EXAMPLE
            (Get-CopilotAtelierClientAdapter -Name software-engineer -Client copilot-cli).UnsupportedCapability

            Lists what the Copilot CLI variant of the representative profile
            cannot do, and why.

        .LINK
            https://github.com/raandree/CopilotAtelier
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Position = 0)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $Name,

        [Parameter()]
        [ValidateSet('vscode', 'copilot-cli')]
        [System.String]
        $Client,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $ContentPath,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [System.String[]]
        $RequiredWorkflow
    )

    $ErrorActionPreference = 'Stop'

    if (-not $PSBoundParameters.ContainsKey('ContentPath'))
    {
        $ContentPath = Get-CopilotAtelierContentPath
    }

    $ContentPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ContentPath)

    if (-not (Test-Path -LiteralPath $ContentPath -PathType Container))
    {
        throw "The customization content path '$ContentPath' does not exist or is not a directory."
    }

    $contract = Get-CopilotAtelierClientContract
    $agentDirectory = Join-Path -Path $ContentPath -ChildPath (Get-CopilotAtelierDirectoryMap)['agents']

    if (-not (Test-Path -LiteralPath $agentDirectory -PathType Container))
    {
        throw "The Custom agent directory '$agentDirectory' does not exist."
    }

    $adaptedName = @($contract.AdaptedAgent.Keys)

    if ($PSBoundParameters.ContainsKey('Name'))
    {
        if ($Name -notin $adaptedName)
        {
            throw "The Custom agent '$Name' is not part of the adapted client rollout. Adapted so far: $($adaptedName -join ', '). Roll a profile out only after its own compatibility test passes."
        }

        $requestedName = @($Name)
    }
    else
    {
        $requestedName = $adaptedName
    }

    $requestedClient = if ($PSBoundParameters.ContainsKey('Client'))
    {
        @($Client)
    }
    else
    {
        @($contract.Client.Keys)
    }

    foreach ($currentName in $requestedName)
    {
        $sourcePath = Join-Path -Path $agentDirectory -ChildPath "$currentName.agent.md"

        if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf))
        {
            throw "The Custom agent profile '$sourcePath' does not exist."
        }

        foreach ($currentClient in $requestedClient)
        {
            $clientContract = $contract.Client[$currentClient]
            $adapted = $contract.AdaptedAgent[$currentName]

            $workflow = @($adapted.RequiredWorkflow)

            if ($PSBoundParameters.ContainsKey('RequiredWorkflow'))
            {
                $workflow += $RequiredWorkflow
            }

            $composed = ConvertTo-CopilotAtelierClientAgent -Path $sourcePath -Client $currentClient `
                -RequiredCapability $adapted.RequiredCapability -RequiredWorkflow $workflow

            [pscustomobject] @{
                Name                     = $currentName
                Client                   = $currentClient
                ClientDisplayName        = $clientContract.DisplayName
                IsAdapted                = $true
                IsAuthoritativeSource    = $clientContract.IsAuthoritativeSource
                VerificationState        = $clientContract.VerificationState
                VerifiedClientVersion    = $clientContract.VerifiedClientVersion
                SourceProfileObservation = $clientContract.SourceProfileObservation
                DocumentationUri         = $clientContract.DocumentationUri
                RequiredCapability       = @($adapted.RequiredCapability)
                RequiredWorkflow         = @($workflow)
                SourcePath               = $sourcePath
                FileName                 = $composed.FileName
                Frontmatter              = $composed.Frontmatter
                Preamble                 = $composed.Preamble
                Body                     = $composed.Body
                SharedBodyHash           = $composed.SharedBodyHash
                Content                  = $composed.Content
                Tool                     = @($composed.Tool)
                WithheldTool             = @($composed.WithheldTool)
                UnsupportedCapability    = @($composed.UnsupportedCapability)
                WorkflowCapability       = @($composed.WorkflowCapability)
                UnsupportedWorkflow      = @($composed.UnsupportedWorkflow)
            }
        }
    }
}
