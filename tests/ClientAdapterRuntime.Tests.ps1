<#
    Runs the model-free cases C1 and C2 of docs/client-adapter-evals.md against
    real Copilot runtimes, and re-checks the outcomes the client contract's
    committed receipt records for them.

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

Describe 'Client adapter smoke cases for <Client>' -Tag 'Integration' -ForEach $script:adapterRuns {
    Context '<Artifact> on <Runtime>' -Skip:(-not $Available) {
        BeforeAll {
            $projectPath = Convert-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..')
            . (Join-Path -Path $projectPath -ChildPath 'tests/Helpers/DeploymentProfile.ps1')
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

            # The runtime names of read, edit, execute, search, fetch, and ask_user on Windows.
            $script:workflowTool = @('view', 'edit', 'create', 'powershell', 'grep', 'glob', 'web_fetch', 'ask_user')
            $script:delegationTool = @('task', 'list_agents', 'read_agent', 'write_agent')

            # Everything the composed variant's eight entries can enable, plus the tools the runtime always offers.
            $script:cliAllowedTool = @(
                'ask_user', 'view', 'edit', 'create', 'grep', 'glob', 'web_fetch'
                'powershell', 'read_powershell', 'write_powershell', 'list_powershell', 'stop_powershell'
                'update_todo', 'skill', 'sql'
            )

            # The fields the source profile carries for local VS Code chat only; nothing else may be ignored.
            $script:vsCodeOnlyField = @('agents', 'argument-hint', 'handoffs')

            $script:ignoredField = @(
                foreach ($warning in $script:loadWarning)
                {
                    if ($warning -match 'unknown fields? ignored:\s*(?<field>.+)$')
                    {
                        $Matches['field'] -split ',' | ForEach-Object -Process { $_.Trim() } | Where-Object -FilterScript { $_ }
                    }
                }
            ) | Sort-Object

            $script:isListedFromScratch = $script:listed.Count -eq 1 -and
                [IO.Path]::GetFullPath([string] $script:listed[0].path) -eq [IO.Path]::GetFullPath($script:stagedPath) -and
                $script:listed[0].source -eq 'user'

            $loadedTool = @($script:selected.tools | Sort-Object)
            $declaredTool = @($script:adapter.Tool | Sort-Object)
            $script:delegationOffered = @($script:offeredWith | Where-Object -FilterScript { $_ -in $script:delegationTool })
            $script:isAllowListIgnored = 'agents' -in $script:ignoredField

            $c2Holds = ($loadedTool -join ',') -eq ($declaredTool -join ',') -and
                'probe_tool' -in $script:offeredWithout -and
                'probe_tool' -notin $script:offeredWith -and
                @($script:workflowTool | Where-Object -FilterScript { $_ -notin $script:offeredWith }).Count -eq 0

            if ($Client -eq 'copilot-cli')
            {
                # C2 also requires the delegation tool withheld, nothing beyond the mapped tools, no VS Code
                # identifier, and neither dead alias.
                $c2Holds = $c2Holds -and $script:delegationOffered.Count -eq 0 -and
                    @($script:offeredWith | Where-Object -FilterScript { $_ -notin $script:cliAllowedTool }).Count -eq 0 -and
                    @($loadedTool | Where-Object -FilterScript { $_ -match '/' -or $_ -in @('web', 'search') }).Count -eq 0
            }
            else
            {
                # Delegation without its agents: allow-list is a privilege widening, so it fails C2.
                $c2Holds = $c2Holds -and -not ($script:isAllowListIgnored -and $script:delegationOffered.Count -gt 0)
            }

            $script:outcome = [ordered] @{
                C1 = if ($script:isListedFromScratch -and $script:loadError.Count -eq 0 -and $script:loadWarning.Count -eq 0) { 'Passed' } else { 'Failed' }
                C2 = if ($c2Holds) { 'Passed' } else { 'Failed' }
            }

            Write-Information -InformationAction Continue -MessageData (
                '{0}: {1} at {2}, runtime version {3}; staged {4} (SHA-256 {5}); C1 {6}, C2 {7}; load warnings: {8}; offered without the agent: {9}; offered with it: {10}' -f
                $Client,
                $Runtime,
                $(if ($RuntimePath) { $RuntimePath } else { Join-Path -Path $PackageRoot -ChildPath 'prebuilds\win32-x64\copilot-runtime.exe' }),
                $script:runtimeVersion,
                $script:artifactPath,
                $script:stagedSha256,
                $script:outcome.C1,
                $script:outcome.C2,
                $(if ($script:loadWarning) { $script:loadWarning -join ' | ' } else { 'none' }),
                (@($script:offeredWithout | Sort-Object) -join ', '),
                (@($script:offeredWith | Sort-Object) -join ', ')
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

        It 'C1: warns about nothing but the fields only local VS Code chat reads' {
            if ($Client -eq 'copilot-cli')
            {
                $script:loadWarning | Should -BeNullOrEmpty -Because 'the composed variant emits only fields the client reads'
            }
            else
            {
                ($script:ignoredField -join ',') |
                    Should -BeExactly ($script:vsCodeOnlyField -join ',') -Because 'a newly ignored field, or one the runtime starts to read, changes what the receipt shows'
            }
        }

        It 'C2: keeps exactly the tools the file declares' {
            @($script:selected.tools | Sort-Object) | Should -Be @($script:adapter.Tool | Sort-Object)
        }

        It 'C2: filters the session to the profile tools once it is selected' {
            $script:offeredWithout | Should -Contain 'probe_tool' -Because 'the session offers its own tool while no agent is selected'
            $script:offeredWith | Should -Not -Contain 'probe_tool' -Because 'the profile does not declare it'
        }

        It 'C2: offers the read, edit, execution, search, fetch, and question tools the workflow needs' {
            foreach ($name in $script:workflowTool)
            {
                $script:offeredWith | Should -Contain $name
            }
        }

        It 'C2: offers delegation only where the profile can bound it' {
            if ($Client -eq 'copilot-cli')
            {
                foreach ($name in $script:delegationTool)
                {
                    $script:offeredWith | Should -Not -Contain $name -Because 'the composed variant withholds delegation it cannot bound'
                }

                @($script:offeredWith | Where-Object -FilterScript { $_ -notin $script:cliAllowedTool }) |
                    Should -BeNullOrEmpty -Because 'nothing beyond the mapped tools and the tools the runtime always offers'
                @($script:selected.tools | Where-Object -FilterScript { $_ -match '/' }) |
                    Should -BeNullOrEmpty -Because 'no VS Code identifier survives the composition'
                $script:selected.tools | Should -Not -Contain 'web'
                $script:selected.tools | Should -Not -Contain 'search'
            }
            elseif ($script:isAllowListIgnored -and $script:delegationOffered.Count -gt 0)
            {
                $script:outcome.C2 |
                    Should -BeExactly 'Failed' -Because "the runtime ignores agents: and still offers $($script:delegationOffered -join ', '), which is delegation without its bound"
            }
            else
            {
                $script:offeredWith | Should -Contain 'task' -Because 'the source profile declares agent, and its allow-list is honoured'
            }
        }

        It 'reproduces the outcome of every runtime case its committed receipt records' {
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

            foreach ($case in @($receipt.Case | Where-Object -Property Kind -EQ -Value 'Runtime'))
            {
                $script:outcome[$case.Id] | Should -BeExactly $case.Outcome -Because "the receipt records $($case.Id) as $($case.Outcome)"
            }
        }
    }
}
