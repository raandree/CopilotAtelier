# The travel-handbook scripts are Python and are tested with pytest under uv.
# This wrapper runs that suite inside the Pester run, so the build's test task
# covers it; pytest's own output becomes the failure message.

Describe 'travel-handbook script toolkit' -Tag 'Unit' {

    BeforeAll {
        $script:repoRoot = Split-Path -Parent $PSScriptRoot
        $script:uvCommand = Get-Command -Name 'uv' -CommandType Application -ErrorAction SilentlyContinue
        $script:hasUv = $null -ne $script:uvCommand

        # The packages the scripts declare in their PEP 723 headers, plus pytest.
        # The suite is offline: every network call is replaced by synthetic data.
        $script:pytestArgument = @(
            'run', '--quiet'
            '--with', 'pytest'
            '--with', 'matplotlib>=3.8'
            '--with', 'pillow>=10.3'
            '--with', 'requests>=2.32.4'
            '--with', 'astral>=3.2'
            '--with', 'ruamel.yaml>=0.18'
            '--with', 'tzdata'
            'python', '-m', 'pytest', 'tests/TravelHandbook', '-q', '-p', 'no:cacheprovider'
        )

        # UTF-8 for Cyrillic test data, no bytecode written into the repository,
        # and a matplotlib backend that needs no display.
        $script:pytestEnvironment = @{
            PYTHONUTF8              = '1'
            PYTHONDONTWRITEBYTECODE = '1'
            MPLBACKEND              = 'Agg'
        }

        $script:environmentBefore = @{}
        foreach ($name in $script:pytestEnvironment.Keys) {
            $script:environmentBefore[$name] = [System.Environment]::GetEnvironmentVariable($name)
        }
    }

    It 'passes the pytest suite' {
        if (-not $script:hasUv) {
            # CI installs uv on purpose. Skipping there would turn a missing gate
            # into a green build with no tests behind it.
            if ($env:CI -eq 'true') {
                throw 'uv is not on PATH. CI installs it in the "Install uv (skills-ref reference validator)" step of ci.yml; skipping here would report a green build with no tests behind it.'
            }

            Set-ItResult -Skipped -Because 'uv is not installed, so the Python tests of travel-handbook cannot run'
            return
        }

        $previous = @{}
        foreach ($name in $script:pytestEnvironment.Keys) {
            $previous[$name] = [System.Environment]::GetEnvironmentVariable($name)
            [System.Environment]::SetEnvironmentVariable($name, $script:pytestEnvironment[$name])
        }

        Push-Location -LiteralPath $script:repoRoot
        try {
            $output = & $script:uvCommand @script:pytestArgument 2>&1 |
                ForEach-Object -Process { [string]$_ }
            $exitCode = $LASTEXITCODE
        }
        finally {
            Pop-Location
            foreach ($name in $script:pytestEnvironment.Keys) {
                # A null reaches SetEnvironmentVariable as an empty string and
                # leaves an empty variable behind; NullString removes it.
                $restore = if ($null -eq $previous[$name]) { [NullString]::Value } else { $previous[$name] }
                [System.Environment]::SetEnvironmentVariable($name, $restore)
            }
        }

        $exitCode | Should -Be 0 -Because ($output -join [System.Environment]::NewLine)
    }

    It 'leaves the environment as it found it' {
        # Later tests in the same run would otherwise inherit the pytest settings,
        # or an empty variable where none was set.
        foreach ($name in $script:pytestEnvironment.Keys) {
            [System.Environment]::GetEnvironmentVariable($name) |
                Should -Be $script:environmentBefore[$name] -Because "$name must be restored, or removed when it was not set"
        }
    }
}
