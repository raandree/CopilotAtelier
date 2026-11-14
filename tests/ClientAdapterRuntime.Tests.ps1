<#
    Runs the model-free cases C1 and C2 of docs/client-adapter-evals.md against
    real Copilot runtimes, and re-checks the observation and the outcomes the
    client contract's committed receipt records for them.

    Get-ClientAdapterCaseVerdict in Helpers/ClientAdapterCase.ps1 decides both
    cases and names what the suite does not accept of a client. The two Unit
    blocks assert it in process, on what the runtimes recorded and on variations
    of it, and on the observation each committed receipt records, so the rule is
    checked on every system, also where no runtime is installed.

    Each run stages one artifact byte for byte in a scratch COPILOT_HOME: the
    composed Copilot CLI variant from output/clientAdapters on the standalone
    Copilot CLI, and the authoritative source profile on the runtime that VS Code
    bundles, which runs VS Code's agent-host chats.
    Fixtures/Invoke-CopilotSdkConversation.mjs starts the runtime with a loopback
    fake model and no sign-in, lists the agents the runtime discovered, selects
    the profile, and records the tools the runtime offers the model before and
    after the selection.

    What runs is the runtime's own agent discovery and the agent list and select
    calls that VS Code's agent host also makes. It is not the Copilot CLI's
    interactive /agent list and not local VS Code chat, so a receipt recorded
    from this suite covers neither.

    It needs Windows, node, and a VS Code installation that bundles
    @github/copilot-sdk-win32-x64; the Copilot CLI run also needs an installed
    CLI. Each run skips without what it needs, for example on a CI runner.
#>

BeforeDiscovery {
    $script:isWindowsPlatform = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
    $script:nodeAvailable = [bool](Get-Command -Name 'node' -CommandType Application -ErrorAction SilentlyContinue)
    $script:sdkPackageRoot = ''
    $script:cliPath = ''

    if ($script:isWindowsPlatform)
    {
        # The same lookup as tests/HookSdkRuntime.Tests.ps1: current VS Code builds install
        # under <install root>\<commit>\resources\app, older ones under <install root>\resources\app.
        $installRoots = @(
            $env:ProgramFiles
            ${env:ProgramFiles(x86)}
            if ($env:LOCALAPPDATA) { Join-Path -Path $env:LOCALAPPDATA -ChildPath 'Programs' }
        ) | Where-Object -FilterScript { $_ }

        $packagePattern = foreach ($installRoot in $installRoots)
        {
            foreach ($product in 'Microsoft VS Code', 'Microsoft VS Code Insiders')
            {
                foreach ($layout in '*\resources\app', 'resources\app')
                {
                    Join-Path -Path $installRoot -ChildPath "$product\$layout\node_modules.asar.unpacked\@github\copilot-sdk-win32-x64"
                }
            }
        }

        $script:sdkPackageRoot = @(
            Resolve-Path -Path $packagePattern -ErrorAction SilentlyContinue |
                ForEach-Object -Process { $_.ProviderPath } |
                Where-Object -FilterScript {
                    (Test-Path -LiteralPath (Join-Path -Path $_ -ChildPath 'copilot-sdk\index.js') -PathType Leaf) -and
                    (Test-Path -LiteralPath (Join-Path -Path $_ -ChildPath 'prebuilds\win32-x64\copilot-runtime.exe') -PathType Leaf)
                } |
                Sort-Object -Property { (Get-Item -LiteralPath (Join-Path -Path $_ -ChildPath 'package.json')).LastWriteTimeUtc } -Descending |
                Select-Object -First 1
        ) -join ''

        # VS Code puts its copilot launcher, bin\copilot-shim\copilot.exe, first on PATH and
        # it hands over to an installed CLI, so the CLI itself is taken, by its full path.
        $script:cliPath = @(
            Get-Command -Name 'copilot' -CommandType Application -ErrorAction SilentlyContinue |
                Where-Object -FilterScript { $_.Source -like '*.exe' -and (Split-Path -Path (Split-Path -Path $_.Source -Parent) -Leaf) -ne 'copilot-shim' } |
                Select-Object -ExpandProperty Source
            if ($env:LOCALAPPDATA)
            {
                Get-ChildItem -Path (Join-Path -Path $env:LOCALAPPDATA -ChildPath 'Microsoft\WinGet\Packages\GitHub.Copilot_*\copilot.exe') -ErrorAction SilentlyContinue |
                    Select-Object -ExpandProperty FullName
            }
        ) | Select-Object -First 1
    }

    $runtimeAvailable = $script:isWindowsPlatform -and $script:nodeAvailable -and [bool]$script:sdkPackageRoot

    $script:adapterRuns = @(
        @{
            Client      = 'vscode'
            Artifact    = 'the source profile'
            Runtime     = 'the runtime that VS Code bundles'
            RuntimePath = ''
            PackageRoot = $script:sdkPackageRoot
            Available   = $runtimeAvailable
        }
        @{
            Client      = 'copilot-cli'
            Artifact    = 'the composed variant'
            Runtime     = 'the standalone Copilot CLI'
            RuntimePath = [string] $script:cliPath
            PackageRoot = $script:sdkPackageRoot
            Available   = $runtimeAvailable -and [bool]$script:cliPath
        }
    )
}

