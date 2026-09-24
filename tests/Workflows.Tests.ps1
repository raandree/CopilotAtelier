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
            "(github.ref == 'refs/heads/main' || startsWith(github.ref, 'refs/tags/'))"
        )
        $workflow.jobs.deploy.needs | Should -Contain 'build'
        $workflow.jobs.deploy.needs | Should -Contain 'test'
        $workflow.on.push['paths-ignore'] | Should -Contain 'CHANGELOG.md'
        $workflow.on.push.tags | Should -Contain 'v*'
        $workflow.on.push.tags | Should -Contain '!v*-*'
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
}
