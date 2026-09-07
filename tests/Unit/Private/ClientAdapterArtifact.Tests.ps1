BeforeAll {
    $script:projectPath = Convert-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')
    . (Join-Path $script:projectPath 'tests/Helpers/DeploymentProfile.ps1')
    Import-CopilotAtelierTestModule -ProjectPath $script:projectPath

    $script:manifestName = '.copilot-atelier-adapter-manifest.json'
    $script:manifestOwner = 'CopilotAtelier/Build_Client_Adapter_Variants'

    function script:Get-FixtureHash
    {
        [CmdletBinding()]
        [OutputType([string])]
        param
        (
            [Parameter(Mandatory)]
            [string]$LiteralPath
        )

        (Get-FileHash -LiteralPath $LiteralPath -Algorithm SHA256).Hash.ToLowerInvariant()
    }

    function script:Set-ManifestFixture
    {
        [CmdletBinding()]
        param
        (
            [Parameter(Mandatory)]
            [string]$AdapterRoot,

            [Parameter()]
            [AllowNull()]
            [psobject]$File = @(),

            [Parameter()]
            [int]$Schema = 2
        )

        $manifest = [ordered] @{
            schema = $Schema
            owner  = $script:manifestOwner
            file   = $File
        }

        Set-Content -LiteralPath (Join-Path $AdapterRoot $script:manifestName) `
            -Value ($manifest | ConvertTo-Json -Depth 5) -NoNewline
    }

    function script:New-VariantFixture
    {
        [CmdletBinding()]
        [OutputType([pscustomobject])]
        param
        (
            [Parameter()]
            [string]$Client = 'copilot-cli',

            [Parameter()]
            [string]$Name = 'software-engineer',

            [Parameter()]
            [string]$Content = "---`nname: software-engineer`n---`n# Body`n"
        )

        [pscustomobject] @{
            Client   = $Client
            FileName = "$Name.agent.md"
            Content  = $Content
        }
    }

    function script:Export-Fixture
    {
        [CmdletBinding()]
        param
        (
            [Parameter(Mandatory)]
            [string]$Path,

            [Parameter(Mandatory)]
            [string]$ParentPath,

            [Parameter()]
            [psobject[]]$Variant = @(script:New-VariantFixture)
        )

        InModuleScope CopilotAtelier -Parameters @{ Path = $Path; ParentPath = $ParentPath; Variant = $Variant } {
            param ($Path, $ParentPath, $Variant)

            Export-CopilotAtelierClientAdapterArtifact -Path $Path -ParentPath $ParentPath -Variant $Variant
        }
    }
}

