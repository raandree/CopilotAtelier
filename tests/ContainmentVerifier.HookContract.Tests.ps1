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

        return New-HookConfig -Path $Path -Command ('"' + $script:systemPowerShell + '"' + $command.Substring('powershell'.Length))
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
        @{ Why = 'a form feed'; Line = ('"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -Command exit' + [char]12 + 'x'); Match = 'outside printable ASCII' }
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
    ) {
        $result = Get-HookInterpreter -CommandLine $Line

        $result.Path | Should -BeNullOrEmpty
        $result.Problem | Should -Match $Match
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
    It 'reads a line with an empty quoted word without throwing' {
        $line = '"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -Command exit ""'

        { Get-HookInterpreter -CommandLine $line } | Should -Not -Throw
        (Get-HookInterpreter -CommandLine $line).Problem | Should -BeNullOrEmpty
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
    # and not by the next review. The generator is seeded, so a failure repeats.
    It 'reads every accepted line as one command whose words are the words the shape saw' {
        $random = [System.Random]::new(20261014)
        $program = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
        $bareAlphabet = [char[]]'abcdefXYZ019_.:\/-'
        $quotedAlphabet = [char[]](' #&''()*+,-./0123456789:;<=>?@ABCXYZ[]\^_{|}~abcxyz')
        $pick = {
            param([char[]]$Alphabet, [int]$Length)

            $builder = [System.Text.StringBuilder]::new()
            for ($index = 0; $index -lt $Length; $index++) {
                $null = $builder.Append($Alphabet[$random.Next(0, $Alphabet.Length)])
            }

            $builder.ToString()
        }
        $accepted = 0
        $deviation = [System.Collections.Generic.List[string]]::new()

        for ($line = 0; $line -lt 4000; $line++) {
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

            $expected = @($program, '-NoProfile', '-Command') + $word
            $text = $expected -join @(' ', "`t", '  ')[$random.Next(0, 3)]

            if ($null -ne (Get-HookInterpreter -CommandLine $text).Problem) {
                continue
            }

            $accepted++
            $errors = $null
            $tokens = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseInput($text, [ref]$tokens, [ref]$errors)
            $statement = @($ast.EndBlock.Statements)
            $command = $null

            if ($statement.Count -eq 1 -and $statement[0] -is [System.Management.Automation.Language.PipelineAst] -and $statement[0].PipelineElements.Count -eq 1) {
                $command = $statement[0].PipelineElements[0]
            }

            $same = $errors.Count -eq 0 -and $command -is [System.Management.Automation.Language.CommandAst] -and
                $command.Redirections.Count -eq 0 -and $command.CommandElements.Count -eq $expected.Count

            for ($element = 0; $same -and $element -lt $expected.Count; $element++) {
                $same = [string]::Equals($command.CommandElements[$element].Extent.Text, $expected[$element], [System.StringComparison]::Ordinal)
            }

            if (-not $same) {
                $deviation.Add($text)
            }
        }

        $accepted | Should -BeGreaterThan 500 -Because 'the generator has to reach lines that the shape accepts, or this test proves nothing'
        $deviation.Count | Should -Be 0 -Because ('PowerShell read these accepted lines as other words than the shape did: ' + (($deviation | Select-Object -First 5) -join ' || '))
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

        # Review pass 3 part C, S-23 and S-24: the probe is a measurement through cmd.exe, and the hosts the README
        # lists wrap the line in PowerShell, so a Pass must not read as a measurement under them.
        It 'says that the probe ran the line through cmd.exe, and that a PowerShell host reads it by other rules' {
            $script:shippedRun.evidence | Should -Match 'through cmd\.exe /d /c'
            $script:shippedRun.evidence | Should -Match 'PowerShell host'
        }

        It 'says that a quoted program path is not shown to run under a PowerShell host' {
            $script:shippedRun.evidence | Should -Match 'program path is quoted'
        }

        It 'does not say so when the program path is not quoted' {
            $shipped = [System.IO.File]::ReadAllText($script:realConfig) | ConvertFrom-Json
            $text = [string]@($shipped.hooks.PreToolUse)[0].windows
            $tree = New-PluginTree -Name 'unquoted-program' -Command ($script:systemPowerShell + $text.Substring('powershell'.Length))

            $result = Test-HookContract -HookConfigPath $tree.Config -HookConfigSha256 $tree.ConfigDigest `
                -HookScriptPath $tree.Script -HookScriptSha256 $tree.ScriptDigest

            $result.status | Should -Be 'Pass' -Because $result.evidence
            $result.evidence | Should -Not -Match 'program path is quoted'
        }
    }

    Context 'the interpreter the command starts' {
        BeforeEach {
            $script:marker = Join-Path $TestDrive "interpreter-marker-$([guid]::NewGuid().ToString('N')).txt"
            # A command that leaves a file behind if it is ever run, so that "runs nothing" can be read off the disk.
            $script:markerRun = "`"$script:systemPowerShell`" -NoProfile -NonInteractive -Command `"Set-Content -LiteralPath '$script:marker' -Value ran`""
        }

        # Review pass 3 part D, S-25, reproduced end to end: PowerShell reads '-x:' as a parameter that binds to the next
        # word or, as the last word, fails to parse, so both documented hosts exit 1 for a push, which does not block,
        # and the cmd.exe probe still reports 0, 2, 2.
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
        # and a push exits 1, which does not block. The cmd.exe probe passes the same text through and reports 0, 2, 2.
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

        It 'measures the interpreter against the writable roots it is given' {
            $root = Join-Path $TestDrive 'a-writable-root'

            $null = Test-HookContract -HookConfigPath $script:plugin.Config -HookConfigSha256 $script:plugin.ConfigDigest `
                -HookScriptPath $script:plugin.Script -HookScriptSha256 $script:plugin.ScriptDigest -WritableRoot @($root)

            Should -Invoke Test-PathProtection -Times 1 -Exactly -ParameterFilter {
                $Path -eq [System.IO.Path]::GetFullPath($script:systemPowerShell) -and $WritableRoot -contains $root
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
