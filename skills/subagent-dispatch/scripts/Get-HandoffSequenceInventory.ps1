#Requires -Version 5.1

<#
.SYNOPSIS
    Inventories a folder of prompts before it is converted to the task-ledger process.
.DESCRIPTION
    Read-only. Lists every prompt-like file at the top of the folder (*.prompt.md,
    *.md, and *.txt, apart from a README, a ledger, and report files), the README,
    the ledger, the report files, and any sign that a prompt already ran: a report
    that states a status, or commits a report or a prompt names.

    For each prompt it proposes the NN-slug.prompt.md name, reads the agent from
    the front matter, names the slots the brief template has and the file lacks,
    and surfaces the lines that hint at a dependency or at a remote step. It
    records the SHA-256 of every file a migration has to keep, and lists a rule
    that several prompts repeat. The numbers come from the ordinals in the file
    names when they are unique, with any unnumbered file after them in file
    order, and from the file order alone otherwise; either fallback warns.

    A report belongs to the one prompt it names. A report that could belong to
    several is left unowned and warned about, and so is a link, which the script
    never reads through.

    AlreadyMigrated is true when the folder has 00-README.md and LEDGER.md under
    exactly those names and every *.prompt.md at its top is named
    NN-slug.prompt.md; any other note beside such a set is a warning, not a
    prompt. Original then lists the briefs that lack a slot, the only files a
    migration edits; in any other folder it lists every file the migration moves.
    The script returns one object and changes nothing, so it is safe to run on
    the only copy of the prompts.
.PARAMETER Path
    The folder that holds the prompts.
.EXAMPLE
    $inventory = ./Get-HandoffSequenceInventory.ps1 -Path ./old-prompts
    $inventory.Prompt | Format-Table File, ProposedName, Agent, ProposedStatus -AutoSize

    Lists each prompt with the name, agent, and status a migration would give it.
.OUTPUTS
    System.Management.Automation.PSCustomObject
#>

[CmdletBinding()]
[OutputType([pscustomobject])]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
    [string] $Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path -Path $PSScriptRoot -ChildPath 'HandoffSequenceCommon.ps1')

$root = (Resolve-Path -LiteralPath $Path).ProviderPath
$warning = [Collections.Generic.List[string]]::new()

$conformingName = '^(?<nn>\d{2,3})-(?<slug>[a-z0-9]+(?:-[a-z0-9]+)*)\.prompt\.md$'
$readmeName = '^(?i:(?:\d{2}-)?readme(?:\.md|\.txt)?)$'
$ledgerName = '^(?i:ledger(?:\.md)?)$'
$strictReportName = '(?i)\.report\.(?:md|txt)$'
$looseReportName = '(?i)[-_]report\.(?:md|txt)$'
$ordinalPrefix = '^(?i:(?:p|prompt|step|task|brief|handoff)[-_ ]?)?(?<nn>\d{1,3})(?:[-_. ]+|$)'
$dependencyWord = '(?i)\b(?:after|depends? on|requires?|waits? for|prerequisite|blocked by|builds? on)\b'
$dependencyTopic = '(?i)\b(?:prompts?|briefs?|handoff|steps?|tasks?|\d+)\b'
$remoteWord = '(?i)\b(?:push(?:es|ed|ing)?|pull requests?|merg(?:e|es|ed|ing)|releas(?:e|es|ed|ing)|publish(?:es|ed|ing)?|deploy(?:s|ed|ing|ment)?|tag(?:s|ged|ging)?)\b'

function Get-RelativeName {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $FullName
    )

    $FullName.Substring($root.Length).TrimStart('\', '/').Replace('\', '/')
}

function Get-Slug {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text
    )

    $slug = ($Text.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
    if ($slug.Length -gt 48) {
        $slug = $slug.Substring(0, 48).TrimEnd('-')
    }

    if ([string]::IsNullOrEmpty($slug)) {
        'brief'
    } else {
        $slug
    }
}

