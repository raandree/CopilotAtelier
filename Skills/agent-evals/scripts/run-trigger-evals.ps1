#requires -Version 7.0
<#
.SYNOPSIS
    Trigger-eval harness: measures whether a skill's description causes an
    agent to select it, using labelled positive and near-miss negative queries
    with a train/validation split.

.DESCRIPTION
    Output evals (run-evals.ps1) ask "given the skill fired, was the answer
    good?". This asks the prior question: "does the skill fire at all, and does
    it stay quiet when it shouldn't?". A skill that never triggers cannot
    produce a good output, so this gate comes first.

    The harness runs in three modes.

    -Mode Prepare (no credential needed)
        Validates the query set, loads every SKILL.md description from -SkillRoot,
        and emits one judge prompt per query x repetition into -WorkDir. Each
        prompt presents the full skill catalogue and one user query, and asks
        which skill would be selected. Feed these to a model that has NOT seen
        the authoring session, save each reply as the matching .out.txt, then
        run -Mode Grade.

    -Mode Execute (needs ShellPilot)
        Does the same as Prepare, then answers each prompt itself via
        Invoke-Shp and writes the replies, so Grade can run immediately.
        Requires the ShellPilot module and a working backend.

        The judge runs with tools, browsing, file and terminal access all
        disabled. It sees only the catalogue and the query, so its answer
        cannot be contaminated by the repository it is judging. The session
        conversation is reset before every call, so each judge call is a genuinely
        fresh context rather than one carrying every previous verdict.

    -Mode Grade (no credential needed)
        Reads the replies, extracts the selected skill name, and reports the
        trigger rate per query and the pass rate per split.

    The train/validation split exists to catch overfitting. Iterate the
    description against train queries only; validation queries are scored but
    never used to decide an edit. If train improves while validation stalls,
    the description has been tuned to the test rather than to the concept.

    A note on who may judge. Do not grade a skill using the same session that
    wrote it: that measures recall of authoring intent, not discoverability.
    Execute mode satisfies this because each call is a fresh context with no
    history of the authoring conversation - which requires resetting the
    ShellPilot session conversation between calls, since Invoke-Shp continues it
    by default. See the comment in Execute mode.

.PARAMETER QueryFile
    Labelled query set. Schema: [ { id, query, should_trigger, split, note? } ].

.PARAMETER TargetSkill
    Directory name of the skill under test, e.g. 'skill-creator'.

.PARAMETER SkillRoot
    Root holding one directory per skill, each with a SKILL.md. Point it at
    `Skills/`, not at the repository root: the search is recursive, so a root
    that also contains a built copy of the module puts every skill in the
    catalogue twice and silently changes what the judge is choosing between.

.PARAMETER WorkDir
    Where prompts and replies live. Keep it outside the repository: Skills/ is
    the published module payload, so scratch written under the skill folder
    ends up in the built module. Relative paths resolve against the caller's
    location, not the script's, so prefer an absolute path.

.PARAMETER Repetitions
    Runs per query. Selection is stochastic; a single run cannot distinguish a
    reliable trigger from a lucky one. Default 3.

.PARAMETER TriggerThreshold
    Fraction of repetitions that must agree for a query to count as triggering.
    Default 0.5.

.PARAMETER Model
    Execute mode only. The judge model. A cheap model is appropriate: the task
    is a single forced-choice selection, not reasoning.

.PARAMETER Temperature
    Execute mode only. Sampling temperature for the judge, 0 to 2. Pass 0 to pin
    the run: selection is stochastic, so without it a query that scores 1 of 3
    cannot be told apart from a reliable trigger that got unlucky, and the
    measurement describes the sampler as much as the description under test.
    Omitted entirely from the call when you do not pass it, so the backend
    default applies and an existing run's operating point does not move. Needs a
    ShellPilot new enough to expose Invoke-Shp -Temperature, first shipped in
    0.4.0-preview0004; Execute mode checks for the parameter once and throws
    before the first call rather than failing every call in the binder.

