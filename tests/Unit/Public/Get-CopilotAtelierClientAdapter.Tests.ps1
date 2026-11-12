BeforeAll {
    $script:projectPath = Convert-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')
    . (Join-Path $script:projectPath 'tests/Helpers/DeploymentProfile.ps1')
    Import-CopilotAtelierTestModule -ProjectPath $script:projectPath

    function script:New-AgentFixture
    {
        [CmdletBinding()]
        [OutputType([string])]
        param
        (
            [Parameter(Mandatory)]
            [string]$Name,

            [Parameter(Mandatory)]
            [string[]]$Tool,

            [Parameter()]
            [string[]]$Subagent,

            [Parameter()]
            [string]$Body = "# Fixture`n`nDo the work.`n"
        )

        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $agentDirectory = Join-Path $root 'com.github.copilot/agents'
        New-Item -ItemType Directory -Path $agentDirectory -Force | Out-Null

        $line = [System.Collections.Generic.List[string]]::new()
        $line.Add('---')
        $line.Add("description: 'Fixture agent for adapter tests.'")
        $line.Add("name: $Name")
        $line.Add("model: ['Claude Opus 5 (copilot)', 'Claude Opus 4.8 (copilot)']")
        $line.Add('disable-model-invocation: true')
        $line.Add("argument-hint: 'Describe the task'")
        $line.Add("tools: [$(($Tool | ForEach-Object -Process { "'$_'" }) -join ', ')]")

        if ($Subagent)
        {
            $line.Add("agents: [$(($Subagent | ForEach-Object -Process { "'$_'" }) -join ', ')]")
        }

        $line.Add('---')

        $content = ($line -join "`n") + "`n" + $Body
        $path = Join-Path $agentDirectory "$Name.agent.md"
        [System.IO.File]::WriteAllText($path, $content, [System.Text.UTF8Encoding]::new($false))

        return $path
    }
}

