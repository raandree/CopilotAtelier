BeforeDiscovery {
    $script:linkItemType = if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) { 'Junction' } else { 'SymbolicLink' }

    # Directory-link creation is a host capability, so it is probed once during
    # discovery rather than assumed. TestDrive does not exist yet at this point.
    $script:canCreateDirectoryLink = $false
    $probeRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('ca-link-probe-' + [guid]::NewGuid().ToString('N'))
    try
    {
        $probeTarget = Join-Path $probeRoot 'target'
        New-Item -ItemType Directory -Path $probeTarget -Force | Out-Null
        New-Item -ItemType $script:linkItemType -Path (Join-Path $probeRoot 'link') -Target $probeTarget -ErrorAction Stop | Out-Null
        $script:canCreateDirectoryLink = $true
    }
    catch
    {
        $script:canCreateDirectoryLink = $false
    }
    finally
    {
        Remove-Item -LiteralPath $probeRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

BeforeAll {
    $script:projectPath = Convert-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')
    . (Join-Path $script:projectPath 'tests/Helpers/DeploymentProfile.ps1')
    Import-CopilotAtelierTestModule -ProjectPath $script:projectPath

    $script:referenceUtc = [datetime]::SpecifyKind([datetime]::Parse('2026-09-01T00:00:00'), [System.DateTimeKind]::Utc)
    $script:linkItemType = if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) { 'Junction' } else { 'SymbolicLink' }

    function Write-ObservationDocument
    {
        param
        (
            [Parameter(Mandatory = $true)] [System.String] $Path,
            [Parameter(Mandatory = $true)] [System.Object] $Document
        )

        New-Item -ItemType Directory -Path (Split-Path -Path $Path -Parent) -Force | Out-Null
        Set-Content -LiteralPath $Path -Encoding utf8 -Value ($Document | ConvertTo-Json -Depth 8)
    }

    function New-Document
    {
        param
        (
            [Parameter(Mandatory = $true)] [System.Object[]] $Record,
            [Parameter()] [System.String] $Client = 'vscode-copilot-chat',
            [Parameter()] [System.String] $ClientVersion = '1.105.0'
        )

        [ordered] @{
            schemaVersion = 1
            client        = $Client
            clientVersion = $ClientVersion
            trust         = 'Imported'
            records       = $Record
        }
    }

    function New-Record
    {
        param
        (
            [Parameter()] [System.String] $EventId = 'e1',
            [Parameter()] [System.String] $EventType = 'SkillActivation',
            [Parameter()] [System.String] $SkillName = 'alpha-tool',
            [Parameter()] [System.String] $SkillSha256 = ('a' * 64),
            [Parameter()] [System.String] $TimestampUtc = '2026-08-30T10:00:00Z',
            [Parameter()] [System.String] $SessionId = 'session-1',
            [Parameter()] [System.String] $Outcome = 'Unknown'
        )

        [ordered] @{
            eventId      = $EventId
            eventType    = $EventType
            skillName    = $SkillName
            skillSha256  = $SkillSha256
            timestampUtc = $TimestampUtc
            sessionId    = $SessionId
            outcome      = $Outcome
        }
    }

    function Invoke-Import
    {
        param ([Parameter(Mandatory = $true)] [System.String[]] $Path)

        InModuleScope -ModuleName CopilotAtelier -Parameters @{ Path = $Path; ReferenceUtc = $script:referenceUtc } -ScriptBlock {
            param ($Path, $ReferenceUtc)

            Import-CopilotAtelierSkillObservation -Path $Path -ReferenceUtc $ReferenceUtc
        }
    }
}

