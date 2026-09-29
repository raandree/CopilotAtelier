function Get-CopilotAtelierClientContract
{
    <#
        .SYNOPSIS
            Returns the allow-listed compatibility contract for each Copilot
            client the Custom agent profiles are composed for.

        .DESCRIPTION
            The shipped Custom agent profiles under com.github.copilot/agents
            are authored in the VS Code shape: a model priority array and
            product-qualified tool identifiers. The Copilot CLI reads the same
            files but documents a different contract, so a profile that loads in
            both is not a profile that behaves the same in both.

            This function is the single source of truth for that difference. It
            declares, per client, which frontmatter fields are emitted, which
            are unsupported and why, how a source tool identifier maps onto one
            or more client tool names, which workflow modes the client cannot
            run, and what verification state the claim rests on. Nothing else in
            the module may invent a mapping: an identifier that is absent from
            ToolMap is an error rather than a silently dropped capability.

            Three rules are encoded rather than left to judgement. A source
            identifier may only map onto the shell-execution alias when it is
            named in ExecutionSourceTool, because a product prefix such as
            execute/ is a namespace and not proof of execution authority -
            reading an existing terminal buffer is not permission to start a
            command. Every other mapping has to stay inside the capability class
            of its source identifier, and CapabilityClass lists the client tool
            names each class contains. And a field that expresses a restriction
            rather than a capability names the tool it guards in WithholdTool,
            so a client that cannot express the restriction loses the capability
            instead of inheriting it unrestricted.

            VerificationState never claims a runtime result without a receipt
            bound to the artifact it describes. A one-off observation that a
            checkout's profile loaded in one editor build is kept separately as
            SourceProfileObservation, because it says nothing about an arbitrary
            content path or a composed variant.

            AdaptedAgent is the rollout gate. Only the profiles listed there are
            composed for a non-authoritative client, and each entry names the
            capabilities and workflow modes its shared workflow body cannot run
            without.

        .OUTPUTS
            System.Management.Automation.PSCustomObject

        .EXAMPLE
            Get-CopilotAtelierClientContract

            Returns the client contracts, tool mappings, and adapted agents.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param ()

    <#
        Verified against the GitHub "Custom agents configuration" reference and
        the VS Code "Custom agents" documentation on 2026-09-07. A value of
        $null means the identifier has no documented client equivalent and is
        reported as unsupported rather than approximated.

        The reference documents web and search as aliases, but the runtime this
        client shares with VS Code agent-host sessions resolves neither to a
        tool (github/copilot-cli#4594). An offline probe of the runtime bundled
        with VS Code 1.139.1 on 2026-09-29 confirmed that web_fetch, grep, glob,
        and ask_user each enable their tool, so those exact names replace the
        dead aliases. The todo alias resolves to nothing as well; it stays
        because the runtime always offers the sql tool that holds the todo list.
    #>
    $copilotCliToolMap = [ordered] @{
        'agent'                       = 'agent'
        'ask_user'                    = 'ask_user'
        'browser'                     = $null
        'codeInterpreter'             = $null
        'edit/createDirectory'        = 'edit'
        'edit/createFile'             = 'edit'
        'edit/editFiles'              = 'edit'
        'edit/editNotebook'           = $null
        'edit/rename'                 = $null
        'execute/createAndRunTask'    = $null
        'execute/getTerminalOutput'   = $null
        'execute/runInTerminal'       = 'execute'
        'execute/runNotebookCell'     = $null
        'execute/runTask'             = $null
        'github'                      = $null
        'glob'                        = 'glob'
        'grep'                        = 'grep'
        'read/getNotebookSummary'     = $null
        'read/problems'               = $null
        'read/readFile'               = 'read'
        'read/readNotebookCellOutput' = $null
        'read/terminalLastCommand'    = $null
        'read/terminalSelection'      = $null
        'read/testFailure'            = $null
        'read/viewImage'              = $null
        'runTests'                    = $null
        'search'                      = @('grep', 'glob')
        'search/changes'              = $null
        'search/codebase'             = $null
        'search/fileSearch'           = @('grep', 'glob')
        'search/findTestFiles'        = $null
        'search/listDirectory'        = @('grep', 'glob')
        'search/searchResults'        = $null
        'search/textSearch'           = @('grep', 'glob')
        'search/usages'               = $null
        'thinking'                    = $null
        'todo'                        = 'todo'
        'useMcp'                      = $null
        'vscode/askQuestions'         = $null
        'vscode/extensions'           = $null
        'vscode/getProjectSetupInfo'  = $null
        'vscode/installExtension'     = $null
        'vscode/newWorkspace'         = $null
        'vscode/runCommand'           = $null
        'vscode/vscodeAPI'            = $null
        'web/fetch'                   = 'web_fetch'
        'web/githubRepo'              = $null
        'web/githubTextSearch'        = $null
        'web_fetch'                   = 'web_fetch'
    }

    <#
        Tools that exist only in VS Code agent-host sessions. The profiles name
        them so that the agent-host runtime keeps them; this client has neither
        the integrated browser nor an agent-host session, so every one of them
        is an explicit unsupported entry.
    #>
    $agentHostBrowserTool = @(
        'vscodeBrowser/openBrowserPage'
        'vscodeBrowser/readPage'
        'vscodeBrowser/screenshotPage'
        'vscodeBrowser/navigatePage'
        'vscodeBrowser/clickElement'
        'vscodeBrowser/typeInPage'
        'vscodeBrowser/hoverElement'
        'vscodeBrowser/dragElement'
        'vscodeBrowser/handleDialog'
        'vscodeBrowser/runPlaywrightCode'
    )

    $agentHostSessionTool = @(
        'set_workspace'
        'list_sessions'
        'get_current_session'
        'get_session_context'
        'add_artifact_or_reference'
        'list_artifacts_and_references'
        'remove_artifact_or_reference'
    )

    foreach ($identifier in $agentHostBrowserTool + $agentHostSessionTool)
    {
        $copilotCliToolMap[$identifier] = $null
    }

    <#
        Only these identifiers carry the authority to start a command, so only
        these may become the client execute alias. Everything else in the
        execute/ namespace either runs a declared VS Code task or reads what a
        command already produced, which is a different permission.
    #>
    $copilotCliExecutionSourceTool = @('execute/runInTerminal')

    <#
        A mapping may only stay inside the capability class of its source
        identifier, and each class lists the client tool names that belong to
        it. The class of a source identifier is the segment before the slash.
        An identifier without one counts toward the class that lists it, which
        is how an exact runtime name such as grep belongs to search; any other
        identifier without a slash names its class itself.
    #>
    $copilotCliCapabilityClass = [ordered] @{
        'agent'    = @('agent')
        'ask_user' = @('ask_user')
        'edit'     = @('edit')
        'execute'  = @('execute')
        'read'     = @('read')
        'search'   = @('grep', 'glob')
        'todo'     = @('todo')
        'web'      = @('web_fetch')
    }

    <#
        An identifier whose absence is a deliberate permission decision rather
        than a missing alias says so, because "no documented equivalent" would
        read as an oversight that a later contributor could "fix".
    #>
    $copilotCliToolUnsupportedReason = [ordered] @{
        'execute/getTerminalOutput' = 'The client contract has no read-only terminal alias. Its execute alias starts arbitrary commands, and reading an existing terminal buffer is not permission to start one, so the capability is reported unsupported rather than widened.'
        'execute/createAndRunTask'  = 'The client has no VS Code task runner. Mapping a task tool onto the shell-execution alias would replace running one declared task with running anything.'
        'execute/runTask'           = 'The client has no VS Code task runner. Mapping a task tool onto the shell-execution alias would replace running one declared task with running anything.'
        'execute/runNotebookCell'   = 'The client has no notebook host, and notebook execution is not interchangeable with shell execution.'
        'runTests'                  = 'Mapping a test runner onto the shell-execution alias would grant a terminal to a profile that never declared one.'
        'useMcp'                    = 'There is no way to reproduce a bounded MCP surface on this client, and an unbounded one would be a privilege increase.'
        'vscode/askQuestions'       = 'The VS Code question tool has no alias in the client contract. Its runtime counterpart, ask_user, is declared by the profile as its own entry and maps to itself.'
    }

    foreach ($identifier in $agentHostBrowserTool)
    {
        $copilotCliToolUnsupportedReason[$identifier] = 'A VS Code agent-host tool that drives the integrated browser. The client has no integrated browser, and a fetch or shell tool is a different capability, so the tool is reported unsupported rather than approximated.'
    }

    foreach ($identifier in $agentHostSessionTool)
    {
        $copilotCliToolUnsupportedReason[$identifier] = 'A VS Code agent-host session tool. The client has no agent-host session for it to act on, so the tool is reported unsupported.'
    }

    $copilotCliUnsupportedField = [ordered] @{
        'model' = [pscustomobject] @{
            Capability   = 'model'
            Kind         = 'Field'
            Reason       = 'The client contract documents a single model string, and the VS Code qualified names are not client model identifiers. The field is omitted so the client falls back to its own default rather than receiving an invented value.'
            WithholdTool = $null
        }

        'argument-hint' = [pscustomobject] @{
            Capability   = 'argument-hint'
            Kind         = 'Field'
            Reason       = 'Documented as ignored outside VS Code and other IDEs.'
            WithholdTool = $null
        }

        'handoffs' = [pscustomobject] @{
            Capability   = 'handoffs'
            Kind         = 'Workflow'
            Reason       = 'Documented as ignored outside VS Code and other IDEs. The shared workflow body offers handoff buttons that this client never shows, so a workflow that advances through a handoff cannot advance here.'
            WithholdTool = $null
        }

        'agents' = [pscustomobject] @{
            Capability   = 'agents'
            Kind         = 'Restriction'
            Reason       = 'The client contract has no subagent allow-list. The restriction cannot be expressed, so the delegation capability it guards is withheld instead of being inherited unrestricted.'
            WithholdTool = 'agent'
        }
    }

    <#
        The workflow modes the shared bodies switch on. An unsupported mode is
        not degraded into a weaker substitute: a required independent review
        that cannot be dispatched under the same bounds stops the request and
        sends it back to a client that can run it.
    #>
    $copilotCliWorkflow = [ordered] @{
        'bounded-default' = [pscustomobject] @{
            Workflow          = 'bounded-default'
            Status            = 'Supported'
            Reason            = 'With review: off and cycle: off the shared body needs no delegation and no handoff, so the composed variant can honour it.'
            ClientInstruction = 'Proceed, and state plainly which validation was run.'
        }

        'review:on' = [pscustomobject] @{
            Workflow          = 'review:on'
            Status            = 'Unsupported'
            Reason            = 'The shared body satisfies review: on by dispatching the security-reviewer subagent over the finished diff. This client has no subagent allow-list, so the delegation tool is withheld and the review cannot be performed under the bounds the body assumes.'
            ClientInstruction = 'Refuse the request and return it to VS Code Copilot Chat, which can dispatch the reviewer. Do not substitute a written recommendation for a review the user explicitly required.'
        }

        'cycle:full' = [pscustomobject] @{
            Workflow          = 'cycle:full'
            Status            = 'Unsupported'
            Reason            = 'The four-stage development cycle advances between agents through handoffs, which this client ignores, and its security-review stage is a dispatch.'
            ClientInstruction = 'Refuse the request and return it to VS Code Copilot Chat. Do not run a partial cycle and report it as the full one.'
        }
    }

    $vsCodeWorkflow = [ordered] @{}

    foreach ($workflow in $copilotCliWorkflow.Keys)
    {
        $vsCodeWorkflow[$workflow] = [pscustomobject] @{
            Workflow          = $workflow
            Status            = 'Supported'
            Reason            = 'The authoritative client provides the subagent allow-list and the handoffs the shared body is written against.'
            ClientInstruction = 'Proceed as the shared workflow body describes.'
        }
    }

    return [pscustomobject] @{
        AuthoritativeClient = 'vscode'

        <#
            The top-level frontmatter fields a shipped profile may declare. A
            field outside this list is rejected during parsing, because an
            unrecognized field may carry a restriction and dropping it quietly
            is how a safety obligation disappears.
        #>
        KnownField = @(
            'name'
            'description'
            'model'
            'target'
            'tools'
            'agents'
            'handoffs'
            'argument-hint'
            'disable-model-invocation'
            'user-invocable'
        )

        AdaptedAgent = [ordered] @{
            'software-engineer' = [pscustomobject] @{
                <#
                    The shared body makes focused executable validation
                    mandatory for every code change and requires the change to
                    be made test-first, which needs read, edit, execution, and
                    search. A variant that cannot do all four would claim an
                    obligation it cannot meet.
                #>
                RequiredCapability = @('read', 'edit', 'execute', 'search')

                <#
                    Only the bounded default is required. The body's review: on
                    and cycle: full modes are user-selected, so a client that
                    cannot run them is usable as long as the composed file says
                    so and refuses them.
                #>
                RequiredWorkflow = @('bounded-default')
            }
        }

        Client = [ordered] @{
            'vscode' = [pscustomobject] @{
                Client                  = 'vscode'
                DisplayName             = 'VS Code Copilot Chat'
                IsAuthoritativeSource   = $true
                ModelShape              = 'PriorityArray'
                VerificationState       = 'StructurallyChecked'
                VerifiedClientVersion   = $null
                RuntimeReceipt          = $null
                SourceProfileObservation = [pscustomobject] @{
                    Client     = 'vscode'
                    Version    = '1.136.1'
                    ObservedOn = '2026-09-07'
                    Scope      = 'Historical evidence that the repository source profile loaded and drove a session in that VS Code build on Windows. It describes that file at that time, not an arbitrary content path and not a composed variant, so it does not raise the emitted verification state.'
                }
                DocumentationUri        = 'https://code.visualstudio.com/docs/copilot/customization/custom-agents'
                DiscoveryPath           = '~/.copilot/agents'
                TargetValue             = $null
                EmittedField            = @('name', 'description', 'model', 'disable-model-invocation', 'user-invocable', 'argument-hint', 'tools', 'agents', 'handoffs')
                ToolMap                 = $null
                ExecutionSourceTool     = @()
                CapabilityClass         = [ordered] @{}
                ToolUnsupportedReason   = [ordered] @{}
                UnsupportedField        = [ordered] @{}
                Workflow                = $vsCodeWorkflow
            }

            'copilot-cli' = [pscustomobject] @{
                Client                  = 'copilot-cli'
                DisplayName             = 'GitHub Copilot CLI'
                IsAuthoritativeSource   = $false
                ModelShape              = 'SingleString'
                VerificationState       = 'StructurallyChecked'
                VerifiedClientVersion   = $null
                RuntimeReceipt          = $null
                SourceProfileObservation = $null
                DocumentationUri        = 'https://docs.github.com/en/copilot/reference/custom-agents-configuration'
                DiscoveryPath           = '~/.copilot/agents'
                TargetValue             = 'github-copilot'
                EmittedField            = @('name', 'description', 'target', 'disable-model-invocation', 'user-invocable', 'tools')
                ToolMap                 = $copilotCliToolMap
                ExecutionSourceTool     = $copilotCliExecutionSourceTool
                CapabilityClass         = $copilotCliCapabilityClass
                ToolUnsupportedReason   = $copilotCliToolUnsupportedReason
                UnsupportedField        = $copilotCliUnsupportedField
                Workflow                = $copilotCliWorkflow
            }
        }
    }
}
