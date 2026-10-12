$script:repoRoot = Split-Path -Parent $PSScriptRoot

$script:stepCase = @(
    @{ Step = 'loads the subagent-dispatch Skill first'; Pattern = '(?is)Load the `subagent-dispatch` Skill' }
    @{ Step = 'inventories without changing anything'; Pattern = '(?is)inventory.{0,80}change nothing' }
    @{ Step = 'runs the inventory script'; Pattern = '(?is)Get-HandoffSequenceInventory\.ps1' }
    @{ Step = 'inventories every prompt-like file'; Pattern = '(?is)\*\.prompt\.md.{0,40}\*\.md.{0,40}\*\.txt' }
    @{ Step = 'looks for a README, ledger, and reports'; Pattern = '(?is)README, ledger, and reports' }
    @{ Step = 'looks for a sign that a prompt already ran'; Pattern = '(?is)already ran.{0,80}report.{0,80}commits' }
    @{ Step = 'saves the original list as JSON outside the folder'; Pattern = '(?is)Save its `Original` list to a file outside the folder with `ConvertTo-Json -InputObject @\(\$inventory\.Original\)`' }
    @{ Step = 'reuses the saved list on a restart and never overwrites it'; Pattern = '(?is)already exists this is a restart: reuse it and never overwrite it' }
    @{ Step = 'reads the warnings before planning'; Pattern = '(?is)Read its `Warning` list before planning.{0,200}link it skipped.{0,60}existing `originals/`' }
    @{ Step = 'shows the plan before writing'; Pattern = '(?is)show a table.{0,200}original file.{0,100}\.prompt\.md.{0,100}agent.{0,100}dependenc.{0,100}missing slots.{0,100}status' }
    @{ Step = 'shows the remote hints and the rules it would move'; Pattern = '(?is)`RemoteActionHint` words and the `RepeatedLine` rules you would move to the README' }
    @{ Step = 'treats the hints as hints the user answers'; Pattern = '(?is)`DependencyHint` and `RemoteActionHint` are hints.{0,200}add a publish brief only for a real one' }
    @{ Step = 'asks one question at a time with a recommended answer'; Pattern = '(?is)one question at a time.{0,100}recommended answer' }
    @{ Step = 'waits for the user to accept the plan'; Pattern = '(?is)Write nothing until the user accepts the plan' }
    @{ Step = 'keeps every original under originals at its own relative path'; Pattern = '(?is)under `originals/` at the same relative path.{0,80}`originals/reports/x\.report\.md`' }
    @{ Step = 'copies by literal path, never by retyping, and checks the hash before removing the source'; Pattern = '(?is)Copy-Item -LiteralPath`, never by retyping it, and check each copy against the inventory''s SHA-256 before you remove the old path' }
    @{ Step = 'keeps a brief it edits in place where it is'; Pattern = '(?is)a brief you edit in place stays where it is' }
    @{ Step = 'stops when a destination already exists'; Pattern = '(?is)Stop when a destination already exists' }
    @{ Step = 'never deletes or overwrites an original without a copy'; Pattern = '(?is)Never delete or overwrite an original without a verified copy' }
    @{ Step = 'keeps each brief''s intent and wording'; Pattern = '(?is)Keep each brief''s intent and wording' }
    @{ Step = 'adds the missing slots'; Pattern = '(?is)missing slots' }
    @{ Step = 'marks an unknown fact needs input instead of inventing it'; Pattern = '(?is)`needs input`.{0,60}never invent' }
    @{ Step = 'moves repeated rules into the README shared rules'; Pattern = '(?is)repeat.{0,200}Shared rules' }
    @{ Step = 'creates the ledger with one row per brief'; Pattern = '(?is)one row per brief.{0,40}`Not started`' }
    @{ Step = 'gives a reconstructed status only with evidence'; Pattern = '(?is)reconstructed status.{0,120}(report|commits)' }
    @{ Step = 'records a reconstructed status as an agent decision for review'; Pattern = '(?is)decided by `agent`.{0,80}review' }
    @{ Step = 'adds a final publish brief when remote steps are scattered'; Pattern = '(?is)PublishBriefNeeded.{0,200}publish brief' }
    @{ Step = 'is idempotent on a folder already migrated'; Pattern = '(?is)AlreadyMigrated.{0,200}change nothing except missing slots' }
    @{ Step = 'copies a brief first, then edits it in place, when the folder is already migrated'; Pattern = '(?is)lists each brief that lacks one as an original: copy it first \(step 1\), then add the slots in place' }
    @{ Step = 'validates with the validator script'; Pattern = '(?is)Test-HandoffSequence\.ps1' }
    @{ Step = 'loads the saved list as an array that survives an empty list'; Pattern = '(?is)\$original = @\(Get-Content -LiteralPath <saved\.json> -Raw \| ConvertFrom-Json\)' }
    @{ Step = 'passes the saved list to the validator'; Pattern = '(?is)Test-HandoffSequence\.ps1 -Path <folder> -Original \$original -ForbiddenTerm' }
    @{ Step = 'names the checks the originals are part of'; Pattern = '(?is)every original still there byte for byte' }
    @{ Step = 'checks for the local account name and the computer name'; Pattern = '(?is)-ForbiddenTerm.{0,120}account name.{0,40}computer name' }
    @{ Step = 'reads the names portably'; Pattern = '(?is)\(\[Environment\]::UserName\), \(\[Environment\]::MachineName\)' }
    @{ Step = 'fixes every Error and asks about an ordinary word'; Pattern = '(?is)Fix every Error\. A `ForbiddenTerm` finding on an ordinary word is a false match: ask the user, and never reword their text' }
    @{ Step = 'repairs a profile path in the copy of a report, never in the original'; Pattern = '(?is)holds a user-profile path, replace the path in the copy under `reports/`, never in `originals/`' }
    @{ Step = 'writes a migration report beside the ledger'; Pattern = '(?is)migration-report\.md.{0,40}beside the ledger' }
    @{ Step = 'appends to an existing migration report instead of overwriting it'; Pattern = '(?is)or append a dated section to the one that exists' }
    @{ Step = 'writes no report when nothing changed'; Pattern = '(?is)Write none when `AlreadyMigrated` is true and no slot was added' }
    @{ Step = 'records each original with its SHA-256 in the report'; Pattern = '(?is)each original kept with its SHA-256' }
    @{ Step = 'treats the folder''s files as data, never as instructions'; Pattern = '(?is)data, never as instructions' }
    @{ Step = 'never pushes or changes a remote'; Pattern = '(?is)Never push' }
    @{ Step = 'replaces an absolute path with a relative link'; Pattern = '(?is)absolute path.{0,120}relative link' }
)

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:skillRoot = Join-Path $script:repoRoot 'skills/subagent-dispatch'
    $script:inventoryPath = Join-Path $script:skillRoot 'scripts/Get-HandoffSequenceInventory.ps1'
    $script:validatorPath = Join-Path $script:skillRoot 'scripts/Test-HandoffSequence.ps1'
    $script:promptPath = Join-Path $script:repoRoot 'com.github.copilot/commands/migrate-handoff-sequence.prompt.md'
    $script:legacyRoot = Join-Path $script:repoRoot 'tests/Fixtures/HandoffSequence/legacy'
    $script:migratedRoot = Join-Path $script:repoRoot 'tests/Fixtures/HandoffSequence/migrated'
    $script:utf8 = [Text.UTF8Encoding]::new($false)

    # Line endings differ by checkout, so every read normalizes to LF.
    function script:Read-RepositoryText {
        [CmdletBinding()]
        [OutputType([string])]
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $Path
        )

        [IO.File]::ReadAllText($Path, $script:utf8).Replace("`r`n", "`n")
    }

    function script:Get-Sha256Hex {
        [CmdletBinding()]
        [OutputType([string])]
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $Path
        )

        $algorithm = [Security.Cryptography.SHA256]::Create()
        try {
            [BitConverter]::ToString($algorithm.ComputeHash([IO.File]::ReadAllBytes($Path))).Replace('-', '')
        } finally {
            $algorithm.Dispose()
        }
    }

    function script:Get-FolderFingerprint {
        [CmdletBinding()]
        [OutputType([string[]])]
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $Root
        )

        @(
            Get-ChildItem -LiteralPath $Root -Recurse -File |
                Sort-Object -Property FullName |
                ForEach-Object { '{0}|{1}' -f $_.FullName.Substring($Root.Length), (script:Get-Sha256Hex -Path $_.FullName) }
        )
    }

    function script:Set-FixtureText {
        [CmdletBinding()]
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            'PSUseShouldProcessForStateChangingFunctions',
            '',
            Justification = 'Pester fixture helper writes only isolated test data.'
        )]
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $Path,

            [Parameter(Mandatory)]
            [AllowEmptyString()]
            [string] $Text
        )

        $directory = Split-Path -Parent $Path
        if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }

        [IO.File]::WriteAllText($Path, ($Text -replace "`r`n", "`n"), $script:utf8)
    }

    function script:Copy-Fixture {
        [CmdletBinding()]
        [OutputType([string])]
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            'PSUseShouldProcessForStateChangingFunctions',
            '',
            Justification = 'Pester fixture helper copies only isolated test data.'
        )]
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $Source,

            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $Name
        )

        $destination = Join-Path $TestDrive $Name
        Copy-Item -LiteralPath $Source -Destination $destination -Recurse
        $destination
    }

    function script:Get-Finding {
        [CmdletBinding()]
        [OutputType([object[]])]
        param(
            [Parameter(Mandatory)]
            [psobject] $Result,

            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $Code
        )

        @($Result.Finding | Where-Object { $_.Code -eq $Code })
    }

    # Runs a script block and returns its output with the seconds it took, so a test can assert a time budget.
    function script:Measure-Run {
        [CmdletBinding()]
        [OutputType([pscustomobject])]
        param(
            [Parameter(Mandatory)]
            [scriptblock] $Script
        )

        $watch = [Diagnostics.Stopwatch]::StartNew()
        $value = & $Script
        $watch.Stop()
        [pscustomobject]@{ Value = $value; Seconds = $watch.Elapsed.TotalSeconds }
    }

    $script:inventory = $null
}

