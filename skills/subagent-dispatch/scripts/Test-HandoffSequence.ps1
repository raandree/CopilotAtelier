#Requires -Version 5.1

<#
.SYNOPSIS
    Validates a handoff sequence folder against the task-ledger process.
.DESCRIPTION
    Reads the sequence README (00-README.md), LEDGER.md, the NN-slug.prompt.md
    briefs, and reports/. Reports a brief without a ledger row, a row without a
    brief, a status outside the vocabulary, a Rulings table that does not say who
    decided, a dependency on an unknown row, a relative link that does not
    resolve, a template slot left unfilled, a user-profile path, and a forbidden
    term. With Repository and IntegrationBranch it also checks that every commit
    a finished row names exists and is on the integration branch.

    The script is read-only and skips the originals folder. It does not read a
    file that is a link, and says so. It returns one summary object whose Passed
    property is true when no finding has the Error severity. A finding never
    repeats an account name or a forbidden term.
.PARAMETER Path
    The sequence folder: the README, the ledger, the briefs, and reports/.
.PARAMETER Repository
    A git working tree or repository directory. Names the repository whose
    commits the finished rows cite; requires IntegrationBranch.
.PARAMETER IntegrationBranch
    The branch the cited commits have to be on, for example main.
.PARAMETER ForbiddenTerm
    Words that must not appear in any file, such as the local account name or a
    machine name. Matched as whole words, ignoring case.
.EXAMPLE
    $result = ./Test-HandoffSequence.ps1 -Path ./handoffs
    $result.Finding | Format-Table Severity, Code, File, Line, Message -AutoSize -Wrap

    Checks the structure of a sequence and lists every finding.
.EXAMPLE
    ./Test-HandoffSequence.ps1 -Path ./handoffs -Repository ../project -IntegrationBranch main -ForbiddenTerm $env:USERNAME

    Also checks that every commit a finished row cites is on main, and that the
    local account name appears nowhere.
.OUTPUTS
    System.Management.Automation.PSCustomObject
#>

[CmdletBinding()]
[OutputType([pscustomobject])]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
    [string] $Path,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
    [string] $Repository,

    [Parameter()]
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._/-]*$')]
    [string] $IntegrationBranch,

    [Parameter()]
    [string[]] $ForbiddenTerm = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($PSBoundParameters.ContainsKey('Repository') -and -not $PSBoundParameters.ContainsKey('IntegrationBranch')) {
    throw 'IntegrationBranch is required when Repository is given.'
}

. (Join-Path -Path $PSScriptRoot -ChildPath 'HandoffSequenceCommon.ps1')

$root = (Resolve-Path -LiteralPath $Path).ProviderPath
$script:finding = [Collections.Generic.List[object]]::new()
$script:forbiddenTerm = @($ForbiddenTerm | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$statusVocabulary = @('Not started', 'Done', 'Done with concerns', 'Needs context', 'Blocked')
$deciderPattern = '^(?:user|agent under delegation|agent)\b'
$slotPattern = '\{\{(?<key>[a-z0-9-]+)(?::[^{}]*)?\}\}'

function Add-Finding {
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions',
        '',
        Justification = 'Adds to an in-memory list only.'
    )]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Error', 'Warning')]
        [string] $Severity,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Code,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $File,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Message,

        [Parameter()]
        [int] $Line = 0
    )

    # A finding never repeats a forbidden term, whichever line, link, or status it quotes.
    foreach ($forbidden in $script:forbiddenTerm) {
        $File = [regex]::Replace($File, [regex]::Escape($forbidden), '<withheld>', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
        $Message = [regex]::Replace($Message, [regex]::Escape($forbidden), '<withheld>', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    }

    $script:finding.Add([pscustomobject]@{
            Severity = $Severity
            Code     = $Code
            File     = $File
            Line     = $Line
            Message  = $Message
        })
}

function Get-RelativeName {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $FullName
    )

    $FullName.Substring($root.Length).TrimStart('\', '/').Replace('\', '/')
}

function Get-CellText {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]] $Cell,

        [Parameter(Mandatory)]
        [int] $Index
    )

    if ($Index -lt 0 -or $Index -ge $Cell.Count) {
        return ''
    }

    $Cell[$Index]
}

function Invoke-GitExitCode {
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [string[]] $Argument
    )

    # Windows PowerShell 5.1 turns native stderr into a terminating error under Stop.
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $null = & git -C $script:repositoryRoot @Argument 2>&1
        $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previous
    }
}