Describe 'Client capability contract' -Tag 'Unit' {
    It 'Should name VS Code as the single authoritative source shape' {
        $contract = InModuleScope CopilotAtelier { Get-CopilotAtelierClientContract }

        $contract.AuthoritativeClient | Should -Be 'vscode'
        $contract.Client['vscode'].IsAuthoritativeSource | Should -BeTrue
        $contract.Client['copilot-cli'].IsAuthoritativeSource | Should -BeFalse
    }

    It 'Should record the verification state and tested client version for every client' {
        $contract = InModuleScope CopilotAtelier { Get-CopilotAtelierClientContract }

        foreach ($client in $contract.Client.Keys)
        {
            $entry = $contract.Client[$client]

            $entry.VerificationState |
                Should -BeIn @('RuntimeVerified', 'StructurallyChecked', 'Unverified', 'Unsupported') -Because $client
            $entry.DocumentationUri | Should -Not -BeNullOrEmpty -Because $client

            if ($entry.VerificationState -eq 'RuntimeVerified')
            {
                $entry.VerifiedClientVersion |
                    Should -Not -BeNullOrEmpty -Because 'a runtime claim names the version it was proven against'
            }
        }
    }

    It 'Should not claim runtime verification without an artifact-bound receipt' {
        <#
            An observation that one checkout's profile once loaded in one editor
            build is historical evidence about that file. It cannot travel with
            an arbitrary composed variant, so it is recorded separately and the
            emitted state stays structural.
        #>
        $contract = InModuleScope CopilotAtelier { Get-CopilotAtelierClientContract }

        foreach ($client in $contract.Client.Keys)
        {
            $entry = $contract.Client[$client]

            if ($entry.VerificationState -eq 'RuntimeVerified')
            {
                $entry.RuntimeReceipt |
                    Should -Not -BeNullOrEmpty -Because "$client claims a runtime state, so it must name the artifact-bound receipt that proves it"
            }
        }

        $observation = $contract.Client['vscode'].SourceProfileObservation

        $observation | Should -Not -BeNullOrEmpty -Because 'the historical VS Code observation is kept, but as source-profile evidence'
        $observation.Version | Should -Not -BeNullOrEmpty
        $observation.Scope | Should -Not -BeNullOrEmpty
    }

    It 'Should name the cases, the file hash, the runtime and its version, the date, and each outcome in every runtime receipt' {
        $contract = InModuleScope CopilotAtelier { Get-CopilotAtelierClientContract }

        foreach ($client in $contract.Client.Keys)
        {
            $receiptMap = $contract.Client[$client].RuntimeReceipt

            foreach ($agent in @($(if ($receiptMap) { $receiptMap.Keys })))
            {
                $receipt = $receiptMap[$agent]
                $label = "$client/$agent"

                $contract.AdaptedAgent.Contains($agent) | Should -BeTrue -Because "$label must belong to the adapted rollout"
                $receipt.Agent | Should -Be $agent -Because $label
                $receipt.Artifact | Should -Not -BeNullOrEmpty -Because $label
                $receipt.ArtifactSha256 | Should -MatchExactly '^[0-9a-f]{64}$' -Because "$label binds to one file by its lowercase SHA-256"
                $receipt.Runtime | Should -Not -BeNullOrEmpty -Because $label
                $receipt.RuntimeVersion | Should -Not -BeNullOrEmpty -Because $label
                $receipt.Harness | Should -Not -BeNullOrEmpty -Because "$label must say how to run the cases again"
                $receipt.NotCovered | Should -Not -BeNullOrEmpty -Because "$label must say what it does not cover"
                [datetime]::ParseExact($receipt.VerifiedOn, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture) |
                    Should -Not -BeNullOrEmpty -Because $label

                $case = @($receipt.Case)
                $case.Count | Should -BeGreaterThan 0 -Because $label
                @($case.Id | Select-Object -Unique).Count | Should -Be $case.Count -Because "$label records each case once"

                foreach ($entry in $case)
                {
                    $entry.Id | Should -MatchExactly '^[BC][1-9]$' -Because "$label names a case of docs/client-adapter-evals.md"
                    $entry.Kind | Should -BeIn @('Runtime', 'File') -Because "$label/$($entry.Id)"
                    $entry.Outcome | Should -BeIn @('Passed', 'Failed') -Because "$label/$($entry.Id)"
                    $entry.Evidence | Should -Not -BeNullOrEmpty -Because "$label/$($entry.Id)"
                }
            }
        }
    }

    It 'Should describe only the clients this adapter was scoped to' {
        $contract = InModuleScope CopilotAtelier { Get-CopilotAtelierClientContract }

        @($contract.Client.Keys) | Should -Be @('vscode', 'copilot-cli')

        foreach ($client in $contract.Client.Keys)
        {
            $contract.Client[$client].DisplayName |
                Should -Not -Match '(?i)cloud' -Because 'the scope is VS Code and the Copilot CLI; no cloud client was checked'
        }
    }

    It 'Should declare the documented model shape and the runtime tool vocabulary' {
        <#
            The Copilot CLI and cloud agent reference documents one model string,
            not the VS Code priority array. Its web and search aliases are
            documented too, but the runtime resolves neither to a tool
            (github/copilot-cli#4594), so the vocabulary is the exact names the
            offline probe saw enable a tool, plus todo, which enables nothing but
            costs nothing because the runtime always offers its sql tool.
        #>
        $contract = InModuleScope CopilotAtelier { Get-CopilotAtelierClientContract }
        $cli = $contract.Client['copilot-cli']

        $cli.ModelShape | Should -Be 'SingleString'
        $contract.Client['vscode'].ModelShape | Should -Be 'PriorityArray'

        $alias = @($cli.ToolMap.Values | Where-Object -FilterScript { $_ }) | Sort-Object -Unique

        foreach ($name in $alias)
        {
            $name |
                Should -BeIn @('agent', 'ask_user', 'edit', 'execute', 'glob', 'grep', 'read', 'todo', 'web_fetch') -Because 'only probe-verified runtime names and the todo alias may be emitted'
        }
    }

    It 'Should map the web and search identifiers to exact runtime names instead of dead aliases' {
        $contract = InModuleScope CopilotAtelier { Get-CopilotAtelierClientContract }
        $cli = $contract.Client['copilot-cli']

        foreach ($source in $cli.ToolMap.Keys)
        {
            @($cli.ToolMap[$source]) |
                Should -Not -Contain 'web' -Because "'$source' would reach an alias that enables no runtime tool"
            @($cli.ToolMap[$source]) |
                Should -Not -Contain 'search' -Because "'$source' would reach an alias that enables no runtime tool"
        }

        $cli.ToolMap['web/fetch'] | Should -Be 'web_fetch'
        $cli.ToolMap['web_fetch'] | Should -Be 'web_fetch'

        foreach ($source in @('search', 'search/fileSearch', 'search/listDirectory', 'search/textSearch'))
        {
            @($cli.ToolMap[$source]) |
                Should -Be @('grep', 'glob') -Because "the documented search alias stands for both, and '$source' keeps both"
        }

        $cli.ToolMap['grep'] | Should -Be 'grep'
        $cli.ToolMap['glob'] | Should -Be 'glob'
        $cli.ToolMap['ask_user'] | Should -Be 'ask_user'
    }

    It 'Should report every agent-host-only tool as unsupported with a reason' {
        <#
            The browser tools and the session tools exist only in VS Code
            agent-host sessions. The client has neither an integrated browser
            nor an agent-host session, so each is an explicit unsupported entry
            rather than a name the composition would reject or approximate.
        #>
        $contract = InModuleScope CopilotAtelier { Get-CopilotAtelierClientContract }
        $cli = $contract.Client['copilot-cli']

        $agentHostTool = @(
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
        ) | ForEach-Object -Process { "vscodeBrowser/$_" }

        $agentHostTool += @(
            'set_workspace'
            'list_sessions'
            'get_current_session'
            'get_session_context'
            'add_artifact_or_reference'
            'list_artifacts_and_references'
            'remove_artifact_or_reference'
        )

        foreach ($identifier in $agentHostTool)
        {
            $cli.ToolMap.Contains($identifier) | Should -BeTrue -Because "'$identifier' needs an explicit entry"
            $cli.ToolMap[$identifier] | Should -BeNullOrEmpty -Because "'$identifier' has no counterpart on this client"
            $cli.ToolUnsupportedReason[$identifier] |
                Should -Match '(?i)agent-host' -Because "'$identifier' is reported with the reason it is missing"
        }
    }

    It 'Should never map an unrestricted or read-only capability onto shell execution' {
        <#
            Making a workflow run by trading a narrow capability for terminal
            access is the failure this mapping exists to prevent. An execute/
            prefix is a product namespace, not proof of execution authority, so
            the grant is bound to an explicit list of executing tools.
        #>
        $contract = InModuleScope CopilotAtelier { Get-CopilotAtelierClientContract }
        $cli = $contract.Client['copilot-cli']

        foreach ($source in $cli.ToolMap.Keys)
        {
            if ('execute' -in @($cli.ToolMap[$source]))
            {
                $source |
                    Should -BeIn $cli.ExecutionSourceTool -Because "'$source' must not be widened to shell execution"
            }
        }

        @($cli.ExecutionSourceTool) | Should -Be @('execute/runInTerminal')
        $cli.ToolMap['execute/getTerminalOutput'] |
            Should -BeNullOrEmpty -Because 'reading an existing terminal buffer is not permission to start a command'
        $cli.ToolMap['useMcp'] | Should -BeNullOrEmpty
        $cli.ToolMap['runTests'] | Should -BeNullOrEmpty
    }

    It 'Should keep every mapping inside the capability class of its source identifier' {
        <#
            The same category error that turned terminal output into shell
            execution can happen to any prefix, so the whole map is checked
            against a declared class rather than one hand-picked rule.
        #>
        $contract = InModuleScope CopilotAtelier { Get-CopilotAtelierClientContract }
        $cli = $contract.Client['copilot-cli']

        foreach ($source in $cli.ToolMap.Keys)
        {
            $mapped = @($cli.ToolMap[$source] | Where-Object -FilterScript { $_ })

            if ($mapped.Count -eq 0)
            {
                continue
            }

            # An exact runtime name has no prefix, so it counts toward the
            # class that lists it rather than forming a class of its own.
            $owner = @(
                $cli.CapabilityClass.Keys |
                    Where-Object -FilterScript { $source -in @($cli.CapabilityClass[$_]) }
            )

            $class = if ($source -match '^(?<prefix>[a-z]+)/')
            {
                $Matches.prefix
            }
            elseif ($owner.Count -eq 1)
            {
                $owner[0]
            }
            else
            {
                $source
            }

            $cli.CapabilityClass.Contains($class) |
                Should -BeTrue -Because "'$source' maps to '$($mapped -join ', ')' without a declared capability class"

            foreach ($name in $mapped)
            {
                $name |
                    Should -BeIn @($cli.CapabilityClass[$class]) -Because "'$source' may only map inside its own capability class"
            }
        }
    }

    It 'Should count each exact runtime name toward exactly one capability class' {
        $contract = InModuleScope CopilotAtelier { Get-CopilotAtelierClientContract }
        $cli = $contract.Client['copilot-cli']

        $member = @(foreach ($class in $cli.CapabilityClass.Keys) { $cli.CapabilityClass[$class] })

        @($member | Group-Object | Where-Object -FilterScript { $_.Count -gt 1 }).Name |
            Should -BeNullOrEmpty -Because 'a runtime name that belonged to two classes could satisfy either one'

        @($cli.CapabilityClass['search']) | Should -Be @('grep', 'glob')
        @($cli.CapabilityClass['web']) | Should -Be @('web_fetch')
    }

    It 'Should declare the workflow modes the client cannot run' {
        $contract = InModuleScope CopilotAtelier { Get-CopilotAtelierClientContract }
        $cli = $contract.Client['copilot-cli']

        foreach ($workflow in @('review:on', 'cycle:full'))
        {
            $cli.Workflow[$workflow].Status | Should -Be 'Unsupported' -Because $workflow
            $cli.Workflow[$workflow].Reason | Should -Not -BeNullOrEmpty -Because $workflow
            $cli.Workflow[$workflow].ClientInstruction |
                Should -Match '(?i)refuse|return' -Because 'an unsupported required review must stop, not degrade to advice'
        }

        $cli.Workflow['bounded-default'].Status | Should -Be 'Supported'

        foreach ($workflow in $contract.Client['vscode'].Workflow.Keys)
        {
            $contract.Client['vscode'].Workflow[$workflow].Status | Should -Be 'Supported'
        }
    }
}

Describe 'Copilot CLI variant composition' -Tag 'Unit' {
    It 'Should reject a tool identifier that has no explicit mapping' {
        $path = script:New-AgentFixture -Name 'fixture-unknown' -Tool @('read/readFile', 'not/aRealTool')

        {
            InModuleScope CopilotAtelier -Parameters @{ Path = $path } {
                param ($Path)
                ConvertTo-CopilotAtelierClientAgent -Path $Path -Client 'copilot-cli'
            }
        } | Should -Throw -ExpectedMessage '*not/aRealTool*'
    }

    It 'Should fail when a required capability cannot be mapped' {
        $path = script:New-AgentFixture -Name 'fixture-required' -Tool @('read/readFile', 'search/textSearch')

        {
            InModuleScope CopilotAtelier -Parameters @{ Path = $path } {
                param ($Path)
                ConvertTo-CopilotAtelierClientAgent -Path $Path -Client 'copilot-cli' -RequiredCapability @('read', 'execute')
            }
        } | Should -Throw -ExpectedMessage '*execute*'
    }

    It 'Should not grant shell execution to a source profile that has none' {
        $path = script:New-AgentFixture -Name 'fixture-readonly' -Tool @('read/readFile', 'search/textSearch', 'runTests')

        $result = InModuleScope CopilotAtelier -Parameters @{ Path = $path } {
            param ($Path)
            ConvertTo-CopilotAtelierClientAgent -Path $Path -Client 'copilot-cli'
        }

        $result.Tool | Should -Not -Contain 'execute'
        $result.Tool | Should -Contain 'read'
        $result.Tool | Should -Contain 'grep'
        $result.Tool | Should -Contain 'glob'
        $result.Tool | Should -Not -Contain 'search' -Because 'the search alias enables no runtime tool'
    }

    It 'Should map web/fetch to the exact runtime fetch tool' {
        $path = script:New-AgentFixture -Name 'fixture-web' -Tool @('read/readFile', 'web/fetch')

        $result = InModuleScope CopilotAtelier -Parameters @{ Path = $path } {
            param ($Path)
            ConvertTo-CopilotAtelierClientAgent -Path $Path -Client 'copilot-cli'
        }

        @($result.Tool) | Should -Be @('read', 'web_fetch')
    }

    It 'Should keep the exact runtime names a profile declares next to its VS Code names' {
        $path = script:New-AgentFixture -Name 'fixture-runtime-names' -Tool @('vscode/askQuestions', 'ask_user', 'grep', 'glob', 'web_fetch')

        $result = InModuleScope CopilotAtelier -Parameters @{ Path = $path } {
            param ($Path)
            ConvertTo-CopilotAtelierClientAgent -Path $Path -Client 'copilot-cli'
        }

        @($result.Tool) | Should -Be @('ask_user', 'glob', 'grep', 'web_fetch')
        @($result.UnsupportedCapability | Where-Object -FilterScript { $_.Capability -eq 'vscode/askQuestions' }).Reason |
            Should -Match 'ask_user' -Because 'the unsupported VS Code name points at its runtime counterpart'
    }

    It 'Should report agent-host-only tools instead of emitting them' {
        $path = script:New-AgentFixture -Name 'fixture-agent-host' -Tool @('read/readFile', 'vscodeBrowser/openBrowserPage', 'set_workspace')

        $result = InModuleScope CopilotAtelier -Parameters @{ Path = $path } {
            param ($Path)
            ConvertTo-CopilotAtelierClientAgent -Path $Path -Client 'copilot-cli'
        }

        @($result.Tool) | Should -Be @('read')

        foreach ($identifier in @('vscodeBrowser/openBrowserPage', 'set_workspace'))
        {
            $reported = @($result.UnsupportedCapability | Where-Object -FilterScript { $_.Capability -eq $identifier })

            $reported | Should -Not -BeNullOrEmpty -Because $identifier
            $reported[0].Reason | Should -Match '(?i)agent-host' -Because $identifier
        }
    }

    It 'Should count exact runtime names toward a required capability class' {
        $path = script:New-AgentFixture -Name 'fixture-required-class' -Tool @('read/readFile', 'search/textSearch')

        $result = InModuleScope CopilotAtelier -Parameters @{ Path = $path } {
            param ($Path)
            ConvertTo-CopilotAtelierClientAgent -Path $Path -Client 'copilot-cli' -RequiredCapability @('read', 'search')
        }

        @($result.Tool) | Should -Be @('glob', 'grep', 'read')
    }

    It 'Should refuse a required capability class that is only partly emitted' {
        <#
            File-name search without content search is not the search the
            shared body depends on, so one runtime name of the class is not
            enough to pass the gate.
        #>
        $path = script:New-AgentFixture -Name 'fixture-partial-class' -Tool @('read/readFile', 'glob')

        {
            InModuleScope CopilotAtelier -Parameters @{ Path = $path } {
                param ($Path)
                ConvertTo-CopilotAtelierClientAgent -Path $Path -Client 'copilot-cli' -RequiredCapability @('read', 'search')
            }
        } | Should -Throw -ExpectedMessage '*search*'
    }

    It 'Should not grant shell execution to a profile that may only read terminal output' {
        <#
            The source profile can look at a terminal that already ran. Turning
            that into the client execute alias would hand it the authority to
            start any command it likes.
        #>
        $path = script:New-AgentFixture -Name 'fixture-terminal-reader' -Tool @('execute/getTerminalOutput', 'read/readFile', 'read/terminalLastCommand')

        $result = InModuleScope CopilotAtelier -Parameters @{ Path = $path } {
            param ($Path)
            ConvertTo-CopilotAtelierClientAgent -Path $Path -Client 'copilot-cli'
        }

        $result.Tool | Should -Not -Contain 'execute'
        $result.Tool | Should -Be @('read')

        $reported = @($result.UnsupportedCapability | Where-Object -FilterScript { $_.Capability -eq 'execute/getTerminalOutput' })

        $reported | Should -Not -BeNullOrEmpty
        $reported[0].Reason | Should -Match '(?i)execut'
    }

    It 'Should map a <Style> tool list to the same aliases' -ForEach @(
        @{ Style = 'single-quoted'; Line = "tools: ['read/readFile', 'edit/editFiles']" }
        @{ Style = 'double-quoted'; Line = 'tools: ["read/readFile", "edit/editFiles"]' }
        @{ Style = 'block sequence'; Line = "tools:`n  - read/readFile`n  - edit/editFiles" }
    ) {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $path = Join-Path $root 'fixture-style.agent.md'
        [System.IO.File]::WriteAllText(
            $path,
            "---`nname: fixture-style`ndescription: 'Fixture agent.'`n$Line`n---`n# Fixture`n",
            [System.Text.UTF8Encoding]::new($false))

        $result = InModuleScope CopilotAtelier -Parameters @{ Path = $path } {
            param ($Path)
            ConvertTo-CopilotAtelierClientAgent -Path $Path -Client 'copilot-cli'
        }

        @($result.Tool) | Should -Be @('edit', 'read')
    }

    It 'Should refuse a profile that carries an unknown top-level field' {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $path = Join-Path $root 'fixture-unknown-field.agent.md'
        [System.IO.File]::WriteAllText(
            $path,
            "---`nname: fixture-unknown-field`ndeny-tools: ['execute/runInTerminal']`ntools: ['read/readFile']`n---`n# Fixture`n",
            [System.Text.UTF8Encoding]::new($false))

        {
            InModuleScope CopilotAtelier -Parameters @{ Path = $path } {
                param ($Path)
                ConvertTo-CopilotAtelierClientAgent -Path $Path -Client 'copilot-cli'
            }
        } | Should -Throw -ExpectedMessage '*deny-tools*'
    }

    It 'Should emit a quoted scalar that survives a reparse unchanged' {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $path = Join-Path $root 'fixture-quoting.agent.md'
        [System.IO.File]::WriteAllText(
            $path,
            "---`nname: fixture-quoting`ndescription: 'Applies Bloom''s taxonomy: carefully.'`ntools: ['read/readFile']`n---`n# Fixture`n",
            [System.Text.UTF8Encoding]::new($false))

        $result = InModuleScope CopilotAtelier -Parameters @{ Path = $path } {
            param ($Path)
            ConvertTo-CopilotAtelierClientAgent -Path $Path -Client 'copilot-cli'
        }

        $result.Frontmatter['description'] | Should -BeExactly "Applies Bloom's taxonomy: carefully."
        $result.Content | Should -Match "description: 'Applies Bloom''s taxonomy: carefully\.'"
    }

    It 'Should compose a client-limitation preamble that refuses the unsupported workflows' {
        <#
            The report is not deployable content. A composed file that carries a
            body promising review dispatch and cycle handoffs must say, inside
            the file, that this client cannot run them.
        #>
        $body = "# Fixture`n`nRun the tests.`n"
        $path = script:New-AgentFixture -Name 'fixture-preamble' -Tool @('read/readFile', 'execute/runInTerminal') -Body $body

        $result = InModuleScope CopilotAtelier -Parameters @{ Path = $path } {
            param ($Path)
            ConvertTo-CopilotAtelierClientAgent -Path $Path -Client 'copilot-cli'
        }

        $result.Preamble | Should -Not -BeNullOrEmpty
        $result.Preamble | Should -Match 'review: on'
        $result.Preamble | Should -Match 'cycle: full'
        $result.Preamble | Should -Match '(?i)refuse'
        $result.Body | Should -BeExactly $body
        $result.Content | Should -Match '(?ms)client-limitations:begin.*client-limitations:end'
        $result.Content.EndsWith($body) |
            Should -BeTrue -Because 'the shared body stays authoritative and last'
    }

    It 'Should bind the preamble to the shared body with a hash the caller can check' {
        $path = script:New-AgentFixture -Name 'fixture-hash' -Tool @('read/readFile')

        $result = InModuleScope CopilotAtelier -Parameters @{ Path = $path } {
            param ($Path)
            ConvertTo-CopilotAtelierClientAgent -Path $Path -Client 'copilot-cli'
        }

        $expected = [System.BitConverter]::ToString(
            [System.Security.Cryptography.SHA256]::Create().ComputeHash(
                [System.Text.Encoding]::UTF8.GetBytes($result.Body))).Replace('-', '').ToLowerInvariant()

        $result.SharedBodyHash | Should -Be $expected
        $result.Content | Should -Match $expected
    }

    It 'Should report the workflow status the composed variant can honour' {
        $path = script:New-AgentFixture -Name 'fixture-workflow' -Tool @('read/readFile')

        $result = InModuleScope CopilotAtelier -Parameters @{ Path = $path } {
            param ($Path)
            ConvertTo-CopilotAtelierClientAgent -Path $Path -Client 'copilot-cli'
        }

        @($result.WorkflowCapability.Workflow) | Should -Contain 'review:on'
        @($result.WorkflowCapability | Where-Object -FilterScript { $_.Workflow -eq 'review:on' }).Status |
            Should -Be 'Unsupported'
        @($result.UnsupportedWorkflow) | Should -Contain 'cycle:full'
    }

    It 'Should withhold the variant when an explicitly required workflow is unsupported' {
        $path = script:New-AgentFixture -Name 'fixture-required-workflow' -Tool @('read/readFile', 'execute/runInTerminal')

        {
            InModuleScope CopilotAtelier -Parameters @{ Path = $path } {
                param ($Path)
                ConvertTo-CopilotAtelierClientAgent -Path $Path -Client 'copilot-cli' -RequiredWorkflow @('review:on')
            }
        } | Should -Throw -ExpectedMessage '*review:on*'
    }

    It 'Should withhold the agent tool when the subagent allow-list cannot be expressed' {
        <#
            The allow-list is a restriction. A client that cannot express which
            subagents may run must lose the ability to run them, never inherit
            unrestricted delegation.
        #>
        $path = script:New-AgentFixture -Name 'fixture-delegating' -Tool @('agent', 'read/readFile') -Subagent @('security-reviewer')

        $result = InModuleScope CopilotAtelier -Parameters @{ Path = $path } {
            param ($Path)
            ConvertTo-CopilotAtelierClientAgent -Path $Path -Client 'copilot-cli'
        }

        $result.Tool | Should -Not -Contain 'agent'
        $result.WithheldTool | Should -Contain 'agent'
        @($result.UnsupportedCapability | Where-Object -FilterScript { $_.Capability -eq 'agents' }).Kind |
            Should -Be 'Restriction'
    }

    It 'Should omit the model rather than invent a client model identifier' {
        $path = script:New-AgentFixture -Name 'fixture-model' -Tool @('read/readFile')

        $result = InModuleScope CopilotAtelier -Parameters @{ Path = $path } {
            param ($Path)
            ConvertTo-CopilotAtelierClientAgent -Path $Path -Client 'copilot-cli'
        }

        $result.Frontmatter.Contains('model') | Should -BeFalse
        @($result.UnsupportedCapability | Where-Object -FilterScript { $_.Capability -eq 'model' }) |
            Should -Not -BeNullOrEmpty
    }

    It 'Should report the VS Code-only fields it drops' {
        $path = script:New-AgentFixture -Name 'fixture-fields' -Tool @('read/readFile')

        $result = InModuleScope CopilotAtelier -Parameters @{ Path = $path } {
            param ($Path)
            ConvertTo-CopilotAtelierClientAgent -Path $Path -Client 'copilot-cli'
        }

        $reported = @($result.UnsupportedCapability.Capability)

        $reported | Should -Contain 'argument-hint'
        $result.Frontmatter.Contains('argument-hint') | Should -BeFalse
        $result.Frontmatter['target'] | Should -Be 'github-copilot'
    }

    It 'Should preserve the shared workflow body exactly' {
        $body = "# Fixture`n`nRun the tests.`n`n- One`n- Two`n"
        $path = script:New-AgentFixture -Name 'fixture-body' -Tool @('read/readFile') -Body $body

        $result = InModuleScope CopilotAtelier -Parameters @{ Path = $path } {
            param ($Path)
            ConvertTo-CopilotAtelierClientAgent -Path $Path -Client 'copilot-cli'
        }

        $result.Body | Should -BeExactly $body
    }

    It 'Should compose byte-identical content on repeated runs' {
        $path = script:New-AgentFixture -Name 'fixture-deterministic' -Tool @('read/readFile', 'edit/editFiles')

        $composed = InModuleScope CopilotAtelier -Parameters @{ Path = $path } {
            param ($Path)
            @(
                (ConvertTo-CopilotAtelierClientAgent -Path $Path -Client 'copilot-cli').Content
                (ConvertTo-CopilotAtelierClientAgent -Path $Path -Client 'copilot-cli').Content
            )
        }

        $composed[0] | Should -BeExactly $composed[1]
        $composed[0] | Should -Not -Match "`r"
    }

    It 'Should return the source unchanged for the authoritative client' {
        $path = script:New-AgentFixture -Name 'fixture-vscode' -Tool @('read/readFile', 'execute/runInTerminal')

        $result = InModuleScope CopilotAtelier -Parameters @{ Path = $path } {
            param ($Path)
            ConvertTo-CopilotAtelierClientAgent -Path $Path -Client 'vscode'
        }

        $result.Content | Should -BeExactly ([System.IO.File]::ReadAllText($path) -replace "`r`n", "`n")
        $result.UnsupportedCapability | Should -BeNullOrEmpty
        $result.Tool | Should -Contain 'execute/runInTerminal'
    }
}

Describe 'Runtime receipt binding' -Tag 'Unit' {
    BeforeAll {
        $script:boundHash = 'a' * 64

        function script:New-ClientContractFixture
        {
            [CmdletBinding()]
            [OutputType([pscustomobject])]
            param
            (
                [Parameter(Mandatory)]
                [object[]]$Case
            )

            [pscustomobject] @{
                VerificationState     = 'StructurallyChecked'
                VerifiedClientVersion = $null
                RuntimeReceipt        = [ordered] @{
                    'fixture-agent' = [pscustomobject] @{
                        Agent          = 'fixture-agent'
                        Artifact       = 'fixture-agent.agent.md'
                        ArtifactSha256 = $script:boundHash
                        Runtime        = 'Fixture runtime'
                        RuntimeVersion = '9.9.9'
                        VerifiedOn     = '2026-11-12'
                        Harness        = 'Fixture harness'
                        Case           = $Case
                        NotCovered     = 'Everything else.'
                    }
                }
            }
        }

        function script:New-CaseFixture
        {
            [CmdletBinding()]
            [OutputType([pscustomobject])]
            param
            (
                [Parameter(Mandatory)]
                [string]$Id,

                [Parameter(Mandatory)]
                [string]$Kind,

                [Parameter(Mandatory)]
                [string]$Outcome
            )

            [pscustomobject] @{ Id = $Id; Kind = $Kind; Outcome = $Outcome; Evidence = 'Fixture evidence.' }
        }
    }

    It 'Should report RuntimeVerified for the passed cases at the receipt version while the hash matches' {
        $clientContract = script:New-ClientContractFixture -Case @(
            (script:New-CaseFixture -Id 'C1' -Kind 'Runtime' -Outcome 'Failed')
            (script:New-CaseFixture -Id 'C2' -Kind 'Runtime' -Outcome 'Passed')
            (script:New-CaseFixture -Id 'C3' -Kind 'File' -Outcome 'Passed')
        )

        $result = InModuleScope CopilotAtelier -Parameters @{ ClientContract = $clientContract; Hash = $script:boundHash } {
            param ($ClientContract, $Hash)
            Resolve-CopilotAtelierClientVerification -ClientContract $ClientContract -Name 'fixture-agent' -ArtifactSha256 $Hash
        }

        $result.RuntimeReceiptStatus | Should -Be 'Bound'
        $result.VerificationState | Should -Be 'RuntimeVerified'
        $result.VerifiedClientVersion | Should -Be '9.9.9'
        $result.VerifiedCase | Should -Be @('C2', 'C3')
        $result.VerifiedCase | Should -Not -Contain 'C1' -Because 'a failed case is never reported as verified'
        $result.RuntimeReceipt.ArtifactSha256 | Should -Be $script:boundHash
    }

    It 'Should fall back to the client contract state once the hash differs' {
        $clientContract = script:New-ClientContractFixture -Case @(
            (script:New-CaseFixture -Id 'C2' -Kind 'Runtime' -Outcome 'Passed')
        )

        $result = InModuleScope CopilotAtelier -Parameters @{ ClientContract = $clientContract } {
            param ($ClientContract)
            Resolve-CopilotAtelierClientVerification -ClientContract $ClientContract -Name 'fixture-agent' -ArtifactSha256 ('b' * 64)
        }

        $result.RuntimeReceiptStatus | Should -Be 'Stale'
        $result.VerificationState | Should -Be 'StructurallyChecked'
        $result.VerifiedClientVersion | Should -BeNullOrEmpty
        $result.VerifiedCase | Should -BeNullOrEmpty
        $result.RuntimeReceipt | Should -BeNullOrEmpty
    }

    It 'Should report no receipt for an agent the contract has none for' {
        $clientContract = script:New-ClientContractFixture -Case @(
            (script:New-CaseFixture -Id 'C2' -Kind 'Runtime' -Outcome 'Passed')
        )

        $result = InModuleScope CopilotAtelier -Parameters @{ ClientContract = $clientContract; Hash = $script:boundHash } {
            param ($ClientContract, $Hash)
            Resolve-CopilotAtelierClientVerification -ClientContract $ClientContract -Name 'other-agent' -ArtifactSha256 $Hash
        }

        $result.RuntimeReceiptStatus | Should -Be 'None'
        $result.VerificationState | Should -Be 'StructurallyChecked'
        $result.RuntimeReceipt | Should -BeNullOrEmpty
    }

    It 'Should not raise the state to a runtime claim on cases that only read the file' {
        $clientContract = script:New-ClientContractFixture -Case @(
            (script:New-CaseFixture -Id 'C1' -Kind 'Runtime' -Outcome 'Failed')
            (script:New-CaseFixture -Id 'C3' -Kind 'File' -Outcome 'Passed')
        )

        $result = InModuleScope CopilotAtelier -Parameters @{ ClientContract = $clientContract; Hash = $script:boundHash } {
            param ($ClientContract, $Hash)
            Resolve-CopilotAtelierClientVerification -ClientContract $ClientContract -Name 'fixture-agent' -ArtifactSha256 $Hash
        }

        $result.RuntimeReceiptStatus | Should -Be 'Bound'
        $result.VerificationState | Should -Be 'StructurallyChecked'
        $result.VerifiedClientVersion | Should -BeNullOrEmpty
        $result.VerifiedCase | Should -Be @('C3')
    }
}

Describe 'Get-CopilotAtelierClientAdapter' -Tag 'Unit' {
    It 'Should report only the agents that have been adapted so far' {
        $result = @(Get-CopilotAtelierClientAdapter -Client 'copilot-cli')

        $result.Name | Should -Be @('software-engineer')
        $result.IsAdapted | Should -BeTrue
    }

    It 'Should report both clients for the representative profile' {
        $result = @(Get-CopilotAtelierClientAdapter -Name 'software-engineer')

        @($result.Client) | Should -Be @('vscode', 'copilot-cli')
    }

    It 'Should keep the VS Code profile authoritative and unmodified' {
        $result = Get-CopilotAtelierClientAdapter -Name 'software-engineer' -Client 'vscode'

        $result.IsAuthoritativeSource | Should -BeTrue
        $result.UnsupportedCapability | Should -BeNullOrEmpty
        $result.Preamble | Should -BeNullOrEmpty -Because 'the authoritative profile is returned untouched'
        $result.Content |
            Should -BeExactly ([System.IO.File]::ReadAllText($result.SourcePath) -replace "`r`n", "`n")
    }

    It 'Should fall back to StructurallyChecked once the file no longer matches its runtime receipt' {
        <#
            A receipt is evidence about the bytes its cases ran on. An edited
            profile is another file, about which the receipt proves nothing, so
            the claim falls back on its own instead of waiting for someone to
            remember the receipt.
        #>
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $agentDirectory = Join-Path $root 'com.github.copilot/agents'
        New-Item -ItemType Directory -Path $agentDirectory -Force | Out-Null

        $shipped = (Get-CopilotAtelierClientAdapter -Name 'software-engineer' -Client 'vscode').SourcePath
        $edited = ([System.IO.File]::ReadAllText($shipped) -replace "`r`n", "`n") + "`nOne line added after the cases ran.`n"
        [System.IO.File]::WriteAllText((Join-Path $agentDirectory 'software-engineer.agent.md'), $edited, [System.Text.UTF8Encoding]::new($false))

        foreach ($result in @(Get-CopilotAtelierClientAdapter -Name 'software-engineer' -ContentPath $root))
        {
            $result.RuntimeReceiptStatus |
                Should -Be 'Stale' -Because "$($result.Client) has a receipt for the shipped file, and this file is not that one"
            $result.VerificationState | Should -Be 'StructurallyChecked' -Because $result.Client
            $result.VerifiedClientVersion | Should -BeNullOrEmpty -Because $result.Client
            $result.VerifiedCase | Should -BeNullOrEmpty -Because $result.Client
            $result.RuntimeReceipt | Should -BeNullOrEmpty -Because $result.Client
        }
    }

    It 'Should back every runtime claim about the shipped profile with a receipt bound to its exact bytes' {
        <#
            This holds whether the committed receipt is current or stale: a
            bound receipt licenses the claim, and anything else falls back.
        #>
        foreach ($result in @(Get-CopilotAtelierClientAdapter -Name 'software-engineer'))
        {
            $expectedHash = [System.BitConverter]::ToString(
                [System.Security.Cryptography.SHA256]::Create().ComputeHash(
                    [System.Text.UTF8Encoding]::new($false).GetBytes($result.Content))).Replace('-', '').ToLowerInvariant()

            $result.ArtifactSha256 | Should -Be $expectedHash -Because "$($result.Client) reports the hash of the content it returns"

            if ($result.VerificationState -eq 'RuntimeVerified')
            {
                $result.RuntimeReceiptStatus | Should -Be 'Bound' -Because $result.Client
                $result.RuntimeReceipt.ArtifactSha256 | Should -Be $result.ArtifactSha256 -Because $result.Client
                $result.VerifiedClientVersion | Should -Be $result.RuntimeReceipt.RuntimeVersion -Because $result.Client

                $passed = @($result.RuntimeReceipt.Case | Where-Object -FilterScript { $_.Outcome -eq 'Passed' } | ForEach-Object -Process { $_.Id })
                $result.VerifiedCase | Should -Not -BeNullOrEmpty -Because $result.Client
                $result.VerifiedCase | Should -Be $passed -Because "$($result.Client) verifies exactly the cases its receipt records as passed"
            }
            else
            {
                $result.VerificationState | Should -Be 'StructurallyChecked' -Because $result.Client
                $result.VerifiedClientVersion | Should -BeNullOrEmpty -Because $result.Client
            }
        }
    }

    It 'Should refuse an explicitly required workflow the client cannot run' {
        { Get-CopilotAtelierClientAdapter -Name 'software-engineer' -Client 'copilot-cli' -RequiredWorkflow 'cycle:full' } |
            Should -Throw -ExpectedMessage '*cycle:full*'
    }

    It 'Should refuse an agent that is outside the adapted rollout' {
        { Get-CopilotAtelierClientAdapter -Name 'technical-writer' -Client 'copilot-cli' } |
            Should -Throw -ExpectedMessage '*technical-writer*'
    }
}