# The name a prompt or a report goes by: no extension, no ordinal prefix, and for a report no report suffix.
function Get-StemKey {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter()]
        [switch] $ForReport
    )

    $stem = $Name -replace '(?i)\.(?:prompt\.md|report\.md|report\.txt|md|txt)$', ''
    if ($ForReport) {
        $stem = $stem -replace '(?i)[-_.]report$', ''
    }

    $stem = $stem -replace $ordinalPrefix, ''
    Get-Slug -Text $stem
}

# True when the short name's words appear, in order and side by side, among the long name's words.
function Test-WordRun {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string] $Long,

        [Parameter(Mandatory)]
        [string] $Short
    )

    $longWord = @($Long -split '-')
    $shortWord = @($Short -split '-')
    for ($start = 0; $start -le $longWord.Count - $shortWord.Count; $start++) {
        $same = $true
        for ($offset = 0; $offset -lt $shortWord.Count; $offset++) {
            if ($longWord[$start + $offset] -ne $shortWord[$offset]) {
                $same = $false
                break
            }
        }

        if ($same) {
            return $true
        }
    }

    $false
}

function Get-NormalizedLine {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text
    )

    ($Text -replace '^\s*(?:[-*+]|\d+[.)])\s+', '' -replace '\s+', ' ').Trim()
}

# Top-level files only, none of them a link: prompt-like files, the README, the ledger, and reports.
$topFile = [Collections.Generic.List[object]]::new()
foreach ($file in @(Get-ChildItem -LiteralPath $root -File | Sort-Object -Property Name)) {
    if (Test-HandoffReparsePoint -Item $file) {
        if ($file.Name -match '\.(?:prompt\.md|md|txt)$') {
            $warning.Add(('{0} is a link; the inventory does not read through links.' -f $file.Name))
        }

        continue
    }

    $topFile.Add($file)
}

$readme = @($topFile | Where-Object { $_.Name -match $readmeName } | Select-Object -First 1)
$ledger = @($topFile | Where-Object { $_.Name -match $ledgerName } | Select-Object -First 1)

# A folder that already follows the process has these two files under exactly these names.
$inProcess = @($topFile | Where-Object { $_.Name -ceq '00-README.md' }).Count -gt 0 -and @($topFile | Where-Object { $_.Name -ceq 'LEDGER.md' }).Count -gt 0

$candidate = @(
    $topFile | Where-Object {
        $_.Name -match '\.(?:prompt\.md|md|txt)$' -and
        $_.Name -notmatch $readmeName -and
        $_.Name -notmatch $ledgerName -and
        $_.Name -notmatch $strictReportName -and
        $_.Name -ne 'migration-report.md'
    }
)

# Beside a migrated set only a *.prompt.md file is a brief; any other file is a note to leave alone.
$promptFile = $candidate
if ($inProcess) {
    $promptFile = @($candidate | Where-Object { $_.Name -match '\.prompt\.md$' })
    foreach ($file in @($candidate | Where-Object { $_.Name -notmatch '\.prompt\.md$' })) {
        $warning.Add(('{0} sits beside a migrated set and is not a brief; leave it, or name it NN-<slug>.prompt.md to make it one.' -f $file.Name))
    }
}

$reportFile = [Collections.Generic.List[object]]::new()
foreach ($file in @($topFile | Where-Object { $_.Name -match $strictReportName -and $_.Name -ne 'migration-report.md' })) {
    $reportFile.Add($file)
}

# A top-level NAME-report.md is the report of the prompt NAME when one exists, and a prompt otherwise.
foreach ($file in @($promptFile | Where-Object { $_.Name -match $looseReportName })) {
    $key = Get-StemKey -Name $file.Name -ForReport
    $named = @($promptFile | Where-Object { $_.FullName -ne $file.FullName -and (Get-StemKey -Name $_.Name) -eq $key })
    if ($named.Count -eq 1) {
        $reportFile.Add($file)
        $promptFile = @($promptFile | Where-Object { $_.FullName -ne $file.FullName })
    }
}