$linkedName = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$markdown = [Collections.Generic.List[object]]::new()
# A bounded depth keeps a cyclic junction from sending the walk around forever.
foreach ($file in @(
        Get-ChildItem -LiteralPath $root -Recurse -Depth 4 -File -Filter '*.md' |
            Where-Object { (Get-RelativeName -FullName $_.FullName) -notmatch '^originals/' } |
            Sort-Object -Property FullName
    )) {
    # A link can point at any file on the machine, so no file is read through one.
    if (Test-HandoffReparsePoint -Item $file) {
        $linkName = Get-RelativeName -FullName $file.FullName
        [void]$linkedName.Add($linkName)
        Add-Finding -Severity Warning -Code 'ReparsePointSkipped' -File $linkName -Message 'The file is a link, and the check does not read through links.'
        continue
    }

    $markdown.Add($file)
}

# The skeleton: README, ledger, and briefs.
$readmePath = Join-Path -Path $root -ChildPath '00-README.md'
$ledgerPath = Join-Path -Path $root -ChildPath 'LEDGER.md'
$hasReadme = (Test-Path -LiteralPath $readmePath -PathType Leaf) -and -not $linkedName.Contains('00-README.md')
$hasLedger = (Test-Path -LiteralPath $ledgerPath -PathType Leaf) -and -not $linkedName.Contains('LEDGER.md')
if (-not $hasReadme) {
    Add-Finding -Severity Error -Code 'ReadmeMissing' -File '00-README.md' -Message 'The sequence README 00-README.md is missing.'
}

if (-not $hasLedger) {
    Add-Finding -Severity Error -Code 'LedgerMissing' -File 'LEDGER.md' -Message 'The ledger LEDGER.md is missing.'
}

$brief = [Collections.Generic.List[object]]::new()
foreach ($file in @(Get-ChildItem -LiteralPath $root -File -Filter '*.prompt.md' | Where-Object { -not $linkedName.Contains($_.Name) } | Sort-Object -Property Name)) {
    if ($file.Name -match '^(?<nn>\d{2,3})-(?<slug>[a-z0-9]+(?:-[a-z0-9]+)*)\.prompt\.md$') {
        $brief.Add([pscustomobject]@{
                Nn   = $Matches['nn']
                Name = $file.Name
                Path = $file.FullName
            })
    } else {
        Add-Finding -Severity Warning -Code 'BriefNameInvalid' -File $file.Name -Message 'A brief is named NN-slug.prompt.md, with a two-digit number and a lowercase slug.'
    }
}

foreach ($group in @($brief | Group-Object -Property Nn | Where-Object { $_.Count -gt 1 })) {
    Add-Finding -Severity Error -Code 'BriefNumberDuplicate' -File $group.Group[0].Name -Message ('More than one brief carries the number {0}.' -f $group.Name)
}