Describe 'Rule of the model-free cases' -Tag 'Unit' {
    <#
        Get-ClientAdapterCaseVerdict decides C1 and C2 for the smoke cases below
        and names what they do not accept of a client. These cases assert it in
        process, on what runtime 1.0.108-0 recorded for the source profile and on
        the variations the re-review of 2026-11-13 and the review of 2026-11-14
        simulated, so the rule is checked where no runtime is installed, as on a
        CI runner.
    #>
    BeforeAll {
        . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers/ClientAdapterCase.ps1')

        # The tools the source profile declares and the runtime kept, cut short: no case here varies them.
        $script:sourceTool = @('agent', 'ask_user', 'edit/editFiles', 'execute/runInTerminal', 'glob', 'grep', 'read/readFile', 'todo', 'web_fetch')
        $script:recordedWarning = 'agents\software-engineer.agent.md: unknown fields ignored: argument-hint, agents, handoffs'
        $script:delegationTool = @('task', 'list_agents', 'read_agent', 'write_agent')
        $script:offeredByAgentHost = @(
            'ask_user', 'create', 'edit', 'glob', 'grep', 'list_agents', 'list_powershell', 'powershell', 'read_agent'
            'read_powershell', 'sql', 'stop_powershell', 'task', 'update_todo', 'view', 'web_fetch', 'write_agent'
        )

        function script:New-AgentHostObservation
        {
            param
            (
                [string[]] $LoadWarning = @($script:recordedWarning),

                [string[]] $OfferedWithAgent = $script:offeredByAgentHost
            )

            [pscustomobject] @{
                ListedAsUserAgent   = $true
                LoadError           = @()
                LoadWarning         = $LoadWarning
                LoadedTool          = $script:sourceTool
                OfferedWithoutAgent = @(
                    'ask_user', 'create', 'dynamic_workflows_manage', 'edit', 'glob', 'grep', 'list_agents', 'list_powershell'
                    'powershell', 'probe_tool', 'read_agent', 'read_powershell', 'run_dynamic_workflow', 'semantic_code_search'
                    'sql', 'stop_powershell', 'task', 'view', 'web_fetch', 'write_agent'
                )
                OfferedWithAgent    = $OfferedWithAgent
            }
        }
    }

    It 'fails C2 on the delegation the agent-host runtime offered while it warned that it ignores agents:' {
        $verdict = Get-ClientAdapterCaseVerdict -Client 'vscode' -DeclaredTool $script:sourceTool -Observation (script:New-AgentHostObservation)

        $verdict.Outcome.C2 | Should -BeExactly 'Failed'
        @($verdict.Check | Where-Object -FilterScript { $_.Case -eq 'C2' -and -not $_.Holds }).Name | Should -Be @('Delegation')
        $verdict.Violation | Should -BeNullOrEmpty -Because 'the VS Code receipt records this run, so the suite accepts it'
    }

    It 'fails C2 on delegation offered without a warning that names agents' {
        $observation = script:New-AgentHostObservation -LoadWarning 'agents\software-engineer.agent.md: unknown fields ignored: argument-hint, handoffs'

        $verdict = Get-ClientAdapterCaseVerdict -Client 'vscode' -DeclaredTool $script:sourceTool -Observation $observation

        $verdict.Outcome.C2 |
            Should -BeExactly 'Failed' -Because 'nothing shows the bound of task, list_agents, read_agent, and write_agent, whatever the runtime warns'
        @($verdict.Check | Where-Object -FilterScript { $_.Case -eq 'C2' -and -not $_.Holds }).Name | Should -Be @('Delegation')
    }

    It 'passes C2 and asks for no delegation tool when the runtime withholds delegation' {
        $observation = script:New-AgentHostObservation -OfferedWithAgent @($script:offeredByAgentHost | Where-Object -FilterScript { $_ -notin $script:delegationTool })

        $verdict = Get-ClientAdapterCaseVerdict -Client 'vscode' -DeclaredTool $script:sourceTool -Observation $observation

        $verdict.Outcome.C2 | Should -BeExactly 'Passed'
        $verdict.Violation | Should -BeNullOrEmpty -Because 'withholding delegation is the safe behaviour'
    }

    It 'fails C2 and the suite on a tool beyond those the VS Code client allows' {
        $offered = @($script:offeredByAgentHost | Where-Object -FilterScript { $_ -notin $script:delegationTool }) + 'web_search'
        $observation = script:New-AgentHostObservation -OfferedWithAgent $offered

        $verdict = Get-ClientAdapterCaseVerdict -Client 'vscode' -DeclaredTool $script:sourceTool -Observation $observation

        $verdict.Outcome.C2 | Should -BeExactly 'Failed' -Because 'the profile declares nothing that enables web_search'
        @($verdict.Check | Where-Object -FilterScript { $_.Case -eq 'C2' -and -not $_.Holds }).Name | Should -Be @('AllowList')
        @($verdict.Violation | Where-Object -Property Name -EQ -Value 'AllowList').Detail | Should -Match 'web_search'
    }

    It 'fails the suite on a load warning it does not expect' {
        $observation = script:New-AgentHostObservation -LoadWarning $script:recordedWarning, 'tool not found: useMcp'

        $verdict = Get-ClientAdapterCaseVerdict -Client 'vscode' -DeclaredTool $script:sourceTool -Observation $observation

        @($verdict.Violation).Name | Should -Be @('ExpectedWarning') -Because 'only the fields local VS Code chat alone reads may be ignored'
        @($verdict.Violation).Detail | Should -Match 'tool not found: useMcp'
    }

    It 'fails the suite on a load warning that carries other text before the notice it expects' {
        $combined = 'agents\software-engineer.agent.md: tool not found: useMcp; unknown fields ignored: argument-hint, agents, handoffs'
        $observation = script:New-AgentHostObservation -LoadWarning $combined

        $verdict = Get-ClientAdapterCaseVerdict -Client 'vscode' -DeclaredTool $script:sourceTool -Observation $observation

        @($verdict.Violation).Name | Should -Be @('ExpectedWarning') -Because 'the whole warning must be the notice of ignored fields'
        @($verdict.Violation).Detail | Should -Match 'tool not found: useMcp'
    }

    It 'fails the suite on a notice of ignored fields that names none' {
        $variantTool = @('ask_user', 'edit', 'execute', 'glob', 'grep', 'read', 'todo', 'web_fetch')
        $observation = [pscustomobject] @{
            ListedAsUserAgent   = $true
            LoadError           = @()
            LoadWarning         = @('agents\software-engineer.agent.md: unknown fields ignored: ,')
            LoadedTool          = $variantTool
            OfferedWithoutAgent = @('ask_user', 'create', 'edit', 'glob', 'grep', 'powershell', 'probe_tool', 'skill', 'sql', 'view', 'web_fetch')
            OfferedWithAgent    = @('ask_user', 'create', 'edit', 'glob', 'grep', 'powershell', 'skill', 'sql', 'view', 'web_fetch')
        }

        $verdict = Get-ClientAdapterCaseVerdict -Client 'copilot-cli' -DeclaredTool $variantTool -Observation $observation

        @($verdict.Violation).Name | Should -Be @('ExpectedWarning') -Because 'the composed variant may cause no warning at all'
    }

    It 'fails C2 and the suite when the composed variant is offered delegation' {
        $variantTool = @('ask_user', 'edit', 'execute', 'glob', 'grep', 'read', 'todo', 'web_fetch')
        $observation = [pscustomobject] @{
            ListedAsUserAgent   = $true
            LoadError           = @()
            LoadWarning         = @()
            LoadedTool          = $variantTool
            OfferedWithoutAgent = @('ask_user', 'create', 'edit', 'glob', 'grep', 'powershell', 'probe_tool', 'skill', 'sql', 'task', 'view', 'web_fetch')
            OfferedWithAgent    = @('ask_user', 'create', 'edit', 'glob', 'grep', 'powershell', 'skill', 'sql', 'task', 'view', 'web_fetch')
        }

        $verdict = Get-ClientAdapterCaseVerdict -Client 'copilot-cli' -DeclaredTool $variantTool -Observation $observation

        $verdict.Outcome.C2 | Should -BeExactly 'Failed'
        @($verdict.Violation).Name | Should -Contain 'Delegation' -Because 'the composed variant withholds delegation it cannot bound'
    }
}

