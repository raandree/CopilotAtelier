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
            'Get-HookInterpreter'
            'Get-PowerShellLaunchOption'
            'Format-RelayedText'
            'Get-GateFailure'
            'Test-PathProtection'
            'Invoke-HookPayload'
            'Get-HookWrapper'
            'Get-HookWrapperProblem'
            'Measure-HookWrapper'
            'Test-HookContract'
        ))

    # The interpreter a contained deployment names by absolute path in place of the bare name the shipped file uses.
    $script:systemPowerShell = [System.IO.Path]::Combine([System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::System), 'WindowsPowerShell', 'v1.0', 'powershell.exe')

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

    # The shipped PreToolUse command with its interpreter named by absolute path, as a contained deployment must pin it.
    # The path of Windows PowerShell in the system folder holds no space, so it is not quoted: a quoted program path
    # does not run under a PowerShell host, and the check measures that.
    function script:New-ContainedConfig {
        param(
            [Parameter(Mandatory)]
            [string]$Path
        )

        $shipped = [System.IO.File]::ReadAllText($script:realConfig) | ConvertFrom-Json
        $command = [string]@($shipped.hooks.PreToolUse)[0].windows

        if (-not $command.StartsWith('powershell ')) {
            throw 'the shipped Windows command no longer starts with the bare name powershell'
        }

        return New-HookConfig -Path $Path -Command ($script:systemPowerShell + $command.Substring('powershell'.Length))
    }

    # A plugin tree as a deployment lays it out: a copy of the guard under scripts, and beside it the
    # hooks.json the host loads from that root. Both are digested the way a profile pins them.
    function script:New-PluginTree {
        param(
            [Parameter(Mandatory)]
            [string]$Name,

            [Parameter()]
            [string]$Command,

            [Parameter()]
            [string]$Body
        )

        $root = Join-Path $TestDrive "plugin-$Name"
        $text = if ($PSBoundParameters.ContainsKey('Body')) { $Body } else { [System.IO.File]::ReadAllText($script:realScript) }
        $scriptPath = New-HookTree -Root $root -Body $text
        $configPath = Join-Path $root 'com.github.copilot/hooks/hooks.json'

        if ($PSBoundParameters.ContainsKey('Command')) {
            $null = New-HookConfig -Path $configPath -Command $Command
        } else {
            $null = New-ContainedConfig -Path $configPath
        }

        return [pscustomobject]@{
            Root = $root
            Script = $scriptPath
            ScriptDigest = (Get-FileDigest -Path $scriptPath)
            Config = $configPath
            ConfigDigest = (Get-FileDigest -Path $configPath)
        }
    }

    # Writes a hooks.json into a plugin tree and returns the digest of what it wrote.
    function script:Set-PluginConfig {
        param(
            [Parameter(Mandatory)]
            $Tree,

            [Parameter(Mandatory)]
            [string]$Json
        )

        [System.IO.File]::WriteAllText($Tree.Config, $Json, [System.Text.UTF8Encoding]::new($false))

        return (Get-FileDigest -Path $Tree.Config)
    }

    # Runs a script block with both the PowerShell location and the process working directory set, then restores them.
    function script:Invoke-InDirectory {
        param(
            [Parameter(Mandatory)]
            [string]$Path,

            [Parameter(Mandatory)]
            [scriptblock]$Action
        )

        $previous = [System.IO.Directory]::GetCurrentDirectory()

        try {
            Push-Location -LiteralPath $Path
            [System.IO.Directory]::SetCurrentDirectory($Path)
            & $Action
        } finally {
            [System.IO.Directory]::SetCurrentDirectory($previous)
            Pop-Location
        }
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

    # The seed of the property test of the hook-line shape. A seed that is asked for in Requested wins, on CI and off it, and a
    # request that is not a whole number from 0 to 2147483647 is an error, so a mistyped replay never runs another seed in
    # silence. Without a request, CI (the variable CI is true, as on GitHub Actions) draws a seed. Otherwise nothing asks for
    # one and the result is $null, which is not the seed 0.
    function script:Resolve-PropertySeed {
        [CmdletBinding()]
        [OutputType([int])]
        param(
            [Parameter()]
            [AllowNull()]
            [AllowEmptyString()]
            [string]$Ci,

            [Parameter()]
            [AllowNull()]
            [AllowEmptyString()]
            [string]$Requested
        )

        if (-not [string]::IsNullOrWhiteSpace($Requested)) {
            $seed = 0

            if (-not [int]::TryParse($Requested.Trim(), [System.Globalization.NumberStyles]::None, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$seed)) {
                throw "CONTAINMENT_PROPERTY_SEED has to be a whole number from 0 to 2147483647, and it is '$Requested'."
            }

            return $seed
        }

        if ($Ci -eq 'true') {
            return Get-Random -Minimum 0 -Maximum ([int]::MaxValue)
        }

        return $null
    }

    # True when the parser of this host reads Text as one command whose elements are exactly the words in Expected, with no parse
    # error and no redirection, and, when Closed, as that command followed by the closing statement that the shipped hook command
    # ends with. Anything else is a deviation: PowerShell reads the line as other words than the shape saw.
    function script:Test-ShapeReading {
        [CmdletBinding()]
        [OutputType([bool])]
        param(
            [Parameter(Mandatory)]
            [string]$Text,

            [Parameter(Mandatory)]
            [string[]]$Expected,

            [Parameter()]
            [switch]$Closed
        )

        $errors = $null
        $tokens = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$tokens, [ref]$errors)
        $statement = @($ast.EndBlock.Statements)
        $command = $null

        if ($statement.Count -eq $(if ($Closed) { 2 } else { 1 }) -and $statement[0] -is [System.Management.Automation.Language.PipelineAst] -and $statement[0].PipelineElements.Count -eq 1) {
            $command = $statement[0].PipelineElements[0]
        }

        $same = $errors.Count -eq 0 -and $command -is [System.Management.Automation.Language.CommandAst] -and
            $command.Redirections.Count -eq 0 -and $command.CommandElements.Count -eq $Expected.Count

        for ($element = 0; $same -and $element -lt $Expected.Count; $element++) {
            $same = [string]::Equals($command.CommandElements[$element].Extent.Text, $Expected[$element], [System.StringComparison]::Ordinal)
        }

        if ($same -and $Closed) {
            $same = [string]::Equals($statement[1].Extent.Text, $script:HookExitTail, [System.StringComparison]::Ordinal)
        }

        return $same
    }

    # Generates hook command lines, keeps those that the interpreter accepts, and checks with Test-ShapeReading that the parser of
    # this host reads each of them as one command whose words are the words that were generated. The same seed gives the same
    # lines. The result lists the accepted lines too, so that a test can see what the property reached. The interpreter is a
    # parameter so that a test can give it one that accepts everything and see that a deviation is reported.
    function script:Invoke-ShapeProperty {
        [CmdletBinding()]
        [OutputType([pscustomobject])]
        param(
            [Parameter(Mandatory)]
            [int]$Seed,

            [Parameter()]
            [ValidateRange(1, 1000000)]
            [int]$LineCount = 4000,

            [Parameter()]
            [scriptblock]$Interpreter = { param($CommandLine) Get-HookInterpreter -CommandLine $CommandLine }
        )

        $random = [System.Random]::new($Seed)
        $program = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
        $bareAlphabet = [char[]]'abcdefXYZ019_.:\/-'
        $quotedAlphabet = [char[]](' #&''()*+,-./0123456789:;<=>?@ABCXYZ[]\^_{|}~abcxyz' + "`t")
        $pick = {
            param([char[]]$Alphabet, [int]$Length)

            $builder = [System.Text.StringBuilder]::new()
            for ($index = 0; $index -lt $Length; $index++) {
                $null = $builder.Append($Alphabet[$random.Next(0, $Alphabet.Length)])
            }

            $builder.ToString()
        }
        $accepted = 0
        $acceptedLine = [System.Collections.Generic.List[string]]::new()
        $deviation = [System.Collections.Generic.List[string]]::new()

        for ($line = 0; $line -lt $LineCount; $line++) {
            $word = [System.Collections.Generic.List[string]]::new()

            for ($count = $random.Next(1, 6); $count -gt 0; $count--) {
                if ($random.Next(0, 10) -lt 6) {
                    $text = & $pick $bareAlphabet $random.Next(1, 8)
                    if ($random.Next(0, 3) -eq 0) { $text = '-' + $text }
                    if ($random.Next(0, 3) -eq 0) { $text += ':.'[$random.Next(0, 2)] }
                    $word.Add($text)
                } else {
                    $word.Add('"' + (& $pick $quotedAlphabet $random.Next(0, 10)) + '"')
                }
            }

            $expected = @($program, '-NoProfile', @('-Command', '-File')[$random.Next(0, 2)]) + $word
            $text = $expected -join @(' ', "`t", '  ')[$random.Next(0, 3)]
            $closed = $random.Next(0, 4) -eq 0

            if ($closed) {
                $text += '; ' + $script:HookExitTail
            }

            if ($null -ne (& $Interpreter $text).Problem) {
                continue
            }

            $accepted++
            $acceptedLine.Add($text)

            if (-not (Test-ShapeReading -Text $text -Expected $expected -Closed:$closed)) {
                $deviation.Add($text)
            }
        }

        return [pscustomobject]@{
            Seed = $Seed
            LineCount = $LineCount
            Accepted = $accepted
            AcceptedLine = @($acceptedLine)
            Deviation = @($deviation)
        }
    }

    # Runs the property on the seed that Resolve-PropertySeed gives and returns the result, which names that seed, or returns
    # $null when nothing asks for a seed. OnSeed is called with the seed before anything runs, so a run that crashes still
    # names the seed it was on.
    function script:Invoke-PropertyOnAskedSeed {
        [CmdletBinding()]
        [OutputType([pscustomobject])]
        param(
            [Parameter()]
            [AllowNull()]
            [AllowEmptyString()]
            [string]$Ci,

            [Parameter()]
            [AllowNull()]
            [AllowEmptyString()]
            [string]$Requested,

            [Parameter()]
            [ValidateRange(1, 1000000)]
            [int]$LineCount = 4000,

            [Parameter()]
            [scriptblock]$OnSeed = {},

            [Parameter()]
            [scriptblock]$Interpreter
        )

        $seed = Resolve-PropertySeed -Ci $Ci -Requested $Requested

        if ($null -eq $seed) {
            return $null
        }

        & $OnSeed $seed

        $run = @{ Seed = $seed; LineCount = $LineCount }

        if ($PSBoundParameters.ContainsKey('Interpreter')) {
            $run.Interpreter = $Interpreter
        }

        return Invoke-ShapeProperty @run
    }

    # The line that names the seed a run is on, the PowerShell version and how to run the seed again. The version is part of it
    # because whether PowerShell reads a line as other words depends on its parser.
    function script:Format-PropertySeedLine {
        [CmdletBinding()]
        [OutputType([string])]
        param(
            [Parameter(Mandatory)]
            [int]$Seed,

            [Parameter()]
            [ValidateNotNullOrEmpty()]
            [string]$Version = $PSVersionTable.PSVersion.ToString()
        )

        return 'Property test of the hook-line shape: seed {0}, PowerShell {1}. Replay it with CONTAINMENT_PROPERTY_SEED={0}.' -f $Seed, $Version
    }

    # Runs the property on the seed that the environment asks for: CONTAINMENT_PROPERTY_SEED to run one again, or CI to draw one.
    # The line that names the seed goes to the information stream before the run. Returns the result, or $null when nothing asks.
    function script:Invoke-PropertyFromEnvironment {
        [CmdletBinding()]
        [OutputType([pscustomobject])]
        param(
            [Parameter()]
            [ValidateRange(1, 1000000)]
            [int]$LineCount = 4000
        )

        $announce = { param($Seed) Write-Information -MessageData (Format-PropertySeedLine -Seed $Seed) -InformationAction Continue }

        return Invoke-PropertyOnAskedSeed -Ci $env:CI -Requested $env:CONTAINMENT_PROPERTY_SEED -LineCount $LineCount -OnSeed $announce
    }

    # Sets an environment variable of this process, or removes it when the value is null or empty. A null that is passed on to a
    # .NET method arrives as an empty string, which leaves the variable set to nothing; only a NullString removes it.
    function script:Set-ProcessEnvironmentVariable {
        param(
            [Parameter(Mandatory)]
            [string]$Name,

            [Parameter()]
            [AllowNull()]
            [AllowEmptyString()]
            [string]$Value
        )

        [System.Environment]::SetEnvironmentVariable($Name, $(if ([string]::IsNullOrEmpty($Value)) { [NullString]::Value } else { $Value }))
    }

    # Runs Invoke-PropertyFromEnvironment over 40 lines with CI and CONTAINMENT_PROPERTY_SEED set to these values, and puts both
    # variables back as they were. A null or empty value removes the variable for the time of the call. It tells what the call
    # returned from what it wrote to the information stream.
    function script:Invoke-PropertyWithEnvironment {
        [CmdletBinding()]
        param(
            [Parameter()]
            [AllowNull()]
            [AllowEmptyString()]
            [string]$Ci,

            [Parameter()]
            [AllowNull()]
            [AllowEmptyString()]
            [string]$Seed
        )

        $previousCi = [System.Environment]::GetEnvironmentVariable('CI')
        $previousSeed = [System.Environment]::GetEnvironmentVariable('CONTAINMENT_PROPERTY_SEED')

        try {
            Set-ProcessEnvironmentVariable -Name 'CI' -Value $Ci
            Set-ProcessEnvironmentVariable -Name 'CONTAINMENT_PROPERTY_SEED' -Value $Seed
            $output = @(Invoke-PropertyFromEnvironment -LineCount 40 6>&1)
        } finally {
            Set-ProcessEnvironmentVariable -Name 'CI' -Value $previousCi
            Set-ProcessEnvironmentVariable -Name 'CONTAINMENT_PROPERTY_SEED' -Value $previousSeed
        }

        return [pscustomobject]@{
            Result = @($output | Where-Object -FilterScript { $_ -isnot [System.Management.Automation.InformationRecord] })[0]
            Printed = @($output | Where-Object -FilterScript { $_ -is [System.Management.Automation.InformationRecord] })
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

Describe 'Hook interpreter' -Tag 'Unit' -Skip:(-not $script:onWindows) {
    It 'reads an unquoted absolute path' {
        $result = Get-HookInterpreter -CommandLine 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -Command exit'

        $result.Problem | Should -BeNullOrEmpty
        $result.Path | Should -Be 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
    }

    It 'reads a quoted absolute path that holds spaces' {
        $result = Get-HookInterpreter -CommandLine '"C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile -File x.ps1'

        $result.Problem | Should -BeNullOrEmpty
        $result.Path | Should -Be 'C:\Program Files\PowerShell\7\pwsh.exe'
    }

    It 'normalizes forward slashes and leading whitespace' {
        $result = Get-HookInterpreter -CommandLine '   C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -NoProfile -Command exit'

        $result.Path | Should -Be 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
    }

    It 'refuses <Why>' -ForEach @(
        @{ Why = 'a bare name'; Line = 'powershell -NoProfile -Command exit'; Match = 'bare name' }
        @{ Why = 'a bare name with an extension'; Line = 'pwsh.exe -NoProfile'; Match = 'bare name' }
        @{ Why = 'a quoted bare name'; Line = '"powershell" -NoProfile'; Match = 'bare name' }
        @{ Why = 'a relative path'; Line = '.\powershell.exe -NoProfile'; Match = 'relative' }
        @{ Why = 'a relative path in a folder'; Line = 'tools\run.exe -x'; Match = 'relative' }
        @{ Why = 'a path relative to a drive'; Line = 'C:run.exe -x'; Match = 'relative' }
        @{ Why = 'a path rooted on the current drive'; Line = '\Windows\System32\cmd.exe /c exit'; Match = 'relative' }
        @{ Why = 'an environment variable'; Line = '%SystemRoot%\System32\cmd.exe /c exit'; Match = 'expands' }
        @{ Why = 'a caret escape'; Line = 'C:\Windows\Sys^tem32\cmd.exe /c exit'; Match = 'expands' }
        @{ Why = 'a network path'; Line = '\\server\share\run.exe -x'; Match = 'network or device' }
        @{ Why = 'a device path'; Line = '\\?\C:\Windows\System32\cmd.exe /c exit'; Match = 'network or device' }
        @{ Why = 'a quote that is never closed'; Line = '"C:\Windows\System32\cmd.exe /c exit'; Match = 'never closed' }
        @{ Why = 'a blank line'; Line = '   '; Match = 'no program' }
        @{ Why = 'a command separator right after the program'; Line = '"C:\Windows\System32\cmd.exe"&calc.exe'; Match = 'unquoted' }
        @{ Why = 'a command separator between words'; Line = 'C:\Windows\System32\cmd.exe /c exit & calc.exe'; Match = 'unquoted' }
        @{ Why = 'a command separator inside an unquoted program word'; Line = 'C:\Windows\System32\cmd.exe&calc.exe /c exit'; Match = 'unquoted' }
        @{ Why = 'a pipe'; Line = 'C:\Windows\System32\cmd.exe /c dir | more'; Match = 'unquoted' }
        @{ Why = 'an output redirection'; Line = 'C:\Windows\System32\cmd.exe /c dir > out.txt'; Match = 'unquoted' }
        @{ Why = 'an input redirection'; Line = 'C:\Windows\System32\cmd.exe /c more < in.txt'; Match = 'unquoted' }
        @{ Why = 'a caret outside quotes'; Line = 'C:\Windows\System32\cmd.exe /c ec^ho x'; Match = 'unquoted' }
        @{ Why = 'a line break'; Line = "C:\Windows\System32\cmd.exe /c exit`r`ncalc.exe"; Match = 'line' }
        @{ Why = 'PowerShell started without -NoProfile'; Line = '"C:\Program Files\PowerShell\7\pwsh.exe" -File x.ps1'; Match = 'NoProfile' }
        @{ Why = 'Windows PowerShell started without -NoProfile'; Line = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NonInteractive -Command exit'; Match = 'NoProfile' }
        @{ Why = 'a -NoProfile that only belongs to the script'; Line = '"C:\Program Files\PowerShell\7\pwsh.exe" -File x.ps1 -NoProfile'; Match = 'NoProfile' }
        @{ Why = 'a different option that begins with -NoProfile'; Line = '"C:\Program Files\PowerShell\7\pwsh.exe" -NoProfileLoadTime -File x.ps1'; Match = 'NoProfile' }
        @{ Why = 'a percent expansion'; Line = '"C:\Windows\System32\cmd.exe" /c %X%'; Match = 'expands' }
        @{ Why = 'a percent expansion inside quotes'; Line = '"C:\Windows\System32\cmd.exe" /c "%X%"'; Match = 'expands' }
        @{ Why = 'an exclamation mark'; Line = '"C:\Windows\System32\cmd.exe" /c echo !X!'; Match = 'expands' }
        @{ Why = 'parentheses outside quotes'; Line = '"C:\Windows\System32\cmd.exe" /c (echo a)'; Match = 'unquoted' }
        @{ Why = 'a semicolon followed by anything but the closing statement of the shipped command'; Line = '"C:\Windows\System32\cmd.exe" /c exit ; calc.exe'; Match = 'semicolon' }
        @{ Why = 'a second statement after the closing statement of the shipped command'; Line = '"C:\Windows\System32\cmd.exe" /c exit ; exit (@(Get-Variable -Name LASTEXITCODE -ValueOnly -ErrorAction Ignore) + 2)[0] ; calc.exe'; Match = 'semicolon' }
        @{ Why = 'PowerShell given a session configuration'; Line = '"C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile -ConfigurationFile x.pssc -File y.ps1'; Match = 'ConfigurationFile' }
        @{ Why = 'PowerShell given a settings file'; Line = '"C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile -SettingsFile x.json -File y.ps1'; Match = 'SettingsFile' }
        @{ Why = 'a working directory that swallows what looks like -NoProfile'; Line = '"C:\Program Files\PowerShell\7\pwsh.exe" -WorkingDirectory -nop -File y.ps1'; Match = 'NoProfile' }
        @{ Why = 'a renamed copy of an interpreter'; Line = 'C:\Tools\runner.exe -NoProfile -File x.ps1'; Match = 'not PowerShell' }
        @{ Why = 'a preview build of PowerShell'; Line = '"C:\Program Files\PowerShell\7-preview\pwsh-preview.exe" -NoProfile -File x.ps1'; Match = 'not PowerShell' }
        @{ Why = 'the PowerShell ISE'; Line = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell_ise.exe -NoProfile -File x.ps1'; Match = 'not PowerShell' }
        @{ Why = 'a name that only ends in powershell'; Line = 'C:\Tools\notpowershell.exe -NoProfile -File x.ps1'; Match = 'not PowerShell' }
        @{ Why = 'cmd.exe, whose registry AutoRun commands this check does not read'; Line = 'C:\Windows\System32\cmd.exe /d /c exit'; Match = 'not PowerShell' }
        @{ Why = 'a script host'; Line = 'C:\Windows\System32\wscript.exe //B x.vbs'; Match = 'not PowerShell' }
        # Review pass 3 part B, S-17: a PowerShell wrapper expands $(...) inside double quotes, reads a
        # single-quoted double quote as text, and treats curly quotes as quotes, so this scan, which toggles
        # on the ASCII double quote, and that shell can disagree about where a quoted part ends.
        @{ Why = 'a subexpression inside double quotes'; Line = '"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -Command "$(calc.exe)"'; Match = 'backtick' }
        @{ Why = 'a variable inside double quotes'; Line = '"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -Command "$env:PLUGIN_ROOT"'; Match = 'backtick' }
        @{ Why = 'a backtick inside double quotes'; Line = ('"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -Command "a' + [char]96 + '"b"'); Match = 'backtick' }
        @{ Why = 'a single-quoted double quote that hides a semicolon'; Line = '"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -Command x ''"'' ; calc.exe ''"'''; Match = 'single quote' }
        @{ Why = 'a single-quoted double quote that hides an ampersand'; Line = '"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -Command x ''"'' & calc.exe ''"'''; Match = 'single quote' }
        @{ Why = 'a single quote in an unquoted program word'; Line = 'C:\Tools\O''Brien\powershell.exe -NoProfile -File x.ps1'; Match = 'unquoted' }
        @{ Why = 'a curly double quote that closes a string for PowerShell only'; Line = ('"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -Command "a' + [char]0x201D + ' ; calc.exe ; ' + [char]0x201C + 'b"'); Match = 'outside printable ASCII' }
        @{ Why = 'a curly single quote'; Line = ('"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -Command ' + [char]0x2018 + '"' + [char]0x2019 + ' ; calc.exe'); Match = 'outside printable ASCII' }
        @{ Why = 'a no-break space before the program'; Line = ([string][char]0xA0 + '"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -Command exit'); Match = 'outside printable ASCII' }
        @{ Why = 'a zero-width space inside the program name'; Line = ('C:\Windows\System32\WindowsPowerShell\v1.0\power' + [char]0x200B + 'shell.exe -NoProfile -Command exit'); Match = 'outside printable ASCII' }
        @{ Why = 'a dot segment in the program path'; Line = 'C:\Windows\System32\..\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -Command exit'; Match = 'dot segment' }
        @{ Why = 'a dot segment written with forward slashes'; Line = 'C:/Windows/System32/../System32/WindowsPowerShell/v1.0/powershell.exe -NoProfile -Command exit'; Match = 'dot segment' }
        # Review pass 3 part C, S-21: refusing a list of characters is never complete. Each line below was
        # accepted by that scan and is read three ways by cmd.exe, a PowerShell wrapper and a POSIX shell.
        @{ Why = 'a comment that hides the closing statement from PowerShell'; Line = '"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -Command "exit 0" # ; exit (@(Get-Variable -Name LASTEXITCODE -ValueOnly -ErrorAction Ignore) + 2)[0]'; Match = 'shape' }
        @{ Why = 'a comment marker glued to the semicolon'; Line = '"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -Command "exit 0" #; exit (@(Get-Variable -Name LASTEXITCODE -ValueOnly -ErrorAction Ignore) + 2)[0]'; Match = 'shape' }
        @{ Why = 'a quoted part that is never closed'; Line = '"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -Command "exit 0'; Match = 'shape' }
        @{ Why = 'a doubled quote inside a quoted part'; Line = '"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -File x.ps1 "a ""b ; c"" d" e'; Match = 'shape' }
        @{ Why = 'a backslash before a quote outside a quoted part, which a POSIX shell reads as a literal quote'; Line = '"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -Command x \"; calc.exe; \" y'; Match = 'shape' }
        @{ Why = 'a backslash before the closing quote'; Line = '"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -Command "a\"'; Match = 'shape' }
        @{ Why = 'a comma between words'; Line = '"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -Command x,y'; Match = 'shape' }
        @{ Why = 'an equals sign in a word'; Line = '"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -Command x=y'; Match = 'shape' }
        @{ Why = 'a brace group'; Line = '"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -Command {x}'; Match = 'shape' }
        @{ Why = 'an at sign'; Line = '"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -Command @x'; Match = 'shape' }
        @{ Why = 'text glued to the closing quote of the program'; Line = '"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"-NoProfile -Command exit'; Match = 'shape' }
        # S-22: the unquoted program word is read by the shell as well.
        @{ Why = 'a semicolon in an unquoted program word'; Line = 'C:\Tools\a;b\powershell.exe -NoProfile -File x.ps1'; Match = 'program word' }
        @{ Why = 'a comma in an unquoted program word'; Line = 'C:\Tools\a,b\powershell.exe -NoProfile -File x.ps1'; Match = 'program word' }
        @{ Why = 'an equals sign in an unquoted program word'; Line = 'C:\Tools\a=b\powershell.exe -NoProfile -File x.ps1'; Match = 'program word' }
        # Review pass 3 part D, S-25: PowerShell reads a word that starts with a dash as a parameter, and binds
        # '-name:' to the next word or fails to parse it; cmd.exe passes it through. Reproduced on the shipped body.
        @{ Why = 'a dash word that ends in a colon, before the closing statement'; Line = '"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -Command "exit 0" -x: ; exit (@(Get-Variable -Name LASTEXITCODE -ValueOnly -ErrorAction Ignore) + 2)[0]'; Match = 'shape' }
        @{ Why = 'a dash word that ends in a colon, as the last word'; Line = '"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -Command "exit 0" -x:'; Match = 'shape' }
        @{ Why = 'a dash word that PowerShell splits at a dot'; Line = '"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -File x.ps1 -Z.7'; Match = 'shape' }
        @{ Why = 'a dash word that ends in a dot'; Line = '"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -File x.ps1 -y.'; Match = 'shape' }
        @{ Why = 'a dash word that holds a digit'; Line = '"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -File x.ps1 -x1'; Match = 'shape' }
        @{ Why = 'a lone dash'; Line = '"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -File x.ps1 -'; Match = 'shape' }
        # S-26: a network path is two separators in any mix, and the check measured the access list over the network.
        @{ Why = 'a network path written with a slash and a backslash'; Line = '\/server\share\powershell.exe -NoProfile -Command exit'; Match = 'network or device' }
        @{ Why = 'a network path written with a backslash and a slash'; Line = '/\server\share\powershell.exe -NoProfile -Command exit'; Match = 'network or device' }
        @{ Why = 'a quoted network path written with a slash and a backslash'; Line = '"\/server\share\powershell.exe" -NoProfile -Command exit'; Match = 'network or device' }
        # Review pass 3 part E, S-30: .NET calls a path that starts with \??\ fully qualified and CreateFileW opens it as
        # the NT path it names, so a quoted program path could point the measurement of the access list at a share.
        # Only a path that starts with a drive letter and a separator is read.
        @{ Why = 'a quoted NT path to a local program'; Line = '"\??\C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -Command exit'; Match = 'drive letter' }
        @{ Why = 'a quoted NT path to a share'; Line = '"\??\UNC\server\share\powershell.exe" -NoProfile -Command exit'; Match = 'drive letter' }
        @{ Why = 'a quoted path with a single question mark'; Line = '"\?\C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -Command exit'; Match = 'drive letter' }
        @{ Why = 'an unquoted NT path'; Line = '\??\C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -Command exit'; Match = 'drive letter' }
        # S-33: only an unquoted program word is held to the program-word shape, so a second colon, after the one that ends the
        # drive letter, got through the drive rule in a quoted word. Windows rejects such a name as invalid or reads it as a
        # stream of a file, so none of these names the file it appears to, and the colon is refused whether the word is quoted
        # or not. The match is the phrase of the reason, because "colon" is also a part of "semicolon", and the drive letters
        # differ so that a rule that narrows the letter (upper case only, or C only) is seen.
        @{ Why = 'a quoted program path with a colon right after the drive'; Line = '"C:\:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -Command exit'; Match = 'second colon' }
        @{ Why = 'a quoted program path with a colon in a folder name'; Line = '"C:\Windows\System32\WindowsPowerShell\v1.0:x\powershell.exe" -NoProfile -Command exit'; Match = 'second colon' }
        @{ Why = 'a quoted program path with a colon in a folder name, written with forward slashes'; Line = '"C:/Windows/System32:x/WindowsPowerShell/v1.0/powershell.exe" -NoProfile -Command exit'; Match = 'second colon' }
        @{ Why = 'a quoted program path with a colon that names a stream of the program'; Line = '"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe:x" -NoProfile -Command exit'; Match = 'second colon' }
        @{ Why = 'an unquoted program path with a colon right after the drive'; Line = 'C:\:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -Command exit'; Match = 'second colon' }
        @{ Why = 'a quoted program path with a colon right after a lower-case drive letter'; Line = '"c:\:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -Command exit'; Match = 'second colon' }
        @{ Why = 'a quoted program path with a colon in a folder name on another drive'; Line = '"D:\Tools\a:b\powershell.exe" -NoProfile -Command exit'; Match = 'second colon' }
        # S-31: the Windows PowerShell 5.1 wrapper drops an empty quoted argument that cmd.exe and the PowerShell 7
        # wrapper pass on, so the shape does not read an empty quoted word.
        @{ Why = 'an empty quoted word'; Line = '"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -File x.ps1 ""'; Match = 'shape' }
    ) {
        $result = Get-HookInterpreter -CommandLine $Line

        $result.Path | Should -BeNullOrEmpty
        $result.Problem | Should -Match $Match
    }

    # XML 1.0 does not allow a form feed. Pester writes the data of a skipped parameterized test into the name of its NUnit
    # test-case, so a table row that carries one breaks the report on every platform that skips the test (Ubuntu and macOS
    # skip this Describe), and the build fails with no failed test. It is built here and not carried in a row of the table.
    It 'refuses a form feed' {
        $line = '"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -Command exit' + [char]12 + 'x'

        $result = Get-HookInterpreter -CommandLine $line

        $result.Path | Should -BeNullOrEmpty
        $result.Problem | Should -Match 'outside printable ASCII'
    }

    # Review pass 2, S-11: only the first word was judged, so a shell that read a separator after it ran
    # a second program that nobody measured, and PowerShell without -NoProfile ran the profile of the
    # identity under test first.
    It 'reads a command whose shell characters are inside quotes' {
        $result = Get-HookInterpreter -CommandLine '"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -Command "echo a & echo b | more > nul < nul ^ x"'

        $result.Problem | Should -BeNullOrEmpty
        $result.Path | Should -Be 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
    }

    # The shipped commands carry single quotes only inside their -Command text, so inside double quotes they stay legal.
    It 'reads single quotes that sit inside double quotes, with a semicolon between them' {
        $line = '"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -Command "Write-Output ''a ; b''"'

        (Get-HookInterpreter -CommandLine $line).Problem | Should -BeNullOrEmpty
    }

    # Review pass 3 part C: what is inside a double-quoted word is data to every shell that reads it, so the
    # shape lets anything through there but a double quote, and the controls below pin that boundary.
    It 'reads a quoted word that holds characters a shell would read as syntax outside quotes' {
        $line = '"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -Command "a ; b # c, d = e { f } @g (h) & i | j < k > l ^ m"'

        (Get-HookInterpreter -CommandLine $line).Problem | Should -BeNullOrEmpty
    }

    It 'reads words that are separated by tabs' {
        $line = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe`t-NoProfile`t-Command`texit"

        (Get-HookInterpreter -CommandLine $line).Problem | Should -BeNullOrEmpty
    }

    It 'reads a quoted program path that holds spaces and parentheses' {
        $result = Get-HookInterpreter -CommandLine '"C:\Program Files (x86)\PowerShell\7\pwsh.exe" -NoProfile -File x.ps1'

        $result.Problem | Should -BeNullOrEmpty
        $result.Path | Should -Be 'C:\Program Files (x86)\PowerShell\7\pwsh.exe'
    }

    It 'says whether the program path was quoted' {
        (Get-HookInterpreter -CommandLine '"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -Command exit').Quoted | Should -BeTrue
        (Get-HookInterpreter -CommandLine 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -Command exit').Quoted | Should -BeFalse
    }

    It 'reads the statement the shipped Windows command ends with, which only an outer PowerShell understands' {
        $line = '"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -Command "exit 0" ; exit (@(Get-Variable -Name LASTEXITCODE -ValueOnly -ErrorAction Ignore) + 2)[0]'

        (Get-HookInterpreter -CommandLine $line).Problem | Should -BeNullOrEmpty
    }

    # Review pass 3: the check on a toy -Command string would not catch a regression on the real, long one.
    It 'reads the <_> command the shipped hooks.json carries, with its interpreter named by absolute path' -ForEach @('windows', 'command', 'powershell') {
        $shipped = [System.IO.File]::ReadAllText($script:realConfig) | ConvertFrom-Json
        $text = [string]@($shipped.hooks.PreToolUse)[0].$_
        $bare = if ($text.StartsWith('powershell ')) { 'powershell' } else { 'pwsh' }
        $interpreter = if ($bare -eq 'powershell') { $script:systemPowerShell } else { 'C:\Program Files\PowerShell\7\pwsh.exe' }

        $result = Get-HookInterpreter -CommandLine ('"' + $interpreter + '"' + $text.Substring($bare.Length))

        $result.Problem | Should -BeNullOrEmpty
        $result.Path | Should -Be ([System.IO.Path]::GetFullPath($interpreter))
    }

    It 'reads -NoProfile as PowerShell does: by prefix, and after other options' -ForEach @(
        @{ Line = '"C:\Program Files\PowerShell\7\pwsh.exe" -nop -File x.ps1' }
        @{ Line = '"C:\Program Files\PowerShell\7\pwsh.exe" -NoPro -File x.ps1' }
        @{ Line = '"C:\Program Files\PowerShell\7\pwsh.exe" -ExecutionPolicy Bypass -NoProfile -File x.ps1' }
        @{ Line = '"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -Command exit' }
    ) {
        (Get-HookInterpreter -CommandLine $Line).Problem | Should -BeNullOrEmpty
    }

    # Review pass 3 part D, S-28: an empty word reached the option reader as an empty string and threw, so the
    # verifier ended with exit code 1 and nothing verified, where it should refuse the line with its reason.
    # Part E, S-31: the shape now refuses an empty quoted word, and the option reader still takes an empty argument.
    It 'refuses a line with an empty quoted word, with the reason of the shape and without throwing' {
        $line = '"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -Command exit ""'

        { Get-HookInterpreter -CommandLine $line } | Should -Not -Throw
        (Get-HookInterpreter -CommandLine $line).Problem | Should -Match 'shape'
    }

    It 'lets the option reader take an empty argument and refuse it as no option, without throwing' {
        { Get-PowerShellLaunchOption -Argument @('-NoProfile', '') } | Should -Not -Throw
        (Get-PowerShellLaunchOption -Argument @('-NoProfile', '')).Problem | Should -Match 'not an option'
    }

    It 'refuses an empty word before the command as an argument that is not an option, without throwing' {
        $line = '"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile "" -Command exit'

        { Get-HookInterpreter -CommandLine $line } | Should -Not -Throw
        (Get-HookInterpreter -CommandLine $line).Problem | Should -Not -BeNullOrEmpty
    }

    # Review pass 3 part D, S-27: a POSIX shell reads a backslash outside double quotes as an escape, and inside them
    # before a dollar, a backtick, a quote or another backslash, so it can drop a separator, join two words, or start
    # a sibling path that nobody measured. The platform is switched here so that the rule is tested on every host.
    It 'refuses a backslash anywhere in the line off Windows: <Line>' -ForEach @(
        @{ Line = '/opt/x\y/pwsh -NoProfile -Command exit' }
        @{ Line = '/opt/pwsh -NoProfile -Command "a\\b"' }
        @{ Line = '/opt/pwsh -NoProfile -Command a\ b' }
    ) {
        $before = $script:OnWindows
        $script:OnWindows = $false

        try {
            $result = Get-HookInterpreter -CommandLine $Line
        } finally {
            $script:OnWindows = $before
        }

        $result.Path | Should -BeNullOrEmpty
        $result.Problem | Should -Match 'backslash'
    }

    # Review pass 3 part D, S-25: the shape says that PowerShell reads an accepted line as the words the shape saw. That
    # is measured here, with the parser of this host, over generated lines, so a word that the shape lets through and
    # PowerShell reads differently (a dash word that ends in a colon, or that splits at a dot) is found by the suite
    # and not by the next review. The generator is seeded, so a failure repeats. Part E: it also writes a tab inside a
    # quoted word, uses -File as well as -Command, and ends some lines with the pinned statement. It checks the
    # structure PowerShell reads, not what a wrapper hands on to the program it starts, so it cannot see S-31.
    It 'reads every accepted line as one command whose words are the words the shape saw' {
        $result = Invoke-ShapeProperty -Seed 20261014

        $result.Accepted | Should -BeGreaterThan 500 -Because 'the generator has to reach lines that the shape accepts, or this test proves nothing'
        $result.Deviation.Count | Should -Be 0 -Because ('PowerShell read these accepted lines as other words than the shape did: ' + (($result.Deviation | Select-Object -First 5) -join ' || '))
    }

    # The fixed seed above makes a failure repeat, and it shows the same lines on every run. On CI the same property runs once
    # more on a seed that is drawn then and printed, so a deviation that only some seed finds can be found by the pipeline. The
    # printed seed, given in CONTAINMENT_PROPERTY_SEED, runs it again on a Windows machine; whether PowerShell reads a line as
    # other words depends on its parser, so the printed line names the version too. The seed is chosen at run time and not at
    # discovery, so that Resolve-PropertySeed can be tested; the test skips itself when nothing asks for a seed.
    It 'reads every accepted line as one command on a seed that is drawn on CI or given' {
        $result = Invoke-PropertyFromEnvironment

        if ($null -eq $result) {
            Set-ItResult -Skipped -Because 'neither CI nor CONTAINMENT_PROPERTY_SEED asks for a seed that is not fixed'
            return
        }

        $result.Accepted | Should -BeGreaterThan 500 -Because ('the generator has to reach lines that the shape accepts, or this test proves nothing (seed {0})' -f $result.Seed)
        $result.Deviation.Count | Should -Be 0 -Because ('PowerShell {0} read these accepted lines as other words than the shape did, on the seed {1}; replay it with CONTAINMENT_PROPERTY_SEED={1}: {2}' -f $PSVersionTable.PSVersion, $result.Seed, (($result.Deviation | Select-Object -First 5) -join ' || '))
    }

    It 'draws no seed when neither CI nor a seed to replay asks for one' -ForEach @(
        @{ Ci = $null; Requested = $null }
        @{ Ci = ''; Requested = '' }
        @{ Ci = 'false'; Requested = '   ' }
        @{ Ci = '1'; Requested = $null }
        @{ Ci = 'yes'; Requested = $null }
    ) {
        Resolve-PropertySeed -Ci $Ci -Requested $Requested | Should -BeNullOrEmpty
    }

    It 'draws a seed on CI, whatever the letter case of true: <Ci>' -ForEach @(
        @{ Ci = 'true' }
        @{ Ci = 'True' }
        @{ Ci = 'TRUE' }
    ) {
        $seed = Resolve-PropertySeed -Ci $Ci -Requested $null

        $seed | Should -BeOfType ([int])
        $seed | Should -BeGreaterOrEqual 0
    }

    It 'draws a different seed each time' {
        $seeds = 1..20 | ForEach-Object -Process { Resolve-PropertySeed -Ci 'true' -Requested $null }

        @($seeds | Select-Object -Unique).Count | Should -BeGreaterThan 1
    }

    It 'draws seeds from the whole range and not from a narrow one' {
        $seeds = 1..50 | ForEach-Object -Process { Resolve-PropertySeed -Ci 'true' -Requested $null }

        ($seeds | Measure-Object -Maximum).Maximum | Should -BeGreaterThan 1000000000 -Because 'a draw from a small range would run a seed that has run before'
    }

    It 'replays the seed that is asked for, on CI and off it: <Requested>' -ForEach @(
        @{ Requested = '0'; Expected = 0 }
        @{ Requested = '20261018'; Expected = 20261018 }
        @{ Requested = ' 42 '; Expected = 42 }
        @{ Requested = '2147483647'; Expected = 2147483647 }
    ) {
        Resolve-PropertySeed -Ci 'true' -Requested $Requested | Should -Be $Expected
        Resolve-PropertySeed -Ci $null -Requested $Requested | Should -Be $Expected
    }

    It 'refuses a seed to replay that is not a whole number from 0 to 2147483647, and draws no other: <Requested>' -ForEach @(
        @{ Requested = 'abc' }
        @{ Requested = '-1' }
        @{ Requested = '1.5' }
        @{ Requested = '2147483648' }
        @{ Requested = '+5' }
        @{ Requested = '1e3' }
        @{ Requested = '0x10' }
    ) {
        { Resolve-PropertySeed -Ci 'true' -Requested $Requested } | Should -Throw -ExpectedMessage '*CONTAINMENT_PROPERTY_SEED*'
    }

    It 'runs the property on the seed that is asked for, and says which seed it ran' {
        $result = Invoke-PropertyOnAskedSeed -Ci $null -Requested '77' -LineCount 40

        $result.Seed | Should -Be 77
        $result.LineCount | Should -Be 40
        $result.Deviation.Count | Should -Be 0
    }

    It 'runs the property on a drawn seed on CI, and says which seed it ran' {
        $result = Invoke-PropertyOnAskedSeed -Ci 'true' -Requested $null -LineCount 40

        $result.Seed | Should -BeOfType ([int])
        $result.Seed | Should -BeGreaterOrEqual 0
        $result.LineCount | Should -Be 40
    }

    It 'runs nothing when neither CI nor a seed to replay asks for it' {
        Invoke-PropertyOnAskedSeed -Ci $null -Requested $null -LineCount 40 | Should -BeNullOrEmpty
    }

    It 'runs the same lines again from the seed that it printed' {
        $first = Invoke-PropertyOnAskedSeed -Ci 'true' -Requested $null -LineCount 60
        $again = Invoke-PropertyOnAskedSeed -Ci $null -Requested ([string]$first.Seed) -LineCount 60

        $again.Seed | Should -Be $first.Seed
        $again.Accepted | Should -Be $first.Accepted
    }

    It 'announces the seed before it runs the property, so that a crash still names it' {
        $announced = [System.Collections.Generic.List[int]]::new()
        $record = { param($Seed) $announced.Add($Seed) }.GetNewClosure()
        $crash = { throw 'the interpreter crashed' }

        { Invoke-PropertyOnAskedSeed -Ci $null -Requested '77' -LineCount 40 -OnSeed $record -Interpreter $crash } | Should -Throw -ExpectedMessage '*the interpreter crashed*'

        $announced.Count | Should -Be 1
        $announced[0] | Should -Be 77
    }

    It 'announces no seed when nothing asks for one' {
        $announced = [System.Collections.Generic.List[int]]::new()
        $record = { param($Seed) $announced.Add($Seed) }.GetNewClosure()

        $null = Invoke-PropertyOnAskedSeed -Ci $null -Requested $null -LineCount 40 -OnSeed $record

        $announced.Count | Should -Be 0
    }

    It 'generates the same lines from the same seed, and other lines from another seed' {
        $linesOf = {
            param([int]$Seed)

            $seen = [System.Collections.Generic.List[string]]::new()
            $recorder = { param($CommandLine) $seen.Add($CommandLine); [pscustomobject]@{ Problem = 'recorded'; Path = $null } }.GetNewClosure()
            $null = Invoke-ShapeProperty -Seed $Seed -LineCount 200 -Interpreter $recorder

            $seen -join "`n"
        }

        $first = & $linesOf 7
        $again = & $linesOf 7
        $other = & $linesOf 8

        $first | Should -Not -BeNullOrEmpty
        $again | Should -BeExactly $first
        $other | Should -Not -BeExactly $first
    }

    It 'reports a line that the interpreter accepts and PowerShell reads as other words' {
        $acceptsEverything = { [pscustomobject]@{ Problem = $null; Path = 'C:\x' } }

        $result = Invoke-ShapeProperty -Seed 20261014 -LineCount 400 -Interpreter $acceptsEverything

        $result.Accepted | Should -Be 400
        $result.Deviation.Count | Should -BeGreaterThan 0
    }

    It 'reports the seed and the number of lines it ran' {
        $result = Invoke-ShapeProperty -Seed 31 -LineCount 50

        $result.Seed | Should -Be 31
        $result.LineCount | Should -Be 50
    }

    # Every check of Test-ShapeReading has a row below that fails that check and no other, so that a check which is removed or
    # weakened is found here and not by a CI run that goes on passing. {tail} in a row stands for the pinned closing statement,
    # and {TAIL} for the same statement in capital letters.
    It 'reads <Why> as the words that were written' -ForEach @(
        @{ Why = 'a plain command'; Text = 'p -NoProfile -Command a'; Expected = @('p', '-NoProfile', '-Command', 'a'); Closed = $false }
        @{ Why = 'an option name of letters only'; Text = 'p -NoProfile -Command -Y'; Expected = @('p', '-NoProfile', '-Command', '-Y'); Closed = $false }
        @{ Why = 'two spaces between the words'; Text = 'p  -NoProfile  -Command  a'; Expected = @('p', '-NoProfile', '-Command', 'a'); Closed = $false }
        @{ Why = 'a quoted word with a space in it'; Text = 'p -NoProfile -Command "a b"'; Expected = @('p', '-NoProfile', '-Command', '"a b"'); Closed = $false }
        @{ Why = 'a command and the pinned closing statement'; Text = 'p -NoProfile -Command a; {tail}'; Expected = @('p', '-NoProfile', '-Command', 'a'); Closed = $true }
    ) {
        $line = $Text.Replace('{tail}', $script:HookExitTail)

        Test-ShapeReading -Text $line -Expected $Expected -Closed:$Closed | Should -BeTrue
    }

    It 'does not read <Why> as the words that were written' -ForEach @(
        @{ Why = 'a dash word that ends in a colon'; Text = 'p -NoProfile -Command -a: b'; Expected = @('p', '-NoProfile', '-Command', '-a:', 'b'); Closed = $false }
        @{ Why = 'a dash word that splits at a dot'; Text = 'p -NoProfile -Command -Z.7'; Expected = @('p', '-NoProfile', '-Command', '-Z.7'); Closed = $false }
        @{ Why = 'a parse error that leaves the words as they were'; Text = 'p -NoProfile -Command )'; Expected = @('p', '-NoProfile', '-Command'); Closed = $false }
        @{ Why = 'a redirection'; Text = 'p -NoProfile -Command a >b'; Expected = @('p', '-NoProfile', '-Command', 'a'); Closed = $false }
        @{ Why = 'one word more than was written'; Text = 'p -NoProfile -Command a b'; Expected = @('p', '-NoProfile', '-Command', 'a'); Closed = $false }
        @{ Why = 'a first word that differs'; Text = 'q -NoProfile -Command a'; Expected = @('p', '-NoProfile', '-Command', 'a'); Closed = $false }
        @{ Why = 'a later word that differs'; Text = 'p -NoProfile -Command a b'; Expected = @('p', '-NoProfile', '-Command', 'a', 'c'); Closed = $false }
        @{ Why = 'a word that differs only in letter case'; Text = 'p -NoProfile -Command A'; Expected = @('p', '-NoProfile', '-Command', 'a'); Closed = $false }
        @{ Why = 'a pipeline of two commands'; Text = 'p -NoProfile -Command a | q'; Expected = @('p', '-NoProfile', '-Command', 'a'); Closed = $false }
        @{ Why = 'a second statement that was not written'; Text = 'p -NoProfile -Command a; b'; Expected = @('p', '-NoProfile', '-Command', 'a'); Closed = $false }
        @{ Why = 'a closing statement that was not written'; Text = 'p -NoProfile -Command a; {tail}'; Expected = @('p', '-NoProfile', '-Command', 'a'); Closed = $false }
        @{ Why = 'a closing statement that is not the pinned one'; Text = 'p -NoProfile -Command a; exit 7'; Expected = @('p', '-NoProfile', '-Command', 'a'); Closed = $true }
        @{ Why = 'the pinned closing statement in capital letters'; Text = 'p -NoProfile -Command a; {TAIL}'; Expected = @('p', '-NoProfile', '-Command', 'a'); Closed = $true }
        @{ Why = 'a closing statement that is missing'; Text = 'p -NoProfile -Command a'; Expected = @('p', '-NoProfile', '-Command', 'a'); Closed = $true }
    ) {
        $line = $Text.Replace('{tail}', $script:HookExitTail).Replace('{TAIL}', $script:HookExitTail.ToUpperInvariant())

        Test-ShapeReading -Text $line -Expected $Expected -Closed:$Closed | Should -BeFalse
    }

    It 'lists the accepted lines in the result, and the same lines for the same seed' {
        $result = Invoke-ShapeProperty -Seed 31 -LineCount 50

        $result.AcceptedLine.Count | Should -Be $result.Accepted
        $result.Accepted | Should -BeGreaterThan 0

        $again = Invoke-ShapeProperty -Seed 31 -LineCount 50
        $again.AcceptedLine -join "`n" | Should -BeExactly ($result.AcceptedLine -join "`n")
    }

    # The property only means something on lines of the kinds that the reviews asked it to reach: the quoted word, the tab inside
    # it, -File as well as -Command, both separators, the closing statement, and the dash words that PowerShell reads as other
    # words. A feature the shape refuses (the dash words) is in the generated lines and in no accepted one.
    Context 'what the generated lines reach' {
        BeforeAll {
            $script:reachGenerated = [System.Collections.Generic.List[string]]::new()
            $recorder = { param($CommandLine) $script:reachGenerated.Add($CommandLine); [pscustomobject]@{ Problem = 'recorded'; Path = $null } }

            $null = Invoke-ShapeProperty -Seed 20261014 -LineCount 400 -Interpreter $recorder
            $script:reachAccepted = @((Invoke-ShapeProperty -Seed 20261014 -LineCount 400).AcceptedLine)
        }

        # Least is how many of the 400 generated lines of the fixed seed have to carry the feature: about a third of what the
        # generator gives. A step of the generator that is dropped shows up in it, and not only a feature that is gone, because a
        # word has the same shape by chance, though much less often: the dash in front of a word and the colon or dot that ends
        # one are steps of their own. The pattern for the tab walks the line word by word, so that the tab between two quoted
        # words is not read as a tab inside one.
        $feature = @(
            @{ Feature = 'a quoted word'; Pattern = '"[^"]*"'; Least = 100; Accepted = $true }
            @{ Feature = 'a tab inside a quoted word'; Pattern = '^(?:[^"]|"[^"]*")*"[^"]*\t[^"]*"'; Least = 10; Accepted = $true }
            @{ Feature = 'the option -Command'; Pattern = ' -Command[ \t]'; Least = 50; Accepted = $true }
            @{ Feature = 'the option -File'; Pattern = ' -File[ \t]'; Least = 50; Accepted = $true }
            @{ Feature = 'a tab between the words'; Pattern = '^\S+\t-NoProfile\t'; Least = 40; Accepted = $true }
            @{ Feature = 'two spaces between the words'; Pattern = '^\S+  -NoProfile  '; Least = 40; Accepted = $true }
            @{ Feature = 'the pinned closing statement'; Pattern = '; exit \(.*\)\[0\]$'; Least = 40; Accepted = $true }
            @{ Feature = 'a dash word that ends in a colon'; Pattern = '(^|\s)-[^\s"]*:(\s|;|$)'; Least = 20; Accepted = $false }
            @{ Feature = 'a dash word that ends in a dot'; Pattern = '(^|\s)-[^\s"]*\.(\s|;|$)'; Least = 20; Accepted = $false }
            @{ Feature = 'a dash word with a dot inside'; Pattern = '(^|\s)-[^\s".]+\.[^\s".]'; Least = 10; Accepted = $false }
        )

        It 'generates at least <Least> lines with <Feature>' -ForEach $feature {
            @($script:reachGenerated | Where-Object -FilterScript { $_ -cmatch $Pattern }).Count | Should -BeGreaterOrEqual $Least -Because 'the generator has to keep reaching this kind of line, or the property stops testing it'
        }

        It 'accepts lines with <Feature>' -ForEach @($feature | Where-Object -FilterScript { $_.Accepted }) {
            @($script:reachAccepted | Where-Object -FilterScript { $_ -cmatch $Pattern }).Count | Should -BeGreaterThan 0
        }
    }

    It 'writes the line that names the seed, the PowerShell version and the way to run the seed again' {
        Format-PropertySeedLine -Seed 77 -Version '7.6.7' | Should -BeExactly 'Property test of the hook-line shape: seed 77, PowerShell 7.6.7. Replay it with CONTAINMENT_PROPERTY_SEED=77.'
    }

    It 'names the PowerShell version of this host unless it is given another' {
        Format-PropertySeedLine -Seed 5 | Should -BeExactly ('Property test of the hook-line shape: seed 5, PowerShell {0}. Replay it with CONTAINMENT_PROPERTY_SEED=5.' -f $PSVersionTable.PSVersion)
    }

    # The wiring of the CI test: which two variables it reads, and what it writes before the run.
    It 'runs on a drawn seed and prints it when CI is true and no seed is given' {
        $run = Invoke-PropertyWithEnvironment -Ci 'true' -Seed $null

        $run.Result.LineCount | Should -Be 40
        $run.Printed.Count | Should -Be 1
        $run.Printed[0].MessageData | Should -BeExactly (Format-PropertySeedLine -Seed $run.Result.Seed)
    }

    It 'runs on the seed that is given and prints it, whatever CI says: <Ci>' -ForEach @(
        @{ Ci = 'true' }
        @{ Ci = 'false' }
        @{ Ci = $null }
    ) {
        $run = Invoke-PropertyWithEnvironment -Ci $Ci -Seed '77'

        $run.Result.Seed | Should -Be 77
        $run.Printed.Count | Should -Be 1
        $run.Printed[0].MessageData | Should -BeExactly (Format-PropertySeedLine -Seed 77)
    }

    It 'runs nothing and prints nothing when neither CI nor a seed asks for it' {
        $run = Invoke-PropertyWithEnvironment -Ci $null -Seed $null

        $run.Result | Should -BeNullOrEmpty
        $run.Printed.Count | Should -Be 0
    }

    It 'fails on a seed to replay that is not a whole number, and does not run another' {
        { Invoke-PropertyWithEnvironment -Ci 'true' -Seed 'abc' } | Should -Throw -ExpectedMessage '*CONTAINMENT_PROPERTY_SEED*'
    }

    # Each of the two tests sets the state that it needs and puts the process back as it found it, so that a defect in the helper
    # that an earlier test left behind cannot make the tests that follow it start from a changed state and pass.
    It 'puts CI and the seed variable back, and an unset one unset and not empty' {
        $ciBefore = [System.Environment]::GetEnvironmentVariable('CI')
        $seedBefore = [System.Environment]::GetEnvironmentVariable('CONTAINMENT_PROPERTY_SEED')

        try {
            Set-ProcessEnvironmentVariable -Name 'CI' -Value $null
            Set-ProcessEnvironmentVariable -Name 'CONTAINMENT_PROPERTY_SEED' -Value $null

            { Invoke-PropertyWithEnvironment -Ci 'false' -Seed 'abc' } | Should -Throw
            $null = Invoke-PropertyWithEnvironment -Ci 'true' -Seed '77'

            $null -eq [System.Environment]::GetEnvironmentVariable('CI') | Should -BeTrue
            $null -eq [System.Environment]::GetEnvironmentVariable('CONTAINMENT_PROPERTY_SEED') | Should -BeTrue
        } finally {
            Set-ProcessEnvironmentVariable -Name 'CI' -Value $ciBefore
            Set-ProcessEnvironmentVariable -Name 'CONTAINMENT_PROPERTY_SEED' -Value $seedBefore
        }
    }

    It 'puts CI and the seed variable back to the values they had' {
        $ciBefore = [System.Environment]::GetEnvironmentVariable('CI')
        $seedBefore = [System.Environment]::GetEnvironmentVariable('CONTAINMENT_PROPERTY_SEED')

        try {
            Set-ProcessEnvironmentVariable -Name 'CI' -Value 'yes'
            Set-ProcessEnvironmentVariable -Name 'CONTAINMENT_PROPERTY_SEED' -Value '5'

            $null = Invoke-PropertyWithEnvironment -Ci 'true' -Seed '77'

            [System.Environment]::GetEnvironmentVariable('CI') | Should -BeExactly 'yes'
            [System.Environment]::GetEnvironmentVariable('CONTAINMENT_PROPERTY_SEED') | Should -BeExactly '5'
        } finally {
            Set-ProcessEnvironmentVariable -Name 'CI' -Value $ciBefore
            Set-ProcessEnvironmentVariable -Name 'CONTAINMENT_PROPERTY_SEED' -Value $seedBefore
        }
    }
}

Describe 'Hook command runner' -Tag 'Unit' -Skip:(-not $script:onWindows) {
    It 'returns the exit code of the command' {
        Invoke-HookPayload -CommandLine 'exit 3' -Payload '{}' -EnvironmentVariable @{} | Should -Be 3
    }

    It 'starts the command in a folder of its own, not in the working directory of the caller' {
        $callerDirectory = Join-Path $TestDrive 'caller-directory'
        $null = New-Item -Path $callerDirectory -ItemType Directory -Force
        $seenPath = Join-Path $TestDrive 'seen-directory.txt'

        Invoke-InDirectory -Path $callerDirectory -Action {
            Invoke-HookPayload -CommandLine "cd > `"$seenPath`"" -Payload '{}' -EnvironmentVariable @{} | Should -Be 0
        }

        $seen = (Get-Content -LiteralPath $seenPath -Raw).Trim()
        $seen | Should -Not -Be $callerDirectory
        $seen | Should -BeLike '*containment-hook-*'
    }

    It 'tells the shell not to look for a command in the working directory' {
        Invoke-HookPayload -CommandLine 'if defined NoDefaultCurrentDirectoryInExePath (exit 5) else (exit 6)' -Payload '{}' -EnvironmentVariable @{} | Should -Be 5
    }

    It 'keeps that instruction when the caller tries to remove it' {
        Invoke-HookPayload -CommandLine 'if defined NoDefaultCurrentDirectoryInExePath (exit 5) else (exit 6)' -Payload '{}' -EnvironmentVariable @{ NoDefaultCurrentDirectoryInExePath = $null } | Should -Be 5
    }

    It 'does not run a program of the same name that the working directory of the caller holds' {
        $callerDirectory = Join-Path $TestDrive 'decoy-directory'
        $null = New-Item -Path $callerDirectory -ItemType Directory -Force
        $marker = Join-Path $TestDrive 'decoy-ran.txt'
        [System.IO.File]::WriteAllText((Join-Path $callerDirectory 'powershell.cmd'), "@echo off`r`necho ran> `"$marker`"`r`nexit /b 9`r`n")
        $script:decoyExit = $null

        Invoke-InDirectory -Path $callerDirectory -Action {
            $script:decoyExit = Invoke-HookPayload -CommandLine 'powershell -NoProfile -NonInteractive -Command "exit 3"' -Payload '{}' -EnvironmentVariable @{}
        }

        Test-Path -LiteralPath $marker | Should -BeFalse -Because 'the program in the working directory of the caller must not be the one that runs'
        $script:decoyExit | Should -Be 3
    }

    # cmd.exe runs the AutoRun commands of the registry of the identity that starts it unless it is given /D,
    # and they run before the probe does: a hostile identity could answer for the guard from there. The
    # shell reports its own command line, so this is read without writing anything to the registry.
    It 'starts the shell with /D before /C, so that no AutoRun command of the identity runs ahead of the probe' {
        $seenPath = Join-Path $TestDrive 'shell-command-line.txt'

        Invoke-HookPayload -CommandLine "echo %CMDCMDLINE%> `"$seenPath`"" -Payload '{}' -EnvironmentVariable @{} | Should -Be 0

        (Get-Content -LiteralPath $seenPath -Raw) | Should -Match '(?i)cmd(\.exe)?"?\s+/d\s+/c\s'
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
        $script:plugin = New-PluginTree -Name 'contained'

        # The access check is the subject of its own suites; here the interpreter is closed to the run unless a case says otherwise.
        $script:closed = [pscustomobject]@{ Path = ''; Closed = $true; Absent = $false; Violation = @(); Unmeasured = @() }
        Mock -CommandName Test-PathProtection -MockWith { $script:closed }
    }

    Context 'on the shipped hook with its interpreter named by absolute path' {
        BeforeAll {
            $script:shippedRun = Test-HookContract -HookConfigPath $script:plugin.Config -HookConfigSha256 $script:plugin.ConfigDigest `
                -HookScriptPath $script:plugin.Script -HookScriptSha256 $script:plugin.ScriptDigest
        }

        It 'passes with the exit codes 0, 2 and 2' {
            $script:shippedRun.status | Should -Be 'Pass' -Because $script:shippedRun.evidence
            $script:shippedRun.evidence | Should -Match 'safe=0 push=2 issue=2'
        }

        It 'names the pinned script that it ran' {
            $script:shippedRun.evidence | Should -Match ([regex]::Escape([System.IO.Path]::GetFullPath($script:plugin.Script)))
        }

        It 'names the interpreter that it ran' {
            $script:shippedRun.evidence | Should -Match ([regex]::Escape([System.IO.Path]::GetFullPath($script:systemPowerShell)))
        }

        # Review pass 3 part C, S-23, and the P5 follow-up that runs the line under the hosts' wrappers: the probe ran the line
        # through cmd.exe only, and the hosts the README lists wrap it in PowerShell, so a Pass names every spawn that measured it.
        It 'says that the line ran through cmd.exe and under both wrappers of the hosts, each with its codes' {
            $script:shippedRun.evidence | Should -Match 'through cmd\.exe /d /c'
            $script:shippedRun.evidence | Should -Match 'Windows PowerShell 5\.1'
            $script:shippedRun.evidence | Should -Match 'VS Code Local harness'
            $script:shippedRun.evidence | Should -Match 'Copilot SDK host'
            $script:shippedRun.evidence | Should -Match '-ExecutionPolicy Bypass -NoProfile -NoLogo -Command'
            $script:shippedRun.evidence | Should -Match '-nop -nol -c'
            [regex]::Matches($script:shippedRun.evidence, 'safe=0 push=2 issue=2').Count | Should -Be 3 -Because 'there is one measurement for each of the three spawns'
        }

        It 'says that the spawns are rebuilt from the README, that the program is this check''s own choice, and that no host ran the line' {
            $script:shippedRun.evidence | Should -Match 'README'
            $script:shippedRun.evidence | Should -Match 'program is this check''s own choice'
            $script:shippedRun.evidence | Should -Match 'no host'
            $script:shippedRun.evidence | Should -Not -Match 'the program and the arguments that the README table'
        }

        It 'no longer says that a PowerShell host reads the line by other rules, because it ran the line under two' {
            $script:shippedRun.evidence | Should -Not -Match 'by other rules'
            $script:shippedRun.evidence | Should -Not -Match 'not a measurement under'
        }

        It 'says nothing about a quoted program path when the path is not quoted' {
            $script:shippedRun.evidence | Should -Not -Match 'quoted'
        }
    }

    # The P5 follow-up that runs the pinned line under the wrappers of the documented hosts, and not through cmd.exe alone
    # (option A of the design note of 2026-10-16). The spawn forms are the README's table of hosts; HookLauncher.Tests.ps1
    # models the same two against the shipped line, and this check runs them against the pinned one.
    Context 'the wrappers the documented hosts start the line in' {
        BeforeAll {
            $script:wrapper = @(Get-HookWrapper)
            $script:ownPowerShell = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        }

        It 'lists Windows PowerShell from the system folder, then the PowerShell that runs the verifier' {
            $script:wrapper | Should -HaveCount 2
            $script:wrapper[0].Name | Should -BeExactly 'Windows PowerShell 5.1'
            $script:wrapper[0].Path | Should -BeExactly $script:systemPowerShell
            $script:wrapper[1].Name | Should -BeLike "*PowerShell $($PSVersionTable.PSVersion.Major).$($PSVersionTable.PSVersion.Minor)"
            $script:wrapper[1].Path | Should -BeExactly $script:ownPowerShell
        }

        It 'passes each the arguments that the README table of hosts gives for it' {
            ($script:wrapper[0].Argument -join ' ') | Should -BeExactly '-ExecutionPolicy Bypass -NoProfile -NoLogo -Command'
            ($script:wrapper[1].Argument -join ' ') | Should -BeExactly '-nop -nol -c'
        }

        It 'names the host of each as the README table does, and that row carries the same arguments' {
            $line = [System.IO.File]::ReadAllLines((Join-Path $script:repoRoot 'com.github.copilot/hooks/README.md'))

            foreach ($item in $script:wrapper) {
                $row = @($line | Where-Object -FilterScript { $_.StartsWith("| $($item.Host) |", [System.StringComparison]::Ordinal) })

                $row | Should -HaveCount 1 -Because "the table of hosts has one row for $($item.Host)"
                $row[0] | Should -Match ([regex]::Escape(($item.Argument -join ' ') + ' <'))
            }
        }
    }

    Context 'running a line under a wrapper' {
        BeforeAll {
            $script:wrapper = @(Get-HookWrapper)
        }

        It 'returns the exit code the line ends with, under <Label>' -ForEach @(
            @{ Index = 0; Label = 'Windows PowerShell' }
            @{ Index = 1; Label = 'PowerShell 7' }
        ) {
            Invoke-HookPayload -CommandLine "exit ([int]'7')" -Payload '{}' -EnvironmentVariable @{} -Wrapper $script:wrapper[$Index] | Should -Be 7
        }

        It 'hands the payload over on standard input, under <Label>' -ForEach @(
            @{ Index = 0; Label = 'Windows PowerShell' }
            @{ Index = 1; Label = 'PowerShell 7' }
        ) {
            $line = 'if ([Console]::In.ReadToEnd() -eq "payload-text") { exit 9 } else { exit 8 }'

            Invoke-HookPayload -CommandLine $line -Payload 'payload-text' -EnvironmentVariable @{} -Wrapper $script:wrapper[$Index] | Should -Be 9
        }

        It 'gives the line the environment it is passed and not the caller''s, under <Label>' -ForEach @(
            @{ Index = 0; Label = 'Windows PowerShell' }
            @{ Index = 1; Label = 'PowerShell 7' }
        ) {
            $line = 'if ($env:PLUGIN_ROOT -eq "given") { exit 9 } else { exit 8 }'

            $code = Invoke-WithEnvironment -Name 'PLUGIN_ROOT' -Value 'caller' -Action {
                Invoke-HookPayload -CommandLine $line -Payload '{}' -EnvironmentVariable @{ PLUGIN_ROOT = 'given' } -Wrapper $script:wrapper[$Index]
            }

            $code | Should -Be 9
        }

        It 'starts the line in a folder of its own that holds nothing, under <Label>' -ForEach @(
            @{ Index = 0; Label = 'Windows PowerShell' }
            @{ Index = 1; Label = 'PowerShell 7' }
        ) {
            Invoke-HookPayload -CommandLine 'exit (@(Get-ChildItem -Force).Count + 5)' -Payload '{}' -EnvironmentVariable @{} -Wrapper $script:wrapper[$Index] | Should -Be 5
        }

        # Review of 2026-10-16, U-07: the instruction reached the cmd.exe spawn and was tested only there, and a change that kept it
        # from the wrapper spawns passed every test of the file.
        It 'tells the line not to look for a command in the working directory, under <Label>' -ForEach @(
            @{ Index = 0; Label = 'Windows PowerShell' }
            @{ Index = 1; Label = 'PowerShell 7' }
        ) {
            Invoke-HookPayload -CommandLine 'if ($env:NoDefaultCurrentDirectoryInExePath -eq "1") { exit 5 } else { exit 6 }' -Payload '{}' -EnvironmentVariable @{} -Wrapper $script:wrapper[$Index] | Should -Be 5
        }

        It 'keeps that instruction when the caller tries to remove it, under <Label>' -ForEach @(
            @{ Index = 0; Label = 'Windows PowerShell' }
            @{ Index = 1; Label = 'PowerShell 7' }
        ) {
            Invoke-HookPayload -CommandLine 'if ($env:NoDefaultCurrentDirectoryInExePath -eq "1") { exit 5 } else { exit 6 }' -Payload '{}' -EnvironmentVariable @{ NoDefaultCurrentDirectoryInExePath = $null } -Wrapper $script:wrapper[$Index] | Should -Be 5
        }

        It 'stops a line that does not finish within the time it is given, under <Label>' -ForEach @(
            @{ Index = 0; Label = 'Windows PowerShell' }
            @{ Index = 1; Label = 'PowerShell 7' }
        ) {
            { Invoke-HookPayload -CommandLine 'Start-Sleep -Seconds 30' -Payload '{}' -EnvironmentVariable @{} -TimeoutSecond 1 -Wrapper $script:wrapper[$Index] } |
                Should -Throw '*did not finish within 1 seconds*'
        }

        It 'throws when the wrapper cannot be started' {
            $missing = [pscustomobject]@{ Name = 'missing'; Host = 'none'; Path = (Join-Path $TestDrive 'no-such-folder\powershell.exe'); Argument = @('-Command') }

            { Invoke-HookPayload -CommandLine 'exit 0' -Payload '{}' -EnvironmentVariable @{} -Wrapper $missing } | Should -Throw
        }

        It 'still runs the line through cmd.exe when no wrapper is given' {
            Invoke-HookPayload -CommandLine 'exit /b 6' -Payload '{}' -EnvironmentVariable @{} | Should -Be 6
        }
    }

    # A wrapper is a program this check runs as the identity under test, and one that identity can replace could answer
    # 0, 2, 2 for the guard: it gets the test the pinned interpreter gets.
    Context 'a wrapper that this identity must not be able to replace' {
        BeforeAll {
            $script:aWrapper = [pscustomobject]@{
                Name = 'Windows PowerShell 5.1'
                Host = 'VS Code Local harness'
                Path = 'C:\containment\wrapper\powershell.exe'
                Argument = @('-Command')
            }
        }

        It 'reports nothing when the wrapper exists and is closed to this identity' {
            Get-HookWrapperProblem -Wrapper $script:aWrapper | Should -BeNullOrEmpty
        }

        It 'asks the access check about the wrapper itself, with the writable roots it is given' {
            $null = Get-HookWrapperProblem -Wrapper $script:aWrapper -WritableRoot @('C:\work')

            Should -Invoke Test-PathProtection -Times 1 -Exactly -ParameterFilter {
                $Path -eq $script:aWrapper.Path -and $WritableRoot -contains 'C:\work'
            }
        }

        It 'fails a wrapper this identity can replace, and names it and the reason' {
            Mock -CommandName Test-PathProtection -MockWith {
                [pscustomobject]@{ Path = $Path; Closed = $false; Absent = $false; Violation = @("${Path}: this identity holds the right to delete it"); Unmeasured = @() }
            }

            $problem = Get-HookWrapperProblem -Wrapper $script:aWrapper

            $problem.Status | Should -Be 'Fail'
            $problem.Evidence | Should -Match 'can be replaced'
            $problem.Evidence | Should -Match 'Windows PowerShell 5\.1'
            $problem.Evidence | Should -Match ([regex]::Escape($script:aWrapper.Path))
            $problem.Evidence | Should -Match 'this identity holds the right to delete it'
            $problem.Evidence | Should -Match 'not run'
        }

        It 'reports a wrapper that does not exist as unavailable, because nothing could be measured under it' {
            Mock -CommandName Test-PathProtection -MockWith {
                [pscustomobject]@{ Path = $Path; Closed = $true; Absent = $true; Violation = @(); Unmeasured = @() }
            }

            $problem = Get-HookWrapperProblem -Wrapper $script:aWrapper

            $problem.Status | Should -Be 'Unavailable'
            $problem.Evidence | Should -Match 'does not exist'
            $problem.Evidence | Should -Match 'Windows PowerShell 5\.1'
        }

        It 'reports a wrapper whose protection could not be measured as unavailable' {
            Mock -CommandName Test-PathProtection -MockWith {
                [pscustomobject]@{ Path = $Path; Closed = $false; Absent = $false; Violation = @(); Unmeasured = @("${Path}: a right could not be measured") }
            }

            $problem = Get-HookWrapperProblem -Wrapper $script:aWrapper

            $problem.Status | Should -Be 'Unavailable'
            $problem.Evidence | Should -Match 'not be shown to be closed'
            $problem.Evidence | Should -Match 'a right could not be measured'
        }

        It 'reports a wrapper that cannot be measured at all as unavailable, and cuts the reason to printable ASCII' {
            Mock -CommandName Test-PathProtection -MockWith { throw "access check unavailable $([char]0x00E9)" }

            $problem = Get-HookWrapperProblem -Wrapper $script:aWrapper

            $problem.Status | Should -Be 'Unavailable'
            $problem.Evidence | Should -Match 'access check unavailable \?'
            $problem.Evidence | Should -Not -Match ([string][char]0x00E9)
        }

        # Review of 2026-10-16, U-05: the closure test comes before every spawn, so nothing had run when a wrapper was refused.
        # "Not run under it" read as if the line had run elsewhere, and a reader could take the cmd.exe measurement for passed.
        It 'says that the hook command was not run, and not that it was not run under the wrapper, for a wrapper that <Case>' -ForEach @(
            @{ Case = 'can be replaced'; Absent = $false; Violation = @('x: this identity holds DELETE'); Unmeasured = @() }
            @{ Case = 'does not exist'; Absent = $true; Violation = @(); Unmeasured = @() }
            @{ Case = 'could not be shown to be closed'; Absent = $false; Violation = @(); Unmeasured = @('x: a right could not be measured') }
        ) {
            $script:protectionAbsent = $Absent
            $script:protectionViolation = $Violation
            $script:protectionUnmeasured = $Unmeasured
            Mock -CommandName Test-PathProtection -MockWith {
                [pscustomobject]@{ Path = $Path; Closed = $false; Absent = $script:protectionAbsent; Violation = $script:protectionViolation; Unmeasured = $script:protectionUnmeasured }
            }

            $problem = Get-HookWrapperProblem -Wrapper $script:aWrapper

            $problem.Evidence | Should -Match 'so the hook command was not run'
            $problem.Evidence | Should -Not -Match 'not run under it'
        }

        It 'says that the hook command was not run when the wrapper cannot be measured at all' {
            Mock -CommandName Test-PathProtection -MockWith { throw 'access check unavailable' }

            $problem = Get-HookWrapperProblem -Wrapper $script:aWrapper

            $problem.Evidence | Should -Match 'so the hook command was not run'
            $problem.Evidence | Should -Not -Match 'not run under it'
        }

        It 'relays the path of the wrapper as printable ASCII' {
            Mock -CommandName Test-PathProtection -MockWith {
                [pscustomobject]@{ Path = $Path; Closed = $false; Absent = $false; Violation = @('replaceable'); Unmeasured = @() }
            }
            $odd = [pscustomobject]@{ Name = 'Windows PowerShell 5.1'; Host = 'VS Code Local harness'; Path = "C:\containment\w$([char]0x00E9)\powershell.exe"; Argument = @('-Command') }

            $problem = Get-HookWrapperProblem -Wrapper $odd

            $problem.Evidence | Should -Match 'w\?\\powershell\.exe'
            $problem.Evidence | Should -Not -Match ([string][char]0x00E9)
        }

        # Review of 2026-10-16, U-01: the second wrapper is the program that runs the verifier, so its path is not held to printable
        # ASCII by the shape rule that holds the interpreter's, and the access check puts that path into every reason it gives.
        # Four tag characters spell a word that a reader cannot see; an accent is the plain case. Delta check, V-04: there are six reasons
        # of 3,000 characters each, because the cap holds what they make together, and a cap on each reason, or the default of 200, has to fail.
        It 'cuts the reason of <Kind> to printable ASCII and to a length that cannot fill the report' -ForEach @(
            @{ Kind = 'a wrapper that can be replaced'; Replaceable = $true; Status = 'Fail' }
            @{ Kind = 'a wrapper whose protection could not be measured'; Replaceable = $false; Status = 'Unavailable' }
        ) {
            $hidden = -join @(0xE0050, 0xE0041, 0xE0053, 0xE0053 | ForEach-Object -Process { [char]::ConvertFromUtf32($_) })
            $oddPath = "C:\containment\w$([char]0x00E9)$hidden\powershell.exe"
            $script:reason = @("${oddPath}: this identity holds the right to delete it") + @(1..5 | ForEach-Object -Process { 'x' * 3000 })
            $script:asViolation = $Replaceable
            Mock -CommandName Test-PathProtection -MockWith {
                [pscustomobject]@{
                    Path = $Path
                    Closed = $false
                    Absent = $false
                    Violation = $(if ($script:asViolation) { $script:reason } else { @() })
                    Unmeasured = $(if ($script:asViolation) { @() } else { $script:reason })
                }
            }
            $odd = [pscustomobject]@{ Name = 'Windows PowerShell 5.1'; Host = 'VS Code Local harness'; Path = $oddPath; Argument = @('-Command') }

            $problem = Get-HookWrapperProblem -Wrapper $odd

            $problem.Status | Should -Be $Status
            $problem.Evidence | Should -Match 'the right to delete it'
            $problem.Evidence | Should -Match 'w\?{5}\\powershell\.exe' -Because 'the accent and each of the four tag characters, which are one rune each, become one question mark each'
            @($problem.Evidence.ToCharArray() | Where-Object -FilterScript { [int]$_ -lt 0x20 -or [int]$_ -gt 0x7E }).Count | Should -Be 0
            $problem.Evidence.Length | Should -BeGreaterThan 1050 -Because 'the six reasons are cut together at 1,000 characters, and not at the default of 200'
            $problem.Evidence.Length | Should -BeLessThan 1500 -Because 'and not each at 1,000'
            $problem.Evidence | Should -Match '\.\.\.$'
        }
    }

    Context 'measuring the line under one wrapper' {
        BeforeAll {
            $script:aWrapper = [pscustomobject]@{
                Name = 'Windows PowerShell 5.1'
                Host = 'VS Code Local harness'
                Path = 'C:\containment\wrapper\powershell.exe'
                Argument = @('-ExecutionPolicy', 'Bypass', '-Command')
            }
            $script:case = [ordered]@{
                safe = @{ expected = 0; payload = 'safe-payload' }
                push = @{ expected = 2; payload = 'push-payload' }
                issue = @{ expected = 2; payload = 'issue-payload' }
            }
            $script:given = @{ PLUGIN_ROOT = 'C:\root'; HOME = 'C:\empty'; USERPROFILE = 'C:\empty' }
            $script:answer = @{ 'safe-payload' = 0; 'push-payload' = 2; 'issue-payload' = 2 }

            function script:Measure-Line {
                param(
                    [Parameter()]
                    [int]$TimeoutSecond = 20
                )

                Measure-HookWrapper -Wrapper $script:aWrapper -CommandLine 'the pinned line' -Case $script:case -EnvironmentVariable $script:given -TimeoutSecond $TimeoutSecond
            }
        }

        BeforeEach {
            $script:order = [System.Collections.Generic.List[string]]::new()
            Mock -CommandName Invoke-HookPayload -MockWith {
                $script:order.Add($Payload)
                [int]$script:answer[$Payload]
            }
        }

        It 'passes when every payload gets the code the guard has to give, and names the wrapper and the codes' {
            $result = Measure-Line

            $result.Status | Should -Be 'Pass' -Because $result.Evidence
            $result.Name | Should -Be 'Windows PowerShell 5.1'
            $result.Evidence | Should -Match 'safe=0 push=2 issue=2'
            $result.Evidence | Should -Match 'Windows PowerShell 5\.1'
            $result.Evidence | Should -Match 'VS Code Local harness'
            $result.Evidence | Should -Match ([regex]::Escape('C:\containment\wrapper\powershell.exe -ExecutionPolicy Bypass -Command'))
        }

        It 'runs the safe, the push and then the issue payload, one spawn each, with the wrapper, the line and the environment it was given' {
            $null = Measure-Line

            $script:order | Should -Be @('safe-payload', 'push-payload', 'issue-payload')
            Should -Invoke Invoke-HookPayload -Times 3 -Exactly -ParameterFilter {
                $Wrapper.Path -eq $script:aWrapper.Path -and $CommandLine -ceq 'the pinned line' -and
                $EnvironmentVariable.PLUGIN_ROOT -eq 'C:\root' -and $EnvironmentVariable.HOME -eq 'C:\empty'
            }
        }

        It 'fails a payload that gets <Measured> and still measures the others' -ForEach @(
            @{ Safe = 1; Push = 2; Issue = 2; Measured = 'safe=1 push=2 issue=2' }
            @{ Safe = 2; Push = 2; Issue = 2; Measured = 'safe=2 push=2 issue=2' }
            @{ Safe = 0; Push = 0; Issue = 2; Measured = 'safe=0 push=0 issue=2' }
            @{ Safe = 0; Push = 1; Issue = 2; Measured = 'safe=0 push=1 issue=2' }
            @{ Safe = 0; Push = 2; Issue = 0; Measured = 'safe=0 push=2 issue=0' }
            @{ Safe = 0; Push = 2; Issue = 1; Measured = 'safe=0 push=2 issue=1' }
            @{ Safe = 1; Push = 1; Issue = 1; Measured = 'safe=1 push=1 issue=1' }
        ) {
            $script:answer = @{ 'safe-payload' = $Safe; 'push-payload' = $Push; 'issue-payload' = $Issue }

            $result = Measure-Line

            $result.Status | Should -Be 'Fail' -Because $result.Evidence
            $result.Evidence | Should -Match $Measured
            Should -Invoke Invoke-HookPayload -Times 3 -Exactly
        }

        It 'reports a spawn that throws as unavailable, with the reason, and runs nothing after it' {
            Mock -CommandName Invoke-HookPayload -ParameterFilter { $Payload -eq 'push-payload' } -MockWith { throw 'the wrapper did not start' }

            $result = Measure-Line

            $result.Status | Should -Be 'Unavailable'
            $result.Evidence | Should -Match 'could not run the push payload'
            $result.Evidence | Should -Match 'the wrapper did not start'
            $result.Evidence | Should -Match 'Windows PowerShell 5\.1'
            Should -Invoke Invoke-HookPayload -Times 2 -Exactly
        }

        It 'cuts the reason of a spawn that throws to printable ASCII' {
            Mock -CommandName Invoke-HookPayload -MockWith { throw "no start $([char]0x00E9)" }

            $result = Measure-Line

            $result.Evidence | Should -Match 'no start \?'
            $result.Evidence | Should -Not -Match ([string][char]0x00E9)
        }

        It 'relays the path of the wrapper as printable ASCII' {
            $odd = [pscustomobject]@{ Name = 'Windows PowerShell 5.1'; Host = 'VS Code Local harness'; Path = "C:\containment\w$([char]0x00E9)\powershell.exe"; Argument = @('-Command') }

            $result = Measure-HookWrapper -Wrapper $odd -CommandLine 'the pinned line' -Case $script:case -EnvironmentVariable $script:given -TimeoutSecond 20

            $result.Evidence | Should -Match 'w\?\\powershell\.exe'
            $result.Evidence | Should -Not -Match ([string][char]0x00E9)
        }

        It 'fails a payload that takes as long as the timeout the hook declares, and runs nothing after it' {
            Mock -CommandName Invoke-HookPayload -MockWith { Start-Sleep -Seconds 2; 0 }

            $result = Measure-Line -TimeoutSecond 1

            $result.Status | Should -Be 'Fail'
            $result.Evidence | Should -Match 'timeout of 1 seconds'
            $result.Evidence | Should -Match 'safe payload'
            $result.Evidence | Should -Match 'Windows PowerShell 5\.1'
            Should -Invoke Invoke-HookPayload -Times 1 -Exactly
        }
    }

    # Review pass 3 part C, S-23 and S-24, measured on 2026-10-16: the cmd.exe probe says 0, 2, 2 for a quoted program path
    # and both wrappers say 1, 1, 1, which is a parse error. By the README, VS Code treats exit 1 as a warning and the Copilot SDK host
    # denies the call on it.
    Context 'a line that has to pass under the wrappers of the documented hosts, run for real' {
        It 'fails a quoted program path, which both wrappers fail to parse, and says why without relaying what they wrote' {
            $shipped = [System.IO.File]::ReadAllText($script:realConfig) | ConvertFrom-Json
            $text = [string]@($shipped.hooks.PreToolUse)[0].windows
            $tree = New-PluginTree -Name 'quoted-program' -Command ('"' + $script:systemPowerShell + '"' + $text.Substring('powershell'.Length))

            $result = Test-HookContract -HookConfigPath $tree.Config -HookConfigSha256 $tree.ConfigDigest `
                -HookScriptPath $tree.Script -HookScriptSha256 $tree.ScriptDigest

            $result.status | Should -Be 'Fail' -Because $result.evidence
            $result.evidence | Should -Match 'measured safe=0 push=2 issue=2'
            [regex]::Matches($result.evidence, 'safe=1 push=1 issue=1').Count | Should -Be 2 -Because 'both wrappers fail the line'
            $result.evidence | Should -Match 'program path is quoted'
            $result.evidence | Should -Match 'ampersand'
            $result.evidence | Should -Not -Match 'Unexpected token|ParserError|At line'
            # Review of 2026-10-16, U-03: VS Code treats exit 1 as a warning, and the Copilot SDK host denies the call on it.
            $result.evidence | Should -Match 'warning in VS Code'
            $result.evidence | Should -Match 'SDK host denies'
            $result.evidence | Should -Not -Match 'does not block'
            # Delta check of the same review, V-02: that is what the README says of the hosts, and no host ran the line, so the note
            # says what a push would do and not what one did.
            $result.evidence | Should -Match 'hooks README states'
            $result.evidence | Should -Match 'would go ahead'
            $result.evidence | Should -Not -Match 'goes ahead|went ahead'
        }

        It 'passes the line with the program path unquoted' {
            $result = Test-HookContract -HookConfigPath $script:plugin.Config -HookConfigSha256 $script:plugin.ConfigDigest `
                -HookScriptPath $script:plugin.Script -HookScriptSha256 $script:plugin.ScriptDigest

            $result.status | Should -Be 'Pass' -Because $result.evidence
        }
    }

    Context 'the verdict over the wrappers of the documented hosts' {
        BeforeEach {
            $script:seen = [System.Collections.Generic.List[object]]::new()
            $script:statusByHost = @{ 'VS Code Local harness' = 'Pass'; 'Copilot SDK host' = 'Pass' }
            Mock -CommandName Measure-HookWrapper -MockWith {
                $script:seen.Add([pscustomobject]@{ Wrapper = $Wrapper; Line = $CommandLine; Case = $Case; Environment = $EnvironmentVariable; Timeout = $TimeoutSecond })

                [pscustomobject]@{ Name = $Wrapper.Name; Status = $script:statusByHost[$Wrapper.Host]; Evidence = "fragment for $($Wrapper.Host) is $($script:statusByHost[$Wrapper.Host])" }
            }
        }

        It 'measures both wrappers in the order of the table, with the pinned line, the three cases, the hook''s own timeout and the environment of the probe' {
            $result = Test-HookContract -HookConfigPath $script:plugin.Config -HookConfigSha256 $script:plugin.ConfigDigest `
                -HookScriptPath $script:plugin.Script -HookScriptSha256 $script:plugin.ScriptDigest

            $result.status | Should -Be 'Pass' -Because $result.evidence
            $script:seen | Should -HaveCount 2
            $script:seen[0].Wrapper.Host | Should -Be 'VS Code Local harness'
            $script:seen[1].Wrapper.Host | Should -Be 'Copilot SDK host'

            $pinned = [string]@(([System.IO.File]::ReadAllText($script:plugin.Config) | ConvertFrom-Json).hooks.PreToolUse)[0].windows

            foreach ($item in $script:seen) {
                $item.Line | Should -BeExactly $pinned
                @($item.Case.Keys) | Should -Be @('safe', 'push', 'issue')
                @($item.Case.Values.expected) | Should -Be @(0, 2, 2)
                $item.Timeout | Should -Be 20
                [System.IO.Path]::GetFullPath($item.Environment['PLUGIN_ROOT']) | Should -Be ([System.IO.Path]::GetFullPath($script:plugin.Root))
                $item.Environment['HOME'] | Should -Be $item.Environment['USERPROFILE']
                $item.Environment['HOME'] | Should -Not -Be $env:USERPROFILE
            }

            $result.evidence.IndexOf('fragment for VS Code Local harness') | Should -BeLessThan $result.evidence.IndexOf('fragment for Copilot SDK host')
        }

        It 'gives <Expected> when the first wrapper is <First> and the second is <Second>, and measures both' -ForEach @(
            @{ First = 'Fail'; Second = 'Pass'; Expected = 'Fail' }
            @{ First = 'Pass'; Second = 'Fail'; Expected = 'Fail' }
            @{ First = 'Unavailable'; Second = 'Pass'; Expected = 'Unavailable' }
            @{ First = 'Pass'; Second = 'Unavailable'; Expected = 'Unavailable' }
            @{ First = 'Fail'; Second = 'Unavailable'; Expected = 'Fail' }
            @{ First = 'Unavailable'; Second = 'Fail'; Expected = 'Fail' }
        ) {
            $script:statusByHost = @{ 'VS Code Local harness' = $First; 'Copilot SDK host' = $Second }

            $result = Test-HookContract -HookConfigPath $script:plugin.Config -HookConfigSha256 $script:plugin.ConfigDigest `
                -HookScriptPath $script:plugin.Script -HookScriptSha256 $script:plugin.ScriptDigest

            $result.status | Should -Be $Expected -Because $result.evidence
            Should -Invoke Measure-HookWrapper -Times 2 -Exactly
            $result.evidence | Should -Match "fragment for VS Code Local harness is $First"
            $result.evidence | Should -Match "fragment for Copilot SDK host is $Second"
        }

        # Review of 2026-10-16, U-06: nothing held the number of wrappers, so a list that came back short made the check pass on
        # the cmd.exe measurement alone, with an evidence sentence that still spoke of "each wrapper". The README table has two rows.
        It 'is unavailable, and runs nothing, when <Count> wrappers are listed and not the two of the documented hosts' -ForEach @(
            @{ Count = 0 }
            @{ Count = 1 }
            @{ Count = 3 }
        ) {
            $real = @(Get-HookWrapper)
            $script:listed = switch ($Count) {
                0 { @() }
                1 { @($real[0]) }
                default { @($real[0], $real[1], $real[1]) }
            }
            Mock -CommandName Get-HookWrapper -MockWith { $script:listed }
            Mock -CommandName Invoke-HookPayload -MockWith { 0 }

            $result = Test-HookContract -HookConfigPath $script:plugin.Config -HookConfigSha256 $script:plugin.ConfigDigest `
                -HookScriptPath $script:plugin.Script -HookScriptSha256 $script:plugin.ScriptDigest

            $result.status | Should -Be 'Unavailable' -Because $result.evidence
            $result.evidence | Should -Match 'could not be listed'
            $result.evidence | Should -Match "$Count found"
            Should -Invoke Invoke-HookPayload -Times 0 -Exactly
            Should -Invoke Measure-HookWrapper -Times 0 -Exactly
        }

        It 'does not run the line under a wrapper when it already failed under cmd.exe, and says so' {
            $broken = New-PluginTree -Name 'wrapper-after-shell' -Body 'exit 0'

            $result = Test-HookContract -HookConfigPath $broken.Config -HookConfigSha256 $broken.ConfigDigest `
                -HookScriptPath $broken.Script -HookScriptSha256 $broken.ScriptDigest

            $result.status | Should -Be 'Fail'
            $result.evidence | Should -Match 'safe=0 push=0 issue=0'
            $result.evidence | Should -Match 'not run under the PowerShell wrappers'
            Should -Invoke Measure-HookWrapper -Times 0 -Exactly
        }

        It 'says nothing about a quoted program path when both wrappers passed the line, because it reports what they measured and not what a rule predicts' {
            $shipped = [System.IO.File]::ReadAllText($script:realConfig) | ConvertFrom-Json
            $text = [string]@($shipped.hooks.PreToolUse)[0].windows
            $tree = New-PluginTree -Name 'wrappers-pass-the-line' -Command ('"' + $script:systemPowerShell + '"' + $text.Substring('powershell'.Length))

            $result = Test-HookContract -HookConfigPath $tree.Config -HookConfigSha256 $tree.ConfigDigest `
                -HookScriptPath $tree.Script -HookScriptSha256 $tree.ScriptDigest

            $result.status | Should -Be 'Pass' -Because $result.evidence
            $result.evidence | Should -Not -Match 'program path is quoted'
        }

        It 'runs nothing when a wrapper can be replaced by this identity' {
            Mock -CommandName Invoke-HookPayload -MockWith { 0 }
            $second = (Get-HookWrapper)[1].Path
            Mock -CommandName Test-PathProtection -ParameterFilter { $Path -eq $second } -MockWith {
                [pscustomobject]@{ Path = $Path; Closed = $false; Absent = $false; Violation = @("${Path}: this identity holds the right to delete it"); Unmeasured = @() }
            }

            $result = Test-HookContract -HookConfigPath $script:plugin.Config -HookConfigSha256 $script:plugin.ConfigDigest `
                -HookScriptPath $script:plugin.Script -HookScriptSha256 $script:plugin.ScriptDigest

            $result.status | Should -Be 'Fail'
            $result.evidence | Should -Match 'can be replaced'
            $result.evidence | Should -Match ([regex]::Escape($second))
            Should -Invoke Invoke-HookPayload -Times 0 -Exactly
            Should -Invoke Measure-HookWrapper -Times 0 -Exactly
        }

        It 'returns the problem of a wrapper as the verdict, with its status and its evidence, and runs nothing, for the <HostName> wrapper as <Status>' -ForEach @(
            @{ HostName = 'VS Code Local harness'; Status = 'Fail' }
            @{ HostName = 'VS Code Local harness'; Status = 'Unavailable' }
            @{ HostName = 'Copilot SDK host'; Status = 'Fail' }
            @{ HostName = 'Copilot SDK host'; Status = 'Unavailable' }
        ) {
            Mock -CommandName Invoke-HookPayload -MockWith { 0 }
            $script:problem = [pscustomobject]@{ Status = $Status; Evidence = "the problem of the $HostName wrapper" }
            $script:problemHost = $HostName
            Mock -CommandName Get-HookWrapperProblem -MockWith { if ($Wrapper.Host -eq $script:problemHost) { $script:problem } }

            $result = Test-HookContract -HookConfigPath $script:plugin.Config -HookConfigSha256 $script:plugin.ConfigDigest `
                -HookScriptPath $script:plugin.Script -HookScriptSha256 $script:plugin.ScriptDigest

            $result.status | Should -Be $Status
            $result.evidence | Should -Be "the problem of the $HostName wrapper"
            Should -Invoke Invoke-HookPayload -Times 0 -Exactly
            Should -Invoke Measure-HookWrapper -Times 0 -Exactly
        }
    }

    Context 'the interpreter the command starts' {
        BeforeEach {
            $script:marker = Join-Path $TestDrive "interpreter-marker-$([guid]::NewGuid().ToString('N')).txt"
            # A command that leaves a file behind if it is ever run, so that "runs nothing" can be read off the disk.
            $script:markerRun = "`"$script:systemPowerShell`" -NoProfile -NonInteractive -Command `"Set-Content -LiteralPath '$script:marker' -Value ran`""
        }

        # Review pass 3 part D, S-25, reproduced end to end: PowerShell reads '-x:' as a parameter that binds to the next
        # word or, as the last word, fails to parse, so both PowerShell wrappers exit 1 for a push, which VS Code treats as
        # a warning and the Copilot SDK host as a denial, and the cmd.exe probe still reports 0, 2, 2.
        It 'fails the shipped command with a dash word that ends in a colon before its closing statement' {
            $shipped = [System.IO.File]::ReadAllText($script:realConfig) | ConvertFrom-Json
            $text = [string]@($shipped.hooks.PreToolUse)[0].windows
            $contained = '"' + $script:systemPowerShell + '"' + $text.Substring('powershell'.Length)
            $dashed = $contained.Replace('; exit (@(', ' -x: ; exit (@(')
            $dashed | Should -Not -Be $contained -Because 'the edit has to change the command for this test to mean anything'
            $tree = New-PluginTree -Name 'dash-word' -Command $dashed

            $result = Test-HookContract -HookConfigPath $tree.Config -HookConfigSha256 $tree.ConfigDigest `
                -HookScriptPath $tree.Script -HookScriptSha256 $tree.ScriptDigest

            $result.status | Should -Be 'Fail'
            $result.evidence | Should -Match 'shape'
        }

        # Review pass 3 part C, S-21, reproduced end to end: PowerShell reads everything after a hash as a comment, so
        # a host that wraps the line in it never runs the statement that turns the guard's exit code into the hook's,
        # and a push exits 1, which VS Code treats as a warning and the Copilot SDK host as a denial. The cmd.exe probe
        # passes the same text through and reports 0, 2, 2.
        It 'fails the shipped command with a comment marker before its closing statement, which the cmd probe passes' {
            $shipped = [System.IO.File]::ReadAllText($script:realConfig) | ConvertFrom-Json
            $text = [string]@($shipped.hooks.PreToolUse)[0].windows
            $contained = '"' + $script:systemPowerShell + '"' + $text.Substring('powershell'.Length)
            $commented = $contained.Replace('; exit (@(', ' # ; exit (@(')
            $commented | Should -Not -Be $contained -Because 'the edit has to change the command for this test to mean anything'
            $tree = New-PluginTree -Name 'comment-tail' -Command $commented

            $result = Test-HookContract -HookConfigPath $tree.Config -HookConfigSha256 $tree.ConfigDigest `
                -HookScriptPath $tree.Script -HookScriptSha256 $tree.ScriptDigest

            $result.status | Should -Be 'Fail'
            $result.evidence | Should -Match 'shape'
        }

        It 'fails a command that names powershell without a path, and runs nothing' {
            $tree = New-PluginTree -Name 'bare-name' -Command "powershell -NoProfile -NonInteractive -Command `"echo ran> '$script:marker'`""

            $result = Test-HookContract -HookConfigPath $tree.Config -HookConfigSha256 $tree.ConfigDigest `
                -HookScriptPath $tree.Script -HookScriptSha256 $tree.ScriptDigest

            $result.status | Should -Be 'Fail'
            $result.evidence | Should -Match 'bare name'
            $result.evidence | Should -Match 'not run'
            Should -Invoke Test-PathProtection -Times 0 -Exactly
            Test-Path -LiteralPath $script:marker | Should -BeFalse
        }

        It 'fails the shipped hooks.json, which registers hooks besides the guard and names no interpreter by path' {
            $result = Test-HookContract -HookConfigPath $script:realConfig -HookConfigSha256 $script:realConfigDigest `
                -HookScriptPath $script:realScript -HookScriptSha256 $script:realScriptDigest

            $result.status | Should -Be 'Fail'
            $result.evidence | Should -Match 'besides the guard'
            $result.evidence | Should -Match 'UserPromptSubmit'
            Should -Invoke Test-PathProtection -Times 0 -Exactly
        }

        It 'does not run a program that the working directory of the caller holds under the name the shipped command uses' {
            $callerDirectory = Join-Path $TestDrive 'contract-decoy'
            $null = New-Item -Path $callerDirectory -ItemType Directory -Force
            [System.IO.File]::WriteAllText((Join-Path $callerDirectory 'powershell.cmd'), "@echo off`r`necho ran> `"$script:marker`"`r`nexit /b 7`r`n")
            $script:contractResult = $null

            Invoke-InDirectory -Path $callerDirectory -Action {
                $script:contractResult = Test-HookContract -HookConfigPath $script:realConfig -HookConfigSha256 $script:realConfigDigest `
                    -HookScriptPath $script:realScript -HookScriptSha256 $script:realScriptDigest
            }

            Test-Path -LiteralPath $script:marker | Should -BeFalse -Because 'a program planted in the working directory must not run before any verdict'
            $script:contractResult.status | Should -Not -Be 'Pass'
        }

        It 'fails a command that names its interpreter by a relative path, and runs nothing' {
            $tree = New-PluginTree -Name 'relative-interpreter' -Command ".\cmd.exe /c echo ran> `"$script:marker`""

            $result = Test-HookContract -HookConfigPath $tree.Config -HookConfigSha256 $tree.ConfigDigest `
                -HookScriptPath $tree.Script -HookScriptSha256 $tree.ScriptDigest

            $result.status | Should -Be 'Fail'
            $result.evidence | Should -Match 'relative'
            Test-Path -LiteralPath $script:marker | Should -BeFalse
        }

        It 'fails an interpreter this identity can replace, and runs nothing' {
            Mock -CommandName Test-PathProtection -MockWith {
                [pscustomobject]@{ Path = $Path; Closed = $false; Absent = $false; Violation = @("${Path}: this identity holds the right to delete it"); Unmeasured = @() }
            }
            $tree = New-PluginTree -Name 'replaceable-interpreter' -Command $script:markerRun

            $result = Test-HookContract -HookConfigPath $tree.Config -HookConfigSha256 $tree.ConfigDigest `
                -HookScriptPath $tree.Script -HookScriptSha256 $tree.ScriptDigest

            $result.status | Should -Be 'Fail'
            $result.evidence | Should -Match 'can be replaced'
            $result.evidence | Should -Match ([regex]::Escape($script:systemPowerShell))
            Test-Path -LiteralPath $script:marker | Should -BeFalse
        }

        It 'reports an interpreter whose protection could not be measured as unmeasured, and runs nothing' {
            Mock -CommandName Test-PathProtection -MockWith {
                [pscustomobject]@{ Path = $Path; Closed = $false; Absent = $false; Violation = @(); Unmeasured = @("${Path}: a right could not be measured") }
            }
            $tree = New-PluginTree -Name 'unmeasured-interpreter' -Command $script:markerRun

            $result = Test-HookContract -HookConfigPath $tree.Config -HookConfigSha256 $tree.ConfigDigest `
                -HookScriptPath $tree.Script -HookScriptSha256 $tree.ScriptDigest

            $result.status | Should -Be 'Unavailable'
            $result.evidence | Should -Match 'not be shown to be closed'
            Test-Path -LiteralPath $script:marker | Should -BeFalse
        }

        It 'reports an interpreter that cannot be measured at all as unmeasured, and runs nothing' {
            Mock -CommandName Test-PathProtection -MockWith { throw 'access check unavailable' }
            $tree = New-PluginTree -Name 'throwing-interpreter' -Command $script:markerRun

            $result = Test-HookContract -HookConfigPath $tree.Config -HookConfigSha256 $tree.ConfigDigest `
                -HookScriptPath $tree.Script -HookScriptSha256 $tree.ScriptDigest

            $result.status | Should -Be 'Unavailable'
            $result.evidence | Should -Match 'access check unavailable'
            Test-Path -LiteralPath $script:marker | Should -BeFalse
        }

        It 'fails an interpreter that does not exist, and runs nothing' {
            Mock -CommandName Test-PathProtection -MockWith {
                [pscustomobject]@{ Path = $Path; Closed = $true; Absent = $true; Violation = @(); Unmeasured = @() }
            }
            $tree = New-PluginTree -Name 'absent-interpreter' -Command $script:markerRun

            $result = Test-HookContract -HookConfigPath $tree.Config -HookConfigSha256 $tree.ConfigDigest `
                -HookScriptPath $tree.Script -HookScriptSha256 $tree.ScriptDigest

            $result.status | Should -Be 'Fail'
            $result.evidence | Should -Match 'does not exist'
            Test-Path -LiteralPath $script:marker | Should -BeFalse
        }

        It 'measures the interpreter and each wrapper against the writable roots it is given' {
            $root = Join-Path $TestDrive 'a-writable-root'
            $ownPowerShell = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName

            $null = Test-HookContract -HookConfigPath $script:plugin.Config -HookConfigSha256 $script:plugin.ConfigDigest `
                -HookScriptPath $script:plugin.Script -HookScriptSha256 $script:plugin.ScriptDigest -WritableRoot @($root)

            # Windows PowerShell in the system folder is the pinned interpreter and the first wrapper, so it is asked about twice.
            Should -Invoke Test-PathProtection -Times 2 -Exactly -ParameterFilter {
                $Path -eq [System.IO.Path]::GetFullPath($script:systemPowerShell) -and $WritableRoot -contains $root
            }
            Should -Invoke Test-PathProtection -Times 1 -Exactly -ParameterFilter {
                $Path -eq $ownPowerShell -and $WritableRoot -contains $root
            }
        }
    }

    Context 'when the caller has a PLUGIN_ROOT or ComSpec of its own' {
        It 'measures the pinned script and not a decoy that PLUGIN_ROOT names' {
            $decoyRoot = Join-Path $TestDrive 'decoy-good'
            $null = New-HookTree -Root $decoyRoot -Body 'exit 0'

            $result = Invoke-WithEnvironment -Name 'PLUGIN_ROOT' -Value $decoyRoot -Action {
                Test-HookContract -HookConfigPath $script:plugin.Config -HookConfigSha256 $script:plugin.ConfigDigest `
                    -HookScriptPath $script:plugin.Script -HookScriptSha256 $script:plugin.ScriptDigest
            }

            $result.status | Should -Be 'Pass' -Because $result.evidence
        }

        It 'fails a pinned script that does not block, even when PLUGIN_ROOT names one that does' {
            $broken = New-PluginTree -Name 'pinned-broken' -Body 'exit 0'

            $result = Invoke-WithEnvironment -Name 'PLUGIN_ROOT' -Value $script:repoRoot -Action {
                Test-HookContract -HookConfigPath $broken.Config -HookConfigSha256 $broken.ConfigDigest `
                    -HookScriptPath $broken.Script -HookScriptSha256 $broken.ScriptDigest
            }

            $result.status | Should -Be 'Fail'
            $result.evidence | Should -Match 'safe=0 push=0 issue=0'
        }

        It 'does not take the shell from the ComSpec variable' {
            $result = Invoke-WithEnvironment -Name 'ComSpec' -Value (Join-Path $TestDrive 'absent\cmd.exe') -Action {
                Test-HookContract -HookConfigPath $script:plugin.Config -HookConfigSha256 $script:plugin.ConfigDigest `
                    -HookScriptPath $script:plugin.Script -HookScriptSha256 $script:plugin.ScriptDigest
            }

            $result.status | Should -Be 'Pass' -Because $result.evidence
        }
    }

    Context 'when the command does not resolve its script from PLUGIN_ROOT' {
        It 'fails, because the pinned script cannot be shown to be the one that runs' {
            $tree = New-PluginTree -Name 'fixed-path' -Command ('"' + $script:systemPowerShell + '" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $script:realScript + '"')

            $result = Test-HookContract -HookConfigPath $tree.Config -HookConfigSha256 $tree.ConfigDigest `
                -HookScriptPath $tree.Script -HookScriptSha256 $tree.ScriptDigest

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

    Context 'which hooks.json the host loads' {
        BeforeEach {
            $script:marker = Join-Path $TestDrive "tie-marker-$([guid]::NewGuid().ToString('N')).txt"
            $script:cmdExe = [System.IO.Path]::Combine([System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::System), 'cmd.exe')
        }

        It 'fails a pinned hooks.json that is not the plugin''s own, and runs nothing' {
            $tree = New-PluginTree -Name 'tie-script'
            $elsewhere = New-HookConfig -Path (Join-Path $TestDrive 'elsewhere-hooks.json') -Command "`"$script:cmdExe`" /c echo ran> `"$script:marker`""

            $result = Test-HookContract -HookConfigPath $elsewhere -HookConfigSha256 (Get-FileDigest -Path $elsewhere) `
                -HookScriptPath $tree.Script -HookScriptSha256 $tree.ScriptDigest

            $result.status | Should -Be 'Fail'
            $result.evidence | Should -Match 'plugin''s own'
            Test-Path -LiteralPath $script:marker | Should -BeFalse
            Should -Invoke Test-PathProtection -Times 0 -Exactly
        }

        It 'fails the hooks.json of another plugin tree, even a byte-identical one' {
            $one = New-PluginTree -Name 'tie-one'
            $two = New-PluginTree -Name 'tie-two'

            $result = Test-HookContract -HookConfigPath $two.Config -HookConfigSha256 $two.ConfigDigest `
                -HookScriptPath $one.Script -HookScriptSha256 $one.ScriptDigest

            $result.status | Should -Be 'Fail'
            $result.evidence | Should -Match 'plugin''s own'
        }

        It 'accepts the plugin''s own hooks.json spelled <Spelling>' -ForEach @(
            @{ Spelling = 'in another case'; Convert = { param($path) $path.ToUpperInvariant() } }
            @{ Spelling = 'with forward slashes'; Convert = { param($path) $path.Replace('\', '/') } }
        ) {
            $tree = New-PluginTree -Name 'tie-spelling'
            $spelled = & $Convert $tree.Config

            $result = Test-HookContract -HookConfigPath $spelled -HookConfigSha256 $tree.ConfigDigest `
                -HookScriptPath $tree.Script -HookScriptSha256 $tree.ScriptDigest

            $result.status | Should -Be 'Pass' -Because $result.evidence
        }
    }

    Context 'the entry the command comes from' {
        BeforeEach {
            $script:marker = Join-Path $TestDrive "entry-marker-$([guid]::NewGuid().ToString('N')).txt"
            $script:cmdExe = [System.IO.Path]::Combine([System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::System), 'cmd.exe')
            $script:markerCommand = ('"' + $script:cmdExe + '" /c copy nul "' + $script:marker + '"').Replace('\', '\\').Replace('"', '\"')
        }

        # A hooks.json whose PreToolUse entry is the one given as JSON text, in a plugin tree of its own.
        It 'fails an entry that is <Reason>, and runs nothing' -ForEach @(
            @{ Reason = 'not a command hook'; Match = 'not command'; Entry = '"type":"http","timeout":20,"command":"{0}","windows":"{0}"' }
            @{ Reason = 'a hook with no type'; Match = 'not command'; Entry = '"timeout":20,"command":"{0}","windows":"{0}"' }
            @{ Reason = 'typed with an invisible character after command'; Match = 'not command'; Entry = '"type":"command\u200b","timeout":20,"command":"{0}","windows":"{0}"' }
            @{ Reason = 'narrowed by a matcher'; Match = 'matcher'; Entry = '"type":"command","matcher":"Bash","timeout":20,"command":"{0}","windows":"{0}"' }
            @{ Reason = 'without a timeout'; Match = 'timeout'; Entry = '"type":"command","command":"{0}","windows":"{0}"' }
            @{ Reason = 'given a timeout of zero'; Match = 'timeout'; Entry = '"type":"command","timeout":0,"command":"{0}","windows":"{0}"' }
            @{ Reason = 'given a timeout that is text'; Match = 'timeout'; Entry = '"type":"command","timeout":"20","command":"{0}","windows":"{0}"' }
            @{ Reason = 'given a timeout beyond any a host allows'; Match = 'timeout'; Entry = '"type":"command","timeout":601,"command":"{0}","windows":"{0}"' }
            @{ Reason = 'given a second timeout under the name the SDK host reads'; Match = "'timeoutSec'"; Entry = '"type":"command","timeout":20,"timeoutSec":1,"command":"{0}","windows":"{0}"' }
            @{ Reason = 'given an environment of its own'; Match = "'env'"; Entry = '"type":"command","timeout":20,"env":{{"PLUGIN_ROOT":"x"}},"command":"{0}","windows":"{0}"' }
            @{ Reason = 'given a working directory of its own'; Match = "'cwd'"; Entry = '"type":"command","timeout":20,"cwd":"x","command":"{0}","windows":"{0}"' }
            @{ Reason = 'given a key whose name only looks like timeout'; Match = 'timeout'; Entry = '"type":"command","timeout":20,"timeout\u200b":1,"command":"{0}","windows":"{0}"' }
        ) {
            $tree = New-PluginTree -Name 'entry-shape'
            $json = '{"hooks":{"PreToolUse":[{' + ($Entry -f $script:markerCommand) + '}]}}'
            $digest = Set-PluginConfig -Tree $tree -Json $json

            $result = Test-HookContract -HookConfigPath $tree.Config -HookConfigSha256 $digest `
                -HookScriptPath $tree.Script -HookScriptSha256 $tree.ScriptDigest

            $result.status | Should -Be 'Fail'
            $result.evidence | Should -Match $Match
            Test-Path -LiteralPath $script:marker | Should -BeFalse
        }

        It 'fails an entry whose command keys hold different commands, and runs nothing' {
            $tree = New-PluginTree -Name 'entry-keys'
            $other = ('"' + $script:cmdExe + '" /c exit 0').Replace('\', '\\').Replace('"', '\"')
            $json = '{"hooks":{"PreToolUse":[{"type":"command","timeout":20,"command":"' + $script:markerCommand + '","windows":"' + $script:markerCommand + '","powershell":"' + $other + '"}]}}'
            $digest = Set-PluginConfig -Tree $tree -Json $json

            $result = Test-HookContract -HookConfigPath $tree.Config -HookConfigSha256 $digest `
                -HookScriptPath $tree.Script -HookScriptSha256 $tree.ScriptDigest

            $result.status | Should -Be 'Fail'
            $result.evidence | Should -Match 'differ'
            $result.evidence | Should -Match 'powershell'
            Test-Path -LiteralPath $script:marker | Should -BeFalse
        }

        It 'fails command keys that differ only in case, and runs nothing' {
            # A host on a case-sensitive system runs two commands that differ only in case apart, so they
            # are two commands. This holds today; the test keeps it from being lost when the comparison changes.
            $tree = New-PluginTree -Name 'entry-keys-case'
            $json = '{"hooks":{"PreToolUse":[{"type":"command","timeout":20,"command":"' + $script:markerCommand + '","windows":"' + $script:markerCommand + '","powershell":"' + $script:markerCommand.ToUpperInvariant() + '"}]}}'
            $digest = Set-PluginConfig -Tree $tree -Json $json

            $result = Test-HookContract -HookConfigPath $tree.Config -HookConfigSha256 $digest `
                -HookScriptPath $tree.Script -HookScriptSha256 $tree.ScriptDigest

            $result.status | Should -Be 'Fail'
            $result.evidence | Should -Match 'differ'
            Test-Path -LiteralPath $script:marker | Should -BeFalse
        }

        It 'fails an event whose name only looks like PreToolUse, and runs nothing' {
            # Review pass 2, S-04: -cne compares by culture, so a second event named PreToolUse followed by a
            # zero-width space was counted as the guard's own event and its hooks were never listed.
            $tree = New-PluginTree -Name 'entry-lookalike-event'
            $json = '{"hooks":{"PreToolUse":[{"type":"command","timeout":20,"command":"' + $script:markerCommand + '","windows":"' + $script:markerCommand + '"}],"PreToolUse\u200b":[{"type":"command","command":"x"}]}}'
            $digest = Set-PluginConfig -Tree $tree -Json $json

            $result = Test-HookContract -HookConfigPath $tree.Config -HookConfigSha256 $digest `
                -HookScriptPath $tree.Script -HookScriptSha256 $tree.ScriptDigest

            $result.status | Should -Be 'Fail'
            $result.evidence | Should -Match 'besides the guard'
            Test-Path -LiteralPath $script:marker | Should -BeFalse
        }

        It 'accepts the same command under every key a host reads' {
            $tree = New-PluginTree -Name 'entry-same'
            $command = (Get-Content -LiteralPath $tree.Config -Raw | ConvertFrom-Json).hooks.PreToolUse[0].windows
            $escaped = $command.Replace('\', '\\').Replace('"', '\"')
            $json = '{"hooks":{"PreToolUse":[{"type":"command","timeout":20,"command":"' + $escaped + '","windows":"' + $escaped + '","powershell":"' + $escaped + '"}]}}'
            $digest = Set-PluginConfig -Tree $tree -Json $json

            $result = Test-HookContract -HookConfigPath $tree.Config -HookConfigSha256 $digest `
                -HookScriptPath $tree.Script -HookScriptSha256 $tree.ScriptDigest

            $result.status | Should -Be 'Pass' -Because $result.evidence
        }

        It 'fails a hooks.json that registers a hook besides the guard, and runs nothing' {
            $tree = New-PluginTree -Name 'entry-other-event'
            $json = '{"hooks":{"PreToolUse":[{"type":"command","timeout":20,"command":"' + $script:markerCommand + '","windows":"' + $script:markerCommand + '"}],"SessionStart":[{"type":"command","command":"x"}],"Stop":[{"type":"command","command":"y"}]}}'
            $digest = Set-PluginConfig -Tree $tree -Json $json

            $result = Test-HookContract -HookConfigPath $tree.Config -HookConfigSha256 $digest `
                -HookScriptPath $tree.Script -HookScriptSha256 $tree.ScriptDigest

            $result.status | Should -Be 'Fail'
            $result.evidence | Should -Match 'SessionStart'
            $result.evidence | Should -Match 'Stop'
            $result.evidence | Should -Match 'neither pinned nor measured'
            Test-Path -LiteralPath $script:marker | Should -BeFalse
        }

        It 'accepts an event that is declared and registers nothing' {
            $tree = New-PluginTree -Name 'entry-empty-event'
            $command = (Get-Content -LiteralPath $tree.Config -Raw | ConvertFrom-Json).hooks.PreToolUse[0].windows
            $escaped = $command.Replace('\', '\\').Replace('"', '\"')
            $json = '{"hooks":{"PreToolUse":[{"type":"command","timeout":20,"command":"' + $escaped + '","windows":"' + $escaped + '"}],"Stop":[]}}'
            $digest = Set-PluginConfig -Tree $tree -Json $json

            $result = Test-HookContract -HookConfigPath $tree.Config -HookConfigSha256 $digest `
                -HookScriptPath $tree.Script -HookScriptSha256 $tree.ScriptDigest

            $result.status | Should -Be 'Pass' -Because $result.evidence
        }

        It 'fails a command that takes as long as the timeout the host would enforce' {
            $slow = ('"' + $script:systemPowerShell + '" -NoProfile -NonInteractive -Command "Start-Sleep -Seconds 3"').Replace('\', '\\').Replace('"', '\"')
            $tree = New-PluginTree -Name 'entry-slow'
            $json = '{"hooks":{"PreToolUse":[{"type":"command","timeout":1,"command":"' + $slow + '","windows":"' + $slow + '"}]}}'
            $digest = Set-PluginConfig -Tree $tree -Json $json

            $result = Test-HookContract -HookConfigPath $tree.Config -HookConfigSha256 $digest `
                -HookScriptPath $tree.Script -HookScriptSha256 $tree.ScriptDigest

            $result.status | Should -Be 'Fail'
            $result.evidence | Should -Match 'timeout of 1'
        }
    }

    Context 'when hooks.json does not declare exactly one PreToolUse hook' {
        It 'fails when there is none, and does not throw on the missing property' {
            $tree = New-PluginTree -Name 'no-pretooluse'
            [System.IO.File]::WriteAllText($tree.Config, '{"hooks":{}}', [System.Text.UTF8Encoding]::new($false))

            $result = Test-HookContract -HookConfigPath $tree.Config -HookConfigSha256 (Get-FileDigest -Path $tree.Config) `
                -HookScriptPath $tree.Script -HookScriptSha256 $tree.ScriptDigest

            $result.status | Should -Be 'Fail'
            $result.evidence | Should -Match 'exactly one PreToolUse'
        }
    }
}