Describe 'Client adapter artifact ownership' -Tag 'Unit' {
    BeforeEach {
        $script:outputRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:outputRoot -Force | Out-Null
    }

    It 'Should write the variants and an ownership manifest into the owned directory' {
        $adapterRoot = Join-Path $script:outputRoot 'clientAdapters'

        $written = @(script:Export-Fixture -Path $adapterRoot -ParentPath $script:outputRoot)

        $written.Count | Should -Be 1
        Test-Path -LiteralPath (Join-Path $adapterRoot 'copilot-cli/software-engineer.agent.md') |
            Should -BeTrue

        $manifest = Get-Content -Raw -LiteralPath (Join-Path $adapterRoot $script:manifestName) |
            ConvertFrom-Json

        @($manifest.file).path | Should -Be @('copilot-cli/software-engineer.agent.md')
        $manifest.owner | Should -Match 'CopilotAtelier'
    }

    It 'Should record the content hash of every file it generated' {
        <#
            Names alone cannot tell a generated file that is still exactly as
            written apart from one a user has edited in place, so ownership has
            to carry content.
        #>
        $adapterRoot = Join-Path $script:outputRoot 'clientAdapters'

        script:Export-Fixture -Path $adapterRoot -ParentPath $script:outputRoot | Out-Null

        $manifest = Get-Content -Raw -LiteralPath (Join-Path $adapterRoot $script:manifestName) |
            ConvertFrom-Json

        $manifest.schema | Should -Be 2

        $entry = @($manifest.file)[0]
        $entry.path | Should -Be 'copilot-cli/software-engineer.agent.md'
        $entry.sha256 | Should -Match '^[0-9a-f]{64}$'
        $entry.sha256 |
            Should -Be (script:Get-FixtureHash -LiteralPath (Join-Path $adapterRoot $entry.path))
    }

    It 'Should refuse a directory that carries no ownership manifest and delete nothing' {
        <#
            Setting the subdirectory property to an existing build directory
            must never turn a rebuild into a recursive delete of unrelated
            artifacts.
        #>
        $foreignRoot = Join-Path $script:outputRoot 'foreign'
        New-Item -ItemType Directory -Path $foreignRoot -Force | Out-Null
        $keepPath = Join-Path $foreignRoot 'keep.txt'
        Set-Content -LiteralPath $keepPath -Value 'unrelated build artifact'

        { script:Export-Fixture -Path $foreignRoot -ParentPath $script:outputRoot } |
            Should -Throw -ExpectedMessage '*ownership*'

        Test-Path -LiteralPath $keepPath | Should -BeTrue
        Get-Content -Raw -LiteralPath $keepPath | Should -Match 'unrelated build artifact'
    }

    It 'Should refuse the reserved build directory <Reserved> even before it exists' -ForEach @(
        @{ Reserved = 'module' }
        @{ Reserved = 'RequiredModules' }
        @{ Reserved = 'testResults' }
    ) {
        $reservedRoot = Join-Path $script:outputRoot $Reserved

        { script:Export-Fixture -Path $reservedRoot -ParentPath $script:outputRoot } |
            Should -Throw -ExpectedMessage "*$Reserved*"

        Test-Path -LiteralPath $reservedRoot | Should -BeFalse
    }

    It 'Should refuse a path that is not a direct child of the build output directory' {
        $outside = Join-Path (Split-Path -Parent $script:outputRoot) 'outside'

        { script:Export-Fixture -Path $outside -ParentPath $script:outputRoot } | Should -Throw

        Test-Path -LiteralPath $outside | Should -BeFalse
    }

    It 'Should refuse a traversal in the adapter directory name' {
        $traversal = Join-Path $script:outputRoot '..'

        { script:Export-Fixture -Path $traversal -ParentPath $script:outputRoot } | Should -Throw

        Test-Path -LiteralPath $script:outputRoot | Should -BeTrue
    }

    It 'Should remove only the files it generated and keep a user file that appeared beside them' {
        $adapterRoot = Join-Path $script:outputRoot 'clientAdapters'
        script:Export-Fixture -Path $adapterRoot -ParentPath $script:outputRoot | Out-Null

        $userPath = Join-Path $adapterRoot 'notes.md'
        Set-Content -LiteralPath $userPath -Value 'reviewer notes'

        script:Export-Fixture -Path $adapterRoot -ParentPath $script:outputRoot | Out-Null

        Test-Path -LiteralPath $userPath | Should -BeTrue
        Get-Content -Raw -LiteralPath $userPath | Should -Match 'reviewer notes'
    }

    It 'Should remove a generated file that the current run no longer produces' {
        $adapterRoot = Join-Path $script:outputRoot 'clientAdapters'

        script:Export-Fixture -Path $adapterRoot -ParentPath $script:outputRoot -Variant @(
            script:New-VariantFixture -Name 'software-engineer'
            script:New-VariantFixture -Name 'retired-agent'
        ) | Out-Null

        Test-Path -LiteralPath (Join-Path $adapterRoot 'copilot-cli/retired-agent.agent.md') | Should -BeTrue

        script:Export-Fixture -Path $adapterRoot -ParentPath $script:outputRoot | Out-Null

        Test-Path -LiteralPath (Join-Path $adapterRoot 'copilot-cli/retired-agent.agent.md') |
            Should -BeFalse -Because 'a stale variant is drift, and it is owned, so it is removed'
        Test-Path -LiteralPath (Join-Path $adapterRoot 'copilot-cli/software-engineer.agent.md') | Should -BeTrue
    }

    It 'Should stay inside a redirected output directory' {
        $redirected = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $redirected -Force | Out-Null
        $sibling = Join-Path $script:outputRoot 'sibling.txt'
        Set-Content -LiteralPath $sibling -Value 'untouched'

        $adapterRoot = Join-Path $redirected 'clientAdapters'
        $written = @(script:Export-Fixture -Path $adapterRoot -ParentPath $redirected)

        foreach ($path in $written)
        {
            $path | Should -BeLike (Join-Path $redirected '*')
        }

        Test-Path -LiteralPath $sibling | Should -BeTrue
    }

    It 'Should refuse a variant whose file name is not a plain agent file name' {
        $adapterRoot = Join-Path $script:outputRoot 'clientAdapters'
        $variant = script:New-VariantFixture
        $variant.FileName = '../escape.agent.md'

        { script:Export-Fixture -Path $adapterRoot -ParentPath $script:outputRoot -Variant @($variant) } |
            Should -Throw

        Test-Path -LiteralPath (Join-Path $script:outputRoot 'escape.agent.md') | Should -BeFalse
    }

    It 'Should refuse a manifest entry that escapes the owned directory' {
        $adapterRoot = Join-Path $script:outputRoot 'clientAdapters'
        script:Export-Fixture -Path $adapterRoot -ParentPath $script:outputRoot | Out-Null

        $outsidePath = Join-Path $script:outputRoot 'victim.txt'
        Set-Content -LiteralPath $outsidePath -Value 'not ours'

        script:Set-ManifestFixture -AdapterRoot $adapterRoot -File @(
            [pscustomobject] @{ path = '../victim.txt'; sha256 = ('0' * 64) }
        )

        { script:Export-Fixture -Path $adapterRoot -ParentPath $script:outputRoot } | Should -Throw

        Test-Path -LiteralPath $outsidePath | Should -BeTrue
    }

    It 'Should refuse an adapter directory that is a reparse point' -Skip:(-not $IsWindows -or -not ([Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        $target = Join-Path $script:outputRoot 'target'
        New-Item -ItemType Directory -Path $target -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $target 'keep.txt') -Value 'linked content'

        $adapterRoot = Join-Path $script:outputRoot 'clientAdapters'
        New-Item -ItemType SymbolicLink -Path $adapterRoot -Target $target -ErrorAction Stop | Out-Null

        { script:Export-Fixture -Path $adapterRoot -ParentPath $script:outputRoot } | Should -Throw

        Test-Path -LiteralPath (Join-Path $target 'keep.txt') | Should -BeTrue
    }
}

Describe 'Client adapter artifact whole-operation validation' -Tag 'Unit' {
    BeforeEach {
        $script:outputRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:outputRoot -Force | Out-Null
    }

    It 'Should refuse a late unsafe manifest entry without having deleted the earlier ones' {
        <#
            Validating and deleting one entry at a time means a valid first
            entry is already gone by the time an unsafe second entry is
            refused. The tree has to be unchanged, not just the error thrown.
        #>
        $adapterRoot = Join-Path $script:outputRoot 'clientAdapters'
        script:Export-Fixture -Path $adapterRoot -ParentPath $script:outputRoot -Variant @(
            script:New-VariantFixture -Name 'first-agent'
            script:New-VariantFixture -Name 'second-agent'
        ) | Out-Null

        $firstPath = Join-Path $adapterRoot 'copilot-cli/first-agent.agent.md'
        $secondPath = Join-Path $adapterRoot 'copilot-cli/second-agent.agent.md'

        script:Set-ManifestFixture -AdapterRoot $adapterRoot -File @(
            [pscustomobject] @{
                path   = 'copilot-cli/first-agent.agent.md'
                sha256 = script:Get-FixtureHash -LiteralPath $firstPath
            }
            [pscustomobject] @{ path = '../victim.txt'; sha256 = ('0' * 64) }
        )

        { script:Export-Fixture -Path $adapterRoot -ParentPath $script:outputRoot } | Should -Throw

        Test-Path -LiteralPath $firstPath |
            Should -BeTrue -Because 'the whole operation is validated before the first delete'
        Test-Path -LiteralPath $secondPath | Should -BeTrue
    }

    It 'Should refuse two variants that target the same destination and write nothing' {
        $adapterRoot = Join-Path $script:outputRoot 'clientAdapters'

        {
            script:Export-Fixture -Path $adapterRoot -ParentPath $script:outputRoot -Variant @(
                script:New-VariantFixture
                script:New-VariantFixture -Content "---`nname: other`n---`n# Other`n"
            )
        } | Should -Throw -ExpectedMessage '*target*'

        Test-Path -LiteralPath $adapterRoot |
            Should -BeFalse -Because 'a rejected request creates nothing at all'
    }

    It 'Should refuse a variant that carries no string content and write nothing' {
        $adapterRoot = Join-Path $script:outputRoot 'clientAdapters'
        $variant = script:New-VariantFixture
        $variant.Content = $null

        { script:Export-Fixture -Path $adapterRoot -ParentPath $script:outputRoot -Variant @($variant) } |
            Should -Throw -ExpectedMessage '*content*'

        Test-Path -LiteralPath $adapterRoot | Should -BeFalse
    }

    It 'Should refuse a manifest that lists the same file twice' {
        $adapterRoot = Join-Path $script:outputRoot 'clientAdapters'
        script:Export-Fixture -Path $adapterRoot -ParentPath $script:outputRoot | Out-Null

        $generated = Join-Path $adapterRoot 'copilot-cli/software-engineer.agent.md'
        $hash = script:Get-FixtureHash -LiteralPath $generated

        script:Set-ManifestFixture -AdapterRoot $adapterRoot -File @(
            [pscustomobject] @{ path = 'copilot-cli/software-engineer.agent.md'; sha256 = $hash }
            [pscustomobject] @{ path = 'copilot-cli/software-engineer.agent.md'; sha256 = $hash }
        )

        { script:Export-Fixture -Path $adapterRoot -ParentPath $script:outputRoot } |
            Should -Throw -ExpectedMessage '*more than once*'

        Test-Path -LiteralPath $generated | Should -BeTrue
    }

    It 'Should refuse a manifest whose file list is not a list of hashed entries: <Case>' -ForEach @(
        @{ Case = 'a bare string'; File = 'copilot-cli/software-engineer.agent.md' }
        @{ Case = 'names without hashes'; File = @('copilot-cli/software-engineer.agent.md') }
        @{ Case = 'an entry with no hash'; File = @([pscustomobject] @{ path = 'copilot-cli/software-engineer.agent.md' }) }
        @{ Case = 'an entry with no path'; File = @([pscustomobject] @{ sha256 = ('0' * 64) }) }
        @{ Case = 'a truncated hash'; File = @([pscustomobject] @{ path = 'copilot-cli/software-engineer.agent.md'; sha256 = 'abc' }) }
    ) {
        $adapterRoot = Join-Path $script:outputRoot 'clientAdapters'
        script:Export-Fixture -Path $adapterRoot -ParentPath $script:outputRoot | Out-Null

        $generated = Join-Path $adapterRoot 'copilot-cli/software-engineer.agent.md'
        script:Set-ManifestFixture -AdapterRoot $adapterRoot -File $File

        { script:Export-Fixture -Path $adapterRoot -ParentPath $script:outputRoot } | Should -Throw

        Test-Path -LiteralPath $generated | Should -BeTrue
    }
}

Describe 'Client adapter artifact content ownership' -Tag 'Unit' {
    BeforeEach {
        $script:outputRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:outputRoot -Force | Out-Null
    }

    It 'Should refuse to delete or overwrite a generated file that was edited in place' {
        $adapterRoot = Join-Path $script:outputRoot 'clientAdapters'
        script:Export-Fixture -Path $adapterRoot -ParentPath $script:outputRoot | Out-Null

        $generated = Join-Path $adapterRoot 'copilot-cli/software-engineer.agent.md'
        [System.IO.File]::WriteAllText($generated, 'a local edit worth keeping', [System.Text.UTF8Encoding]::new($false))

        { script:Export-Fixture -Path $adapterRoot -ParentPath $script:outputRoot } |
            Should -Throw -ExpectedMessage '*modified*'

        [System.IO.File]::ReadAllText($generated) | Should -BeExactly 'a local edit worth keeping'
    }

    It 'Should refuse an unowned file that collides with a generated variant: <Case>' -ForEach @(
        @{ Case = 'identical content'; Identical = $true }
        @{ Case = 'different content'; Identical = $false }
    ) {
        <#
            A destination that was never generated is a user's file no matter
            what it contains. Adopting an identical one is the same silent
            ownership grab as overwriting a different one.
        #>
        $adapterRoot = Join-Path $script:outputRoot 'clientAdapters'
        script:Export-Fixture -Path $adapterRoot -ParentPath $script:outputRoot -Variant @(
            script:New-VariantFixture -Name 'other-agent'
        ) | Out-Null

        $variant = script:New-VariantFixture
        $collisionText = if ($Identical) { $variant.Content } else { 'a user file that happened to land here' }
        $collision = Join-Path $adapterRoot 'copilot-cli/software-engineer.agent.md'
        [System.IO.File]::WriteAllText($collision, $collisionText, [System.Text.UTF8Encoding]::new($false))

        { script:Export-Fixture -Path $adapterRoot -ParentPath $script:outputRoot -Variant @($variant) } |
            Should -Throw -ExpectedMessage '*ownership manifest*'

        [System.IO.File]::ReadAllText($collision) | Should -BeExactly $collisionText
    }

    It 'Should still remove an untouched generated file the current run no longer produces' {
        $adapterRoot = Join-Path $script:outputRoot 'clientAdapters'
        script:Export-Fixture -Path $adapterRoot -ParentPath $script:outputRoot -Variant @(
            script:New-VariantFixture
            script:New-VariantFixture -Name 'retired-agent'
        ) | Out-Null

        $unrelated = Join-Path $adapterRoot 'copilot-cli/reviewer-notes.md'
        Set-Content -LiteralPath $unrelated -Value 'kept' -NoNewline

        script:Export-Fixture -Path $adapterRoot -ParentPath $script:outputRoot | Out-Null

        Test-Path -LiteralPath (Join-Path $adapterRoot 'copilot-cli/retired-agent.agent.md') | Should -BeFalse
        Test-Path -LiteralPath $unrelated | Should -BeTrue
        Get-Content -Raw -LiteralPath $unrelated | Should -BeExactly 'kept'
    }

    It 'Should refuse a legacy names-only manifest and name a migration path' {
        <#
            Adopting the names in a schema 1 manifest would take ownership of
            whatever happens to sit at those paths now, which is exactly the
            proof that is missing.
        #>
        $adapterRoot = Join-Path $script:outputRoot 'clientAdapters'
        script:Export-Fixture -Path $adapterRoot -ParentPath $script:outputRoot | Out-Null

        $generated = Join-Path $adapterRoot 'copilot-cli/software-engineer.agent.md'
        $before = [System.IO.File]::ReadAllText($generated)

        script:Set-ManifestFixture -AdapterRoot $adapterRoot -Schema 1 -File @(
            'copilot-cli/software-engineer.agent.md'
        )

        { script:Export-Fixture -Path $adapterRoot -ParentPath $script:outputRoot } |
            Should -Throw -ExpectedMessage '*schema 1*'

        [System.IO.File]::ReadAllText($generated) | Should -BeExactly $before
    }
}

Describe 'Client adapter artifact ancestor path guarding' -Tag 'Unit' {
    BeforeEach {
        $script:outputRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:outputRoot -Force | Out-Null
    }

    It 'Should refuse a client directory that is a reparse point and change nothing behind it' -Skip:(-not $IsWindows -or -not ([Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        <#
            The owned root and the file leaf were guarded, but the client
            directory between them was not, so a link there redirected both the
            delete and the write outside the owned tree.
        #>
        $adapterRoot = Join-Path $script:outputRoot 'clientAdapters'
        New-Item -ItemType Directory -Path $adapterRoot -Force | Out-Null
        script:Set-ManifestFixture -AdapterRoot $adapterRoot -File @()

        $external = Join-Path $script:outputRoot 'external'
        New-Item -ItemType Directory -Path $external -Force | Out-Null
        $victim = Join-Path $external 'software-engineer.agent.md'
        Set-Content -LiteralPath $victim -Value 'external content' -NoNewline

        New-Item -ItemType SymbolicLink -Path (Join-Path $adapterRoot 'copilot-cli') -Target $external -ErrorAction Stop | Out-Null

        { script:Export-Fixture -Path $adapterRoot -ParentPath $script:outputRoot } | Should -Throw

        Get-Content -Raw -LiteralPath $victim | Should -BeExactly 'external content'
        @(Get-ChildItem -LiteralPath $external -Force).Count | Should -Be 1
    }

    It 'Should refuse an ownership manifest that is a reparse point' -Skip:(-not $IsWindows -or -not ([Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        $adapterRoot = Join-Path $script:outputRoot 'clientAdapters'
        New-Item -ItemType Directory -Path $adapterRoot -Force | Out-Null

        $external = Join-Path $script:outputRoot 'external-manifest.json'
        $externalText = '{"schema":2,"owner":"CopilotAtelier/Build_Client_Adapter_Variants","file":[]}'
        Set-Content -LiteralPath $external -Value $externalText -NoNewline

        New-Item -ItemType SymbolicLink -Path (Join-Path $adapterRoot $script:manifestName) -Target $external -ErrorAction Stop | Out-Null

        { script:Export-Fixture -Path $adapterRoot -ParentPath $script:outputRoot } | Should -Throw

        Get-Content -Raw -LiteralPath $external | Should -BeExactly $externalText
    }

    It 'Should refuse to clean a stale generated file that now sits behind a link' -Skip:(-not $IsWindows -or -not ([Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        $adapterRoot = Join-Path $script:outputRoot 'clientAdapters'
        New-Item -ItemType Directory -Path $adapterRoot -Force | Out-Null

        $external = Join-Path $script:outputRoot 'external'
        New-Item -ItemType Directory -Path $external -Force | Out-Null
        $victim = Join-Path $external 'retired-agent.agent.md'
        Set-Content -LiteralPath $victim -Value 'external content' -NoNewline

        New-Item -ItemType SymbolicLink -Path (Join-Path $adapterRoot 'copilot-cli') -Target $external -ErrorAction Stop | Out-Null

        # The recorded hash matches, so the refusal can only come from the link.
        script:Set-ManifestFixture -AdapterRoot $adapterRoot -File @(
            [pscustomobject] @{
                path   = 'copilot-cli/retired-agent.agent.md'
                sha256 = script:Get-FixtureHash -LiteralPath $victim
            }
        )

        { script:Export-Fixture -Path $adapterRoot -ParentPath $script:outputRoot } | Should -Throw

        Test-Path -LiteralPath $victim | Should -BeTrue
        Get-Content -Raw -LiteralPath $victim | Should -BeExactly 'external content'
    }
}