# The ledger: status table, rulings, and the place for work after the last row.
$row = [Collections.Generic.List[object]]::new()
if ($hasLedger) {
    $ledgerText = Read-HandoffText -Path $ledgerPath
    $ledgerTable = @(Get-HandoffTable -Line @($ledgerText -split '\r?\n'))

    $statusTable = @($ledgerTable | Where-Object {
            $_.Header.Count -gt 1 -and $_.Header[0] -eq '#' -and (Get-HandoffColumnIndex -Header $_.Header -Pattern '^Status$') -ge 0
        }) | Select-Object -First 1

    if ($null -eq $statusTable) {
        Add-Finding -Severity Error -Code 'StatusTableMissing' -File 'LEDGER.md' -Message 'The ledger has no status table whose first columns are # and Status.'
    } else {
        $statusColumn = Get-HandoffColumnIndex -Header $statusTable.Header -Pattern '^Status$'
        $commitColumn = Get-HandoffColumnIndex -Header $statusTable.Header -Pattern '^Commits\b'
        foreach ($entry in $statusTable.Row) {
            $number = (Get-CellText -Cell $entry.Cell -Index 0).Trim('`', '*', ' ')
            if ($number -notmatch '^\d{2,3}$') {
                continue
            }

            $status = (Get-CellText -Cell $entry.Cell -Index $statusColumn) -replace '[`*]', ''
            $status = $status.Trim()
            $row.Add([pscustomobject]@{
                    Nn      = $number
                    Status  = $status
                    Commits = Get-CellText -Cell $entry.Cell -Index $commitColumn
                    Line    = $entry.Line
                })

            if ($statusVocabulary -notcontains $status) {
                Add-Finding -Severity Error -Code 'StatusInvalid' -File 'LEDGER.md' -Line $entry.Line -Message ('Row {0} reads "{1}"; a status is one of: {2}.' -f $number, $status, ($statusVocabulary -join ', '))
            }
        }
    }

    $rulingTable = @($ledgerTable | Where-Object {
            (Get-HandoffColumnIndex -Header $_.Header -Pattern '^Question$') -ge 0 -and (Get-HandoffColumnIndex -Header $_.Header -Pattern '^Answer$') -ge 0
        }) | Select-Object -First 1

    if ($null -eq $rulingTable) {
        Add-Finding -Severity Error -Code 'RulingsTableMissing' -File 'LEDGER.md' -Message 'The ledger has no Rulings table with Question and Answer columns.'
    } else {
        $deciderColumn = Get-HandoffColumnIndex -Header $rulingTable.Header -Pattern '^Decided by$'
        if ($deciderColumn -lt 0) {
            Add-Finding -Severity Error -Code 'DecidedByColumnMissing' -File 'LEDGER.md' -Line $rulingTable.Line -Message 'The Rulings table has no Decided by column, so nothing says which decisions the user made.'
        } else {
            foreach ($entry in $rulingTable.Row) {
                $decider = (Get-CellText -Cell $entry.Cell -Index $deciderColumn) -replace '[`*]', ''
                if ($decider.Trim() -notmatch $deciderPattern) {
                    Add-Finding -Severity Error -Code 'DecidedByInvalid' -File 'LEDGER.md' -Line $entry.Line -Message 'A ruling says who decided it with user, agent, or agent under delegation.'
                }
            }
        }
    }

    if ($ledgerText -notmatch '(?im)^#{1,6}\s+After the last row\b') {
        Add-Finding -Severity Warning -Code 'AfterLastRowMissing' -File 'LEDGER.md' -Message 'The ledger has no After the last row section for work that runs after the last brief.'
    }
}

# The README: order table with a Depends on column.
$orderRow = [Collections.Generic.List[object]]::new()
if ($hasReadme) {
    $readmeText = Read-HandoffText -Path $readmePath
    $readmeTable = @(Get-HandoffTable -Line @($readmeText -split '\r?\n'))
    $orderTable = @($readmeTable | Where-Object {
            $_.Header.Count -gt 1 -and $_.Header[0] -eq '#' -and (Get-HandoffColumnIndex -Header $_.Header -Pattern '^(?:Brief|Prompt|Task)$') -ge 0
        }) | Select-Object -First 1

    if ($null -eq $orderTable) {
        Add-Finding -Severity Error -Code 'OrderTableMissing' -File '00-README.md' -Message 'The README has no order table whose first columns are # and Brief.'
    } else {
        $dependsColumn = Get-HandoffColumnIndex -Header $orderTable.Header -Pattern '^Depends on$'
        if ($dependsColumn -lt 0) {
            Add-Finding -Severity Error -Code 'DependsOnColumnMissing' -File '00-README.md' -Line $orderTable.Line -Message 'The order table has no Depends on column, so the start gate has nothing to read.'
        }

        foreach ($entry in $orderTable.Row) {
            $number = (Get-CellText -Cell $entry.Cell -Index 0).Trim('`', '*', ' ')
            if ($number -match '^\d{2,3}$') {
                $orderRow.Add([pscustomobject]@{
                        Nn      = $number
                        Depends = Get-CellText -Cell $entry.Cell -Index $dependsColumn
                        Line    = $entry.Line
                    })
            }
        }
    }
}

# Cross-checks between the briefs, the ledger rows, and the README rows.
$rowNumber = @($row | ForEach-Object { $_.Nn })
$briefNumber = @($brief | ForEach-Object { $_.Nn })
$orderNumber = @($orderRow | ForEach-Object { $_.Nn })
if ($hasLedger) {
    foreach ($entry in $brief) {
        if ($rowNumber -notcontains $entry.Nn) {
            Add-Finding -Severity Error -Code 'BriefWithoutRow' -File $entry.Name -Message ('Brief {0} has no row in LEDGER.md.' -f $entry.Nn)
        }
    }

    foreach ($entry in $row) {
        if ($briefNumber -notcontains $entry.Nn) {
            Add-Finding -Severity Error -Code 'RowWithoutBrief' -File 'LEDGER.md' -Line $entry.Line -Message ('Ledger row {0} has no brief file.' -f $entry.Nn)
        }
    }
}

