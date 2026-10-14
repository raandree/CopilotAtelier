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
            'Get-PowerShellLaunchOption'
        ))

    $script:entryScript = if ($script:onWindows) { 'C:\containment\Test-RunContainment.ps1' } else { '/containment/Test-RunContainment.ps1' }
    $script:otherScript = if ($script:onWindows) { 'C:\elsewhere\wrapper.ps1' } else { '/elsewhere/wrapper.ps1' }
    $script:hostModule = if ($script:onWindows) { 'C:\Program Files\PowerShell\7\pwsh.dll' } else { '/usr/share/powershell/pwsh.dll' }

    # The first element of a process command line is the host itself; the rest is what it was given.
    # The depth is the number of frames of the call stack where the script starts: one under -File.
    function script:Get-Problem {
        param(
            [Parameter(Mandatory)]
            [AllowEmptyCollection()]
            [string[]]$Argument,

            [Parameter()]
            [int]$Depth = 1
        )

        return (Get-FreshProcessProblem -CommandLineArgument (@($script:hostModule) + $Argument) -ScriptPath $script:entryScript -CallStackDepth $Depth)
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

    Context 'a command line that names this script but runs other code around it' {
        # Review pass 2, S-01: -Command takes every later argument as command text, yet the host still lists
        # them, so "-Command <code> -File <script>" read exactly like "-File <script>" and the code ran first.
        It 'refuses a call stack deeper than the one frame the script has under -File' {
            $problem = Get-Problem -Argument @('-NoProfile', '-File', $script:entryScript) -Depth 2

            $problem | Should -Match 'fresh process'
            $problem | Should -Match '2 frames'
        }

        # Since the options before -File are read in order, -Command ends the scan, so this shape is refused by
        # the command line itself, at either depth; the stack is what catches a launch whose line is clean.
        It 'refuses -Command text that carries -File and the script after it, at a stack of <_>' -ForEach @(1, 2) {
            $problem = Get-Problem -Argument @('-NoProfile', '-Command', "function Get-Date { 'x' }; & '$($script:entryScript)' #", '-File', $script:entryScript) -Depth $_

            $problem | Should -Match 'fresh process'
        }

        It 'refuses a call stack of no frame, which is not the shape of a script that was started by -File' {
            Get-Problem -Argument @('-NoProfile', '-File', $script:entryScript) -Depth 0 | Should -Match 'fresh process'
        }

        It 'accepts the one frame that -File gives' {
            Get-Problem -Argument @('-NoProfile', '-File', $script:entryScript) -Depth 1 | Should -BeNullOrEmpty
        }
    }

    Context 'options before -File that decide what runs first, or that swallow what looks like an option' {
        # Review pass 3, S-13: the options before -File were scanned for -NoProfile, not allow-listed.
        # -ConfigurationFile runs a session configuration, which can define functions, before the
        # script, and -WorkingDirectory takes the next argument as its value, so "-WorkingDirectory
        # -nop" is a directory named -nop and no -NoProfile at all.
        It 'refuses <Option>, which the verifier does not allow before -File' -ForEach @(
            @{ Option = @('-ConfigurationFile', 'shadow.pssc') }
            @{ Option = @('-SettingsFile', 'settings.json') }
            @{ Option = @('-ConfigurationName', 'endpoint') }
            @{ Option = @('-CustomPipeName', 'pipe') }
            @{ Option = @('-InputFormat', 'Text') }
            @{ Option = @('-Interactive') }
            @{ Option = @('-NoExit') }
            @{ Option = @('stray') }
        ) {
            $problem = Get-Problem -Argument (@('-NoProfile') + $Option + @('-File', $script:entryScript))

            $problem | Should -Match 'fresh process'
            $problem | Should -Match ([regex]::Escape($Option[0]))
        }

        It 'does not take a value for the option that follows it, and so does not count it' {
            $problem = Get-Problem -Argument @('-WorkingDirectory', '-nop', '-File', $script:entryScript)

            $problem | Should -Match 'NoProfile'
        }

        It 'refuses an option that takes a value and is given none' {
            Get-Problem -Argument @('-NoProfile', '-ExecutionPolicy') | Should -Match 'fresh process'
        }

        It 'accepts <Spelling>' -ForEach @(
            @{ Spelling = 'the options a launcher uses'; Option = @('-NoProfile', '-NonInteractive', '-NoLogo', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-MTA') }
            @{ Spelling = 'their short forms'; Option = @('-nop', '-noni', '-nol', '-ep', 'Bypass', '-w', 'Hidden', '-sta') }
            @{ Spelling = 'a working directory'; Option = @('-WorkingDirectory', 'C:\work', '-NoProfile') }
            @{ Spelling = 'a working directory in its short form'; Option = @('-wd', 'C:\work', '-nop') }
        ) {
            Get-Problem -Argument ($Option + @('-File', $script:entryScript, '-Verify')) | Should -BeNullOrEmpty
        }
    }

    Context 'what the launch check itself calls' {
        # Review pass 3, S-12: command lookup tries an alias before a function, so any command the check
        # resolves by name can be put out of the way by a session that ran before it. The check and the
        # option reader therefore use operators and .NET members only, and the main flow reaches the check
        # through the function table, which an alias cannot shadow.
        BeforeAll {
            $script:tree = [System.Management.Automation.Language.Parser]::ParseFile($script:verifierScript, [ref]$null, [ref]$null)

            function script:Get-FunctionCommand {
                param(
                    [Parameter(Mandatory)]
                    [string]$Name
                )

                $function = $script:tree.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) |
                    Where-Object -FilterScript { $_.Name -ceq $Name } |
                    Select-Object -First 1

                return @($function.Body.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true))
            }
        }

        It 'reads the options without invoking any command' {
            @(Get-FunctionCommand -Name 'Get-PowerShellLaunchOption') | Should -HaveCount 0
        }

        It 'invokes only the option reader, through the function table, and nothing else' {
            $command = @(Get-FunctionCommand -Name 'Get-FreshProcessProblem')

            $command | Should -HaveCount 1
            $command[0].CommandElements[0] | Should -BeOfType ([System.Management.Automation.Language.VariableExpressionAst])
            $command[0].CommandElements[0].VariablePath.UserPath | Should -BeExactly 'function:Get-PowerShellLaunchOption'
        }

        It 'is reached from the main flow through the function table, and never by name' {
            $byName = @($script:tree.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] -and $node.GetCommandName() -ceq 'Get-FreshProcessProblem' }, $true))
            $viaTable = @($script:tree.FindAll({
                        param($node)
                        $node -is [System.Management.Automation.Language.CommandAst] -and
                        $node.CommandElements[0] -is [System.Management.Automation.Language.VariableExpressionAst] -and
                        $node.CommandElements[0].VariablePath.UserPath -ceq 'function:Get-FreshProcessProblem'
                    }, $true))

            $byName | Should -HaveCount 0
            $viaTable | Should -HaveCount 1
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
