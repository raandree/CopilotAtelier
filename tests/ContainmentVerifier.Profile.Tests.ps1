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
            'Test-VerifierBinding'
            'Get-Verdict'
            'Get-NotRunCheck'
            'Test-ReportPath'
            'Test-PathOverlap'
            'Get-PathChain'
            'Get-PathProblem'
            'Test-ProfileSchema'
        ))

    function script:New-SchemaProfile {
        param(
            [Parameter()]
            [hashtable]$Override = @{}
        )

        $base = if ($script:onWindows) { 'C:\containment' } else { '/containment' }
        $entry = { param($name) [pscustomobject]@{ path = (Join-Path $base $name); sha256 = ('a' * 64) } }
        $document = [ordered]@{
            schemaVersion = 2
            runId = 'run-1'
            verifier = & $entry 'verifier.ps1'
            hooksConfig = & $entry 'hooks.json'
            hookScript = & $entry 'hook.ps1'
            ledgerAppender = & $entry 'appender.ps1'
            ledgerSink = (Join-Path $base 'run.jsonl')
            chainHead = (Join-Path $base 'run.head.json')
            controllerEgressAllow = @()
            workerEgressAllow = @()
            controllerIdentity = 'LAB\controller'
            workerIdentity = 'LAB\worker'
            immutableControlPaths = @((Join-Path $base 'extra.json'))
            writableRoots = @((Join-Path $base 'work'))
        }

        foreach ($key in $Override.Keys) {
            $document[$key] = $Override[$key]
        }

        # Round-trips through JSON as the verifier sees it: a custom object, not a hashtable.
        return ($document | ConvertTo-Json -Depth 6 | ConvertFrom-Json)
    }
}

Describe 'Containment digests and bytes' -Tag 'Unit' {
    It 'computes a lowercase SHA-256 over exactly the bytes it is given' {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes('abc')

        Get-BytesDigest -Bytes $bytes | Should -Be 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'
    }

    It 'parses JSON from bytes and drops a byte-order mark' {
        $bytes = [byte[]](@(0xEF, 0xBB, 0xBF) + [System.Text.Encoding]::UTF8.GetBytes('{"a":1}'))

        (ConvertFrom-JsonByteArray -Bytes $bytes).a | Should -Be 1
    }

    It 'refuses bytes that are not valid UTF-8' {
        { ConvertFrom-JsonByteArray -Bytes ([byte[]](0x7B, 0xFF, 0xFE, 0x7D)) } | Should -Throw
    }

    It 'refuses bytes that are not JSON' {
        { ConvertFrom-JsonByteArray -Bytes ([System.Text.Encoding]::UTF8.GetBytes('not json')) } | Should -Throw
    }
}

Describe 'Containment verifier binding' -Tag 'Unit' {
    BeforeEach {
        $script:running = Join-Path $TestDrive 'Test-RunContainment.ps1'
        [System.IO.File]::WriteAllText($script:running, '# the running verifier')
        $script:runningDigest = Get-BytesDigest -Bytes ([System.IO.File]::ReadAllBytes($script:running))
    }

    It 'passes when the profile pins the running script by its path and digest' {
        $containmentProfile = [pscustomobject]@{ verifier = [pscustomobject]@{ path = $script:running; sha256 = $script:runningDigest } }

        $result = Test-VerifierBinding -ContainmentProfile $containmentProfile -ScriptPath $script:running

        $result.name | Should -Be 'VerifierBinding'
        $result.status | Should -Be 'Pass' -Because $result.evidence
    }

    It 'fails when the profile pins a different file than the one that runs' {
        # Review of 2026-10-12, C-13: verifier.path was not bound to the running script.
        $other = Join-Path $TestDrive 'Other-Verifier.ps1'
        [System.IO.File]::WriteAllText($other, '# a decoy')
        $containmentProfile = [pscustomobject]@{ verifier = [pscustomobject]@{ path = $other; sha256 = (Get-BytesDigest -Bytes ([System.IO.File]::ReadAllBytes($other))) } }

        $result = Test-VerifierBinding -ContainmentProfile $containmentProfile -ScriptPath $script:running

        $result.status | Should -Be 'Fail'
        $result.evidence | Should -Match ([regex]::Escape($other))
    }

    It 'fails when the running script is not the one whose digest the profile pins' {
        $containmentProfile = [pscustomobject]@{ verifier = [pscustomobject]@{ path = $script:running; sha256 = ('f' * 64) } }

        $result = Test-VerifierBinding -ContainmentProfile $containmentProfile -ScriptPath $script:running

        $result.status | Should -Be 'Fail'
        $result.evidence | Should -Match $script:runningDigest
    }

    It 'reports a profile with no verifier entry as unavailable' {
        $result = Test-VerifierBinding -ContainmentProfile ([pscustomobject]@{}) -ScriptPath $script:running

        $result.status | Should -Be 'Unavailable'
    }
}