.PARAMETER MaxBudgetUSD
    Execute mode only. Hard ceiling passed to each call.

.PARAMETER Force
    Execute mode only. Re-answer prompts whose reply file already exists.

.EXAMPLE
    ./run-trigger-evals.ps1 -Mode Prepare -QueryFile ../assets/trigger-queries.skill-creator.json -TargetSkill skill-creator -SkillRoot ../../ -WorkDir "$env:TEMP/trigger-evals/skill-creator"

.EXAMPLE
    ./run-trigger-evals.ps1 -Mode Execute -QueryFile ../assets/trigger-queries.skill-creator.json -TargetSkill skill-creator -SkillRoot ../../ -WorkDir "$env:TEMP/trigger-evals/skill-creator"

.EXAMPLE
    ./run-trigger-evals.ps1 -Mode Execute -QueryFile ../assets/trigger-queries.skill-creator.json -TargetSkill skill-creator -SkillRoot ../../ -WorkDir "$env:TEMP/trigger-evals/skill-creator" -Temperature 0

    Pins the judge so a repeated run measures the description rather than the
    sampler. Compare against an unpinned run to see how much of a partial score
    was noise.

.EXAMPLE
    ./run-trigger-evals.ps1 -Mode Grade -QueryFile ../assets/trigger-queries.skill-creator.json -TargetSkill skill-creator -WorkDir "$env:TEMP/trigger-evals/skill-creator"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Prepare', 'Execute', 'Grade')]
    [string] $Mode,

    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string] $QueryFile,

    [Parameter(Mandatory)]
    [string] $TargetSkill,

    [string] $SkillRoot,

    [Parameter(Mandatory)]
    [string] $WorkDir,

    [ValidateRange(1, 20)]
    [int] $Repetitions = 3,

    [ValidateRange(0.0, 1.0)]
    [double] $TriggerThreshold = 0.5,

    [string] $Model = 'claude-haiku-4.5',

    [ValidateRange(0.0, 2.0)]
    [double] $Temperature,

    [double] $MaxBudgetUSD = 2.0,

    [switch] $Force
)

$ErrorActionPreference = 'Stop'

function Get-SkillCatalogue {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Root)

    if (-not (Get-Module -ListAvailable -Name powershell-yaml)) {
        throw 'powershell-yaml is required. Install-Module powershell-yaml -Scope CurrentUser'
    }
    Import-Module powershell-yaml -ErrorAction Stop

    foreach ($file in Get-ChildItem -LiteralPath $Root -Filter 'SKILL.md' -Recurse -File) {
        $raw = [System.IO.File]::ReadAllText($file.FullName)
        $m = [regex]::Match($raw, '(?s)\A---\r?\n(.*?)\r?\n---\r?\n')
        if (-not $m.Success) {
            Write-Warning "No frontmatter: $($file.FullName)"
            continue
        }
        try {
            $fm = ConvertFrom-Yaml $m.Groups[1].Value
        }
        catch {
            # A skill whose frontmatter will not load cannot be selected at all.
            Write-Warning "Frontmatter does not parse, skill is unloadable: $($file.Directory.Name) - $($_.Exception.Message)"
            continue
        }
        [pscustomobject]@{
            Name        = [string]$fm.name
            Description = [string]$fm.description
        }
    }
}