$reportFolder = Join-Path -Path $root -ChildPath 'reports'
if (Test-Path -LiteralPath $reportFolder -PathType Container) {
    if (Test-HandoffReparsePoint -Item (Get-Item -LiteralPath $reportFolder -Force)) {
        $warning.Add('The folder reports is a link; the inventory does not read through links.')
    } else {
        foreach ($file in @(Get-ChildItem -LiteralPath $reportFolder -File | Sort-Object -Property Name)) {
            if (Test-HandoffReparsePoint -Item $file) {
                $warning.Add(('reports/{0} is a link; the inventory does not read through links.' -f $file.Name))
                continue
            }

            $reportFile.Add($file)
        }
    }
}

foreach ($folder in @(Get-ChildItem -LiteralPath $root -Directory | Where-Object { $_.Name -notin @('reports', 'originals') } | Sort-Object -Property Name)) {
    if (Test-HandoffReparsePoint -Item $folder) {
        $warning.Add(('The folder {0} is a link; the inventory does not read through links.' -f $folder.Name))
        continue
    }

    # A bounded depth keeps a cyclic junction from sending the walk around forever.
    $inside = @(Get-ChildItem -LiteralPath $folder.FullName -Recurse -Depth 3 -File -Filter '*.md') + @(Get-ChildItem -LiteralPath $folder.FullName -Recurse -Depth 3 -File -Filter '*.txt')
    if ($inside.Count -gt 0) {
        $warning.Add(('The folder {0} holds {1} prompt-like file(s) that this inventory does not read; move them up a level, or run the inventory on that folder.' -f $folder.Name, $inside.Count))
    }
}

# Numbers: the ordinals in the names when they are unique, with the unnumbered files after them in file order.
$entry = @(
    foreach ($file in $promptFile) {
        $ordinal = $null
        $conforming = $file.Name -match $conformingName
        if ($conforming) {
            $ordinal = [int]$Matches['nn']
        } elseif (($file.Name -replace '(?i)\.(?:prompt\.md|md|txt)$', '') -match $ordinalPrefix) {
            $ordinal = [int]$Matches['nn']
        }

        [pscustomobject]@{
            File       = $file.Name
            Full       = $file.FullName
            Ordinal    = $ordinal
            Conforming = $conforming
        }
    }
)

$withOrdinal = @($entry | Where-Object { $null -ne $_.Ordinal })
$ordinalsUnique = @($withOrdinal | ForEach-Object { $_.Ordinal } | Select-Object -Unique).Count -eq $withOrdinal.Count
$useOrdinal = $withOrdinal.Count -gt 0 -and $ordinalsUnique
$numberSource = 'order'
if ($useOrdinal -and $withOrdinal.Count -eq $entry.Count) {
    $numberSource = 'filename'
} elseif ($useOrdinal) {
    $numberSource = 'mixed'
    $warning.Add('A file whose name carries a number keeps it; the others are numbered after those, in file order. Confirm the order before you rely on it.')
} elseif ($entry.Count -gt 0) {
    $warning.Add('The numbers follow the file order, because the file names do not each carry their own ordinal; confirm the order before you rely on it.')
}

$ordered = [Collections.Generic.List[object]]::new()
if ($useOrdinal) {
    $numbered = @($withOrdinal | Sort-Object -Property @{ Expression = { $_.Ordinal } }, @{ Expression = { $_.File.ToLowerInvariant() } })
    $unnumbered = @($entry | Where-Object { $null -eq $_.Ordinal } | Sort-Object -Property @{ Expression = { $_.File.ToLowerInvariant() } })
    $next = [int]($numbered | Measure-Object -Property Ordinal -Maximum).Maximum
    foreach ($item in $numbered) {
        $ordered.Add($item)
    }

    foreach ($item in $unnumbered) {
        $next++
        $item.Ordinal = $next
        $ordered.Add($item)
    }
} else {
    $position = 0
    foreach ($item in @($entry | Sort-Object -Property @{ Expression = { $_.File.ToLowerInvariant() } })) {
        $position++
        $item.Ordinal = $position
        $ordered.Add($item)
    }
}