Describe 'Committed runtime receipts' -Tag 'Unit' {
    BeforeAll {
        $script:projectPath = Convert-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..')
        . (Join-Path -Path $script:projectPath -ChildPath 'tests/Helpers/DeploymentProfile.ps1')
        . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers/ClientAdapterCase.ps1')
        Import-CopilotAtelierTestModule -ProjectPath $script:projectPath
    }

    It 'decides every runtime case the <Client> receipt records from the observation it records' -ForEach @(
        @{ Client = 'vscode' }
        @{ Client = 'copilot-cli' }
    ) {
        <#
            The smoke cases below need the runtimes. A receipt edited to record a
            pass that its own observation refutes fails here instead, on every
            system, and so does a claim of RuntimeVerified that rests on a receipt
            whose observation fails a case. A receipt that is not bound to the
            file a client loads claims nothing, so it is skipped.
        #>
        $adapter = Get-CopilotAtelierClientAdapter -Name 'software-engineer' -Client $Client -ContentPath $script:projectPath

        if ($adapter.RuntimeReceiptStatus -ne 'Bound')
        {
            Set-ItResult -Skipped -Because "the $Client receipt is $($adapter.RuntimeReceiptStatus) for the file a client loads"
            return
        }

        $receipt = $adapter.RuntimeReceipt
        $receipt.PSObject.Properties.Name | Should -Contain 'Observation' -Because 'a receipt records what its run observed'

        $verdict = Get-ClientAdapterCaseVerdict -Client $Client -DeclaredTool $adapter.Tool -Observation $receipt.Observation

        # Any letter case, so that a kind in another letter case cannot keep a case out of this check; the shape test pins the exact kind.
        foreach ($case in @($receipt.Case | Where-Object -Property Kind -EQ -Value 'Runtime'))
        {
            $verdict.Outcome[$case.Id] |
                Should -BeExactly $case.Outcome -Because "the receipt records $($case.Id) as $($case.Outcome), and its observation decides the case"
        }

        $verdict.Violation | Should -BeNullOrEmpty -Because 'a receipt is recorded only from a run the smoke suite accepts'

        if ($adapter.VerificationState -eq 'RuntimeVerified')
        {
            @($verdict.Outcome.Values | Where-Object -FilterScript { $_ -cne 'Passed' }) |
                Should -BeNullOrEmpty -Because "$Client may claim RuntimeVerified only while its receipt's observation passes every runtime case, C2 included"
        }
    }
}

