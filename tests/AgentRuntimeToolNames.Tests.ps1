BeforeDiscovery {
    $agentsPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'com.github.copilot/agents'

    <#
        Contained Custom agents declare no network tool by design: the Contoso
        overlay withholds every egress tool, and decision 0025 gives the three
        specification-completion agents no network access. These checks cover
        tool names only; terminal and delegation paths are bounded by prose.
        Every other agent is open and gets the common baseline, so a new agent
        has to be classified here deliberately rather than inheriting either
        rule by accident.
    #>
    $containedName = @(
        'software-engineer-contoso'
        'spec-completion-controller'
        'spec-completion-reviewer'
        'spec-work-implementer'
    )

    $script:agentCase = @(
        Get-ChildItem -LiteralPath $agentsPath -File -Filter '*.agent.md' |
            Sort-Object -Property Name |
            ForEach-Object -Process {
                @{
                    Name = $_.Name -replace '\.agent\.md$', ''
                    Path = $_.FullName
                }
            }
    )

    $script:containedCase = @($script:agentCase | Where-Object -FilterScript { $_.Name -in $containedName })
    $script:openCase = @($script:agentCase | Where-Object -FilterScript { $_.Name -notin $containedName })
    $script:containedNameCase = @($containedName | ForEach-Object -Process { @{ Name = $_ } })
}

BeforeAll {
    $script:agentsPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'com.github.copilot/agents'

    $script:browserTool = @(
        'openBrowserPage'
        'readPage'
        'screenshotPage'
        'navigatePage'
        'clickElement'
        'typeInPage'
        'hoverElement'
        'dragElement'
        'handleDialog'
        'runPlaywrightCode'
    )

    <#
        The Copilot runtime behind VS Code agent-host sessions treats an agent's
        tools list as a strict allow-list and silently drops the VS Code names
        it does not resolve (github/copilot-cli#4594). Each rule pairs the kept
        VS Code names with the exact runtime names that restore the tool. The
        browser tool set is deprecated in VS Code 1.139.1, so its tools are named
        through the vscodeBrowser tool set that the agent-file checker suggests;
        the runtime matches them by the part after the slash.
    #>
    $script:runtimeNameRule = @(
        [pscustomobject] @{
            Label   = 'web/fetch'
            Source  = @('web/fetch')
            Runtime = @('web_fetch')
        }
        [pscustomobject] @{
            Label   = 'search'
            Source  = @('search', 'search/codebase', 'search/fileSearch', 'search/listDirectory', 'search/textSearch')
            Runtime = @('grep', 'glob')
        }
        [pscustomobject] @{
            Label   = 'vscode/askQuestions'
            Source  = @('vscode/askQuestions')
            Runtime = @('ask_user')
        }
        [pscustomobject] @{
            Label   = 'browser'
            Source  = @('browser')
            Runtime = @($script:browserTool | ForEach-Object -Process { "vscodeBrowser/$_" })
        }
    )

    $script:sessionTool = @(
        'set_workspace'
        'list_sessions'
        'get_current_session'
        'get_session_context'
        'add_artifact_or_reference'
        'list_artifacts_and_references'
        'remove_artifact_or_reference'
    )

    # These create, message, rename, or delete sessions. No agent needs them.
    $script:excludedSessionTool = @(
        'create_session'
        'send_message'
        'rename_chat'
        'delete_session'
    )

    $script:baselineTool = @(
        'web/fetch'
        'web_fetch'
        'search'
        'grep'
        'glob'
        'vscode/askQuestions'
        'ask_user'
    ) + $script:sessionTool

    # Network capability under either naming: VS Code tools, tool sets, and
    # aliases, runtime tools, and the supply-chain tools the Contoso overlay
    # withholds. Any namespace outside the local ones is treated as remote, so
    # an MCP server's tools count as network by default.
    $script:networkTool = @(
        'web'
        'web/fetch'
        'fetch'
        'web/githubRepo'
        'githubRepo'
        'web/githubTextSearch'
        'githubTextSearch'
        'browser'
        'vscodeBrowser'
        'github'
        'useMcp'
        'codeInterpreter'
        'vscode/installExtension'
        'vscode/extensions'
        'web_fetch'
        'web_search'
        'WebFetch'
        'WebSearch'
    )
    $script:localNamespace = @('search', 'read', 'edit', 'execute', 'vscode')

    function script:Get-AgentTool
    {
        [CmdletBinding()]
        [OutputType([string[]])]
        param
        (
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string]$Path
        )

        $content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        $toolsLine = [regex]::Match($content, '(?m)^tools:\s*\[(.*)\]\r?$')

        if (-not $toolsLine.Success)
        {
            throw "No single-line tools list in '$Path'."
        }

        # Validate the whole list before extracting from it: an entry the
        # extraction cannot read would otherwise vanish from every check.
        if ($toolsLine.Groups[1].Value -notmatch "^\s*'[^']+'(?:\s*,\s*'[^']+')*\s*$")
        {
            throw "The tools list in '$Path' is not a non-empty list of single-quoted names, so it cannot be checked in full."
        }

        return [string[]] @(
            [regex]::Matches($toolsLine.Groups[1].Value, "'([^']+)'") |
                ForEach-Object -Process { $_.Groups[1].Value }
        )
    }

    function script:Test-NetworkTool
    {
        [CmdletBinding()]
        [OutputType([bool])]
        param
        (
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string]$Name
        )

        if ($Name -in $script:networkTool)
        {
            return $true
        }

        $segment = $Name -split '/'

        return ($segment[-1] -in $script:browserTool) -or
            ($segment.Count -gt 1 -and $segment[0] -notin $script:localNamespace)
    }
}

