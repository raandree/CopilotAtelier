BeforeDiscovery {
    $script:linkItemType = if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) { 'Junction' } else { 'SymbolicLink' }

    # Directory-link creation is a host capability, so it is probed once during
    # discovery rather than assumed. TestDrive does not exist yet at this point.
    $script:canCreateDirectoryLink = $false
    $probeRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('ca-health-probe-' + [guid]::NewGuid().ToString('N'))
    try
    {
        $probeTarget = Join-Path $probeRoot 'target'
        New-Item -ItemType Directory -Path $probeTarget -Force | Out-Null
        New-Item -ItemType $script:linkItemType -Path (Join-Path $probeRoot 'link') -Target $probeTarget -ErrorAction Stop | Out-Null
        $script:canCreateDirectoryLink = $true
    }
    catch
    {
        $script:canCreateDirectoryLink = $false
    }
    finally
    {
        Remove-Item -LiteralPath $probeRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

BeforeAll {
    $script:projectPath = Convert-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')
    . (Join-Path $script:projectPath 'tests/Helpers/DeploymentProfile.ps1')
    Import-CopilotAtelierTestModule -ProjectPath $script:projectPath

    $script:referenceUtc = [datetime]::SpecifyKind([datetime]::Parse('2026-09-01T00:00:00'), [System.DateTimeKind]::Utc)
    $script:linkItemType = if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) { 'Junction' } else { 'SymbolicLink' }

    function New-HealthSkill
    {
        param
        (
            [Parameter(Mandatory = $true)] [System.String] $Root,
            [Parameter(Mandatory = $true)] [System.String] $Name,
            [Parameter(Mandatory = $true)] [System.String] $Description,
            [Parameter()] [System.String] $Body = 'Body line.'
        )

        $skillPath = Join-Path $Root "skills/$Name"
        New-Item -ItemType Directory -Path $skillPath -Force | Out-Null
        $content = @(
            '---'
            "name: $Name"
            "description: $Description"
            '---'
            ''
            "# $Name"
            ''
            $Body
        )
        Set-Content -LiteralPath (Join-Path $skillPath 'SKILL.md') -Encoding utf8 -Value $content
    }

    function New-HealthContent
    {
        param ([Parameter(Mandatory = $true)] [System.String] $Root)

        New-Item -ItemType Directory -Path (Join-Path $Root 'skills/agent-evals/assets') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $Root 'com.github.copilot/rules') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $Root 'com.github.copilot/hooks') -Force | Out-Null

        Set-Content -LiteralPath (Join-Path $Root 'com.github.copilot/rules/copilot-authoring.instructions.md') -Encoding utf8 -Value @(
            '---'
            'applyTo: "**/*.md"'
            'description: "Authoring rules."'
            '---'
            'Events: SessionStart, UserPromptSubmit, PreToolUse, PostToolUse, PreCompact, SubagentStart, SubagentStop, Stop.'
        )
        Set-Content -LiteralPath (Join-Path $Root 'com.github.copilot/hooks/hooks.json') -Encoding utf8 -Value '{ "hooks": {} }'

        New-HealthSkill -Root $Root -Name 'alpha-tool' -Description 'Alpha converts invoices. USE FOR: invoice conversion, ledger reconciliation, statement extraction.'
        New-HealthSkill -Root $Root -Name 'beta-tool' -Description 'Beta reviews pipelines. USE FOR: pipeline review, workflow triage, runner diagnostics.'
        New-HealthSkill -Root $Root -Name 'gamma-tool' -Description 'Gamma drafts letters. USE FOR: letter drafting, correspondence tone, salutation choice.'
        New-HealthSkill -Root $Root -Name 'delta-tool' -Description 'Delta also converts invoices. USE FOR: invoice conversion, ledger reconciliation, statement extraction.'

        # Discoverability evidence: an authored trigger-query set for one Skill only.
        Set-Content -LiteralPath (Join-Path $Root 'skills/agent-evals/assets/trigger-queries.alpha-tool.json') -Encoding utf8 -Value (@(
                @{ query = 'convert this invoice'; should_trigger = $true; split = 'train' }
                @{ query = 'convert the ledger export'; should_trigger = $true; split = 'validation' }
                @{ query = 'write a unit test'; should_trigger = $false; split = 'train' }
            ) | ConvertTo-Json -Depth 5)

        # Evaluation evidence: the authored input shape the agent-evals Skill
        # documents. Authored cases are not a run and prove no quality.
        New-Item -ItemType Directory -Path (Join-Path $Root 'skills/alpha-tool/evals') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $Root 'skills/alpha-tool/evals/evals.json') -Encoding utf8 -Value (@{
                skill_name = 'alpha-tool'
                evals      = @(
                    @{ id = 1; prompt = 'convert this invoice'; expected_output = 'a markdown table' }
                    @{ id = 2; prompt = 'convert the ledger'; expected_output = 'a markdown table' }
                )
            } | ConvertTo-Json -Depth 6)

        # Evaluation evidence: a real grading artifact bound to the current body
        # by an explicit provenance sidecar, recording failures.
        New-Item -ItemType Directory -Path (Join-Path $Root 'skills/beta-tool/evals') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $Root 'skills/beta-tool/evals/evals.json') -Encoding utf8 -Value (@{
                skill_name = 'beta-tool'
                evals      = @(@{ id = 1; prompt = 'review this pipeline'; expected_output = 'a triage list' })
            } | ConvertTo-Json -Depth 6)
        New-GradingArtifact -Path (Join-Path $Root 'skills/beta-tool/evals/grading.json') -Passed 3 -Failed 2
        New-EvalProvenance -Path (Join-Path $Root 'skills/beta-tool/evals/grading.provenance.json') -SkillName 'beta-tool' -SkillSha256 (Get-SkillSha -Root $Root -Name 'beta-tool') -RunId 'run-beta-1'
    }

    function New-GradingArtifact
    {
        param
        (
            [Parameter(Mandatory = $true)] [System.String] $Path,
            [Parameter(Mandatory = $true)] [System.Object] $Passed,
            [Parameter(Mandatory = $true)] [System.Object] $Failed,
            [Parameter()] [System.Object] $Total,
            [Parameter()] [AllowNull()] [System.Object] $Assertion,
            [Parameter()] [System.Management.Automation.SwitchParameter] $OmitAssertion
        )

        if (-not $PSBoundParameters.ContainsKey('Total'))
        {
            $Total = $Passed + $Failed
        }

        New-Item -ItemType Directory -Path (Split-Path -Path $Path -Parent) -Force | Out-Null
        $rate = 0
        if ($Passed -is [int] -and $Total -is [int] -and $Total -gt 0)
        {
            $rate = [math]::Round($Passed / $Total, 2)
        }

        # By default the assertion list reconciles with the summary, because a
        # graded run that cannot be reconciled is exactly what must not count.
        if (-not $PSBoundParameters.ContainsKey('Assertion'))
        {
            $generated = [System.Collections.Generic.List[object]]::new()
            if ($Passed -is [int] -and $Failed -is [int] -and $Passed -ge 0 -and $Failed -ge 0)
            {
                for ($index = 0; $index -lt $Passed; $index++)
                {
                    $generated.Add(@{ text = "Assertion p$index"; passed = $true; evidence = 'Recorded evidence.' })
                }
                for ($index = 0; $index -lt $Failed; $index++)
                {
                    $generated.Add(@{ text = "Assertion f$index"; passed = $false; evidence = 'Recorded evidence.' })
                }
            }
            else
            {
                $generated.Add(@{ text = 'Assertion p0'; passed = $true; evidence = 'Recorded evidence.' })
            }
            $Assertion = $generated.ToArray()
        }

        $document = [ordered] @{}
        if (-not $OmitAssertion.IsPresent)
        {
            $document['assertion_results'] = @($Assertion)
        }
        $document['summary'] = [ordered] @{ passed = $Passed; failed = $Failed; total = $Total; pass_rate = $rate }

        Set-Content -LiteralPath $Path -Encoding utf8 -Value ($document | ConvertTo-Json -Depth 6)
    }

    function New-BenchmarkArtifact
    {
        param ([Parameter(Mandatory = $true)] [System.String] $Path)

        New-Item -ItemType Directory -Path (Split-Path -Path $Path -Parent) -Force | Out-Null
        Set-Content -LiteralPath $Path -Encoding utf8 -Value ([ordered] @{
                run_summary = [ordered] @{
                    with_skill    = [ordered] @{ pass_rate = [ordered] @{ mean = 0.83; stddev = 0.06 } }
                    without_skill = [ordered] @{ pass_rate = [ordered] @{ mean = 0.33; stddev = 0.1 } }
                    delta         = [ordered] @{ pass_rate = 0.5 }
                }
            } | ConvertTo-Json -Depth 8)
    }

    function New-EvalProvenance
    {
        param
        (
            [Parameter(Mandatory = $true)] [System.String] $Path,
            [Parameter(Mandatory = $true)] [System.String] $SkillName,
            [Parameter(Mandatory = $true)] [System.String] $SkillSha256,
            [Parameter(Mandatory = $true)] [System.String] $RunId,
            [Parameter()] [AllowNull()] [System.Object] $CompletedUtc = '2026-08-30T10:00:00Z'
        )

        New-Item -ItemType Directory -Path (Split-Path -Path $Path -Parent) -Force | Out-Null
        Set-Content -LiteralPath $Path -Encoding utf8 -Value ([ordered] @{
                schemaVersion = 1
                skillName     = $SkillName
                skillSha256   = $SkillSha256
                runId         = $RunId
                completedUtc  = $CompletedUtc
            } | ConvertTo-Json -Depth 5)
    }

    function Get-SkillSha
    {
        param
        (
            [Parameter(Mandatory = $true)] [System.String] $Root,
            [Parameter(Mandatory = $true)] [System.String] $Name
        )

        (Get-FileHash -LiteralPath (Join-Path $Root "skills/$Name/SKILL.md") -Algorithm SHA256).Hash.ToLowerInvariant()
    }

    function New-ObservationFile
    {
        param
        (
            [Parameter(Mandatory = $true)] [System.String] $Path,
            [Parameter(Mandatory = $true)] [AllowEmptyCollection()] [System.Object[]] $Record,
            [Parameter()] [System.String] $Trust = 'Imported',
            [Parameter()] [System.Object] $SchemaVersion = 1,
            [Parameter()] [AllowEmptyCollection()] [System.Object[]] $Coverage
        )

        New-Item -ItemType Directory -Path (Split-Path -Path $Path -Parent) -Force | Out-Null
        $document = [ordered] @{
            schemaVersion = $SchemaVersion
            client        = 'vscode-copilot-chat'
            clientVersion = '1.105.0'
            trust         = $Trust
            records       = @($Record)
        }
        if ($PSBoundParameters.ContainsKey('Coverage'))
        {
            $document['coverage'] = @($Coverage)
        }
        Set-Content -LiteralPath $Path -Encoding utf8 -Value ($document | ConvertTo-Json -Depth 6)
    }

    function New-CoverageDeclaration
    {
        param
        (
            [Parameter(Mandatory = $true)] [System.String] $SkillName,
            [Parameter(Mandatory = $true)] [System.String] $SkillSha256,
            [Parameter()] [System.String] $WindowStartUtc = '2026-07-01T00:00:00Z',
            [Parameter()] [System.String] $WindowEndUtc = '2026-08-30T00:00:00Z',
            [Parameter()] [System.Int32] $SessionCount = 25,
            [Parameter()] [System.Boolean] $ActivationCaptureComplete = $true
        )

        [ordered] @{
            skillName                 = $SkillName
            skillSha256               = $SkillSha256
            windowStartUtc            = $WindowStartUtc
            windowEndUtc              = $WindowEndUtc
            sessionCount              = $SessionCount
            activationCaptureComplete = $ActivationCaptureComplete
        }
    }

    function New-ObservationRecord
    {
        param
        (
            [Parameter(Mandatory = $true)] [System.String] $EventId,
            [Parameter(Mandatory = $true)] [System.String] $EventType,
            [Parameter(Mandatory = $true)] [System.String] $SkillName,
            [Parameter(Mandatory = $true)] [System.String] $SkillSha256,
            [Parameter(Mandatory = $true)] [System.String] $TimestampUtc,
            [Parameter()] [System.String] $SessionId = 'session-1',
            [Parameter()] [System.String] $Outcome = 'Unknown'
        )

        [ordered] @{
            eventId      = $EventId
            eventType    = $EventType
            skillName    = $SkillName
            skillSha256  = $SkillSha256
            timestampUtc = $TimestampUtc
            sessionId    = $SessionId
            outcome      = $Outcome
        }
    }

    function Get-TreeSnapshot
    {
        param ([Parameter(Mandatory = $true)] [System.String] $Root)

        @(
            Get-ChildItem -LiteralPath $Root -Recurse -Force |
                Sort-Object -Property FullName |
                ForEach-Object -Process {
                    if ($_.PSIsContainer) { "D|$($_.FullName)" }
                    else { "F|$($_.FullName)|$((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash)" }
                }
        )
    }
}