$prompt = [Collections.Generic.List[object]]::new()

# A report belongs to the one prompt it names: an exact name first, a name that contains or is contained
# only when no other prompt could be meant. An ambiguous report is left unowned and warned about.
$slugOf = @{}
foreach ($item in $ordered) {
    $slugOf[$item.File] = Get-StemKey -Name $item.File
}

$reportOwner = @{}
foreach ($file in $reportFile) {
    $key = Get-StemKey -Name $file.Name -ForReport
    $relativeReport = Get-RelativeName -FullName $file.FullName
    $exact = @($ordered | Where-Object { $slugOf[$_.File] -eq $key })
    if ($exact.Count -eq 1) {
        $reportOwner[$relativeReport] = $exact[0].File
    } elseif ($exact.Count -gt 1) {
        $warning.Add(('The report {0} names {1} prompts equally; it is used for none of them.' -f $relativeReport, $exact.Count))
    } elseif ($key.Length -ge 4) {
        $near = @($ordered | Where-Object {
                $other = $slugOf[$_.File]
                $other.Length -ge 4 -and ((Test-WordRun -Long $other -Short $key) -or (Test-WordRun -Long $key -Short $other))
            })
        if ($near.Count -eq 1) {
            $reportOwner[$relativeReport] = $near[0].File
        } elseif ($near.Count -gt 1) {
            $warning.Add(('The report {0} could belong to {1} prompts; it is used for none of them.' -f $relativeReport, $near.Count))
        }
    }
}