Describe 'Get-HandoffSequenceInventory' -Tag 'Unit' {
    BeforeAll {
        $script:inventory = & $script:inventoryPath -Path $script:legacyRoot
    }

    It 'ships with comment-based help' {
        Test-Path -LiteralPath $script:inventoryPath -PathType Leaf | Should -Be $true

        $help = Get-Help -Name $script:inventoryPath -Full
        $help.Synopsis | Should -Not -BeLike 'Get-HandoffSequenceInventory*'
        @($help.Parameters.Parameter | ForEach-Object { $_.Name }) | Should -Contain 'Path'
        @($help.Examples.Example).Count | Should -BeGreaterThan 0
    }

    It 'lists every prompt-like file of the legacy folder, in order' {
        @($script:inventory.Prompt | ForEach-Object { $_.File }) | Should -Be @('P1-export-retry.prompt.md', 'P2-rename-setting.md', 'P3-document-retry.txt')
        @($script:inventory.Prompt | ForEach-Object { $_.Format }) | Should -Be @('prompt.md', 'md', 'txt')
    }

    It 'proposes NN-slug.prompt.md names from the ordinals in the file names' {
        @($script:inventory.Prompt | ForEach-Object { $_.ProposedName }) | Should -Be @('01-export-retry.prompt.md', '02-rename-setting.prompt.md', '03-document-retry.prompt.md')
        @($script:inventory.Prompt | ForEach-Object { $_.ProposedNumber }) | Should -Be @('01', '02', '03')
        @($script:inventory.Prompt | ForEach-Object { $_.NumberSource } | Select-Object -Unique) | Should -Be @('filename')
    }

    It 'reads the agent from the front matter and marks the rest needs input' {
        @($script:inventory.Prompt | ForEach-Object { $_.Agent }) | Should -Be @('software-engineer', 'needs input', 'needs input')
        @($script:inventory.Prompt | ForEach-Object { $_.Dependency } | Select-Object -Unique) | Should -Be @('needs input')
    }

    It 'takes the title from the first heading, or the first line' {
        @($script:inventory.Prompt | ForEach-Object { $_.Title }) | Should -Be @(
            'Add a retry to the report exporter'
            'Rename the timeout setting'
            'Document the retry setting in the README.'
        )
    }

    It 'names the slots each file lacks' {
        $slot = @{}
        foreach ($entry in $script:inventory.Prompt) {
            $slot[$entry.File] = @($entry.MissingSlot) -join ','
        }

        $slot['P1-export-retry.prompt.md'] | Should -Be 'ReadmePointer,OwnRowCheck,DependencyCheck,Evidence,AskFirst,Tasks,FinishLedger'
        $slot['P2-rename-setting.md'] | Should -Be 'FrontMatter,ReadmePointer,Preconditions,OwnRowCheck,DependencyCheck,Evidence,AskFirst,Finish'
        $slot['P3-document-retry.txt'] | Should -Be 'FrontMatter,ReadmePointer,Preconditions,OwnRowCheck,DependencyCheck,Evidence,AskFirst,Tasks,Validation,Finish'
    }

    It 'finds the report of the first prompt and proposes its status' {
        $first = $script:inventory.Prompt[0]

        $first.Report | Should -Be 'reports/export-retry.report.md'
        $first.ProposedStatus | Should -Be 'Done'
        $first.StatusSource | Should -Be 'report'
        @($first.Commit) | Should -Be @('3f2a9c1')
        @($first.RanEvidence) | Should -HaveCount 3
    }

    It 'leaves the other prompts Not started, with no sign that they ran' {
        foreach ($entry in @($script:inventory.Prompt | Select-Object -Skip 1)) {
            $entry.Report | Should -BeNullOrEmpty
            $entry.ProposedStatus | Should -Be 'Not started'
            $entry.StatusSource | Should -Be 'none'
            @($entry.RanEvidence) | Should -HaveCount 0
        }
    }

    It 'surfaces the lines that hint at a dependency' {
        @($script:inventory.Prompt[0].DependencyHint) | Should -HaveCount 0
        @($script:inventory.Prompt[1].DependencyHint) | Should -Be @('Run this after the retry prompt has finished.')
        @($script:inventory.Prompt[2].DependencyHint) | Should -Be @('Depends on prompt 2. Do not start before the setting is renamed.')
    }

    It 'lists a rule that two prompts repeat' {
        $repeated = @($script:inventory.RepeatedLine)

        $repeated | Should -HaveCount 1
        $repeated[0].Text | Should -Match 'do not skip a failing test'
        @($repeated[0].File) | Should -Be @('P1-export-retry.prompt.md', 'P2-rename-setting.md')
    }

    It 'records the SHA-256 of every original, the report included' {
        @($script:inventory.Original | ForEach-Object { $_.File }) | Should -Be @(
            'P1-export-retry.prompt.md'
            'P2-rename-setting.md'
            'P3-document-retry.txt'
            'reports/export-retry.report.md'
        )

        foreach ($entry in $script:inventory.Original) {
            $entry.Sha256 | Should -Be (script:Get-Sha256Hex -Path (Join-Path $script:legacyRoot $entry.File))
        }
    }

    It 'changes nothing in the folder' {
        $root = script:Copy-Fixture -Source $script:legacyRoot -Name 'legacy-read-only'
        $before = script:Get-FolderFingerprint -Root $root

        & $script:inventoryPath -Path $root | Out-Null

        script:Get-FolderFingerprint -Root $root | Should -Be $before
    }

    It 'finds no README, ledger, or migrated brief in a legacy folder, and no reason to warn' {
        $script:inventory.AlreadyMigrated | Should -Be $false
        $script:inventory.Readme | Should -BeNullOrEmpty
        $script:inventory.Ledger | Should -BeNullOrEmpty
        $script:inventory.PublishBriefNeeded | Should -Be $false
        @($script:inventory.Warning) | Should -HaveCount 0
        @($script:inventory.Prompt | ForEach-Object { $_.RemoteActionHint }) | Should -HaveCount 0
    }

    It 'recognizes a migrated folder and finds nothing left to convert' {
        $result = & $script:inventoryPath -Path $script:migratedRoot

        $result.AlreadyMigrated | Should -Be $true
        $result.Readme | Should -Be '00-README.md'
        $result.Ledger | Should -Be 'LEDGER.md'
        @($result.Prompt) | Should -HaveCount 3
        foreach ($entry in $result.Prompt) {
            @($entry.MissingSlot) | Should -HaveCount 0 -Because "$($entry.File) already carries every slot"
            $entry.ProposedName | Should -Be $entry.File
        }
    }

    It 'does not read the originals, reports, README, ledger, or migration report as prompts' {
        $result = & $script:inventoryPath -Path $script:migratedRoot

        @($result.Prompt | ForEach-Object { $_.File }) | Should -Be @('01-export-retry.prompt.md', '02-rename-setting.prompt.md', '03-document-retry.prompt.md')
    }

    It 'falls back to the file order, with a warning, when the names carry no ordinals' {
        $root = Join-Path $TestDrive 'no-ordinal'
        script:Set-FixtureText -Path (Join-Path $root 'beta.md') -Text "# Second`n"
        script:Set-FixtureText -Path (Join-Path $root 'alpha.md') -Text "# First`n"

        $result = & $script:inventoryPath -Path $root

        @($result.Prompt | ForEach-Object { $_.ProposedName }) | Should -Be @('01-alpha.prompt.md', '02-beta.prompt.md')
        @($result.Prompt | ForEach-Object { $_.NumberSource } | Select-Object -Unique) | Should -Be @('order')
        ($result.Warning -join ' ') | Should -Match 'order'
    }

    It 'falls back to the file order when two names share an ordinal' {
        $root = Join-Path $TestDrive 'shared-ordinal'
        script:Set-FixtureText -Path (Join-Path $root '1-first.md') -Text "# First`n"
        script:Set-FixtureText -Path (Join-Path $root '1-second.md') -Text "# Second`n"

        $result = & $script:inventoryPath -Path $root

        @($result.Prompt | ForEach-Object { $_.ProposedNumber }) | Should -Be @('01', '02')
        @($result.Prompt | ForEach-Object { $_.NumberSource } | Select-Object -Unique) | Should -Be @('order')
    }

    It 'renames a conforming name too when two names carry the same number' {
        $root = Join-Path $TestDrive 'shared-conforming-number'
        script:Set-FixtureText -Path (Join-Path $root '02-alpha.prompt.md') -Text "# Alpha`n"
        script:Set-FixtureText -Path (Join-Path $root '02-beta.prompt.md') -Text "# Beta`n"

        $result = & $script:inventoryPath -Path $root

        @($result.Prompt | ForEach-Object { $_.ProposedName }) | Should -Be @('01-alpha.prompt.md', '02-beta.prompt.md')
        @($result.Prompt | ForEach-Object { $_.NumberSource } | Select-Object -Unique) | Should -Be @('order')
    }

    It 'asks for a publish brief when a prompt needs a remote step and none collects them' {
        $root = Join-Path $TestDrive 'remote-step'
        script:Set-FixtureText -Path (Join-Path $root '1-change.md') -Text "# Change it`n`nPush the branch and open a pull request.`n"

        $result = & $script:inventoryPath -Path $root

        @($result.Prompt[0].RemoteActionHint) | Should -Contain 'push'
        @($result.Prompt[0].RemoteActionHint) | Should -Contain 'pull request'
        $result.PublishBriefNeeded | Should -Be $true
    }

    It 'does not ask for one when a publish brief already exists' {
        $root = Join-Path $TestDrive 'has-publish'
        script:Set-FixtureText -Path (Join-Path $root '1-change.md') -Text "# Change it`n`nPush the branch and open a pull request.`n"
        script:Set-FixtureText -Path (Join-Path $root '2-publish.md') -Text "# Publish the branch`n`nPush it, with approval.`n"

        (& $script:inventoryPath -Path $root).PublishBriefNeeded | Should -Be $false
    }

    It 'warns about a subfolder that holds prompt-like files it does not read' {
        $root = Join-Path $TestDrive 'subfolder'
        script:Set-FixtureText -Path (Join-Path $root 'prompts/one.md') -Text "# One`n"
        script:Set-FixtureText -Path (Join-Path $root '1-top.md') -Text "# Top`n"

        $result = & $script:inventoryPath -Path $root

        @($result.Prompt) | Should -HaveCount 1
        ($result.Warning -join ' ') | Should -Match 'prompts'
    }

    It 'treats a report that states no status as needs input, not Done' {
        $root = Join-Path $TestDrive 'report-without-status'
        script:Set-FixtureText -Path (Join-Path $root '1-change.md') -Text "# Change it`n"
        script:Set-FixtureText -Path (Join-Path $root 'reports/change.report.md') -Text "# Change it`n`nIt went fine.`n"

        $entry = (& $script:inventoryPath -Path $root).Prompt[0]

        $entry.Report | Should -Be 'reports/change.report.md'
        $entry.ProposedStatus | Should -Be 'needs input'
    }

    It 'matches a report to a prompt with a short name, which only an exact name can match' {
        $root = Join-Path $TestDrive 'short-name'
        script:Set-FixtureText -Path (Join-Path $root '1-db.md') -Text "# Move the db`n"
        script:Set-FixtureText -Path (Join-Path $root 'reports/db.report.md') -Text "# Move the db`n`n## Status`n`nDone`n"

        $entry = (& $script:inventoryPath -Path $root).Prompt[0]

        $entry.Report | Should -Be 'reports/db.report.md'
        $entry.ProposedStatus | Should -Be 'Done'
    }

    It 'gives a report to the prompt it names, not to a prompt whose name is a prefix of it' {
        $root = Join-Path $TestDrive 'prefix-names'
        script:Set-FixtureText -Path (Join-Path $root '1-add-retry.md') -Text "# Add the retry`n"
        script:Set-FixtureText -Path (Join-Path $root '2-add-retry-docs.md') -Text "# Document the retry`n"
        script:Set-FixtureText -Path (Join-Path $root 'reports/add-retry-docs.report.md') -Text "# Docs`n`n## Status`n`nDone`n"

        $result = & $script:inventoryPath -Path $root

        $result.Prompt[0].Report | Should -BeNullOrEmpty
        $result.Prompt[0].ProposedStatus | Should -Be 'Not started'
        $result.Prompt[1].Report | Should -Be 'reports/add-retry-docs.report.md'
        $result.Prompt[1].ProposedStatus | Should -Be 'Done'
    }

    It 'leaves a report that could belong to two prompts unowned, with a warning' {
        $root = Join-Path $TestDrive 'ambiguous-report'
        script:Set-FixtureText -Path (Join-Path $root '1-export-csv.md') -Text "# Export CSV`n"
        script:Set-FixtureText -Path (Join-Path $root '2-export-json.md') -Text "# Export JSON`n"
        script:Set-FixtureText -Path (Join-Path $root 'reports/export.report.md') -Text "# Export`n`n## Status`n`nDone`n"

        $result = & $script:inventoryPath -Path $root

        $result.Prompt[0].Report | Should -BeNullOrEmpty
        $result.Prompt[1].Report | Should -BeNullOrEmpty
        $result.Prompt[0].ProposedStatus | Should -Be 'Not started'
        ($result.Warning -join ' ') | Should -Match 'export\.report\.md could belong to 2 prompts'
    }

    It 'leaves a report that two prompts name equally unowned, with a warning' {
        $root = Join-Path $TestDrive 'same-name-report'
        script:Set-FixtureText -Path (Join-Path $root '1-sync.md') -Text "# Sync it`n"
        script:Set-FixtureText -Path (Join-Path $root '2-sync.md') -Text "# Sync it again`n"
        script:Set-FixtureText -Path (Join-Path $root 'reports/sync.report.md') -Text "# Sync`n`n## Status`n`nDone`n"

        $result = & $script:inventoryPath -Path $root

        $result.Prompt[0].Report | Should -BeNullOrEmpty
        $result.Prompt[1].Report | Should -BeNullOrEmpty
        ($result.Warning -join ' ') | Should -Match 'sync\.report\.md names 2 prompts equally'
    }

    It 'takes a commit from the text only when it has a digit and a letter, never a date or a word' {
        $root = Join-Path $TestDrive 'commit-token'
        $text = @'
# Change it

Start on `20261008`. The word `defaced` is not a commit. The commit is `a1b2c3d`.
'@
        script:Set-FixtureText -Path (Join-Path $root '1-change.md') -Text $text

        $entry = (& $script:inventoryPath -Path $root).Prompt[0]

        @($entry.Commit) | Should -Be @('a1b2c3d')
        $entry.ProposedStatus | Should -Be 'needs input'
        $entry.StatusSource | Should -Be 'none'
    }

    It 'warns when a folder that is not migrated already holds an originals folder' {
        $root = Join-Path $TestDrive 'has-originals'
        script:Set-FixtureText -Path (Join-Path $root '1-change.md') -Text "# Change it`n"
        script:Set-FixtureText -Path (Join-Path $root 'originals/old.md') -Text "# Old`n"

        $result = & $script:inventoryPath -Path $root

        ($result.Warning -join ' ') | Should -Match 'already holds an originals folder'
    }

    It 'keeps a note beside a migrated set out of the briefs, with a warning' {
        $root = script:Copy-Fixture -Source $script:migratedRoot -Name 'migrated-with-note'
        script:Set-FixtureText -Path (Join-Path $root 'notes.md') -Text "# My notes`n"

        $result = & $script:inventoryPath -Path $root

        $result.AlreadyMigrated | Should -Be $true
        @($result.Prompt) | Should -HaveCount 3
        ($result.Warning -join ' ') | Should -Match 'notes\.md sits beside a migrated set'
    }

    It 'does not call a folder migrated when its README and ledger carry other names' {
        $root = Join-Path $TestDrive 'other-names'
        script:Set-FixtureText -Path (Join-Path $root 'README.md') -Text "# Readme`n"
        script:Set-FixtureText -Path (Join-Path $root 'ledger.md') -Text "# Ledger`n"
        script:Set-FixtureText -Path (Join-Path $root '01-alpha.prompt.md') -Text "# Alpha`n"

        $result = & $script:inventoryPath -Path $root

        $result.AlreadyMigrated | Should -Be $false
        @($result.Original | ForEach-Object { $_.File }) | Should -Be @('01-alpha.prompt.md', 'README.md', 'ledger.md')
    }

    It 'lists only the briefs that lack a slot as the originals of a migrated folder' {
        $root = script:Copy-Fixture -Source $script:migratedRoot -Name 'migrated-missing-slot'
        $path = Join-Path $root '03-document-retry.prompt.md'
        script:Set-FixtureText -Path $path -Text (script:Read-RepositoryText -Path $path).Replace('## Validation', '## Checks')

        $result = & $script:inventoryPath -Path $root

        $result.AlreadyMigrated | Should -Be $true
        @($result.Original | ForEach-Object { $_.File }) | Should -Be @('03-document-retry.prompt.md')
        $result.Original[0].Sha256 | Should -Be (script:Get-Sha256Hex -Path $path)
        @($result.Prompt[2].MissingSlot) | Should -Contain 'Validation'
    }

    It 'keeps the numbers of the names that have one and numbers the rest after them' {
        $root = Join-Path $TestDrive 'mixed-numbers'
        script:Set-FixtureText -Path (Join-Path $root '02-alpha.prompt.md') -Text "# Alpha`n"
        script:Set-FixtureText -Path (Join-Path $root 'extra.md') -Text "# Extra`n"
        script:Set-FixtureText -Path (Join-Path $root 'more.txt') -Text "More`n"

        $result = & $script:inventoryPath -Path $root

        @($result.Prompt | ForEach-Object { $_.ProposedName }) | Should -Be @('02-alpha.prompt.md', '03-extra.prompt.md', '04-more.prompt.md')
        @($result.Prompt | ForEach-Object { $_.NumberSource } | Select-Object -Unique) | Should -Be @('mixed')
        ($result.Warning -join ' ') | Should -Match 'file order'
    }

    It 'numbers an unnumbered file after the ones that carry a number, whatever the file order' {
        $root = Join-Path $TestDrive 'mixed-legacy'
        script:Set-FixtureText -Path (Join-Path $root 'final.md') -Text "# Final`n"
        script:Set-FixtureText -Path (Join-Path $root 'P1-a.md') -Text "# A`n"
        script:Set-FixtureText -Path (Join-Path $root 'P2-b.md') -Text "# B`n"

        $result = & $script:inventoryPath -Path $root

        @($result.Prompt | ForEach-Object { $_.ProposedName }) | Should -Be @('01-a.prompt.md', '02-b.prompt.md', '03-final.prompt.md')
    }

    It 'does not give a report to a prompt that only has one of its words inside another word' {
        $root = Join-Path $TestDrive 'word-inside-word'
        script:Set-FixtureText -Path (Join-Path $root '1-latest-fixes.md') -Text "# Latest fixes`n"
        script:Set-FixtureText -Path (Join-Path $root 'reports/test.report.md') -Text "# Test`n`n## Status`n`nDone`n"

        $result = & $script:inventoryPath -Path $root

        $result.Prompt[0].Report | Should -BeNullOrEmpty
        $result.Prompt[0].ProposedStatus | Should -Be 'Not started'
        ($result.Warning -join ' ') | Should -Match 'reports/test\.report\.md matches no prompt'
    }

    It 'reads a prompt that is named like a report as a prompt' {
        $root = Join-Path $TestDrive 'report-named-prompt'
        script:Set-FixtureText -Path (Join-Path $root 'P1-intro.md') -Text "# Intro`n"
        script:Set-FixtureText -Path (Join-Path $root 'P2-weekly-report.md') -Text "# Write the weekly report`n"

        $result = & $script:inventoryPath -Path $root

        @($result.Prompt | ForEach-Object { $_.ProposedName }) | Should -Be @('01-intro.prompt.md', '02-weekly-report.prompt.md')
        @($result.Report) | Should -HaveCount 0
    }

    It 'reads a top-level NAME-report file as the report of the prompt NAME' {
        $root = Join-Path $TestDrive 'loose-report'
        script:Set-FixtureText -Path (Join-Path $root '1-export-retry.md') -Text "# Export retry`n"
        script:Set-FixtureText -Path (Join-Path $root 'export-retry-report.md') -Text "# Report`n`n## Status`n`nDone`n"

        $result = & $script:inventoryPath -Path $root

        @($result.Prompt) | Should -HaveCount 1
        $result.Prompt[0].Report | Should -Be 'export-retry-report.md'
        $result.Prompt[0].ProposedStatus | Should -Be 'Done'
    }

    It 'does not read a link, and says so' {
        $outside = Join-Path $TestDrive 'outside-prompt.md'
        script:Set-FixtureText -Path $outside -Text "# Secret plan`n`nAPI_KEY=value`n"
        $root = Join-Path $TestDrive 'linked-prompt'
        script:Set-FixtureText -Path (Join-Path $root '1-real.md') -Text "# Real`n"
        try {
            New-Item -ItemType SymbolicLink -Path (Join-Path $root '2-linked.md') -Target $outside -ErrorAction Stop | Out-Null
        } catch {
            Set-ItResult -Skipped -Because 'this account may not create symbolic links'
            return
        }

        $result = & $script:inventoryPath -Path $root

        @($result.Prompt | ForEach-Object { $_.File }) | Should -Be @('1-real.md')
        ($result.Warning -join ' ') | Should -Match '2-linked\.md is a link'
        ($result | ConvertTo-Json -Depth 6) | Should -Not -Match 'API_KEY'
    }

    It 'reads a heading line that is mostly blanks in linear time' {
        $root = Join-Path $TestDrive 'hostile-title'
        script:Set-FixtureText -Path (Join-Path $root '1-hostile.md') -Text ('# a' + (' ' * 60000) + "b`n")

        $run = script:Measure-Run { & $script:inventoryPath -Path $root }

        $run.Value.Prompt[0].Title | Should -Match '^a +b$'
        $run.Seconds | Should -BeLessThan 5
    }

    It 'throws when the folder does not exist' {
        { & $script:inventoryPath -Path (Join-Path $TestDrive 'absent') } | Should -Throw
    }
}

