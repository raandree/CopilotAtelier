# Evaluated during discovery so -Skip: can see it; a BeforeAll runs too late.
# Never name this $isWindows: PowerShell variable names are case-insensitive, so
# it would collide with the read-only automatic $IsWindows and abort the file.
$script:onWindows = $IsWindows -or $PSVersionTable.PSEdition -eq 'Desktop'

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:verifierScript = Join-Path $script:repoRoot 'com.github.copilot/hooks/scripts/Test-RunContainment.ps1'
    . (Join-Path $script:repoRoot 'tests/Helpers/ScriptFunction.ps1')
    . (Get-ScriptFunctionDefinition -Path $script:verifierScript -Name @(
            'Get-FreshProcessProblem'
        ))

    $script:entryScript = if ($script:onWindows) { 'C:\containment\Test-RunContainment.ps1' } else { '/containment/Test-RunContainment.ps1' }
    $script:otherScript = if ($script:onWindows) { 'C:\elsewhere\wrapper.ps1' } else { '/elsewhere/wrapper.ps1' }
    $script:hostModule = if ($script:onWindows) { 'C:\Program Files\PowerShell\7\pwsh.dll' } else { '/usr/share/powershell/pwsh.dll' }

    # The first element of a process command line is the host itself; the rest is what it was given.
    function script:Get-Problem {
        param(
            [Parameter(Mandatory)]
            [AllowEmptyCollection()]
            [string[]]$Argument
        )

        return (Get-FreshProcessProblem -CommandLineArgument (@($script:hostModule) + $Argument) -ScriptPath $script:entryScript)
    }
}

Describe 'Containment fresh process' -Tag 'Unit' {
    Context 'a process that was started to run this script' {
        It 'accepts -NoProfile, -NonInteractive and -File with the script' {
            Get-Problem -Argument @('-NoProfile', '-NonInteractive', '-File', $script:entryScript, '-Verify') | Should -BeNullOrEmpty
        }

        It 'accepts options that take a value before -File' {
            Get-Problem -Argument @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-NonInteractive', '-File', $script:entryScript) | Should -BeNullOrEmpty
        }

        It 'accepts the abbreviations PowerShell accepts' {
            Get-Problem -Argument @('-nop', '-f', $script:entryScript) | Should -BeNullOrEmpty
            Get-Problem -Argument @('-NoPro', '-Fi', $script:entryScript) | Should -BeNullOrEmpty
        }

        It 'accepts the spelling of the script in another case on Windows' -Skip:(-not $script:onWindows) {
            Get-Problem -Argument @('-NoProfile', '-File', $script:entryScript.ToUpperInvariant()) | Should -BeNullOrEmpty
        }
    }

    Context 'a session that has run other code before this script' {
        It 'refuses a call from inside another command, because a function or type defined there outranks the ones this script uses' {
            $problem = Get-Problem -Argument @('-NoProfile', '-Command', "& '$($script:entryScript)' -Verify")

            $problem | Should -Match 'fresh process'
            $problem | Should -Match '-File'
        }

        It 'refuses an encoded command' {
            Get-Problem -Argument @('-NoProfile', '-EncodedCommand', 'JgBlAGMAaABvAA==') | Should -Match 'fresh process'
        }

        It 'refuses an interactive host that was not given the script at all' {
            Get-Problem -Argument @('-NoLogo') | Should -Match 'fresh process'
            Get-Problem -Argument @() | Should -Match 'fresh process'
        }

        It 'refuses a script that another script was started with and merely mentions this one' {
            Get-Problem -Argument @('-NoProfile', '-File', $script:otherScript, $script:entryScript) | Should -Match 'fresh process'
        }

        It 'refuses the script given without -File, because the position of the name is not a promise' {
            Get-Problem -Argument @('-NoProfile', '-ExecutionPolicy', $script:entryScript) | Should -Match 'fresh process'
            Get-Problem -Argument @('-NoProfile', $script:entryScript) | Should -Match 'fresh process'
        }

        It 'refuses -File with nothing after it' {
            Get-Problem -Argument @('-NoProfile', '-File') | Should -Match 'fresh process'
        }
    }

    Context 'the profile of the user' {
        It 'refuses a process that loaded it' {
            Get-Problem -Argument @('-NonInteractive', '-File', $script:entryScript) | Should -Match 'NoProfile'
        }

        It 'does not count a -NoProfile that is an argument of the script' {
            Get-Problem -Argument @('-File', $script:entryScript, '-NoProfile') | Should -Match 'NoProfile'
        }
    }
}