if ($hasReadme) {
    foreach ($entry in $brief) {
        if ($orderNumber -notcontains $entry.Nn) {
            Add-Finding -Severity Error -Code 'ReadmeRowMissing' -File $entry.Name -Message ('Brief {0} has no row in the README order table.' -f $entry.Nn)
        }
    }

    foreach ($entry in $orderRow) {
        if ($briefNumber -notcontains $entry.Nn) {
            Add-Finding -Severity Error -Code 'ReadmeRowOrphan' -File '00-README.md' -Line $entry.Line -Message ('README order row {0} has no brief file.' -f $entry.Nn)
        }

        foreach ($dependency in @(($entry.Depends -replace '[`*]', '') -split '(?:,|;|&|\band\b)' | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -notmatch '^(?i:none|n/a|-)$' })) {
            if ($dependency -eq $entry.Nn) {
                Add-Finding -Severity Error -Code 'DependencySelf' -File '00-README.md' -Line $entry.Line -Message ('Brief {0} lists itself under Depends on.' -f $entry.Nn)
            } elseif ($dependency -notmatch '^\d{2,3}$' -or ($orderNumber -notcontains $dependency -and $rowNumber -notcontains $dependency)) {
                Add-Finding -Severity Error -Code 'DependencyUnknown' -File '00-README.md' -Line $entry.Line -Message ('Brief {0} lists "{1}" under Depends on, which is not a row number of this sequence; name an outside dependency in the brief''s preconditions instead.' -f $entry.Nn, $dependency)
            }
        }
    }
}

# What each brief has to carry.
$slotCode = [ordered]@{
    FrontMatter     = @('Error', 'FrontMatterInvalid', 'The front matter does not open and close with ---, or declares no description.')
    Agent           = @('Warning', 'AgentMissing', 'The front matter declares no agent.')
    ReadmePointer   = @('Error', 'ReadmePointerMissing', 'The brief has no link to 00-README.md, so its shared rules, report contract, and ledger are not named.')
    Preconditions   = @('Error', 'PreconditionsMissing', 'The brief has no Preconditions section.')
    OwnRowCheck     = @('Warning', 'OwnRowCheckMissing', 'The preconditions do not read the brief''s own ledger row before resuming.')
    DependencyCheck = @('Warning', 'DependencyCheckMissing', 'The preconditions do not check the dependency rows another run wrote.')
    Evidence        = @('Warning', 'EvidenceMissing', 'The brief has no Evidence section with a verification date.')
    AskFirst        = @('Warning', 'AskFirstMissing', 'The brief has no Ask first section.')
    Tasks           = @('Warning', 'TasksMissing', 'The brief has no Tasks section.')
    Validation      = @('Warning', 'ValidationMissing', 'The brief has no Validation section.')
    Finish          = @('Error', 'FinishMissing', 'The brief has no Finish section.')
    FinishCommit    = @('Warning', 'FinishCommitMissing', 'The Finish section does not give the commit message.')
    FinishReport    = @('Warning', 'FinishReportMissing', 'The Finish section does not name the report path under reports/.')
    FinishLedger    = @('Warning', 'FinishLedgerMissing', 'The Finish section does not update the brief''s ledger row.')
}

foreach ($entry in $brief) {
    foreach ($slot in @(Get-HandoffMissingSlot -Text (Read-HandoffText -Path $entry.Path))) {
        if ($slotCode.Contains($slot)) {
            $rule = $slotCode[$slot]
            Add-Finding -Severity $rule[0] -Code $rule[1] -File $entry.Name -Message $rule[2]
        }
    }
}