foreach ($item in $ordered) {
    $text = Read-HandoffText -Path $item.Full
    $front = Get-HandoffFrontMatter -Text $text
    $body = [string]$front.Body
    $number = '{0:00}' -f $item.Ordinal
    $slug = Get-StemKey -Name $item.File
    $proposedName = if ($item.Conforming -and $numberSource -ne 'order') { $item.File } else { '{0}-{1}.prompt.md' -f $number, $slug }

    $agent = 'needs input'
    $description = $null
    if ($front.IsValid) {
        if (-not [string]::IsNullOrWhiteSpace([string]$front.Value['agent'])) {
            $agent = [string]$front.Value['agent']
        }

        if (-not [string]::IsNullOrWhiteSpace([string]$front.Value['description'])) {
            $description = [string]$front.Value['description']
        }
    }

    # String operations, not a backtracking pattern: a long line of blanks must not cost time that grows with its square.
    $title = $null
    $firstLine = $null
    foreach ($current in ($body -split '\r?\n')) {
        $trimmed = $current.Trim()
        if ($trimmed.Length -eq 0) {
            continue
        }

        if ($null -eq $firstLine) {
            $firstLine = $trimmed
        }

        if ($trimmed.Length -ge 2 -and $trimmed[0] -eq '#' -and ($trimmed[1] -eq ' ' -or $trimmed[1] -eq "`t")) {
            $title = $trimmed.Substring(1).Trim()
            break
        }
    }

    if ([string]::IsNullOrEmpty($title)) {
        $title = if ($null -ne $firstLine) { $firstLine.TrimStart('#', '*', '_', ' ', "`t").TrimEnd('*', '_', ' ', "`t") } else { $item.File }
        if ([string]::IsNullOrEmpty($title)) {
            $title = $item.File
        }
    }

    $dependencyHint = @(
        foreach ($current in ($body -split '\r?\n')) {
            $line = $current.Trim()
            if ($line -and $line -notmatch '^#' -and $line -match $dependencyWord -and $line -match $dependencyTopic) {
                $line
            }
        }
    )

    $remote = [Collections.Generic.List[string]]::new()
    foreach ($match in [regex]::Matches($body, $remoteWord)) {
        $word = $match.Value.ToLowerInvariant()
        $canonical = if ($word -match '^push') { 'push' }
        elseif ($word -match '^pull request') { 'pull request' }
        elseif ($word -match '^merg') { 'merge' }
        elseif ($word -match '^releas') { 'release' }
        elseif ($word -match '^publish') { 'publish' }
        elseif ($word -match '^deploy') { 'deploy' }
        else { 'tag' }
        if (-not $remote.Contains($canonical)) {
            $remote.Add($canonical)
        }
    }

    $report = $null
    $reportText = $null
    $matching = @($reportFile | Where-Object { $reportOwner[(Get-RelativeName -FullName $_.FullName)] -eq $item.File })
    if ($matching.Count -gt 0) {
        $report = Get-RelativeName -FullName $matching[0].FullName
        $reportText = Read-HandoffText -Path $matching[0].FullName
        if ($matching.Count -gt 1) {
            $warning.Add(('{0} reports match {1}; the first one is used.' -f $matching.Count, $item.File))
        }
    }

    $commit = [Collections.Generic.List[string]]::new()
    $evidence = [Collections.Generic.List[string]]::new()
    $status = 'Not started'
    $statusSource = 'none'
    $promptCommit = @(Get-HandoffCommitToken -Text $text)
    if ($null -ne $report) {
        $evidence.Add('report: ' + $report)
        $stated = Get-HandoffReportStatus -Text $reportText
        if ($null -ne $stated) {
            $evidence.Add('report status: ' + $stated)
            $status = $stated
            $statusSource = 'report'
        } else {
            $status = 'needs input'
        }

        $reportCommit = @(Get-HandoffCommitToken -Text $reportText)
        if ($reportCommit.Count -gt 0) {
            $evidence.Add('commits named in the report: ' + ($reportCommit -join ', '))
            foreach ($token in $reportCommit) {
                if (-not $commit.Contains($token)) {
                    $commit.Add($token)
                }
            }
        }
    }

    if ($promptCommit.Count -gt 0) {
        $evidence.Add('commits named in the prompt: ' + ($promptCommit -join ', '))
        foreach ($token in $promptCommit) {
            if (-not $commit.Contains($token)) {
                $commit.Add($token)
            }
        }

        if ($null -eq $report) {
            $status = 'needs input'
        }
    }

    $prompt.Add([pscustomobject]@{
            File             = $item.File
            Format           = if ($item.File -match '\.prompt\.md$') { 'prompt.md' } elseif ($item.File -match '\.md$') { 'md' } else { 'txt' }
            Sha256           = Get-HandoffFileHash -Path $item.Full
            ProposedNumber   = $number
            NumberSource     = $numberSource
            ProposedName     = $proposedName
            Title            = $title
            Description      = if ($null -ne $description) { $description } else { $title }
            Agent            = $agent
            HasFrontMatter   = [bool]$front.IsValid
            Dependency       = 'needs input'
            DependencyHint   = $dependencyHint
            MissingSlot      = @(Get-HandoffMissingSlot -Text $text)
            RemoteActionHint = $remote.ToArray()
            Report           = $report
            RanEvidence      = $evidence.ToArray()
            Commit           = $commit.ToArray()
            ProposedStatus   = $status
            StatusSource     = $statusSource
        })
}

$alreadyMigrated = $inProcess -and $entry.Count -gt 0 -and @($entry | Where-Object { -not $_.Conforming }).Count -eq 0

# An originals folder that exists already is not this run's to fill: a copy must never overwrite a file in it.
if (-not $alreadyMigrated -and (Test-Path -LiteralPath (Join-Path -Path $root -ChildPath 'originals') -PathType Container)) {
    $warning.Add('The folder already holds an originals folder; a copy must never overwrite a file in it, so ask which files it keeps before you copy.')
}