Describe 'Client adapter smoke cases for <Client>' -Tag 'Integration' -ForEach $script:adapterRuns {
    Context '<Artifact> on <Runtime>' -Skip:(-not $Available) {
        BeforeAll {
            $projectPath = Convert-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..')
            . (Join-Path -Path $projectPath -ChildPath 'tests/Helpers/DeploymentProfile.ps1')
            . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers/ClientAdapterCase.ps1')
            Import-CopilotAtelierTestModule -ProjectPath $projectPath

            $utf8 = [Text.UTF8Encoding]::new($false)
            $script:agentName = 'software-engineer'
            $script:adapter = Get-CopilotAtelierClientAdapter -Name $script:agentName -Client $Client -ContentPath $projectPath

            # The file each case runs on: the build artifact for the composed variant, the
            # shipped profile itself for the authoritative client.
            $script:artifactPath = if ($Client -eq 'copilot-cli')
            {
                Join-Path -Path $projectPath -ChildPath "output/clientAdapters/copilot-cli/$($script:adapter.FileName)"
            }
            else
            {
                $script:adapter.SourcePath
            }

            if (-not (Test-Path -LiteralPath $script:artifactPath -PathType Leaf))
            {
                throw "The artifact '$script:artifactPath' does not exist. Run './build.ps1 -Tasks build' first."
            }

            $runRoot = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid().ToString('N'))
            $copilotHome = Join-Path -Path $runRoot -ChildPath 'copilot-home'
            $agentDirectory = Join-Path -Path $copilotHome -ChildPath 'agents'
            $workspace = Join-Path -Path $runRoot -ChildPath 'workspace'
            $null = New-Item -ItemType Directory -Path $agentDirectory, $workspace -Force

            $script:stagedPath = Join-Path -Path $agentDirectory -ChildPath $script:adapter.FileName
            [IO.File]::Copy($script:artifactPath, $script:stagedPath)
            $script:stagedSha256 = (Get-FileHash -LiteralPath $script:stagedPath -Algorithm SHA256).Hash.ToLowerInvariant()

            $hashProvider = [Security.Cryptography.SHA256]::Create()
            try
            {
                $script:composedSha256 = [BitConverter]::ToString($hashProvider.ComputeHash($utf8.GetBytes($script:adapter.Content))).Replace('-', '').ToLowerInvariant()
            }
            finally
            {
                $hashProvider.Dispose()
            }

            # Steps 2 and 4 are the turns whose model requests show the tools on offer.
            $steps = @(
                @{ op = 'newSession'; allTools = $true; userInput = $true }
                @{ op = 'listAgents' }
                @{ op = 'send'; prompt = 'turn without an agent'; noTool = $true }
                @{ op = 'selectAgent'; name = $script:agentName }
                @{ op = 'send'; prompt = 'turn with the agent'; noTool = $true }
                @{ op = 'disconnect' }
            )

            $startInfo = [Diagnostics.ProcessStartInfo]::new((Get-Command -Name 'node' -CommandType Application | Select-Object -First 1 -ExpandProperty Source))
            foreach ($argument in @((Join-Path -Path $PSScriptRoot -ChildPath 'Fixtures\Invoke-CopilotSdkConversation.mjs'), $PackageRoot, $copilotHome, $workspace, $RuntimePath))
            {
                $startInfo.Arguments += ' "' + $argument + '"'
            }

            $startInfo.UseShellExecute = $false
            $startInfo.CreateNoWindow = $true
            $startInfo.WorkingDirectory = $workspace
            $startInfo.RedirectStandardInput = $true
            $startInfo.RedirectStandardOutput = $true
            $startInfo.RedirectStandardError = $true
            $startInfo.StandardOutputEncoding = $utf8
            $startInfo.StandardErrorEncoding = $utf8

            # No sign-in must not depend on the caller: the runtime gets the scratch home and no token.
            foreach ($name in 'COPILOT_HOME', 'COPILOT_GITHUB_TOKEN', 'GH_TOKEN', 'GITHUB_TOKEN')
            {
                $null = $startInfo.Environment.Remove($name)
            }

            $process = [Diagnostics.Process]::Start($startInfo)
            try
            {
                $outputTask = $process.StandardOutput.ReadToEndAsync()
                $errorTask = $process.StandardError.ReadToEndAsync()
                $inputBytes = $utf8.GetBytes((ConvertTo-Json -InputObject $steps -Depth 6 -Compress))
                $process.StandardInput.BaseStream.Write($inputBytes, 0, $inputBytes.Length)
                $process.StandardInput.Close()

                # The fixture stops itself after 600 seconds; this only catches a stuck node and the runtime it started.
                if (-not $process.WaitForExit(660000))
                {
                    if ($PSVersionTable.PSVersion.Major -ge 7)
                    {
                        $process.Kill($true)
                    }
                    else
                    {
                        $process.Kill()
                    }

                    throw 'Invoke-CopilotSdkConversation.mjs did not exit within 660 seconds.'
                }

                $process.WaitForExit()
                if ($process.ExitCode -ne 0)
                {
                    throw ('Invoke-CopilotSdkConversation.mjs exited with {0}: {1}' -f $process.ExitCode, $errorTask.Result)
                }

                $script:run = $outputTask.Result | ConvertFrom-Json
            }
            finally
            {
                $process.Dispose()
            }

            $script:runtimeVersion = [string] $script:run.runtimeVersion
            $script:listed = @(
                @($script:run.steps | Where-Object -Property op -EQ -Value 'listAgents')[0].agents |
                    Where-Object -Property name -EQ -Value $script:agentName
            )
            $script:selected = @($script:run.steps | Where-Object -Property op -EQ -Value 'selectAgent')[0].agent
            $script:loading = @($script:run.events | Where-Object -Property type -EQ -Value 'session.custom_agents_updated')
            $script:loadError = @($script:loading | ForEach-Object -Process { @($_.errors) } | Where-Object -FilterScript { $_ })
            $script:loadWarning = @($script:loading | ForEach-Object -Process { @($_.warnings) } | Where-Object -FilterScript { $_ })
            $script:offeredWithout = @(@($script:run.requests | Where-Object -Property step -EQ -Value 2)[0].toolNames)
            $script:offeredWith = @(@($script:run.requests | Where-Object -Property step -EQ -Value 4)[0].toolNames)

            # What the run observed, in the shape a receipt records it; the helper decides both cases from it.
            $script:observation = [pscustomobject] @{
                ListedAsUserAgent   = $script:listed.Count -eq 1 -and
                    [IO.Path]::GetFullPath([string] $script:listed[0].path) -eq [IO.Path]::GetFullPath($script:stagedPath) -and
                    $script:listed[0].source -eq 'user'
                LoadError           = $script:loadError
                LoadWarning         = $script:loadWarning
                LoadedTool          = @($script:selected.tools | Sort-Object)
                OfferedWithoutAgent = @($script:offeredWithout | Sort-Object)
                OfferedWithAgent    = @($script:offeredWith | Sort-Object)
            }

            $script:verdict = Get-ClientAdapterCaseVerdict -Client $Client -DeclaredTool $script:adapter.Tool -Observation $script:observation
            $script:outcome = $script:verdict.Outcome

            Write-Information -InformationAction Continue -MessageData (
                '{0}: {1} at {2}, runtime version {3}; staged {4} (SHA-256 {5}); C1 {6}, C2 {7}; not accepted: {8}; load warnings: {9}; kept: {10}; offered without the agent: {11}; offered with it: {12}' -f
                $Client,
                $Runtime,
                $(if ($RuntimePath) { $RuntimePath } else { Join-Path -Path $PackageRoot -ChildPath 'prebuilds\win32-x64\copilot-runtime.exe' }),
                $script:runtimeVersion,
                $script:artifactPath,
                $script:stagedSha256,
                $script:outcome.C1,
                $script:outcome.C2,
                $(if ($script:verdict.Violation) { @($script:verdict.Violation | ForEach-Object -Process { $_.Name }) -join ', ' } else { 'none' }),
                $(if ($script:loadWarning) { $script:loadWarning -join ' | ' } else { 'none' }),
                ($script:observation.LoadedTool -join ', '),
                ($script:observation.OfferedWithoutAgent -join ', '),
                ($script:observation.OfferedWithAgent -join ', ')
            )
        }

        It 'reports the version of the runtime it ran' {
            $script:runtimeVersion | Should -Not -BeNullOrEmpty
        }

        It 'runs on the exact bytes the adapter composes and reports' {
            $script:stagedSha256 |
                Should -BeExactly $script:composedSha256 -Because "$script:artifactPath must be what Get-CopilotAtelierClientAdapter composes; rebuild when it is stale"
            $script:adapter.ArtifactSha256 |
                Should -BeExactly $script:stagedSha256 -Because 'a receipt binds to the SHA-256 the adapter reports for the file the cases ran on'
        }

        It 'C1: lists the profile from the scratch agents directory as a user agent' {
            $script:listed.Count | Should -Be 1
            [IO.Path]::GetFullPath([string] $script:listed[0].path) | Should -Be ([IO.Path]::GetFullPath($script:stagedPath))
            $script:listed[0].source | Should -BeExactly 'user'
        }

        It 'C1: loads the profile without a load error' {
            $script:loading | Should -Not -BeNullOrEmpty -Because 'the runtime reports agent loading in session.custom_agents_updated'
            $script:loadError | Should -BeNullOrEmpty
        }

        It 'C1: warns about nothing the suite does not expect of this client' {
            @($script:verdict.Violation | Where-Object -Property Name -EQ -Value 'ExpectedWarning').Detail |
                Should -BeNullOrEmpty -Because 'the composed variant emits only fields its client reads, and the source profile only fields local VS Code chat reads'
        }

        It 'C2: keeps exactly the tools the file declares' {
            @($script:selected.tools | Sort-Object) | Should -Be @($script:adapter.Tool | Sort-Object)
        }

        It 'C2: filters the session to the profile tools once it is selected' {
            $script:offeredWithout | Should -Contain 'probe_tool' -Because 'the session offers its own tool while no agent is selected'
            $script:offeredWith | Should -Not -Contain 'probe_tool' -Because 'the profile does not declare it'
        }

        It 'C2: offers the read, edit, execution, search, fetch, and question tools the workflow needs' {
            @($script:verdict.Violation | Where-Object -Property Name -EQ -Value 'WorkflowTool').Detail | Should -BeNullOrEmpty
        }

        It 'C2: offers nothing beyond the tools its client allows' {
            @($script:verdict.Violation | Where-Object -Property Name -EQ -Value 'AllowList').Detail |
                Should -BeNullOrEmpty -Because 'a tool the file cannot enable on this runtime fails C2 until a review adds it to the allow-list'
        }

        It 'C2: offers no delegation it cannot bound, or fails' {
            $delegation = $script:verdict.Check | Where-Object -Property Name -EQ -Value 'Delegation'

            if ($Client -eq 'copilot-cli')
            {
                $delegation.Detail | Should -BeNullOrEmpty -Because 'the composed variant withholds delegation it cannot bound'
                @($script:verdict.Violation | Where-Object -Property Name -EQ -Value 'ClientIdentifier').Detail |
                    Should -BeNullOrEmpty -Because 'no VS Code identifier and neither dead alias survives the composition'
            }
            elseif (-not $delegation.Holds)
            {
                # Nothing shows the bound, so any delegation tool offered to this client counts as unbounded.
                $script:outcome.C2 | Should -BeExactly 'Failed' -Because $delegation.Detail
            }
        }

        It 'reproduces the observation and the outcomes its committed receipt records' {
            $contract = InModuleScope CopilotAtelier { Get-CopilotAtelierClientContract }
            $receiptMap = $contract.Client[$Client].RuntimeReceipt
            $receipt = if ($receiptMap -and $receiptMap.Contains($script:agentName)) { $receiptMap[$script:agentName] }

            if (-not $receipt)
            {
                Set-ItResult -Skipped -Because "no receipt is committed for '$script:agentName' on $Client"
                return
            }

            if ($receipt.RuntimeVersion -cne $script:runtimeVersion)
            {
                Set-ItResult -Skipped -Because "the receipt records runtime $($receipt.RuntimeVersion), and this runtime reports $script:runtimeVersion"
                return
            }

            if ($receipt.ArtifactSha256 -cne $script:stagedSha256)
            {
                Set-ItResult -Skipped -Because "the receipt is bound to $($receipt.ArtifactSha256), and the file now hashes to $script:stagedSha256; run the cases again and record the new receipt"
                return
            }

            $receipt.PSObject.Properties.Name | Should -Contain 'Observation' -Because 'a receipt records what its run observed'

            foreach ($name in 'ListedAsUserAgent', 'LoadError', 'LoadWarning', 'LoadedTool', 'OfferedWithoutAgent', 'OfferedWithAgent')
            {
                (@($script:observation.$name | Sort-Object) -join ' | ') |
                    Should -BeExactly (@($receipt.Observation.$name | Sort-Object) -join ' | ') -Because "the receipt records $name as its run observed it"
            }

            # Any letter case, so that a kind in another letter case cannot keep a case out of this check; the shape test pins the exact kind.
            foreach ($case in @($receipt.Case | Where-Object -Property Kind -EQ -Value 'Runtime'))
            {
                $script:outcome[$case.Id] | Should -BeExactly $case.Outcome -Because "the receipt records $($case.Id) as $($case.Outcome)"
            }
        }
    }
}
