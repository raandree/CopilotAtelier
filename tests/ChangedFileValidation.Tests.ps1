BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:skillRoot = Join-Path $script:repoRoot 'skills/changed-file-validation'
    $script:scriptRoot = Join-Path $script:skillRoot 'scripts'
    $script:addScript = Join-Path $script:scriptRoot 'Add-ChangedFile.ps1'
    $script:getScript = Join-Path $script:scriptRoot 'Get-ChangedFileBatch.ps1'
    $script:invokeScript = Join-Path $script:scriptRoot 'Invoke-ChangedFileValidation.ps1'
    $script:clearScript = Join-Path $script:scriptRoot 'Clear-ChangedFileBatch.ps1'
    $script:commonScript = Join-Path $script:scriptRoot 'ChangedFileValidationCommon.ps1'
    $script:skillBodyPath = Join-Path $script:skillRoot 'SKILL.md'
    $script:evalFixturePath = Join-Path $script:skillRoot 'evals/validation-cases.json'

    $script:storeRelativePath = '.copilot-atelier/changed-file-validation/batches.json'
    $script:lockRelativePath = '.copilot-atelier/changed-file-validation/.batches.lock'
    $script:isWindowsHost = $env:OS -eq 'Windows_NT'
    $script:supportsArgumentList = $PSVersionTable.PSVersion.Major -ge 6
    $script:hostExecutable = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    $script:hasScriptAnalyzer = [bool] (
        Get-Module -Name PSScriptAnalyzer -ListAvailable -ErrorAction SilentlyContinue
    )

    function Set-ValidationFile
    {
        [CmdletBinding()]
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            'PSUseShouldProcessForStateChangingFunctions',
            '',
            Justification = 'Pester fixture helper writes only isolated test data.'
        )]
        param
        (
            [Parameter(Mandatory)]
            [string]$Root,

            [Parameter(Mandatory)]
            [string]$RelativePath,

            [Parameter(Mandatory)]
            [AllowEmptyString()]
            [string]$Content
        )

        $full = Join-Path $Root ($RelativePath -replace '/', [IO.Path]::DirectorySeparatorChar)
        $parent = Split-Path -Parent $full
        if (-not (Test-Path -LiteralPath $parent -PathType Container))
        {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }

        # Exact bytes matter: the trailing-newline rule and every content hash in
        # this suite are assertions about the file as it is written to disk.
        [IO.File]::WriteAllText($full, $Content, [Text.UTF8Encoding]::new($false))
        return $full
    }

    function New-ValidationFixture
    {
        [CmdletBinding()]
        [OutputType([string])]
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            'PSUseShouldProcessForStateChangingFunctions',
            '',
            Justification = 'Pester fixture helper writes only isolated test data.'
        )]
        param ()

        $root = Join-Path ([IO.Path]::GetTempPath()) (
            'changed-file-{0}' -f [guid]::NewGuid().ToString('N')
        )
        New-Item -ItemType Directory -Path $root -Force | Out-Null

        Set-ValidationFile -Root $root -RelativePath 'source/Good.ps1' -Content @'
function Get-Good
{
    [CmdletBinding()]
    [OutputType([int])]
    param ()

    return 1
}

'@ | Out-Null

        Set-ValidationFile -Root $root -RelativePath 'source/Broken.ps1' -Content @'
function Get-Broken
{
    if ($true
}

'@ | Out-Null

        Set-ValidationFile -Root $root -RelativePath 'docs/good.md' -Content "# Title`n`nBody text.`n" | Out-Null
        Set-ValidationFile -Root $root -RelativePath 'docs/no-newline.md' -Content "# Title`n`nBody text." | Out-Null
        Set-ValidationFile -Root $root -RelativePath 'assets/logo.bin' -Content 'not a validated type' | Out-Null

        return $root
    }

    function Get-ValidationFullPath
    {
        [CmdletBinding()]
        [OutputType([string])]
        param
        (
            [Parameter(Mandatory)]
            [string]$Root,

            [Parameter(Mandatory)]
            [string]$RelativePath
        )

        return Join-Path $Root ($RelativePath -replace '/', [IO.Path]::DirectorySeparatorChar)
    }

    function Remove-ValidationFixture
    {
        [CmdletBinding()]
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            'PSUseShouldProcessForStateChangingFunctions',
            '',
            Justification = 'Pester fixture helper removes only isolated test data.'
        )]
        param
        (
            [Parameter(Mandatory)]
            [AllowEmptyString()]
            [string]$Root
        )

        if (-not [string]::IsNullOrWhiteSpace($Root) -and (Test-Path -LiteralPath $Root))
        {
            Remove-Item -LiteralPath $Root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    function Get-DirectorySnapshot
    {
        [CmdletBinding()]
        [OutputType([string])]
        param
        (
            [Parameter(Mandatory)]
            [string]$Root
        )

        return (
            Get-ChildItem -LiteralPath $Root -Recurse -File -Force |
                Sort-Object -Property FullName |
                ForEach-Object -Process {
                    '{0}|{1}|{2}' -f $_.FullName, $_.Length, $_.LastWriteTimeUtc.Ticks
                }
        ) -join "`n"
    }

    <#
        A fixture that speaks the markdownlint-cli interface: it answers
        --version, records the argument vector it was handed, and can report one
        diagnostic. It exists to prove the integration path, never to stand in
        for markdownlint's rule coverage.
    #>
    function New-StubMarkdownLint
    {
        [CmdletBinding()]
        [OutputType([string])]
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            'PSUseShouldProcessForStateChangingFunctions',
            '',
            Justification = 'Pester fixture helper writes only isolated test data.'
        )]
        param
        (
            [Parameter(Mandatory)]
            [string]$Directory,

            [Parameter(Mandatory)]
            [string]$MarkerPath,

            [Parameter()]
            [AllowEmptyString()]
            [string]$DiagnosticLine = '',

            [Parameter()]
            [int]$ExitCode = 0,

            [Parameter()]
            [string]$Version = '0.44.0'
        )

        if (-not (Test-Path -LiteralPath $Directory -PathType Container))
        {
            New-Item -ItemType Directory -Path $Directory -Force | Out-Null
        }

        if ($script:isWindowsHost)
        {
            $stub = Join-Path $Directory 'stub-markdownlint.cmd'
            $text = @"
@echo off
if "%~1"=="--version" (
  echo $Version
  exit /b 0
)
>>"$MarkerPath" echo %*
if not "$DiagnosticLine"=="" echo $DiagnosticLine
exit /b $ExitCode
"@
            [IO.File]::WriteAllText($stub, ($text -replace "\r?\n", "`r`n"), [Text.UTF8Encoding]::new($false))
            return $stub
        }

        $stub = Join-Path $Directory 'stub-markdownlint'
        $text = @"
#!/bin/sh
if [ "`$1" = "--version" ]; then
  echo $Version
  exit 0
fi
printf '%s\n' "`$*" >> "$MarkerPath"
if [ -n "$DiagnosticLine" ]; then
  echo "$DiagnosticLine"
fi
exit $ExitCode
"@
        [IO.File]::WriteAllText($stub, ($text -replace "\r?\n", "`n"), [Text.UTF8Encoding]::new($false))
        & chmod '+x' $stub
        return $stub
    }

    function Edit-ValidationReceipt
    {
        [CmdletBinding()]
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            'PSUseShouldProcessForStateChangingFunctions',
            '',
            Justification = 'Pester fixture helper writes only isolated test data.'
        )]
        param
        (
            [Parameter(Mandatory)]
            [string]$Root,

            [Parameter(Mandatory)]
            [string]$RelativePath,

            [Parameter(Mandatory)]
            [scriptblock]$Change,

            [Parameter()]
            [string]$SessionId = 'default'
        )

        $storePath = Join-Path $Root (
            $script:storeRelativePath -replace '/', [IO.Path]::DirectorySeparatorChar
        )
        $store = Get-Content -LiteralPath $storePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $entry = @($store.sessions.$SessionId.entries) |
            Where-Object { $_.path -eq $RelativePath } |
            Select-Object -First 1

        & $Change $entry.receipt

        [IO.File]::WriteAllText(
            $storePath,
            ($store | ConvertTo-Json -Depth 12),
            [Text.UTF8Encoding]::new($false)
        )
    }
}

