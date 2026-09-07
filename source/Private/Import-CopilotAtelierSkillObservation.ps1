function Import-CopilotAtelierSkillObservation
{
    <#
        .SYNOPSIS
            Imports explicitly selected Skill observation records and validates
            them against a closed metadata schema.

        .DESCRIPTION
            Reads observation import files from paths the caller selected
            explicitly, validates every document and every record against an
            allow-listed schema with bounded sizes, and returns the accepted
            records together with the rejections and the conflicts.

            Every accepted record keeps its provenance: the local import file it
            came from, the declaring client and client version, and the identity
            scope its event identifier is unique within. An event identifier is
            local to a client and a session, so the scope is the client, the
            client version, the session, and the event identifier together, and
            the same local identifier from two clients does not collide.

            Exact copies of one record deduplicate onto a single accepted record.
            Records that share an identity scope but disagree on their payload
            are a conflict: none of them is accepted, because accepting one would
            mean accepting whichever file happened to be read first. The conflict
            is reported with the import locator of every variant instead.

            The schema carries identifiers, times, content identity, and explicit
            outcomes only. Prompt text, Skill bodies, tool responses, credentials,
            and free-form notes are not part of the schema, so a document that
            carries them is refused rather than partially accepted. A rejection
            reason names the field and the rule, never the offending value, so the
            report can never echo imported content back to the caller.

            A document may also declare coverage: an explicit, per Skill and per
            body claim that activation capture was complete over a stated window.
            Nothing else can establish that an absent record means an absent use,
            so a validated coverage declaration is the only evidence under which
            the report will raise a retirement review for a human.

            The function reads files only. It never writes, never follows a
            reparse point, and never enumerates outside the selected paths.

        .PARAMETER Path
            One or more explicitly selected files or directories holding
            observation import documents. A directory contributes its JSON files.

        .PARAMETER ReferenceUtc
            The UTC instant the import is validated against. A record stamped
            after this instant is rejected as implausible.

        .OUTPUTS
            System.Management.Automation.PSCustomObject

        .EXAMPLE
            Import-CopilotAtelierSkillObservation -Path $importDirectory -ReferenceUtc ([datetime]::UtcNow)

            Returns the accepted records and the rejections for one import directory.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String[]]
        $Path,

        [Parameter(Mandatory = $true)]
        [System.DateTime]
        $ReferenceUtc
    )

    $ErrorActionPreference = 'Stop'

    # Documented bounds. They exist so a malformed or hostile import cannot
    # exhaust memory or smuggle a payload through an unbounded field.
    $maxFileByte = 1048576
    $maxFilePerRun = 200
    $maxRecordPerFile = 2000
    $maxCoveragePerFile = 200
    $maxEventIdLength = 128
    $maxSessionIdLength = 128
    $maxSkillNameLength = 64
    $maxClientLength = 64
    $maxClientVersionLength = 32
    $maxSessionCount = 1000000

    $supportedSchemaVersion = 1
    $supportedDocumentProperty = @('schemaVersion', 'client', 'clientVersion', 'trust', 'records', 'coverage')
    $supportedRecordProperty = @('eventId', 'eventType', 'skillName', 'skillSha256', 'timestampUtc', 'sessionId', 'outcome')
    $supportedCoverageProperty = @('skillName', 'skillSha256', 'windowStartUtc', 'windowEndUtc', 'sessionCount', 'activationCaptureComplete')
    $supportedEventType = @('SkillFileRead', 'SkillActivation', 'SkillToolExecution')
    $supportedOutcome = @('Success', 'Failure', 'Unknown')
    $supportedTrust = @('Observed', 'Imported')

    $skillNamePattern = [regex]::new('^[a-z0-9]+(-[a-z0-9]+)*$')
    $sha256Pattern = [regex]::new('^[0-9a-fA-F]{64}$')
    $identifierPattern = [regex]::new('^[\x20-\x7E]+$')
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

    $file = @(Get-CopilotAtelierBoundedFile -Path $Path -Extension '.json' -MaxFileCount $maxFilePerRun -Subject 'Skill observation' -ErrorAction Stop)

    $candidateRecord = [System.Collections.Generic.List[object]]::new()
    $rejectedFile = [System.Collections.Generic.List[object]]::new()
    $rejectedRecord = [System.Collections.Generic.List[object]]::new()
    $rejectedCoverage = [System.Collections.Generic.List[object]]::new()
    $coverage = [System.Collections.Generic.List[object]]::new()
    $declaredTrust = [System.Collections.Generic.List[string]]::new()

    foreach ($current in $file)
    {
        if ($current.Length -gt $maxFileByte)
        {
            $rejectedFile.Add([pscustomobject] @{
                    Path   = $current.FullName
                    Reason = "The file exceeds the $maxFileByte-byte observation import size bound."
                })
            continue
        }

        $document = $null
        try
        {
            $document = [System.IO.File]::ReadAllText($current.FullName) | ConvertFrom-Json
        }
        catch
        {
            # The parser message can quote the offending text, so it is discarded.
            $rejectedFile.Add([pscustomobject] @{
                    Path   = $current.FullName
                    Reason = 'The file is not a valid JSON document.'
                })
            continue
        }

        if ($null -eq $document -or $document -isnot [System.Management.Automation.PSCustomObject])
        {
            $rejectedFile.Add([pscustomobject] @{
                    Path   = $current.FullName
                    Reason = 'The file does not hold an observation document object.'
                })
            continue
        }

        $documentProperty = @($document.PSObject.Properties.Name)
        if (@($documentProperty | Where-Object -FilterScript { $_ -notin $supportedDocumentProperty }).Count -gt 0)
        {
            $rejectedFile.Add([pscustomobject] @{
                    Path   = $current.FullName
                    Reason = 'The document declares an unsupported top-level property.'
                })
            continue
        }

        $declaredSchemaVersion = if ('schemaVersion' -in $documentProperty) { $document.schemaVersion } else { $null }
        if ($declaredSchemaVersion -isnot [int] -and $declaredSchemaVersion -isnot [long])
        {
            $declaredSchemaVersion = $null
        }

        if ($null -eq $declaredSchemaVersion -or $declaredSchemaVersion -ne $supportedSchemaVersion)
        {
            $rejectedFile.Add([pscustomobject] @{
                    Path   = $current.FullName
                    Reason = "The document declares an unsupported schema version; only version $supportedSchemaVersion is read."
                })
            continue
        }

        $documentClient = if ('client' -in $documentProperty) { $document.client } else { $null }
        $documentClientVersion = if ('clientVersion' -in $documentProperty) { $document.clientVersion } else { $null }
        $documentTrust = if ('trust' -in $documentProperty) { $document.trust } else { 'Imported' }

        if ($documentClient -isnot [string] -or $documentClient.Length -eq 0 -or $documentClient.Length -gt $maxClientLength -or -not $identifierPattern.IsMatch($documentClient))
        {
            $rejectedFile.Add([pscustomobject] @{
                    Path   = $current.FullName
                    Reason = 'The document does not declare a bounded printable client identifier.'
                })
            continue
        }

        if ($documentClientVersion -isnot [string] -or $documentClientVersion.Length -eq 0 -or $documentClientVersion.Length -gt $maxClientVersionLength -or -not $identifierPattern.IsMatch($documentClientVersion))
        {
            $rejectedFile.Add([pscustomobject] @{
                    Path   = $current.FullName
                    Reason = 'The document does not declare a bounded printable client version.'
                })
            continue
        }

        if ($documentTrust -isnot [string] -or $documentTrust -notin $supportedTrust)
        {
            $rejectedFile.Add([pscustomobject] @{
                    Path   = $current.FullName
                    Reason = 'The document declares an unsupported trust label.'
                })
            continue
        }

        if ('records' -notin $documentProperty -or $null -eq $document.records)
        {
            $rejectedFile.Add([pscustomobject] @{
                    Path   = $current.FullName
                    Reason = 'The document does not declare a records collection.'
                })
            continue
        }

        if ($document.records -isnot [System.Object[]])
        {
            # A scalar or a bare object would be silently wrapped into a
            # one-element array, so the shape is required rather than coerced.
            $rejectedFile.Add([pscustomobject] @{
                    Path   = $current.FullName
                    Reason = 'The document does not declare its records as an array.'
                })
            continue
        }

        $documentRecord = @($document.records)
        if ($documentRecord.Count -gt $maxRecordPerFile)
        {
            $rejectedFile.Add([pscustomobject] @{
                    Path   = $current.FullName
                    Reason = "The document declares more than $maxRecordPerFile records, which is the documented import bound."
                })
            continue
        }

        $documentCoverage = @()
        if ('coverage' -in $documentProperty -and $null -ne $document.coverage)
        {
            if ($document.coverage -isnot [System.Object[]])
            {
                $rejectedFile.Add([pscustomobject] @{
                        Path   = $current.FullName
                        Reason = 'The document does not declare its coverage as an array.'
                    })
                continue
            }

            $documentCoverage = @($document.coverage)
            if ($documentCoverage.Count -gt $maxCoveragePerFile)
            {
                $rejectedFile.Add([pscustomobject] @{
                        Path   = $current.FullName
                        Reason = "The document declares more than $maxCoveragePerFile coverage declarations, which is the documented import bound."
                    })
                continue
            }
        }

        if (-not $declaredTrust.Contains($documentTrust))
        {
            $declaredTrust.Add($documentTrust)
        }

        for ($index = 0; $index -lt $documentRecord.Count; $index++)
        {
            $candidate = $documentRecord[$index]
            $reject = {
                param ($Field, $Reason)

                $rejectedRecord.Add([pscustomobject] @{
                        Path   = $current.FullName
                        Index  = $index
                        Field  = $Field
                        Reason = $Reason
                    })
            }

            if ($null -eq $candidate -or $candidate -isnot [System.Management.Automation.PSCustomObject])
            {
                & $reject 'record' 'The record is not an object.'
                continue
            }

            $candidateProperty = @($candidate.PSObject.Properties.Name)
            if (@($candidateProperty | Where-Object -FilterScript { $_ -notin $supportedRecordProperty }).Count -gt 0)
            {
                & $reject 'record' 'The record declares an unsupported property.'
                continue
            }

            $missing = @($supportedRecordProperty | Where-Object -FilterScript { $_ -notin $candidateProperty -and $_ -ne 'outcome' })
            if ($missing.Count -gt 0)
            {
                & $reject $missing[0] 'The record omits a required field.'
                continue
            }

            $eventId = $candidate.eventId
            if ($eventId -isnot [string] -or $eventId.Length -eq 0 -or $eventId.Length -gt $maxEventIdLength -or -not $identifierPattern.IsMatch($eventId))
            {
                & $reject 'eventId' "The event identifier must be printable text of at most $maxEventIdLength characters."
                continue
            }

            $eventType = $candidate.eventType
            if ($eventType -isnot [string] -or $eventType -notin $supportedEventType)
            {
                & $reject 'eventType' 'The event type is not a supported observation event type.'
                continue
            }

            $skillName = $candidate.skillName
            if ($skillName -isnot [string] -or $skillName.Length -eq 0 -or $skillName.Length -gt $maxSkillNameLength -or -not $skillNamePattern.IsMatch($skillName))
            {
                & $reject 'skillName' 'The Skill name is not a valid Skill identifier.'
                continue
            }

            $skillSha256 = $candidate.skillSha256
            if ($skillSha256 -isnot [string] -or -not $sha256Pattern.IsMatch($skillSha256))
            {
                & $reject 'skillSha256' 'The content identity must be a 64-character SHA-256 hexadecimal digest.'
                continue
            }

            $timestampUtc = & $parseTimestamp $candidate.timestampUtc
            if ($null -eq $timestampUtc)
            {
                & $reject 'timestampUtc' 'The timestamp must be an ISO 8601 instant in UTC.'
                continue
            }

            if ($timestampUtc -gt $ReferenceUtc -or $timestampUtc -lt $earliestUtc)
            {
                & $reject 'timestampUtc' 'The timestamp is outside the plausible observation range.'
                continue
            }

            $sessionId = $candidate.sessionId
            if ($sessionId -isnot [string] -or $sessionId.Length -eq 0 -or $sessionId.Length -gt $maxSessionIdLength -or -not $identifierPattern.IsMatch($sessionId))
            {
                & $reject 'sessionId' "The session identifier must be printable text of at most $maxSessionIdLength characters."
                continue
            }

            $outcome = if ('outcome' -in $candidateProperty) { $candidate.outcome } else { 'Unknown' }
            if ($outcome -isnot [string] -or $outcome -notin $supportedOutcome)
            {
                & $reject 'outcome' 'The outcome is not a supported outcome label.'
                continue
            }

            # An event identifier is only unique inside the client and session
            # that minted it, so the identity scope carries all four parts.
            $identityScope = "$documentClient|$documentClientVersion|$sessionId|$eventId"
            $normalizedSha = $skillSha256.ToLowerInvariant()
            $normalizedStamp = $timestampUtc.ToString('o')

            $candidateRecord.Add([pscustomobject] @{
                    IdentityScope = $identityScope
                    Fingerprint   = "$eventType|$skillName|$normalizedSha|$normalizedStamp|$outcome"
                    SourcePath    = $current.FullName
                    Index         = $index
                    Client        = $documentClient
                    ClientVersion = $documentClientVersion
                    SessionId     = $sessionId
                    EventId       = $eventId
                    Record        = [pscustomobject] [ordered] @{
                        EventId       = $eventId
                        EventType     = $eventType
                        SkillName     = $skillName
                        SkillSha256   = $normalizedSha
                        TimestampUtc  = $timestampUtc
                        SessionId     = $sessionId
                        Outcome       = $outcome
                        Client        = $documentClient
                        ClientVersion = $documentClientVersion
                        IdentityScope = $identityScope
                        SourcePath    = $current.FullName
                    }
                })
        }

        for ($index = 0; $index -lt $documentCoverage.Count; $index++)
        {
            $claim = $documentCoverage[$index]
            $rejectClaim = {
                param ($Field, $Reason)

                $rejectedCoverage.Add([pscustomobject] @{
                        Path   = $current.FullName
                        Index  = $index
                        Field  = $Field
                        Reason = $Reason
                    })
            }

            if ($null -eq $claim -or $claim -isnot [System.Management.Automation.PSCustomObject])
            {
                & $rejectClaim 'coverage' 'The coverage declaration is not an object.'
                continue
            }

            $claimProperty = @($claim.PSObject.Properties.Name)
            if (@($claimProperty | Where-Object -FilterScript { $_ -notin $supportedCoverageProperty }).Count -gt 0)
            {
                & $rejectClaim 'coverage' 'The coverage declaration declares an unsupported property.'
                continue
            }

            $missingClaim = @($supportedCoverageProperty | Where-Object -FilterScript { $_ -notin $claimProperty })
            if ($missingClaim.Count -gt 0)
            {
                & $rejectClaim $missingClaim[0] 'The coverage declaration omits a required field.'
                continue
            }

            if ($claim.skillName -isnot [string] -or $claim.skillName.Length -eq 0 -or $claim.skillName.Length -gt $maxSkillNameLength -or -not $skillNamePattern.IsMatch($claim.skillName))
            {
                & $rejectClaim 'skillName' 'The Skill name is not a valid Skill identifier.'
                continue
            }

            if ($claim.skillSha256 -isnot [string] -or -not $sha256Pattern.IsMatch($claim.skillSha256))
            {
                & $rejectClaim 'skillSha256' 'The content identity must be a 64-character SHA-256 hexadecimal digest.'
                continue
            }

            $windowStartUtc = & $parseTimestamp $claim.windowStartUtc
            if ($null -eq $windowStartUtc)
            {
                & $rejectClaim 'windowStartUtc' 'The window start must be an ISO 8601 instant in UTC.'
                continue
            }

            $windowEndUtc = & $parseTimestamp $claim.windowEndUtc
            if ($null -eq $windowEndUtc)
            {
                & $rejectClaim 'windowEndUtc' 'The window end must be an ISO 8601 instant in UTC.'
                continue
            }

            if ($windowStartUtc -lt $earliestUtc -or $windowEndUtc -gt $ReferenceUtc -or $windowEndUtc -lt $windowStartUtc)
            {
                & $rejectClaim 'windowEndUtc' 'The declared window is outside the plausible observation range.'
                continue
            }

            if (($claim.sessionCount -isnot [int] -and $claim.sessionCount -isnot [long]) -or $claim.sessionCount -lt 0 -or $claim.sessionCount -gt $maxSessionCount)
            {
                & $rejectClaim 'sessionCount' "The session count must be a whole number between 0 and $maxSessionCount."
                continue
            }

            if ($claim.activationCaptureComplete -isnot [bool])
            {
                & $rejectClaim 'activationCaptureComplete' 'The activation capture claim must be a boolean.'
                continue
            }

            $coverage.Add([pscustomobject] [ordered] @{
                    SkillName                 = $claim.skillName
                    SkillSha256               = $claim.skillSha256.ToLowerInvariant()
                    WindowStartUtc            = $windowStartUtc
                    WindowEndUtc              = $windowEndUtc
                    SessionCount              = [int] $claim.sessionCount
                    ActivationCaptureComplete = [bool] $claim.activationCaptureComplete
                    Client                    = $documentClient
                    ClientVersion             = $documentClientVersion
                    SourcePath                = $current.FullName
                })
        }
    }

    $record = [System.Collections.Generic.List[object]]::new()
    $conflictingRecord = [System.Collections.Generic.List[object]]::new()
    $duplicateCount = 0

    foreach ($scope in $candidateRecord | Group-Object -Property IdentityScope | Sort-Object -Property Name)
    {
        # The order the files happened to be read must not decide anything, so
        # the group is ordered by its own import locator before it is judged.
        $ordered = @($scope.Group | Sort-Object -Property SourcePath, Index)
        $variant = @($ordered | Group-Object -Property Fingerprint)

        if ($variant.Count -eq 1)
        {
            $duplicateCount += ($ordered.Count - 1)
            $record.Add($ordered[0].Record)
            continue
        }

        $conflictingRecord.Add([pscustomobject] @{
                IdentityScope = $scope.Name
                Client        = $ordered[0].Client
                ClientVersion = $ordered[0].ClientVersion
                SessionId     = $ordered[0].SessionId
                EventId       = $ordered[0].EventId
                VariantCount  = $variant.Count
                Source        = @($ordered | ForEach-Object -Process { [pscustomobject] @{ Path = $_.SourcePath; Index = $_.Index } })
                Reason        = 'Records share one identity scope but disagree, so none of them is accepted.'
            })
    }

    $accepted = @($record | Sort-Object -Property SkillName, TimestampUtc, IdentityScope)

    $client = @(
        foreach ($group in $accepted | Group-Object -Property Client, ClientVersion | Sort-Object -Property Name)
        {
            [pscustomobject] @{
                Name        = $group.Group[0].Client
                Version     = $group.Group[0].ClientVersion
                RecordCount = $group.Count
            }
        }
    )

    return [pscustomobject] @{
        FileCount         = $file.Count
        Record            = $accepted
        RejectedFile      = $rejectedFile.ToArray()
        RejectedRecord    = $rejectedRecord.ToArray()
        ConflictingRecord = $conflictingRecord.ToArray()
        DuplicateCount    = $duplicateCount
        ConflictCount     = $conflictingRecord.Count
        Client            = $client
        DeclaredTrust     = $declaredTrust.ToArray()
        Coverage          = $coverage.ToArray()
        RejectedCoverage  = $rejectedCoverage.ToArray()
        SourceFile        = @($file | ForEach-Object -Process { $_.FullName })
    }
}
