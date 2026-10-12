$script:repoRoot = Split-Path -Parent $PSScriptRoot
$script:skillRoot = Join-Path $script:repoRoot 'skills/subagent-dispatch'

$script:templateCase = @(
    foreach ($name in @('task-ledger', 'sequence-readme', 'brief', 'report')) {
        @{
            TemplateName = $name
            TemplatePath = Join-Path $script:skillRoot ('assets/{0}.template.md' -f $name)
        }
    }
)

# Each rule the Skill has to carry, as a pattern over the Skill body and its
# reference. A pattern names the rule's distinctive wording, not the whole rule.
$script:ruleCase = @(
    @{ Rule = 'creates the ledger before the first task runs'; Pattern = '(?is)create the ledger.{0,120}before the first task' }
    @{ Rule = 'gives every planned task a row that starts Not started'; Pattern = '(?is)one row per planned task.{0,80}`Not started`' }
    @{ Rule = 'names the five statuses as one vocabulary'; Pattern = '(?is)`Not started`.{0,300}`Done`.{0,300}`Done with concerns`.{0,300}`Needs context`.{0,300}`Blocked`' }
    @{ Rule = 'keeps one writer per row'; Pattern = '(?is)one writer per row' }
    @{ Rule = 'has the controller write rows after verifying the report'; Pattern = '(?is)controller writes each row after verifying' }
    @{ Rule = 'has each user-run brief write only its own row'; Pattern = '(?is)writes only its own row' }
    @{ Rule = 'gates a start on the rows a task depends on'; Pattern = '(?is)start a task only when every row it depends on' }
    @{ Rule = 'accepts a ruling that lets a task proceed without a dependency'; Pattern = '(?is)ruling that lets the task proceed without it' }
    @{ Rule = 'makes every earlier row a non-default dependency'; Pattern = '(?is)every earlier row' }
    @{ Rule = 'checks that a row''s commits exist on the integration branch'; Pattern = '(?is)git cat-file -e.{0,300}git merge-base --is-ancestor' }
    @{ Rule = 'checks that a row''s report file exists'; Pattern = '(?is)report file exists' }
    @{ Rule = 'stops for a ruling on a mismatch instead of correcting the ledger'; Pattern = '(?is)never correct the ledger silently' }
    @{ Rule = 'reads its own row before resuming'; Pattern = '(?is)read your own row.{0,200}not `Done`' }
    @{ Rule = 'records who decided each ruling'; Pattern = '(?is)`user`.{0,40}`agent`.{0,60}`agent under delegation`' }
    @{ Rule = 'flags a not sure, you pick answer for review'; Pattern = '(?is)`not sure, you pick`.{0,120}review' }
    @{ Rule = 'appends a dated Update section instead of rewriting a brief'; Pattern = '(?is)dated `Update` section.{0,200}takes precedence' }
    @{ Rule = 'lists wrong brief facts under Evidence corrections'; Pattern = '(?is)Evidence corrections' }
    @{ Rule = 'gives a task added mid-sequence a README row, a ledger row, and a ruling'; Pattern = '(?is)added mid-sequence.{0,200}README row.{0,80}ledger row.{0,80}ruling' }
    @{ Rule = 're-homes every dependency that waited on a task that left'; Pattern = '(?is)re-home' }
    @{ Rule = 'appends a superseding ruling when a status changes'; Pattern = '(?is)supersede' }
    @{ Rule = 'has a place for work after the last row'; Pattern = '(?is)After the last row' }
    @{ Rule = 'keeps the Memory Bank entry short'; Pattern = '(?is)Memory Bank entry stays short' }
    @{ Rule = 'writes what only the chat knows down before archiving'; Pattern = '(?is)archived.{0,300}ledger' }
    @{ Rule = 'treats a delegation as a ruling with limits'; Pattern = '(?is)delegation.{0,200}limits' }
    @{ Rule = 'never lets a delegated answer authorize a risky action'; Pattern = '(?is)never authorizes a remote, destructive, or security-relevant action' }
    @{ Rule = 'collects remote steps in a final publish brief with approval per action'; Pattern = '(?is)publish brief.{0,300}approval per action|approval per action.{0,300}publish brief' }
    @{ Rule = 'hands a command over in its own fenced code block'; Pattern = '(?is)its own fenced code block' }
    @{ Rule = 'hands a command over only in the final reply of the turn'; Pattern = '(?is)final reply' }
    @{ Rule = 'keeps a command out of the text of a question'; Pattern = '(?is)never inside the text of a question' }
    @{ Rule = 'verifies a handed-over command read-only'; Pattern = '(?is)read-only' }
    @{ Rule = 'says the guard matches command text, not intent'; Pattern = '(?is)matches command text, not intent' }
    @{ Rule = 'never reshapes a command to pass the guard'; Pattern = '(?is)never reshape a command' }
    @{ Rule = 'names the branch that holds the current record'; Pattern = '(?is)branch that holds the current record' }
    @{ Rule = 'simulates an irreversible step in a throwaway clone'; Pattern = '(?is)throwaway clone' }
    @{ Rule = 'carries repository state to another machine as a verified bundle'; Pattern = '(?is)git bundle verify' }
    @{ Rule = 'records the bundle hash in the brief and the ledger'; Pattern = '(?is)SHA-256.{0,200}ledger' }
    @{ Rule = 'takes one bundle back per repository changed'; Pattern = '(?is)one bundle per repository' }
    @{ Rule = 'checks by ancestry before syncing returned work'; Pattern = '(?is)ancestry' }
    @{ Rule = 'stops for a ruling on a divergence'; Pattern = '(?is)divergence stops' }
    @{ Rule = 'has the controller verify the row, the diff, and the report before the next dispatch'; Pattern = '(?is)controller verifies the row, the diff, and the report before the next dispatch' }
    @{ Rule = 'warns that tool output can mask a secret-looking string'; Pattern = '(?is)`\*{6}`' }
    @{ Rule = 'says source material outlives its sequence'; Pattern = '(?is)source material outlives' }
    @{ Rule = 'names the boundary with the session-handoff prompt'; Pattern = '(?is)`session-handoff`' }
    @{ Rule = 'names the boundary with the spec-completion-controller ledger'; Pattern = '(?is)`spec-completion-controller`' }
    @{ Rule = 'runs the validator after creating or changing a sequence'; Pattern = '(?is)Test-HandoffSequence\.ps1' }
)

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:skillRoot = Join-Path $script:repoRoot 'skills/subagent-dispatch'
    $script:skillPath = Join-Path $script:skillRoot 'SKILL.md'
    $script:assetRoot = Join-Path $script:skillRoot 'assets'
    $script:referencePath = Join-Path $script:skillRoot 'references/sequence-operations.md'
    $script:validatorPath = Join-Path $script:skillRoot 'scripts/Test-HandoffSequence.ps1'

    $script:utf8 = [Text.UTF8Encoding]::new($false)

    # Line endings differ by checkout (md is LF, ps1 is CRLF), so every read normalizes to LF.
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

    # Prose wraps at about 80 columns, so every run of whitespace collapses to one space before a phrase is matched.
    function script:Get-SkillBodyText {
        [CmdletBinding()]
        [OutputType([string])]
        param()

        $text = script:Read-RepositoryText -Path $script:skillPath
        if (Test-Path -LiteralPath $script:referencePath -PathType Leaf) {
            $text += "`n" + (script:Read-RepositoryText -Path $script:referencePath)
        }

        $text -replace '\s+', ' '
    }

    # Writes with no byte order mark and LF endings, the way the repository stores Markdown.
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

    # Fills every {{key}} or {{key: guidance}} slot. A key without a value reads "example".
    function script:Expand-Template {
        [CmdletBinding()]
        [OutputType([string])]
        param(
            [Parameter(Mandatory)]
            [AllowEmptyString()]
            [string] $Text,

            [Parameter()]
            [hashtable] $Value = @{}
        )

        $slot = [regex]::Matches($Text, '\{\{(?<key>[a-z0-9-]+)(?::[^{}]*)?\}\}')
        foreach ($token in @($slot | ForEach-Object { $_.Value } | Select-Object -Unique)) {
            $key = [regex]::Match($token, '\{\{(?<key>[a-z0-9-]+)').Groups['key'].Value
            $replacement = if ($Value.ContainsKey($key)) { [string]$Value[$key] } else { 'example' }
            $Text = $Text.Replace($token, $replacement)
        }

        $Text
    }

    # One brief, built from the four templates, that the validator has to accept.
    function script:New-SequenceFolder {
        [CmdletBinding()]
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            'PSUseShouldProcessForStateChangingFunctions',
            '',
            Justification = 'Pester fixture helper writes only isolated test data.'
        )]
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $Root
        )

        $value = @{
            'nn'                 = '01'
            'slug'               = 'example'
            'title'              = 'Example task'
            'agent'              = 'software-engineer'
            'review'             = 'off'
            'depends-on'         = 'none'
            'needs-you-for'      = 'none'
            'integration-branch' = 'main'
            'total'              = '1'
            'status'             = 'Done'
        }

        $template = @{}
        foreach ($name in @('task-ledger', 'sequence-readme', 'brief', 'report')) {
            $template[$name] = script:Read-RepositoryText -Path (Join-Path $script:assetRoot ('{0}.template.md' -f $name))
        }

        script:Set-FixtureText -Path (Join-Path $Root '00-README.md') -Text (script:Expand-Template -Text $template['sequence-readme'] -Value $value)
        script:Set-FixtureText -Path (Join-Path $Root 'LEDGER.md') -Text (script:Expand-Template -Text $template['task-ledger'] -Value $value)
        script:Set-FixtureText -Path (Join-Path $Root '01-example.prompt.md') -Text (script:Expand-Template -Text $template['brief'] -Value $value)
        New-Item -ItemType Directory -Path (Join-Path $Root 'reports') -Force | Out-Null
        $script:reportText = script:Expand-Template -Text $template['report'] -Value $value
    }

    function script:Get-FolderFingerprint {
        [CmdletBinding()]
        [OutputType([string[]])]
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $Root
        )

        # .NET, not Get-FileHash: Windows PowerShell 5.1 cannot always resolve that cmdlet inside a Pester It.
        $algorithm = [Security.Cryptography.SHA256]::Create()
        try {
            @(
                Get-ChildItem -LiteralPath $Root -Recurse -File |
                    Sort-Object -Property FullName |
                    ForEach-Object { '{0}|{1}' -f $_.FullName.Substring($Root.Length), [BitConverter]::ToString($algorithm.ComputeHash([IO.File]::ReadAllBytes($_.FullName))) }
            )
        } finally {
            $algorithm.Dispose()
        }
    }

    # Builds a folder, applies one change to it, and returns what the validator says.
    function script:Test-Sequence {
        [CmdletBinding()]
        [OutputType([psobject])]
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $Name,

            [Parameter()]
            [scriptblock] $Mutate,

            [Parameter()]
            [hashtable] $Parameter = @{}
        )

        $root = Join-Path $TestDrive $Name
        script:New-SequenceFolder -Root $root
        if ($Mutate) {
            & $Mutate $root
        }

        & $script:validatorPath -Path $root @Parameter
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

    function script:Edit-FixtureText {
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
            [string] $Old,

            [Parameter(Mandatory)]
            [AllowEmptyString()]
            [string] $New
        )

        $text = script:Read-RepositoryText -Path $Path
        if (-not $text.Contains($Old)) {
            throw "Fixture edit found no '$Old' in $Path."
        }

        script:Set-FixtureText -Path $Path -Text $text.Replace($Old, $New)
    }

    # Runs git without letting stderr turn into a terminating error on Windows PowerShell 5.1.
    function script:Invoke-TestGit {
        [CmdletBinding()]
        [OutputType([string])]
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string] $Repository,

            [Parameter(Mandatory)]
            [string[]] $Argument
        )

        $previous = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $output = & git -C $Repository -c user.name=Fixture -c user.email=fixture@example.invalid -c commit.gpgsign=false @Argument 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "git $($Argument -join ' ') failed: $output"
            }

            ($output | Out-String).Trim()
        }
        finally {
            $ErrorActionPreference = $previous
        }
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

    $script:hasGit = $null -ne (Get-Command -Name git -CommandType Application -ErrorAction SilentlyContinue)
}