# A report that no prompt claims is worth a look.
$claimed = @($prompt | Where-Object { $null -ne $_.Report } | ForEach-Object { $_.Report })
foreach ($file in $reportFile) {
    $relative = Get-RelativeName -FullName $file.FullName
    if ($claimed -notcontains $relative) {
        $warning.Add(('The report {0} matches no prompt.' -f $relative))
    }
}

# A line that several prompts repeat is a candidate for the README's shared rules.
$repeated = [Collections.Generic.List[object]]::new()
if (-not $alreadyMigrated) {
    $seen = [ordered]@{}
    foreach ($item in $prompt) {
        $body = [string](Get-HandoffFrontMatter -Text (Read-HandoffText -Path (Join-Path -Path $root -ChildPath $item.File))).Body
        foreach ($current in ($body -split '\r?\n')) {
            $normalized = Get-NormalizedLine -Text $current
            if ($normalized.Length -lt 25 -or $normalized -match '^(?:#|---|```|~~~)') {
                continue
            }

            $key = $normalized.ToLowerInvariant()
            if (-not $seen.Contains($key)) {
                $seen[$key] = [pscustomobject]@{ Text = $normalized; File = [Collections.Generic.List[string]]::new() }
            }

            if (-not $seen[$key].File.Contains($item.File)) {
                $seen[$key].File.Add($item.File)
            }
        }
    }

    foreach ($key in $seen.Keys) {
        if ($seen[$key].File.Count -gt 1) {
            $repeated.Add([pscustomobject]@{ Text = $seen[$key].Text; File = $seen[$key].File.ToArray() })
        }
    }
}

# What a migration has to keep, byte for byte. In a folder that already follows the process the only files a
# migration edits are the briefs that lack a slot, so those are the files to keep a copy of first.
$original = [Collections.Generic.List[object]]::new()
if ($alreadyMigrated) {
    foreach ($item in @($prompt | Where-Object { @($_.MissingSlot).Count -gt 0 })) {
        $original.Add([pscustomobject]@{ File = $item.File; Sha256 = $item.Sha256 })
    }
} else {
    $keep = [Collections.Generic.List[object]]::new()
    foreach ($item in $prompt) {
        $keep.Add([pscustomobject]@{ File = $item.File; Full = Join-Path -Path $root -ChildPath $item.File })
    }

    foreach ($file in @($readme) + @($ledger)) {
        if ($null -ne $file -and $file -is [IO.FileInfo]) {
            $keep.Add([pscustomobject]@{ File = $file.Name; Full = $file.FullName })
        }
    }

    foreach ($file in $reportFile) {
        $keep.Add([pscustomobject]@{ File = (Get-RelativeName -FullName $file.FullName); Full = $file.FullName })
    }

    foreach ($item in $keep) {
        $original.Add([pscustomobject]@{ File = $item.File; Sha256 = Get-HandoffFileHash -Path $item.Full })
    }
}

$publishBrief = @($prompt | Where-Object { $_.File -match '(?i)\bpublish' -or $_.Title -match '(?i)\bpublish' }).Count -gt 0
$remoteHint = @($prompt | Where-Object { $_.RemoteActionHint.Count -gt 0 }).Count -gt 0

[pscustomobject]@{
    Path               = $root
    AlreadyMigrated    = $alreadyMigrated
    Readme             = if ($readme.Count -gt 0) { $readme[0].Name } else { $null }
    Ledger             = if ($ledger.Count -gt 0) { $ledger[0].Name } else { $null }
    Report             = @($reportFile | ForEach-Object { Get-RelativeName -FullName $_.FullName })
    Prompt             = $prompt.ToArray()
    RepeatedLine       = $repeated.ToArray()
    Original           = $original.ToArray()
    PublishBriefNeeded = ($remoteHint -and -not $publishBrief)
    Warning            = $warning.ToArray()
}
