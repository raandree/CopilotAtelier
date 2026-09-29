Describe 'CI admission decisions' -Tag 'Unit' {
    BeforeAll {
        Import-Module powershell-yaml -ErrorAction Stop
        $script:workflow = ConvertFrom-Yaml -Yaml (
            Get-Content -LiteralPath (Join-Path $PSScriptRoot '../.github/workflows/ci.yml') -Raw)

        function Invoke-CiAdmission {
            $step = @($script:workflow.jobs.select.steps | Where-Object id -eq 'decision')
            $step | Should -HaveCount 1 -Because 'the tested script must be the one executed by CI'
            & ([scriptblock]::Create($step[0].run))
            Get-Content -LiteralPath $env:GITHUB_OUTPUT -Raw | ConvertFrom-StringData
        }
    }

    BeforeEach {
        $script:environment = @{
            GITHUB_EVENT_NAME = 'push'
            GITHUB_REF = 'refs/heads/ai/eval-gate-integrity'
            GITHUB_REF_NAME = 'ai/eval-gate-integrity'
            GITHUB_SHA = 'a' * 40
            GITHUB_REPOSITORY = 'raandree/CopilotAtelier'
            GITHUB_REPOSITORY_OWNER = 'raandree'
            GITHUB_API_URL = 'https://api.github.com'
            GITHUB_OUTPUT = Join-Path $TestDrive ('output-' + [guid]::NewGuid().ToString('N'))
            BEFORE_SHA = 'b' * 40
            GH_TOKEN = 'test-placeholder'
            defaultBranch = 'main'
        }
        $script:savedEnvironment = @{}
        foreach ($key in $script:environment.Keys) {
            $script:savedEnvironment[$key] = [Environment]::GetEnvironmentVariable($key)
            [Environment]::SetEnvironmentVariable($key, $script:environment[$key])
        }
        $exitVariable = Get-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue
        $script:savedExitCode = [pscustomobject]@{
            Exists = $null -ne $exitVariable
            Value = $exitVariable.Value
        }
        $script:pulls = @()
        $script:changedPaths = @('source/Public/Get-Example.ps1')
        $script:gitExitCode = 0
        Mock Invoke-RestMethod { ,$script:pulls }
        Mock git {
            Set-Variable -Name LASTEXITCODE -Value $script:gitExitCode -Scope Global
            $script:changedPaths
        }
    }

    AfterEach {
        foreach ($key in $script:savedEnvironment.Keys) {
            [Environment]::SetEnvironmentVariable($key, $script:savedEnvironment[$key])
        }
        if ($script:savedExitCode.Exists) {
            Set-Variable -Name LASTEXITCODE -Value $script:savedExitCode.Value -Scope Global
        }
        else { Remove-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue }
    }

    It 'Runs the topic matrix when no matching PR exists' {
        (Invoke-CiAdmission).run_ci | Should -BeExactly 'true'
        Should -Invoke Invoke-RestMethod -Times 1 -Exactly
    }

    It 'Defers duplicate topic pushes only to an open PR for the same repository and SHA' {
        $script:pulls = @([pscustomobject]@{
            state = 'open'
            head = @{ sha = $env:GITHUB_SHA; ref = $env:GITHUB_REF_NAME; repo = @{ full_name = $env:GITHUB_REPOSITORY } }
            base = @{ ref = 'main' }
        })
        (Invoke-CiAdmission).run_ci | Should -BeExactly 'false'
        Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
            $Uri -like '*head=raandree%3Aai%2Feval-gate-integrity*' -and $Uri -like '*base=main*'
        }
    }

    It 'Does not suppress a push for a stale or unrelated PR: <Mismatch>' -ForEach @(
        @{ Mismatch = 'sha' }, @{ Mismatch = 'repository' }, @{ Mismatch = 'base' }, @{ Mismatch = 'closed' }
    ) {
        $pr = [pscustomobject]@{
            state = 'open'
            head = @{ sha = $env:GITHUB_SHA; ref = $env:GITHUB_REF_NAME; repo = @{ full_name = $env:GITHUB_REPOSITORY } }
            base = @{ ref = 'main' }
        }
        switch ($Mismatch) {
            'sha' { $pr.head.sha = 'c' * 40 }
            'repository' { $pr.head.repo.full_name = 'someone/CopilotAtelier' }
            'base' { $pr.base.ref = 'other' }
            'closed' { $pr.state = 'closed' }
        }
        $script:pulls = @($pr)
        (Invoke-CiAdmission).run_ci | Should -BeExactly 'true'
    }

    It 'Fails visibly when the PR lookup fails rather than skipping checks' {
        Mock Invoke-RestMethod { throw 'simulated lookup unavailable' }
        { Invoke-CiAdmission } | Should -Throw '*simulated lookup unavailable*'
        Test-Path -LiteralPath $env:GITHUB_OUTPUT | Should -BeFalse
    }

    It 'Runs PRs and manual or tag requests without a PR lookup: <EventName> <Ref>' -ForEach @(
        @{ EventName = 'pull_request'; Ref = 'refs/pull/42/merge' },
        @{ EventName = 'workflow_dispatch'; Ref = 'refs/heads/main' },
        @{ EventName = 'push'; Ref = 'refs/tags/v5.1.0' }
    ) {
        $env:GITHUB_EVENT_NAME = $EventName
        $env:GITHUB_REF = $Ref
        $result = Invoke-CiAdmission
        $result.run_ci | Should -BeExactly 'true'
        $result.publish | Should -BeExactly 'true'
        Should -Invoke Invoke-RestMethod -Times 0 -Exactly
        Should -Invoke git -Times 0 -Exactly
    }

    It 'Validates changelog-only main pushes but never republishes them' {
        $env:GITHUB_REF = 'refs/heads/main'
        $script:changedPaths = @('CHANGELOG.md')
        $result = Invoke-CiAdmission
        $result.run_ci | Should -BeExactly 'true'
        $result.publish | Should -BeExactly 'false'
        Should -Invoke git -Times 1 -Exactly
    }

    It 'Preserves publication for main code changes alongside the changelog' {
        $env:GITHUB_REF = 'refs/heads/main'
        $script:changedPaths = @('CHANGELOG.md', 'source/Public/Get-Example.ps1')
        $result = Invoke-CiAdmission
        $result.run_ci | Should -BeExactly 'true'
        $result.publish | Should -BeExactly 'true'
    }

    It 'Fails visibly when changed paths cannot be determined' {
        $env:GITHUB_REF = 'refs/heads/main'
        $script:gitExitCode = 1
        { Invoke-CiAdmission } | Should -Throw '*Cannot determine changed paths*'
    }

    It 'Rejects an invalid before revision without interpreting it as a git option' {
        $env:GITHUB_REF = 'refs/heads/main'
        $env:BEFORE_SHA = '--help'
        { Invoke-CiAdmission } | Should -Throw '*Invalid before revision*'
        Should -Invoke git -Times 0 -Exactly
    }

    It 'Preserves an initial default-branch publication without diffing the zero SHA' {
        $env:GITHUB_REF = 'refs/heads/main'
        $env:BEFORE_SHA = '0' * 40
        (Invoke-CiAdmission).publish | Should -BeExactly 'true'
        Should -Invoke git -Times 0 -Exactly
    }
}