Describe 'Test-HandoffSequence on a migration' -Tag 'Unit' {
    BeforeAll {
        $script:legacyInventory = & $script:inventoryPath -Path $script:legacyRoot
    }

    It 'passes the migrated fixture, and every Warning is a needs input marker' {
        $result = & $script:validatorPath -Path $script:migratedRoot -Original $script:legacyInventory.Original

        $result.Passed | Should -Be $true
        $result.ErrorCount | Should -Be 0
        $result.BriefCount | Should -Be 3
        $result.RowCount | Should -Be 3
        @($result.Finding | Where-Object { $_.Code -ne 'NeedsInput' }) | Should -HaveCount 0
        $result.WarningCount | Should -BeGreaterThan 0
    }

    It 'passes the migrated fixture without the originals check' {
        (& $script:validatorPath -Path $script:migratedRoot).Passed | Should -Be $true
    }

    It 'reports an original that is missing' {
        $root = script:Copy-Fixture -Source $script:migratedRoot -Name 'missing-original'
        Remove-Item -LiteralPath (Join-Path $root 'originals/P2-rename-setting.md')

        $result = & $script:validatorPath -Path $root -Original $script:legacyInventory.Original

        $finding = script:Get-Finding -Result $result -Code 'OriginalMissing'
        $finding | Should -HaveCount 1
        $finding[0].Severity | Should -Be 'Error'
        $finding[0].Message | Should -Match 'P2-rename-setting\.md'
    }

    It 'reports an original that changed' {
        $root = script:Copy-Fixture -Source $script:migratedRoot -Name 'changed-original'
        Add-Content -LiteralPath (Join-Path $root 'originals/P3-document-retry.txt') -Value 'An edit.'

        $result = & $script:validatorPath -Path $root -Original $script:legacyInventory.Original

        $finding = script:Get-Finding -Result $result -Code 'OriginalChanged'
        $finding | Should -HaveCount 1
        $finding[0].Severity | Should -Be 'Error'
    }

    It 'accepts an original kept at its own path beside the migrated set' {
        $root = script:Copy-Fixture -Source $script:migratedRoot -Name 'original-in-place'
        Move-Item -LiteralPath (Join-Path $root 'originals/P1-export-retry.prompt.md') -Destination (Join-Path $root 'P1-export-retry.prompt.md')

        $result = & $script:validatorPath -Path $root -Original $script:legacyInventory.Original

        (script:Get-Finding -Result $result -Code 'OriginalMissing') | Should -BeNullOrEmpty
        (script:Get-Finding -Result $result -Code 'OriginalChanged') | Should -BeNullOrEmpty
    }

    It 'rejects an original list whose entries lack a file or a hash' {
        { & $script:validatorPath -Path $script:migratedRoot -Original @([pscustomobject]@{ File = 'x' }) } | Should -Throw
    }

    It 'accepts <Name> as the list of originals' -ForEach @(
        @{ Name = 'an empty list'; Value = @() }
        @{ Name = 'null'; Value = $null }
    ) {
        $result = & $script:validatorPath -Path $script:migratedRoot -Original $Value

        $result.Passed | Should -Be $true
    }

    It 'rejects an original named by a path that leaves the folder, without echoing it' -ForEach @(
        @{ Name = '../outside-secret.md' }
        @{ Name = '..\outside-secret.md' }
        @{ Name = 'reports/../../outside-secret.md' }
        @{ Name = 'C:\Windows\outside-secret.ini' }
        @{ Name = '/outside-secret.md' }
        @{ Name = 'stream:outside-secret' }
    ) {
        $result = & $script:validatorPath -Path $script:migratedRoot -Original @([pscustomobject]@{ File = $Name; Sha256 = ('AB' * 32) })

        $finding = script:Get-Finding -Result $result -Code 'OriginalPathInvalid'
        $finding | Should -HaveCount 1
        $finding[0].Severity | Should -Be 'Error'
        $finding[0].Message | Should -Not -Match 'outside-secret'
        $result.Passed | Should -Be $false
        (script:Get-Finding -Result $result -Code 'OriginalMissing') | Should -BeNullOrEmpty
    }

    It 'does not hash a file outside the folder when the original points at it' {
        $outside = Join-Path $TestDrive 'outside-the-folder.md'
        script:Set-FixtureText -Path $outside -Text "Outside.`n"
        $root = script:Copy-Fixture -Source $script:migratedRoot -Name 'traversal'
        $hash = script:Get-Sha256Hex -Path $outside

        $result = & $script:validatorPath -Path $root -Original @([pscustomobject]@{ File = '../outside-the-folder.md'; Sha256 = $hash })

        (script:Get-Finding -Result $result -Code 'OriginalPathInvalid') | Should -HaveCount 1
        $result.Passed | Should -Be $false
    }

    It 'fails the legacy folder with the findings a migration has to fix' {
        $result = & $script:validatorPath -Path $script:legacyRoot

        $result.Passed | Should -Be $false
        (script:Get-Finding -Result $result -Code 'ReadmeMissing').Severity | Should -Be 'Error'
        (script:Get-Finding -Result $result -Code 'LedgerMissing').Severity | Should -Be 'Error'
        (script:Get-Finding -Result $result -Code 'BriefNameInvalid').File | Should -Be 'P1-export-retry.prompt.md'
    }
}