Describe 'Containment verdict' -Tag 'Unit' {
    It 'passes only when every check passed' {
        $check = @(
            (New-CheckResult -Name 'A' -Status 'Pass' -Evidence 'ok')
            (New-CheckResult -Name 'B' -Status 'Pass' -Evidence 'ok')
        )

        (Get-Verdict -Check $check).Verdict | Should -Be 'Pass'
    }

    It 'fails when a check failed' {
        $check = @((New-CheckResult -Name 'A' -Status 'Pass' -Evidence 'ok'), (New-CheckResult -Name 'B' -Status 'Fail' -Evidence 'no'))

        $verdict = Get-Verdict -Check $check

        $verdict.Verdict | Should -Be 'Fail'
        @($verdict.Blocking).Count | Should -Be 1
    }

    It 'fails when a check could not be measured, exactly like a measured breach' {
        # An unmeasured control was not verified (the Unavailable-means-Fail invariant).
        $check = @((New-CheckResult -Name 'A' -Status 'Pass' -Evidence 'ok'), (New-CheckResult -Name 'B' -Status 'Unavailable' -Evidence 'unmeasured'))

        (Get-Verdict -Check $check).Verdict | Should -Be 'Fail'
    }

    It 'fails when no check ran at all' {
        (Get-Verdict -Check @()).Verdict | Should -Be 'Fail'
    }
}

Describe 'Containment checks that did not run' -Tag 'Unit' {
    It 'reports each named check as unavailable with the reason it did not run' {
        $result = @(Get-NotRunCheck -Name @('HookContract', 'EgressPolicy') -Reason 'the profile failed validation')

        $result.name | Should -Be @('HookContract', 'EgressPolicy')
        $result.status | Should -Be @('Unavailable', 'Unavailable')
        $result[0].evidence | Should -Match 'not run: the profile failed validation'
    }
}

