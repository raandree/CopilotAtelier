# Evaluated during discovery so -Skip: can see it; a BeforeAll runs too late.
# Never name this $isWindows: PowerShell variable names are case-insensitive, so
# it would collide with the read-only automatic $IsWindows and abort the file.
$script:onWindows = $IsWindows -or $PSVersionTable.PSEdition -eq 'Desktop'

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:verifierScript = Join-Path $script:repoRoot 'com.github.copilot/hooks/scripts/Test-RunContainment.ps1'
    $script:realConfig = Join-Path $script:repoRoot 'com.github.copilot/hooks/hooks.json'
    $script:realScript = Join-Path $script:repoRoot 'com.github.copilot/hooks/scripts/Block-RemoteMutation.ps1'
    . (Join-Path $script:repoRoot 'tests/Helpers/ScriptFunction.ps1')
    . (Get-ScriptFunctionDefinition -Path $script:verifierScript -Name @(
            'New-CheckResult'
            'Get-BytesDigest'
            'ConvertFrom-JsonByteArray'
            'Get-HookRootBinding'
            'Get-GateFailure'
            'Invoke-HookPayload'
            'Test-HookContract'
        ))

    function script:Get-FileDigest {
        param(
            [Parameter(Mandatory)]
            [string]$Path
        )

        (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
    }

    # A plugin tree with the layout the shipped hook command resolves its script from.
    function script:New-HookTree {
        param(
            [Parameter(Mandatory)]
            [string]$Root,

            [Parameter(Mandatory)]
            [string]$Body
        )

        $directory = Join-Path $Root 'com.github.copilot/hooks/scripts'
        $null = New-Item -Path $directory -ItemType Directory -Force
        $path = Join-Path $directory 'Block-RemoteMutation.ps1'
        [System.IO.File]::WriteAllText($path, $Body, [System.Text.UTF8Encoding]::new($false))

        return $path
    }

    function script:New-HookConfig {
        param(
            [Parameter(Mandatory)]
            [string]$Path,

            [Parameter(Mandatory)]
            [string]$Command
        )

        $configuration = @{
            hooks = @{
                PreToolUse = @(@{ type = 'command'; windows = $Command; command = $Command; timeout = 20 })
            }
        }

        [System.IO.File]::WriteAllText($Path, ($configuration | ConvertTo-Json -Depth 6), [System.Text.UTF8Encoding]::new($false))

        return $Path
    }

    # Runs a script block with one environment variable set, and restores it afterwards.
    function script:Invoke-WithEnvironment {
        param(
            [Parameter(Mandatory)]
            [string]$Name,

            [Parameter(Mandatory)]
            [AllowNull()]
            [string]$Value,

            [Parameter(Mandatory)]
            [scriptblock]$Action
        )

        $previous = [System.Environment]::GetEnvironmentVariable($Name)

        try {
            [System.Environment]::SetEnvironmentVariable($Name, $Value)
            & $Action
        } finally {
            [System.Environment]::SetEnvironmentVariable($Name, $previous)
        }
    }
}

