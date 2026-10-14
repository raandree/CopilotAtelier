# Evaluated during discovery so -Skip: can see it; a BeforeAll runs too late.
# Never name this $isWindows: PowerShell variable names are case-insensitive, so
# it would collide with the read-only automatic $IsWindows and abort the file.
$script:onWindows = $IsWindows -or $PSVersionTable.PSEdition -eq 'Desktop'

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:verifierScript = Join-Path $script:repoRoot 'com.github.copilot/hooks/scripts/Test-RunContainment.ps1'
    . (Join-Path $script:repoRoot 'tests/Helpers/ScriptFunction.ps1')
    . (Get-ScriptFunctionDefinition -Path $script:verifierScript -Name @(
            'New-CheckResult'
            'Get-BytesDigest'
            'ConvertFrom-JsonByteArray'
            'Get-JsonNode'
            'Format-LimitedList'
            'Get-GrantRoot'
            'Test-GrantChannelClosed'
        ))

    # Writes a hooks.json and returns its path and digest, as the profile would pin them.
    function script:New-ConfigFile {
        param(
            [Parameter(Mandatory)]
            [string]$Name,

            [Parameter(Mandatory)]
            [string]$Json
        )

        $path = Join-Path $TestDrive $Name
        [System.IO.File]::WriteAllText($path, $Json, [System.Text.UTF8Encoding]::new($false))

        return [pscustomobject]@{
            Path = $path
            Digest = (Get-BytesDigest -Bytes ([System.IO.File]::ReadAllBytes($path)))
        }
    }

    function script:Invoke-Check {
        param(
            [Parameter(Mandatory)]
            $Config,

            [Parameter()]
            [string]$GrantRoot = (Join-Path $TestDrive 'no-grants-here')
        )

        return Test-GrantChannelClosed -HookConfigPath $Config.Path -HookConfigSha256 $Config.Digest -GrantRoot $GrantRoot
    }

    $script:guardOnly = '{"hooks":{"PreToolUse":[{"type":"command","windows":"powershell -File guard.ps1","command":"pwsh -File guard.ps1"}]}}'
}