Describe 'The migrated fixture' -Tag 'Unit' {
    BeforeAll {
        $script:ledgerText = script:Read-RepositoryText -Path (Join-Path $script:migratedRoot 'LEDGER.md')
    }

    It 'holds the expected ledger rows' {
        $script:ledgerText | Should -Match '(?m)^\| 01 \| Done \| `3f2a9c1` \|.*\[01\]\(reports/01-export-retry\.report\.md\) \|$'
        $script:ledgerText | Should -Match '(?m)^\| 02 \| Not started \|'
        $script:ledgerText | Should -Match '(?m)^\| 03 \| Not started \|'
    }

    It 'records the reconstructed status as an agent decision for review' {
        $script:ledgerText | Should -Match '(?m)^\| \d{4}-\d{2}-\d{2} \| 01 \|.*\| agent \|.*Flagged for your review\. \|$'
    }

    It 'keeps every original byte for byte' {
        foreach ($relative in @('P1-export-retry.prompt.md', 'P2-rename-setting.md', 'P3-document-retry.txt', 'reports/export-retry.report.md')) {
            script:Get-Sha256Hex -Path (Join-Path $script:migratedRoot ('originals/' + $relative)) |
                Should -Be (script:Get-Sha256Hex -Path (Join-Path $script:legacyRoot $relative))
        }
    }

    It 'keeps the original report as the report of the finished row, unchanged' {
        script:Get-Sha256Hex -Path (Join-Path $script:migratedRoot 'reports/01-export-retry.report.md') |
            Should -Be (script:Get-Sha256Hex -Path (Join-Path $script:legacyRoot 'reports/export-retry.report.md'))
    }

    It 'moves the repeated rule into the README shared rules and out of the briefs' {
        (script:Read-RepositoryText -Path (Join-Path $script:migratedRoot '00-README.md')) | Should -Match 'do not skip a failing test'

        foreach ($brief in @('01-export-retry.prompt.md', '02-rename-setting.prompt.md', '03-document-retry.prompt.md')) {
            (script:Read-RepositoryText -Path (Join-Path $script:migratedRoot $brief)) | Should -Not -Match 'do not skip a failing test'
        }
    }

    It 'marks each fact it could not supply needs input and keeps the agent it could read' {
        foreach ($entry in (& $script:inventoryPath -Path $script:legacyRoot).Prompt) {
            (script:Read-RepositoryText -Path (Join-Path $script:migratedRoot $entry.ProposedName)) | Should -Match ('(?m)^agent: {0}$' -f [regex]::Escape($entry.Agent))
        }
    }

    It 'names every original with its SHA-256 in the migration report' {
        $report = script:Read-RepositoryText -Path (Join-Path $script:migratedRoot 'migration-report.md')

        # The fixture is stored with LF endings, so the hash of the stored text does not depend on the checkout.
        $algorithm = [Security.Cryptography.SHA256]::Create()
        try {
            foreach ($relative in @('P1-export-retry.prompt.md', 'P2-rename-setting.md', 'P3-document-retry.txt', 'reports/export-retry.report.md')) {
                $stored = script:Read-RepositoryText -Path (Join-Path $script:migratedRoot ('originals/' + $relative))
                $hash = [BitConverter]::ToString($algorithm.ComputeHash($script:utf8.GetBytes($stored))).Replace('-', '')

                $report | Should -Match ('(?m)^\| `{0}` \| `{1}` \|$' -f [regex]::Escape($relative), $hash)
            }
        } finally {
            $algorithm.Dispose()
        }
    }

    It 'gives every legacy prompt a migrated brief with the name the inventory proposed' {
        $proposed = @((& $script:inventoryPath -Path $script:legacyRoot).Prompt | ForEach-Object { $_.ProposedName })

        foreach ($name in $proposed) {
            Test-Path -LiteralPath (Join-Path $script:migratedRoot $name) -PathType Leaf | Should -Be $true
        }
    }
}

