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
}