Describe 'Containment grant channel' -Tag 'Unit' {
    Context 'the hooks.json the profile pins' {
        It 'passes a hooks.json that registers only the guard' {
            $result = Invoke-Check -Config (New-ConfigFile -Name 'guard-only.json' -Json $script:guardOnly)

            $result.status | Should -Be 'Pass' -Because $result.evidence
            $result.name | Should -Be 'GrantChannelClosed'
        }

        It 'fails a hooks.json that registers a UserPromptSubmit hook' {
            $json = '{"hooks":{"PreToolUse":[{"type":"command","command":"guard"}],"UserPromptSubmit":[{"type":"command","command":"anything"}]}}'

            $result = Invoke-Check -Config (New-ConfigFile -Name 'prompt-hook.json' -Json $json)

            $result.status | Should -Be 'Fail'
            $result.evidence | Should -Match 'UserPromptSubmit'
            $result.evidence | Should -Match 'Remote grant'
        }

        It 'fails the spelling the Copilot CLI uses for the same event' {
            $json = '{"hooks":{"userPromptSubmitted":[{"type":"command","command":"anything"}]}}'

            $result = Invoke-Check -Config (New-ConfigFile -Name 'prompt-hook-cli.json' -Json $json)

            $result.status | Should -Be 'Fail'
            $result.evidence | Should -Match 'userPromptSubmitted'
        }

        It 'fails the event name whatever its case' {
            $json = '{"hooks":{"USERPROMPTSUBMIT":[{"type":"command","command":"anything"}]}}'

            (Invoke-Check -Config (New-ConfigFile -Name 'prompt-hook-upper.json' -Json $json)).status | Should -Be 'Fail'
        }

        It 'passes a prompt event that registers no hook' {
            $json = '{"hooks":{"PreToolUse":[{"type":"command","command":"guard"}],"UserPromptSubmit":[]}}'

            (Invoke-Check -Config (New-ConfigFile -Name 'prompt-empty.json' -Json $json)).status | Should -Be 'Pass'
        }

        It 'fails a command that runs the Remote grant recorder under any other event' {
            $json = '{"hooks":{"SessionStart":[{"type":"command","windows":"powershell -File C:/x/Add-RemoteGrant.ps1"}]}}'

            $result = Invoke-Check -Config (New-ConfigFile -Name 'recorder-elsewhere.json' -Json $json)

            $result.status | Should -Be 'Fail'
            $result.evidence | Should -Match 'SessionStart'
            $result.evidence | Should -Match 'recorder'
        }

        It 'fails a recorder nested in a matcher group, however deep' {
            $json = '{"hooks":{"SessionStart":[{"matcher":"","hooks":[{"type":"command","command":"pwsh -File C:/x/Add-RemoteGrant.ps1"}]}]}}'

            $result = Invoke-Check -Config (New-ConfigFile -Name 'recorder-nested.json' -Json $json)

            $result.status | Should -Be 'Fail'
            $result.evidence | Should -Match 'SessionStart'
            $result.evidence | Should -Match 'recorder'
        }

        It 'fails a recorder named in a field the scan does not list' {
            $json = '{"hooks":{"PreToolUse":[{"type":"command","command":"guard","script":"Add-RemoteGrant.ps1"}]}}'

            (Invoke-Check -Config (New-ConfigFile -Name 'recorder-other-field.json' -Json $json)).status | Should -Be 'Fail'
        }

        It 'names a recorder case-insensitively' {
            $json = '{"hooks":{"SessionStart":[{"type":"command","command":"pwsh -File add-remotegrant.PS1"}]}}'

            (Invoke-Check -Config (New-ConfigFile -Name 'recorder-case.json' -Json $json)).status | Should -Be 'Fail'
        }

        It 'finds a recorder nested deeper than a serializer would follow' {
            $json = '{"hooks":{"SessionStart":[' + ('{"a":' * 150) + '"Add-RemoteGrant"' + ('}' * 150) + ']}}'

            $result = Invoke-Check -Config (New-ConfigFile -Name 'recorder-deep.json' -Json $json)

            $result.status | Should -Be 'Fail'
            $result.evidence | Should -Match 'SessionStart'
        }

        It 'fails a recorder named as a property name' {
            $json = '{"hooks":{"SessionStart":[{"Add-RemoteGrant.ps1":true}]}}'

            (Invoke-Check -Config (New-ConfigFile -Name 'recorder-key.json' -Json $json)).status | Should -Be 'Fail'
        }

        It 'fails a prompt event registered below another key' {
            $json = '{"hooks":{"PreToolUse":[{"type":"command","command":"guard"}]},"plugins":{"extra":{"hooks":{"UserPromptSubmit":[{"type":"command","command":"anything"}]}}}}'

            $result = Invoke-Check -Config (New-ConfigFile -Name 'prompt-nested.json' -Json $json)

            $result.status | Should -Be 'Fail'
            $result.evidence | Should -Match 'UserPromptSubmit'
            $result.evidence | Should -Match 'plugins'
        }

        It 'names where in the file each finding sits, and at most three of them' {
            $entry = '{"type":"command","command":"Add-RemoteGrant"}'
            $json = '{"hooks":{"SessionStart":[' + ((1..5 | ForEach-Object { $entry }) -join ',') + ']}}'

            $result = Invoke-Check -Config (New-ConfigFile -Name 'recorder-many.json' -Json $json)

            $result.status | Should -Be 'Fail'
            $result.evidence | Should -Match ([regex]::Escape('hooks.SessionStart[0].command'))
            $result.evidence | Should -Match 'and 2 more'
        }

        It 'does not take the guard for the recorder' {
            $json = '{"hooks":{"PreToolUse":[{"type":"command","command":"pwsh -File Block-RemoteMutation.ps1"}]}}'

            (Invoke-Check -Config (New-ConfigFile -Name 'guard-named.json' -Json $json)).status | Should -Be 'Pass'
        }

        It 'does not parse a hooks.json that does not match its digest' {
            $config = New-ConfigFile -Name 'digest.json' -Json $script:guardOnly

            $result = Test-GrantChannelClosed -HookConfigPath $config.Path -HookConfigSha256 ('b' * 64) -GrantRoot (Join-Path $TestDrive 'none')

            $result.status | Should -Be 'Fail'
            $result.evidence | Should -Match 'digest|hashes'
        }

        It 'reports a hooks.json that is not valid JSON as unmeasured' {
            $result = Invoke-Check -Config (New-ConfigFile -Name 'broken.json' -Json '{ not json')

            $result.status | Should -Be 'Unavailable'
        }

        It 'reports a hooks.json that cannot be read as unmeasured' {
            $result = Test-GrantChannelClosed -HookConfigPath (Join-Path $TestDrive 'absent.json') -HookConfigSha256 ('a' * 64) -GrantRoot (Join-Path $TestDrive 'none')

            $result.status | Should -Be 'Unavailable'
        }

        It 'does not throw on a hooks.json whose hooks is not an object' {
            $result = Invoke-Check -Config (New-ConfigFile -Name 'odd.json' -Json '{"hooks":["a","b"]}')

            $result.status | Should -Be 'Pass'
        }

        It 'does not throw on a hooks.json that is not an object: <Json>' -ForEach @(
            @{ Json = 'null' }
            @{ Json = '[]' }
            @{ Json = '"text"' }
            @{ Json = '42' }
        ) {
            (Invoke-Check -Config (New-ConfigFile -Name 'not-object.json' -Json $Json)).status | Should -Be 'Pass'
        }
    }

    Context 'the grants folder of the identity that runs' {
        BeforeAll {
            $script:config = New-ConfigFile -Name 'guard-for-folder.json' -Json $script:guardOnly
        }

        It 'passes when the folder does not exist' {
            (Invoke-Check -Config $script:config -GrantRoot (Join-Path $TestDrive 'never-created')).status | Should -Be 'Pass'
        }

        It 'passes when the folder is empty' {
            $root = Join-Path $TestDrive 'empty-grants'
            $null = New-Item -Path $root -ItemType Directory -Force

            (Invoke-Check -Config $script:config -GrantRoot $root).status | Should -Be 'Pass'
        }

        It 'fails when a Remote grant is waiting in it' {
            $root = Join-Path $TestDrive 'waiting-grants'
            $null = New-Item -Path $root -ItemType Directory -Force
            [System.IO.File]::WriteAllText((Join-Path $root 'grant-0123456789abcdef.json'), '{}')

            $result = Invoke-Check -Config $script:config -GrantRoot $root

            $result.status | Should -Be 'Fail'
            $result.evidence | Should -Match 'Remote grant'
            $result.evidence | Should -Match ([regex]::Escape($root))
        }

        It 'fails when the folder holds anything at all' {
            $root = Join-Path $TestDrive 'stray-grants'
            $null = New-Item -Path $root -ItemType Directory -Force
            [System.IO.File]::WriteAllText((Join-Path $root 'left-over.tmp'), 'x')

            (Invoke-Check -Config $script:config -GrantRoot $root).status | Should -Be 'Fail'
        }

        It 'names both findings when the hook and a grant are both present' {
            $json = '{"hooks":{"UserPromptSubmit":[{"type":"command","command":"anything"}]}}'
            $config = New-ConfigFile -Name 'both.json' -Json $json
            $root = Join-Path $TestDrive 'both-grants'
            $null = New-Item -Path $root -ItemType Directory -Force
            [System.IO.File]::WriteAllText((Join-Path $root 'grant-0123456789abcdef.json'), '{}')

            $result = Invoke-Check -Config $config -GrantRoot $root

            $result.status | Should -Be 'Fail'
            $result.evidence | Should -Match 'UserPromptSubmit'
            $result.evidence | Should -Match 'waiting|wait'
        }
    }

    Context 'the default grants folder' {
        It 'is the folder the guard reads: CopilotAtelier/grants under LocalApplicationData' {
            $expected = [System.IO.Path]::Combine([System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::LocalApplicationData), 'CopilotAtelier', 'grants')

            Get-GrantRoot | Should -Be $expected
        }

        It 'is the folder measured when no root is given' {
            $config = New-ConfigFile -Name 'guard-default-root.json' -Json $script:guardOnly
            $root = Join-Path $TestDrive 'mocked-default'
            $null = New-Item -Path $root -ItemType Directory -Force
            [System.IO.File]::WriteAllText((Join-Path $root 'grant-0123456789abcdef.json'), '{}')
            $script:mockedRoot = $root
            Mock -CommandName Get-GrantRoot -MockWith { $script:mockedRoot }

            $result = Test-GrantChannelClosed -HookConfigPath $config.Path -HookConfigSha256 $config.Digest

            $result.status | Should -Be 'Fail'
        }
    }
}