Describe 'Hook root binding' -Tag 'Unit' {
    BeforeAll {
        $script:sep = [System.IO.Path]::DirectorySeparatorChar
        $script:base = if ($script:onWindows) { 'C:\containment\plugin' } else { '/containment/plugin' }
    }

    It 'derives the plugin root from a script laid out as the hook command expects' {
        $path = [System.IO.Path]::Combine($script:base, 'com.github.copilot', 'hooks', 'scripts', 'Block-RemoteMutation.ps1')

        $binding = Get-HookRootBinding -ScriptPath $path

        $binding.Problem | Should -BeNullOrEmpty
        $binding.Root | Should -Be $script:base
    }

    It 'derives the root when the path mixes separators' -Skip:(-not $script:onWindows) {
        $binding = Get-HookRootBinding -ScriptPath 'C:\containment\plugin/com.github.copilot/hooks\scripts/Block-RemoteMutation.ps1'

        $binding.Root | Should -Be 'C:\containment\plugin'
    }

    It 'matches the layout without regard to case on Windows' -Skip:(-not $script:onWindows) {
        $binding = Get-HookRootBinding -ScriptPath 'C:\containment\plugin\COM.GITHUB.COPILOT\Hooks\Scripts\block-remotemutation.ps1'

        $binding.Problem | Should -BeNullOrEmpty
        $binding.Root | Should -Be 'C:\containment\plugin'
    }

    It 'refuses a script that is not laid out under com.github.copilot/hooks/scripts' {
        $path = [System.IO.Path]::Combine($script:base, 'hooks', 'scripts', 'Block-RemoteMutation.ps1')

        $binding = Get-HookRootBinding -ScriptPath $path

        $binding.Root | Should -BeNullOrEmpty
        $binding.Problem | Should -Match 'com.github.copilot'
    }

    It 'refuses a script that has another name' {
        $path = [System.IO.Path]::Combine($script:base, 'com.github.copilot', 'hooks', 'scripts', 'Other.ps1')

        (Get-HookRootBinding -ScriptPath $path).Problem | Should -Match 'Block-RemoteMutation.ps1'
    }

    It 'refuses a relative path' {
        (Get-HookRootBinding -ScriptPath 'com.github.copilot/hooks/scripts/Block-RemoteMutation.ps1').Problem |
            Should -Match 'absolute'
    }
}

Describe 'Containment gate' -Tag 'Unit' {
    It 'names every required check that did not pass' {
        $check = @(
            (New-CheckResult -Name 'ControlDigest' -Status 'Pass' -Evidence 'x')
            (New-CheckResult -Name 'ControlImmutability' -Status 'Fail' -Evidence 'x')
            (New-CheckResult -Name 'VerifierBinding' -Status 'Unavailable' -Evidence 'x')
        )

        @(Get-GateFailure -Check $check -Require @('ControlDigest', 'ControlImmutability', 'VerifierBinding')) |
            Should -Be @('ControlImmutability', 'VerifierBinding')
    }

    It 'counts a required check that is absent as not passed' {
        $check = @((New-CheckResult -Name 'ControlDigest' -Status 'Pass' -Evidence 'x'))

        @(Get-GateFailure -Check $check -Require @('ControlDigest', 'ControlImmutability')) |
            Should -Be @('ControlImmutability')
    }

    It 'returns nothing when every required check passed' {
        $check = @(
            (New-CheckResult -Name 'ControlDigest' -Status 'Pass' -Evidence 'x')
            (New-CheckResult -Name 'ControlImmutability' -Status 'Pass' -Evidence 'x')
        )

        @(Get-GateFailure -Check $check -Require @('ControlDigest', 'ControlImmutability')) | Should -HaveCount 0
    }

    It 'matches a check name exactly, not by case' {
        $check = @((New-CheckResult -Name 'controldigest' -Status 'Pass' -Evidence 'x'))

        @(Get-GateFailure -Check $check -Require @('ControlDigest')) | Should -Be @('ControlDigest')
    }
}