# Reports: a finished row needs one, and it has to say what the row says.
foreach ($entry in $row) {
    $report = @(
        if (Test-Path -LiteralPath (Join-Path -Path $root -ChildPath 'reports') -PathType Container) {
            Get-ChildItem -LiteralPath (Join-Path -Path $root -ChildPath 'reports') -File -Filter ('{0}-*.report.md' -f $entry.Nn) |
                Where-Object { -not $linkedName.Contains('reports/' + $_.Name) }
        }
    )

    if ($entry.Status -eq 'Not started') {
        if ($report.Count -gt 0) {
            Add-Finding -Severity Warning -Code 'ReportUnexpected' -File ('reports/' + $report[0].Name) -Message ('Row {0} reads Not started, yet a report exists.' -f $entry.Nn)
        }

        continue
    }

    if ($statusVocabulary -notcontains $entry.Status) {
        continue
    }

    if ($report.Count -eq 0) {
        Add-Finding -Severity Error -Code 'ReportMissing' -File 'LEDGER.md' -Line $entry.Line -Message ('Row {0} reads {1}, but reports/{0}-*.report.md does not exist.' -f $entry.Nn, $entry.Status)
    } else {
        $stated = Get-HandoffReportStatus -Text (Read-HandoffText -Path $report[0].FullName)
        if ($null -ne $stated -and $stated -ne $entry.Status) {
            Add-Finding -Severity Warning -Code 'StatusMismatch' -File ('reports/' + $report[0].Name) -Message ('The report states {0}; ledger row {1} reads {2}.' -f $stated, $entry.Nn, $entry.Status)
        }
    }

    if ($entry.Status -in @('Done', 'Done with concerns') -and [string]::IsNullOrWhiteSpace(($entry.Commits -replace '[`*]', ''))) {
        Add-Finding -Severity Warning -Code 'CommitsEmpty' -File 'LEDGER.md' -Line $entry.Line -Message ('Row {0} is finished but names no commits; write none when the brief commits nothing.' -f $entry.Nn)
    }
}

# Links, unfilled slots, unresolved facts, and private paths in every file except the originals.
$windowsProfile = '(?i)(?<![A-Za-z0-9])[A-Z]:[\\/]+Users[\\/]+(?<name>[^\\/\s''"`<>|)\]]+)'
$unixProfile = '(?<![A-Za-z0-9_.~-])/(?:Users|home)/(?<name>[^/\s''"`<>|)\]]+)'
$neutralName = @('Public', 'Default', 'Default User', 'All Users', 'Shared')
$driveRoot = '(?i)(?<![A-Za-z0-9])[A-Z]:[\\/]'
$term = $script:forbiddenTerm

foreach ($file in $markdown) {
    $name = Get-RelativeName -FullName $file.FullName
    $text = Read-HandoffText -Path $file.FullName
    $directory = Split-Path -Parent $file.FullName

    foreach ($link in @(Get-HandoffLink -Text $text)) {
        $target = $link.Target
        if ($target -match '^#' -or $target -match '^[A-Za-z][A-Za-z0-9+.-]+:' -or $target -match '^[A-Za-z]:[\\/]') {
            continue
        }

        $target = ($target -split '[#?]')[0]
        if ([string]::IsNullOrWhiteSpace($target)) {
            continue
        }

        $exists = $false
        try {
            $exists = Test-Path -LiteralPath (Join-Path -Path $directory -ChildPath ([Uri]::UnescapeDataString($target)))
        } catch {
            $exists = $false
        }

        if (-not $exists) {
            Add-Finding -Severity Error -Code 'LinkBroken' -File $name -Line $link.Line -Message ('The relative link {0} does not resolve.' -f $link.Target)
        }
    }

    $line = @($text -split '\r?\n')
    $needsInput = 0
    for ($index = 0; $index -lt $line.Count; $index++) {
        foreach ($match in [regex]::Matches($line[$index], $slotPattern)) {
            Add-Finding -Severity Error -Code 'SlotUnfilled' -File $name -Line ($index + 1) -Message ('The {{{{{0}}}}} slot is unfilled; replace it with the fact, or with needs input when the fact is unknown.' -f $match.Groups['key'].Value)
        }

        $needsInput += [regex]::Matches($line[$index], '(?i)\bneeds input\b').Count

        $profileHit = $false
        foreach ($pattern in @($windowsProfile, $unixProfile)) {
            foreach ($match in [regex]::Matches($line[$index], $pattern)) {
                $account = $match.Groups['name'].Value
                if (-not $profileHit -and $neutralName -notcontains $account -and $account -notmatch '^[%$]') {
                    $profileHit = $true
                    Add-Finding -Severity Error -Code 'UserProfilePath' -File $name -Line ($index + 1) -Message 'The line holds a user-profile path; the account name is withheld here. Use a path relative to this folder.'
                }
            }
        }

        if (-not $profileHit -and $line[$index] -match $driveRoot) {
            Add-Finding -Severity Warning -Code 'MachinePath' -File $name -Line ($index + 1) -Message 'The line holds a drive-letter path that exists on one machine only; name it relative to this folder, or keep it only where the machine matters.'
        }

        for ($termIndex = 0; $termIndex -lt $term.Count; $termIndex++) {
            if ($line[$index] -match ('(?i)(?<![\p{L}\p{N}_])' + [regex]::Escape($term[$termIndex]) + '(?![\p{L}\p{N}_])')) {
                Add-Finding -Severity Error -Code 'ForbiddenTerm' -File $name -Line ($index + 1) -Message ('The line holds forbidden term {0} of {1}; the term is withheld here.' -f ($termIndex + 1), $term.Count)
            }
        }
    }

    if ($needsInput -gt 0) {
        Add-Finding -Severity Warning -Code 'NeedsInput' -File $name -Message ('{0} unresolved needs input marker(s); each is a fact a person has to supply.' -f $needsInput)
    }
}