Describe 'Custom agent runtime tool names' -Tag 'Unit' {
    Context 'When any Custom agent keeps a VS Code tool name' {
        It 'Should declare the runtime name next to every VS Code name <Name> keeps' -ForEach $script:agentCase {
            $tool = script:Get-AgentTool -Path $Path

            $missing = @(
                foreach ($rule in $script:runtimeNameRule)
                {
                    if (-not @($rule.Source | Where-Object -FilterScript { $_ -in $tool }))
                    {
                        continue
                    }

                    foreach ($expected in $rule.Runtime)
                    {
                        if ($expected -notin $tool)
                        {
                            "$($rule.Label) -> $expected"
                        }
                    }
                }
            )

            $missing |
                Should -BeNullOrEmpty -Because "the agent-host runtime drops the VS Code name, so $Name loses the tool without the runtime name"
        }

        It 'Should name browser tools through the non-deprecated tool set in <Name>' -ForEach $script:agentCase {
            $tool = script:Get-AgentTool -Path $Path

            $misnamed = @(
                $tool | Where-Object -FilterScript {
                    ($_ -split '/')[-1] -in $script:browserTool -and $_ -notlike 'vscodeBrowser/*'
                }
            )

            $misnamed |
                Should -BeNullOrEmpty -Because 'a bare name is reported as renamed and the browser tool set is deprecated'
        }

        It 'Should list every tool in <Name> once' -ForEach $script:agentCase {
            $tool = script:Get-AgentTool -Path $Path

            @($tool | Group-Object | Where-Object -FilterScript { $_.Count -gt 1 }).Name |
                Should -BeNullOrEmpty -Because $Name
        }

        It 'Should never give <Name> a tool that creates, messages, renames, or deletes sessions' -ForEach $script:agentCase {
            $tool = script:Get-AgentTool -Path $Path

            @($tool | Where-Object -FilterScript { $_ -in $script:excludedSessionTool }) |
                Should -BeNullOrEmpty -Because $Name
        }
    }

    Context 'When a Custom agent is open to the network' {
        It 'Should give <Name> the common web, search, question, and session baseline' -ForEach $script:openCase {
            $tool = script:Get-AgentTool -Path $Path

            @($script:baselineTool | Where-Object -FilterScript { $_ -notin $tool }) |
                Should -BeNullOrEmpty -Because "$Name is not contained, so it needs the common baseline in agent-host sessions"
        }
    }

    Context 'When a Custom agent is contained' {
        It 'Should find the contained agent <Name>' -ForEach $script:containedNameCase {
            Test-Path -LiteralPath (Join-Path $script:agentsPath "$Name.agent.md") -PathType Leaf |
                Should -BeTrue -Because 'a renamed contained agent would silently lose its containment checks'
        }

        It 'Should keep <Name> free of every network tool under either naming' -ForEach $script:containedCase {
            $tool = script:Get-AgentTool -Path $Path

            @($tool | Where-Object -FilterScript { script:Test-NetworkTool -Name $_ }) |
                Should -BeNullOrEmpty -Because "$Name must declare no network tool under either naming"
        }

        It 'Should keep <Name> free of agent-host session tools' -ForEach $script:containedCase {
            $tool = script:Get-AgentTool -Path $Path

            @($tool | Where-Object -FilterScript { $_ -in $script:sessionTool }) |
                Should -BeNullOrEmpty -Because "$Name gets runtime names only for the VS Code names it already declares"
        }

        It 'Should declare a runtime name in <Name> only next to a VS Code name it already has' -ForEach $script:containedCase {
            $tool = script:Get-AgentTool -Path $Path

            $unpaired = @(
                foreach ($rule in $script:runtimeNameRule)
                {
                    if (@($rule.Source | Where-Object -FilterScript { $_ -in $tool }))
                    {
                        continue
                    }

                    $rule.Runtime | Where-Object -FilterScript { $_ -in $tool }
                }
            )

            $unpaired | Should -BeNullOrEmpty -Because "$Name may not gain a capability through a runtime name"
        }
    }
}

