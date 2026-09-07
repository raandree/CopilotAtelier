function Get-CopilotAtelierSkillHealth
{
    <#
        .SYNOPSIS
            Reports Skill maintenance evidence on demand without changing
            anything.

        .DESCRIPTION
            Produces a read-only maintenance report for a Skill collection by
            combining four separate evidence sources and keeping them separate:
            structural facts read from each SKILL.md, discoverability material
            read from authored trigger-query sets, evaluation material read from
            the eval artifacts that already exist beside a Skill, and usage
            material taken from explicitly imported observation records.

            Evidence sources and what each one can prove:

            - Structural checks read the shipped files. They prove description
              and body budgets, frontmatter parsing, and lexical overlap between
              two discovery descriptions. Overlap flags a candidate for a human
              comparison; it never proves duplication.
            - Trigger-query sets prove that discovery material was authored. This
              command never runs one, so discovery stays unmeasured and Executed
              is always reported as false.
            - Eval artifacts are read in the shapes the agent-evals Skill
              defines. `evals.json` is authored input and proves only that cases
              were written. `grading.json` and `benchmark.json` are run output
              and carry no Skill identity of their own, so a run counts towards
              the current body only when a validated sidecar, named after the
              artifact with its extension replaced (`grading.provenance.json`
              beside `grading.json`), names this Skill, the SHA-256 of its
              current body, and a real completion instant no later than the
              reference instant. A run bound to a different body is labelled and
              excluded, a run with no valid provenance is shown as unbound and
              never counted, and a run identifier is consumed only by a graded
              result that could be counted, so a benchmark arm sharing it costs
              nothing. Copies of one run that agree are counted once; copies that
              disagree are exposed and none of them is counted. A graded run
              counts only when its summary reconciles exactly with bounded
              Boolean assertion verdicts, so a summary with no assertions, a
              contradicted verdict, an ungraded case, a non-Boolean verdict, and
              a count that is missing, negative, non-numeric, or out of range
              never become a pass. Assertion text and evidence are never read out
              of an artifact. A successful file load or read is never reported as
              a passed capability evaluation. This command is not a second
              evaluation engine and runs no model.
            - Observation records supply usage. A file read, a Skill activation,
              and a tool execution outcome are counted separately and are never
              promoted into one another or into demonstrated quality.

            Supported client evidence and the known gap: within the scope this
            command can inspect, which is the deployed authoring Instruction and
            the shipped hook configuration under the content root at the version
            present there, the enumerated hook events are SessionStart,
            UserPromptSubmit, PreToolUse, PostToolUse, PreCompact, SubagentStart,
            SubagentStop, and Stop, and each one is verified against that
            Instruction rather than asserted. None of them reports that a Skill
            was selected, loaded, or executed, so no reliable Skill-activation
            contract is verified for this implementation. Another client, or a
            newer version of this one, may expose a contract this check cannot
            see; the report states the verification state rather than claiming a
            universal fact. Consequently no automatic collection exists and
            capture is disabled by default. Usage evidence therefore reaches the
            report only through ObservationPath, every record is reported as
            Imported rather than observed, and a document that claims observed
            trust is recorded as a claim and read as imported.

            Missing telemetry means unknown, never zero use, and never evidence
            that a Skill should be removed. An imported file read is evidence of
            a read, not of an activation and not of complete capture. Suggestions
            are advisory only: each one cites local evidence and carries a human
            decision marker. A retirement review is raised only when an import
            declares, for this Skill and this body, that activation capture was
            complete over a window wide enough and recent enough to judge, and
            that window recorded no activation. It is never raised for a mandatory
            Skill, never inferred from a window belonging to another Skill, never
            inferred from file reads, and never a decision. The report never
            edits, removes, retires, or reconfigures a Skill, a setting, or an
            installation, and it never contacts the network.

            Retention: an imported record may carry an event identifier, an event
            type, a Skill name, a SHA-256 content identity, a UTC timestamp, a
            session identifier, and an explicit outcome label, all bounded in
            length. Prompt text, Skill bodies, tool responses, credentials, and
            free-form notes are not part of the schema, so a document carrying
            them is refused rather than partially read. A rejection names the
            field and the rule and never echoes the offending value. Nothing is
            stored and nothing is uploaded.

            Observations are bound to a Skill name and to the SHA-256 of the body
            they name. Records produced against a different body are counted and
            labelled separately instead of merged into the current body. An event
            identifier is unique only inside the client and session that minted
            it, so exact copies deduplicate while records that share one identity
            scope and disagree are reported as a conflict with the import locator
            of every variant, and none of them is accepted.

        .PARAMETER ContentPath
            The directory that holds the customization directories. Defaults to
            the module base, or the repository root when the source files are
            dot-sourced during development.

        .PARAMETER ObservationPath
            One or more explicitly selected files or directories holding
            validated observation import documents. A directory contributes its
            JSON files. A document may also declare coverage: an explicit claim,
            per Skill and per body, that activation capture was complete over a
            stated window. Omit the parameter to run with no usage evidence,
            which reports usage as unknown.

        .PARAMETER ReferenceUtc
            The UTC instant that freshness and staleness are measured against.
            Defaults to the current UTC time. Supply it to obtain a deterministic
            report.

        .PARAMETER AsText
            Returns a deterministic, human-readable summary string instead of the
            structured report object.

        .OUTPUTS
            System.Management.Automation.PSCustomObject
            System.String

        .EXAMPLE
            Get-CopilotAtelierSkillHealth

            Returns the structured maintenance report with no usage evidence.

        .EXAMPLE
            Get-CopilotAtelierSkillHealth -ObservationPath ~/skill-observations -AsText

            Prints the maintenance summary using explicitly imported observations.

        .EXAMPLE
            (Get-CopilotAtelierSkillHealth).Suggestion | Where-Object Kind -eq 'Consolidate'

            Lists the Skills whose discovery descriptions overlap enough to review.

        .LINK
            https://github.com/raandree/CopilotAtelier
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject], [System.String])]
    param
    (
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $ContentPath,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [System.String[]]
        $ObservationPath,

        [Parameter()]
        [System.DateTime]
        $ReferenceUtc = [System.DateTime]::UtcNow,

        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $AsText
    )

    $ErrorActionPreference = 'Stop'

    if (-not $PSBoundParameters.ContainsKey('ContentPath'))
    {
        $ContentPath = Get-CopilotAtelierContentPath
    }

    $ContentPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ContentPath)

    if (-not (Test-Path -LiteralPath $ContentPath -PathType Container))
    {
        throw "The customization content path '$ContentPath' does not exist or is not a directory."
    }

    if ($ReferenceUtc.Kind -eq [System.DateTimeKind]::Local)
    {
        $ReferenceUtc = $ReferenceUtc.ToUniversalTime()
    }
    elseif ($ReferenceUtc.Kind -eq [System.DateTimeKind]::Unspecified)
    {
        $ReferenceUtc = [System.DateTime]::SpecifyKind($ReferenceUtc, [System.DateTimeKind]::Utc)
    }

    $observation = $null
    if ($PSBoundParameters.ContainsKey('ObservationPath'))
    {
        $observation = Import-CopilotAtelierSkillObservation -Path $ObservationPath -ReferenceUtc $ReferenceUtc
    }

    $report = Measure-CopilotAtelierSkillHealth -ContentPath $ContentPath -DirectoryMap (Get-CopilotAtelierDirectoryMap) -Observation $observation -ReferenceUtc $ReferenceUtc

    if (-not $AsText)
    {
        return $report
    }

    $line = [System.Collections.Generic.List[string]]::new()
    $line.Add('Skill health report')
    $line.Add("Content path: $($report.ContentPath)")
    $line.Add("Reference time (UTC): $($report.ReferenceUtc.ToString('yyyy-MM-ddTHH:mm:ssZ'))")
    $line.Add('')
    $line.Add('Observation gap:')
    $line.Add("  Supported activation event : $($report.Telemetry.ActivationEventSupported)")
    $line.Add("  Contract verification      : $($report.Telemetry.VerificationState)")
    $line.Add("  Verification scope         : $($report.Telemetry.VerificationScope)")
    $line.Add("  Capture                    : $($report.Telemetry.CaptureMode) (enabled: $($report.Telemetry.CaptureEnabled))")
    $line.Add("  $($report.Telemetry.Gap)")
    foreach ($source in $report.Telemetry.Source)
    {
        $line.Add("  Source $($source.RelativePath) available: $($source.Available)")
    }
    $line.Add('')
    $line.Add('Imported observations:')
    $line.Add("  Files read       : $($report.Observation.FileCount)")
    $line.Add("  Records accepted : $($report.Observation.AcceptedCount)")
    $line.Add("  Duplicates       : $($report.Observation.DuplicateCount)")
    $line.Add("  Conflicts        : $($report.Observation.ConflictCount)")
    $line.Add("  Rejected files   : $(@($report.Observation.RejectedFile).Count)")
    $line.Add("  Rejected records : $(@($report.Observation.RejectedRecord).Count)")
    $line.Add("  Coverage claims  : $(@($report.Observation.Coverage).Count) accepted, $(@($report.Observation.RejectedCoverage).Count) rejected")
    $line.Add("  Window           : $($report.Observation.WindowDay) days, $($report.Observation.SessionCount) sessions ($($report.Observation.EvidenceSufficiency))")
    $line.Add("  Trust            : $($report.Observation.EffectiveTrust)")
    foreach ($conflict in $report.Observation.ConflictingRecord)
    {
        $line.Add("  Conflicting identity $($conflict.IdentityScope) in: $(@($conflict.Source | ForEach-Object -Process { "$($_.Path)#$($_.Index)" }) -join '; ')")
    }
    if (@($report.Observation.UnknownSkillName).Count -gt 0)
    {
        $line.Add("  Records naming a Skill that is not installed: $(@($report.Observation.UnknownSkillName) -join ', ')")
    }
    $line.Add('')
    $line.Add('Per Skill (facets are reported separately and never combined):')
    $line.Add(('  {0,-32} {1,-14} {2,-16} {3,-13} {4,-14} {5}' -f 'Skill', 'Usage', 'Evaluation', 'Quality', 'Discoverability', 'Overlap'))
    foreach ($current in $report.Skill)
    {
        $usageText = if ($current.Usage.Coverage -eq 'Observed')
        {
            "act $($current.Usage.ActivationCount)/read $($current.Usage.FileReadCount)"
        }
        else
        {
            'unknown'
        }
        $line.Add(('  {0,-32} {1,-14} {2,-16} {3,-13} {4,-14} {5}' -f
                $current.Name,
                $usageText,
                $current.Evaluation.State,
                $current.Quality.State,
                $current.Discoverability.TriggerQuerySet,
                $current.Overlap.PartnerCount))
    }
    $line.Add('')
    $line.Add('Suggestions (advisory; every suggestion needs a human decision):')
    if (@($report.Suggestion).Count -eq 0)
    {
        $line.Add('  (none)')
    }
    foreach ($item in $report.Suggestion)
    {
        $line.Add("  [$($item.Severity)] $($item.Kind) $($item.Skill): $($item.Reason)")
        $line.Add("      evidence: $(@($item.Evidence) -join '; ')")
    }
    $line.Add('')
    $line.Add($report.Disclaimer)

    return ($line -join [System.Environment]::NewLine)
}