Describe 'subagent-dispatch ledger guidance' -Tag 'Unit' {
    It 'covers the rule: <Rule>' -ForEach $script:ruleCase {
        script:Get-SkillBodyText | Should -Match $Pattern -Because 'the Skill has to state the rule, not leave it to the agent'
    }

    It 'keeps the body within the 500-line budget' {
        $line = @(Get-Content -LiteralPath $script:skillPath -Encoding UTF8)
        $delimiter = @(for ($index = 0; $index -lt $line.Count; $index++) { if ($line[$index] -eq '---') { $index } })

        ($line.Count - ($delimiter[1] + 1)) | Should -BeLessOrEqual 500
    }

    It 'declares that its scripts need PowerShell and its row check needs git' {
        $text = script:Read-RepositoryText -Path $script:skillPath
        $compatibility = [regex]::Match($text, '(?s)compatibility:\s*>-\s*(?<value>.+?)\n---').Groups['value'].Value -replace '\s+', ' '

        $compatibility | Should -Match 'PowerShell 5\.1'
        $compatibility | Should -Match '\bgit\b'
        $compatibility.Length | Should -BeLessOrEqual 500
    }

    It 'links <TemplateName> with the condition for loading it' -ForEach $script:templateCase {
        $row = @(
            (script:Read-RepositoryText -Path $script:skillPath) -split "`n" |
                Where-Object { $_ -match ('\]\(assets/{0}\.template\.md\)' -f [regex]::Escape($TemplateName)) }
        )

        $row | Should -HaveCount 1 -Because 'one row names the template and when to load it'
        $row[0] | Should -Match '\|\s*[^|]{20,}\|\s*$' -Because 'the load condition has to sit beside the link'
    }

    It 'links every reference and script, and every link resolves' {
        $text = script:Read-RepositoryText -Path $script:skillPath
        $target = @(
            [regex]::Matches($text, '\]\((?<path>(?:assets|references|scripts)/[^)#\s]+)') |
                ForEach-Object { $_.Groups['path'].Value } |
                Select-Object -Unique
        )

        foreach ($relative in $target) {
            Test-Path -LiteralPath (Join-Path $script:skillRoot $relative) -PathType Leaf |
                Should -Be $true -Because "SKILL.md links $relative"
        }

        $shipped = @(
            foreach ($folder in @('assets', 'references', 'scripts')) {
                $folderPath = Join-Path $script:skillRoot $folder
                if (Test-Path -LiteralPath $folderPath -PathType Container) {
                    Get-ChildItem -LiteralPath $folderPath -File | ForEach-Object { '{0}/{1}' -f $folder, $_.Name }
                }
            }
        )

        $shipped | Should -Not -BeNullOrEmpty
        foreach ($relative in $shipped) {
            if ($relative -eq 'scripts/HandoffSequenceCommon.ps1') {
                continue
            }

            $target | Should -Contain $relative -Because "$relative ships in the Skill, so the body has to say when to load it"
        }
    }

    It 'adds the ledger rows of the anti-rationalization table and the red flags' {
        $text = script:Read-RepositoryText -Path $script:skillPath
        $table = [regex]::Match($text, '(?s)## Anti-rationalization table(?<body>.+?)\n## ').Groups['body'].Value
        $flag = [regex]::Match($text, '(?s)## Red flags(?<body>.+?)\n## ').Groups['body'].Value

        $table | Should -Match '(?i)previous row' -Because 'building on a row nobody checked is the discipline failure the ledger rules close'
        $table | Should -Match '(?i)correct it'
        $table | Should -Match '(?i)delegat|you decide'
        $table | Should -Match '(?i)question'
        $table | Should -Match '(?i)guard'
        $flag | Should -Match '(?i)no ledger row'
        $flag | Should -Match '(?i)question'
        $flag | Should -Match '(?i)Depends on|dependenc'
    }

    It 'closes the Verification section on the ledger' {
        $text = script:Read-RepositoryText -Path $script:skillPath
        $verification = [regex]::Match($text, '(?s)## Verification(?<body>.+)$').Groups['body'].Value

        $verification | Should -Match '(?i)ledger'
        $verification | Should -Match '(?i)decided'
        $verification | Should -Match 'Test-HandoffSequence'
    }

    It 'uses the ledger status vocabulary for the report statuses' {
        (script:Read-RepositoryText -Path $script:skillPath) | Should -Match '\|\s*Done with concerns\s*\|'
    }
}