# The commits a finished row cites have to exist and be on the integration branch.
if ($PSBoundParameters.ContainsKey('Repository')) {
    if ($null -eq (Get-Command -Name git -CommandType Application -ErrorAction SilentlyContinue)) {
        throw 'git is not installed, and checking commits needs it.'
    }

    $script:repositoryRoot = (Resolve-Path -LiteralPath $Repository).ProviderPath
    if ((Invoke-GitExitCode -Argument @('rev-parse', '--verify', '--quiet', ($IntegrationBranch + '^{commit}'))) -ne 0) {
        Add-Finding -Severity Error -Code 'IntegrationBranchMissing' -File 'LEDGER.md' -Message 'The integration branch does not resolve to a commit in the repository.'
    } else {
        $commitToken = '(?<![0-9A-Za-z_.])(?<token>[0-9a-fA-F]{7,40}(?:\.{2,3}[0-9a-fA-F]{7,40})?)(?![0-9A-Za-z_])'
        foreach ($entry in @($row | Where-Object { $_.Status -in @('Done', 'Done with concerns', 'Needs context', 'Blocked') })) {
            # Every commit-shaped word counts, in a code span or out of one; a word with no digit is not a commit.
            $cell = $entry.Commits -replace '[`*]', ' '
            $found = @([regex]::Matches($cell, $commitToken) | ForEach-Object { $_.Groups['token'].Value } | Where-Object { $_ -match '[0-9]' })
            if ($found.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($cell) -and $cell.Trim() -notmatch '^(?i:none|n/a|-|\u2014|\u2013)(?![\p{L}\p{N}])') {
                Add-Finding -Severity Warning -Code 'CommitsUnchecked' -File 'LEDGER.md' -Line $entry.Line -Message ('Row {0} names no commit the check can read; write each commit as 7 to 40 hexadecimal characters, or none.' -f $entry.Nn)
            }

            foreach ($token in $found) {
                foreach ($commit in @($token -split '\.{2,3}')) {
                    if ((Invoke-GitExitCode -Argument @('cat-file', '-e', ($commit + '^{commit}'))) -ne 0) {
                        Add-Finding -Severity Error -Code 'CommitMissing' -File 'LEDGER.md' -Line $entry.Line -Message ('Row {0} cites commit {1}, which does not exist in the repository.' -f $entry.Nn, $commit)
                    } elseif ((Invoke-GitExitCode -Argument @('merge-base', '--is-ancestor', $commit, $IntegrationBranch)) -ne 0) {
                        Add-Finding -Severity Error -Code 'CommitNotOnBranch' -File 'LEDGER.md' -Line $entry.Line -Message ('Row {0} cites commit {1}, which is not on {2}.' -f $entry.Nn, $commit, $IntegrationBranch)
                    }
                }
            }
        }
    }
}

$errorCount = @($script:finding | Where-Object { $_.Severity -eq 'Error' }).Count
$warningCount = @($script:finding | Where-Object { $_.Severity -eq 'Warning' }).Count
[pscustomobject]@{
    Path         = $root
    Passed       = ($errorCount -eq 0)
    ErrorCount   = $errorCount
    WarningCount = $warningCount
    BriefCount   = $brief.Count
    RowCount     = $row.Count
    Finding      = $script:finding.ToArray()
}