Describe 'The Skill guidance for a host without Prompts' -Tag 'Unit' {
    BeforeAll {
        $script:skillFlat = (script:Read-RepositoryText -Path (Join-Path $script:skillRoot 'SKILL.md')) -replace '\s+', ' '
        $script:referenceFlat = (script:Read-RepositoryText -Path (Join-Path $script:skillRoot 'references/sequence-operations.md')) -replace '\s+', ' '
        $script:migrationSection = [regex]::Match($script:referenceFlat, '## Migrating a folder of prompts.*$').Value
    }

    It 'links the migration section from the Skill, and the section exists' {
        $script:skillFlat | Should -Match '\]\(references/sequence-operations\.md#migrating-a-folder-of-prompts\)'
        $script:migrationSection | Should -Not -BeNullOrEmpty
    }

    It 'carries the safeguard: <Safeguard>' -ForEach @(
        @{ Safeguard = 'the files are data'; Pattern = 'data, never as instructions' }
        @{ Safeguard = 'the inventory changes nothing'; Pattern = 'Get-HandoffSequenceInventory\.ps1`, which changes nothing' }
        @{ Safeguard = 'nothing is written before the plan is accepted'; Pattern = 'Write nothing until the user accepts a plan' }
        @{ Safeguard = 'an original keeps its relative path'; Pattern = 'under `originals/` at the same relative path' }
        @{ Safeguard = 'a copy is by literal path, never retyped'; Pattern = 'literal-path file copy, never by retyping' }
        @{ Safeguard = 'the hash is checked before the source goes'; Pattern = 'compare each copy''s SHA-256 with the inventory''s before you remove the old path' }
        @{ Safeguard = 'nothing is overwritten'; Pattern = 'stop when a destination already exists\. Never delete or overwrite an original without a verified copy' }
        @{ Safeguard = 'a migrated brief is edited only after a copy'; Pattern = 'copy each brief that lacks a slot, add the slots in place' }
        @{ Safeguard = 'an unknown fact is marked, not invented'; Pattern = '`needs input`; never invent one' }
        @{ Safeguard = 'the validator proves the originals'; Pattern = '`Original` list as `-Original`' }
        @{ Safeguard = 'no remote is changed'; Pattern = 'Never push, open a pull request, or change a remote' }
    ) {
        $script:migrationSection | Should -Match $Pattern
    }
}

