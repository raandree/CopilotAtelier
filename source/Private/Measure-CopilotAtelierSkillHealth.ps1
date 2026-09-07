function Measure-CopilotAtelierSkillHealth
{
    <#
        .SYNOPSIS
            Measures Skill maintenance evidence and produces separated findings.

        .DESCRIPTION
            Combines four independent evidence sources over a Skill collection:
            structural facts read from each SKILL.md, discoverability material
            read from authored trigger-query sets, evaluation material read from
            existing eval artifacts, and usage material taken from explicitly
            imported observation records.

            Each source stays in its own facet. An observed file read is never
            promoted to an activation, an activation is never promoted to a tool
            success, and neither is ever promoted to demonstrated quality. An
            evaluation that was authored but never executed is reported as
            unexecuted rather than as a pass. No facet is collapsed into a single
            invented health score.

            Observations are bound to a Skill name and to the SHA-256 of the body
            they name, so records produced against a different body are counted
            and labelled separately instead of merged into the current body.

            Suggestions are advisory. Every suggestion cites local evidence and
            carries a human decision marker; the function changes nothing.

        .PARAMETER ContentPath
            The content root that holds the customization source directories.

        .PARAMETER DirectoryMap
            The deployed directory name to source relative path map, as returned
            by Get-CopilotAtelierDirectoryMap.

        .PARAMETER Observation
            The validated import result from Import-CopilotAtelierSkillObservation,
            or $null when no observation import was selected.

        .PARAMETER ReferenceUtc
            The UTC instant that freshness and staleness are measured against.

        .OUTPUTS
            System.Management.Automation.PSCustomObject

        .EXAMPLE
            Measure-CopilotAtelierSkillHealth -ContentPath $content -DirectoryMap (Get-CopilotAtelierDirectoryMap) -Observation $null -ReferenceUtc ([datetime]::UtcNow)

            Returns the structural, discoverability, and evaluation facets with no usage evidence.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $ContentPath,

        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]
        $DirectoryMap,

        [Parameter()]
        [System.Object]
        $Observation,

        [Parameter(Mandatory = $true)]
        [System.DateTime]
        $ReferenceUtc
    )

    $ErrorActionPreference = 'Stop'

    # Advisory thresholds. They decide what is worth a human's attention; none of
    # them decides anything about the installed catalog.
    $descriptionCap = 1024
    $bodyLineBudget = 500
    $staleObservationDay = 90
    $overlapTermThreshold = 4
    $sufficientWindowDay = 30
    $sufficientSessionCount = 20
    $minimumTermLength = 4

    # Documented read bounds. Every file this report opens is size-bounded, and
    # an artifact over the bound is reported as oversize rather than read.
    $maxArtifactByte = 1048576
    $maxSkillCount = 2000
    $maxEvalArtifactPerSkill = 200
    $maxAssertionPerArtifact = 5000

    $stopWord = @(
        'also', 'and', 'any', 'are', 'because', 'been', 'both', 'but', 'can', 'each', 'else', 'for',
        'from', 'have', 'here', 'into', 'its', 'just', 'like', 'more', 'most', 'must', 'not', 'once',
        'only', 'other', 'over', 'same', 'should', 'skill', 'some', 'such', 'than', 'that', 'their',
        'them', 'then', 'there', 'these', 'they', 'this', 'those', 'through', 'use', 'used', 'uses',
        'using', 'very', 'was', 'were', 'what', 'when', 'where', 'which', 'while', 'will', 'with',
        'would', 'your'
    )

    $contentRootFull = [System.IO.Path]::GetFullPath($ContentPath).TrimEnd([char[]] '\/')
    Assert-CopilotAtelierRegularPath -LiteralPath $contentRootFull -RootPath $contentRootFull -ErrorAction Stop

    $utf8 = [System.Text.Encoding]::UTF8
    $frontmatterPattern = [regex]::new('^---[ \t]*\r?\n(.*?)\r?\n---[ \t]*(\r?\n|$)', [System.Text.RegularExpressions.RegexOptions]::Singleline)
    $skillNamePattern = [regex]::new('^[a-z0-9]+(-[a-z0-9]+)*$')
    $sha256Pattern = [regex]::new('^[0-9a-fA-F]{64}$')
    $identifierPattern = [regex]::new('^[\x20-\x7E]+$')

    # A provenance completion instant follows the same rules as an observation
    # timestamp: an explicit UTC instant, no earlier than the plausible floor and
    # no later than the instant the report is measured against.
    $timestampFormat = @(
        'yyyy-MM-ddTHH:mm:ssZ'
        'yyyy-MM-ddTHH:mm:ss.fffZ'
        'yyyy-MM-ddTHH:mm:ss.fffffffZ'
    )
    $earliestUtc = [datetime]::SpecifyKind([datetime]::new(2020, 1, 1), [System.DateTimeKind]::Utc)

    $parseTimestamp = {
        param ($Value)

        if ($Value -is [datetime])
        {
            if ($Value.Kind -eq [System.DateTimeKind]::Utc) { return $Value }
            if ($Value.Kind -eq [System.DateTimeKind]::Local) { return $Value.ToUniversalTime() }
            return [datetime]::SpecifyKind($Value, [System.DateTimeKind]::Utc)
        }

        $parsed = [datetime]::MinValue
        if ($Value -is [string] -and [datetime]::TryParseExact(
                $Value,
                $timestampFormat,
                [System.Globalization.CultureInfo]::InvariantCulture,
                [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal,
                [ref] $parsed))
        {
            return [datetime]::SpecifyKind($parsed, [System.DateTimeKind]::Utc)
        }

        return $null
    }

    # --- Supported client event contract ------------------------------------
    # The event names below are the ones the deployed authoring Instruction
    # enumerates. Each is verified against that file rather than asserted, and
    # the claim is scoped to this implementation: another client, or a newer
    # version of this one, may expose a contract this check cannot see.
    $instructionPath = Join-Path (Join-Path $ContentPath $DirectoryMap['instructions']) 'copilot-authoring.instructions.md'
    $hookPath = Join-Path (Join-Path $ContentPath $DirectoryMap['hooks']) 'hooks.json'

    $instructionText = ''
    $instructionAvailable = $false
    if (Test-Path -LiteralPath $instructionPath -PathType Leaf)
    {
        Assert-CopilotAtelierRegularPath -LiteralPath $instructionPath -RootPath $contentRootFull -ErrorAction Stop
        if ((Get-Item -LiteralPath $instructionPath -Force).Length -le $maxArtifactByte)
        {
            $instructionText = $utf8.GetString([System.IO.File]::ReadAllBytes($instructionPath))
            $instructionAvailable = $true
        }
    }

    $eventContract = @(
        [pscustomobject] @{ Event = 'SessionStart'; Payload = 'session identifier, working directory'; Limitation = 'Fires once per session and names no Customization.' }
        [pscustomobject] @{ Event = 'UserPromptSubmit'; Payload = 'prompt text'; Limitation = 'Carries prompt text, which this report never retains, and names no Skill.' }
        [pscustomobject] @{ Event = 'PreToolUse'; Payload = 'tool name, tool input'; Limitation = 'A tool name is not a Skill identity and tool input is untrusted content.' }
        [pscustomobject] @{ Event = 'PostToolUse'; Payload = 'tool name, tool response'; Limitation = 'A tool response is raw output this report never retains.' }
        [pscustomobject] @{ Event = 'PreCompact'; Payload = 'trigger, transcript path'; Limitation = 'The transcript path is documented as unstable and is never read here.' }
        [pscustomobject] @{ Event = 'SubagentStart'; Payload = 'subagent lifecycle'; Limitation = 'A forked Skill and any other subagent are indistinguishable in the payload.' }
        [pscustomobject] @{ Event = 'SubagentStop'; Payload = 'subagent lifecycle'; Limitation = 'Same limitation as SubagentStart.' }
        [pscustomobject] @{ Event = 'Stop'; Payload = 'stop_hook_active'; Limitation = 'Closes a turn and names no Customization.' }
    )

    $supportedClientEvent = @(
        foreach ($entry in $eventContract)
        {
            $documented = $instructionAvailable -and [regex]::IsMatch($instructionText, "\b$([regex]::Escape($entry.Event))\b")
            [pscustomobject] @{
                Event             = $entry.Event
                Payload           = $entry.Payload
                IdentifiesSkill   = $false
                DocumentedInSource = $documented
                Limitation        = $entry.Limitation
            }
        }
    )

    $verificationState = if ($instructionAvailable -and @($supportedClientEvent | Where-Object -FilterScript { -not $_.DocumentedInSource }).Count -eq 0) { 'Verified' } else { 'Unverified' }

    $telemetrySource = @(
        [pscustomobject] @{
            RelativePath = 'instructions/copilot-authoring.instructions.md'
            Claim        = 'Enumerates the hook events a client dispatches and their payload fields.'
            Available    = $instructionAvailable
        }
        [pscustomobject] @{
            RelativePath = 'hooks/hooks.json'
            Claim        = 'The shipped hook configuration, which registers no Skill-activation event.'
            Available    = (Test-Path -LiteralPath $hookPath -PathType Leaf)
        }
    )

    $telemetry = [pscustomobject] @{
        ActivationEventSupported = $false
        CaptureEnabled           = $false
        CaptureMode              = 'None'
        VerificationState        = $verificationState
        VerificationScope        = 'The deployed authoring Instruction and the shipped hook configuration under the inspected content root, at the version present there. No client was executed and no client API was queried.'
        SupportedClientEvent     = $supportedClientEvent
        SupportedCaptureClient   = @()
        Gap                      = 'Within that scope there is no reliable Skill-activation contract verified for this implementation: none of the enumerated events reports that a Skill was selected, loaded, or executed. No automatic capture is implemented and none is enabled. Usage evidence can only come from explicitly imported observation records, and the absence of a record means unknown use rather than no use.'
        Source                   = $telemetrySource
    }

    # --- Skill inventory -----------------------------------------------------
    $skillsRoot = Join-Path $ContentPath $DirectoryMap['skills']
    $inventory = [System.Collections.Generic.List[object]]::new()

    if (Test-Path -LiteralPath $skillsRoot -PathType Container)
    {
        $skillsRootFull = [System.IO.Path]::GetFullPath($skillsRoot).TrimEnd([char[]] '\/')
        Assert-CopilotAtelierRegularPath -LiteralPath $skillsRootFull -RootPath $contentRootFull -ErrorAction Stop

        foreach ($folder in Get-ChildItem -LiteralPath $skillsRootFull -Directory -Force -ErrorAction Stop | Sort-Object -Property Name)
        {
            Assert-CopilotAtelierRegularPath -LiteralPath $folder.FullName -RootPath $skillsRootFull -ErrorAction Stop

            $skillFilePath = Join-Path $folder.FullName 'SKILL.md'
            if (-not (Test-Path -LiteralPath $skillFilePath -PathType Leaf))
            {
                continue
            }
            Assert-CopilotAtelierRegularPath -LiteralPath $skillFilePath -RootPath $skillsRootFull -ErrorAction Stop

            if ($inventory.Count -ge $maxSkillCount)
            {
                throw "The inspected Skills root holds more than $maxSkillCount Skills, which is the documented read bound."
            }

            $skillFileItem = Get-Item -LiteralPath $skillFilePath -Force
            if ($skillFileItem.Length -gt $maxArtifactByte)
            {
                $inventory.Add([pscustomobject] @{
                        Name               = $folder.Name
                        Sha256             = $null
                        RelativePath       = "skills/$($folder.Name)/SKILL.md"
                        FolderPath         = $folder.FullName
                        DeclaredName       = $null
                        Description        = ''
                        DescriptionLength  = 0
                        BodyLineCount      = 0
                        FrontmatterFence   = $false
                        MetadataParseState = 'Oversize'
                        LastWriteUtc       = $skillFileItem.LastWriteTimeUtc
                        Term               = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
                    })
                continue
            }

            $bytes = [System.IO.File]::ReadAllBytes($skillFilePath)
            $sha256 = [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::Create().ComputeHash($bytes)).Replace('-', '').ToLowerInvariant()
            $text = $utf8.GetString($bytes)
            if ($text.Length -gt 0 -and $text[0] -eq [char] 0xFEFF)
            {
                $text = $text.Substring(1)
            }

            # A matching fence is not proof of valid metadata, so the block is
            # only reported as parsed when every line is a supported top-level
            # key and both identity fields resolved to a scalar.
            $fenceFound = $false
            $metadataSupported = $true
            $declaredName = $null
            $description = ''
            $scalarKey = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
            $body = $text
            $match = $frontmatterPattern.Match($text)
            if ($match.Success -and $match.Index -eq 0)
            {
                $fenceFound = $true
                $body = $text.Substring($match.Length)
                $frontmatterLine = @($match.Groups[1].Value -split '\r?\n')
                for ($lineIndex = 0; $lineIndex -lt $frontmatterLine.Count; $lineIndex++)
                {
                    $line = $frontmatterLine[$lineIndex]
                    if ([string]::IsNullOrWhiteSpace($line) -or $line.TrimStart().StartsWith('#'))
                    {
                        continue
                    }
                    if ($line -notmatch '^(?<key>[A-Za-z][A-Za-z0-9_-]*)\s*:\s*(?<value>.*)$')
                    {
                        $metadataSupported = $false
                        continue
                    }
                    $key = $Matches.key
                    $value = $Matches.value.Trim()
                    $isScalar = $true
                    if ($value -match '^[|>][+-]?[0-9]*$')
                    {
                        # A block scalar continues while the following lines are indented.
                        $collected = [System.Collections.Generic.List[string]]::new()
                        while ($lineIndex + 1 -lt $frontmatterLine.Count -and $frontmatterLine[$lineIndex + 1] -match '^\s+\S')
                        {
                            $lineIndex++
                            $collected.Add($frontmatterLine[$lineIndex].Trim())
                        }
                        $value = ($collected -join ' ')
                    }
                    elseif ($value.Length -eq 0)
                    {
                        # An empty value followed by indented lines is a nested
                        # node, not a scalar, so the key carries no usable text.
                        while ($lineIndex + 1 -lt $frontmatterLine.Count -and $frontmatterLine[$lineIndex + 1] -match '^\s+\S')
                        {
                            $lineIndex++
                            $isScalar = $false
                        }
                    }
                    elseif ($value.Length -ge 2 -and ($value[0] -eq "'" -or $value[0] -eq '"') -and $value[$value.Length - 1] -eq $value[0])
                    {
                        $value = $value.Substring(1, $value.Length - 2)
                    }

                    if ($isScalar)
                    {
                        $null = $scalarKey.Add($key)
                    }

                    if ($key -eq 'name') { $declaredName = $value }
                    elseif ($key -eq 'description') { $description = $value }
                }
            }

            $metadataParseState = 'Absent'
            if ($fenceFound)
            {
                $identityUsable = $scalarKey.Contains('name') -and $scalarKey.Contains('description') -and
                    -not [string]::IsNullOrWhiteSpace($declaredName) -and -not [string]::IsNullOrWhiteSpace($description)
                $metadataParseState = if ($metadataSupported -and $identityUsable) { 'Parsed' } else { 'Unsupported' }
            }

            $bodyLineCount = @($body -split '\r?\n').Count

            $term = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
            foreach ($token in ([regex]::Matches($description.ToLowerInvariant(), '[a-z][a-z0-9]*') | ForEach-Object -Process { $_.Value }))
            {
                if ($token.Length -ge $minimumTermLength -and $token -notin $stopWord)
                {
                    $null = $term.Add($token)
                }
            }

            $inventory.Add([pscustomobject] @{
                    Name               = $folder.Name
                    Sha256             = $sha256
                    RelativePath       = "skills/$($folder.Name)/SKILL.md"
                    FolderPath         = $folder.FullName
                    DeclaredName       = $declaredName
                    Description        = $description
                    DescriptionLength  = $description.Length
                    BodyLineCount      = $bodyLineCount
                    FrontmatterFence   = $fenceFound
                    MetadataParseState = $metadataParseState
                    LastWriteUtc       = $skillFileItem.LastWriteTimeUtc
                    Term               = $term
                })
        }
    }

    $mandatorySkill = @((Get-CopilotAtelierProfileCatalog).MandatorySkill)

    # --- Observation binding -------------------------------------------------
    $acceptedRecord = @()
    if ($null -ne $Observation)
    {
        $acceptedRecord = @($Observation.Record)
    }

    $windowStartUtc = $null
    $windowEndUtc = $null
    $windowDay = 0
    $sessionCount = 0
    if ($acceptedRecord.Count -gt 0)
    {
        $windowStartUtc = ($acceptedRecord | Sort-Object -Property TimestampUtc | Select-Object -First 1).TimestampUtc
        $windowEndUtc = ($acceptedRecord | Sort-Object -Property TimestampUtc | Select-Object -Last 1).TimestampUtc
        $windowDay = [int] [System.Math]::Round(($windowEndUtc - $windowStartUtc).TotalDays)
        $sessionCount = @($acceptedRecord | Select-Object -ExpandProperty SessionId -Unique).Count
    }

    $evidenceSufficiency = 'None'
    if ($acceptedRecord.Count -gt 0)
    {
        $evidenceSufficiency = if ($windowDay -ge $sufficientWindowDay -and $sessionCount -ge $sufficientSessionCount) { 'Sufficient' } else { 'Insufficient' }
    }

    $installedName = @($inventory | ForEach-Object -Process { $_.Name })
    $unknownSkillName = @(
        $acceptedRecord |
            Where-Object -FilterScript { $_.SkillName -notin $installedName } |
            Select-Object -ExpandProperty SkillName -Unique |
            Sort-Object
    )

    $declaredTrust = @()
    if ($null -ne $Observation)
    {
        $declaredTrust = @($Observation.DeclaredTrust)
    }

    $coverageClaim = @()
    if ($null -ne $Observation)
    {
        $coverageClaim = @($Observation.Coverage)
    }

    $observationSummary = [pscustomobject] @{
        FileCount           = if ($null -ne $Observation) { $Observation.FileCount } else { 0 }
        AcceptedCount       = $acceptedRecord.Count
        DuplicateCount      = if ($null -ne $Observation) { $Observation.DuplicateCount } else { 0 }
        ConflictCount       = if ($null -ne $Observation) { $Observation.ConflictCount } else { 0 }
        ConflictingRecord   = if ($null -ne $Observation) { @($Observation.ConflictingRecord) } else { @() }
        RejectedFile        = if ($null -ne $Observation) { @($Observation.RejectedFile) } else { @() }
        RejectedRecord      = if ($null -ne $Observation) { @($Observation.RejectedRecord) } else { @() }
        RejectedCoverage    = if ($null -ne $Observation) { @($Observation.RejectedCoverage) } else { @() }
        Coverage            = $coverageClaim
        SourceFile          = if ($null -ne $Observation) { @($Observation.SourceFile) } else { @() }
        Client              = if ($null -ne $Observation) { @($Observation.Client) } else { @() }
        WindowStartUtc      = $windowStartUtc
        WindowEndUtc        = $windowEndUtc
        WindowDay           = $windowDay
        SessionCount        = $sessionCount
        EvidenceSufficiency = $evidenceSufficiency
        DeclaredTrust       = $declaredTrust
        EffectiveTrust      = 'Imported'
        TrustNote           = 'Every record is treated as imported. No supported client event produces an observation this module captured itself, so a document that declares observed trust is recorded as a claim and read as imported.'
        CoverageNote        = 'An imported window is not a coverage claim. Absence of a record means unknown use unless a validated coverage declaration states, for one Skill and one body, that activation capture was complete over a stated window.'
        UnknownSkillName    = $unknownSkillName
    }

    # --- Per-Skill facets ----------------------------------------------------
    $skill = [System.Collections.Generic.List[object]]::new()

    foreach ($current in $inventory)
    {
        $currentBody = @($acceptedRecord | Where-Object -FilterScript { $_.SkillName -eq $current.Name -and $_.SkillSha256 -eq $current.Sha256 })
        $otherBody = @($acceptedRecord | Where-Object -FilterScript { $_.SkillName -eq $current.Name -and $_.SkillSha256 -ne $current.Sha256 })

        $activationCount = @($currentBody | Where-Object -FilterScript { $_.EventType -eq 'SkillActivation' }).Count
        $fileReadCount = @($currentBody | Where-Object -FilterScript { $_.EventType -eq 'SkillFileRead' }).Count
        $toolExecution = @($currentBody | Where-Object -FilterScript { $_.EventType -eq 'SkillToolExecution' })
        $coverage = if ($currentBody.Count -gt 0) { 'Observed' } else { 'NoObservations' }
        $usageNote = if ($coverage -eq 'Observed')
        {
            'Counts come from imported records bound to the current body. They are a lower bound on use, never a complete usage measurement.'
        }
        else
        {
            'No imported record names this body, so use is unknown. Absence of a record is not evidence that this Skill was never used.'
        }

        $lastObservationUtc = $null
        $firstObservationUtc = $null
        if ($currentBody.Count -gt 0)
        {
            $firstObservationUtc = ($currentBody | Sort-Object -Property TimestampUtc | Select-Object -First 1).TimestampUtc
            $lastObservationUtc = ($currentBody | Sort-Object -Property TimestampUtc | Select-Object -Last 1).TimestampUtc
        }

        # Coverage is the only evidence that an absent record means an absent
        # use, and it is only ever an explicit, validated, per-body claim.
        $declaration = @(
            $coverageClaim |
                Where-Object -FilterScript {
                    $_.SkillName -eq $current.Name -and
                    $_.SkillSha256 -eq $current.Sha256 -and
                    $_.ActivationCaptureComplete
                }
        )
        $usableDeclaration = @(
            $declaration |
                Where-Object -FilterScript {
                    [int] [System.Math]::Round(($_.WindowEndUtc - $_.WindowStartUtc).TotalDays) -ge $sufficientWindowDay -and
                    $_.SessionCount -ge $sufficientSessionCount -and
                    [int] [System.Math]::Round(($ReferenceUtc - $_.WindowEndUtc).TotalDays) -le $staleObservationDay
                }
        )

        $usage = [pscustomobject] @{
            Coverage             = $coverage
            CoverageDeclared     = ($usableDeclaration.Count -gt 0)
            CoverageDeclaration  = $declaration
            ActivationCount      = $activationCount
            FileReadCount        = $fileReadCount
            ToolExecutionCount   = $toolExecution.Count
            ToolSuccessCount     = @($toolExecution | Where-Object -FilterScript { $_.Outcome -eq 'Success' }).Count
            ToolFailureCount     = @($toolExecution | Where-Object -FilterScript { $_.Outcome -eq 'Failure' }).Count
            SessionCount         = @($currentBody | Select-Object -ExpandProperty SessionId -Unique).Count
            FirstObservationUtc  = $firstObservationUtc
            LastObservationUtc   = $lastObservationUtc
            OtherBodyRecordCount = $otherBody.Count
            BodyVersionMismatch  = ($otherBody.Count -gt 0)
            Note                 = $usageNote
        }

        # Discoverability: authored trigger-query material only. A query set is
        # never a measured trigger rate; running one needs a model backend.
        $triggerRoot = Join-Path $skillsRoot 'agent-evals/assets'
        $triggerPath = Join-Path $triggerRoot "trigger-queries.$($current.Name).json"
        $triggerPresent = Test-Path -LiteralPath $triggerPath -PathType Leaf
        if ($triggerPresent)
        {
            # The set is read through the skills root, so guard the whole chain
            # rather than trusting a directory that was never enumerated.
            Assert-CopilotAtelierRegularPath -LiteralPath $triggerPath -RootPath $skillsRoot -ErrorAction Stop
        }
        $positiveCount = 0
        $negativeCount = 0
        $trainCount = 0
        $validationCount = 0
        if ($triggerPresent)
        {
            try
            {
                if ((Get-Item -LiteralPath $triggerPath -Force).Length -gt $maxArtifactByte)
                {
                    throw 'The trigger-query set exceeds the documented read bound.'
                }
                $query = @($utf8.GetString([System.IO.File]::ReadAllBytes($triggerPath)) | ConvertFrom-Json)
                $positiveCount = @($query | Where-Object -FilterScript { $_.should_trigger -eq $true }).Count
                $negativeCount = @($query | Where-Object -FilterScript { $_.should_trigger -eq $false }).Count
                $trainCount = @($query | Where-Object -FilterScript { $_.split -eq 'train' }).Count
                $validationCount = @($query | Where-Object -FilterScript { $_.split -eq 'validation' }).Count
            }
            catch
            {
                $triggerPresent = $false
            }
        }

        $discoverability = [pscustomobject] @{
            TriggerQuerySet   = if ($triggerPresent) { 'Present' } else { 'Absent' }
            TriggerQueryPath  = if ($triggerPresent) { "skills/agent-evals/assets/trigger-queries.$($current.Name).json" } else { $null }
            PositiveCount     = $positiveCount
            NegativeCount     = $negativeCount
            TrainCount        = $trainCount
            ValidationCount   = $validationCount
            Executed          = $false
            DescriptionLength = $current.DescriptionLength
            HasUseFor         = ($current.Description -match 'USE FOR:')
            HasDoNotUseFor    = ($current.Description -match 'DO NOT USE FOR:')
            Note              = 'A trigger-query set is authored material. This report never executes it, so discovery remains unmeasured.'
        }

        # Evaluation: the artifacts the agent-evals Skill actually defines, read
        # as they are. This is not a second evaluation engine. `evals.json` is
        # authored input in either the Agent Skills shape or the bundled harness
        # shape; `grading.json` and `benchmark.json` are run output. Run output
        # carries no Skill identity of its own, so it counts towards the current
        # body only through an explicit, validated provenance sidecar.
        $artifact = [System.Collections.Generic.List[object]]::new()
        $authoredCaseCount = 0
        $executedRunCount = 0
        $passedCount = 0
        $failedCount = 0
        $evalRoot = Join-Path $current.FolderPath 'evals'
        if ($null -ne $current.Sha256 -and (Test-Path -LiteralPath $evalRoot -PathType Container))
        {
            Assert-CopilotAtelierRegularPath -LiteralPath $evalRoot -RootPath $current.FolderPath -ErrorAction Stop

            $evalFile = @(
                Get-ChildItem -LiteralPath $evalRoot -File -Force -Filter '*.json' -ErrorAction Stop |
                    Where-Object -FilterScript { -not $_.Name.EndsWith('.provenance.json', [System.StringComparison]::OrdinalIgnoreCase) } |
                    Sort-Object -Property Name
            )

            if ($evalFile.Count -gt $maxEvalArtifactPerSkill)
            {
                throw "The evals directory for '$($current.Name)' holds more than $maxEvalArtifactPerSkill artifacts, which is the documented read bound."
            }

            foreach ($file in $evalFile)
            {
                Assert-CopilotAtelierRegularPath -LiteralPath $file.FullName -RootPath $evalRoot -ErrorAction Stop

                $relativePath = "skills/$($current.Name)/evals/$($file.Name)"
                $kind = 'Unrecognized'
                $binding = 'NotApplicable'
                $caseCount = 0
                $artifactPassed = 0
                $artifactFailed = 0
                $artifactTotal = 0
                $countsValid = $false
                $executed = $false
                $runId = $null
                $assertionCount = 0
                $assertionState = 'NotApplicable'
                $provenanceRelativePath = $null
                $note = 'The artifact does not match a documented agent-evals shape, so it contributes no evidence.'

                if ($file.Length -gt $maxArtifactByte)
                {
                    $artifact.Add([pscustomobject] @{
                            RelativePath   = $relativePath
                            Kind           = 'Oversize'
                            Binding        = 'NotApplicable'
                            ProvenancePath = $null
                            RunId          = $null
                            Executed       = $false
                            CaseCount      = 0
                            PassedCount    = 0
                            FailedCount    = 0
                            TotalCount     = 0
                            AssertionCount = 0
                            AssertionState = 'NotApplicable'
                            CountsValid    = $false
                            Note           = "The artifact exceeds the $maxArtifactByte-byte read bound and was not opened."
                        })
                    continue
                }

                $document = $null
                try
                {
                    $document = $utf8.GetString([System.IO.File]::ReadAllBytes($file.FullName)) | ConvertFrom-Json
                }
                catch
                {
                    $document = $null
                }

                if ($null -eq $document -or $document -isnot [System.Management.Automation.PSCustomObject])
                {
                    $artifact.Add([pscustomobject] @{
                            RelativePath   = $relativePath
                            Kind           = 'Unreadable'
                            Binding        = 'NotApplicable'
                            ProvenancePath = $null
                            RunId          = $null
                            Executed       = $false
                            CaseCount      = 0
                            PassedCount    = 0
                            FailedCount    = 0
                            TotalCount     = 0
                            AssertionCount = 0
                            AssertionState = 'NotApplicable'
                            CountsValid    = $false
                            Note           = 'The artifact could not be read as a JSON object, so it contributes no evidence.'
                        })
                    continue
                }

                $property = @($document.PSObject.Properties.Name)

                if ('evals' -in $property -and $document.evals -is [System.Object[]])
                {
                    $kind = 'AuthoredCases'
                    $caseCount = @($document.evals).Count
                    $declaredSkill = if ('skill_name' -in $property -and $document.skill_name -is [string]) { $document.skill_name } else { $null }
                    if ($null -eq $declaredSkill)
                    {
                        $binding = 'Unbound'
                        $note = 'Authored cases with no skill_name, so the cases are visible but not bound to this Skill.'
                    }
                    elseif ($declaredSkill -ne $current.Name)
                    {
                        $binding = 'MismatchedSkill'
                        $note = 'The authored cases name a different Skill, so they are excluded from this Skill.'
                    }
                    else
                    {
                        $binding = 'Bound'
                        $note = 'Authored cases only. No run is recorded here, so no pass rate exists.'
                    }
                }
                elseif ('cases' -in $property -and $document.cases -is [System.Object[]])
                {
                    $kind = 'AuthoredCases'
                    $caseCount = @($document.cases).Count
                    $binding = 'Unbound'
                    $note = 'Authored harness cases. The bundled harness shape carries no Skill identity, so the cases are visible but unbound.'
                }
                elseif ('assertion_results' -in $property -or ('summary' -in $property -and $null -ne $document.summary))
                {
                    # A graded run is the assertion list; the summary is a claim
                    # about it. The claim counts only when it reconciles exactly
                    # with bounded Boolean verdicts, so a summary-only artifact, a
                    # contradicted verdict, and an ungraded case never become a
                    # pass. Assertion text and evidence are never read out.
                    $kind = 'Grading'
                    $note = 'A graded run arm.'
                    $assertionState = 'Missing'
                    $assertionPassed = 0
                    $assertionFailed = 0

                    if ('assertion_results' -in $property)
                    {
                        if ($document.assertion_results -is [System.Object[]])
                        {
                            $assertionEntry = @($document.assertion_results)
                            if ($assertionEntry.Count -gt $maxAssertionPerArtifact)
                            {
                                $assertionState = 'Oversize'
                            }
                            else
                            {
                                $assertionCount = $assertionEntry.Count
                                $assertionState = 'Valid'
                                foreach ($entry in $assertionEntry)
                                {
                                    if ($entry -isnot [System.Management.Automation.PSCustomObject] -or
                                        'passed' -notin @($entry.PSObject.Properties.Name) -or
                                        $entry.passed -isnot [bool])
                                    {
                                        $assertionState = 'Invalid'
                                        break
                                    }

                                    if ($entry.passed) { $assertionPassed++ } else { $assertionFailed++ }
                                }
                            }
                        }
                        else
                        {
                            $assertionState = 'Invalid'
                        }
                    }

                    if ($assertionState -eq 'Missing')
                    {
                        $note = 'The graded run records no assertion results, so its summary is a claim with nothing to reconcile against and proves nothing.'
                    }
                    elseif ($assertionState -eq 'Oversize')
                    {
                        $note = "The graded run records more than $maxAssertionPerArtifact assertions, which is the documented read bound, so it is shown and not counted."
                    }
                    elseif ($assertionState -eq 'Invalid')
                    {
                        $note = 'The graded run records an assertion without a Boolean verdict, so its results cannot be reconciled and prove nothing.'
                    }
                    elseif (-not ('summary' -in $property -and $document.summary -is [System.Management.Automation.PSCustomObject]))
                    {
                        $note = 'The graded run records no summary counts, so its quality evidence is inconclusive.'
                    }
                    else
                    {
                        $summaryProperty = @($document.summary.PSObject.Properties.Name)
                        $rawPassed = if ('passed' -in $summaryProperty) { $document.summary.passed } else { $null }
                        $rawFailed = if ('failed' -in $summaryProperty) { $document.summary.failed } else { $null }
                        $rawTotal = if ('total' -in $summaryProperty) { $document.summary.total } else { $null }

                        $numeric = ($rawPassed -is [int] -or $rawPassed -is [long]) -and
                            ($rawFailed -is [int] -or $rawFailed -is [long]) -and
                            ($rawTotal -is [int] -or $rawTotal -is [long])

                        # The range check runs before any narrowing conversion, so
                        # an oversized count is reported rather than thrown.
                        $inRange = $numeric -and
                            $rawPassed -ge 0 -and $rawPassed -le [int]::MaxValue -and
                            $rawFailed -ge 0 -and $rawFailed -le [int]::MaxValue -and
                            $rawTotal -ge 0 -and $rawTotal -le [int]::MaxValue

                        if (-not $numeric)
                        {
                            $note = 'The graded run records counts that are missing or non-numeric, so it proves nothing.'
                        }
                        elseif (-not $inRange)
                        {
                            $note = 'The graded run records counts that are negative or outside the supported range, so it proves nothing.'
                        }
                        elseif ([int] $rawPassed -ne $assertionPassed -or
                            [int] $rawFailed -ne $assertionFailed -or
                            [int] $rawTotal -ne $assertionCount -or
                            ([int] $rawPassed + [int] $rawFailed) -ne [int] $rawTotal)
                        {
                            $note = 'The graded run records a summary that does not reconcile with its assertion verdicts, so it proves nothing.'
                        }
                        else
                        {
                            $countsValid = $true
                            $artifactPassed = [int] $rawPassed
                            $artifactFailed = [int] $rawFailed
                            $artifactTotal = [int] $rawTotal
                            $executed = $true
                        }
                    }
                }
                elseif ('run_summary' -in $property)
                {
                    $kind = 'Benchmark'
                    $note = 'An aggregated benchmark. It records rates rather than per-case counts, so it never establishes a pass on its own.'
                }
                elseif ('total_tokens' -in $property -or 'duration_ms' -in $property)
                {
                    $kind = 'Timing'
                    $note = 'A timing artifact. It records cost, never quality.'
                }

                if ($kind -eq 'Grading' -or $kind -eq 'Benchmark')
                {
                    $provenancePath = Join-Path $evalRoot ([System.IO.Path]::GetFileNameWithoutExtension($file.Name) + '.provenance.json')
                    $provenance = $null
                    if (Test-Path -LiteralPath $provenancePath -PathType Leaf)
                    {
                        Assert-CopilotAtelierRegularPath -LiteralPath $provenancePath -RootPath $evalRoot -ErrorAction Stop
                        if ((Get-Item -LiteralPath $provenancePath -Force).Length -le $maxArtifactByte)
                        {
                            try
                            {
                                $provenance = $utf8.GetString([System.IO.File]::ReadAllBytes($provenancePath)) | ConvertFrom-Json
                            }
                            catch
                            {
                                $provenance = $null
                            }
                        }
                    }

                    $provenanceValid = $false
                    if ($provenance -is [System.Management.Automation.PSCustomObject])
                    {
                        $provenanceProperty = @($provenance.PSObject.Properties.Name)
                        $provenanceValid = @('schemaVersion', 'skillName', 'skillSha256', 'runId', 'completedUtc' | Where-Object -FilterScript { $_ -notin $provenanceProperty }).Count -eq 0 -and
                            ($provenance.schemaVersion -is [int] -or $provenance.schemaVersion -is [long]) -and $provenance.schemaVersion -eq 1 -and
                            $provenance.skillName -is [string] -and $skillNamePattern.IsMatch($provenance.skillName) -and
                            $provenance.skillSha256 -is [string] -and $sha256Pattern.IsMatch($provenance.skillSha256) -and
                            $provenance.runId -is [string] -and $provenance.runId.Length -gt 0 -and $provenance.runId.Length -le 128 -and $identifierPattern.IsMatch($provenance.runId)
                    }

                    # A completion instant is validated, not merely present: a run
                    # that claims no real instant, or one later than the instant
                    # the report is measured against, binds nothing.
                    $completionValid = $false
                    if ($provenanceValid)
                    {
                        $completedUtc = & $parseTimestamp $provenance.completedUtc
                        $completionValid = $null -ne $completedUtc -and $completedUtc -ge $earliestUtc -and $completedUtc -le $ReferenceUtc
                    }

                    if (-not $provenanceValid)
                    {
                        $binding = 'Unbound'
                        $note = 'The run output carries no valid provenance, so its identity is unknown and it cannot describe the current body. It is shown, never counted.'
                    }
                    elseif (-not $completionValid)
                    {
                        $binding = 'Unbound'
                        $note = 'The provenance records no plausible completion instant at or before the reference time, so the run is not bound to this body. It is shown, never counted.'
                    }
                    else
                    {
                        $provenanceRelativePath = "skills/$($current.Name)/evals/$([System.IO.Path]::GetFileName($provenancePath))"
                        $runId = $provenance.runId
                        if ($provenance.skillName -ne $current.Name)
                        {
                            $binding = 'MismatchedSkill'
                            $note = 'The provenance names a different Skill, so the run is excluded here.'
                        }
                        elseif ($provenance.skillSha256.ToLowerInvariant() -ne $current.Sha256)
                        {
                            $binding = 'DifferentBody'
                            $note = 'The run was produced against a different body of this Skill, so it is labelled and excluded from the current counts.'
                        }
                        else
                        {
                            $binding = 'Bound'
                        }
                    }
                }

                $artifact.Add([pscustomobject] @{
                        RelativePath   = $relativePath
                        Kind           = $kind
                        Binding        = $binding
                        ProvenancePath = $provenanceRelativePath
                        RunId          = $runId
                        Executed       = $executed
                        CaseCount      = $caseCount
                        PassedCount    = $artifactPassed
                        FailedCount    = $artifactFailed
                        TotalCount     = $artifactTotal
                        AssertionCount = $assertionCount
                        AssertionState = $assertionState
                        CountsValid    = $countsValid
                        Note           = $note
                    })
            }

            # A run identity is a quality identity, so only a graded result that
            # could be counted claims one. A benchmark arm sharing the identifier
            # never consumes it. Copies that agree count once; copies that
            # disagree are exposed and none of them counts, because choosing one
            # would mean choosing whichever filename sorted first.
            $countable = @($artifact | Where-Object -FilterScript { $_.Kind -eq 'Grading' -and $_.Binding -eq 'Bound' -and $_.CountsValid })
            foreach ($group in ($countable | Group-Object -Property RunId))
            {
                if ($group.Count -le 1)
                {
                    continue
                }

                $variant = @($group.Group | ForEach-Object -Process { '{0}|{1}|{2}' -f $_.PassedCount, $_.FailedCount, $_.TotalCount } | Sort-Object -Unique)
                if ($variant.Count -gt 1)
                {
                    foreach ($member in $group.Group)
                    {
                        $member.Binding = 'ConflictingRun'
                        $member.Note = 'Another graded result claims this run identifier and disagrees with it, so neither is counted.'
                    }

                    continue
                }

                foreach ($member in ($group.Group | Select-Object -Skip 1))
                {
                    $member.Binding = 'DuplicateRun'
                    $member.Note = 'A run with this identifier was already counted, so this copy is labelled and not counted again.'
                }
            }

            foreach ($record in $artifact)
            {
                if ($record.Binding -ne 'Bound')
                {
                    continue
                }

                if ($record.Kind -eq 'AuthoredCases')
                {
                    $authoredCaseCount += $record.CaseCount
                }
                elseif ($record.Kind -eq 'Grading' -and $record.CountsValid)
                {
                    $executedRunCount++
                    $passedCount += $record.PassedCount
                    $failedCount += $record.FailedCount
                }
            }
        }

        $resultArtifact = @($artifact | Where-Object -FilterScript { $_.Kind -eq 'Grading' -or $_.Kind -eq 'Benchmark' })
        $evaluationState = if ($artifact.Count -eq 0) { 'None' }
        elseif ($executedRunCount -gt 0) { 'Executed' }
        elseif ($resultArtifact.Count -gt 0) { 'UnboundResults' }
        else { 'AuthoredOnly' }

        $evaluation = [pscustomobject] @{
            State             = $evaluationState
            Artifact          = $artifact.ToArray()
            AuthoredCaseCount = $authoredCaseCount
            ExecutedRunCount  = $executedRunCount
            PassedCount       = $passedCount
            FailedCount       = $failedCount
            Note              = 'Evaluation evidence is read from the existing agent-evals artifacts. Authored cases are not a run, a load or a read is never a passed case, and run output only describes the current body when a validated provenance sidecar binds it to this Skill name and this body hash. A graded run counts only when its summary reconciles exactly with its bounded Boolean assertion verdicts.'
        }

        $qualityState = if ($executedRunCount -eq 0) { 'Unmeasured' }
        elseif ($failedCount -gt 0) { 'Failing' }
        elseif ($passedCount -gt 0) { 'Passing' }
        else { 'Inconclusive' }

        $quality = [pscustomobject] @{
            State       = $qualityState
            PassedCount = $passedCount
            FailedCount = $failedCount
            Note        = 'Quality is claimed only from an executed evaluation that recorded per-case results.'
        }

        $observationAgeDay = $null
        $observationState = 'Unknown'
        if ($null -ne $lastObservationUtc)
        {
            $observationAgeDay = [int] [System.Math]::Round(($ReferenceUtc - $lastObservationUtc).TotalDays)
            $observationState = if ($observationAgeDay -gt $staleObservationDay) { 'Stale' } else { 'Fresh' }
        }

        $freshness = [pscustomobject] @{
            ContentLastWriteUtc = $current.LastWriteUtc
            ContentAgeDay       = [int] [System.Math]::Round(($ReferenceUtc - $current.LastWriteUtc).TotalDays)
            ObservationAgeDay   = $observationAgeDay
            ObservationState    = $observationState
            StaleHorizonDay     = $staleObservationDay
        }

        $partner = @(
            foreach ($other in $inventory)
            {
                if ($other.Name -eq $current.Name)
                {
                    continue
                }
                $shared = @($current.Term | Where-Object -FilterScript { $other.Term.Contains($_) } | Sort-Object)
                if ($shared.Count -ge $overlapTermThreshold)
                {
                    [pscustomobject] @{
                        Name            = $other.Name
                        SharedTermCount = $shared.Count
                        SharedTerm      = $shared
                    }
                }
            }
        )

        $overlap = [pscustomobject] @{
            PartnerCount  = $partner.Count
            Partner       = $partner
            TermThreshold = $overlapTermThreshold
            Note          = 'Overlap is a lexical comparison of the discovery descriptions. It flags candidates for a human comparison, not proven duplication.'
        }

        $structure = [pscustomobject] @{
            FrontmatterFenceFound = $current.FrontmatterFence
            MetadataParseState    = $current.MetadataParseState
            FrontmatterParsed     = ($current.MetadataParseState -eq 'Parsed')
            NameMatchesFolder     = ($current.DeclaredName -eq $current.Name)
            DescriptionLength     = $current.DescriptionLength
            DescriptionOverCap    = ($current.DescriptionLength -gt $descriptionCap)
            DescriptionCap        = $descriptionCap
            BodyLineCount         = $current.BodyLineCount
            BodyOverBudget        = ($current.BodyLineCount -gt $bodyLineBudget)
            BodyLineBudget        = $bodyLineBudget
            Note                  = 'A matching frontmatter fence is not proof of valid metadata. The block is reported as parsed only when every line is a supported top-level key and both the name and the description resolved to a scalar.'
        }

        $skill.Add([pscustomobject] @{
                Name            = $current.Name
                Sha256          = $current.Sha256
                RelativePath    = $current.RelativePath
                Mandatory       = ($current.Name -in $mandatorySkill)
                Usage           = $usage
                Evaluation      = $evaluation
                Quality         = $quality
                Discoverability = $discoverability
                Freshness       = $freshness
                Overlap         = $overlap
                Structure       = $structure
            })
    }

    # --- Suggestions ---------------------------------------------------------
    $suggestion = [System.Collections.Generic.List[object]]::new()

    foreach ($current in $skill)
    {
        if ($current.Structure.DescriptionOverCap)
        {
            $suggestion.Add([pscustomobject] @{
                    Skill    = $current.Name
                    Kind     = 'Improve'
                    Severity = 'Warning'
                    Reason   = "The discovery description is $($current.Structure.DescriptionLength) characters, over the $descriptionCap-character cap."
                    Evidence = @($current.RelativePath)
                    Decision = 'HumanReviewRequired'
                })
        }

        if ($current.Structure.BodyOverBudget)
        {
            $suggestion.Add([pscustomobject] @{
                    Skill    = $current.Name
                    Kind     = 'Improve'
                    Severity = 'Information'
                    Reason   = "The body is $($current.Structure.BodyLineCount) lines, over the $bodyLineBudget-line budget."
                    Evidence = @($current.RelativePath)
                    Decision = 'HumanReviewRequired'
                })
        }

        if (-not $current.Structure.FrontmatterParsed -or -not $current.Structure.NameMatchesFolder)
        {
            $suggestion.Add([pscustomobject] @{
                    Skill    = $current.Name
                    Kind     = 'Investigate'
                    Severity = 'Warning'
                    Reason   = "The metadata block is reported as '$($current.Structure.MetadataParseState)' or the declared name does not match the folder."
                    Evidence = @($current.RelativePath)
                    Decision = 'HumanReviewRequired'
                })
        }

        $unboundResult = @($current.Evaluation.Artifact | Where-Object -FilterScript { ($_.Kind -eq 'Grading' -or $_.Kind -eq 'Benchmark') -and $_.Binding -eq 'Unbound' })
        if ($unboundResult.Count -gt 0)
        {
            $suggestion.Add([pscustomobject] @{
                    Skill    = $current.Name
                    Kind     = 'Investigate'
                    Severity = 'Information'
                    Reason   = "$($unboundResult.Count) evaluation result artifacts carry no validated identity, so their results cannot describe the current body. Add a provenance sidecar naming the Skill and its body hash, or treat them as historical."
                    Evidence = @($unboundResult | ForEach-Object -Process { $_.RelativePath })
                    Decision = 'HumanReviewRequired'
                })
        }

        $conflictingResult = @($current.Evaluation.Artifact | Where-Object -FilterScript { $_.Binding -eq 'ConflictingRun' })
        if ($conflictingResult.Count -gt 0)
        {
            $suggestion.Add([pscustomobject] @{
                    Skill    = $current.Name
                    Kind     = 'Investigate'
                    Severity = 'Warning'
                    Reason   = "$($conflictingResult.Count) graded results claim the same run identifier and disagree about it, so none of them is counted. Resolve the disagreement or give each run its own identifier."
                    Evidence = @($conflictingResult | ForEach-Object -Process { $_.RelativePath })
                    Decision = 'HumanReviewRequired'
                })
        }

        $otherBodyResult = @($current.Evaluation.Artifact | Where-Object -FilterScript { $_.Binding -eq 'DifferentBody' })
        if ($otherBodyResult.Count -gt 0)
        {
            $suggestion.Add([pscustomobject] @{
                    Skill    = $current.Name
                    Kind     = 'Investigate'
                    Severity = 'Information'
                    Reason   = "$($otherBodyResult.Count) evaluation results were produced against a different body of this Skill, so they are labelled and excluded from the current counts."
                    Evidence = @($otherBodyResult | ForEach-Object -Process { $_.RelativePath })
                    Decision = 'HumanReviewRequired'
                })
        }

        if ($current.Quality.State -eq 'Failing')
        {
            $suggestion.Add([pscustomobject] @{
                    Skill    = $current.Name
                    Kind     = 'Investigate'
                    Severity = 'Warning'
                    Reason   = "An executed evaluation recorded $($current.Quality.FailedCount) failed cases."
                    Evidence = @($current.Evaluation.Artifact | Where-Object -FilterScript { $_.Executed } | ForEach-Object -Process { $_.RelativePath })
                    Decision = 'HumanReviewRequired'
                })
        }

        if ($current.Discoverability.TriggerQuerySet -eq 'Absent')
        {
            $suggestion.Add([pscustomobject] @{
                    Skill    = $current.Name
                    Kind     = 'Investigate'
                    Severity = 'Information'
                    Reason   = 'No trigger-query set exists, so discovery for this Skill is unmeasured.'
                    Evidence = @($current.RelativePath)
                    Decision = 'HumanReviewRequired'
                })
        }

        if ($current.Overlap.PartnerCount -gt 0)
        {
            $suggestion.Add([pscustomobject] @{
                    Skill    = $current.Name
                    Kind     = 'Consolidate'
                    Severity = 'Information'
                    Reason   = "The description shares $($current.Overlap.Partner[0].SharedTermCount) or more distinctive terms with $(@($current.Overlap.Partner | ForEach-Object -Process { $_.Name }) -join ', ')."
                    Evidence = @(@($current.RelativePath) + @($current.Overlap.Partner | ForEach-Object -Process { "skills/$($_.Name)/SKILL.md" }))
                    Decision = 'HumanReviewRequired'
                })
        }

        if ($current.Usage.BodyVersionMismatch)
        {
            $suggestion.Add([pscustomobject] @{
                    Skill    = $current.Name
                    Kind     = 'Investigate'
                    Severity = 'Information'
                    Reason   = "$($current.Usage.OtherBodyRecordCount) imported records name a different body of this Skill, so their evidence is not merged into the current one."
                    Evidence = @($current.RelativePath)
                    Decision = 'HumanReviewRequired'
                })
        }

        # Retirement is never inferred from silence. A global window says nothing
        # about a Skill that has no records in it, and a file read is evidence of
        # a read rather than of complete activation capture. The only evidence
        # that turns an absent record into an absent use is an explicit,
        # validated coverage declaration for this Skill, this body, and a window
        # wide enough and recent enough to judge.
        if (-not $current.Mandatory -and $current.Usage.CoverageDeclared -and $current.Usage.ActivationCount -eq 0)
        {
            $claim = @($current.Usage.CoverageDeclaration)[0]
            $suggestion.Add([pscustomobject] @{
                    Skill    = $current.Name
                    Kind     = 'RetirementReview'
                    Severity = 'Information'
                    Reason   = "An import declares complete activation capture for this body across $([int] [System.Math]::Round(($claim.WindowEndUtc - $claim.WindowStartUtc).TotalDays)) days and $($claim.SessionCount) sessions, and recorded no activation. This is a prompt for a human decision, not a retirement."
                    Evidence = @(
                        $current.RelativePath
                        $claim.SourcePath
                        "declared window $($claim.WindowStartUtc.ToString('yyyy-MM-dd')) to $($claim.WindowEndUtc.ToString('yyyy-MM-dd'))"
                    )
                    Decision = 'HumanReviewRequired'
                })
        }
    }

    $summary = [pscustomobject] @{
        SkillCount                = $skill.Count
        ObservedSkillCount        = @($skill | Where-Object -FilterScript { $_.Usage.Coverage -eq 'Observed' }).Count
        UnknownUsageSkillCount    = @($skill | Where-Object -FilterScript { $_.Usage.Coverage -eq 'NoObservations' }).Count
        DeclaredCoverageCount     = @($skill | Where-Object -FilterScript { $_.Usage.CoverageDeclared }).Count
        AuthoredEvaluationCount   = @($skill | Where-Object -FilterScript { $_.Evaluation.State -eq 'AuthoredOnly' }).Count
        UnboundEvaluationCount    = @($skill | Where-Object -FilterScript { $_.Evaluation.State -eq 'UnboundResults' }).Count
        ExecutedEvaluationCount   = @($skill | Where-Object -FilterScript { $_.Evaluation.State -eq 'Executed' }).Count
        FailingQualityCount       = @($skill | Where-Object -FilterScript { $_.Quality.State -eq 'Failing' }).Count
        UnmeasuredDiscoveryCount  = @($skill | Where-Object -FilterScript { $_.Discoverability.TriggerQuerySet -eq 'Absent' }).Count
        OverlapSkillCount         = @($skill | Where-Object -FilterScript { $_.Overlap.PartnerCount -gt 0 }).Count
        SuggestionCount           = $suggestion.Count
    }

    return [pscustomobject] @{
        ContentPath  = $contentRootFull
        ReferenceUtc = $ReferenceUtc
        Telemetry    = $telemetry
        Observation  = $observationSummary
        Skill        = $skill.ToArray()
        Suggestion   = $suggestion.ToArray()
        Summary      = $summary
        Disclaimer   = 'Usage, discoverability, evaluation, quality, freshness, and overlap are separate facets and are never combined into a single health score. Missing evidence means unknown, never zero use. This report is read-only: it never edits, removes, retires, or reconfigures a Skill, a setting, or an installation.'
    }
}