function Test-QuerySet {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object[]] $Queries)

    $problems = [System.Collections.Generic.List[string]]::new()

    $dupes = $Queries | Group-Object id | Where-Object Count -gt 1
    foreach ($d in $dupes) { $problems.Add("duplicate id: $($d.Name)") }

    foreach ($q in $Queries) {
        if ([string]::IsNullOrWhiteSpace($q.id))    { $problems.Add('a query has no id') }
        if ([string]::IsNullOrWhiteSpace($q.query)) { $problems.Add("query '$($q.id)' has empty text") }
        if ($q.split -notin 'train', 'validation')  { $problems.Add("query '$($q.id)' has invalid split '$($q.split)'") }
        if ($q.should_trigger -isnot [bool])        { $problems.Add("query '$($q.id)' should_trigger is not a boolean") }
    }

    # Upstream guidance: 8-10 positives and 8-10 near-miss negatives. Fewer
    # negatives than positives is the common failure - it hides over-triggering,
    # because a description that matches everything scores perfectly on
    # positives alone.
    $pos = @($Queries | Where-Object { $_.should_trigger }).Count
    $neg = @($Queries | Where-Object { -not $_.should_trigger }).Count
    if ($pos -lt 8) { $problems.Add("only $pos positive queries; guidance says 8-10") }
    if ($neg -lt 8) { $problems.Add("only $neg negative queries; guidance says 8-10") }

    foreach ($split in 'train', 'validation') {
        $inSplit = @($Queries | Where-Object { $_.split -eq $split })
        if (@($inSplit | Where-Object { $_.should_trigger }).Count -lt 1) {
            $problems.Add("split '$split' has no positive queries")
        }
        if (@($inSplit | Where-Object { -not $_.should_trigger }).Count -lt 1) {
            $problems.Add("split '$split' has no negative queries")
        }
    }

    $problems
}

function New-JudgePromptSet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]   $Root,
        [Parameter(Mandatory)][string]   $Target,
        [Parameter(Mandatory)][object[]] $Queries,
        [Parameter(Mandatory)][int]      $Reps
    )

    $catalogue = @(Get-SkillCatalogue -Root $Root | Sort-Object Name)
    if (-not $catalogue) { throw "No loadable skills found under '$Root'." }
    if ($catalogue.Name -notcontains $Target) {
        throw "Target skill '$Target' is not in the catalogue - it may be unloadable. See warnings above."
    }

    $sb = [System.Text.StringBuilder]::new()
    foreach ($s in $catalogue) { $null = $sb.AppendLine("- $($s.Name): $($s.Description)") }
    $catalogueText = $sb.ToString()

    foreach ($q in $Queries) {
        foreach ($rep in 1..$Reps) {
            $prompt = @"
You are an agent with the skills listed below. Read the user message and decide
which single skill, if any, you would load before answering.

Answer with exactly one line:
SELECTED: <skill-name>
or
SELECTED: none

Do not explain.

AVAILABLE SKILLS
$catalogueText
USER MESSAGE
$($q.query)
"@
            [pscustomobject]@{
                Id     = $q.id
                Rep    = $rep
                Count  = $catalogue.Count
                Prompt = $prompt
            }
        }
    }
}

$queries = @(Get-Content -LiteralPath $QueryFile -Raw -Encoding utf8 | ConvertFrom-Json)
if (-not $queries) { throw "Query file '$QueryFile' is empty." }

$issues = @(Test-QuerySet -Queries $queries)
if ($issues.Count -gt 0) {
    Write-Host 'Query set problems:' -ForegroundColor Yellow
    $issues | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
    if ($issues | Where-Object { $_ -match 'duplicate|empty|invalid|not a boolean' }) {
        throw 'Query set is structurally invalid; fix the errors above.'
    }
}

$null = New-Item -ItemType Directory -Path $WorkDir -Force