Describe 'Changed-file batch collection' -Tag 'Unit' {
    BeforeEach {
        $script:root = New-ValidationFixture
    }

    AfterEach {
        Remove-ValidationFixture -Root $script:root
    }

    It 'collects a changed file once and counts repeated edits' {
        & $script:addScript -Path $script:root -ChangedPath 'source/Good.ps1' | Out-Null
        & $script:addScript -Path $script:root -ChangedPath 'source/Good.ps1' | Out-Null
        $result = @(& $script:addScript -Path $script:root -ChangedPath 'source/Good.ps1')

        $result | Should -HaveCount 1
        $result[0].Occurrences | Should -Be 3

        $batch = @(& $script:getScript -Path $script:root)
        $batch | Should -HaveCount 1
        $batch[0].RelativePath | Should -Be 'source/Good.ps1'
        $batch[0].Occurrences | Should -Be 3
    }

    It 'normalizes an absolute path and a backslash path onto one entry' {
        & $script:addScript -Path $script:root -ChangedPath (
            Get-ValidationFullPath -Root $script:root -RelativePath 'source/Good.ps1'
        ) | Out-Null
        & $script:addScript -Path $script:root -ChangedPath 'source\Good.ps1' | Out-Null

        $batch = @(& $script:getScript -Path $script:root)
        $batch | Should -HaveCount 1
        $batch[0].RelativePath | Should -Be 'source/Good.ps1'
        $batch[0].Occurrences | Should -Be 2
    }

    It 'keeps two sessions isolated' {
        & $script:addScript -Path $script:root -ChangedPath 'source/Good.ps1' -SessionId 'alpha' | Out-Null
        & $script:addScript -Path $script:root -ChangedPath 'docs/good.md' -SessionId 'beta' | Out-Null

        @(& $script:getScript -Path $script:root -SessionId 'alpha').RelativePath |
            Should -Be 'source/Good.ps1'
        @(& $script:getScript -Path $script:root -SessionId 'beta').RelativePath |
            Should -Be 'docs/good.md'
        @(& $script:getScript -Path $script:root -AllSession) | Should -HaveCount 2
    }

    It 'clears one session without touching the other' {
        & $script:addScript -Path $script:root -ChangedPath 'source/Good.ps1' -SessionId 'alpha' | Out-Null
        & $script:addScript -Path $script:root -ChangedPath 'docs/good.md' -SessionId 'beta' | Out-Null

        & $script:clearScript -Path $script:root -SessionId 'alpha' | Out-Null

        @(& $script:getScript -Path $script:root -SessionId 'alpha') | Should -HaveCount 0
        @(& $script:getScript -Path $script:root -SessionId 'beta') | Should -HaveCount 1
    }

    It 'loses no entry when separate processes collect concurrently' {
        $expected = 1..4 | ForEach-Object -Process { 'source/Concurrent{0}.ps1' -f $_ }
        foreach ($relative in $expected)
        {
            Set-ValidationFile -Root $script:root -RelativePath $relative -Content "function Get-C { return 1 }`n" |
                Out-Null
        }

        $process = foreach ($relative in $expected)
        {
            Start-Process -FilePath $script:hostExecutable -PassThru -NoNewWindow -ArgumentList @(
                '-NoProfile'
                '-NonInteractive'
                '-File'
                $script:addScript
                '-Path'
                $script:root
                '-ChangedPath'
                $relative
                '-SessionId'
                'shared'
            )
        }

        $process | Wait-Process -Timeout 120
        @($process | Where-Object { $_.ExitCode -ne 0 }) |
            Should -HaveCount 0 -Because 'a contended collector must retry, not fail'

        $batch = @(& $script:getScript -Path $script:root -SessionId 'shared')
        @($batch.RelativePath | Sort-Object) |
            Should -Be @($expected | Sort-Object) -Because 'a lost update silently drops a file from the batch'
    }

    It 'records an unsupported file type explicitly and never as verified' {
        $result = @(& $script:addScript -Path $script:root -ChangedPath 'assets/logo.bin')

        $result[0].State | Should -Be 'Unsupported'

        $batch = @(& $script:getScript -Path $script:root)
        $batch[0].Supported | Should -BeFalse
        $batch[0].ValidationState | Should -Be 'Unsupported'
        $batch[0].Verified | Should -BeFalse
    }

    It 'records a deleted file as missing and never as verified' {
        & $script:addScript -Path $script:root -ChangedPath 'source/Good.ps1' | Out-Null
        Remove-Item -LiteralPath (Get-ValidationFullPath -Root $script:root -RelativePath 'source/Good.ps1') -Force

        $batch = @(& $script:getScript -Path $script:root)
        $batch[0].FileState | Should -Be 'Missing'
        $batch[0].ValidationState | Should -Be 'Missing'
        $batch[0].Verified | Should -BeFalse
    }

    It 'treats a rename as a deleted path plus a new one' {
        & $script:addScript -Path $script:root -ChangedPath 'source/Good.ps1' | Out-Null
        Move-Item `
            -LiteralPath (Get-ValidationFullPath -Root $script:root -RelativePath 'source/Good.ps1') `
            -Destination (Get-ValidationFullPath -Root $script:root -RelativePath 'source/Renamed.ps1')
        & $script:addScript -Path $script:root -ChangedPath 'source/Renamed.ps1' | Out-Null

        $batch = @(& $script:getScript -Path $script:root | Sort-Object -Property RelativePath)
        $batch | Should -HaveCount 2
        ($batch | Where-Object { $_.RelativePath -eq 'source/Good.ps1' }).FileState | Should -Be 'Missing'
        ($batch | Where-Object { $_.RelativePath -eq 'source/Renamed.ps1' }).FileState | Should -Be 'Present'
    }

    It 'refuses a path outside the selected root' {
        $outside = Join-Path ([IO.Path]::GetTempPath()) ('outside-{0}.ps1' -f [guid]::NewGuid().ToString('N'))
        [IO.File]::WriteAllText($outside, "function Get-Outside { return 1 }`n")

        try
        {
            { & $script:addScript -Path $script:root -ChangedPath $outside -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*inside the selected project*'
        }
        finally
        {
            Remove-Item -LiteralPath $outside -Force -ErrorAction SilentlyContinue
        }
    }

    It 'refuses <Reason>' -ForEach @(
        @{ Reason = 'a traversal segment'; ChangedPath = '../escape.ps1' }
        @{ Reason = 'an embedded traversal segment'; ChangedPath = 'source/../../escape.ps1' }
        @{ Reason = 'a whitespace path'; ChangedPath = '   ' }
    ) {
        { & $script:addScript -Path $script:root -ChangedPath $ChangedPath -ErrorAction Stop } |
            Should -Throw
    }

    It 'refuses a session identifier that could escape the store' -ForEach @(
        @{ SessionId = '../evil' }
        @{ SessionId = 'a/b' }
        @{ SessionId = '' }
        @{ SessionId = ('x' * 200) }
    ) {
        { & $script:addScript -Path $script:root -ChangedPath 'source/Good.ps1' -SessionId $SessionId -ErrorAction Stop } |
            Should -Throw
    }

    It 'refuses a path reached through a reparse point' {
        $outsideRoot = Join-Path ([IO.Path]::GetTempPath()) ('outside-{0}' -f [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $outsideRoot -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $outsideRoot 'Sneak.ps1'), "function Get-Sneak { return 1 }`n")

        $linkPath = Join-Path $script:root 'linked'
        $linkType = if ($script:isWindowsHost) { 'Junction' } else { 'SymbolicLink' }

        try
        {
            New-Item -ItemType $linkType -Path $linkPath -Value $outsideRoot -ErrorAction Stop | Out-Null
        }
        catch
        {
            Set-ItResult -Skipped -Because 'this host cannot create a link without elevation'
            return
        }

        try
        {
            { & $script:addScript -Path $script:root -ChangedPath 'linked/Sneak.ps1' -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*reparse point*'
        }
        finally
        {
            Remove-Item -LiteralPath $linkPath -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $outsideRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'fails closed on a store that was corrupted by hand' {
        & $script:addScript -Path $script:root -ChangedPath 'source/Good.ps1' | Out-Null
        $storePath = Get-ValidationFullPath -Root $script:root -RelativePath $script:storeRelativePath
        [IO.File]::WriteAllText($storePath, '{ not json')

        { & $script:getScript -Path $script:root -ErrorAction Stop } | Should -Throw
    }

    It 'fails closed on a store recorded against another project' {
        & $script:addScript -Path $script:root -ChangedPath 'source/Good.ps1' | Out-Null
        $storePath = Get-ValidationFullPath -Root $script:root -RelativePath $script:storeRelativePath
        $store = Get-Content -LiteralPath $storePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $store.repositoryRoot = Join-Path ([IO.Path]::GetTempPath()) 'some-other-project'
        [IO.File]::WriteAllText($storePath, ($store | ConvertTo-Json -Depth 12))

        { & $script:getScript -Path $script:root -ErrorAction Stop } |
            Should -Throw -ExpectedMessage '*does not match the selected project*'
    }
}

Describe 'Changed-file validation' -Tag 'Unit' {
    BeforeEach {
        $script:root = New-ValidationFixture
    }

    AfterEach {
        Remove-ValidationFixture -Root $script:root
    }

    It 'validates a well-formed script and records the content it checked' {
        & $script:addScript -Path $script:root -ChangedPath 'source/Good.ps1' | Out-Null
        $result = @(& $script:invokeScript -Path $script:root)

        $result | Should -HaveCount 1
        $result[0].Action | Should -Be 'Validated'
        $result[0].ContentSha256 | Should -Match '^[0-9a-f]{64}$'

        $parse = $result[0].Checks | Where-Object { $_.Validator -eq 'PowerShell.Parse' }
        $parse | Should -Not -BeNullOrEmpty
        $parse.Outcome | Should -Be 'Passed'
        $parse.Version | Should -Not -BeNullOrEmpty
        $parse.ConfigIdentity | Should -Not -BeNullOrEmpty

        $expectedState = if ($script:hasScriptAnalyzer) { 'Verified' } else { 'Incomplete' }
        $result[0].ValidationState | Should -Be $expectedState
    }

    It 'reports a parse error with its location and never as verified' {
        & $script:addScript -Path $script:root -ChangedPath 'source/Broken.ps1' | Out-Null
        $result = @(& $script:invokeScript -Path $script:root)

        $result[0].ValidationState | Should -Be 'Failed'
        $result[0].Verified | Should -BeFalse

        $parse = $result[0].Checks | Where-Object { $_.Validator -eq 'PowerShell.Parse' }
        $parse.Outcome | Should -Be 'Failed'
        @($parse.Diagnostics).Count | Should -BeGreaterThan 0
        @($parse.Diagnostics)[0].Line | Should -BeGreaterThan 0
        @($parse.Diagnostics)[0].Message | Should -Not -BeNullOrEmpty
    }

    It 'checks each unchanged supported file once per batch' {
        & $script:addScript -Path $script:root -ChangedPath 'source/Good.ps1' | Out-Null
        @(& $script:invokeScript -Path $script:root)[0].Action | Should -Be 'Validated'

        $second = @(& $script:invokeScript -Path $script:root)
        $second[0].Action | Should -Be 'Reused'

        $forced = @(& $script:invokeScript -Path $script:root -Force)
        $forced[0].Action | Should -Be 'Validated'
    }

    It 'never reuses a successful receipt for content that changed afterwards' {
        & $script:addScript -Path $script:root -ChangedPath 'source/Good.ps1' | Out-Null
        $first = @(& $script:invokeScript -Path $script:root)
        $first[0].ValidationState | Should -BeIn @('Verified', 'Incomplete')

        Set-ValidationFile -Root $script:root -RelativePath 'source/Good.ps1' -Content @'
function Get-Good
{
    if ($true
}

'@ | Out-Null

        $stale = @(& $script:getScript -Path $script:root)
        $stale[0].ValidationState | Should -Be 'Stale'
        $stale[0].Verified | Should -BeFalse

        $revalidated = @(& $script:invokeScript -Path $script:root)
        $revalidated[0].Action | Should -Be 'Validated'
        $revalidated[0].ValidationState | Should -Be 'Failed'
    }

    It 'reports a markdown file that breaks the enforced trailing-newline rule' {
        & $script:addScript -Path $script:root -ChangedPath 'docs/no-newline.md' | Out-Null
        $result = @(& $script:invokeScript -Path $script:root)

        $structure = $result[0].Checks | Where-Object { $_.Validator -eq 'Markdown.NativeStructure' }
        $structure.Outcome | Should -Be 'Failed'
        @($structure.Diagnostics).RuleId | Should -Contain 'MD047'
    }

    It 'accepts a well-formed markdown file' {
        & $script:addScript -Path $script:root -ChangedPath 'docs/good.md' | Out-Null
        $result = @(& $script:invokeScript -Path $script:root)

        $structure = $result[0].Checks | Where-Object { $_.Validator -eq 'Markdown.NativeStructure' }
        $structure.Outcome | Should -Be 'Passed'
    }

    It 'keeps a configured but unresolvable markdown linter fail-closed' {
        & $script:addScript -Path $script:root -ChangedPath 'docs/good.md' | Out-Null
        $result = @(
            & $script:invokeScript -Path $script:root -MarkdownLintPath (
                'no-such-linter-{0}' -f [guid]::NewGuid().ToString('N')
            )
        )

        $lint = $result[0].Checks | Where-Object { $_.Validator -eq 'Markdown.Lint' }
        $lint | Should -Not -BeNullOrEmpty
        $lint.Outcome | Should -Be 'Unavailable'
        $result[0].ValidationState | Should -Be 'Incomplete'
        $result[0].Verified | Should -BeFalse
    }

    It 'reports an unterminated frontmatter fence' {
        Set-ValidationFile -Root $script:root -RelativePath 'docs/broken.md' -Content "---`nname: x`n`n# Title`n" |
            Out-Null
        & $script:addScript -Path $script:root -ChangedPath 'docs/broken.md' | Out-Null

        $result = @(& $script:invokeScript -Path $script:root)
        $structure = $result[0].Checks | Where-Object { $_.Validator -eq 'Markdown.NativeStructure' }
        @($structure.Diagnostics).RuleId | Should -Contain 'CFV001'
    }

    It 'passes a hostile filename through as data and never executes it' {
        $hostile = 'source/$(New-Item -Path evidence.txt -ItemType File) `x [a].ps1'
        Set-ValidationFile -Root $script:root -RelativePath $hostile -Content "function Get-Hostile { return 1 }`n" |
            Out-Null

        & $script:addScript -Path $script:root -ChangedPath $hostile | Out-Null
        $result = @(& $script:invokeScript -Path $script:root)

        $result | Should -HaveCount 1
        $result[0].RelativePath | Should -Be $hostile
        ($result[0].Checks | Where-Object { $_.Validator -eq 'PowerShell.Parse' }).Outcome |
            Should -Be 'Passed' -Because 'a wildcard or subexpression in a name must not stop the file being read literally'
        Test-Path -LiteralPath (Join-Path $script:root 'evidence.txt') |
            Should -BeFalse -Because 'no part of a filename may ever be evaluated'
    }

    It 'reports an oversized file as unavailable rather than validated' {
        $big = 'x' * 4096
        Set-ValidationFile -Root $script:root -RelativePath 'source/Large.ps1' -Content "# $big`n" | Out-Null
        & $script:addScript -Path $script:root -ChangedPath 'source/Large.ps1' | Out-Null

        $result = @(& $script:invokeScript -Path $script:root -MaxFileKilobyte 1)
        $result[0].Action | Should -Be 'Skipped'
        $result[0].ValidationState | Should -Be 'Incomplete'
        $result[0].Verified | Should -BeFalse
    }

    It 'skips an unsupported or missing file instead of claiming a result' {
        & $script:addScript -Path $script:root -ChangedPath 'assets/logo.bin' | Out-Null
        & $script:addScript -Path $script:root -ChangedPath 'source/Good.ps1' | Out-Null
        Remove-Item -LiteralPath (Get-ValidationFullPath -Root $script:root -RelativePath 'source/Good.ps1') -Force

        $result = @(& $script:invokeScript -Path $script:root | Sort-Object -Property RelativePath)
        @($result | Where-Object { $_.Action -ne 'Skipped' }) | Should -HaveCount 0
        @($result | Where-Object { $_.Verified }) | Should -HaveCount 0
    }

    It 'rewrites no file it validates and no file it was not given' {
        & $script:addScript -Path $script:root -ChangedPath 'source/Good.ps1' | Out-Null
        $before = Get-DirectorySnapshot -Root (Join-Path $script:root 'source')
        $docsBefore = Get-DirectorySnapshot -Root (Join-Path $script:root 'docs')

        & $script:invokeScript -Path $script:root | Out-Null

        Get-DirectorySnapshot -Root (Join-Path $script:root 'source') | Should -Be $before
        Get-DirectorySnapshot -Root (Join-Path $script:root 'docs') | Should -Be $docsBefore
    }

    It 'writes nothing while reporting a batch' {
        & $script:addScript -Path $script:root -ChangedPath 'source/Good.ps1' | Out-Null
        $before = Get-DirectorySnapshot -Root $script:root

        & $script:getScript -Path $script:root | Out-Null

        Get-DirectorySnapshot -Root $script:root |
            Should -Be $before -Because 'a report must never mutate the batch it reports on'
    }

    It 'runs no validator for a session that collected nothing' {
        $result = @(& $script:invokeScript -Path $script:root -SessionId 'empty')
        $result | Should -HaveCount 0
    }
}

Describe 'Bounded external validator invocation' -Tag 'Unit' {
    BeforeAll {
        . (Join-Path (Split-Path -Parent $PSScriptRoot) 'skills/changed-file-validation/scripts/ChangedFileValidationCommon.ps1')
    }

    It 'reports a missing executable as unavailable rather than passed' {
        $result = Invoke-ChangedFileExternalTool `
            -FilePath ('no-such-tool-{0}' -f [guid]::NewGuid().ToString('N')) `
            -Argument @('--version') `
            -TimeoutSecond 10

        $result.Outcome | Should -Be 'Unavailable'
        $result.Reason | Should -Be 'ExecutableNotFound'
    }

    It 'stops a child that outruns the time bound and reports a timeout' {
        if (-not $script:supportsArgumentList)
        {
            Set-ItResult -Skipped -Because 'Windows PowerShell cannot pass an argument list without building a command line'
            return
        }

        $result = Invoke-ChangedFileExternalTool `
            -FilePath $script:hostExecutable `
            -Argument @('-NoProfile', '-NonInteractive', '-Command', 'Start-Sleep -Seconds 45') `
            -TimeoutSecond 2

        $result.Outcome | Should -Be 'TimedOut'
        $result.ExitCode | Should -Not -Be 0
        Get-Process -Id $result.ProcessId -ErrorAction SilentlyContinue |
            Should -BeNullOrEmpty -Because 'the helper must stop the child it started'
    }

    It 'caps the output it retains from a talkative child' {
        if (-not $script:supportsArgumentList)
        {
            Set-ItResult -Skipped -Because 'Windows PowerShell cannot pass an argument list without building a command line'
            return
        }

        $result = Invoke-ChangedFileExternalTool `
            -FilePath $script:hostExecutable `
            -Argument @('-NoProfile', '-NonInteractive', '-Command', '1..5000 | ForEach-Object { "x" * 200 }') `
            -TimeoutSecond 60 `
            -MaxOutputCharacter 4096

        $result.StandardOutput.Length | Should -BeLessOrEqual 4096
        $result.Truncated | Should -BeTrue
    }

    It 'passes an argument containing shell metacharacters through literally' {
        if (-not $script:supportsArgumentList)
        {
            Set-ItResult -Skipped -Because 'Windows PowerShell cannot pass an argument list without building a command line'
            return
        }

        $hostileArgument = '$(New-Item -Path pwned.txt) & echo owned | "quoted"'
        $echoScript = Join-Path ([IO.Path]::GetTempPath()) ('echo-{0}.ps1' -f [guid]::NewGuid().ToString('N'))
        [IO.File]::WriteAllText($echoScript, "Write-Output `$args[0]`n")

        try
        {
            $result = Invoke-ChangedFileExternalTool `
                -FilePath $script:hostExecutable `
                -Argument @('-NoProfile', '-NonInteractive', '-File', $echoScript, $hostileArgument) `
                -TimeoutSecond 60

            $result.Outcome | Should -Be 'Completed'
            $result.StandardOutput.Trim() | Should -Be $hostileArgument
            Test-Path -LiteralPath (Join-Path $PWD.Path 'pwned.txt') | Should -BeFalse
        }
        finally
        {
            Remove-Item -LiteralPath $echoScript -Force -ErrorAction SilentlyContinue
        }
    }

    It 'reports a nonzero exit status as failed' {
        if (-not $script:supportsArgumentList)
        {
            Set-ItResult -Skipped -Because 'Windows PowerShell cannot pass an argument list without building a command line'
            return
        }

        $result = Invoke-ChangedFileExternalTool `
            -FilePath $script:hostExecutable `
            -Argument @('-NoProfile', '-NonInteractive', '-Command', 'exit 3') `
            -TimeoutSecond 60

        $result.Outcome | Should -Be 'Completed'
        $result.ExitCode | Should -Be 3
    }
}

Describe 'Changed-file validation boundaries' -Tag 'Unit' {
    BeforeAll {
        $script:hookConfigPath = Join-Path $script:repoRoot 'com.github.copilot/hooks/hooks.json'
        $script:hookConfig = Get-Content -LiteralPath $script:hookConfigPath -Raw -Encoding UTF8 |
            ConvertFrom-Json
    }

    It 'adds no hook event to the shipped configuration' {
        @($script:hookConfig.hooks.PSObject.Properties.Name | Sort-Object) |
            Should -Be @('PreCompact', 'PreToolUse', 'SessionStart', 'Stop')
    }

    It 'wires no changed-file collection into any hook command' {
        (Get-Content -LiteralPath $script:hookConfigPath -Raw -Encoding UTF8) |
            Should -Not -Match 'changed-file' -Because 'collection is opt-in and manual, so no guard depends on it'

        foreach ($file in Get-ChildItem -LiteralPath (Join-Path $script:repoRoot 'com.github.copilot/hooks/scripts') -Filter '*.ps1' -File)
        {
            (Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8) |
                Should -Not -Match 'ChangedFile' -Because "$($file.Name) must not gain an optional dependency that could fail a guard"
        }
    }

    It 'keeps the remote-mutation guard blocking a push' {
        $blockScript = Join-Path $script:repoRoot 'com.github.copilot/hooks/scripts/Block-RemoteMutation.ps1'
        $payload = [ordered]@{
            hook_event_name = 'PreToolUse'
            tool_name = 'run_in_terminal'
            tool_input = [ordered]@{ command = 'git push origin main' }
        } | ConvertTo-Json -Depth 5 -Compress

        # The guard writes to standard error and exits non-zero by design, so the
        # child runs the way the client invokes it rather than in this session.
        $previousPreference = $ErrorActionPreference
        try
        {
            $ErrorActionPreference = 'Continue'
            $output = $payload | & $script:hostExecutable @(
                '-NoProfile', '-NonInteractive', '-File', $blockScript
            ) 2>&1
            $exitCode = $LASTEXITCODE
        }
        finally
        {
            $ErrorActionPreference = $previousPreference
        }

        $exitCode | Should -Be 2 -Because 'the mandatory guard must be unchanged by this feature'
        ($output | Out-String) | Should -Not -BeNullOrEmpty
    }

    It 'never runs a validator from the read-only deployment health command' {
        (Get-Content -LiteralPath (Join-Path $script:repoRoot 'source/Public/Test-CopilotAtelier.ps1') -Raw -Encoding UTF8) |
            Should -Not -Match 'ChangedFile|changed-file-validation'
    }

    It 'ships offline evaluation cases that were never run against a paid backend' {
        Test-Path -LiteralPath $script:evalFixturePath -PathType Leaf | Should -BeTrue

        $fixture = Get-Content -LiteralPath $script:evalFixturePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $fixture.executed | Should -BeFalse
        @($fixture.cases).Count | Should -BeGreaterThan 3
    }

    It 'documents activation, manual use, supported types, and the immediate-test boundary' {
        $body = Get-Content -LiteralPath $script:skillBodyPath -Raw -Encoding UTF8

        foreach ($heading in @(
                'Activation'
                'Supported file types'
                'Diagnostics'
                'What this is not'
            ))
        {
            $body | Should -Match ([regex]::Escape($heading))
        }
    }

    It 'parses every shipped script' {
        foreach ($file in Get-ChildItem -LiteralPath $script:scriptRoot -Filter '*.ps1' -File)
        {
            $parseError = $null
            $null = [Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref] $null, [ref] $parseError)
            @($parseError) | Should -HaveCount 0 -Because $file.Name
        }
    }
}

Describe 'Changed-file receipt identity' -Tag 'Unit' {
    BeforeEach {
        $script:root = New-ValidationFixture
    }

    AfterEach {
        Remove-ValidationFixture -Root $script:root
    }

    It 'revalidates when the failing severity changes' {
        & $script:addScript -Path $script:root -ChangedPath 'source/Good.ps1' | Out-Null
        @(& $script:invokeScript -Path $script:root)[0].Action | Should -Be 'Validated'
        @(& $script:invokeScript -Path $script:root)[0].Action | Should -Be 'Reused'

        @(& $script:invokeScript -Path $script:root -FailOnSeverity 'Warning')[0].Action |
            Should -Be 'Validated' -Because 'a receipt is a claim about the plan it was made under'
    }

    It 'reports a receipt made under another plan as PlanChanged' {
        & $script:addScript -Path $script:root -ChangedPath 'source/Good.ps1' | Out-Null
        & $script:invokeScript -Path $script:root | Out-Null

        $report = @(& $script:getScript -Path $script:root -FailOnSeverity 'Warning')
        $report[0].ValidationState | Should -Be 'PlanChanged'
        $report[0].Verified | Should -BeFalse
    }

    It 'revalidates a markdown receipt once a linter is selected' {
        Set-ValidationFile -Root $script:root -RelativePath '.markdownlint.jsonc' -Content "{ }`n" | Out-Null
        $marker = Join-Path $script:root 'stub-args.txt'
        $stub = New-StubMarkdownLint -Directory (Join-Path $script:root 'tools') -MarkerPath $marker

        & $script:addScript -Path $script:root -ChangedPath 'docs/good.md' | Out-Null
        @(& $script:invokeScript -Path $script:root)[0].Action | Should -Be 'Validated'

        @(& $script:invokeScript -Path $script:root -MarkdownLintPath $stub)[0].Action |
            Should -Be 'Validated' -Because 'a receipt made without a linter cannot cover a plan that now has one'
    }

    It 'fails closed on a receipt whose checks were emptied by hand' {
        & $script:addScript -Path $script:root -ChangedPath 'source/Good.ps1' | Out-Null
        & $script:invokeScript -Path $script:root | Out-Null

        Edit-ValidationReceipt -Root $script:root -RelativePath 'source/Good.ps1' -Change {
            param ($Receipt)
            $Receipt.checks = @()
            $Receipt.outcome = 'Passed'
        }

        $report = @(& $script:getScript -Path $script:root)
        $report[0].Verified | Should -BeFalse
        $report[0].ValidationState | Should -Be 'Incomplete'

        @(& $script:invokeScript -Path $script:root)[0].Action |
            Should -Be 'Validated' -Because 'an unusable receipt must be replaced, not trusted'
    }

    It 'fails closed on a receipt whose recorded outcome contradicts its checks' {
        & $script:addScript -Path $script:root -ChangedPath 'source/Broken.ps1' | Out-Null
        & $script:invokeScript -Path $script:root | Out-Null

        Edit-ValidationReceipt -Root $script:root -RelativePath 'source/Broken.ps1' -Change {
            param ($Receipt)
            $Receipt.outcome = 'Passed'
        }

        $report = @(& $script:getScript -Path $script:root)
        $report[0].Verified | Should -BeFalse
        $report[0].ValidationState | Should -Be 'Incomplete'
    }

    It 'never verifies a receipt that flags a change during validation' {
        & $script:addScript -Path $script:root -ChangedPath 'source/Good.ps1' | Out-Null
        & $script:invokeScript -Path $script:root | Out-Null

        Edit-ValidationReceipt -Root $script:root -RelativePath 'source/Good.ps1' -Change {
            param ($Receipt)
            $Receipt.contentChangedDuringValidation = $true
        }

        $report = @(& $script:getScript -Path $script:root)
        $report[0].Verified |
            Should -BeFalse -Because 'the bytes moved under the run even though they match again now'
        $report[0].ValidationState | Should -Be 'Stale'

        @(& $script:invokeScript -Path $script:root)[0].Action | Should -Be 'Validated'
    }

    It 'starts no external tool while reporting a receipt' {
        Set-ValidationFile -Root $script:root -RelativePath '.markdownlint.jsonc' -Content "{ }`n" | Out-Null
        $marker = Join-Path $script:root 'stub-args.txt'
        $stub = New-StubMarkdownLint -Directory (Join-Path $script:root 'tools') -MarkerPath $marker

        & $script:addScript -Path $script:root -ChangedPath 'docs/good.md' | Out-Null
        & $script:invokeScript -Path $script:root -MarkdownLintPath $stub | Out-Null
        Remove-Item -LiteralPath $marker -Force -ErrorAction SilentlyContinue

        & $script:getScript -Path $script:root -MarkdownLintPath $stub | Out-Null

        Test-Path -LiteralPath $marker |
            Should -BeFalse -Because 'a read-only report must never launch a tool to inspect a receipt'
    }

    It 'fails closed on a receipt <Case>' -ForEach @(
        @{
            Case = 'whose check outcome is not a result this implementation can produce'
            Reason = 'ReceiptUnreadable'
            Change = { param ($Receipt) $Receipt.checks[0].outcome = 'Skipped' }
        }
        @{
            Case = 'whose passing check carries no exit status'
            Reason = 'ReceiptExitStatusMismatch'
            Change = { param ($Receipt) $Receipt.checks[0].exitStatus = $null }
        }
        @{
            Case = 'whose passing check carries a nonzero exit status'
            Reason = 'ReceiptExitStatusMismatch'
            Change = { param ($Receipt) $Receipt.checks[0].exitStatus = 3 }
        }
        @{
            Case = 'that records the same check twice'
            Reason = 'UnexpectedCheckPresent'
            Change = {
                param ($Receipt)
                $Receipt.checks = @($Receipt.checks[0], $Receipt.checks[0], $Receipt.checks[1])
            }
        }
        @{
            Case = 'that carries a check the plan never asked for'
            Reason = 'UnexpectedCheckPresent'
            Change = {
                param ($Receipt)
                $Receipt.checks = @($Receipt.checks) + [PSCustomObject]@{
                    validator = 'Markdown.Rumour'
                    executable = 'in-process:rumour'
                    version = ''
                    configIdentity = 'none'
                    outcome = 'Passed'
                    reason = ''
                    exitStatus = 0
                    diagnosticCount = 0
                    truncated = $false
                    diagnostics = @()
                }
            }
        }
        @{
            Case = 'whose during-validation flag is not a Boolean'
            Reason = 'ReceiptUnreadable'
            Change = { param ($Receipt) $Receipt.contentChangedDuringValidation = 0 }
        }
    ) {
        Set-ValidationFile -Root $script:root -RelativePath '.markdownlint.jsonc' -Content "{ }`n" | Out-Null
        $stub = New-StubMarkdownLint -Directory (Join-Path $script:root 'tools') `
            -MarkerPath (Join-Path $script:root 'stub-args.txt')

        & $script:addScript -Path $script:root -ChangedPath 'docs/good.md' | Out-Null
        & $script:invokeScript -Path $script:root -MarkdownLintPath $stub | Out-Null

        @(& $script:getScript -Path $script:root -MarkdownLintPath $stub)[0].Verified |
            Should -BeTrue -Because 'the forgery only means something against a receipt that did verify'

        Edit-ValidationReceipt -Root $script:root -RelativePath 'docs/good.md' -Change $Change

        $report = @(& $script:getScript -Path $script:root -MarkdownLintPath $stub)
        $report[0].Verified | Should -BeFalse
        $report[0].ValidationState | Should -Be 'Incomplete'
        $report[0].ValidationReason | Should -Be $Reason
    }

    It 'revalidates after the shipped checker implementation is edited' {
        $checker = Join-Path $script:root 'checker'
        Copy-Item -LiteralPath $script:scriptRoot -Destination $checker -Recurse -Force

        $localAdd = Join-Path $checker 'Add-ChangedFile.ps1'
        $localInvoke = Join-Path $checker 'Invoke-ChangedFileValidation.ps1'
        $localGet = Join-Path $checker 'Get-ChangedFileBatch.ps1'
        $localWorker = Join-Path $checker 'Invoke-ChangedFileValidationWorker.ps1'

        & $localAdd -Path $script:root -ChangedPath 'source/Good.ps1' | Out-Null
        @(& $localInvoke -Path $script:root)[0].Action | Should -Be 'Validated'
        @(& $localInvoke -Path $script:root)[0].Action | Should -Be 'Reused'

        [IO.File]::AppendAllText($localWorker, "`n# A local edit to the checker.`n")

        @(& $localGet -Path $script:root)[0].ValidationState |
            Should -Be 'PlanChanged' -Because 'a receipt cannot outlive the implementation that produced it'

        @(& $localInvoke -Path $script:root)[0].Action | Should -Be 'Validated'
    }

    It 'revalidates when the linter binary is replaced at the same size and timestamp' {
        Set-ValidationFile -Root $script:root -RelativePath '.markdownlint.jsonc' -Content "{ }`n" | Out-Null
        $marker = Join-Path $script:root 'stub-args.txt'
        $tools = Join-Path $script:root 'tools'
        $stub = New-StubMarkdownLint -Directory $tools -MarkerPath $marker -Version '0.44.0'

        & $script:addScript -Path $script:root -ChangedPath 'docs/good.md' | Out-Null
        & $script:invokeScript -Path $script:root -MarkdownLintPath $stub | Out-Null
        @(& $script:getScript -Path $script:root -MarkdownLintPath $stub)[0].Verified | Should -BeTrue

        $original = Get-Item -LiteralPath $stub -Force
        $stamp = $original.LastWriteTimeUtc
        $length = $original.Length

        New-StubMarkdownLint -Directory $tools -MarkerPath $marker -Version '0.44.1' | Out-Null
        $replaced = Get-Item -LiteralPath $stub -Force
        $replaced.Length | Should -Be $length -Because 'the replacement has to be indistinguishable by size'
        $replaced.LastWriteTimeUtc = $stamp

        @(& $script:getScript -Path $script:root -MarkdownLintPath $stub)[0].ValidationState |
            Should -Be 'PlanChanged' -Because 'a size and a timestamp do not identify a binary'
    }
}

Describe 'Changed-file execution bounds' -Tag 'Unit' {
    BeforeAll {
        . (Join-Path (Split-Path -Parent $PSScriptRoot) 'skills/changed-file-validation/scripts/ChangedFileValidationCommon.ps1')
    }

    BeforeEach {
        $script:root = New-ValidationFixture
    }

    AfterEach {
        Remove-ValidationFixture -Root $script:root
    }

    It 'refuses to validate while another run holds the session execution lock' {
        & $script:addScript -Path $script:root -ChangedPath 'source/Good.ps1' | Out-Null

        $lockPath = Join-Path $script:root (
            '.copilot-atelier/changed-file-validation/.execution-default.lock' -replace '/', [IO.Path]::DirectorySeparatorChar
        )
        $held = [IO.FileStream]::new(
            $lockPath,
            [IO.FileMode]::OpenOrCreate,
            [IO.FileAccess]::ReadWrite,
            [IO.FileShare]::None
        )

        try
        {
            { & $script:invokeScript -Path $script:root -ExecutionWaitSecond 1 -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*holds the execution lock*'
        }
        finally
        {
            $held.Dispose()
        }
    }

    It 'bounds a worker that never finishes and reports every check as timed out' {
        $workspace = Join-Path ([IO.Path]::GetTempPath()) ('cfv-worker-{0}' -f [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $workspace -Force | Out-Null
        $spinner = Join-Path $workspace 'spin.ps1'
        [IO.File]::WriteAllText($spinner, "`$null = [Console]::In.ReadToEnd()`nStart-Sleep -Seconds 45`n")
        [IO.File]::WriteAllText((Join-Path $workspace 'snapshot.ps1'), "function Get-Snapshot { return 1 }`n")

        try
        {
            $checks = @(
                Invoke-ChangedFilePowerShellCheck `
                    -WorkingDirectory $workspace `
                    -FileName 'snapshot.ps1' `
                    -FailOnSeverity 'Error' `
                    -TimeoutSecond 3 `
                    -WorkerScriptPath $spinner
            )

            $checks | Should -HaveCount 2
            @($checks | ForEach-Object -Process { $_['outcome'] } | Sort-Object -Unique) |
                Should -Be @('TimedOut') -Because 'an in-process validator with no wall clock can hang the session'
        }
        finally
        {
            Remove-Item -LiteralPath $workspace -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'validates the bytes it copied rather than the path it copied them from' {
        $context = Resolve-ChangedFileContext -Path $script:root
        $full = Get-ValidationFullPath -Root $script:root -RelativePath 'source/Good.ps1'
        $original = [IO.File]::ReadAllText($full)

        $snapshot = New-ChangedFileSnapshot -Context $context -FullPath $full
        try
        {
            [IO.File]::WriteAllText($full, "function Get-Good`n{`n    if (`$true`n}`n")

            [IO.File]::ReadAllText($snapshot.FullPath) | Should -Be $original
            Get-ChangedFileContentHash -LiteralPath $snapshot.FullPath | Should -Be $snapshot.Sha256
        }
        finally
        {
            Remove-ChangedFileSnapshot -Directory $snapshot.Directory
        }

        Test-Path -LiteralPath $snapshot.Directory |
            Should -BeFalse -Because 'a snapshot is working state, not a second copy of the project'
    }

    It 'runs no code from the file it validates' {
        $evidence = (Join-Path $script:root 'executed.txt') -replace '\\', '/'
        Set-ValidationFile -Root $script:root -RelativePath 'source/Payload.ps1' `
            -Content "New-Item -Path '$evidence' -ItemType File | Out-Null`n" | Out-Null

        & $script:addScript -Path $script:root -ChangedPath 'source/Payload.ps1' | Out-Null
        & $script:invokeScript -Path $script:root | Out-Null

        Test-Path -LiteralPath (Join-Path $script:root 'executed.txt') |
            Should -BeFalse -Because 'validation reads a file, it never runs one'
    }

    It 'ignores a project analyzer settings file' {
        if (-not $script:hasScriptAnalyzer)
        {
            Set-ItResult -Skipped -Because 'PSScriptAnalyzer is not installed on this host'
            return
        }

        Set-ValidationFile -Root $script:root -RelativePath 'PSScriptAnalyzerSettings.psd1' `
            -Content "@{ ExcludeRules = @('PSAvoidUsingWriteHost') }`n" | Out-Null
        Set-ValidationFile -Root $script:root -RelativePath 'source/Loud.ps1' `
            -Content "function Get-Loud`n{`n    Write-Host 'x'`n}`n" | Out-Null

        & $script:addScript -Path $script:root -ChangedPath 'source/Loud.ps1' | Out-Null
        $result = @(& $script:invokeScript -Path $script:root)

        $analyzer = $result[0].Checks | Where-Object { $_.Validator -eq 'PowerShell.ScriptAnalyzer' }
        @($analyzer.Diagnostics).RuleId |
            Should -Contain 'PSAvoidUsingWriteHost' -Because 'project analyzer settings are not part of the verified plan'
    }
}

Describe 'Bounded external validator output' -Tag 'Unit' {
    BeforeAll {
        . (Join-Path (Split-Path -Parent $PSScriptRoot) 'skills/changed-file-validation/scripts/ChangedFileValidationCommon.ps1')
    }

    It 'caps retained output while the child is still running' {
        if (-not $script:supportsArgumentList)
        {
            Set-ItResult -Skipped -Because 'Windows PowerShell cannot pass an argument list without building a command line'
            return
        }

        $result = Invoke-ChangedFileExternalTool `
            -FilePath $script:hostExecutable `
            -Argument @(
                '-NoProfile'
                '-NonInteractive'
                '-Command'
                '1..20000 | ForEach-Object { "y" * 200 }; Start-Sleep -Seconds 30'
            ) `
            -TimeoutSecond 5 `
            -MaxOutputCharacter 2048

        $result.Outcome | Should -Be 'TimedOut'
        $result.StandardOutput.Length | Should -BeLessOrEqual 2048
        $result.TotalOutputCharacter |
            Should -BeGreaterThan 2048 -Because 'output must be drained and counted during the run, not buffered until exit'
    }

    It 'reports an executable that cannot start as unavailable' {
        $missingDirectory = Join-Path ([IO.Path]::GetTempPath()) ('cfv-absent-{0}' -f [guid]::NewGuid().ToString('N'))

        $result = Invoke-ChangedFileExternalTool `
            -FilePath $script:hostExecutable `
            -Argument @('-NoProfile', '-NonInteractive', '-Command', 'exit 0') `
            -WorkingDirectory $missingDirectory `
            -TimeoutSecond 10

        $result.Outcome | Should -Be 'Unavailable'
        $result.Reason | Should -Be 'StartFailed'
        $result.ExitCode | Should -BeNullOrEmpty -Because 'an exit status that was never produced must not be invented'
    }

    It 'does not claim complete output when a descendant still holds the pipe' {
        if (-not $script:supportsArgumentList)
        {
            Set-ItResult -Skipped -Because 'Windows PowerShell cannot pass an argument list without building a command line'
            return
        }

        $workspace = Join-Path ([IO.Path]::GetTempPath()) ('cfv-pipe-{0}' -f [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $workspace -Force | Out-Null
        $spawn = Join-Path $workspace 'spawn.ps1'
        [IO.File]::WriteAllText(
            $spawn,
            "Start-Process -FilePath `$args[0] -ArgumentList '-NoProfile', '-NonInteractive', '-Command', 'Start-Sleep -Seconds 8' -NoNewWindow`nexit 0`n"
        )

        try
        {
            $result = Invoke-ChangedFileExternalTool `
                -FilePath $script:hostExecutable `
                -Argument @('-NoProfile', '-NonInteractive', '-File', $spawn, $script:hostExecutable) `
                -TimeoutSecond 20 `
                -OutputDrainMillisecond 1500

            $result.OutputComplete |
                Should -BeFalse -Because 'a descendant holding the pipe open must not stall or be reported as a clean read'
        }
        finally
        {
            Remove-Item -LiteralPath $workspace -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Markdown checking' -Tag 'Unit' {
    BeforeEach {
        $script:root = New-ValidationFixture
        $script:marker = Join-Path $script:root 'stub-args.txt'
        $script:toolDirectory = Join-Path $script:root 'tools'
        Set-ValidationFile -Root $script:root -RelativePath '.markdownlint.jsonc' `
            -Content "{ `"MD013`": false }`n" | Out-Null
    }

    AfterEach {
        Remove-ValidationFixture -Root $script:root
    }

    It 'reports the lint check as unavailable when no linter is configured' {
        & $script:addScript -Path $script:root -ChangedPath 'docs/good.md' | Out-Null
        $result = @(& $script:invokeScript -Path $script:root)

        $lint = $result[0].Checks | Where-Object { $_.Validator -eq 'Markdown.Lint' }
        $lint | Should -Not -BeNullOrEmpty -Because 'markdownlint coverage is part of the plan, present or not'
        $lint.Outcome | Should -Be 'Unavailable'
        $lint.Reason | Should -Be 'LinterNotConfigured'
        $result[0].ValidationState | Should -Be 'Incomplete'
        $result[0].Verified |
            Should -BeFalse -Because 'the native structure check is not markdownlint and cannot stand in for it'
    }

    It 'reports an enabled markdownlint rule through a verified linter interface' {
        $stub = New-StubMarkdownLint -Directory $script:toolDirectory -MarkerPath $script:marker `
            -DiagnosticLine 'snapshot.md:1:1 MD018/no-missing-space-atx Missing space after hash' -ExitCode 1

        Set-ValidationFile -Root $script:root -RelativePath 'docs/atx.md' -Content "#Title`n`nBody.`n" | Out-Null
        & $script:addScript -Path $script:root -ChangedPath 'docs/atx.md' | Out-Null

        $result = @(& $script:invokeScript -Path $script:root -MarkdownLintPath $stub)

        $native = $result[0].Checks | Where-Object { $_.Validator -eq 'Markdown.NativeStructure' }
        $native.Outcome |
            Should -Be 'Passed' -Because 'the native check implements four rules, not the markdownlint defaults'

        $lint = $result[0].Checks | Where-Object { $_.Validator -eq 'Markdown.Lint' }
        $lint.Outcome | Should -Be 'Failed'
        $lint.Version | Should -Be '0.44.0'
        @($lint.Diagnostics).RuleId | Should -Contain 'MD018'
        $result[0].Verified | Should -BeFalse
    }

    It 'passes the declarative configuration to the linter and records its identity' {
        $stub = New-StubMarkdownLint -Directory $script:toolDirectory -MarkerPath $script:marker

        & $script:addScript -Path $script:root -ChangedPath 'docs/good.md' | Out-Null
        $result = @(& $script:invokeScript -Path $script:root -MarkdownLintPath $stub)

        $lint = $result[0].Checks | Where-Object { $_.Validator -eq 'Markdown.Lint' }
        $lint.Outcome | Should -Be 'Passed'
        $lint.ConfigIdentity | Should -Match '\.markdownlint\.jsonc:[0-9a-f]{64}'

        (Get-Content -LiteralPath $script:marker -Raw) |
            Should -Match '--config' -Because 'ancestor discovery must be replaced by an explicit configuration'
    }

    It 'checks only the file it was given when the name carries glob characters' {
        $stub = New-StubMarkdownLint -Directory $script:toolDirectory -MarkerPath $script:marker

        Set-ValidationFile -Root $script:root -RelativePath 'docs/a.md' -Content "# Sibling" | Out-Null
        Set-ValidationFile -Root $script:root -RelativePath 'docs/[a].md' -Content "# Selected`n" | Out-Null
        & $script:addScript -Path $script:root -ChangedPath 'docs/[a].md' | Out-Null

        $result = @(& $script:invokeScript -Path $script:root -MarkdownLintPath $stub)
        $result[0].RelativePath | Should -Be 'docs/[a].md'

        $recorded = Get-Content -LiteralPath $script:marker -Raw
        $recorded | Should -Not -Match 'docs' -Because 'the linter is handed an isolated snapshot, never a project glob'
        $recorded | Should -Match 'snapshot\.md'
    }

    It 'refuses an executable markdownlint configuration at <Location>' -ForEach @(
        @{ Location = 'the project root'; RelativePath = '.markdownlint.js' }
        @{ Location = 'the project root as cli2'; RelativePath = '.markdownlint-cli2.cjs' }
        @{ Location = 'the file directory'; RelativePath = 'docs/.markdownlint.js' }
    ) {
        $stub = New-StubMarkdownLint -Directory $script:toolDirectory -MarkerPath $script:marker
        Set-ValidationFile -Root $script:root -RelativePath $RelativePath -Content "module.exports = {};`n" | Out-Null

        & $script:addScript -Path $script:root -ChangedPath 'docs/good.md' | Out-Null
        $result = @(& $script:invokeScript -Path $script:root -MarkdownLintPath $stub)

        $lint = $result[0].Checks | Where-Object { $_.Validator -eq 'Markdown.Lint' }
        $lint.Outcome | Should -Be 'Unavailable'
        $lint.Reason | Should -Be 'ExecutableConfigurationPresent'
        Test-Path -LiteralPath $script:marker |
            Should -BeFalse -Because 'a configuration that can load code must never reach the linter'
    }

    It 'refuses a declarative configuration that references <Key>' -ForEach @(
        @{ Key = 'custom rules'; Content = '{ "customRules": ["./rule.js"] }' }
        @{ Key = 'another configuration'; Content = '{ "extends": "./base.js" }' }
        @{ Key = 'a dynamic key spelled with escapes'; Content = '{ "\u0065xtends": "./base.js" }' }
        @{ Key = 'a module path nested inside a rule block'; Content = '{ "MD044": { "modulePaths": ["./rules"] } }' }
    ) {
        $stub = New-StubMarkdownLint -Directory $script:toolDirectory -MarkerPath $script:marker
        Set-ValidationFile -Root $script:root -RelativePath '.markdownlint.jsonc' -Content ($Content + "`n") | Out-Null

        & $script:addScript -Path $script:root -ChangedPath 'docs/good.md' | Out-Null
        $result = @(& $script:invokeScript -Path $script:root -MarkdownLintPath $stub)

        $lint = $result[0].Checks | Where-Object { $_.Validator -eq 'Markdown.Lint' }
        $lint.Outcome | Should -Be 'Unavailable'
        $lint.Reason | Should -Be 'ExecutableConfigurationPresent'
        Test-Path -LiteralPath $script:marker |
            Should -BeFalse -Because 'unvalidated configuration bytes must never reach an executable'
    }

    It 'refuses a configuration whose shape is not a rule map' {
        $stub = New-StubMarkdownLint -Directory $script:toolDirectory -MarkerPath $script:marker
        Set-ValidationFile -Root $script:root -RelativePath '.markdownlint.jsonc' -Content "[ `"MD013`" ]`n" | Out-Null

        & $script:addScript -Path $script:root -ChangedPath 'docs/good.md' | Out-Null
        $result = @(& $script:invokeScript -Path $script:root -MarkdownLintPath $stub)

        $lint = $result[0].Checks | Where-Object { $_.Validator -eq 'Markdown.Lint' }
        $lint.Outcome | Should -Be 'Unavailable'
        $lint.Reason | Should -Be 'ConfigurationShapeUnsupported'
        Test-Path -LiteralPath $script:marker | Should -BeFalse
    }

    It 'reports a configuration format it cannot parse safely as unavailable' {
        $stub = New-StubMarkdownLint -Directory $script:toolDirectory -MarkerPath $script:marker
        Remove-Item -LiteralPath (Join-Path $script:root '.markdownlint.jsonc') -Force
        Set-ValidationFile -Root $script:root -RelativePath '.markdownlint.yaml' -Content "MD013: false`n" | Out-Null

        & $script:addScript -Path $script:root -ChangedPath 'docs/good.md' | Out-Null
        $result = @(& $script:invokeScript -Path $script:root -MarkdownLintPath $stub)

        $lint = $result[0].Checks | Where-Object { $_.Validator -eq 'Markdown.Lint' }
        $lint.Outcome | Should -Be 'Unavailable'
        $lint.Reason | Should -Be 'ConfigurationFormatUnsupported'
        Test-Path -LiteralPath $script:marker |
            Should -BeFalse -Because 'a format with no trusted parser is refused, not copied to the linter'
    }

    It 'keeps a commented JSONC configuration usable' {
        $stub = New-StubMarkdownLint -Directory $script:toolDirectory -MarkerPath $script:marker
        Set-ValidationFile -Root $script:root -RelativePath '.markdownlint.jsonc' -Content @'
{
  // The repository's own configuration style: comments and disabled rules.
  "MD013": false,
  "MD060": false
}

'@ | Out-Null

        & $script:addScript -Path $script:root -ChangedPath 'docs/good.md' | Out-Null
        $result = @(& $script:invokeScript -Path $script:root -MarkdownLintPath $stub)

        $lint = $result[0].Checks | Where-Object { $_.Validator -eq 'Markdown.Lint' }
        $lint.Outcome | Should -Be 'Passed' -Because 'the repository configuration has to stay usable'
        Test-Path -LiteralPath $script:marker | Should -BeTrue
    }

    It 'reports an unverified linter interface as unavailable' {
        $stub = New-StubMarkdownLint -Directory $script:toolDirectory -MarkerPath $script:marker -Version 'not-a-version'

        & $script:addScript -Path $script:root -ChangedPath 'docs/good.md' | Out-Null
        $result = @(& $script:invokeScript -Path $script:root -MarkdownLintPath $stub)

        $lint = $result[0].Checks | Where-Object { $_.Validator -eq 'Markdown.Lint' }
        $lint.Outcome | Should -Be 'Unavailable'
        $lint.Reason | Should -Be 'InterfaceNotVerified'
    }

    It 'reports an unsupported linter interface as unavailable' {
        $stub = New-StubMarkdownLint -Directory $script:toolDirectory -MarkerPath $script:marker

        & $script:addScript -Path $script:root -ChangedPath 'docs/good.md' | Out-Null
        $result = @(
            & $script:invokeScript -Path $script:root -MarkdownLintPath $stub -MarkdownLintInterface 'markdownlint-cli2'
        )

        $lint = $result[0].Checks | Where-Object { $_.Validator -eq 'Markdown.Lint' }
        $lint.Outcome | Should -Be 'Unavailable'
        $lint.Reason | Should -Be 'UnsupportedInterface'
    }

    It 'states the native checker coverage honestly in the skill body' {
        $body = Get-Content -LiteralPath $script:skillBodyPath -Raw -Encoding UTF8

        $body | Should -Not -Match 'the one markdownlint rule'
        $body | Should -Match 'Markdown\.NativeStructure'
        $body | Should -Match 'default'
    }
}