Describe 'Task ledger templates' -Tag 'Unit' {
    It '<TemplateName> exists and carries only well-formed slots' -ForEach $script:templateCase {
        Test-Path -LiteralPath $TemplatePath -PathType Leaf | Should -Be $true

        $text = script:Read-RepositoryText -Path $TemplatePath
        $slot = @([regex]::Matches($text, '\{\{(?<key>[a-z0-9-]+)(?::[^{}]*)?\}\}'))
        $slot.Count | Should -BeGreaterThan 0 -Because 'a template with no slot is a document'

        $stripped = [regex]::Replace($text, '\{\{(?<key>[a-z0-9-]+)(?::[^{}]*)?\}\}', '')
        $stripped | Should -Not -Match '\{\{|\}\}' -Because 'a malformed slot would survive into the sequence unnoticed'
    }

    It '<TemplateName> ends with a single newline' -ForEach $script:templateCase {
        $text = script:Read-RepositoryText -Path $TemplatePath

        $text.EndsWith("`n") | Should -Be $true
        $text.EndsWith("`n`n") | Should -Be $false
    }

    Context 'The ledger' {
        BeforeAll {
            $script:ledgerTemplate = script:Read-RepositoryText -Path (Join-Path $script:assetRoot 'task-ledger.template.md')
        }

        It 'starts every row Not started and names the integration branch in the commits column' {
            $script:ledgerTemplate | Should -Match '(?m)^\| # \| Status \| Commits on \{\{integration-branch[^}]*\}\} \| Validation \| Open findings \| Report \|$'
            $script:ledgerTemplate | Should -Match '(?m)^\| \{\{nn[^}]*\}\} \| Not started \|'
        }

        It 'lists the five statuses once' {
            $script:ledgerTemplate | Should -Match '`Not started`, `Done`, `Done with concerns`, `Needs context`, `Blocked`'
        }

        It 'marks who decided each ruling' {
            $script:ledgerTemplate | Should -Match '(?m)^\| Date \| Brief \| Question \| Decided by \| Answer \|$'
            $script:ledgerTemplate | Should -Match '`user`'
            $script:ledgerTemplate | Should -Match '`agent under delegation`'
        }

        It 'has a place for work after the last row' {
            $script:ledgerTemplate | Should -Match '(?m)^## After the last row$'
        }
    }

    Context 'The sequence README' {
        BeforeAll {
            $script:readmeTemplate = script:Read-RepositoryText -Path (Join-Path $script:assetRoot 'sequence-readme.template.md')
        }

        It 'has an order table with a Depends on column' {
            $script:readmeTemplate | Should -Match '(?m)^\| # \| Brief \| Scope \| Agent \| Model tier \| Review \| Depends on \| Needs you for \|$'
        }

        It 'says a brief starts only on the rows it depends on' {
            $script:readmeTemplate | Should -Match '(?is)starts only when each'
            $script:readmeTemplate | Should -Match '(?is)every earlier row'
        }

        It 'carries the section <Heading>' -ForEach @(
            @{ Heading = 'How to run' }
            @{ Heading = 'Branch' }
            @{ Heading = 'Source material' }
            @{ Heading = 'Other machines' }
            @{ Heading = 'Shared rules' }
            @{ Heading = 'Report contract' }
            @{ Heading = 'Decisions waiting for you' }
        ) {
            $script:readmeTemplate | Should -Match ('(?m)^## {0}$' -f [regex]::Escape($Heading))
        }

        It 'names the branch that holds the current record' {
            $script:readmeTemplate | Should -Match '(?is)branch that holds the current record'
        }
    }

    Context 'The brief' {
        BeforeAll {
            $script:briefTemplate = script:Read-RepositoryText -Path (Join-Path $script:assetRoot 'brief.template.md')
        }

        It 'opens with front matter that declares a description and an agent' {
            $script:briefTemplate | Should -Match '(?s)\A---\ndescription: [^\n]+\nagent: [^\n]+\n---\n'
        }

        It 'points to the sequence README' {
            $script:briefTemplate | Should -Match '\]\(00-README\.md\)'
        }

        It 'carries the section <Heading>' -ForEach @(
            @{ Heading = 'Preconditions' }
            @{ Heading = 'Evidence' }
            @{ Heading = 'Ask first' }
            @{ Heading = 'Tasks' }
            @{ Heading = 'Validation' }
            @{ Heading = 'Finish' }
        ) {
            $script:briefTemplate | Should -Match ('(?m)^## {0}$' -f [regex]::Escape($Heading))
        }

        It 'checks its own row and each dependency row before it starts' {
            $script:briefTemplate | Should -Match '(?i)own row'
            $script:briefTemplate | Should -Match '(?i)dependency rows?'
            $script:briefTemplate | Should -Match 'git cat-file -e'
            $script:briefTemplate | Should -Match 'git merge-base --is-ancestor'
            $script:briefTemplate | Should -Match '(?i)report file exists'
        }

        It 'finishes with the commit message, the report path, and the ledger row' {
            $finish = [regex]::Match($script:briefTemplate, '(?s)## Finish(?<body>.+)$').Groups['body'].Value

            $finish | Should -Match '(?i)commit'
            $finish | Should -Match 'reports/'
            $finish | Should -Match '(?i)ledger row'
        }
    }

    Context 'The report' {
        BeforeAll {
            $script:reportTemplate = script:Read-RepositoryText -Path (Join-Path $script:assetRoot 'report.template.md')
        }

        It 'carries the section <Heading>' -ForEach @(
            @{ Heading = 'Status' }
            @{ Heading = 'Commits' }
            @{ Heading = 'Changed files' }
            @{ Heading = 'Validation' }
            @{ Heading = 'Evidence corrections' }
            @{ Heading = 'Open findings' }
            @{ Heading = 'Rulings' }
            @{ Heading = 'Changes to later assumptions' }
        ) {
            $script:reportTemplate | Should -Match ('(?m)^## {0}$' -f [regex]::Escape($Heading))
        }

        It 'lists the four report statuses' {
            $script:reportTemplate | Should -Match '`Done`.{0,40}`Done with concerns`.{0,40}`Needs context`.{0,40}`Blocked`'
        }

        It 'marks who decided each ruling' {
            $script:reportTemplate | Should -Match '(?m)^\| Question \| Decided by \| Answer \|$'
        }
    }
}