Describe 'Hook command runner' -Tag 'Unit' -Skip:(-not $script:onWindows) {
    It 'returns the exit code of the command' {
        Invoke-HookPayload -CommandLine 'exit 3' -Payload '{}' -EnvironmentVariable @{} | Should -Be 3
    }

    It 'passes the payload on standard input' {
        Invoke-HookPayload -CommandLine 'findstr "needle" >nul' -Payload 'a needle in it' -EnvironmentVariable @{} | Should -Be 0
        Invoke-HookPayload -CommandLine 'findstr "needle" >nul' -Payload 'nothing here' -EnvironmentVariable @{} | Should -Be 1
    }

    It 'gives the command the environment it is told to and no other value for that name' {
        $command = 'if "%CONTAINMENT_PROBE%"=="yes" (exit 5) else (exit 6)'

        Invoke-WithEnvironment -Name 'CONTAINMENT_PROBE' -Value 'ambient' -Action {
            Invoke-HookPayload -CommandLine $command -Payload '{}' -EnvironmentVariable @{ CONTAINMENT_PROBE = 'yes' } | Should -Be 5
        }
    }

    It 'removes a variable whose value is null' {
        $command = 'if defined CONTAINMENT_PROBE (exit 5) else (exit 6)'

        Invoke-WithEnvironment -Name 'CONTAINMENT_PROBE' -Value 'ambient' -Action {
            Invoke-HookPayload -CommandLine $command -Payload '{}' -EnvironmentVariable @{ CONTAINMENT_PROBE = $null } | Should -Be 6
        }
    }

    It 'does not take the shell from the ComSpec variable' {
        Invoke-WithEnvironment -Name 'ComSpec' -Value (Join-Path $TestDrive 'absent\cmd.exe') -Action {
            Invoke-HookPayload -CommandLine 'exit 4' -Payload '{}' -EnvironmentVariable @{} | Should -Be 4
        }
    }

    It 'stops a command that does not finish in time' {
        $clock = [System.Diagnostics.Stopwatch]::StartNew()

        { Invoke-HookPayload -CommandLine 'ping -n 40 127.0.0.1 >nul' -Payload '{}' -EnvironmentVariable @{} -TimeoutSecond 2 } |
            Should -Throw -ExpectedMessage '*did not finish*'

        $clock.Elapsed.TotalSeconds | Should -BeLessThan 20
    }
}