Describe 'Network tool classification' -Tag 'Unit' {
    It 'Should classify <Name> as a network tool' -ForEach @(
        @{ Name = 'web/fetch' }
        @{ Name = 'web_fetch' }
        @{ Name = 'web_search' }
        @{ Name = 'web/githubRepo' }
        @{ Name = 'github' }
        @{ Name = 'github/search_code' }
        @{ Name = 'useMcp' }
        @{ Name = 'browser' }
        @{ Name = 'openBrowserPage' }
        @{ Name = 'browser/readPage' }
        @{ Name = 'vscodeBrowser/runPlaywrightCode' }
        @{ Name = 'codeInterpreter' }
        @{ Name = 'vscode/installExtension' }
        @{ Name = 'vscode/extensions' }
        @{ Name = 'someMcpServer/someTool' }
    ) {
        script:Test-NetworkTool -Name $Name | Should -BeTrue
    }

    It 'Should not classify the local tool <Name> as a network tool' -ForEach @(
        @{ Name = 'grep' }
        @{ Name = 'glob' }
        @{ Name = 'ask_user' }
        @{ Name = 'search/textSearch' }
        @{ Name = 'read/readFile' }
        @{ Name = 'edit/editFiles' }
        @{ Name = 'execute/runInTerminal' }
        @{ Name = 'vscode/askQuestions' }
    ) {
        script:Test-NetworkTool -Name $Name | Should -BeFalse
    }
}

Describe 'Agent tool list parsing' -Tag 'Unit' {
    BeforeAll {
        function script:New-ToolListFixture
        {
            [CmdletBinding()]
            [OutputType([string])]
            param
            (
                [Parameter(Mandatory)]
                [string]$ToolsLine
            )

            $path = Join-Path $TestDrive ("{0}.agent.md" -f [guid]::NewGuid().ToString('N'))
            [System.IO.File]::WriteAllText(
                $path,
                "---`nname: fixture`ndescription: 'Fixture agent.'`n$ToolsLine`n---`n# Fixture`n",
                [System.Text.UTF8Encoding]::new($false))

            return $path
        }
    }

    It 'Should return every entry of a single-quoted list' {
        $path = script:New-ToolListFixture -ToolsLine "tools: ['grep', 'glob']"

        script:Get-AgentTool -Path $path | Should -Be @('grep', 'glob')
    }

    It 'Should refuse a list with a <Style> entry it cannot read in full' -ForEach @(
        @{ Style = 'double-quoted'; Line = "tools: ['grep', `"web_fetch`"]" }
        @{ Style = 'unquoted'; Line = "tools: ['grep', web_fetch]" }
    ) {
        <#
            A containment check that skips an entry it cannot parse passes on a
            truncated list, which is how a network tool would go unseen.
        #>
        $path = script:New-ToolListFixture -ToolsLine $Line

        { script:Get-AgentTool -Path $path } | Should -Throw -ExpectedMessage '*single-quoted*'
    }

    It 'Should refuse an empty list' {
        $path = script:New-ToolListFixture -ToolsLine 'tools: []'

        { script:Get-AgentTool -Path $path } | Should -Throw -ExpectedMessage '*single-quoted*'
    }
}