switch ($Mode) {
    'Prepare' {
        if (-not $SkillRoot) { throw '-SkillRoot is required in Prepare mode.' }

        $set = @(New-JudgePromptSet -Root $SkillRoot -Target $TargetSkill -Queries $queries -Reps $Repetitions)
        $enc = New-Object System.Text.UTF8Encoding $false
        foreach ($item in $set) {
            $path = Join-Path $WorkDir "$($item.Id).rep$($item.Rep).prompt.txt"
            [System.IO.File]::WriteAllText($path, $item.Prompt, $enc)
        }

        Write-Host "Prepared $($set.Count) prompts in '$WorkDir' across $($set[0].Count) skills." -ForegroundColor Cyan
        Write-Host 'Run each against a model with no prior context of this session,' -ForegroundColor Cyan
        Write-Host 'save the reply next to it as <id>.rep<n>.out.txt, then use -Mode Grade.' -ForegroundColor Cyan
    }

    'Execute' {
        if (-not $SkillRoot) { throw '-SkillRoot is required in Execute mode.' }
        $shp = Get-Command Invoke-Shp -ErrorAction SilentlyContinue
        if (-not $shp) {
            throw 'Execute mode needs the ShellPilot module (Invoke-Shp). Use -Mode Prepare instead.'
        }

        # Probe the parameter, not the version: 0.4.0-preview0003 reports version
        # 0.4.0 and has no -Temperature, so any minimum-version test passes on the
        # build that fails. Only what this run needs is checked - an older
        # ShellPilot is fine as long as -Temperature was not asked for. Without
        # this, a stale module fails every call in the parameter binder and a
        # 54-call run reports 54 failures that never name the cause.
        if ($PSBoundParameters.ContainsKey('Temperature') -and -not $shp.Parameters.ContainsKey('Temperature')) {
            $module = $shp.Module
            $resolved = if ($module) {
                $prerelease = if ($module.PrivateData.PSData.Prerelease) { "-$($module.PrivateData.PSData.Prerelease)" }
                "$($module.Name) $($module.Version)$prerelease at $($module.ModuleBase)"
            }
            else {
                "an Invoke-Shp defined outside any module ($($shp.CommandType))"
            }

            throw "-Temperature requires a ShellPilot that exposes Invoke-Shp -Temperature. " +
                "The resolved module is $resolved. Import a newer build by path " +
                "(Import-Module <dir>/ShellPilot.psd1 -Force) or install one. " +
                'Omit -Temperature to run against the resolved build.'
        }

        $set = @(New-JudgePromptSet -Root $SkillRoot -Target $TargetSkill -Queries $queries -Reps $Repetitions)
        $enc = New-Object System.Text.UTF8Encoding $false
        $done = 0
        $failed = 0
        $spent = 0.0

        # Omit-or-send: 0 is a meaningful temperature, so binding is the only
        # safe test. Defaulting it would move the operating point of every run
        # that never asked for one.
        $samplingParams = @{}
        if ($PSBoundParameters.ContainsKey('Temperature')) { $samplingParams['Temperature'] = $Temperature }

        foreach ($item in $set) {
            $stem = Join-Path $WorkDir "$($item.Id).rep$($item.Rep)"
            [System.IO.File]::WriteAllText("$stem.prompt.txt", $item.Prompt, $enc)
            $outPath = "$stem.out.txt"

            if ((Test-Path -LiteralPath $outPath -PathType Leaf) -and -not $Force) {
                $done++
                continue
            }

            try {
                # Every Invoke-Shp -Prompt call seeds from AND writes back to the
                # module-scoped session conversation, so a loop like this one
                # accumulates every prompt and reply. Measured 2026-08-11 on this
                # query set: calls 1-18 succeeded and calls 19-54 all failed with
                # HTTP 400 model_max_prompt_tokens_exceeded once the accumulated
                # conversation passed claude-haiku-4.5's 136k window - and never
                # recovered, because a failed call does not write back. Re-running
                # the script "fixed" it only because a fresh process starts with
                # an empty conversation, which is what made the failure look
                # transient and get misread as rate limiting.
                #
                # Resetting here also restores the isolation this harness claims:
                # a judge that carries 18 previous verdicts is not a fresh
                # context, so the scores were contaminated well before the first
                # 400. Do not remove without re-measuring.
                Clear-ShpChat

                $r = Invoke-Shp -Prompt $item.Prompt -Model $Model `
                    -DisableUserTools -DisableBrowsing -DisableFileAccess `
                    -DisableTerminal -DisableUserPrompts -DisableTodoList `
                    -MaxBudgetUSD $MaxBudgetUSD -TimeoutSec 120 @samplingParams -ErrorAction Stop
                [System.IO.File]::WriteAllText($outPath, [string]$r.Content, $enc)
                if ($null -ne $r.CostUSD) { $spent += [double]$r.CostUSD }
                $done++
            }
            catch {
                # Record the failure rather than aborting: one bad call should not
                # discard the rest of the run. Grade counts missing replies.
                Write-Warning "$($item.Id) rep$($item.Rep) failed: $($_.Exception.Message)"
                $failed++
            }

            Write-Progress -Activity 'Trigger eval' -Status "$done/$($set.Count)" `
                -PercentComplete (100.0 * $done / $set.Count)
        }
        Write-Progress -Activity 'Trigger eval' -Completed

        Write-Host "Executed $done/$($set.Count) prompts against $Model  failures=$failed  cost=$([math]::Round($spent, 4)) USD" -ForegroundColor Cyan
        Write-Host "Now: -Mode Grade -WorkDir '$WorkDir'" -ForegroundColor Cyan
    }

    'Grade' {
        $missing = 0
        $rows = foreach ($q in $queries) {
            $hits = 0
            $seen = 0
            foreach ($rep in 1..$Repetitions) {
                $out = Join-Path $WorkDir "$($q.id).rep$rep.out.txt"
                if (-not (Test-Path -LiteralPath $out -PathType Leaf)) { $missing++; continue }
                $seen++
                $text = [string](Get-Content -LiteralPath $out -Raw -Encoding utf8)
                $m = [regex]::Match($text, '(?im)^\s*SELECTED:\s*(?<sel>[a-z0-9._-]+)\s*$')
                if ($m.Success -and $m.Groups['sel'].Value -eq $TargetSkill) { $hits++ }
            }

            $rate = if ($seen -gt 0) { $hits / $seen } else { [double]::NaN }
            $triggered = ($seen -gt 0 -and $rate -ge $TriggerThreshold)

            [pscustomobject]@{
                Id       = $q.id
                Split    = $q.split
                Expected = [bool]$q.should_trigger
                Runs     = $seen
                Hits     = $hits
                Rate     = if ($seen -gt 0) { [math]::Round($rate, 2) } else { $null }
                Correct  = ($seen -gt 0 -and $triggered -eq [bool]$q.should_trigger)
            }
        }

        if ($missing -gt 0) {
            Write-Warning "$missing reply file(s) missing; those repetitions were not scored."
        }

        $scored = @($rows | Where-Object { $_.Runs -gt 0 })
        if (-not $scored) {
            Write-Host 'No replies found. Run -Mode Prepare or -Mode Execute, then grade.' -ForegroundColor Yellow
            exit 2
        }

        $rows | Sort-Object Split, Id | Format-Table -AutoSize

        foreach ($split in 'train', 'validation') {
            $s = @($scored | Where-Object { $_.Split -eq $split })
            if (-not $s) { continue }
            $ok = @($s | Where-Object Correct).Count
            $fp = @($s | Where-Object { -not $_.Correct -and -not $_.Expected }).Count
            $fn = @($s | Where-Object { -not $_.Correct -and $_.Expected }).Count
            '{0,-11} pass {1,2}/{2,-2} ({3,5:P0})  false-positive {4}  false-negative {5}' -f `
                $split, $ok, $s.Count, ($ok / $s.Count), $fp, $fn
        }

        Write-Host ''
        Write-Host 'Iterate on train only. If train climbs while validation does not,' -ForegroundColor Cyan
        Write-Host 'the description is overfitted - generalise to the concept instead of' -ForegroundColor Cyan
        Write-Host 'adding keywords from failed queries.' -ForegroundColor Cyan
    }
}