Describe 'Hook contract' -Tag 'Unit' -Skip:(-not $script:onWindows) {
    BeforeAll {
        $script:realConfigDigest = Get-FileDigest -Path $script:realConfig
        $script:realScriptDigest = Get-FileDigest -Path $script:realScript
    }

    Context 'on the shipped hook' {
        BeforeAll {
            $script:shippedRun = Test-HookContract -HookConfigPath $script:realConfig -HookConfigSha256 $script:realConfigDigest `
                -HookScriptPath $script:realScript -HookScriptSha256 $script:realScriptDigest
        }

        It 'passes with the exit codes 0, 2 and 2' {
            $script:shippedRun.status | Should -Be 'Pass' -Because $script:shippedRun.evidence
            $script:shippedRun.evidence | Should -Match 'safe=0 push=2 issue=2'
        }

        It 'names the pinned script that it ran' {
            $script:shippedRun.evidence | Should -Match ([regex]::Escape([System.IO.Path]::GetFullPath($script:realScript)))
        }
    }

    Context 'when the caller has a PLUGIN_ROOT or ComSpec of its own' {
        It 'measures the pinned script and not a decoy that PLUGIN_ROOT names' {
            $decoyRoot = Join-Path $TestDrive 'decoy-good'
            $null = New-HookTree -Root $decoyRoot -Body 'exit 0'

            $result = Invoke-WithEnvironment -Name 'PLUGIN_ROOT' -Value $decoyRoot -Action {
                Test-HookContract -HookConfigPath $script:realConfig -HookConfigSha256 $script:realConfigDigest `
                    -HookScriptPath $script:realScript -HookScriptSha256 $script:realScriptDigest
            }

            $result.status | Should -Be 'Pass' -Because $result.evidence
        }

        It 'fails a pinned script that does not block, even when PLUGIN_ROOT names one that does' {
            $brokenRoot = Join-Path $TestDrive 'pinned-broken'
            $broken = New-HookTree -Root $brokenRoot -Body 'exit 0'

            $result = Invoke-WithEnvironment -Name 'PLUGIN_ROOT' -Value $script:repoRoot -Action {
                Test-HookContract -HookConfigPath $script:realConfig -HookConfigSha256 $script:realConfigDigest `
                    -HookScriptPath $broken -HookScriptSha256 (Get-FileDigest -Path $broken)
            }

            $result.status | Should -Be 'Fail'
            $result.evidence | Should -Match 'safe=0 push=0 issue=0'
        }

        It 'does not take the shell from the ComSpec variable' {
            $result = Invoke-WithEnvironment -Name 'ComSpec' -Value (Join-Path $TestDrive 'absent\cmd.exe') -Action {
                Test-HookContract -HookConfigPath $script:realConfig -HookConfigSha256 $script:realConfigDigest `
                    -HookScriptPath $script:realScript -HookScriptSha256 $script:realScriptDigest
            }

            $result.status | Should -Be 'Pass' -Because $result.evidence
        }
    }

    Context 'when the command does not resolve its script from PLUGIN_ROOT' {
        It 'fails, because the pinned script cannot be shown to be the one that runs' {
            $command = 'powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $script:realScript + '"'
            $config = New-HookConfig -Path (Join-Path $TestDrive 'fixed-path-hooks.json') -Command $command

            $result = Test-HookContract -HookConfigPath $config -HookConfigSha256 (Get-FileDigest -Path $config) `
                -HookScriptPath $script:realScript -HookScriptSha256 $script:realScriptDigest

            $result.status | Should -Be 'Fail'
            $result.evidence | Should -Match 'PLUGIN_ROOT'
        }
    }

    Context 'when the bytes are not the pinned bytes' {
        It 'runs nothing from a hooks.json that does not match its digest' {
            $marker = Join-Path $TestDrive 'must-not-exist.txt'
            $config = New-HookConfig -Path (Join-Path $TestDrive 'wrong-digest-hooks.json') -Command "echo ran> `"$marker`""

            $result = Test-HookContract -HookConfigPath $config -HookConfigSha256 ('b' * 64) `
                -HookScriptPath $script:realScript -HookScriptSha256 $script:realScriptDigest

            $result.status | Should -Not -Be 'Pass'
            $result.evidence | Should -Match 'hooks.json'
            Test-Path -LiteralPath $marker | Should -BeFalse
        }

        It 'runs nothing when the hook script does not match its digest' {
            $marker = Join-Path $TestDrive 'script-marker.txt'
            $root = Join-Path $TestDrive 'wrong-script-digest'
            $script = New-HookTree -Root $root -Body "Set-Content -LiteralPath '$marker' -Value ran`nexit 0"

            $result = Test-HookContract -HookConfigPath $script:realConfig -HookConfigSha256 $script:realConfigDigest `
                -HookScriptPath $script -HookScriptSha256 ('c' * 64)

            $result.status | Should -Not -Be 'Pass'
            Test-Path -LiteralPath $marker | Should -BeFalse
        }

        It 'is not run for a pinned script outside the layout the command resolves' {
            $path = Join-Path $TestDrive 'elsewhere/Block-RemoteMutation.ps1'
            $null = New-Item -Path (Split-Path -Parent $path) -ItemType Directory -Force
            Copy-Item -LiteralPath $script:realScript -Destination $path

            $result = Test-HookContract -HookConfigPath $script:realConfig -HookConfigSha256 $script:realConfigDigest `
                -HookScriptPath $path -HookScriptSha256 (Get-FileDigest -Path $path)

            $result.status | Should -Be 'Unavailable'
            $result.evidence | Should -Match 'com.github.copilot'
        }
    }

    Context 'when hooks.json does not declare exactly one PreToolUse hook' {
        It 'fails when there is none, and does not throw on the missing property' {
            $config = Join-Path $TestDrive 'no-pretooluse.json'
            [System.IO.File]::WriteAllText($config, '{"hooks":{}}', [System.Text.UTF8Encoding]::new($false))

            $result = Test-HookContract -HookConfigPath $config -HookConfigSha256 (Get-FileDigest -Path $config) `
                -HookScriptPath $script:realScript -HookScriptSha256 $script:realScriptDigest

            $result.status | Should -Be 'Fail'
            $result.evidence | Should -Match 'exactly one PreToolUse'
        }
    }
}