Describe 'Containment report path' -Tag 'Unit' {
    It 'accepts a new file in an existing directory' {
        Test-ReportPath -ReportPath (Join-Path $TestDrive 'report.json') -ProtectedPath @() | Should -BeNullOrEmpty
    }

    It 'refuses a relative path' {
        Test-ReportPath -ReportPath 'report.json' -ProtectedPath @() | Should -Match 'absolute'
    }

    It 'refuses a directory that does not exist, because it creates none' {
        Test-ReportPath -ReportPath (Join-Path $TestDrive 'missing-dir/report.json') -ProtectedPath @() | Should -Match 'does not exist'
    }

    It 'refuses a path that is a protected control' {
        $protected = Join-Path $TestDrive 'ledger.jsonl'
        [System.IO.File]::WriteAllText($protected, '')

        Test-ReportPath -ReportPath $protected -ProtectedPath @($protected) | Should -Match 'protected'
    }

    It 'refuses a path inside a protected directory' {
        $directory = Join-Path $TestDrive 'protected-dir'
        $null = New-Item -Path $directory -ItemType Directory -Force

        Test-ReportPath -ReportPath (Join-Path $directory 'report.json') -ProtectedPath @($directory) | Should -Match 'protected'
    }

    It 'refuses a path that names a directory' {
        $directory = Join-Path $TestDrive 'a-directory'
        $null = New-Item -Path $directory -ItemType Directory -Force

        Test-ReportPath -ReportPath $directory -ProtectedPath @() | Should -Match 'directory'
    }

    It 'refuses <Reason>, which names the protected file under another spelling' -ForEach @(
        @{ Reason = 'a named stream of a protected file'; Suffix = ':stream'; Match = 'alternate data stream' }
        @{ Reason = 'the default stream of a protected file'; Suffix = '::$DATA'; Match = 'alternate data stream' }
    ) -Skip:(-not $script:onWindows) {
        $protected = Join-Path $TestDrive 'stream-protected.jsonl'
        [System.IO.File]::WriteAllText($protected, '')

        Test-ReportPath -ReportPath ($protected + $Suffix) -ProtectedPath @($protected) | Should -Match $Match
    }

    It 'refuses the <Prefix> spelling of a protected file' -ForEach @(
        @{ Prefix = '\\?\' }
        @{ Prefix = '\\.\' }
    ) -Skip:(-not $script:onWindows) {
        $protected = Join-Path $TestDrive 'device-protected.jsonl'
        [System.IO.File]::WriteAllText($protected, '')

        Test-ReportPath -ReportPath ($Prefix + $protected) -ProtectedPath @($protected) | Should -Match 'device or extended-length'
    }

    It 'refuses a report path that reaches a protected file through a junction' -Skip:(-not $script:onWindows) {
        $real = Join-Path $TestDrive 'junction-target'
        $null = New-Item -Path $real -ItemType Directory -Force
        $protected = Join-Path $real 'control.json'
        [System.IO.File]::WriteAllText($protected, '{}')
        $junction = Join-Path $TestDrive 'junction-entry'
        $null = New-Item -Path $junction -ItemType Junction -Value $real

        Test-ReportPath -ReportPath (Join-Path $junction 'control.json') -ProtectedPath @($protected) | Should -Match 'link'
    }

    It 'refuses a report path in a directory that is a junction, whatever it protects' -Skip:(-not $script:onWindows) {
        $real = Join-Path $TestDrive 'junction-target-2'
        $null = New-Item -Path $real -ItemType Directory -Force
        $junction = Join-Path $TestDrive 'junction-entry-2'
        $null = New-Item -Path $junction -ItemType Junction -Value $real

        Test-ReportPath -ReportPath (Join-Path $junction 'report.json') -ProtectedPath @() | Should -Match 'link'
    }

    It 'refuses a report path whose last element is a symbolic link' {
        $target = Join-Path $TestDrive 'link-target.json'
        [System.IO.File]::WriteAllText($target, '{}')
        $link = Join-Path $TestDrive 'link-entry.json'

        try {
            $null = New-Item -Path $link -ItemType SymbolicLink -Value $target
        } catch {
            Set-ItResult -Skipped -Because "a symbolic link cannot be created here: $($_.Exception.Message)"
            return
        }

        Test-ReportPath -ReportPath $link -ProtectedPath @() | Should -Match 'link'
    }
}

Describe 'Containment profile schema paths and digests' -Tag 'Unit' {
    It 'accepts a profile whose paths are absolute and whose digests are lowercase' {
        @(Test-ProfileSchema -ContainmentProfile (New-SchemaProfile)) | Should -HaveCount 0
    }

    It 'refuses an uppercase digest' {
        # Review of 2026-10-12, C-13: the digest patterns were case-insensitive.
        $containmentProfile = New-SchemaProfile
        $containmentProfile.hookScript.sha256 = ('A' * 64)

        (Test-ProfileSchema -ContainmentProfile $containmentProfile) -join '; ' | Should -Match 'lowercase 64-hex'
    }

    It 'refuses <Reason>' -ForEach @(
        @{ Reason = 'a relative pinned path'; Field = 'verifier'; Value = [pscustomobject]@{ path = 'scripts/verify.ps1'; sha256 = ('a' * 64) } }
        @{ Reason = 'a relative ledger sink'; Field = 'ledgerSink'; Value = 'run.jsonl' }
        @{ Reason = 'a relative chain head'; Field = 'chainHead'; Value = 'ledger\run.head.json' }
        @{ Reason = 'a relative immutable path'; Field = 'immutableControlPaths'; Value = @('extra.json') }
        @{ Reason = 'a relative writable root'; Field = 'writableRoots'; Value = @('work') }
    ) {
        $containmentProfile = New-SchemaProfile
        $containmentProfile.$Field = $Value

        (Test-ProfileSchema -ContainmentProfile $containmentProfile) -join '; ' | Should -Match 'absolute'
    }

    It 'refuses a path with a dot segment' -Skip:(-not $script:onWindows) {
        $containmentProfile = New-SchemaProfile
        $containmentProfile.ledgerSink = 'C:\containment\..\elsewhere\run.jsonl'

        (Test-ProfileSchema -ContainmentProfile $containmentProfile) -join '; ' | Should -Match 'dot segment'
    }

    It 'refuses a Windows short name, which names a file the text does not' -Skip:(-not $script:onWindows) {
        $containmentProfile = New-SchemaProfile
        $containmentProfile.chainHead = 'C:\PROGRA~1\containment\run.head.json'

        (Test-ProfileSchema -ContainmentProfile $containmentProfile) -join '; ' | Should -Match 'short name'
    }

    It 'refuses a schema version other than 2: <Version>' -ForEach @(
        @{ Version = 1 }
        @{ Version = 3 }
    ) {
        # Review of 2026-10-12: the documentation said "always 1" and nothing enforced it. Version 2 names the run.
        $containmentProfile = New-SchemaProfile
        $containmentProfile.schemaVersion = $Version

        (Test-ProfileSchema -ContainmentProfile $containmentProfile) -join '; ' | Should -Match "'schemaVersion' must be the integer 2"
    }

    It 'tells the owner of a version-1 profile what version 2 adds' {
        $containmentProfile = New-SchemaProfile
        $containmentProfile.schemaVersion = 1
        $containmentProfile.PSObject.Properties.Remove('runId')

        $problem = (Test-ProfileSchema -ContainmentProfile $containmentProfile) -join '; '

        $problem | Should -Match "'schemaVersion' must be the integer 2"
        $problem | Should -Match "missing required field 'runId'"
        $problem | Should -Match 'names no run'
        $problem | Should -Match 'new for (this|each) run'
    }

    It 'tells the owner of a version-1 profile that already names its run only to raise the version' {
        # Review R14-07: the hint said that such a profile names no run.
        $containmentProfile = New-SchemaProfile
        $containmentProfile.schemaVersion = 1

        $problem = (Test-ProfileSchema -ContainmentProfile $containmentProfile) -join '; '

        $problem | Should -Match "'schemaVersion' must be the integer 2"
        $problem | Should -Match "version 2 adds 'runId', a run id that is new for each run; set 'schemaVersion' to 2"
        $problem | Should -Not -Match 'names no run'
    }

    It 'refuses a schema version that only equals 2 after a conversion, or is no number: <Reason>' -ForEach @(
        @{ Reason = 'a string'; Version = '2' }
        @{ Reason = 'a boolean'; Version = $true }
        @{ Reason = 'a fraction'; Version = [double]2.0 }
        @{ Reason = 'an array'; Version = @(2) }
    ) {
        # Review pass 1, R-10: each of these passed a loose comparison with the version.
        $containmentProfile = New-SchemaProfile
        $containmentProfile.schemaVersion = $Version

        (Test-ProfileSchema -ContainmentProfile $containmentProfile) -join '; ' | Should -Match 'schemaVersion'
    }

    It 'accepts the integer 2 as a JSON document spells it' {
        $containmentProfile = New-SchemaProfile

        @(Test-ProfileSchema -ContainmentProfile $containmentProfile) | Should -HaveCount 0
    }

    It 'refuses <Reason>' -ForEach @(
        @{ Reason = 'a stream of the ledger sink'; Field = 'ledgerSink'; Value = 'C:\containment\run.jsonl::$DATA'; Match = 'alternate data stream' }
        @{ Reason = 'an extended-length spelling of the chain head'; Field = 'chainHead'; Value = '\\?\C:\containment\run.head.json'; Match = 'device or extended-length' }
    ) -Skip:(-not $script:onWindows) {
        $containmentProfile = New-SchemaProfile
        $containmentProfile.$Field = $Value

        (Test-ProfileSchema -ContainmentProfile $containmentProfile) -join '; ' | Should -Match $Match
    }

    It 'refuses an empty <Field>' -ForEach @(
        @{ Field = 'controllerIdentity' }
        @{ Field = 'workerIdentity' }
    ) {
        $containmentProfile = New-SchemaProfile -Override @{ $Field = '' }

        (Test-ProfileSchema -ContainmentProfile $containmentProfile) -join '; ' | Should -Match $Field
    }

    It 'refuses a live artifact that does not declare a path and a digest' {
        $containmentProfile = New-SchemaProfile -Override @{ liveRunner = [pscustomobject]@{ path = 'C:\containment\runner.exe' } }

        (Test-ProfileSchema -ContainmentProfile $containmentProfile) -join '; ' | Should -Match 'liveRunner'
    }

    It 'checks the paths and digests of a live artifact like those of a pinned control' {
        $containmentProfile = New-SchemaProfile -Override @{ liveRunner = [pscustomobject]@{ path = 'runner.exe'; sha256 = ('B' * 64) } }

        $problem = (Test-ProfileSchema -ContainmentProfile $containmentProfile) -join '; '

        $problem | Should -Match 'liveRunner.*absolute'
        $problem | Should -Match 'liveRunner.*lowercase 64-hex'
    }

    # Review pass 3: a pinned control given as null made the schema check throw, so the run ended with exit
    # code 1 and no report instead of a ProfileSchema failure. No Pass was possible, but the refusal should say why.
    It 'refuses a pinned control that is <Reason>, and does not throw' -ForEach @(
        @{ Reason = 'null'; Value = $null }
        @{ Reason = 'text'; Value = 'verifier.ps1' }
        @{ Reason = 'a number'; Value = 5 }
    ) {
        $containmentProfile = New-SchemaProfile
        $containmentProfile.verifier = $Value

        { Test-ProfileSchema -ContainmentProfile $containmentProfile } | Should -Not -Throw
        (Test-ProfileSchema -ContainmentProfile $containmentProfile) -join '; ' | Should -Match "'verifier' must be an object"
    }

    It 'refuses a field whose name only looks like a known one' {
        # Review pass 2, S-04: -notin compares by culture, and a culture ignores a zero-width space, so
        # an unknown field passed as the field it imitates.
        $containmentProfile = New-SchemaProfile
        $containmentProfile | Add-Member -NotePropertyName ('ledger' + [char]0x200B + 'Sink') -NotePropertyValue $containmentProfile.ledgerSink

        (Test-ProfileSchema -ContainmentProfile $containmentProfile) -join '; ' | Should -Match 'unknown field'
    }

    It 'does not let a field that only looks like a required one stand in for it' {
        $containmentProfile = New-SchemaProfile
        $verifier = $containmentProfile.verifier
        $containmentProfile.PSObject.Properties.Remove('verifier')
        $containmentProfile | Add-Member -NotePropertyName ('verifier' + [char]0x200B) -NotePropertyValue $verifier

        (Test-ProfileSchema -ContainmentProfile $containmentProfile) -join '; ' | Should -Match "missing required field 'verifier'"
    }

    It 'does not let a key that only looks like the digest of a pinned control stand in for it' {
        $containmentProfile = New-SchemaProfile
        $containmentProfile.hookScript = [pscustomobject]@{ path = $containmentProfile.hookScript.path; ('sha256' + [char]0x200B) = ('a' * 64) }

        (Test-ProfileSchema -ContainmentProfile $containmentProfile) -join '; ' | Should -Match "'hookScript' must declare a path and a sha256"
    }

    It 'refuses a field spelled in another case, because every other part of the profile is read by its exact name' {
        $containmentProfile = New-SchemaProfile
        $containmentProfile.PSObject.Properties.Remove('ledgerSink')
        $containmentProfile | Add-Member -NotePropertyName 'LedgerSink' -NotePropertyValue 'run.jsonl'

        $problem = (Test-ProfileSchema -ContainmentProfile $containmentProfile) -join '; '

        $problem | Should -Match "unknown field 'LedgerSink'"
        $problem | Should -Match "missing required field 'ledgerSink'"
    }
}

Describe 'Containment profile run id' -Tag 'Unit' {
    It 'accepts a run id of <Reason>' -ForEach @(
        @{ Reason = 'a GUID'; RunId = '3f2504e0-4f89-11d3-9a0c-0305e82c3301' }
        @{ Reason = 'one character'; RunId = 'a' }
        @{ Reason = 'sixty-four characters'; RunId = ('r' * 64) }
        @{ Reason = 'letters, digits, dots, underscores and hyphens'; RunId = 'Run_2026-11-14.1' }
    ) {
        @(Test-ProfileSchema -ContainmentProfile (New-SchemaProfile -Override @{ runId = $RunId })) | Should -HaveCount 0
    }

    It 'refuses a profile that names no run id' {
        $containmentProfile = New-SchemaProfile
        $containmentProfile.PSObject.Properties.Remove('runId')

        (Test-ProfileSchema -ContainmentProfile $containmentProfile) -join '; ' | Should -Match "missing required field 'runId'"
    }

    It 'refuses a run id that is <Reason>, and does not throw' -ForEach @(
        @{ Reason = 'a number'; RunId = 1234 }
        @{ Reason = 'a boolean'; RunId = $true }
        @{ Reason = 'an array'; RunId = @('run-1') }
        @{ Reason = 'an object'; RunId = [pscustomobject]@{ id = 'run-1' } }
        @{ Reason = 'null'; RunId = $null }
        @{ Reason = 'empty'; RunId = '' }
        @{ Reason = 'blank'; RunId = '   ' }
        @{ Reason = 'sixty-five characters long'; RunId = ('r' * 65) }
        @{ Reason = 'spelled with a space'; RunId = 'run 1' }
        @{ Reason = 'spelled with a colon'; RunId = 'run:1' }
        @{ Reason = 'spelled with a slash'; RunId = 'run/1' }
        @{ Reason = 'spelled with a zero-width space'; RunId = ('run-1' + [char]0x200B) }
        @{ Reason = 'spelled with the Kelvin sign, which a match that ignores case reads as a K'; RunId = ('run-' + [char]0x212A) }
        @{ Reason = 'spelled with a letter outside ASCII'; RunId = ('r' + [char]0x00FC + 'n') }
        @{ Reason = 'ended by a line feed'; RunId = ('run-1' + [char]0x000A) }
    ) {
        $containmentProfile = New-SchemaProfile
        $containmentProfile.runId = $RunId

        { Test-ProfileSchema -ContainmentProfile $containmentProfile } | Should -Not -Throw
        (Test-ProfileSchema -ContainmentProfile $containmentProfile) -join '; ' | Should -Match "'runId' must be"
    }

    It 'refuses a run id that the JSON reader of the profile turns into a date: <Value>' -ForEach @(
        @{ Value = '2026-11-14T08:00:00Z' }
        @{ Value = '/Date(1700000000000)/' }
    ) {
        # ConvertFrom-Json, which reads the profile, returns a DateTime for these strings (pwsh 7.6.10), so the
        # value the verifier compares would not be the text the operator wrote.
        $containmentProfile = New-SchemaProfile -Override @{ runId = $Value }

        $containmentProfile.runId | Should -BeOfType [datetime] -Because 'the fixture reads the profile as the verifier does'
        (Test-ProfileSchema -ContainmentProfile $containmentProfile) -join '; ' | Should -Match "'runId' must be"
    }

    It 'does not let a run id spelled in another case stand in for it' {
        $containmentProfile = New-SchemaProfile
        $containmentProfile.PSObject.Properties.Remove('runId')
        $containmentProfile | Add-Member -NotePropertyName 'RunId' -NotePropertyValue 'run-1'

        $problem = (Test-ProfileSchema -ContainmentProfile $containmentProfile) -join '; '

        $problem | Should -Match "unknown field 'RunId'"
        $problem | Should -Match "missing required field 'runId'"
    }
}