Describe 'Get-CopilotAtelierSkillHealth' -Tag 'Unit' {
    BeforeEach {
        $script:content = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-HealthContent -Root $script:content
        $script:observationRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:observationRoot -Force | Out-Null
    }

    Context 'Telemetry support and the observation gap' {
        It 'Should report that no supported client event identifies a Skill activation' {
            $result = Get-CopilotAtelierSkillHealth -ContentPath $script:content -ReferenceUtc $script:referenceUtc

            $result.Telemetry.ActivationEventSupported | Should -BeFalse
            $result.Telemetry.CaptureEnabled | Should -BeFalse
            $result.Telemetry.CaptureMode | Should -Be 'None'
            $result.Telemetry.Gap | Should -Not -BeNullOrEmpty
            @($result.Telemetry.SupportedClientEvent).Count | Should -BeGreaterThan 0
            @($result.Telemetry.SupportedClientEvent | Where-Object -FilterScript { $_.IdentifiesSkill }) |
                Should -BeNullOrEmpty -Because 'no documented hook event carries a Skill identity'
        }

        It 'Should ground the supported-event claim in files that exist in the inspected content' {
            $result = Get-CopilotAtelierSkillHealth -ContentPath $script:content -ReferenceUtc $script:referenceUtc

            @($result.Telemetry.Source).Count | Should -BeGreaterThan 0
            foreach ($source in $result.Telemetry.Source)
            {
                $source.Available | Should -BeTrue -Because "$($source.RelativePath) is the cited evidence"
            }
        }

        It 'Should scope the activation claim to this implementation rather than to every client' {
            $result = Get-CopilotAtelierSkillHealth -ContentPath $script:content -ReferenceUtc $script:referenceUtc

            $result.Telemetry.Gap | Should -Match 'no reliable Skill-activation contract'
            $result.Telemetry.VerificationScope | Should -Not -BeNullOrEmpty
            $result.Telemetry.VerificationState | Should -Be 'Verified'
            @($result.Telemetry.SupportedClientEvent | Where-Object -FilterScript { -not $_.DocumentedInSource }) |
                Should -BeNullOrEmpty -Because 'each listed event must be found in the inspected Instruction'
        }

        It 'Should mark the event contract unverified when its source is unavailable' {
            Remove-Item -LiteralPath (Join-Path $script:content 'com.github.copilot/rules/copilot-authoring.instructions.md') -Force

            $result = Get-CopilotAtelierSkillHealth -ContentPath $script:content -ReferenceUtc $script:referenceUtc

            $result.Telemetry.VerificationState | Should -Be 'Unverified'
            @($result.Telemetry.SupportedClientEvent | Where-Object -FilterScript { $_.DocumentedInSource }) | Should -BeNullOrEmpty
        }

        It 'Should report an unavailable source rather than claiming an ungrounded fact' {
            Remove-Item -LiteralPath (Join-Path $script:content 'com.github.copilot/hooks/hooks.json') -Force

            $result = Get-CopilotAtelierSkillHealth -ContentPath $script:content -ReferenceUtc $script:referenceUtc

            @($result.Telemetry.Source | Where-Object -FilterScript { -not $_.Available }) | Should -Not -BeNullOrEmpty
            $result.Telemetry.ActivationEventSupported | Should -BeFalse
        }

        It 'Should report absent observations as unknown use, never as zero use' {
            $result = Get-CopilotAtelierSkillHealth -ContentPath $script:content -ReferenceUtc $script:referenceUtc

            $alpha = $result.Skill | Where-Object -FilterScript { $_.Name -eq 'alpha-tool' }
            $alpha.Usage.Coverage | Should -Be 'NoObservations'
            $alpha.Usage.Note | Should -Match 'unknown'
            $result.Observation.FileCount | Should -Be 0
        }
    }

    Context 'Evidence separation' {
        It 'Should never report a file read or a load as a passed capability evaluation' {
            $observationPath = Join-Path $script:observationRoot 'reads.json'
            New-ObservationFile -Path $observationPath -Record @(
                New-ObservationRecord -EventId 'e1' -EventType 'SkillFileRead' -SkillName 'alpha-tool' -SkillSha256 (Get-SkillSha -Root $script:content -Name 'alpha-tool') -TimestampUtc '2026-08-30T10:00:00Z'
                New-ObservationRecord -EventId 'e2' -EventType 'SkillFileRead' -SkillName 'alpha-tool' -SkillSha256 (Get-SkillSha -Root $script:content -Name 'alpha-tool') -TimestampUtc '2026-08-30T11:00:00Z'
            )

            $result = Get-CopilotAtelierSkillHealth -ContentPath $script:content -ObservationPath $observationPath -ReferenceUtc $script:referenceUtc
            $alpha = $result.Skill | Where-Object -FilterScript { $_.Name -eq 'alpha-tool' }

            $alpha.Usage.FileReadCount | Should -Be 2
            $alpha.Usage.ActivationCount | Should -Be 0
            $alpha.Usage.ToolSuccessCount | Should -Be 0
            $alpha.Evaluation.PassedCount | Should -Be 0
            $alpha.Evaluation.State | Should -Be 'AuthoredOnly'
        }

        It 'Should keep activation, tool success, and evaluation quality in separate facets' {
            $sha = Get-SkillSha -Root $script:content -Name 'alpha-tool'
            $observationPath = Join-Path $script:observationRoot 'mixed.json'
            New-ObservationFile -Path $observationPath -Record @(
                New-ObservationRecord -EventId 'a1' -EventType 'SkillActivation' -SkillName 'alpha-tool' -SkillSha256 $sha -TimestampUtc '2026-08-30T10:00:00Z'
                New-ObservationRecord -EventId 't1' -EventType 'SkillToolExecution' -SkillName 'alpha-tool' -SkillSha256 $sha -TimestampUtc '2026-08-30T10:05:00Z' -Outcome 'Success'
                New-ObservationRecord -EventId 't2' -EventType 'SkillToolExecution' -SkillName 'alpha-tool' -SkillSha256 $sha -TimestampUtc '2026-08-30T10:06:00Z' -Outcome 'Failure'
            )

            $result = Get-CopilotAtelierSkillHealth -ContentPath $script:content -ObservationPath $observationPath -ReferenceUtc $script:referenceUtc
            $alpha = $result.Skill | Where-Object -FilterScript { $_.Name -eq 'alpha-tool' }

            $alpha.Usage.ActivationCount | Should -Be 1
            $alpha.Usage.ToolSuccessCount | Should -Be 1
            $alpha.Usage.ToolFailureCount | Should -Be 1
            $alpha.Evaluation.State | Should -Be 'AuthoredOnly'
            $alpha.Quality.State | Should -Be 'Unmeasured'
        }

        It 'Should read the authored eval input shape without inventing a run' {
            $result = Get-CopilotAtelierSkillHealth -ContentPath $script:content -ReferenceUtc $script:referenceUtc
            $alpha = $result.Skill | Where-Object -FilterScript { $_.Name -eq 'alpha-tool' }

            $alpha.Evaluation.State | Should -Be 'AuthoredOnly'
            $alpha.Evaluation.AuthoredCaseCount | Should -Be 2
            $alpha.Evaluation.ExecutedRunCount | Should -Be 0
            @($alpha.Evaluation.Artifact).Count | Should -Be 1
            $alpha.Evaluation.Artifact[0].Kind | Should -Be 'AuthoredCases'
            $alpha.Evaluation.Artifact[0].Binding | Should -Be 'Bound'
            $alpha.Quality.State | Should -Be 'Unmeasured'
        }

        It 'Should report an executed evaluation with failures as failed quality evidence' {
            $result = Get-CopilotAtelierSkillHealth -ContentPath $script:content -ReferenceUtc $script:referenceUtc
            $beta = $result.Skill | Where-Object -FilterScript { $_.Name -eq 'beta-tool' }

            $beta.Evaluation.State | Should -Be 'Executed'
            $beta.Quality.State | Should -Be 'Failing'
            $beta.Quality.FailedCount | Should -Be 2
            $beta.Quality.PassedCount | Should -Be 3
        }

        It 'Should report discoverability separately from usage and never as executed' {
            $result = Get-CopilotAtelierSkillHealth -ContentPath $script:content -ReferenceUtc $script:referenceUtc

            $alpha = $result.Skill | Where-Object -FilterScript { $_.Name -eq 'alpha-tool' }
            $gamma = $result.Skill | Where-Object -FilterScript { $_.Name -eq 'gamma-tool' }

            $alpha.Discoverability.TriggerQuerySet | Should -Be 'Present'
            $alpha.Discoverability.PositiveCount | Should -Be 2
            $alpha.Discoverability.NegativeCount | Should -Be 1
            $alpha.Discoverability.Executed | Should -BeFalse
            $gamma.Discoverability.TriggerQuerySet | Should -Be 'Absent'
        }

        It 'Should report overlap between two Skills that claim the same work' {
            $result = Get-CopilotAtelierSkillHealth -ContentPath $script:content -ReferenceUtc $script:referenceUtc

            $alpha = $result.Skill | Where-Object -FilterScript { $_.Name -eq 'alpha-tool' }
            $gamma = $result.Skill | Where-Object -FilterScript { $_.Name -eq 'gamma-tool' }

            @($alpha.Overlap.Partner | ForEach-Object -Process { $_.Name }) | Should -Contain 'delta-tool'
            @($gamma.Overlap.Partner) | Should -BeNullOrEmpty
        }

        It 'Should not fabricate a single combined health score' {
            $result = Get-CopilotAtelierSkillHealth -ContentPath $script:content -ReferenceUtc $script:referenceUtc
            $alpha = $result.Skill | Where-Object -FilterScript { $_.Name -eq 'alpha-tool' }

            @($alpha.PSObject.Properties.Name) | Should -Not -Contain 'HealthScore'
            @($alpha.PSObject.Properties.Name) | Should -Not -Contain 'Score'
            @($result.PSObject.Properties.Name) | Should -Not -Contain 'HealthScore'
        }
    }

    Context 'Evaluation evidence is bound to the current body' {
        It 'Should refuse to count a result artifact that carries no identity' {
            New-GradingArtifact -Path (Join-Path $script:content 'skills/gamma-tool/evals/grading.json') -Passed 4 -Failed 0

            $result = Get-CopilotAtelierSkillHealth -ContentPath $script:content -ReferenceUtc $script:referenceUtc
            $gamma = $result.Skill | Where-Object -FilterScript { $_.Name -eq 'gamma-tool' }

            $gamma.Evaluation.State | Should -Be 'UnboundResults'
            $gamma.Evaluation.PassedCount | Should -Be 0
            $gamma.Quality.State | Should -Be 'Unmeasured'
            $gamma.Evaluation.Artifact[0].Kind | Should -Be 'Grading'
            $gamma.Evaluation.Artifact[0].Binding | Should -Be 'Unbound'
            @($result.Suggestion | Where-Object -FilterScript { $_.Skill -eq 'gamma-tool' -and $_.Reason -match 'identity' }) |
                Should -Not -BeNullOrEmpty
        }

        It 'Should label a result produced against a different body and exclude it' {
            New-GradingArtifact -Path (Join-Path $script:content 'skills/gamma-tool/evals/grading.json') -Passed 4 -Failed 0
            New-EvalProvenance -Path (Join-Path $script:content 'skills/gamma-tool/evals/grading.provenance.json') -SkillName 'gamma-tool' -SkillSha256 ('b' * 64) -RunId 'run-old'

            $result = Get-CopilotAtelierSkillHealth -ContentPath $script:content -ReferenceUtc $script:referenceUtc
            $gamma = $result.Skill | Where-Object -FilterScript { $_.Name -eq 'gamma-tool' }

            $gamma.Evaluation.Artifact[0].Binding | Should -Be 'DifferentBody'
            $gamma.Evaluation.PassedCount | Should -Be 0
            $gamma.Quality.State | Should -Be 'Unmeasured'
        }

        It 'Should refuse provenance that names another Skill' {
            New-GradingArtifact -Path (Join-Path $script:content 'skills/gamma-tool/evals/grading.json') -Passed 4 -Failed 0
            New-EvalProvenance -Path (Join-Path $script:content 'skills/gamma-tool/evals/grading.provenance.json') -SkillName 'alpha-tool' -SkillSha256 (Get-SkillSha -Root $script:content -Name 'alpha-tool') -RunId 'run-wrong'

            $result = Get-CopilotAtelierSkillHealth -ContentPath $script:content -ReferenceUtc $script:referenceUtc
            $gamma = $result.Skill | Where-Object -FilterScript { $_.Name -eq 'gamma-tool' }

            $gamma.Evaluation.Artifact[0].Binding | Should -Be 'MismatchedSkill'
            $gamma.Quality.State | Should -Be 'Unmeasured'
        }

        It 'Should count a bound run once when the same run identifier appears twice' {
            $sha = Get-SkillSha -Root $script:content -Name 'gamma-tool'
            New-GradingArtifact -Path (Join-Path $script:content 'skills/gamma-tool/evals/grading.json') -Passed 2 -Failed 0
            New-EvalProvenance -Path (Join-Path $script:content 'skills/gamma-tool/evals/grading.provenance.json') -SkillName 'gamma-tool' -SkillSha256 $sha -RunId 'run-1'
            New-GradingArtifact -Path (Join-Path $script:content 'skills/gamma-tool/evals/copy.json') -Passed 2 -Failed 0
            New-EvalProvenance -Path (Join-Path $script:content 'skills/gamma-tool/evals/copy.provenance.json') -SkillName 'gamma-tool' -SkillSha256 $sha -RunId 'run-1'

            $result = Get-CopilotAtelierSkillHealth -ContentPath $script:content -ReferenceUtc $script:referenceUtc
            $gamma = $result.Skill | Where-Object -FilterScript { $_.Name -eq 'gamma-tool' }

            $gamma.Evaluation.ExecutedRunCount | Should -Be 1
            $gamma.Evaluation.PassedCount | Should -Be 2
            @($gamma.Evaluation.Artifact | Where-Object -FilterScript { $_.Binding -eq 'DuplicateRun' }).Count | Should -Be 1
            $gamma.Quality.State | Should -Be 'Passing'
        }

        It 'Should never report Passing from <Case> counts' -ForEach @(
            @{ Case = 'negative'; Passed = -1; Failed = 0; Total = 5 }
            @{ Case = 'inconsistent'; Passed = 9; Failed = 9; Total = 2 }
            @{ Case = 'non-numeric'; Passed = 'many'; Failed = 0; Total = 5 }
        ) {
            $sha = Get-SkillSha -Root $script:content -Name 'gamma-tool'
            New-GradingArtifact -Path (Join-Path $script:content 'skills/gamma-tool/evals/grading.json') -Passed $Passed -Failed $Failed -Total $Total
            New-EvalProvenance -Path (Join-Path $script:content 'skills/gamma-tool/evals/grading.provenance.json') -SkillName 'gamma-tool' -SkillSha256 $sha -RunId 'run-bad'

            $result = Get-CopilotAtelierSkillHealth -ContentPath $script:content -ReferenceUtc $script:referenceUtc
            $gamma = $result.Skill | Where-Object -FilterScript { $_.Name -eq 'gamma-tool' }

            $gamma.Evaluation.Artifact[0].CountsValid | Should -BeFalse
            $gamma.Evaluation.PassedCount | Should -Be 0
            $gamma.Quality.State | Should -Not -Be 'Passing'
        }

        It 'Should not read a legacy artifact that claims a run in an unrecognized shape' {
            New-Item -ItemType Directory -Path (Join-Path $script:content 'skills/gamma-tool/evals') -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $script:content 'skills/gamma-tool/evals/legacy.json') -Encoding utf8 -Value (@{
                    schemaVersion = 1
                    evidenceClass = 'executed'
                    executed      = $true
                    results       = @{ total = 9; passed = 9; failed = 0 }
                } | ConvertTo-Json -Depth 5)

            $result = Get-CopilotAtelierSkillHealth -ContentPath $script:content -ReferenceUtc $script:referenceUtc
            $gamma = $result.Skill | Where-Object -FilterScript { $_.Name -eq 'gamma-tool' }

            $gamma.Evaluation.Artifact[0].Kind | Should -Be 'Unrecognized'
            $gamma.Evaluation.PassedCount | Should -Be 0
            $gamma.Quality.State | Should -Be 'Unmeasured'
        }

        It 'Should refuse an eval artifact larger than the documented read bound' {
            New-Item -ItemType Directory -Path (Join-Path $script:content 'skills/gamma-tool/evals') -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $script:content 'skills/gamma-tool/evals/huge.json') -Encoding utf8 -Value ('{ "filler": "' + ('x' * 1200000) + '" }')

            $result = Get-CopilotAtelierSkillHealth -ContentPath $script:content -ReferenceUtc $script:referenceUtc
            $gamma = $result.Skill | Where-Object -FilterScript { $_.Name -eq 'gamma-tool' }

            $gamma.Evaluation.Artifact[0].Kind | Should -Be 'Oversize'
            $gamma.Quality.State | Should -Be 'Unmeasured'
        }
    }

    Context 'A graded run is reconciled with its own assertion results' {
        BeforeEach {
            $script:gammaSha = Get-SkillSha -Root $script:content -Name 'gamma-tool'
        }

        It 'Should refuse a graded run that records only a summary' {
            New-GradingArtifact -Path (Join-Path $script:content 'skills/gamma-tool/evals/grading.json') -Passed 4 -Failed 0 -OmitAssertion
            New-EvalProvenance -Path (Join-Path $script:content 'skills/gamma-tool/evals/grading.provenance.json') -SkillName 'gamma-tool' -SkillSha256 $script:gammaSha -RunId 'run-summary-only'

            $result = Get-CopilotAtelierSkillHealth -ContentPath $script:content -ReferenceUtc $script:referenceUtc
            $gamma = $result.Skill | Where-Object -FilterScript { $_.Name -eq 'gamma-tool' }

            $gamma.Evaluation.Artifact[0].Kind | Should -Be 'Grading'
            $gamma.Evaluation.Artifact[0].AssertionState | Should -Be 'Missing'
            $gamma.Evaluation.Artifact[0].CountsValid | Should -BeFalse
            $gamma.Evaluation.ExecutedRunCount | Should -Be 0
            $gamma.Evaluation.PassedCount | Should -Be 0
            $gamma.Quality.State | Should -Be 'Unmeasured'
        }

        It 'Should refuse a graded run whose summary contradicts an assertion verdict' {
            New-GradingArtifact -Path (Join-Path $script:content 'skills/gamma-tool/evals/grading.json') -Passed 2 -Failed 0 -Total 2 -Assertion @(
                @{ text = 'The first assertion'; passed = $true; evidence = 'Recorded evidence.' }
                @{ text = 'The second assertion'; passed = $false; evidence = 'Recorded evidence.' }
            )
            New-EvalProvenance -Path (Join-Path $script:content 'skills/gamma-tool/evals/grading.provenance.json') -SkillName 'gamma-tool' -SkillSha256 $script:gammaSha -RunId 'run-contradiction'

            $result = Get-CopilotAtelierSkillHealth -ContentPath $script:content -ReferenceUtc $script:referenceUtc
            $gamma = $result.Skill | Where-Object -FilterScript { $_.Name -eq 'gamma-tool' }

            $gamma.Evaluation.Artifact[0].AssertionState | Should -Be 'Valid'
            $gamma.Evaluation.Artifact[0].CountsValid | Should -BeFalse
            $gamma.Evaluation.PassedCount | Should -Be 0
            $gamma.Quality.State | Should -Be 'Unmeasured'
        }

        It 'Should refuse a graded run that leaves cases ungraded' {
            New-GradingArtifact -Path (Join-Path $script:content 'skills/gamma-tool/evals/grading.json') -Passed 2 -Failed 0 -Total 3 -Assertion @(
                @{ text = 'The first assertion'; passed = $true; evidence = 'Recorded evidence.' }
                @{ text = 'The second assertion'; passed = $true; evidence = 'Recorded evidence.' }
            )
            New-EvalProvenance -Path (Join-Path $script:content 'skills/gamma-tool/evals/grading.provenance.json') -SkillName 'gamma-tool' -SkillSha256 $script:gammaSha -RunId 'run-gap'

            $result = Get-CopilotAtelierSkillHealth -ContentPath $script:content -ReferenceUtc $script:referenceUtc
            $gamma = $result.Skill | Where-Object -FilterScript { $_.Name -eq 'gamma-tool' }

            $gamma.Evaluation.Artifact[0].CountsValid | Should -BeFalse
            $gamma.Evaluation.PassedCount | Should -Be 0
            $gamma.Quality.State | Should -Be 'Unmeasured'
        }

        It 'Should refuse a graded run whose assertion verdict is not a Boolean' {
            New-GradingArtifact -Path (Join-Path $script:content 'skills/gamma-tool/evals/grading.json') -Passed 2 -Failed 0 -Total 2 -Assertion @(
                @{ text = 'The first assertion'; passed = $true; evidence = 'Recorded evidence.' }
                @{ text = 'The second assertion'; passed = 'yes'; evidence = 'Recorded evidence.' }
            )
            New-EvalProvenance -Path (Join-Path $script:content 'skills/gamma-tool/evals/grading.provenance.json') -SkillName 'gamma-tool' -SkillSha256 $script:gammaSha -RunId 'run-verdict'

            $result = Get-CopilotAtelierSkillHealth -ContentPath $script:content -ReferenceUtc $script:referenceUtc
            $gamma = $result.Skill | Where-Object -FilterScript { $_.Name -eq 'gamma-tool' }

            $gamma.Evaluation.Artifact[0].AssertionState | Should -Be 'Invalid'
            $gamma.Evaluation.Artifact[0].CountsValid | Should -BeFalse
            $gamma.Quality.State | Should -Be 'Unmeasured'
        }

        It 'Should report the whole catalog when a graded summary records an out-of-range count' {
            New-GradingArtifact -Path (Join-Path $script:content 'skills/gamma-tool/evals/grading.json') -Passed 3000000000 -Failed 0 -Total 4000000000 -Assertion @(
                @{ text = 'The first assertion'; passed = $true; evidence = 'Recorded evidence.' }
                @{ text = 'The second assertion'; passed = $true; evidence = 'Recorded evidence.' }
            )
            New-EvalProvenance -Path (Join-Path $script:content 'skills/gamma-tool/evals/grading.provenance.json') -SkillName 'gamma-tool' -SkillSha256 $script:gammaSha -RunId 'run-overflow'

            $result = Get-CopilotAtelierSkillHealth -ContentPath $script:content -ReferenceUtc $script:referenceUtc
            $gamma = $result.Skill | Where-Object -FilterScript { $_.Name -eq 'gamma-tool' }

            @($result.Skill).Count | Should -Be 4
            $gamma.Evaluation.Artifact[0].CountsValid | Should -BeFalse
            $gamma.Evaluation.PassedCount | Should -Be 0
            $gamma.Quality.State | Should -Be 'Unmeasured'
        }

        It 'Should count a graded run whose assertion verdicts reconcile with its summary' {
            New-GradingArtifact -Path (Join-Path $script:content 'skills/gamma-tool/evals/grading.json') -Passed 3 -Failed 1
            New-EvalProvenance -Path (Join-Path $script:content 'skills/gamma-tool/evals/grading.provenance.json') -SkillName 'gamma-tool' -SkillSha256 $script:gammaSha -RunId 'run-reconciled'

            $result = Get-CopilotAtelierSkillHealth -ContentPath $script:content -ReferenceUtc $script:referenceUtc
            $gamma = $result.Skill | Where-Object -FilterScript { $_.Name -eq 'gamma-tool' }

            $gamma.Evaluation.Artifact[0].AssertionState | Should -Be 'Valid'
            $gamma.Evaluation.Artifact[0].AssertionCount | Should -Be 4
            $gamma.Evaluation.Artifact[0].CountsValid | Should -BeTrue
            $gamma.Evaluation.ExecutedRunCount | Should -Be 1
            $gamma.Evaluation.PassedCount | Should -Be 3
            $gamma.Evaluation.FailedCount | Should -Be 1
            $gamma.Quality.State | Should -Be 'Failing'
        }

        It 'Should never echo assertion text or evidence from a graded run' {
            New-GradingArtifact -Path (Join-Path $script:content 'skills/gamma-tool/evals/grading.json') -Passed 1 -Failed 1 -Total 2 -Assertion @(
                @{ text = 'CANARY-ASSERTION-TEXT'; passed = $true; evidence = 'CANARY-ASSERTION-EVIDENCE' }
                @{ text = 'CANARY-ASSERTION-TEXT'; passed = $false; evidence = 'CANARY-ASSERTION-EVIDENCE' }
            )
            New-EvalProvenance -Path (Join-Path $script:content 'skills/gamma-tool/evals/grading.provenance.json') -SkillName 'gamma-tool' -SkillSha256 $script:gammaSha -RunId 'run-echo-check'

            $result = Get-CopilotAtelierSkillHealth -ContentPath $script:content -ReferenceUtc $script:referenceUtc
            $text = Get-CopilotAtelierSkillHealth -ContentPath $script:content -ReferenceUtc $script:referenceUtc -AsText

            ($result | ConvertTo-Json -Depth 12 -Compress) | Should -Not -Match 'CANARY'
            $text | Should -Not -Match 'CANARY'
        }
    }

    Context 'Only a counted graded result consumes a run identity' {
        BeforeEach {
            $script:gammaSha = Get-SkillSha -Root $script:content -Name 'gamma-tool'
        }

        It 'Should count a graded run that shares its identifier with a benchmark arm' {
            New-BenchmarkArtifact -Path (Join-Path $script:content 'skills/gamma-tool/evals/benchmark.json')
            New-EvalProvenance -Path (Join-Path $script:content 'skills/gamma-tool/evals/benchmark.provenance.json') -SkillName 'gamma-tool' -SkillSha256 $script:gammaSha -RunId 'run-pair'
            New-GradingArtifact -Path (Join-Path $script:content 'skills/gamma-tool/evals/grading.json') -Passed 2 -Failed 0
            New-EvalProvenance -Path (Join-Path $script:content 'skills/gamma-tool/evals/grading.provenance.json') -SkillName 'gamma-tool' -SkillSha256 $script:gammaSha -RunId 'run-pair'

            $result = Get-CopilotAtelierSkillHealth -ContentPath $script:content -ReferenceUtc $script:referenceUtc
            $gamma = $result.Skill | Where-Object -FilterScript { $_.Name -eq 'gamma-tool' }
            $grading = $gamma.Evaluation.Artifact | Where-Object -FilterScript { $_.Kind -eq 'Grading' }
            $benchmark = $gamma.Evaluation.Artifact | Where-Object -FilterScript { $_.Kind -eq 'Benchmark' }

            $benchmark.Binding | Should -Be 'Bound'
            $grading.Binding | Should -Be 'Bound'
            $gamma.Evaluation.ExecutedRunCount | Should -Be 1
            $gamma.Evaluation.PassedCount | Should -Be 2
            $gamma.Quality.State | Should -Be 'Passing'
        }

        It 'Should expose disagreeing graded results for one run identifier and count none' {
            New-GradingArtifact -Path (Join-Path $script:content 'skills/gamma-tool/evals/grading.json') -Passed 2 -Failed 0
            New-EvalProvenance -Path (Join-Path $script:content 'skills/gamma-tool/evals/grading.provenance.json') -SkillName 'gamma-tool' -SkillSha256 $script:gammaSha -RunId 'run-disagree'
            New-GradingArtifact -Path (Join-Path $script:content 'skills/gamma-tool/evals/zz-grading.json') -Passed 5 -Failed 1
            New-EvalProvenance -Path (Join-Path $script:content 'skills/gamma-tool/evals/zz-grading.provenance.json') -SkillName 'gamma-tool' -SkillSha256 $script:gammaSha -RunId 'run-disagree'

            $result = Get-CopilotAtelierSkillHealth -ContentPath $script:content -ReferenceUtc $script:referenceUtc
            $gamma = $result.Skill | Where-Object -FilterScript { $_.Name -eq 'gamma-tool' }

            @($gamma.Evaluation.Artifact | Where-Object -FilterScript { $_.Binding -eq 'ConflictingRun' }).Count | Should -Be 2
            $gamma.Evaluation.ExecutedRunCount | Should -Be 0
            $gamma.Evaluation.PassedCount | Should -Be 0
            $gamma.Quality.State | Should -Be 'Unmeasured'
            @($result.Suggestion | Where-Object -FilterScript { $_.Skill -eq 'gamma-tool' -and $_.Reason -match 'disagree' }) |
                Should -Not -BeNullOrEmpty
        }

        It 'Should not let an uncountable graded result consume the run identifier' {
            New-GradingArtifact -Path (Join-Path $script:content 'skills/gamma-tool/evals/a-grading.json') -Passed 4 -Failed 0 -OmitAssertion
            New-EvalProvenance -Path (Join-Path $script:content 'skills/gamma-tool/evals/a-grading.provenance.json') -SkillName 'gamma-tool' -SkillSha256 $script:gammaSha -RunId 'run-once'
            New-GradingArtifact -Path (Join-Path $script:content 'skills/gamma-tool/evals/b-grading.json') -Passed 2 -Failed 0
            New-EvalProvenance -Path (Join-Path $script:content 'skills/gamma-tool/evals/b-grading.provenance.json') -SkillName 'gamma-tool' -SkillSha256 $script:gammaSha -RunId 'run-once'

            $result = Get-CopilotAtelierSkillHealth -ContentPath $script:content -ReferenceUtc $script:referenceUtc
            $gamma = $result.Skill | Where-Object -FilterScript { $_.Name -eq 'gamma-tool' }
            $counted = $gamma.Evaluation.Artifact | Where-Object -FilterScript { $_.RelativePath -match 'b-grading.json$' }

            $counted.Binding | Should -Be 'Bound'
            $gamma.Evaluation.ExecutedRunCount | Should -Be 1
            $gamma.Evaluation.PassedCount | Should -Be 2
            $gamma.Quality.State | Should -Be 'Passing'
        }
    }

    Context 'Provenance records a real completion instant' {
        It 'Should refuse provenance whose completion instant is <Case>' -ForEach @(
            @{ Case = 'absent'; CompletedUtc = $null }
            @{ Case = 'malformed'; CompletedUtc = '30 August 2026' }
            @{ Case = 'earlier than the plausible floor'; CompletedUtc = '2019-12-31T23:59:59Z' }
            @{ Case = 'later than the reference instant'; CompletedUtc = '2026-09-02T00:00:00Z' }
        ) {
            $sha = Get-SkillSha -Root $script:content -Name 'gamma-tool'
            New-GradingArtifact -Path (Join-Path $script:content 'skills/gamma-tool/evals/grading.json') -Passed 4 -Failed 0
            New-EvalProvenance -Path (Join-Path $script:content 'skills/gamma-tool/evals/grading.provenance.json') -SkillName 'gamma-tool' -SkillSha256 $sha -RunId 'run-time' -CompletedUtc $CompletedUtc

            $result = Get-CopilotAtelierSkillHealth -ContentPath $script:content -ReferenceUtc $script:referenceUtc
            $gamma = $result.Skill | Where-Object -FilterScript { $_.Name -eq 'gamma-tool' }

            $gamma.Evaluation.Artifact[0].Binding | Should -Be 'Unbound'
            $gamma.Evaluation.ExecutedRunCount | Should -Be 0
            $gamma.Evaluation.PassedCount | Should -Be 0
            $gamma.Quality.State | Should -Be 'Unmeasured'
        }
    }

    Context 'Metadata parsing stays conservative' {
        It 'Should not report a parsed metadata block for a fence that is not supported metadata' {
            $skillPath = Join-Path $script:content 'skills/gamma-tool/SKILL.md'
            Set-Content -LiteralPath $skillPath -Encoding utf8 -Value @(
                '---'
                'name: gamma-tool'
                'description:'
                '  - one'
                '  - two'
                '---'
                ''
                'Body.'
            )

            $result = Get-CopilotAtelierSkillHealth -ContentPath $script:content -ReferenceUtc $script:referenceUtc
            $gamma = $result.Skill | Where-Object -FilterScript { $_.Name -eq 'gamma-tool' }

            $gamma.Structure.FrontmatterFenceFound | Should -BeTrue
            $gamma.Structure.MetadataParseState | Should -Be 'Unsupported'
            $gamma.Structure.FrontmatterParsed | Should -BeFalse
        }
    }

    Context 'Import validation' {
        It 'Should reject a record that carries an unsupported property' {
            $sha = Get-SkillSha -Root $script:content -Name 'alpha-tool'
            $record = New-ObservationRecord -EventId 'x1' -EventType 'SkillActivation' -SkillName 'alpha-tool' -SkillSha256 $sha -TimestampUtc '2026-08-30T10:00:00Z'
            $record['promptText'] = 'CANARY-PROMPT-BODY'
            $observationPath = Join-Path $script:observationRoot 'unsupported.json'
            New-ObservationFile -Path $observationPath -Record @($record)

            $result = Get-CopilotAtelierSkillHealth -ContentPath $script:content -ObservationPath $observationPath -ReferenceUtc $script:referenceUtc

            $result.Observation.AcceptedCount | Should -Be 0
            @($result.Observation.RejectedRecord).Count | Should -Be 1
            $result.Observation.RejectedRecord[0].Reason | Should -Match 'unsupported'
        }

        It 'Should never echo an imported value in a rejection reason' {
            $sha = Get-SkillSha -Root $script:content -Name 'alpha-tool'
            $record = New-ObservationRecord -EventId ('CANARY-SECRET-' + ('a' * 200)) -EventType 'SkillActivation' -SkillName 'alpha-tool' -SkillSha256 $sha -TimestampUtc '2026-08-30T10:00:00Z'
            $record['note'] = 'CANARY-SECRET-BODY'
            $observationPath = Join-Path $script:observationRoot 'secret.json'
            New-ObservationFile -Path $observationPath -Record @($record)

            $result = Get-CopilotAtelierSkillHealth -ContentPath $script:content -ObservationPath $observationPath -ReferenceUtc $script:referenceUtc

            ($result | ConvertTo-Json -Depth 12) | Should -Not -Match 'CANARY-SECRET'
        }

        It 'Should reject a malformed observation file without failing the report' {
            $observationPath = Join-Path $script:observationRoot 'malformed.json'
            New-Item -ItemType Directory -Path $script:observationRoot -Force | Out-Null
            Set-Content -LiteralPath $observationPath -Encoding utf8 -Value '{ "records": [ '

            $result = Get-CopilotAtelierSkillHealth -ContentPath $script:content -ObservationPath $observationPath -ReferenceUtc $script:referenceUtc

            @($result.Observation.RejectedFile).Count | Should -Be 1
            $result.Observation.AcceptedCount | Should -Be 0
            @($result.Skill).Count | Should -Be 4
        }

        It 'Should reject an unsupported schema version for the whole file' {
            $sha = Get-SkillSha -Root $script:content -Name 'alpha-tool'
            $observationPath = Join-Path $script:observationRoot 'schema.json'
            New-ObservationFile -SchemaVersion 99 -Path $observationPath -Record @(
                New-ObservationRecord -EventId 's1' -EventType 'SkillActivation' -SkillName 'alpha-tool' -SkillSha256 $sha -TimestampUtc '2026-08-30T10:00:00Z'
            )

            $result = Get-CopilotAtelierSkillHealth -ContentPath $script:content -ObservationPath $observationPath -ReferenceUtc $script:referenceUtc

            @($result.Observation.RejectedFile).Count | Should -Be 1
            $result.Observation.RejectedFile[0].Reason | Should -Match 'schema'
            $result.Observation.AcceptedCount | Should -Be 0
        }

        It 'Should reject an unsupported event type' {
            $sha = Get-SkillSha -Root $script:content -Name 'alpha-tool'
            $observationPath = Join-Path $script:observationRoot 'eventtype.json'
            New-ObservationFile -Path $observationPath -Record @(
                New-ObservationRecord -EventId 'u1' -EventType 'SkillRetired' -SkillName 'alpha-tool' -SkillSha256 $sha -TimestampUtc '2026-08-30T10:00:00Z'
            )

            $result = Get-CopilotAtelierSkillHealth -ContentPath $script:content -ObservationPath $observationPath -ReferenceUtc $script:referenceUtc

            @($result.Observation.RejectedRecord).Count | Should -Be 1
            $result.Observation.RejectedRecord[0].Field | Should -Be 'eventType'
        }

        It 'Should deduplicate an imported event that appears in two files' {
            $sha = Get-SkillSha -Root $script:content -Name 'alpha-tool'
            $record = @(New-ObservationRecord -EventId 'dup-1' -EventType 'SkillActivation' -SkillName 'alpha-tool' -SkillSha256 $sha -TimestampUtc '2026-08-30T10:00:00Z')
            New-ObservationFile -Path (Join-Path $script:observationRoot 'one.json') -Record $record
            New-ObservationFile -Path (Join-Path $script:observationRoot 'two.json') -Record $record

            $result = Get-CopilotAtelierSkillHealth -ContentPath $script:content -ObservationPath $script:observationRoot -ReferenceUtc $script:referenceUtc
            $alpha = $result.Skill | Where-Object -FilterScript { $_.Name -eq 'alpha-tool' }

            $result.Observation.FileCount | Should -Be 2
            $result.Observation.DuplicateCount | Should -Be 1
            $result.Observation.AcceptedCount | Should -Be 1
            $alpha.Usage.ActivationCount | Should -Be 1
        }

        It 'Should expose the observation time window' {
            $sha = Get-SkillSha -Root $script:content -Name 'alpha-tool'
            New-ObservationFile -Path (Join-Path $script:observationRoot 'window.json') -Record @(
                New-ObservationRecord -EventId 'w1' -EventType 'SkillActivation' -SkillName 'alpha-tool' -SkillSha256 $sha -TimestampUtc '2026-06-01T00:00:00Z'
                New-ObservationRecord -EventId 'w2' -EventType 'SkillActivation' -SkillName 'alpha-tool' -SkillSha256 $sha -TimestampUtc '2026-08-30T00:00:00Z'
            )

            $result = Get-CopilotAtelierSkillHealth -ContentPath $script:content -ObservationPath $script:observationRoot -ReferenceUtc $script:referenceUtc

            $result.Observation.WindowStartUtc | Should -Not -BeNullOrEmpty
            $result.Observation.WindowEndUtc | Should -Not -BeNullOrEmpty
            $result.Observation.WindowDay | Should -Be 90
        }

        It 'Should downgrade an observed-trust claim while no supported capture exists' {
            $sha = Get-SkillSha -Root $script:content -Name 'alpha-tool'
            New-ObservationFile -Trust 'Observed' -Path (Join-Path $script:observationRoot 'trust.json') -Record @(
                New-ObservationRecord -EventId 'tr1' -EventType 'SkillActivation' -SkillName 'alpha-tool' -SkillSha256 $sha -TimestampUtc '2026-08-30T00:00:00Z'
            )

            $result = Get-CopilotAtelierSkillHealth -ContentPath $script:content -ObservationPath $script:observationRoot -ReferenceUtc $script:referenceUtc

            @($result.Observation.DeclaredTrust) | Should -Contain 'Observed'
            $result.Observation.EffectiveTrust | Should -Be 'Imported'
            $result.Observation.TrustNote | Should -Not -BeNullOrEmpty
        }

        It 'Should bind an observation to the Skill body it names and label a version mismatch' {
            $observationPath = Join-Path $script:observationRoot 'version.json'
            New-ObservationFile -Path $observationPath -Record @(
                New-ObservationRecord -EventId 'v1' -EventType 'SkillActivation' -SkillName 'alpha-tool' -SkillSha256 ('b' * 64) -TimestampUtc '2026-08-30T00:00:00Z'
            )

            $result = Get-CopilotAtelierSkillHealth -ContentPath $script:content -ObservationPath $observationPath -ReferenceUtc $script:referenceUtc
            $alpha = $result.Skill | Where-Object -FilterScript { $_.Name -eq 'alpha-tool' }

            $alpha.Usage.ActivationCount | Should -Be 0
            $alpha.Usage.OtherBodyRecordCount | Should -Be 1
            $alpha.Usage.BodyVersionMismatch | Should -BeTrue
        }

        It 'Should report an observation naming a Skill that is not installed' {
            $observationPath = Join-Path $script:observationRoot 'unknown.json'
            New-ObservationFile -Path $observationPath -Record @(
                New-ObservationRecord -EventId 'n1' -EventType 'SkillActivation' -SkillName 'absent-tool' -SkillSha256 ('c' * 64) -TimestampUtc '2026-08-30T00:00:00Z'
            )

            $result = Get-CopilotAtelierSkillHealth -ContentPath $script:content -ObservationPath $observationPath -ReferenceUtc $script:referenceUtc

            @($result.Observation.UnknownSkillName) | Should -Contain 'absent-tool'
        }

        It 'Should mark observations older than the staleness horizon as stale' {
            $sha = Get-SkillSha -Root $script:content -Name 'alpha-tool'
            $observationPath = Join-Path $script:observationRoot 'stale.json'
            New-ObservationFile -Path $observationPath -Record @(
                New-ObservationRecord -EventId 'st1' -EventType 'SkillActivation' -SkillName 'alpha-tool' -SkillSha256 $sha -TimestampUtc '2025-01-01T00:00:00Z'
            )

            $result = Get-CopilotAtelierSkillHealth -ContentPath $script:content -ObservationPath $observationPath -ReferenceUtc $script:referenceUtc
            $alpha = $result.Skill | Where-Object -FilterScript { $_.Name -eq 'alpha-tool' }

            $alpha.Freshness.ObservationState | Should -Be 'Stale'
            $alpha.Freshness.ObservationAgeDay | Should -BeGreaterThan 90
        }

        It 'Should reject a timestamp in the future relative to the reference time' {
            $sha = Get-SkillSha -Root $script:content -Name 'alpha-tool'
            $observationPath = Join-Path $script:observationRoot 'future.json'
            New-ObservationFile -Path $observationPath -Record @(
                New-ObservationRecord -EventId 'f1' -EventType 'SkillActivation' -SkillName 'alpha-tool' -SkillSha256 $sha -TimestampUtc '2030-01-01T00:00:00Z'
            )

            $result = Get-CopilotAtelierSkillHealth -ContentPath $script:content -ObservationPath $observationPath -ReferenceUtc $script:referenceUtc

            @($result.Observation.RejectedRecord).Count | Should -Be 1
            $result.Observation.RejectedRecord[0].Field | Should -Be 'timestampUtc'
        }

        It 'Should refuse an observation file larger than the documented bound' {
            $observationPath = Join-Path $script:observationRoot 'large.json'
            $filler = 'x' * 1200000
            Set-Content -LiteralPath $observationPath -Encoding utf8 -Value ('{ "schemaVersion": 1, "filler": "' + $filler + '" }')

            $result = Get-CopilotAtelierSkillHealth -ContentPath $script:content -ObservationPath $observationPath -ReferenceUtc $script:referenceUtc

            @($result.Observation.RejectedFile).Count | Should -Be 1
            $result.Observation.RejectedFile[0].Reason | Should -Match 'size'
        }

        It 'Should throw a directed error when an observation path does not exist' {
            { Get-CopilotAtelierSkillHealth -ContentPath $script:content -ObservationPath (Join-Path $TestDrive 'no-such-observations') -ReferenceUtc $script:referenceUtc } |
                Should -Throw -ExpectedMessage '*does not exist*'
        }
    }

    Context 'Suggestions never decide' {
        It 'Should never suggest retirement from absent observations' {
            $result = Get-CopilotAtelierSkillHealth -ContentPath $script:content -ReferenceUtc $script:referenceUtc

            @($result.Suggestion | Where-Object -FilterScript { $_.Kind -eq 'RetirementReview' }) | Should -BeNullOrEmpty
            @($result.Suggestion | Where-Object -FilterScript { $_.Kind -eq 'Retire' }) | Should -BeNullOrEmpty
        }

        It 'Should never suggest retirement from a sparse observation window' {
            $sha = Get-SkillSha -Root $script:content -Name 'beta-tool'
            $observationPath = Join-Path $script:observationRoot 'sparse.json'
            New-ObservationFile -Path $observationPath -Record @(
                New-ObservationRecord -EventId 'sp1' -EventType 'SkillActivation' -SkillName 'beta-tool' -SkillSha256 $sha -TimestampUtc '2026-08-29T00:00:00Z' -SessionId 's1'
                New-ObservationRecord -EventId 'sp2' -EventType 'SkillActivation' -SkillName 'beta-tool' -SkillSha256 $sha -TimestampUtc '2026-08-30T00:00:00Z' -SessionId 's2'
            )

            $result = Get-CopilotAtelierSkillHealth -ContentPath $script:content -ObservationPath $observationPath -ReferenceUtc $script:referenceUtc

            @($result.Suggestion | Where-Object -FilterScript { $_.Kind -eq 'RetirementReview' }) | Should -BeNullOrEmpty
        }

        It 'Should never let records for one Skill imply that another Skill is unused' {
            $sha = Get-SkillSha -Root $script:content -Name 'alpha-tool'
            $record = [System.Collections.Generic.List[object]]::new()
            for ($index = 0; $index -lt 40; $index++)
            {
                $stamp = $script:referenceUtc.AddDays(-60 + $index).ToString('yyyy-MM-ddTHH:mm:ssZ')
                $record.Add((New-ObservationRecord -EventId "ok-$index" -EventType 'SkillActivation' -SkillName 'alpha-tool' -SkillSha256 $sha -TimestampUtc $stamp -SessionId "session-$index"))
            }
            $observationPath = Join-Path $script:observationRoot 'rich.json'
            New-ObservationFile -Path $observationPath -Record $record.ToArray()

            $result = Get-CopilotAtelierSkillHealth -ContentPath $script:content -ObservationPath $observationPath -ReferenceUtc $script:referenceUtc

            @($result.Suggestion | Where-Object -FilterScript { $_.Kind -eq 'RetirementReview' }) |
                Should -BeNullOrEmpty -Because 'a wide window for alpha-tool says nothing about gamma-tool'
            $gamma = $result.Skill | Where-Object -FilterScript { $_.Name -eq 'gamma-tool' }
            $gamma.Usage.CoverageDeclared | Should -BeFalse
            $gamma.Usage.Coverage | Should -Be 'NoObservations'
        }

        It 'Should never suggest retirement from file-read records alone' {
            $sha = Get-SkillSha -Root $script:content -Name 'gamma-tool'
            $record = [System.Collections.Generic.List[object]]::new()
            for ($index = 0; $index -lt 30; $index++)
            {
                $stamp = $script:referenceUtc.AddDays(-50 + $index).ToString('yyyy-MM-ddTHH:mm:ssZ')
                $record.Add((New-ObservationRecord -EventId "rd-$index" -EventType 'SkillFileRead' -SkillName 'gamma-tool' -SkillSha256 $sha -TimestampUtc $stamp -SessionId "session-$index"))
            }
            New-ObservationFile -Path (Join-Path $script:observationRoot 'reads.json') -Record $record.ToArray()

            $result = Get-CopilotAtelierSkillHealth -ContentPath $script:content -ObservationPath $script:observationRoot -ReferenceUtc $script:referenceUtc

            @($result.Suggestion | Where-Object -FilterScript { $_.Kind -eq 'RetirementReview' }) |
                Should -BeNullOrEmpty -Because 'a read is evidence of a read, never of complete activation capture'
        }

        It 'Should suggest a human retirement review only from a validated coverage declaration' {
            $observationPath = Join-Path $script:observationRoot 'covered.json'
            New-ObservationFile -Path $observationPath -Record @(
                New-ObservationRecord -EventId 'c1' -EventType 'SkillActivation' -SkillName 'alpha-tool' -SkillSha256 (Get-SkillSha -Root $script:content -Name 'alpha-tool') -TimestampUtc '2026-08-30T00:00:00Z'
            ) -Coverage @(
                New-CoverageDeclaration -SkillName 'gamma-tool' -SkillSha256 (Get-SkillSha -Root $script:content -Name 'gamma-tool')
            )

            $result = Get-CopilotAtelierSkillHealth -ContentPath $script:content -ObservationPath $observationPath -ReferenceUtc $script:referenceUtc

            $review = @($result.Suggestion | Where-Object -FilterScript { $_.Kind -eq 'RetirementReview' })
            @($review).Count | Should -Be 1
            $review[0].Skill | Should -Be 'gamma-tool'
            $review[0].Decision | Should -Be 'HumanReviewRequired'
            ($review[0].Evidence -join ' ') | Should -Match 'covered.json'
            $gamma = $result.Skill | Where-Object -FilterScript { $_.Name -eq 'gamma-tool' }
            $gamma.Usage.CoverageDeclared | Should -BeTrue
        }

        It 'Should ignore a coverage declaration that names a different body' {
            $observationPath = Join-Path $script:observationRoot 'mismatched.json'
            New-ObservationFile -Path $observationPath -Record @() -Coverage @(
                New-CoverageDeclaration -SkillName 'gamma-tool' -SkillSha256 ('d' * 64)
            )

            $result = Get-CopilotAtelierSkillHealth -ContentPath $script:content -ObservationPath $observationPath -ReferenceUtc $script:referenceUtc

            @($result.Suggestion | Where-Object -FilterScript { $_.Kind -eq 'RetirementReview' }) | Should -BeNullOrEmpty
            $gamma = $result.Skill | Where-Object -FilterScript { $_.Name -eq 'gamma-tool' }
            $gamma.Usage.CoverageDeclared | Should -BeFalse
        }

        It 'Should ignore a coverage declaration whose window is too thin to judge' {
            $observationPath = Join-Path $script:observationRoot 'thin.json'
            New-ObservationFile -Path $observationPath -Record @() -Coverage @(
                New-CoverageDeclaration -SkillName 'gamma-tool' -SkillSha256 (Get-SkillSha -Root $script:content -Name 'gamma-tool') -WindowStartUtc '2026-08-28T00:00:00Z' -SessionCount 3
            )

            $result = Get-CopilotAtelierSkillHealth -ContentPath $script:content -ObservationPath $observationPath -ReferenceUtc $script:referenceUtc

            @($result.Suggestion | Where-Object -FilterScript { $_.Kind -eq 'RetirementReview' }) | Should -BeNullOrEmpty
        }

        It 'Should ignore a coverage declaration that does not claim complete activation capture' {
            $observationPath = Join-Path $script:observationRoot 'incomplete.json'
            New-ObservationFile -Path $observationPath -Record @() -Coverage @(
                New-CoverageDeclaration -SkillName 'gamma-tool' -SkillSha256 (Get-SkillSha -Root $script:content -Name 'gamma-tool') -ActivationCaptureComplete $false
            )

            $result = Get-CopilotAtelierSkillHealth -ContentPath $script:content -ObservationPath $observationPath -ReferenceUtc $script:referenceUtc

            @($result.Suggestion | Where-Object -FilterScript { $_.Kind -eq 'RetirementReview' }) | Should -BeNullOrEmpty
        }

        It 'Should ignore a coverage declaration whose window ended before the staleness horizon' {
            $observationPath = Join-Path $script:observationRoot 'stale-coverage.json'
            New-ObservationFile -Path $observationPath -Record @() -Coverage @(
                New-CoverageDeclaration -SkillName 'gamma-tool' -SkillSha256 (Get-SkillSha -Root $script:content -Name 'gamma-tool') -WindowStartUtc '2025-01-01T00:00:00Z' -WindowEndUtc '2025-03-01T00:00:00Z'
            )

            $result = Get-CopilotAtelierSkillHealth -ContentPath $script:content -ObservationPath $observationPath -ReferenceUtc $script:referenceUtc

            @($result.Suggestion | Where-Object -FilterScript { $_.Kind -eq 'RetirementReview' }) |
                Should -BeNullOrEmpty -Because 'a window that closed long ago cannot describe the current body'
        }

        It 'Should never suggest retirement for a mandatory Skill even under declared coverage' {
            $mandatory = 'memory-bank'
            New-HealthSkill -Root $script:content -Name $mandatory -Description 'A mandatory Skill fixture. USE FOR: nothing in particular.'
            $observationPath = Join-Path $script:observationRoot 'mandatory.json'
            New-ObservationFile -Path $observationPath -Record @() -Coverage @(
                New-CoverageDeclaration -SkillName $mandatory -SkillSha256 (Get-SkillSha -Root $script:content -Name $mandatory)
            )

            $result = Get-CopilotAtelierSkillHealth -ContentPath $script:content -ObservationPath $observationPath -ReferenceUtc $script:referenceUtc

            @($result.Suggestion | Where-Object -FilterScript { $_.Kind -eq 'RetirementReview' -and $_.Skill -eq $mandatory }) | Should -BeNullOrEmpty
        }

        It 'Should suggest consolidation for an overlapping pair and link the evidence' {
            $result = Get-CopilotAtelierSkillHealth -ContentPath $script:content -ReferenceUtc $script:referenceUtc

            $consolidate = @($result.Suggestion | Where-Object -FilterScript { $_.Kind -eq 'Consolidate' -and $_.Skill -eq 'alpha-tool' })
            @($consolidate).Count | Should -Be 1
            @($consolidate[0].Evidence) | Should -Not -BeNullOrEmpty
            $consolidate[0].Decision | Should -Be 'HumanReviewRequired'
        }

        It 'Should suggest investigating an executed evaluation that failed' {
            $result = Get-CopilotAtelierSkillHealth -ContentPath $script:content -ReferenceUtc $script:referenceUtc

            $investigate = @($result.Suggestion | Where-Object -FilterScript { $_.Kind -eq 'Investigate' -and $_.Skill -eq 'beta-tool' })
            @($investigate).Count | Should -BeGreaterThan 0
            ($investigate.Evidence -join ' ') | Should -Match 'grading.json'
        }

        It 'Should link every suggestion to at least one local evidence item' {
            $result = Get-CopilotAtelierSkillHealth -ContentPath $script:content -ReferenceUtc $script:referenceUtc

            foreach ($suggestion in $result.Suggestion)
            {
                @($suggestion.Evidence).Count | Should -BeGreaterThan 0 -Because "$($suggestion.Kind) for $($suggestion.Skill) must cite evidence"
            }
        }
    }

    Context 'Read-only behavior' {
        It 'Should not change the inspected content or the observation input' {
            $sha = Get-SkillSha -Root $script:content -Name 'alpha-tool'
            $observationPath = Join-Path $script:observationRoot 'readonly.json'
            New-ObservationFile -Path $observationPath -Record @(
                New-ObservationRecord -EventId 'ro1' -EventType 'SkillActivation' -SkillName 'alpha-tool' -SkillSha256 $sha -TimestampUtc '2026-08-30T00:00:00Z'
            )
            $contentBefore = Get-TreeSnapshot -Root $script:content
            $observationBefore = Get-TreeSnapshot -Root $script:observationRoot

            $null = Get-CopilotAtelierSkillHealth -ContentPath $script:content -ObservationPath $observationPath -ReferenceUtc $script:referenceUtc

            Get-TreeSnapshot -Root $script:content | Should -Be $contentBefore
            Get-TreeSnapshot -Root $script:observationRoot | Should -Be $observationBefore
        }

        It 'Should return the same report for the same inputs' {
            $first = Get-CopilotAtelierSkillHealth -ContentPath $script:content -ReferenceUtc $script:referenceUtc
            $second = Get-CopilotAtelierSkillHealth -ContentPath $script:content -ReferenceUtc $script:referenceUtc

            ($first | ConvertTo-Json -Depth 12) | Should -Be ($second | ConvertTo-Json -Depth 12)
        }

        It 'Should throw a directed error when the content path is missing' {
            { Get-CopilotAtelierSkillHealth -ContentPath (Join-Path $TestDrive 'absent-content') -ReferenceUtc $script:referenceUtc } |
                Should -Throw -ExpectedMessage '*does not exist*'
        }

        It 'Should refuse discoverability material reached through a linked directory' -Skip:(-not $script:canCreateDirectoryLink) {
            $outside = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $outside -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $outside 'trigger-queries.alpha-tool.json') -Encoding utf8 -Value '[]'
            Remove-Item -LiteralPath (Join-Path $script:content 'skills/agent-evals/assets') -Recurse -Force
            New-Item -ItemType $script:linkItemType -Path (Join-Path $script:content 'skills/agent-evals/assets') -Target $outside | Out-Null

            { Get-CopilotAtelierSkillHealth -ContentPath $script:content -ReferenceUtc $script:referenceUtc } |
                Should -Throw -ExpectedMessage '*reparse*'
        }
    }

    Context 'Presentation and help' {
        It 'Should return a human-readable summary with -AsText' {
            $text = Get-CopilotAtelierSkillHealth -ContentPath $script:content -ReferenceUtc $script:referenceUtc -AsText

            $text | Should -BeOfType [System.String]
            $text | Should -Match 'Skill health report'
            $text | Should -Match 'Usage'
            $text | Should -Match 'Discoverability'
            $text | Should -Match 'Observation gap'
            $text | Should -Match 'suggestion'
        }

        It 'Should document every evidence source, the retention choice, and the observation gap in help' {
            $help = Get-Help -Name Get-CopilotAtelierSkillHealth -Full | Out-String

            $help | Should -Match 'read-only'
            $help | Should -Match 'capture is disabled by default'
            $help | Should -Match 'reliable Skill-activation'
            $help | Should -Match 'may expose a contract this check cannot'
            $help | Should -Match 'prompt text'
            $help | Should -Match 'Imported'
            $help | Should -Match 'unknown'
        }

        It 'Should never claim that the report retires or changes a Skill' {
            $help = Get-Help -Name Get-CopilotAtelierSkillHealth -Full | Out-String

            $help | Should -Match 'never'
            $help | Should -Not -Match 'automatically removes'
        }
    }
}
