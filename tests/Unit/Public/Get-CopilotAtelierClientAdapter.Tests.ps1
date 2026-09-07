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

    It 'Should describe only the clients this adapter was scoped to' {
        $contract = InModuleScope CopilotAtelier { Get-CopilotAtelierClientContract }

        @($contract.Client.Keys) | Should -Be @('vscode', 'copilot-cli')

        foreach ($client in $contract.Client.Keys)
        {
            $contract.Client[$client].DisplayName |
                Should -Not -Match '(?i)cloud' -Because 'the scope is VS Code and the Copilot CLI; no cloud client was checked'
        }
    }

    It 'Should declare the documented Copilot CLI model shape and tool vocabulary' {
        <#
            The Copilot CLI and cloud agent reference documents one model string,
            not the VS Code priority array, and a closed set of tool aliases.
        #>
        $contract = InModuleScope CopilotAtelier { Get-CopilotAtelierClientContract }
        $cli = $contract.Client['copilot-cli']

        $cli.ModelShape | Should -Be 'SingleString'
        $contract.Client['vscode'].ModelShape | Should -Be 'PriorityArray'

        $alias = @($cli.ToolMap.Values | Where-Object -FilterScript { $_ }) | Sort-Object -Unique

        foreach ($name in $alias)
        {
            $name |
                Should -BeIn @('agent', 'edit', 'execute', 'read', 'search', 'todo', 'web') -Because 'only documented aliases may be emitted'
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
            if ($cli.ToolMap[$source] -eq 'execute')
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
            $mapped = $cli.ToolMap[$source]

            if (-not $mapped)
            {
                continue
            }

            $class = if ($source -match '^(?<prefix>[a-z]+)/')
            {
                $Matches.prefix
            }
            else
            {
                $source
            }

            $cli.CapabilityClass.Contains($class) |
                Should -BeTrue -Because "'$source' maps to '$mapped' without a declared capability class"
            $mapped |
                Should -Be $cli.CapabilityClass[$class] -Because "'$source' may only map inside its own capability class"
        }
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
        $result.Tool | Should -Contain 'search'
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

    It 'Should never report a runtime state for a composed variant' {
        foreach ($result in @(Get-CopilotAtelierClientAdapter -Name 'software-engineer'))
        {
            $result.VerificationState |
                Should -Be 'StructurallyChecked' -Because "$($result.Client) has no artifact-bound runtime receipt"
            $result.VerifiedClientVersion | Should -BeNullOrEmpty -Because $result.Client
        }
    }

    It 'Should refuse an explicitly required workflow the client cannot run' {
        { Get-CopilotAtelierClientAdapter -Name 'software-engineer' -Client 'copilot-cli' -RequiredWorkflow 'cycle:full' } |
            Should -Throw -ExpectedMessage '*cycle:full*'
    }

    It 'Should not claim runtime verification for a client that was never run' {
        $result = Get-CopilotAtelierClientAdapter -Name 'software-engineer' -Client 'copilot-cli'

        $result.VerificationState | Should -Be 'StructurallyChecked'
    }

    It 'Should refuse an agent that is outside the adapted rollout' {
        { Get-CopilotAtelierClientAdapter -Name 'technical-writer' -Client 'copilot-cli' } |
            Should -Throw -ExpectedMessage '*technical-writer*'
    }
}