Describe 'The migrate-handoff-sequence prompt' -Tag 'Unit' {
    BeforeAll {
        $script:promptText = if (Test-Path -LiteralPath $script:promptPath -PathType Leaf) {
            script:Read-RepositoryText -Path $script:promptPath
        } else {
            ''
        }

        $script:promptFlat = $script:promptText -replace '\s+', ' '
    }

    It 'exists beside the other Prompts' {
        Test-Path -LiteralPath $script:promptPath -PathType Leaf | Should -Be $true
    }

    It 'declares a description, a default agent, an argument hint, and no tool list' {
        $front = [regex]::Match($script:promptText, '(?s)\A---\n(?<body>.*?)\n---\n').Groups['body'].Value

        $front | Should -Match '(?m)^description: .{40,}$'
        $front | Should -Match '(?m)^agent: agent$'
        $front | Should -Match '(?m)^argument-hint: .+$'
        $front | Should -Not -Match '(?m)^tools:' -Because 'a Prompt that names no Custom agent cannot widen or narrow a tool boundary it cannot verify'
    }

    It 'covers the step: <Step>' -ForEach $script:stepCase {
        $script:promptFlat | Should -Match $Pattern
    }

    It 'names the four templates it writes from' {
        foreach ($name in @('task-ledger', 'sequence-readme', 'brief', 'report')) {
            $script:promptText | Should -Match ('assets/{0}\.template\.md' -f $name)
        }
    }

    It 'stays short, the way a Prompt does' {
        @($script:promptText -split "`n").Count | Should -BeLessOrEqual 90
    }

    It 'links the inventory script from the Skill, so it can be found without the Prompt' {
        (script:Read-RepositoryText -Path (Join-Path $script:skillRoot 'SKILL.md')) | Should -Match '\]\(scripts/Get-HandoffSequenceInventory\.ps1\)'
        (script:Read-RepositoryText -Path (Join-Path $script:skillRoot 'SKILL.md')) | Should -Match '/migrate-handoff-sequence'
    }
}