Describe 'Test-HandoffSequence' -Tag 'Unit' {
    BeforeAll {
        $script:accountPath = 'C:' + '\Users\' + 'example-account' + '\Desktop\handoffs'
        $script:unixAccountPath = '/' + 'home' + '/example-account/handoffs'
    }

    It 'ships with comment-based help' {
        Test-Path -LiteralPath $script:validatorPath -PathType Leaf | Should -Be $true

        $help = Get-Help -Name $script:validatorPath -Full
        $help.Synopsis | Should -Not -BeLike 'Test-HandoffSequence*'
        @($help.Parameters.Parameter | ForEach-Object { $_.Name }) | Should -Contain 'Path'
        @($help.Examples.Example).Count | Should -BeGreaterThan 0
    }

    Context 'A sequence built from the templates' {
        It 'passes with no error and no warning' {
            $result = script:Test-Sequence -Name 'valid'

            $result.Finding | Should -BeNullOrEmpty
            $result.Passed | Should -Be $true
            $result.ErrorCount | Should -Be 0
            $result.WarningCount | Should -Be 0
            $result.BriefCount | Should -Be 1
            $result.RowCount | Should -Be 1
        }

        It 'does not change the folder' {
            $root = Join-Path $TestDrive 'read-only'
            script:New-SequenceFolder -Root $root
            $before = script:Get-FolderFingerprint -Root $root

            & $script:validatorPath -Path $root | Out-Null

            script:Get-FolderFingerprint -Root $root | Should -Be $before
        }

        It 'accepts a folder path that contains spaces' {
            $root = Join-Path $TestDrive 'a folder with spaces'
            script:New-SequenceFolder -Root $root

            (& $script:validatorPath -Path $root).Passed | Should -Be $true
        }

        It 'leaves the originals folder alone' {
            $result = script:Test-Sequence -Name 'originals' -Mutate {
                param($root)
                script:Set-FixtureText -Path (Join-Path $root 'originals/old.md') -Text ('See {{unfilled}} at ' + $script:accountPath + "`n[gone](missing.md)`n")
            }

            $result.Passed | Should -Be $true
            $result.WarningCount | Should -Be 0
        }

        It 'throws when the folder does not exist' {
            { & $script:validatorPath -Path (Join-Path $TestDrive 'absent') } | Should -Throw
        }
    }

    Context 'The folder skeleton' {
        It 'reports a missing README' {
            $result = script:Test-Sequence -Name 'no-readme' -Mutate { param($root) Remove-Item -LiteralPath (Join-Path $root '00-README.md') }

            (script:Get-Finding -Result $result -Code 'ReadmeMissing').Severity | Should -Be 'Error'
            $result.Passed | Should -Be $false
        }

        It 'reports a missing ledger' {
            $result = script:Test-Sequence -Name 'no-ledger' -Mutate { param($root) Remove-Item -LiteralPath (Join-Path $root 'LEDGER.md') }

            (script:Get-Finding -Result $result -Code 'LedgerMissing').Severity | Should -Be 'Error'
        }

        It 'reports a brief that has no ledger row' {
            $result = script:Test-Sequence -Name 'brief-without-row' -Mutate {
                param($root)
                Copy-Item -LiteralPath (Join-Path $root '01-example.prompt.md') -Destination (Join-Path $root '02-second.prompt.md')
            }

            $finding = script:Get-Finding -Result $result -Code 'BriefWithoutRow'
            $finding | Should -HaveCount 1
            $finding[0].File | Should -Be '02-second.prompt.md'
            $finding[0].Severity | Should -Be 'Error'
            (script:Get-Finding -Result $result -Code 'ReadmeRowMissing') | Should -HaveCount 1
        }

        It 'reports a ledger row that has no brief' {
            $result = script:Test-Sequence -Name 'row-without-brief' -Mutate {
                param($root)
                script:Edit-FixtureText -Path (Join-Path $root 'LEDGER.md') -Old '| 01 | Not started | | | | |' -New "| 01 | Not started | | | | |`n| 02 | Not started | | | | |"
            }

            $finding = script:Get-Finding -Result $result -Code 'RowWithoutBrief'
            $finding | Should -HaveCount 1
            $finding[0].Message | Should -Match '02'
        }

        It 'warns about a prompt file whose name does not follow NN-slug.prompt.md' {
            $result = script:Test-Sequence -Name 'odd-name' -Mutate {
                param($root)
                Copy-Item -LiteralPath (Join-Path $root '01-example.prompt.md') -Destination (Join-Path $root 'Odd Name.prompt.md')
            }

            (script:Get-Finding -Result $result -Code 'BriefNameInvalid').Severity | Should -Be 'Warning'
            $result.Passed | Should -Be $true
        }
    }

    Context 'The ledger' {
        It 'rejects a status outside the vocabulary' {
            $result = script:Test-Sequence -Name 'bad-status' -Mutate {
                param($root)
                script:Edit-FixtureText -Path (Join-Path $root 'LEDGER.md') -Old '| 01 | Not started |' -New '| 01 | In progress |'
            }

            $finding = script:Get-Finding -Result $result -Code 'StatusInvalid'
            $finding | Should -HaveCount 1
            $finding[0].Severity | Should -Be 'Error'
        }

        It 'reports a ledger with no status table' {
            $result = script:Test-Sequence -Name 'no-status-table' -Mutate {
                param($root)
                script:Set-FixtureText -Path (Join-Path $root 'LEDGER.md') -Text "# Ledger`n`n## Rulings`n`n| Date | Brief | Question | Decided by | Answer |`n| --- | --- | --- | --- | --- |`n"
            }

            (script:Get-Finding -Result $result -Code 'StatusTableMissing').Severity | Should -Be 'Error'
        }

        It 'reports a Rulings table that does not say who decided' {
            $result = script:Test-Sequence -Name 'no-decider' -Mutate {
                param($root)
                script:Edit-FixtureText -Path (Join-Path $root 'LEDGER.md') -Old '| Date | Brief | Question | Decided by | Answer |' -New '| Date | Brief | Question | Answer |'
                script:Edit-FixtureText -Path (Join-Path $root 'LEDGER.md') -Old '| --- | --- | --- | --- | --- |' -New '| --- | --- | --- | --- |'
            }

            (script:Get-Finding -Result $result -Code 'DecidedByColumnMissing').Severity | Should -Be 'Error'
        }

        It 'reports a ruling whose Decided by is empty or unknown' {
            $result = script:Test-Sequence -Name 'bad-decider' -Mutate {
                param($root)
                $path = Join-Path $root 'LEDGER.md'
                $text = script:Read-RepositoryText -Path $path
                $row = "| 2026-01-01 | 01 | A question? | | An answer. |`n| 2026-01-02 | 01 | Another? | the team | Yes. |`n| 2026-01-03 | 01 | Third? | agent | Yes. |`n"
                $marker = '| Date | Brief | Question | Decided by | Answer |'
                $header = $text.IndexOf($marker)
                $delimiterEnd = $text.IndexOf("`n", $text.IndexOf("`n", $header) + 1) + 1
                script:Set-FixtureText -Path $path -Text ($text.Substring(0, $delimiterEnd) + $row + $text.Substring($delimiterEnd))
            }

            (script:Get-Finding -Result $result -Code 'DecidedByInvalid') | Should -HaveCount 2
        }

        It 'accepts user, agent, and agent under delegation as the decider' {
            $result = script:Test-Sequence -Name 'good-decider' -Mutate {
                param($root)
                $path = Join-Path $root 'LEDGER.md'
                $text = script:Read-RepositoryText -Path $path
                $row = "| 2026-01-01 | 01 | Q1? | user | A. |`n| 2026-01-02 | 01 | Q2? | agent | A. |`n| 2026-01-03 | after 01 | Q3? | agent under delegation | A. |`n"
                $marker = '| Date | Brief | Question | Decided by | Answer |'
                $header = $text.IndexOf($marker)
                $delimiterEnd = $text.IndexOf("`n", $text.IndexOf("`n", $header) + 1) + 1
                script:Set-FixtureText -Path $path -Text ($text.Substring(0, $delimiterEnd) + $row + $text.Substring($delimiterEnd))
            }

            (script:Get-Finding -Result $result -Code 'DecidedByInvalid') | Should -BeNullOrEmpty
            $result.Passed | Should -Be $true
        }

        It 'warns when the ledger has no place for work after the last row' {
            $result = script:Test-Sequence -Name 'no-after' -Mutate {
                param($root)
                script:Edit-FixtureText -Path (Join-Path $root 'LEDGER.md') -Old '## After the last row' -New '## Later'
            }

            (script:Get-Finding -Result $result -Code 'AfterLastRowMissing').Severity | Should -Be 'Warning'
        }

        It 'warns when a finished row records no commits' {
            $result = script:Test-Sequence -Name 'no-commits' -Mutate {
                param($root)
                script:Edit-FixtureText -Path (Join-Path $root 'LEDGER.md') -Old '| 01 | Not started | | | | |' -New '| 01 | Done | | passed | none | [01](reports/01-example.report.md) |'
                script:Set-FixtureText -Path (Join-Path $root 'reports/01-example.report.md') -Text "# 01`n`n## Status`n`nDone. It ran.`n"
            }

            (script:Get-Finding -Result $result -Code 'CommitsEmpty').Severity | Should -Be 'Warning'
        }
    }

    Context 'The README' {
        It 'reports an order table with no Depends on column' {
            $result = script:Test-Sequence -Name 'no-depends' -Mutate {
                param($root)
                script:Edit-FixtureText -Path (Join-Path $root '00-README.md') -Old '| Depends on |' -New '| Waits for |'
            }

            (script:Get-Finding -Result $result -Code 'DependsOnColumnMissing').Severity | Should -Be 'Error'
        }

        It 'reports a README with no order table' {
            $result = script:Test-Sequence -Name 'no-order' -Mutate {
                param($root)
                script:Set-FixtureText -Path (Join-Path $root '00-README.md') -Text "# Sequence`n`nNo table here.`n"
            }

            (script:Get-Finding -Result $result -Code 'OrderTableMissing').Severity | Should -Be 'Error'
        }

        It 'reports a dependency on a row that does not exist' {
            $result = script:Test-Sequence -Name 'unknown-dependency' -Mutate {
                param($root)
                $path = Join-Path $root '00-README.md'
                $text = script:Read-RepositoryText -Path $path
                script:Set-FixtureText -Path $path -Text ($text -replace '(?m)^(\| 01 \|.*?\| )none( \| none \|)$', '${1}07${2}')
            }

            $finding = script:Get-Finding -Result $result -Code 'DependencyUnknown'
            $finding | Should -HaveCount 1
            $finding[0].Message | Should -Match '07'
        }

        It 'reports a brief that depends on itself' {
            $result = script:Test-Sequence -Name 'self-dependency' -Mutate {
                param($root)
                $path = Join-Path $root '00-README.md'
                $text = script:Read-RepositoryText -Path $path
                script:Set-FixtureText -Path $path -Text ($text -replace '(?m)^(\| 01 \|.*?\| )none( \| none \|)$', '${1}01${2}')
            }

            (script:Get-Finding -Result $result -Code 'DependencySelf') | Should -HaveCount 1
        }

        It 'reports an order row that has no brief' {
            $result = script:Test-Sequence -Name 'order-orphan' -Mutate {
                param($root)
                $path = Join-Path $root '00-README.md'
                $text = script:Read-RepositoryText -Path $path
                $row = [regex]::Match($text, '(?m)^\| 01 \|.*$').Value
                script:Set-FixtureText -Path $path -Text $text.Replace($row, $row + "`n" + $row.Replace('| 01 |', '| 02 |'))
            }

            (script:Get-Finding -Result $result -Code 'ReadmeRowOrphan') | Should -HaveCount 1
        }

        It 'reads an order table whose second column is named Prompt' {
            $result = script:Test-Sequence -Name 'prompt-header' -Mutate {
                param($root)
                script:Edit-FixtureText -Path (Join-Path $root '00-README.md') -Old '| # | Brief |' -New '| # | Prompt |'
            }

            (script:Get-Finding -Result $result -Code 'OrderTableMissing') | Should -BeNullOrEmpty
            $result.Passed | Should -Be $true
        }

        It 'reports free text under Depends on once per item, not once per word' {
            $result = script:Test-Sequence -Name 'free-text-dependency' -Mutate {
                param($root)
                $path = Join-Path $root '00-README.md'
                $text = script:Read-RepositoryText -Path $path
                script:Set-FixtureText -Path $path -Text ($text -replace '(?m)^(\| 01 \|.*?\| )none( \| none \|)$', '${1}an outside merge and a release${2}')
            }

            (script:Get-Finding -Result $result -Code 'DependencyUnknown') | Should -HaveCount 2
        }

        It 'accepts several row numbers separated by commas or and' {
            $result = script:Test-Sequence -Name 'several-dependencies' -Mutate {
                param($root)
                $path = Join-Path $root '00-README.md'
                $text = script:Read-RepositoryText -Path $path
                $row = [regex]::Match($text, '(?m)^\| 01 \|.*$').Value
                $more = $row.Replace('| 01 |', '| 02 |') + "`n" + $row.Replace('| 01 |', '| 03 |')
                $text = $text.Replace($row, ($row -replace '\| none \| none \|$', '| 02, 03 and 04 | none |') + "`n" + $more + "`n" + $row.Replace('| 01 |', '| 04 |'))
                script:Set-FixtureText -Path $path -Text $text
            }

            (script:Get-Finding -Result $result -Code 'DependencyUnknown') | Should -BeNullOrEmpty
            (script:Get-Finding -Result $result -Code 'DependencySelf') | Should -BeNullOrEmpty
        }
    }

    Context 'A brief' {
        It 'reports front matter that does not close' {
            $result = script:Test-Sequence -Name 'open-front-matter' -Mutate {
                param($root)
                $path = Join-Path $root '01-example.prompt.md'
                $text = script:Read-RepositoryText -Path $path
                script:Set-FixtureText -Path $path -Text ($text -replace '(?s)\A(---\n.*?\n)---\n', '$1')
            }

            (script:Get-Finding -Result $result -Code 'FrontMatterInvalid').Severity | Should -Be 'Error'
        }

        It 'reports front matter with no description' {
            $result = script:Test-Sequence -Name 'no-description' -Mutate {
                param($root)
                $path = Join-Path $root '01-example.prompt.md'
                $text = script:Read-RepositoryText -Path $path
                script:Set-FixtureText -Path $path -Text ($text -replace '(?m)^description: .*\n', '')
            }

            (script:Get-Finding -Result $result -Code 'FrontMatterInvalid').Severity | Should -Be 'Error'
        }

        It 'warns about a brief with no agent' {
            $result = script:Test-Sequence -Name 'no-agent' -Mutate {
                param($root)
                $path = Join-Path $root '01-example.prompt.md'
                $text = script:Read-RepositoryText -Path $path
                script:Set-FixtureText -Path $path -Text ($text -replace '(?m)^agent: .*\n', '')
            }

            (script:Get-Finding -Result $result -Code 'AgentMissing').Severity | Should -Be 'Warning'
            $result.Passed | Should -Be $true
        }

        It 'reports a brief that does not point to the README' {
            $result = script:Test-Sequence -Name 'no-pointer' -Mutate {
                param($root)
                script:Edit-FixtureText -Path (Join-Path $root '01-example.prompt.md') -Old '](00-README.md)' -New '](README-other.md)'
            }

            (script:Get-Finding -Result $result -Code 'ReadmePointerMissing').Severity | Should -Be 'Error'
        }

        It 'reports a brief with no <Heading> section' -ForEach @(
            @{ Heading = 'Preconditions'; Code = 'PreconditionsMissing' }
            @{ Heading = 'Finish'; Code = 'FinishMissing' }
        ) {
            $result = script:Test-Sequence -Name ('no-' + $Heading) -Mutate {
                param($root)
                script:Edit-FixtureText -Path (Join-Path $root '01-example.prompt.md') -Old ('## ' + $Heading) -New '## Other'
            }

            (script:Get-Finding -Result $result -Code $Code).Severity | Should -Be 'Error'
        }

        It 'warns about a missing <Slot> slot' -ForEach @(
            @{ Slot = 'own-row check'; Old = 'Own row:'; New = 'Row:'; Code = 'OwnRowCheckMissing' }
            @{ Slot = 'dependency-row check'; Old = 'Dependency rows:'; New = 'Rows:'; Code = 'DependencyCheckMissing' }
            @{ Slot = 'evidence'; Old = '## Evidence'; New = '## Background'; Code = 'EvidenceMissing' }
            @{ Slot = 'ask-first'; Old = '## Ask first'; New = '## Questions'; Code = 'AskFirstMissing' }
            @{ Slot = 'validation'; Old = '## Validation'; New = '## Checks'; Code = 'ValidationMissing' }
        ) {
            $result = script:Test-Sequence -Name ('slot-' + $Code) -Mutate {
                param($root)
                script:Edit-FixtureText -Path (Join-Path $root '01-example.prompt.md') -Old $Old -New $New
            }

            (script:Get-Finding -Result $result -Code $Code).Severity | Should -Be 'Warning'
            $result.Passed | Should -Be $true
        }
    }

    Context 'Links, slots, and private paths' {
        It 'reports a relative link that does not resolve' {
            $result = script:Test-Sequence -Name 'broken-link' -Mutate {
                param($root)
                Add-Content -LiteralPath (Join-Path $root '00-README.md') -Value "`nSee [the plan](missing/plan.md) and [site](https://example.com/x) and [top](#order).`n"
            }

            $finding = script:Get-Finding -Result $result -Code 'LinkBroken'
            $finding | Should -HaveCount 1
            $finding[0].Message | Should -Match 'missing/plan\.md'
        }

        It 'does not read a link inside a code block or a code span' {
            $result = script:Test-Sequence -Name 'code-link' -Mutate {
                param($root)
                $tick = [string][char]96
                $block = "`n{0}[a](nowhere.md){0} and`n`n{1}text`n[b](nowhere-too.md)`n{1}`n" -f $tick, ($tick * 3)
                Add-Content -LiteralPath (Join-Path $root '00-README.md') -Value $block
            }

            (script:Get-Finding -Result $result -Code 'LinkBroken') | Should -BeNullOrEmpty
        }

        It 'reports a slot left unfilled' {
            $result = script:Test-Sequence -Name 'slot-left' -Mutate {
                param($root)
                Add-Content -LiteralPath (Join-Path $root '01-example.prompt.md') -Value "`nDo {{tasks: what to do}} first.`n"
            }

            $finding = script:Get-Finding -Result $result -Code 'SlotUnfilled'
            $finding | Should -HaveCount 1
            $finding[0].Severity | Should -Be 'Error'
        }

        It 'counts needs input as a warning, not a failure' {
            $result = script:Test-Sequence -Name 'needs-input' -Mutate {
                param($root)
                Add-Content -LiteralPath (Join-Path $root '01-example.prompt.md') -Value "`nThe branch is needs input.`n"
            }

            (script:Get-Finding -Result $result -Code 'NeedsInput').Severity | Should -Be 'Warning'
            $result.Passed | Should -Be $true
        }

        It 'reports a Windows user-profile path as an error' {
            $result = script:Test-Sequence -Name 'windows-profile' -Mutate {
                param($root)
                Add-Content -LiteralPath (Join-Path $root '00-README.md') -Value ("`nSource: {0}`n" -f $script:accountPath)
            }

            $finding = script:Get-Finding -Result $result -Code 'UserProfilePath'
            $finding | Should -HaveCount 1
            $finding[0].Severity | Should -Be 'Error'
            $finding[0].Message | Should -Not -Match 'example-account' -Because 'the finding must not repeat the account name it reports'
        }

        It 'reports a Unix home path as an error' {
            $result = script:Test-Sequence -Name 'unix-profile' -Mutate {
                param($root)
                Add-Content -LiteralPath (Join-Path $root '00-README.md') -Value ("`nSource: {0}`n" -f $script:unixAccountPath)
            }

            (script:Get-Finding -Result $result -Code 'UserProfilePath') | Should -HaveCount 1
        }

        It 'accepts a placeholder where an account name would sit' {
            $result = script:Test-Sequence -Name 'placeholder-profile' -Mutate {
                param($root)
                Add-Content -LiteralPath (Join-Path $root '00-README.md') -Value ("`nWindows: {0}Users{1}<account>{1}handoffs and %USERPROFILE%{1}handoffs`n" -f ('C:' + '\'), '\')
            }

            (script:Get-Finding -Result $result -Code 'UserProfilePath') | Should -BeNullOrEmpty
        }

        It 'warns about a machine-specific drive path' {
            $result = script:Test-Sequence -Name 'machine-path' -Mutate {
                param($root)
                Add-Content -LiteralPath (Join-Path $root '00-README.md') -Value ("`nClone: {0}`n" -f ('D:' + '\Git\project'))
            }

            (script:Get-Finding -Result $result -Code 'MachinePath').Severity | Should -Be 'Warning'
        }

        It 'reports a forbidden term as a whole word, ignoring case' {
            $result = script:Test-Sequence -Name 'forbidden' -Mutate {
                param($root)
                Add-Content -LiteralPath (Join-Path $root '00-README.md') -Value "`nHost LabMachine7 and labmachine7x.`n"
            } -Parameter @{ ForbiddenTerm = @('labmachine7') }

            $finding = script:Get-Finding -Result $result -Code 'ForbiddenTerm'
            $finding | Should -HaveCount 1
            $finding[0].Severity | Should -Be 'Error'
        }

        It 'never repeats a forbidden term in a finding, wherever the text came from' {
            $result = script:Test-Sequence -Name 'forbidden-echo' -Mutate {
                param($root)
                script:Edit-FixtureText -Path (Join-Path $root 'LEDGER.md') -Old '| 01 | Not started | | | | |' -New '| 01 | Done-labmachine7 | | | | |'
                Add-Content -LiteralPath (Join-Path $root '00-README.md') -Value "`nSee [notes](../labmachine7-private/notes.md) and {{labmachine7-token}}.`n"
                Copy-Item -LiteralPath (Join-Path $root '01-example.prompt.md') -Destination (Join-Path $root '02-labmachine7-task.prompt.md')
            } -Parameter @{ ForbiddenTerm = @('labmachine7') }

            @($result.Finding | Where-Object { $_.Code -in @('StatusInvalid', 'LinkBroken', 'SlotUnfilled', 'ForbiddenTerm') } | ForEach-Object { $_.Code } | Select-Object -Unique) | Should -HaveCount 4
            (script:Get-Finding -Result $result -Code 'BriefWithoutRow') | Should -HaveCount 1
            foreach ($finding in $result.Finding) {
                $finding.Message | Should -Not -Match 'labmachine7'
                $finding.File | Should -Not -Match 'labmachine7'
            }
        }
    }

    Context 'Hostile text' {
        It 'reads <Name> in linear time' -ForEach @(
            @{ Name = 'a long run of opening brackets'; Text = ('[' * 60000) }
            @{ Name = 'a long run of backticks'; Text = ('`' * 60000) }
        ) {
            $run = script:Measure-Run {
                script:Test-Sequence -Name ('hostile-' + ($Name -replace '\W', '-')) -Mutate {
                    param($root)
                    Add-Content -LiteralPath (Join-Path $root '00-README.md') -Value ("`n" + $Text + "`n")
                }
            }

            $run.Value | Should -Not -BeNullOrEmpty
            $run.Seconds | Should -BeLessThan 5
        }

        It 'reads a brief whose README anchors never close in linear time' {
            $run = script:Measure-Run {
                script:Test-Sequence -Name 'hostile-anchor' -Mutate {
                    param($root)
                    script:Edit-FixtureText -Path (Join-Path $root '01-example.prompt.md') -Old '[00-README.md](00-README.md)' -New ('](00-README.md#' * 30000)
                }
            }

            (script:Get-Finding -Result $run.Value -Code 'ReadmePointerMissing').Severity | Should -Be 'Error'
            $run.Seconds | Should -BeLessThan 5
        }

        It 'reads a Depends on cell that is mostly blanks in linear time' {
            $run = script:Measure-Run {
                script:Test-Sequence -Name 'hostile-depends' -Mutate {
                    param($root)
                    script:Edit-FixtureText -Path (Join-Path $root '00-README.md') -Old '| off | none | none |' -New ('| off | ' + (' ' * 100000) + 'x | none |')
                }
            }

            (script:Get-Finding -Result $run.Value -Code 'DependencyUnknown') | Should -HaveCount 1
            $run.Seconds | Should -BeLessThan 5
        }

        It 'reads a report that is mostly blank lines in linear time' {
            . (Join-Path $script:skillRoot 'scripts/HandoffSequenceCommon.ps1')
            $text = "# 01`n" + ("`n" * 150000)

            $run = script:Measure-Run { Get-HandoffReportStatus -Text $text }

            $run.Value | Should -BeNullOrEmpty
            $run.Seconds | Should -BeLessThan 5
        }
    }

    Context 'Linked files' {
        It 'does not read a file that a link points to, and says so' {
            $outside = Join-Path $TestDrive 'outside-secret.md'
            script:Set-FixtureText -Path $outside -Text ('Token {{leak}} at ' + $script:accountPath + "`n")
            $script:linkMade = $false
            $result = script:Test-Sequence -Name 'linked-file' -Mutate {
                param($root)
                try {
                    New-Item -ItemType SymbolicLink -Path (Join-Path $root 'reports/linked.md') -Target $outside -ErrorAction Stop | Out-Null
                    $script:linkMade = $true
                } catch {
                    $script:linkMade = $false
                }
            }

            if (-not $script:linkMade) {
                Set-ItResult -Skipped -Because 'this account may not create symbolic links'
                return
            }

            (script:Get-Finding -Result $result -Code 'SlotUnfilled') | Should -BeNullOrEmpty
            (script:Get-Finding -Result $result -Code 'UserProfilePath') | Should -BeNullOrEmpty
            $finding = script:Get-Finding -Result $result -Code 'ReparsePointSkipped'
            $finding | Should -HaveCount 1
            $finding[0].Severity | Should -Be 'Warning'
            $finding[0].File | Should -Be 'reports/linked.md'
        }

        It 'treats a README that is a link as missing, and says so' {
            $outside = Join-Path $TestDrive 'outside-readme.md'
            script:Set-FixtureText -Path $outside -Text "# Outside`n"
            $script:linkMade = $false
            $result = script:Test-Sequence -Name 'linked-readme' -Mutate {
                param($root)
                Remove-Item -LiteralPath (Join-Path $root '00-README.md')
                try {
                    New-Item -ItemType SymbolicLink -Path (Join-Path $root '00-README.md') -Target $outside -ErrorAction Stop | Out-Null
                    $script:linkMade = $true
                } catch {
                    $script:linkMade = $false
                }
            }

            if (-not $script:linkMade) {
                Set-ItResult -Skipped -Because 'this account may not create symbolic links'
                return
            }

            (script:Get-Finding -Result $result -Code 'ReadmeMissing').Severity | Should -Be 'Error'
            (script:Get-Finding -Result $result -Code 'ReparsePointSkipped') | Should -HaveCount 1
        }
    }

    Context 'Reports' {
        It 'reports a finished row whose report file is missing' {
            $result = script:Test-Sequence -Name 'no-report' -Mutate {
                param($root)
                script:Edit-FixtureText -Path (Join-Path $root 'LEDGER.md') -Old '| 01 | Not started | | | | |' -New '| 01 | Done | `abc1234` | passed | none | |'
            }

            (script:Get-Finding -Result $result -Code 'ReportMissing').Severity | Should -Be 'Error'
        }

        It 'warns about a report for a row that is Not started' {
            $result = script:Test-Sequence -Name 'early-report' -Mutate {
                param($root)
                script:Set-FixtureText -Path (Join-Path $root 'reports/01-example.report.md') -Text $script:reportText
            }

            (script:Get-Finding -Result $result -Code 'ReportUnexpected').Severity | Should -Be 'Warning'
        }

        It 'warns when the report states a different status than the row' {
            $result = script:Test-Sequence -Name 'status-mismatch' -Mutate {
                param($root)
                script:Edit-FixtureText -Path (Join-Path $root 'LEDGER.md') -Old '| 01 | Not started | | | | |' -New '| 01 | Done | `abc1234` | passed | none | [01](reports/01-example.report.md) |'
                script:Set-FixtureText -Path (Join-Path $root 'reports/01-example.report.md') -Text "# 01`n`n## Status`n`nDone with concerns. One thing is open.`n"
            }

            (script:Get-Finding -Result $result -Code 'StatusMismatch').Severity | Should -Be 'Warning'
        }

        It 'accepts a finished row whose report agrees' {
            $result = script:Test-Sequence -Name 'finished' -Mutate {
                param($root)
                script:Edit-FixtureText -Path (Join-Path $root 'LEDGER.md') -Old '| 01 | Not started | | | | |' -New '| 01 | Done with concerns | `abc1234` | passed | one open | [01](reports/01-example.report.md) |'
                script:Set-FixtureText -Path (Join-Path $root 'reports/01-example.report.md') -Text "# 01`n`n## Status`n`n**Done with concerns** on 2026-01-01. One thing is open.`n"
            }

            $result.Finding | Should -BeNullOrEmpty
            $result.Passed | Should -Be $true
        }
    }

    Context 'Checking the commits a row names' {
        BeforeAll {
            if ($script:hasGit) {
                $script:repository = Join-Path $TestDrive 'repository'
                New-Item -ItemType Directory -Path $script:repository -Force | Out-Null
                script:Invoke-TestGit -Repository $script:repository -Argument @('init', '--quiet') | Out-Null
                script:Invoke-TestGit -Repository $script:repository -Argument @('symbolic-ref', 'HEAD', 'refs/heads/main') | Out-Null
                script:Invoke-TestGit -Repository $script:repository -Argument @('commit', '--quiet', '--allow-empty', '-m', 'first') | Out-Null
                $script:onMain = script:Invoke-TestGit -Repository $script:repository -Argument @('rev-parse', '--short=12', 'HEAD')
                script:Invoke-TestGit -Repository $script:repository -Argument @('checkout', '--quiet', '-b', 'side') | Out-Null
                script:Invoke-TestGit -Repository $script:repository -Argument @('commit', '--quiet', '--allow-empty', '-m', 'side work') | Out-Null
                $script:onSide = script:Invoke-TestGit -Repository $script:repository -Argument @('rev-parse', '--short=12', 'HEAD')
                script:Invoke-TestGit -Repository $script:repository -Argument @('checkout', '--quiet', 'main') | Out-Null
            }
        }

        It 'passes when every named commit is on the integration branch' {
            if (-not $script:hasGit) {
                Set-ItResult -Skipped -Because 'git is not installed'
                return
            }

            $commit = $script:onMain
            $result = script:Test-Sequence -Name 'commits-ok' -Mutate {
                param($root)
                script:Edit-FixtureText -Path (Join-Path $root 'LEDGER.md') -Old '| 01 | Not started | | | | |' -New ('| 01 | Done | `{0}` | passed | none | [01](reports/01-example.report.md) |' -f $commit)
                script:Set-FixtureText -Path (Join-Path $root 'reports/01-example.report.md') -Text "# 01`n`n## Status`n`nDone.`n"
            } -Parameter @{ Repository = $script:repository; IntegrationBranch = 'main' }

            $result.Finding | Should -BeNullOrEmpty
            $result.Passed | Should -Be $true
        }

        It 'reports a commit that exists but is not on the integration branch' {
            if (-not $script:hasGit) {
                Set-ItResult -Skipped -Because 'git is not installed'
                return
            }

            $commit = $script:onSide
            $result = script:Test-Sequence -Name 'commit-elsewhere' -Mutate {
                param($root)
                script:Edit-FixtureText -Path (Join-Path $root 'LEDGER.md') -Old '| 01 | Not started | | | | |' -New ('| 01 | Done | `{0}` | passed | none | [01](reports/01-example.report.md) |' -f $commit)
                script:Set-FixtureText -Path (Join-Path $root 'reports/01-example.report.md') -Text "# 01`n`n## Status`n`nDone.`n"
            } -Parameter @{ Repository = $script:repository; IntegrationBranch = 'main' }

            (script:Get-Finding -Result $result -Code 'CommitNotOnBranch').Severity | Should -Be 'Error'
            (script:Get-Finding -Result $result -Code 'CommitMissing') | Should -BeNullOrEmpty
        }

        It 'reports a commit that does not exist' {
            if (-not $script:hasGit) {
                Set-ItResult -Skipped -Because 'git is not installed'
                return
            }

            $result = script:Test-Sequence -Name 'commit-missing' -Mutate {
                param($root)
                script:Edit-FixtureText -Path (Join-Path $root 'LEDGER.md') -Old '| 01 | Not started | | | | |' -New '| 01 | Done | `1234567` | passed | none | [01](reports/01-example.report.md) |'
                script:Set-FixtureText -Path (Join-Path $root 'reports/01-example.report.md') -Text "# 01`n`n## Status`n`nDone.`n"
            } -Parameter @{ Repository = $script:repository; IntegrationBranch = 'main' }

            (script:Get-Finding -Result $result -Code 'CommitMissing').Severity | Should -Be 'Error'
        }

        It 'checks both ends of a range and ignores backticked words that are not commits' {
            if (-not $script:hasGit) {
                Set-ItResult -Skipped -Because 'git is not installed'
                return
            }

            $commit = $script:onMain
            $result = script:Test-Sequence -Name 'commit-range' -Mutate {
                param($root)
                script:Edit-FixtureText -Path (Join-Path $root 'LEDGER.md') -Old '| 01 | Not started | | | | |' -New ('| 01 | Done | `{0}..{0}` on `ai/topic`, not pushed | passed | none | [01](reports/01-example.report.md) |' -f $commit)
                script:Set-FixtureText -Path (Join-Path $root 'reports/01-example.report.md') -Text "# 01`n`n## Status`n`nDone.`n"
            } -Parameter @{ Repository = $script:repository; IntegrationBranch = 'main' }

            $result.Finding | Should -BeNullOrEmpty
        }

        It 'checks a commit written <Form>' -ForEach @(
            @{ Form = 'without backticks'; Cell = '1234567' }
            @{ Form = 'in a list inside one code span'; Cell = '`{0}, 1234567`' }
            @{ Form = 'after the word and'; Cell = '`{0}` and 1234567' }
            @{ Form = 'in a sentence'; Cell = 'fixed in 1234567 on the branch' }
            @{ Form = 'beside a word made only of hexadecimal letters'; Cell = 'defaced in 1234567' }
        ) {
            if (-not $script:hasGit) {
                Set-ItResult -Skipped -Because 'git is not installed'
                return
            }

            $cell = $Cell -f $script:onMain
            $result = script:Test-Sequence -Name ('commit-form-' + ($Form -replace '\W', '-')) -Mutate {
                param($root)
                script:Edit-FixtureText -Path (Join-Path $root 'LEDGER.md') -Old '| 01 | Not started | | | | |' -New ('| 01 | Done | {0} | passed | none | [01](reports/01-example.report.md) |' -f $cell)
                script:Set-FixtureText -Path (Join-Path $root 'reports/01-example.report.md') -Text "# 01`n`n## Status`n`nDone.`n"
            } -Parameter @{ Repository = $script:repository; IntegrationBranch = 'main' }

            $finding = script:Get-Finding -Result $result -Code 'CommitMissing'
            $finding | Should -HaveCount 1
            $finding[0].Message | Should -Match '1234567'
        }

        It 'warns when a finished row names no commit the check can read: <Cell>' -ForEach @(
            @{ Cell = 'see the report' }
            @{ Cell = 'three commits' }
        ) {
            if (-not $script:hasGit) {
                Set-ItResult -Skipped -Because 'git is not installed'
                return
            }

            $result = script:Test-Sequence -Name ('commit-unreadable-' + ($Cell -replace '\W', '-')) -Mutate {
                param($root)
                script:Edit-FixtureText -Path (Join-Path $root 'LEDGER.md') -Old '| 01 | Not started | | | | |' -New ('| 01 | Done | {0} | passed | none | [01](reports/01-example.report.md) |' -f $Cell)
                script:Set-FixtureText -Path (Join-Path $root 'reports/01-example.report.md') -Text "# 01`n`n## Status`n`nDone.`n"
            } -Parameter @{ Repository = $script:repository; IntegrationBranch = 'main' }

            (script:Get-Finding -Result $result -Code 'CommitsUnchecked').Severity | Should -Be 'Warning'
            $result.Passed | Should -Be $true
        }

        It 'accepts <Cell> as the statement that a finished row has no commit' -ForEach @(
            @{ Cell = 'none' }
            @{ Cell = 'None.' }
            @{ Cell = 'n/a' }
            @{ Cell = '-' }
        ) {
            if (-not $script:hasGit) {
                Set-ItResult -Skipped -Because 'git is not installed'
                return
            }

            $result = script:Test-Sequence -Name ('commit-none-' + ($Cell -replace '\W', 'x')) -Mutate {
                param($root)
                script:Edit-FixtureText -Path (Join-Path $root 'LEDGER.md') -Old '| 01 | Not started | | | | |' -New ('| 01 | Done | {0} | passed | none | [01](reports/01-example.report.md) |' -f $Cell)
                script:Set-FixtureText -Path (Join-Path $root 'reports/01-example.report.md') -Text "# 01`n`n## Status`n`nDone.`n"
            } -Parameter @{ Repository = $script:repository; IntegrationBranch = 'main' }

            $result.Finding | Should -BeNullOrEmpty
        }

        It 'does not check commits unless asked' {
            $result = script:Test-Sequence -Name 'commits-unchecked' -Mutate {
                param($root)
                script:Edit-FixtureText -Path (Join-Path $root 'LEDGER.md') -Old '| 01 | Not started | | | | |' -New '| 01 | Done | `1234567` | passed | none | [01](reports/01-example.report.md) |'
                script:Set-FixtureText -Path (Join-Path $root 'reports/01-example.report.md') -Text "# 01`n`n## Status`n`nDone.`n"
            }

            $result.Passed | Should -Be $true
        }

        It 'rejects an integration branch that could be read as an option' {
            { & $script:validatorPath -Path $TestDrive -Repository $TestDrive -IntegrationBranch '--upload-pack=x' } | Should -Throw
        }

        It 'requires the integration branch whenever a repository is named' {
            { & $script:validatorPath -Path $TestDrive -Repository $TestDrive } | Should -Throw -ExpectedMessage '*IntegrationBranch*'
        }
    }
}