Describe 'Import-CopilotAtelierSkillObservation' -Tag 'Unit' {
    BeforeEach {
        $script:root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:root -Force | Out-Null
    }

    It 'Should normalize an accepted record to the documented shape' {
        $path = Join-Path $script:root 'ok.json'
        Write-ObservationDocument -Path $path -Document (New-Document -Record @(New-Record -SkillSha256 ('A' * 64)))

        $result = Invoke-Import -Path $path

        @($result.Record).Count | Should -Be 1
        $result.Record[0].SkillSha256 | Should -Be ('a' * 64)
        $result.Record[0].EventType | Should -Be 'SkillActivation'
        $result.Record[0].TimestampUtc.Kind | Should -Be ([System.DateTimeKind]::Utc)
        @($result.Record[0].PSObject.Properties.Name) | Should -Be @('EventId', 'EventType', 'SkillName', 'SkillSha256', 'TimestampUtc', 'SessionId', 'Outcome', 'Client', 'ClientVersion', 'IdentityScope', 'SourcePath')
    }

    It 'Should refuse an observation path that is a reparse point' -Skip:(-not $script:canCreateDirectoryLink) {
        $target = Join-Path $script:root 'outside'
        New-Item -ItemType Directory -Path $target -Force | Out-Null
        Write-ObservationDocument -Path (Join-Path $target 'ok.json') -Document (New-Document -Record @(New-Record))
        $link = Join-Path $script:root 'linked'
        New-Item -ItemType $script:linkItemType -Path $link -Target $target | Out-Null

        { Invoke-Import -Path $link } | Should -Throw -ExpectedMessage '*reparse*'
    }

    It 'Should refuse a file that holds more records than the documented bound' {
        $record = @(
            1..2001 | ForEach-Object -Process { New-Record -EventId "e$_" }
        )
        $path = Join-Path $script:root 'many.json'
        Write-ObservationDocument -Path $path -Document (New-Document -Record $record)

        $result = Invoke-Import -Path $path

        @($result.RejectedFile).Count | Should -Be 1
        $result.RejectedFile[0].Reason | Should -Match 'record'
        @($result.Record).Count | Should -Be 0
    }

    It 'Should reject <Field> when it violates the schema' -ForEach @(
        @{ Field = 'eventId'; Mutation = { param ($r) $r['eventId'] = 'a' * 200 } }
        @{ Field = 'eventId'; Mutation = { param ($r) $r['eventId'] = "line`nbreak" } }
        @{ Field = 'skillName'; Mutation = { param ($r) $r['skillName'] = '../escape' } }
        @{ Field = 'skillSha256'; Mutation = { param ($r) $r['skillSha256'] = 'not-a-hash' } }
        @{ Field = 'timestampUtc'; Mutation = { param ($r) $r['timestampUtc'] = '30 August 2026' } }
        @{ Field = 'outcome'; Mutation = { param ($r) $r['outcome'] = 'Maybe' } }
        @{ Field = 'sessionId'; Mutation = { param ($r) $r['sessionId'] = 'b' * 200 } }
    ) {
        $record = New-Record
        & $Mutation $record
        $path = Join-Path $script:root 'bad.json'
        Write-ObservationDocument -Path $path -Document (New-Document -Record @($record))

        $result = Invoke-Import -Path $path

        @($result.Record).Count | Should -Be 0
        @($result.RejectedRecord).Count | Should -Be 1
        $result.RejectedRecord[0].Field | Should -Be $Field
    }

    It 'Should reject a document that carries an unsupported top-level property' {
        $document = New-Document -Record @(New-Record)
        $document['transcript'] = 'CANARY-TRANSCRIPT'
        $path = Join-Path $script:root 'extra.json'
        Write-ObservationDocument -Path $path -Document $document

        $result = Invoke-Import -Path $path

        @($result.RejectedFile).Count | Should -Be 1
        ($result | ConvertTo-Json -Depth 8) | Should -Not -Match 'CANARY-TRANSCRIPT'
    }

    It 'Should keep one copy of an exactly duplicated record' {
        $first = Join-Path $script:root 'a.json'
        $second = Join-Path $script:root 'b.json'
        Write-ObservationDocument -Path $first -Document (New-Document -Record @(New-Record -EventId 'same'))
        Write-ObservationDocument -Path $second -Document (New-Document -Record @(New-Record -EventId 'same'))

        $result = Invoke-Import -Path $script:root

        @($result.Record).Count | Should -Be 1
        $result.DuplicateCount | Should -Be 1
        @($result.ConflictingRecord).Count | Should -Be 0
    }

    It 'Should expose a conflicting duplicate instead of accepting one by input order' {
        $first = Join-Path $script:root 'a.json'
        $second = Join-Path $script:root 'b.json'
        Write-ObservationDocument -Path $first -Document (New-Document -Record @(New-Record -EventId 'same' -EventType 'SkillActivation'))
        Write-ObservationDocument -Path $second -Document (New-Document -Record @(New-Record -EventId 'same' -EventType 'SkillFileRead'))

        $result = Invoke-Import -Path $script:root

        @($result.Record).Count | Should -Be 0 -Because 'neither payload may win on input order'
        @($result.ConflictingRecord).Count | Should -Be 1
        $result.ConflictingRecord[0].VariantCount | Should -Be 2
        @($result.ConflictingRecord[0].Source | ForEach-Object -Process { $_.Path }) | Should -Contain $first
        @($result.ConflictingRecord[0].Source | ForEach-Object -Process { $_.Path }) | Should -Contain $second
    }

    It 'Should accept the same local identifier from two different clients' {
        Write-ObservationDocument -Path (Join-Path $script:root 'a.json') -Document (New-Document -Client 'client-a' -Record @(New-Record -EventId 'e1'))
        Write-ObservationDocument -Path (Join-Path $script:root 'b.json') -Document (New-Document -Client 'client-b' -Record @(New-Record -EventId 'e1'))

        $result = Invoke-Import -Path $script:root

        @($result.Record).Count | Should -Be 2 -Because 'an event identifier is only local to its client'
        $result.DuplicateCount | Should -Be 0
        @($result.Record | ForEach-Object -Process { $_.Client }) | Should -Contain 'client-a'
        @($result.Record | ForEach-Object -Process { $_.Client }) | Should -Contain 'client-b'
    }

    It 'Should accept the same local identifier from two different sessions' {
        Write-ObservationDocument -Path (Join-Path $script:root 'a.json') -Document (New-Document -Record @(New-Record -EventId 'e1' -SessionId 's1'))
        Write-ObservationDocument -Path (Join-Path $script:root 'b.json') -Document (New-Document -Record @(New-Record -EventId 'e1' -SessionId 's2'))

        $result = Invoke-Import -Path $script:root

        @($result.Record).Count | Should -Be 2
    }

    It 'Should preserve the import locator and client provenance on every accepted record' {
        $path = Join-Path $script:root 'ok.json'
        Write-ObservationDocument -Path $path -Document (New-Document -Record @(New-Record))

        $result = Invoke-Import -Path $path

        $result.Record[0].SourcePath | Should -Be $path
        $result.Record[0].Client | Should -Be 'vscode-copilot-chat'
        $result.Record[0].ClientVersion | Should -Be '1.105.0'
        $result.Record[0].IdentityScope | Should -Not -BeNullOrEmpty
    }

    It 'Should return the same accepted records regardless of the order the files are selected' {
        $first = Join-Path $script:root 'a.json'
        $second = Join-Path $script:root 'b.json'
        Write-ObservationDocument -Path $first -Document (New-Document -Record @(New-Record -EventId 'e1' -TimestampUtc '2026-08-30T10:00:00Z'))
        Write-ObservationDocument -Path $second -Document (New-Document -Record @(New-Record -EventId 'e2' -TimestampUtc '2026-08-29T10:00:00Z'))

        $forward = Invoke-Import -Path @($first, $second)
        $reverse = Invoke-Import -Path @($second, $first)

        ($forward.Record | ConvertTo-Json -Depth 6) | Should -Be ($reverse.Record | ConvertTo-Json -Depth 6)
    }

    It 'Should reject a document whose records member is not an array' {
        $path = Join-Path $script:root 'scalar.json'
        Set-Content -LiteralPath $path -Encoding utf8 -Value '{ "schemaVersion": 1, "client": "c", "clientVersion": "1", "trust": "Imported", "records": "one" }'

        $result = Invoke-Import -Path $path

        @($result.RejectedFile).Count | Should -Be 1
        $result.RejectedFile[0].Reason | Should -Match 'array'
        @($result.Record).Count | Should -Be 0
    }

    It 'Should reject a single record object that was not wrapped in an array' {
        $path = Join-Path $script:root 'object.json'
        Set-Content -LiteralPath $path -Encoding utf8 -Value '{ "schemaVersion": 1, "client": "c", "clientVersion": "1", "trust": "Imported", "records": { "eventId": "e1" } }'

        $result = Invoke-Import -Path $path

        @($result.RejectedFile).Count | Should -Be 1
        $result.RejectedFile[0].Reason | Should -Match 'array'
    }

    It 'Should refuse an explicitly selected file whose parent directory is a reparse point' -Skip:(-not $script:canCreateDirectoryLink) {
        $target = Join-Path $script:root 'outside'
        New-Item -ItemType Directory -Path $target -Force | Out-Null
        Write-ObservationDocument -Path (Join-Path $target 'ok.json') -Document (New-Document -Record @(New-Record))
        $link = Join-Path $script:root 'linked'
        New-Item -ItemType $script:linkItemType -Path $link -Target $target | Out-Null

        { Invoke-Import -Path (Join-Path $link 'ok.json') } | Should -Throw -ExpectedMessage '*reparse*'
    }

    It 'Should accept a validated coverage declaration and expose its window' {
        $document = New-Document -Record @(New-Record)
        $document['coverage'] = @(
            [ordered] @{
                skillName                 = 'alpha-tool'
                skillSha256               = ('a' * 64)
                windowStartUtc            = '2026-07-01T00:00:00Z'
                windowEndUtc              = '2026-08-30T00:00:00Z'
                sessionCount              = 25
                activationCaptureComplete = $true
            }
        )
        $path = Join-Path $script:root 'coverage.json'
        Write-ObservationDocument -Path $path -Document $document

        $result = Invoke-Import -Path $path

        @($result.Coverage).Count | Should -Be 1
        $result.Coverage[0].SkillName | Should -Be 'alpha-tool'
        $result.Coverage[0].ActivationCaptureComplete | Should -BeTrue
        $result.Coverage[0].SessionCount | Should -Be 25
        $result.Coverage[0].SourcePath | Should -Be $path
    }

    It 'Should reject a malformed coverage declaration without echoing its values' {
        $document = New-Document -Record @(New-Record)
        $document['coverage'] = @(
            [ordered] @{
                skillName                 = 'alpha-tool'
                skillSha256               = 'not-a-hash'
                windowStartUtc            = '2026-07-01T00:00:00Z'
                windowEndUtc              = '2026-08-30T00:00:00Z'
                sessionCount              = 25
                activationCaptureComplete = $true
                secretNote                = 'CANARY-COVERAGE'
            }
        )
        $path = Join-Path $script:root 'bad-coverage.json'
        Write-ObservationDocument -Path $path -Document $document

        $result = Invoke-Import -Path $path

        @($result.Coverage).Count | Should -Be 0
        @($result.RejectedCoverage).Count | Should -Be 1
        ($result | ConvertTo-Json -Depth 8) | Should -Not -Match 'CANARY-COVERAGE'
    }

    It 'Should read only JSON files from a selected directory' {
        Write-ObservationDocument -Path (Join-Path $script:root 'ok.json') -Document (New-Document -Record @(New-Record))
        Set-Content -LiteralPath (Join-Path $script:root 'notes.txt') -Encoding utf8 -Value 'CANARY-TEXT'

        $result = Invoke-Import -Path $script:root

        $result.FileCount | Should -Be 1
        ($result | ConvertTo-Json -Depth 8) | Should -Not -Match 'CANARY-TEXT'
    }

    It 'Should record the declared client and trust without trusting them' {
        $document = New-Document -Record @(New-Record)
        $document['trust'] = 'Observed'
        $path = Join-Path $script:root 'trust.json'
        Write-ObservationDocument -Path $path -Document $document

        $result = Invoke-Import -Path $path

        @($result.DeclaredTrust) | Should -Contain 'Observed'
        @($result.Client | ForEach-Object -Process { $_.Name }) | Should -Contain 'vscode-copilot-chat'
    }

    It 'Should throw when the selected path does not exist' {
        { Invoke-Import -Path (Join-Path $script:root 'missing') } | Should -Throw -ExpectedMessage '*does not exist*'
    }
}
