BeforeDiscovery {
    $projectPath = Convert-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..')
    $workflowPath = Join-Path -Path $projectPath -ChildPath '.github/workflows'

    $script:workflowTestCase = @(
        Get-ChildItem -Path $workflowPath -Filter '*.yml' -File -ErrorAction SilentlyContinue |
            ForEach-Object -Process {
                @{
                    Name = $_.Name
                    Path = $_.FullName
                }
            }
    )

    $script:pwshAvailable = $null -ne (Get-Command -Name 'pwsh' -CommandType 'Application' -ErrorAction 'SilentlyContinue')
}

BeforeAll {
    Import-Module -Name powershell-yaml -ErrorAction Stop

    $script:workflowPath = Join-Path -Path (
        Convert-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..')
    ) -ChildPath '.github/workflows'
}

Describe 'GitHub Actions workflows' -Tag 'Unit' {
    It 'Should ship at least one workflow' {
        @(Get-ChildItem -Path $script:workflowPath -Filter '*.yml' -File -ErrorAction SilentlyContinue) |
            Should -Not -BeNullOrEmpty
    }

    It 'Should parse <Name> as YAML' -ForEach $script:workflowTestCase {
        { ConvertFrom-Yaml -Yaml (Get-Content -LiteralPath $Path -Raw) } | Should -Not -Throw
    }

    It 'Should keep expressions out of every step shell in <Name>' -ForEach $script:workflowTestCase {
        <#
            GitHub rejects the whole workflow file with "Unrecognized named-value"
            when a step's shell key holds an expression: shell is absent from the
            contexts-availability table for jobs.<job_id>.steps. Parameterise it
            through jobs.<job_id>.defaults.run instead, which does accept matrix.
        #>
        $workflow = ConvertFrom-Yaml -Yaml (Get-Content -LiteralPath $Path -Raw)

        $offendingStep = foreach ($jobName in $workflow.jobs.Keys)
        {
            foreach ($step in @($workflow.jobs[$jobName].steps))
            {
                if ($step.shell -and $step.shell -match '\$\{\{')
                {
                    '{0} -> {1}' -f $jobName, $step.name
                }
            }
        }

        $offendingStep | Should -BeNullOrEmpty -Because 'a step shell must be a literal; use jobs.<job_id>.defaults.run for a matrix-driven shell'
    }

    It 'Should validate topic branch pushes without allowing topic branch deployment' {
        $workflow = ConvertFrom-Yaml -Yaml (
            Get-Content -LiteralPath (Join-Path $script:workflowPath 'ci.yml') -Raw
        )
        $workflow.on.push.branches | Should -Contain 'ai/**'
        $workflow.on.push.branches | Should -Contain 'main'
        $workflow.permissions.contents | Should -BeExactly 'read'
        @($workflow.jobs.test.strategy.matrix.include) | Should -HaveCount 3
        $workflow.jobs.deploy.if.Trim() | Should -BeExactly (
            "github.repository_owner == 'raandree' && " +
            "needs.select.outputs.publish == 'true' && " +
            "(github.ref == 'refs/heads/main' || startsWith(github.ref, 'refs/tags/'))"
        )
        $workflow.jobs.deploy.needs | Should -Contain 'build'
        $workflow.jobs.deploy.needs | Should -Contain 'test'
        $workflow.jobs.deploy.needs | Should -Contain 'select'
        $workflow.on.push.Keys | Should -Not -Contain 'paths-ignore'
        $workflow.on.push.tags | Should -Contain 'v*'
        $workflow.on.push.tags | Should -Contain '!v*-*'
    }

    It 'Should cancel superseded topic runs without cancelling main or release runs' {
        $workflow = ConvertFrom-Yaml -Yaml (Get-Content -LiteralPath (Join-Path $script:workflowPath 'ci.yml') -Raw)
        $workflow.concurrency.group | Should -BeExactly (
            '${{ github.workflow }}-${{ github.event_name }}-${{ github.event.pull_request.number || github.ref }}')
        $workflow.concurrency['cancel-in-progress'] | Should -BeExactly (
            "`${{ github.event_name == 'pull_request' || startsWith(github.ref, 'refs/heads/ai/') }}")
    }

    It 'Should bind the build and publication gates to the admission job outputs' {
        $workflow = ConvertFrom-Yaml -Yaml (Get-Content -LiteralPath (Join-Path $script:workflowPath 'ci.yml') -Raw)
        $workflow.jobs.build.needs | Should -Contain 'select'
        $workflow.jobs.build.if | Should -BeExactly "needs.select.outputs.run_ci == 'true'"
        $workflow.jobs.select.outputs.run_ci | Should -BeExactly '${{ steps.decision.outputs.run_ci }}'
        $workflow.jobs.select.outputs.publish | Should -BeExactly '${{ steps.decision.outputs.publish }}'
        $workflow.jobs.select.permissions.contents | Should -BeExactly 'read'
        $workflow.jobs.select.permissions['pull-requests'] | Should -BeExactly 'read'
        $checkout = @($workflow.jobs.select.steps | Where-Object { $_.uses -like 'actions/checkout@*' })
        $checkout | Should -HaveCount 1
        $checkout[0].with['fetch-depth'] | Should -Be 0
        $checkout[0].with['persist-credentials'] | Should -BeFalse
    }

    It 'Should retain hidden ownership metadata in the output build artifact' {
        $workflow = ConvertFrom-Yaml -Yaml (
            Get-Content -LiteralPath (Join-Path -Path $script:workflowPath -ChildPath 'ci.yml') -Raw
        )

        $artifactStep = @(
            $workflow.jobs['build'].steps |
                Where-Object -FilterScript { $_.uses -like 'actions/upload-artifact@*' }
        )

        $artifactStep | Should -HaveCount 1
        $artifactStep[0].with.path | Should -BeExactly 'output/'
        $artifactStep[0].with['include-hidden-files'] |
            Should -BeTrue -Because 'downstream tests require the hidden client-adapter ownership manifest'
    }

    It 'Should run the complete suite on a Windows runner' {
        <#
            The hook launchers once failed only on Windows, where HOME is unset,
            and only in the branch VS Code never runs there. A POSIX leg, or a
            leg filtered by tag, cannot reach that failure or the Windows-only
            launcher cases in tests/HookLauncher.Tests.ps1.
        #>
        $workflow = ConvertFrom-Yaml -Yaml (
            Get-Content -LiteralPath (Join-Path -Path $script:workflowPath -ChildPath 'ci.yml') -Raw
        )

        $windowsLeg = @(
            $workflow.jobs.test.strategy.matrix.include |
                Where-Object -FilterScript { $_.os -like 'windows-*' -and $_.arguments -notmatch '-Pester\w+' }
        )

        $windowsLeg | Should -Not -BeNullOrEmpty -Because 'one Windows leg must run every test without a tag filter'
    }

    It 'Should verify the release secrets before publishing' {
        <#
            Publish_Release_To_GitHub skips itself when GitHubToken is empty while
            Publish_Module_To_gallery still runs, which ships a Gallery version
            without the v* tag GitVersion anchors the next pre-release number on.
        #>
        $workflow = ConvertFrom-Yaml -Yaml (
            Get-Content -LiteralPath (Join-Path -Path $script:workflowPath -ChildPath 'ci.yml') -Raw
        )

        $deployStep = @($workflow.jobs['deploy'].steps)
        $guardIndex = [array]::FindIndex($deployStep, [Predicate[object]] { $args[0].name -eq 'Verify Release Secrets' })
        $publishIndex = [array]::FindIndex($deployStep, [Predicate[object]] { $args[0].name -eq 'Publish Release' })

        $guardIndex | Should -BeGreaterOrEqual 0 -Because 'a missing release secret must fail the job instead of silently skipping the tag'
        $guardIndex | Should -BeLessThan $publishIndex
    }

    Context 'Dependency resolution from the PowerShell Gallery' {
        <#
            A transient refusal of the PowerShell Gallery failed the Package Module
            job of run 38637411323 before any build task ran. The dependency
            resolution therefore runs as a step of its own and is retried; the
            build, the tests, and the release run once.
        #>
        BeforeAll {
            $script:buildScriptPath = Convert-Path -LiteralPath (Join-Path -Path $script:workflowPath -ChildPath '../../build.ps1')
            $script:pwshPath = (Get-Command -Name 'pwsh' -CommandType 'Application' -ErrorAction 'SilentlyContinue' | Select-Object -First 1).Source

            <#
                Stands in for build.ps1, with its real parameter block, so it binds
                what build.ps1 binds. It records each call: whether its session ran
                an earlier one, the parameters bound, and what output/RequiredModules
                held at its start. It leaves a module of its own there, holding a
                hidden dot-file as a signed module holds .signature.p7s, which a
                removal without -Force cannot take, and fails the first calls.
            #>
            $buildParamBlock = [System.Management.Automation.Language.Parser]::ParseFile($script:buildScriptPath, [ref] $null, [ref] $null).ParamBlock
            $script:fakeBuildScript = @(
                $buildParamBlock.Attributes | ForEach-Object -Process { $_.Extent.Text }
                $buildParamBlock.Extent.Text
                @'
$fresh = -not (Test-Path -LiteralPath 'variable:global:FakeBuildRan')
$global:FakeBuildRan = $true
$moduleFolder = Join-Path -Path $PSScriptRoot -ChildPath 'output/RequiredModules'
$found = @(Get-ChildItem -LiteralPath $moduleFolder -Name -ErrorAction 'SilentlyContinue' | Sort-Object) -join ','
$bound = @($PSBoundParameters.GetEnumerator() | Sort-Object -Property 'Key' | ForEach-Object -Process { '{0}={1}' -f $_.Key, (@($_.Value) -join ',') }) -join ';'
$callPath = Join-Path -Path $PSScriptRoot -ChildPath 'calls.log'
Add-Content -LiteralPath $callPath -Value ('{0}|{1}|{2}' -f $fresh, $bound, $found)
$call = @(Get-Content -LiteralPath $callPath).Count
$moduleCopy = New-Item -Path (Join-Path -Path $moduleFolder -ChildPath "call$call") -ItemType 'Directory' -Force
$signaturePath = Join-Path -Path $moduleCopy.FullName -ChildPath '.signature.p7s'
Set-Content -LiteralPath $signaturePath -Value $call
if ($IsWindows)
{
    [System.IO.File]::SetAttributes($signaturePath, [System.IO.File]::GetAttributes($signaturePath) -bor [System.IO.FileAttributes]::Hidden)
}
$failedCall, $failure = (Get-Content -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath 'failure.txt')) -split ' '
if ($call -le [System.Int32] $failedCall)
{
    $message = "Simulated refusal of the PowerShell Gallery, call $call."
    if ($failure -eq 'WriteError')
    {
        Write-Error -Message $message
    }
    else
    {
        throw $message
    }
}
'@
            ) -join [System.Environment]::NewLine

            function ConvertTo-BuildCall
            {
                <#
                    Binds the arguments that follow the script element of a call of
                    build.ps1 with PowerShell's own parameter binder, against the
                    parameters of the real build.ps1.
                #>
                param
                (
                    [Parameter(Mandatory = $true)]
                    [System.Management.Automation.Language.CommandAst]
                    $CommandAst,

                    [Parameter(Mandatory = $true)]
                    [System.Management.Automation.Language.CommandElementAst]
                    $ScriptElement,

                    [Parameter(Mandatory = $true)]
                    [System.Boolean]
                    $InChildProcess,

                    [Parameter(Mandatory = $true)]
                    [System.Boolean]
                    $RunsAlone
                )

                $argumentText = $CommandAst.Extent.Text.Substring($ScriptElement.Extent.EndOffset - $CommandAst.Extent.StartOffset)
                $bindingAst = [System.Management.Automation.Language.Parser]::ParseInput(
                    ("& '{0}'{1}" -f $script:buildScriptPath.Replace("'", "''"), $argumentText), [ref] $null, [ref] $null
                )
                $binding = [System.Management.Automation.Language.StaticParameterBinder]::BindCommand(
                    $bindingAst.Find({ param ($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true), $true
                )
                $task = @('.')

                if ($binding.BoundParameters.ContainsKey('Tasks'))
                {
                    $taskAst = $binding.BoundParameters['Tasks'].Value

                    try
                    {
                        $task = @($taskAst.SafeGetValue())
                    }
                    catch
                    {
                        $task = @($taskAst.Extent.Text)
                    }
                }

                [pscustomobject]@{
                    Text           = $CommandAst.Extent.Text
                    Bound          = $binding.BindingExceptions.Count -eq 0 -and $CommandAst.Extent.Text -notmatch '\$\{\{'
                    Parameter      = @($binding.BoundParameters.Keys)
                    Task           = $task
                    InChildProcess = $InChildProcess
                    RunsAlone      = $RunsAlone
                }
            }

            function Get-BuildCall
            {
                <#
                    Each call of build.ps1 in the PowerShell script of a step: a call
                    of its own, or one that a pwsh or powershell call starts with
                    -Command or -File. It is bound by PowerShell's own parameter
                    binder, so that the alias -bootstrap and an abbreviated name count
                    too, and comes back with Bound set to $false when it cannot be
                    bound or a workflow expression fills in its arguments. A comment
                    or a Write-* line that only names build.ps1 is no call; any other
                    mention outside these calls, such as a call whose script path is
                    computed, comes back unbound too, so that a test sees it. An
                    encoded command stays unseen. RunsAlone says that nothing but
                    comments and line breaks surrounds the call.
                #>
                param
                (
                    [Parameter(Mandatory = $true)]
                    [AllowEmptyString()]
                    [System.String]
                    $Script,

                    [Parameter()]
                    [System.Management.Automation.SwitchParameter]
                    $InChildProcess
                )

                $token = $null
                $scriptAst = [System.Management.Automation.Language.Parser]::ParseInput($Script, [ref] $token, [ref] $null)
                $significantToken = @(
                    $token | Where-Object -FilterScript { $_.Kind -notin 'Comment', 'NewLine', 'LineContinuation', 'EndOfInput' }
                )
                $allCommandAst = @($scriptAst.FindAll({ param ($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true))

                foreach ($commandAst in $allCommandAst)
                {
                    $element = $commandAst.CommandElements
                    $commandName = $commandAst.GetCommandName()

                    if ($commandName -match '(?:^|[\\/])build\.ps1$')
                    {
                        $tokenOutside = @(
                            $significantToken | Where-Object -FilterScript {
                                $_.Extent.StartOffset -lt $commandAst.Extent.StartOffset -or $_.Extent.EndOffset -gt $commandAst.Extent.EndOffset
                            }
                        )

                        ConvertTo-BuildCall -CommandAst $commandAst -ScriptElement $element[0] -InChildProcess $InChildProcess.IsPresent -RunsAlone (
                            -not $InChildProcess -and $tokenOutside.Count -eq 0
                        )
                    }
                    elseif ($commandName -match '(?:^|[\\/])(?:pwsh|powershell)(?:\.exe)?$')
                    {
                        for ($index = 1; $index -lt $element.Count; $index++)
                        {
                            if ($element[$index] -is [System.Management.Automation.Language.CommandParameterAst] -and
                                $element[$index].ParameterName.Length -gt 0 -and
                                'command'.StartsWith($element[$index].ParameterName, [System.StringComparison]::OrdinalIgnoreCase))
                            {
                                $commandText = $element[$index].Argument

                                if (-not $commandText -and $index + 1 -lt $element.Count)
                                {
                                    $commandText = $element[$index + 1]
                                }

                                if ($commandText -is [System.Management.Automation.Language.StringConstantExpressionAst] -or
                                    $commandText -is [System.Management.Automation.Language.ExpandableStringExpressionAst])
                                {
                                    Get-BuildCall -Script $commandText.Value -InChildProcess
                                }

                                break
                            }

                            if ($element[$index] -is [System.Management.Automation.Language.StringConstantExpressionAst] -and
                                $element[$index].Value -match '(?:^|[\\/])build\.ps1$')
                            {
                                # -File ./build.ps1, or the script as the first argument of pwsh.
                                ConvertTo-BuildCall -CommandAst $commandAst -ScriptElement $element[$index] -InChildProcess $true -RunsAlone $false
                                break
                            }
                        }
                    }
                }

                # The calls read above and the log lines; a mention of build.ps1 outside all of them is a call no test can read.
                $readExtent = @(
                    $allCommandAst | Where-Object -FilterScript {
                        $_.GetCommandName() -match '(?:^|[\\/])(?:build\.ps1|pwsh(?:\.exe)?|powershell(?:\.exe)?|Write-\w+)$'
                    } | ForEach-Object -Process { $_.Extent }
                )

                foreach ($mention in @($token | Where-Object -FilterScript { $_.Kind -ne 'Comment' -and $_.Text -match 'build\.ps1' }))
                {
                    $insideRead = @(
                        $readExtent | Where-Object -FilterScript {
                            $_.StartOffset -le $mention.Extent.StartOffset -and $_.EndOffset -ge $mention.Extent.EndOffset
                        }
                    )

                    if ($insideRead.Count -eq 0)
                    {
                        [pscustomobject]@{
                            Text           = $mention.Text
                            Bound          = $false
                            Parameter      = @()
                            Task           = @()
                            InChildProcess = $InChildProcess.IsPresent
                            RunsAlone      = $false
                        }
                    }
                }
            }

            function Get-WorkflowStep
            {
                <#
                    Every step of a workflow, once for each matrix entry of its job,
                    with the matrix expressions of its run script replaced by the
                    values of that entry, as GitHub replaces them before the shell
                    starts.
                #>
                param
                (
                    [Parameter(Mandatory = $true)]
                    [System.String]
                    $Path
                )

                $workflow = ConvertFrom-Yaml -Yaml (Get-Content -LiteralPath $Path -Raw)

                foreach ($jobName in $workflow.jobs.Keys)
                {
                    $job = $workflow.jobs[$jobName]
                    $matrixEntry = @($job.strategy.matrix.include | Where-Object -FilterScript { $null -ne $_ })

                    if ($matrixEntry.Count -eq 0)
                    {
                        $matrixEntry = @(@{ })
                    }

                    foreach ($entry in $matrixEntry)
                    {
                        $step = @($job.steps)

                        for ($index = 0; $index -lt $step.Count; $index++)
                        {
                            $run = [System.String] $step[$index].run

                            foreach ($key in $entry.Keys)
                            {
                                $run = [System.Text.RegularExpressions.Regex]::Replace(
                                    $run, ('\$\{{\{{\s*matrix\.{0}\s*\}}\}}' -f [System.Text.RegularExpressions.Regex]::Escape($key)), ([System.String] $entry[$key]).Replace('$', '$$')
                                )
                            }

                            $shell = $step[$index].shell

                            if (-not $shell)
                            {
                                $shell = $job.defaults.run.shell
                            }

                            [pscustomobject]@{
                                Workflow           = Split-Path -Path $Path -Leaf
                                Job                = $jobName
                                Matrix             = $entry.name
                                Index              = $index
                                Label              = '{0}: {1}{2} -> {3}' -f (Split-Path -Path $Path -Leaf), $jobName, $(if ($entry.name) { " ($($entry.name))" }), $step[$index].name
                                Uses               = $step[$index].uses
                                With               = $step[$index].with
                                Shell              = $shell
                                ContinueOnError    = $step[$index]['continue-on-error']
                                JobContinueOnError = $job['continue-on-error']
                                TimeoutMinutes     = $step[$index]['timeout-minutes']
                                Run                = $run
                                Call               = @(Get-BuildCall -Script $run)
                            }
                        }
                    }
                }
            }

            function Test-ResolutionCall
            {
                <#
                    build.ps1 resolves dependencies itself in three ways: always with
                    -ResolveDependency (alias -bootstrap), and, while one of the
                    modules it bootstraps is missing, with -AutoRestore, or with no
                    -Tasks or build among the tasks. This counts the two explicit
                    ways; the test that every task step finds its modules in place
                    first covers the third.
                #>
                param
                (
                    [Parameter(Mandatory = $true)]
                    [System.Object]
                    $Call
                )

                $Call.Parameter -contains 'ResolveDependency' -or $Call.Parameter -contains 'AutoRestore'
            }

            function Invoke-ResolutionStepScript
            {
                <#
                    Runs the script of a pwsh step as the GitHub runner does: in a new
                    pwsh, after $ErrorActionPreference = 'stop', and exiting with the
                    exit code of its last native command. output/RequiredModules
                    starts with one module, seed. The fake build.ps1 fails the first
                    calls, Start-Sleep only records its pause, and a failed native
                    command throws, as it does where
                    $PSNativeCommandUseErrorActionPreference is on.
                #>
                param
                (
                    [Parameter(Mandatory = $true)]
                    [System.String]
                    $Run,

                    [Parameter(Mandatory = $true)]
                    [System.Int32]
                    $FailedCall,

                    [Parameter(Mandatory = $true)]
                    [ValidateSet('Throw', 'WriteError')]
                    [System.String]
                    $Failure
                )

                $workingPath = Join-Path -Path $TestDrive -ChildPath ([System.Guid]::NewGuid().ToString('N'))
                $moduleFolder = Join-Path -Path $workingPath -ChildPath 'output/RequiredModules'
                $null = New-Item -Path $moduleFolder -ItemType 'Directory'
                Set-Content -LiteralPath (Join-Path -Path $moduleFolder -ChildPath 'seed') -Value 'seed'
                $pausePath = Join-Path -Path $workingPath -ChildPath 'pauses.log'
                $stepPath = Join-Path -Path $workingPath -ChildPath 'step.ps1'

                Set-Content -LiteralPath (Join-Path -Path $workingPath -ChildPath 'build.ps1') -Value $script:fakeBuildScript
                Set-Content -LiteralPath (Join-Path -Path $workingPath -ChildPath 'failure.txt') -Value ('{0} {1}' -f $FailedCall, $Failure)
                Set-Content -LiteralPath $stepPath -Value @(
                    '$ErrorActionPreference = ''stop'''
                    '$PSNativeCommandUseErrorActionPreference = $true'
                    ('function Start-Sleep {{ param ([System.Int32] $Seconds) Add-Content -LiteralPath ''{0}'' -Value $Seconds }}' -f $pausePath.Replace("'", "''"))
                    $Run
                    'if ((Test-Path -LiteralPath variable:\LASTEXITCODE)) { exit $LASTEXITCODE }'
                )

                $PSNativeCommandUseErrorActionPreference = $false
                Push-Location -LiteralPath $workingPath

                try
                {
                    $output = & $script:pwshPath -NoProfile -NonInteractive -Command (". '{0}'" -f $stepPath.Replace("'", "''")) 2>&1 |
                        ForEach-Object -Process { [System.String] $_ }
                    $exitCode = $LASTEXITCODE
                }
                finally
                {
                    Pop-Location
                }

                [pscustomobject]@{
                    ExitCode  = $exitCode
                    Output    = $output -join [System.Environment]::NewLine
                    Call      = @(
                        Get-Content -LiteralPath (Join-Path -Path $workingPath -ChildPath 'calls.log') -ErrorAction 'SilentlyContinue' |
                            ForEach-Object -Process {
                                $fresh, $bound, $found = $_ -split '\|'
                                [pscustomobject]@{
                                    Fresh = $fresh
                                    Bound = $bound
                                    Found = $found
                                }
                            }
                    )
                    Pause     = @(Get-Content -LiteralPath $pausePath -ErrorAction 'SilentlyContinue')
                    Remaining = @(Get-ChildItem -LiteralPath $moduleFolder -Name -ErrorAction 'SilentlyContinue' | Sort-Object) -join ','
                }
            }

            $script:workflowStep = @(
                Get-ChildItem -Path $script:workflowPath -Filter '*.yml' -File |
                    ForEach-Object -Process { Get-WorkflowStep -Path $_.FullName }
            )
            $script:resolutionStep = @(
                $script:workflowStep | Where-Object -FilterScript {
                    @($_.Call | Where-Object -FilterScript { Test-ResolutionCall -Call $_ }).Count -gt 0
                }
            )
        }

        It 'Should resolve the dependencies only in a step of their own that runs the noop task' {
            $script:resolutionStep | Should -Not -BeNullOrEmpty -Because 'the Package Module job resolves its dependencies from the PowerShell Gallery'

            $offendingCall = foreach ($step in $script:resolutionStep)
            {
                foreach ($call in $step.Call)
                {
                    if (-not $call.Bound -or -not (Test-ResolutionCall -Call $call) -or ($call.Task -join ',') -cne 'noop')
                    {
                        '{0}: {1}' -f $step.Label, $call.Text
                    }
                }
            }

            $offendingCall | Should -BeNullOrEmpty -Because 'a retry repeats everything its step runs, so the step that resolves dependencies must run the noop task and nothing else'
        }

        It 'Should run every other task of build.ps1 once, without resolving dependencies' {
            $offendingCall = foreach ($step in $script:workflowStep)
            {
                foreach ($call in @($step.Call | Where-Object -FilterScript { -not $_.Bound -or ($_.Task -join ',') -cne 'noop' }))
                {
                    if (-not $call.Bound -or (Test-ResolutionCall -Call $call) -or -not $call.RunsAlone)
                    {
                        '{0}: {1}' -f $step.Label, $call.Text
                    }
                }
            }

            $offendingCall | Should -BeNullOrEmpty -Because 'the build, the tests, and the release must each be the whole script of their step, so no retry repeats them, and must not reach the PowerShell Gallery for dependencies'
        }

        It 'Should have the modules in place before a task of build.ps1 runs' {
            $taskStep = @(
                $script:workflowStep | Where-Object -FilterScript {
                    @($_.Call | Where-Object -FilterScript { ($_.Task -join ',') -cne 'noop' }).Count -gt 0
                }
            )

            $offendingStep = foreach ($step in $taskStep)
            {
                $moduleSource = @(
                    $script:workflowStep | Where-Object -FilterScript {
                        $_.Workflow -eq $step.Workflow -and $_.Job -eq $step.Job -and $_.Matrix -eq $step.Matrix -and $_.Index -lt $step.Index -and (
                            ($_.Uses -like 'actions/download-artifact@*' -and $_.With.path -eq 'output/') -or
                            $_ -in $script:resolutionStep
                        )
                    }
                )

                if ($moduleSource.Count -eq 0)
                {
                    $step.Label
                }
            }

            $offendingStep | Should -BeNullOrEmpty -Because 'a step that runs a task takes its modules from an earlier dependency step or from the build artifact in output/'
        }

        It 'Should let a failed dependency resolution fail its job' {
            $script:resolutionStep | Should -Not -BeNullOrEmpty -Because 'the Package Module job resolves its dependencies from the PowerShell Gallery'

            $offendingStep = foreach ($step in $script:resolutionStep)
            {
                foreach ($scope in @(@{ Name = 'step'; Value = $step.ContinueOnError }, @{ Name = 'job'; Value = $step.JobContinueOnError }))
                {
                    if ($null -ne $scope.Value -and -not ($scope.Value -is [System.Boolean] -and -not $scope.Value))
                    {
                        '{0}: continue-on-error of the {1} is {2}' -f $step.Label, $scope.Name, $scope.Value
                    }
                }
            }

            $offendingStep | Should -BeNullOrEmpty -Because 'on the step it would build after the third failure, and on the job it would let the run pass with a failed job'
        }

        It 'Should bound the dependency resolution in time' {
            $script:resolutionStep | Should -Not -BeNullOrEmpty -Because 'the Package Module job resolves its dependencies from the PowerShell Gallery'

            foreach ($step in $script:resolutionStep)
            {
                $step.TimeoutMinutes | Should -BeIn (5..30) -Because ('{0} must fit three cold resolutions and the minute of pauses, and a Gallery that hangs, which no retry catches, must fail the job long before the default of 360 minutes' -f $step.Label)
            }
        }

        It 'Should <Description>' -Skip:(-not $script:pwshAvailable) -ForEach @(
            @{
                Description = 'resolve once and go on when the first attempt succeeds'
                FailedCall  = 0
                Failure     = 'Throw'
                Succeeds    = $true
                Attempt     = 1
                Pause       = @()
                Remaining   = 'call1,seed'
            }
            @{
                Description = 'retry a refused resolution after a growing pause and go on when an attempt succeeds'
                FailedCall  = 2
                Failure     = 'Throw'
                Succeeds    = $true
                Attempt     = 3
                Pause       = @(15, 45)
                Remaining   = 'call3'
            }
            @{
                Description = 'fail the job when the last of three attempts is refused too'
                FailedCall  = 3
                Failure     = 'Throw'
                Succeeds    = $false
                Attempt     = 3
                Pause       = @(15, 45)
                Remaining   = $null
            }
            @{
                Description = 'fail an attempt on an error the resolution only writes, as the runner fails the step'
                FailedCall  = 3
                Failure     = 'WriteError'
                Succeeds    = $false
                Attempt     = 3
                Pause       = @(15, 45)
                Remaining   = $null
            }
        ) {
            $script:resolutionStep | Should -Not -BeNullOrEmpty -Because 'the Package Module job resolves its dependencies from the PowerShell Gallery'

            foreach ($step in $script:resolutionStep)
            {
                $step.Shell | Should -BeExactly 'pwsh' -Because 'the run is emulated as a pwsh step'

                $result = Invoke-ResolutionStepScript -Run $step.Run -FailedCall $FailedCall -Failure $Failure
                $because = 'the step printed: {0}' -f $result.Output

                if ($Succeeds)
                {
                    $result.ExitCode | Should -Be 0 -Because $because
                }
                else
                {
                    $result.ExitCode | Should -Not -Be 0 -Because $because
                }

                $result.Call | Should -HaveCount $Attempt -Because $because
                (@($result.Call.Bound) -join [System.Environment]::NewLine) | Should -BeExactly (
                    (@('ResolveDependency=True;Tasks=noop') * $Attempt) -join [System.Environment]::NewLine
                ) -Because 'each attempt resolves the dependencies and runs nothing else'
                (@($result.Call.Fresh) -join ',') | Should -BeExactly ((@('True') * $Attempt) -join ',') -Because 'each attempt runs in a session that no earlier attempt touched'
                (@($result.Call.Found) -join '|') | Should -BeExactly ((@('seed') + @(@('') * ($Attempt - 1))) -join '|') -Because 'the first attempt finds output/RequiredModules as it was, and each retry starts without what a failed attempt saved'
                ($result.Pause -join ',') | Should -BeExactly ($Pause -join ',') -Because 'a pause precedes each retry and none follows the last attempt'

                if ($Remaining)
                {
                    $result.Remaining | Should -BeExactly $Remaining -Because 'the modules of the attempt that succeeded stay for the build'
                }

                foreach ($number in @(1..$Attempt | Where-Object -FilterScript { $_ -le $FailedCall }))
                {
                    if ($number -lt $Attempt)
                    {
                        $result.Output | Should -Match ('(?m)^::warning::.*\battempt {0} of 3\b' -f $number) -Because 'each attempt that fails and is retried is a warning annotation that names its number'
                    }
                    else
                    {
                        $result.Output | Should -Match ('\battempt {0}\b' -f $number) -Because 'the error that fails the job names the last attempt'
                    }
                }
            }
        }
    }
}
