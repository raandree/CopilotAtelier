<#
    Writers of the contributor-profile Skill. Decision record 0028.

    Builds every writer on ContributorProfileReader.ps1: Set, Export, Import,
    Remove, the diagnosis report, and the registration file with its two-phase
    record. Every write takes the profile lock, writes a temporary file, and
    replaces the target atomically; nothing is ever written under a git working
    tree. The entry script ContributorProfile.ps1 and the module commands call
    these functions; nothing else implements them.

    Keep this file ASCII, as the reader.
#>

. (Join-Path -Path $PSScriptRoot -ChildPath 'ContributorProfileReader.ps1')

function Get-ContributorUtcNow
{
    [CmdletBinding()]
    [OutputType([System.String])]
    param ()

    return [System.DateTime]::UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [System.Globalization.CultureInfo]::InvariantCulture)
}

function ConvertTo-ContributorJsonString
{
    <#
        A JSON string literal: quotes, backslashes, and control characters are
        escaped; every other character is written as itself.
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [System.String]
        $Value
    )

    $builder = [System.Text.StringBuilder]::new($Value.Length + 2)
    $null = $builder.Append([char]34)
    foreach ($character in $Value.ToCharArray())
    {
        $code = [int] $character
        if ($code -eq 34 -or $code -eq 92)
        {
            $null = $builder.Append([char]92).Append($character)
        }
        elseif ($code -lt 32)
        {
            $null = $builder.Append(('\u{0:x4}' -f $code))
        }
        else
        {
            $null = $builder.Append($character)
        }
    }

    $null = $builder.Append([char]34)
    return $builder.ToString()
}

function ConvertTo-ContributorProfileJson
{
    <#
        Serializes a profile model as schema 1 in a fixed property order with
        two-space indentation, identically in every PowerShell edition.
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Object]
        $ContributorProfile
    )

    $q = { param ($text) ConvertTo-ContributorJsonString -Value $text }
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('{')
    $lines.Add('  "schemaVersion": 1,')
    $lines.Add('  "contributors": [')

    $entries = @($ContributorProfile.Contributors)
    for ($index = 0; $index -lt $entries.Count; $index++)
    {
        $entry = $entries[$index]
        $snooze = if ($entry.InterviewSnoozedUntilUtc) { & $q $entry.InterviewSnoozedUntilUtc } else { 'null' }
        $lines.Add('    {')
        $lines.Add('      "id": ' + (& $q $entry.Id) + ',')
        $lines.Add('      "default": ' + $(if ($entry.Default) { 'true' } else { 'false' }) + ',')
        $lines.Add('      "state": ' + (& $q $entry.State) + ',')
        $lines.Add('      "stateUpdatedUtc": ' + (& $q $entry.StateUpdatedUtc) + ',')
        $lines.Add('      "interviewSnoozedUntilUtc": ' + $snooze + ',')

        $aliases = @($entry.Aliases)
        if ($aliases.Count -eq 0)
        {
            $lines.Add('      "aliases": [],')
        }
        else
        {
            $lines.Add('      "aliases": [')
            for ($aliasIndex = 0; $aliasIndex -lt $aliases.Count; $aliasIndex++)
            {
                $separator = if ($aliasIndex -lt $aliases.Count - 1) { ',' } else { '' }
                $lines.Add('        ' + (& $q $aliases[$aliasIndex]) + $separator)
            }

            $lines.Add('      ],')
        }

        $areas = @($entry.Areas.Values)
        if ($areas.Count -eq 0)
        {
            $lines.Add('      "areas": {}')
        }
        else
        {
            $lines.Add('      "areas": {')
            for ($areaIndex = 0; $areaIndex -lt $areas.Count; $areaIndex++)
            {
                $area = $areas[$areaIndex]
                $separator = if ($areaIndex -lt $areas.Count - 1) { ',' } else { '' }
                $lines.Add('        ' + (& $q $area.Name) + ': {')
                $lines.Add('          "level": ' + (& $q $area.Level) + ',')
                $lines.Add('          "updatedUtc": ' + (& $q $area.UpdatedUtc))
                $lines.Add('        }' + $separator)
            }

            $lines.Add('      }')
        }

        $lines.Add('    }' + $(if ($index -lt $entries.Count - 1) { ',' } else { '' }))
    }

    $lines.Add('  ]')
    $lines.Add('}')
    return ($lines -join "`n") + "`n"
}

function Get-ContributorSha256
{
    <#
        SHA-256 of bytes as uppercase hexadecimal. Get-FileHash is not used:
        Windows PowerShell 5.1 cannot always resolve it from a nested script.
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Byte[]]
        $Bytes
    )

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try
    {
        return [System.BitConverter]::ToString($sha.ComputeHash($Bytes)).Replace('-', '')
    }
    finally
    {
        $sha.Dispose()
    }
}

function Assert-ContributorWritablePath
{
    <#
        Refuses any write destination under a git working tree, before a
        directory or a file is created there.
    #>
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Path
    )

    if (Test-ContributorPathInsideRepository -Path $Path)
    {
        throw ("'{0}' lies inside a git working tree; no Familiarity level may be written there (inside-repository). Nothing was written." -f $Path)
    }
}

function Write-ContributorFileAtomically
{
    <#
        Writes bytes to a temporary file beside the target, then replaces the
        target in one step, so a reader sees the old or the new file, never a
        partial one. The temporary name does not end in .json, so no host can
        load it as a hook file while it exists.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Path,

        [Parameter(Mandatory = $true)]
        [System.Byte[]]
        $Bytes
    )

    $directory = [System.IO.Path]::GetDirectoryName($Path)
    $temporary = [System.IO.Path]::Combine($directory, ('.{0}.{1}.tmp' -f [System.IO.Path]::GetFileNameWithoutExtension($Path), [System.Guid]::NewGuid().ToString('N')))

    if (-not $PSCmdlet.ShouldProcess($Path, 'Write file'))
    {
        return
    }

    $null = [System.IO.Directory]::CreateDirectory($directory)
    try
    {
        [System.IO.File]::WriteAllBytes($temporary, $Bytes)
        if ([System.IO.File]::Exists($Path))
        {
            # [NullString]: PowerShell would pass $null as an empty path.
            [System.IO.File]::Replace($temporary, $Path, [System.Management.Automation.Language.NullString]::Value)
        }
        else
        {
            [System.IO.File]::Move($temporary, $Path)
        }
    }
    finally
    {
        if ([System.IO.File]::Exists($temporary))
        {
            [System.IO.File]::Delete($temporary)
        }
    }
}

function Enter-ContributorProfileLock
{
    <#
        Takes the profile lock that every writer and Uninstall share: an
        exclusive lock file deleted on close. Fails clearly, having written
        nothing, when another writer holds it past the timeout.
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileStream])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Object]
        $Location,

        [Parameter()]
        [System.Int32]
        $TimeoutMilliseconds = 5000
    )

    Assert-ContributorWritablePath -Path $Location.ProfilePath
    $null = [System.IO.Directory]::CreateDirectory($Location.ContributorDirectory)
    $watch = [System.Diagnostics.Stopwatch]::StartNew()

    while ($true)
    {
        try
        {
            return [System.IO.FileStream]::new(
                $Location.LockPath,
                [System.IO.FileMode]::OpenOrCreate,
                [System.IO.FileAccess]::ReadWrite,
                [System.IO.FileShare]::None,
                1,
                [System.IO.FileOptions]::DeleteOnClose
            )
        }
        catch [System.IO.IOException], [System.UnauthorizedAccessException]
        {
            if ($watch.ElapsedMilliseconds -ge $TimeoutMilliseconds)
            {
                throw ("The contributor profile is locked by another writer ({0}); nothing was written. Try again when it is done." -f $Location.LockPath)
            }

            Start-Sleep -Milliseconds 100
        }
    }
}

function Save-ContributorProfile
{
    <#
        Writes the profile model atomically. The bytes are parsed and validated
        again before the write, so no writer can produce a file that the reader
        would reject. On a Windows OneDrive path the file is pinned, so it is
        always available offline and never becomes a placeholder.
    #>
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Object]
        $Location,

        [Parameter(Mandatory = $true)]
        [System.Object]
        $ContributorProfile
    )

    Assert-ContributorWritablePath -Path $Location.ProfilePath
    $json = ConvertTo-ContributorProfileJson -ContributorProfile $ContributorProfile
    $null = ConvertTo-ContributorProfileModel -Node (ConvertFrom-ContributorJson -Text $json)

    $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($json)
    if ($bytes.Length -gt (Get-ContributorProfileLimit).ProfileBytes)
    {
        throw 'The contributor profile would exceed 64 KB; nothing was written.'
    }

    Write-ContributorFileAtomically -Path $Location.ProfilePath -Bytes $bytes -Confirm:$false -WhatIf:$false

    if ($Location.Synced -and [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT)
    {
        try
        {
            $null = & "$env:SystemRoot\System32\attrib.exe" +P $Location.ProfilePath 2>&1
        }
        catch
        {
            Write-Warning -Message ('The contributor profile could not be pinned: ' + $_.Exception.Message)
        }
    }
}

function New-ContributorEntryModel
{
    <#
        A new entry: an immutable GUID, on, no levels, and the git address as
        the first alias when git has a valid one.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [System.String]
        $Email
    )

    $aliases = [System.Collections.Generic.List[string]]::new()
    if (Test-ContributorAlias -Alias $Email)
    {
        $aliases.Add($Email)
    }

    return [pscustomobject] @{
        Id                       = [System.Guid]::NewGuid().ToString('D')
        Default                  = $false
        State                    = 'on'
        StateUpdatedUtc          = Get-ContributorUtcNow
        InterviewSnoozedUntilUtc = $null
        Aliases                  = $aliases
        Areas                    = [System.Collections.Specialized.OrderedDictionary]::new([System.StringComparer]::InvariantCultureIgnoreCase)
    }
}

function Resolve-ContributorEntrySelector
{
    <#
        -Contributor names an entry by id or alias and must resolve to exactly
        one; anything else fails before any write.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Object]
        $ContributorProfile,

        [Parameter(Mandatory = $true)]
        [System.String]
        $Contributor
    )

    $found = @(
        foreach ($entry in $ContributorProfile.Contributors)
        {
            $byAlias = @($entry.Aliases | Where-Object -FilterScript { [System.String]::Equals($_, $Contributor, [System.StringComparison]::OrdinalIgnoreCase) })
            if ([System.String]::Equals($entry.Id, $Contributor, [System.StringComparison]::OrdinalIgnoreCase) -or $byAlias.Count -gt 0)
            {
                $entry
            }
        }
    )

    if ($found.Count -ne 1)
    {
        throw ("-Contributor '{0}' must name exactly one entry by id or alias; it names {1}. Nothing was written." -f $Contributor, $found.Count)
    }

    return $found[0]
}

function Test-ContributorRegistrationDesired
{
    <#
        The registration exists exactly while an entry is on and rates at least
        one Knowledge area; without levels there is nothing to re-send.
    #>
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [Parameter()]
        [AllowNull()]
        [System.Object]
        $ContributorProfile
    )

    if ($null -eq $ContributorProfile)
    {
        return $false
    }

    foreach ($entry in $ContributorProfile.Contributors)
    {
        if ($entry.State -eq 'on' -and $entry.Areas.Count -gt 0)
        {
            return $true
        }
    }

    return $false
}

# --- ContributorProfileCommon part 2 ---

function Get-ContributorRegistrationTemplate
{
    <#
        The shipped registration template: its bytes and their SHA-256. The
        file holds one PostToolUse entry with the launchers of hooks.json; no
        input ever reaches its bytes, and its path is fixed.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param ()

    $path = [System.IO.Path]::Combine($PSScriptRoot, '..', 'assets', 'contributor-profile.hooks.json')
    $bytes = [System.IO.File]::ReadAllBytes([System.IO.Path]::GetFullPath($path))
    return [pscustomobject] @{
        Bytes  = $bytes
        Sha256 = Get-ContributorSha256 -Bytes $bytes
    }
}

function Read-ContributorRegistrationRecord
{
    <#
        Reads registration.json: { schemaVersion, operation, state, sha256,
        updatedUtc }. Returns $null when there is none, or an object with
        Valid = $false when it cannot be trusted. It never holds a path, so a
        record can never redirect a deletion.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Object]
        $Location
    )

    if (-not [System.IO.File]::Exists($Location.RecordPath))
    {
        return $null
    }

    try
    {
        $node = ConvertFrom-ContributorJson -Text ([System.IO.File]::ReadAllText($Location.RecordPath))
        $member = Get-ContributorNodeMember -Node $node -Allowed @('schemaVersion', 'operation', 'state', 'sha256', 'updatedUtc') -Where 'the registration record'
        $valid = $member['schemaVersion'].V -ceq '1' -and
            @('create', 'delete') -ccontains $member['operation'].V -and
            @('pending', 'complete') -ccontains $member['state'].V -and
            [string] $member['sha256'].V -cmatch '\A[0-9A-F]{64}\z'

        return [pscustomobject] @{
            Valid     = [bool] $valid
            Operation = [string] $member['operation'].V
            State     = [string] $member['state'].V
            Sha256    = [string] $member['sha256'].V
        }
    }
    catch
    {
        return [pscustomobject] @{ Valid = $false; Operation = $null; State = $null; Sha256 = $null }
    }
}

function Write-ContributorRegistrationRecord
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)] [System.Object] $Location,
        [Parameter(Mandatory = $true)] [ValidateSet('create', 'delete')] [System.String] $Operation,
        [Parameter(Mandatory = $true)] [ValidateSet('pending', 'complete')] [System.String] $State,
        [Parameter(Mandatory = $true)] [System.String] $Sha256
    )

    $text = "{`n  `"schemaVersion`": 1,`n  `"operation`": `"$Operation`",`n  `"state`": `"$State`",`n  `"sha256`": `"$Sha256`",`n  `"updatedUtc`": `"$(Get-ContributorUtcNow)`"`n}`n"
    Write-ContributorFileAtomically -Path $Location.RecordPath -Bytes ([System.Text.UTF8Encoding]::new($false).GetBytes($text)) -Confirm:$false -WhatIf:$false
}

function Remove-ContributorRegistrationRecord
{
    [CmdletBinding()]
    param ([Parameter(Mandatory = $true)] [System.Object] $Location)

    if ([System.IO.File]::Exists($Location.RecordPath))
    {
        [System.IO.File]::Delete($Location.RecordPath)
    }
}

function Get-ContributorRegistrationFileHash
{
    [CmdletBinding()]
    [OutputType([System.String])]
    param ([Parameter(Mandatory = $true)] [System.Object] $Location)

    if (-not [System.IO.File]::Exists($Location.RegistrationPath))
    {
        return $null
    }

    return Get-ContributorSha256 -Bytes ([System.IO.File]::ReadAllBytes($Location.RegistrationPath))
}

function Invoke-ContributorRegistrationReconcile
{
    <#
        Reconciles the record against the observed file after any crash. The
        caller holds the profile lock. Returns the status: none, owned, foreign
        (a file this writer did not create), or modified (a file whose bytes no
        longer match what was recorded and shipped). Only a pending or stale
        record is ever changed here; the registration file never is.
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Object]
        $Location
    )

    $template = Get-ContributorRegistrationTemplate
    $record = Read-ContributorRegistrationRecord -Location $Location
    $fileHash = Get-ContributorRegistrationFileHash -Location $Location

    if ($null -eq $record)
    {
        if ($null -eq $fileHash) { return 'none' }
        return 'foreign'
    }

    if (-not $record.Valid)
    {
        if ($null -eq $fileHash) { return 'none' }
        return 'modified'
    }

    $matchesBoth = $null -ne $fileHash -and $fileHash -ceq $record.Sha256 -and $fileHash -ceq $template.Sha256
    if ($null -eq $fileHash)
    {
        # Crash before the file was written, or after it was removed, or the
        # file was deleted by hand: nothing is registered any more.
        Remove-ContributorRegistrationRecord -Location $Location
        return 'none'
    }

    if (-not $matchesBoth)
    {
        return 'modified'
    }

    if ($record.Operation -ne 'create' -or $record.State -ne 'complete')
    {
        # A pending create that wrote its file, or a pending delete that did
        # not remove it: the file is this writer's, unchanged.
        Write-ContributorRegistrationRecord -Location $Location -Operation 'create' -State 'complete' -Sha256 $fileHash
    }

    return 'owned'
}

function New-ContributorRegistration
{
    <#
        Creates the registration in two phases: a pending record, the file
        written atomically, then the completed record with the file's hash.
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param ([Parameter(Mandatory = $true)] [System.Object] $Location)

    if (-not [System.IO.File]::Exists($Location.RegistrationScript))
    {
        # A plugin-only install has no ~/.copilot/hooks/scripts, so the
        # launcher could not resolve the script and would warn on every call.
        return 'unavailable'
    }

    $template = Get-ContributorRegistrationTemplate
    Write-ContributorRegistrationRecord -Location $Location -Operation 'create' -State 'pending' -Sha256 $template.Sha256

    $temporary = [System.IO.Path]::Combine($Location.HooksDirectory, ('.contributor-profile.{0}.tmp' -f [System.Guid]::NewGuid().ToString('N')))
    try
    {
        [System.IO.File]::WriteAllBytes($temporary, $template.Bytes)
        [System.IO.File]::Move($temporary, $Location.RegistrationPath)
    }
    catch
    {
        if ([System.IO.File]::Exists($temporary))
        {
            [System.IO.File]::Delete($temporary)
        }

        # Another file appeared at the fixed path in the meantime. This writer
        # did not create it, so it must never adopt it.
        Remove-ContributorRegistrationRecord -Location $Location
        if ([System.IO.File]::Exists($Location.RegistrationPath)) { return 'foreign' }
        return 'none'
    }

    $fileHash = Get-ContributorRegistrationFileHash -Location $Location
    if ($fileHash -cne $template.Sha256)
    {
        return 'modified'
    }

    Write-ContributorRegistrationRecord -Location $Location -Operation 'create' -State 'complete' -Sha256 $fileHash
    return 'owned'
}

function Remove-ContributorRegistration
{
    <#
        Deletes the registration in two phases, and only when the fixed path,
        the record, the recorded hash, and the shipped template's hash agree.
        The caller has reconciled and holds the lock.
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param ([Parameter(Mandatory = $true)] [System.Object] $Location)

    $template = Get-ContributorRegistrationTemplate
    $record = Read-ContributorRegistrationRecord -Location $Location
    $fileHash = Get-ContributorRegistrationFileHash -Location $Location

    if ($null -eq $record -or -not $record.Valid -or $record.Operation -ne 'create' -or $record.State -ne 'complete' -or
        $fileHash -cne $record.Sha256 -or $fileHash -cne $template.Sha256)
    {
        return Invoke-ContributorRegistrationReconcile -Location $Location
    }

    Write-ContributorRegistrationRecord -Location $Location -Operation 'delete' -State 'pending' -Sha256 $fileHash
    [System.IO.File]::Delete($Location.RegistrationPath)
    Remove-ContributorRegistrationRecord -Location $Location
    return 'none'
}

function Sync-ContributorRegistration
{
    <#
        Reconciles, then drives the registration toward the desired state.
        Returns the status and a message for any file it must leave alone.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Object]
        $Location,

        [Parameter(Mandatory = $true)]
        [System.Boolean]
        $Desired
    )

    $status = Invoke-ContributorRegistrationReconcile -Location $Location
    if ($Desired -and $status -eq 'none')
    {
        $status = New-ContributorRegistration -Location $Location
    }
    elseif (-not $Desired -and $status -eq 'owned')
    {
        $status = Remove-ContributorRegistration -Location $Location
    }

    $messages = @(
        switch ($status)
        {
            'foreign' { "A file this writer did not create sits at '$($Location.RegistrationPath)'; it was left untouched. Remove it by hand if it is not yours." }
            'modified' { "The registration at '$($Location.RegistrationPath)' was changed after it was written; it was left untouched." }
            'unavailable' { 'Levels are not re-sent after a compaction on this machine: the PostToolUse hook script is not deployed here.' }
        }
    )

    return [pscustomobject] @{ Status = $status; Messages = $messages }
}

# --- ContributorProfileCommon part 3 ---

function Get-ContributorRegistrationStatus
{
    <#
        The registration status without changing anything, for a reader that
        does not hold the lock: none, owned, pending, foreign, or modified.
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param ([Parameter(Mandatory = $true)] [System.Object] $Location)

    $template = Get-ContributorRegistrationTemplate
    $record = Read-ContributorRegistrationRecord -Location $Location
    $fileHash = Get-ContributorRegistrationFileHash -Location $Location

    if ($null -eq $fileHash) { return 'none' }
    if ($null -eq $record) { return 'foreign' }
    if (-not $record.Valid -or $fileHash -cne $record.Sha256 -or $fileHash -cne $template.Sha256) { return 'modified' }
    if ($record.Operation -eq 'create' -and $record.State -eq 'complete') { return 'owned' }
    return 'pending'
}

function Get-ContributorLocationMessage
{
    [CmdletBinding()]
    [OutputType([System.String])]
    param ([Parameter(Mandatory = $true)] [System.Object] $Location)

    if ($Location.Kind -eq 'local')
    {
        "The contributor profile is saved on this machine only ($($Location.ProfilePath)). To use it on another machine, run Export-CopilotAtelierContributorProfile -Path <file> here and Import-CopilotAtelierContributorProfile -Path <file> there."
    }
}

function Hide-ContributorAlias
{
    [CmdletBinding()]
    [OutputType([System.String])]
    param ([Parameter(Mandatory = $true)] [System.String] $Alias)

    $parts = $Alias.Split([char]64, 2)
    return $parts[0].Substring(0, 1) + '***@' + $parts[1]
}

function Copy-ContributorEntry
{
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param ([Parameter(Mandatory = $true)] [System.Object] $Entry)

    $areas = [System.Collections.Specialized.OrderedDictionary]::new([System.StringComparer]::InvariantCultureIgnoreCase)
    foreach ($area in $Entry.Areas.Values)
    {
        $areas[$area.Name] = [pscustomobject] @{ Name = $area.Name; Level = $area.Level; UpdatedUtc = $area.UpdatedUtc }
    }

    return [pscustomobject] @{
        Id                       = $Entry.Id
        Default                  = [bool] $Entry.Default
        State                    = $Entry.State
        StateUpdatedUtc          = $Entry.StateUpdatedUtc
        InterviewSnoozedUntilUtc = $Entry.InterviewSnoozedUntilUtc
        Aliases                  = [System.Collections.Generic.List[string]]::new([string[]] @($Entry.Aliases))
        Areas                    = $areas
    }
}

function New-ContributorProfileModel
{
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param ()

    return [pscustomobject] @{ SchemaVersion = 1; Contributors = [System.Collections.Generic.List[object]]::new() }
}

function Set-ContributorProfile
{
    <#
        Sets one Knowledge area level, the opt-out state, aliases, the default
        flag, or the interview snooze on one entry, then manages the
        registration file. Without -Contributor the identity rule selects the
        entry; with no entry yet, or an unmatched git address among several
        entries without a default, it creates one.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true)] [System.Object] $Location,
        [Parameter()] [AllowNull()] [AllowEmptyString()] [System.String] $WorkspacePath,
        [Parameter()] [AllowNull()] [AllowEmptyString()] [System.String] $GitExecutable,
        [Parameter()] [AllowNull()] [AllowEmptyString()] [System.String] $Contributor,
        [Parameter()] [AllowNull()] [AllowEmptyCollection()] [System.String[]] $KnowledgeArea = @(),
        [Parameter()] [ValidateSet('new', 'familiar', 'expert')] [System.String[]] $Level = @(),
        [Parameter()] [ValidateSet('On', 'Off')] [System.String] $State,
        [Parameter()] [System.String[]] $AddAlias = @(),
        [Parameter()] [System.String[]] $RemoveAlias = @(),
        [Parameter()] [System.Management.Automation.SwitchParameter] $Default,
        [Parameter()] [System.Management.Automation.SwitchParameter] $SnoozeInterview
    )

    $limit = Get-ContributorProfileLimit
    $KnowledgeArea = @($KnowledgeArea | Where-Object -FilterScript { -not [System.String]::IsNullOrWhiteSpace($_) })
    if ($KnowledgeArea.Count -ne $Level.Count)
    {
        throw 'Pass -KnowledgeArea and -Level together, one level for each area. Nothing was written.'
    }

    $ratings = [System.Collections.Generic.List[object]]::new()
    for ($index = 0; $index -lt $KnowledgeArea.Count; $index++)
    {
        $areaName = ConvertTo-ContributorAreaName -Name $KnowledgeArea[$index]
        if ($null -eq $areaName)
        {
            throw ("'{0}' breaks the area-name rule: 1 to 48 letters, digits, single spaces, and . + # / & ( ) -, starting with a letter or a digit. Nothing was written." -f $KnowledgeArea[$index])
        }

        $ratings.Add([pscustomobject] @{ Name = $areaName; Level = $Level[$index] })
    }

    foreach ($alias in $AddAlias)
    {
        if (-not (Test-ContributorAlias -Alias $alias))
        {
            throw ("'{0}' is not an email address. Nothing was written." -f $alias)
        }
    }

    if ($ratings.Count -eq 0 -and -not $State -and $AddAlias.Count -eq 0 -and $RemoveAlias.Count -eq 0 -and -not $Default -and -not $SnoozeInterview)
    {
        throw 'Name at least one change. Nothing was written.'
    }

    Assert-ContributorWritablePath -Path $Location.ProfilePath
    $lock = if ($WhatIfPreference) { $null } else { Enter-ContributorProfileLock -Location $Location }
    try
    {
        $read = Read-ContributorProfile -Location $Location
        if ($read.ReasonCode)
        {
            throw ('The contributor profile cannot be changed ({0}): {1} Nothing was written.' -f $read.ReasonCode, $read.Detail)
        }

        $model = if ($read.Profile) { $read.Profile } else { New-ContributorProfileModel }
        $changes = [System.Collections.Generic.List[string]]::new()
        $created = $false
        $entry = $null

        if (-not [System.String]::IsNullOrWhiteSpace($Contributor))
        {
            $entry = Resolve-ContributorEntrySelector -ContributorProfile $model -Contributor $Contributor
        }
        else
        {
            $workspace = $WorkspacePath
            if ([System.String]::IsNullOrWhiteSpace($workspace))
            {
                $workspace = (Get-Location).ProviderPath
            }

            $email = Get-ContributorGitEmail -WorkingDirectory $workspace -GitExecutable $GitExecutable
            if ($model.Contributors.Count -gt 0)
            {
                $entry = (Select-ContributorEntry -ContributorProfile $model -Email $email).Entry
            }

            if ($null -eq $entry)
            {
                if ($model.Contributors.Count -gt 0 -and -not (Test-ContributorAlias -Alias $email))
                {
                    throw 'Several entries exist, none is the default, and git names no address here, so it is unclear whose entry to change. Pass -Contributor with an id or an alias. Nothing was written.'
                }

                if ($model.Contributors.Count -ge $limit.Entries)
                {
                    throw "The profile already holds $($limit.Entries) entries. Nothing was written."
                }

                $entry = New-ContributorEntryModel -Email $email
                $model.Contributors.Add($entry)
                $created = $true
                $changes.Add('create an entry')
            }
        }

        $now = Get-ContributorUtcNow
        foreach ($rating in $ratings)
        {
            if ($entry.Areas.Contains($rating.Name))
            {
                $storedName = $entry.Areas[$rating.Name].Name
                $entry.Areas[$rating.Name] = [pscustomobject] @{ Name = $storedName; Level = $rating.Level; UpdatedUtc = $now }
                $changes.Add(('set {0} to {1}' -f $storedName, $rating.Level))
            }
            else
            {
                if ($entry.Areas.Count -ge $limit.Areas)
                {
                    throw "An entry holds at most $($limit.Areas) Knowledge areas. Nothing was written."
                }

                $entry.Areas[$rating.Name] = [pscustomobject] @{ Name = $rating.Name; Level = $rating.Level; UpdatedUtc = $now }
                $changes.Add(('set {0} to {1}' -f $rating.Name, $rating.Level))
            }
        }

        if ($State)
        {
            $entry.State = $State.ToLowerInvariant()
            $entry.StateUpdatedUtc = $now
            $changes.Add('turn the profile ' + $entry.State)
        }

        foreach ($alias in $AddAlias)
        {
            $owner = $null
            foreach ($candidate in $model.Contributors)
            {
                foreach ($existing in $candidate.Aliases)
                {
                    if ([System.String]::Equals($existing, $alias, [System.StringComparison]::OrdinalIgnoreCase))
                    {
                        $owner = $candidate
                    }
                }
            }

            if ($null -ne $owner -and -not [System.Object]::ReferenceEquals($owner, $entry))
            {
                throw ("The alias '{0}' belongs to another entry; one alias selects at most one entry. Nothing was written." -f $alias)
            }

            if ($null -eq $owner)
            {
                if ($entry.Aliases.Count -ge $limit.Aliases)
                {
                    throw "An entry holds at most $($limit.Aliases) aliases. Nothing was written."
                }

                $entry.Aliases.Add($alias)
                $changes.Add('add an alias')
            }
        }

        foreach ($alias in $RemoveAlias)
        {
            $existing = @($entry.Aliases | Where-Object -FilterScript { [System.String]::Equals($_, $alias, [System.StringComparison]::OrdinalIgnoreCase) })
            if ($existing.Count -gt 0)
            {
                $null = $entry.Aliases.Remove($existing[0])
                $changes.Add('remove an alias')
            }
        }

        if ($Default)
        {
            foreach ($candidate in $model.Contributors)
            {
                $candidate.Default = [System.Object]::ReferenceEquals($candidate, $entry)
            }

            $changes.Add('mark the entry as the default')
        }

        if ($SnoozeInterview)
        {
            $entry.InterviewSnoozedUntilUtc = [System.DateTime]::UtcNow.AddDays(14).ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [System.Globalization.CultureInfo]::InvariantCulture)
            $changes.Add('snooze the interview for 14 days')
        }

        $result = [pscustomobject] @{
            ProfilePath  = $Location.ProfilePath
            Kind         = $Location.Kind
            Synced       = $Location.Synced
            EntryId      = $entry.Id
            Created      = $created
            Changes      = $changes.ToArray()
            Registration = $null
            Messages     = [System.String[]] @()
            WhatIf       = $false
        }

        if (-not $PSCmdlet.ShouldProcess($Location.ProfilePath, ('Set contributor profile: ' + ($changes -join '; '))))
        {
            $result.WhatIf = $true
            return $result
        }

        Save-ContributorProfile -Location $Location -ContributorProfile $model
        $sync = Sync-ContributorRegistration -Location $Location -Desired (Test-ContributorRegistrationDesired -ContributorProfile $model)
        $result.Registration = $sync.Status
        $result.Messages = @($sync.Messages) + @(Get-ContributorLocationMessage -Location $Location)
        return $result
    }
    finally
    {
        if ($null -ne $lock)
        {
            $lock.Dispose()
        }
    }
}

# --- ContributorProfileCommon part 4 ---

function Resolve-ContributorFullPath
{
    [CmdletBinding()]
    [OutputType([System.String])]
    param ([Parameter(Mandatory = $true)] [System.String] $Path)

    return $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
}

function Export-ContributorProfile
{
    <#
        Writes a schema-1 file of every entry, or of the one entry -Contributor
        names, for import on another machine. Refuses a destination inside a git
        working tree.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true)] [System.Object] $Location,
        [Parameter(Mandatory = $true)] [System.String] $Path,
        [Parameter()] [AllowNull()] [AllowEmptyString()] [System.String] $Contributor
    )

    $destination = Resolve-ContributorFullPath -Path $Path
    Assert-ContributorWritablePath -Path $destination

    $read = Read-ContributorProfile -Location $Location
    if ($read.ReasonCode)
    {
        throw ('The contributor profile cannot be exported ({0}): {1} Nothing was written.' -f $read.ReasonCode, $read.Detail)
    }

    if (-not $read.Exists)
    {
        throw 'There is no contributor profile to export. Nothing was written.'
    }

    $entries = if ([System.String]::IsNullOrWhiteSpace($Contributor))
    {
        @($read.Profile.Contributors)
    }
    else
    {
        @(Resolve-ContributorEntrySelector -ContributorProfile $read.Profile -Contributor $Contributor)
    }

    $export = New-ContributorProfileModel
    foreach ($entry in $entries)
    {
        $export.Contributors.Add($entry)
    }

    $json = ConvertTo-ContributorProfileJson -ContributorProfile $export
    $null = ConvertTo-ContributorProfileModel -Node (ConvertFrom-ContributorJson -Text $json)

    if ($PSCmdlet.ShouldProcess($destination, ('Export {0} contributor profile entries' -f $entries.Count)))
    {
        Write-ContributorFileAtomically -Path $destination -Bytes ([System.Text.UTF8Encoding]::new($false).GetBytes($json)) -Confirm:$false -WhatIf:$false
    }

    return [pscustomobject] @{
        Path       = $destination
        EntryCount = $entries.Count
        WhatIf     = [bool] $WhatIfPreference
    }
}

function Merge-ContributorProfile
{
    <#
        The import merge of Decision record 0028. An imported entry matches the
        local entry with the same id, else the one local entry that shares an
        alias with it. Per area the newer updatedUtc wins and a tie keeps the
        local value; an area on one side only is kept. State follows the newer
        stateUpdatedUtc, the later snooze wins, aliases form a union, and the
        default flag stays local. An ambiguous match, an alias that would belong
        to two entries, or a cap overflow refuses the whole file.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true)] [System.Object] $Local,
        [Parameter(Mandatory = $true)] [System.Object] $Incoming
    )

    $limit = Get-ContributorProfileLimit
    $refuse = {
        param ([string] $Reason)
        throw ('Import refused: {0} Nothing was written.' -f $Reason)
    }

    $later = {
        param ([string] $Left, [string] $Right)
        (ConvertFrom-ContributorUtcTimestamp -Value $Left) -gt (ConvertFrom-ContributorUtcTimestamp -Value $Right)
    }

    $merged = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in $Local.Contributors)
    {
        $merged.Add((Copy-ContributorEntry -Entry $entry))
    }

    $localCount = $merged.Count
    $assigned = [System.Collections.Generic.HashSet[int]]::new()
    $matched = 0
    $added = 0

    foreach ($incomingEntry in $Incoming.Contributors)
    {
        $target = -1
        for ($index = 0; $index -lt $localCount; $index++)
        {
            if ([System.String]::Equals($merged[$index].Id, $incomingEntry.Id, [System.StringComparison]::OrdinalIgnoreCase))
            {
                $target = $index
            }
        }

        if ($target -lt 0)
        {
            $hits = [System.Collections.Generic.HashSet[int]]::new()
            for ($index = 0; $index -lt $localCount; $index++)
            {
                foreach ($alias in $incomingEntry.Aliases)
                {
                    foreach ($localAlias in $merged[$index].Aliases)
                    {
                        if ([System.String]::Equals($alias, $localAlias, [System.StringComparison]::OrdinalIgnoreCase))
                        {
                            $null = $hits.Add($index)
                        }
                    }
                }
            }

            if ($hits.Count -gt 1)
            {
                & $refuse 'an imported entry shares aliases with two local entries.'
            }

            foreach ($hit in $hits)
            {
                $target = $hit
            }
        }

        if ($target -lt 0)
        {
            $copy = Copy-ContributorEntry -Entry $incomingEntry
            $copy.Default = $false
            $merged.Add($copy)
            $added++
            continue
        }

        if (-not $assigned.Add($target))
        {
            & $refuse 'two imported entries match the same local entry.'
        }

        $matched++
        $into = $merged[$target]
        foreach ($area in $incomingEntry.Areas.Values)
        {
            if ($into.Areas.Contains($area.Name))
            {
                $current = $into.Areas[$area.Name]
                if (& $later $area.UpdatedUtc $current.UpdatedUtc)
                {
                    $into.Areas[$area.Name] = [pscustomobject] @{ Name = $current.Name; Level = $area.Level; UpdatedUtc = $area.UpdatedUtc }
                }
            }
            else
            {
                $into.Areas[$area.Name] = [pscustomobject] @{ Name = $area.Name; Level = $area.Level; UpdatedUtc = $area.UpdatedUtc }
            }
        }

        if (& $later $incomingEntry.StateUpdatedUtc $into.StateUpdatedUtc)
        {
            $into.State = $incomingEntry.State
            $into.StateUpdatedUtc = $incomingEntry.StateUpdatedUtc
        }

        if ($incomingEntry.InterviewSnoozedUntilUtc -and
            (-not $into.InterviewSnoozedUntilUtc -or (& $later $incomingEntry.InterviewSnoozedUntilUtc $into.InterviewSnoozedUntilUtc)))
        {
            $into.InterviewSnoozedUntilUtc = $incomingEntry.InterviewSnoozedUntilUtc
        }

        foreach ($alias in $incomingEntry.Aliases)
        {
            $present = @($into.Aliases | Where-Object -FilterScript { [System.String]::Equals($_, $alias, [System.StringComparison]::OrdinalIgnoreCase) })
            if ($present.Count -eq 0)
            {
                $into.Aliases.Add($alias)
            }
        }
    }

    if ($merged.Count -gt $limit.Entries)
    {
        & $refuse "the result would hold more than $($limit.Entries) entries."
    }

    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in $merged)
    {
        if ($entry.Aliases.Count -gt $limit.Aliases)
        {
            & $refuse "an entry would hold more than $($limit.Aliases) aliases."
        }

        if ($entry.Areas.Count -gt $limit.Areas)
        {
            & $refuse "an entry would hold more than $($limit.Areas) Knowledge areas."
        }

        foreach ($alias in $entry.Aliases)
        {
            if (-not $seen.Add($alias))
            {
                & $refuse 'an alias would belong to two entries.'
            }
        }
    }

    return [pscustomobject] @{
        Profile = [pscustomobject] @{ SchemaVersion = 1; Contributors = $merged }
        Matched = $matched
        Added   = $added
    }
}

function Import-ContributorProfile
{
    <#
        Validates a schema-1 file as strictly as the hooks do, merges it into
        the profile at the location, and manages the registration. -WhatIf
        reports what would be matched and added.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true)] [System.Object] $Location,
        [Parameter(Mandatory = $true)] [System.String] $Path
    )

    $source = Resolve-ContributorFullPath -Path $Path
    $incoming = Read-ContributorProfileData -Path $source
    if (-not $incoming.Exists)
    {
        throw ("There is no file at '{0}'. Nothing was written." -f $source)
    }

    if ($incoming.ReasonCode)
    {
        throw ('The file cannot be imported ({0}): {1} Nothing was written.' -f $incoming.ReasonCode, $incoming.Detail)
    }

    Assert-ContributorWritablePath -Path $Location.ProfilePath
    $lock = if ($WhatIfPreference) { $null } else { Enter-ContributorProfileLock -Location $Location }
    try
    {
        $read = Read-ContributorProfile -Location $Location
        if ($read.ReasonCode)
        {
            throw ('The contributor profile cannot be changed ({0}): {1} Nothing was written.' -f $read.ReasonCode, $read.Detail)
        }

        $local = if ($read.Profile) { $read.Profile } else { New-ContributorProfileModel }
        $merge = Merge-ContributorProfile -Local $local -Incoming $incoming.Profile

        $result = [pscustomobject] @{
            ProfilePath  = $Location.ProfilePath
            Kind         = $Location.Kind
            Synced       = $Location.Synced
            Matched      = $merge.Matched
            Added        = $merge.Added
            Registration = $null
            Messages     = [System.String[]] @()
            WhatIf       = $false
        }

        if (-not $PSCmdlet.ShouldProcess($Location.ProfilePath, ('Import {0}: merge {1} entries, add {2}' -f $source, $merge.Matched, $merge.Added)))
        {
            $result.WhatIf = $true
            return $result
        }

        Save-ContributorProfile -Location $Location -ContributorProfile $merge.Profile
        $sync = Sync-ContributorRegistration -Location $Location -Desired (Test-ContributorRegistrationDesired -ContributorProfile $merge.Profile)
        $result.Registration = $sync.Status
        $result.Messages = @($sync.Messages) + @(Get-ContributorLocationMessage -Location $Location)
        return $result
    }
    finally
    {
        if ($null -ne $lock)
        {
            $lock.Dispose()
        }
    }
}

function Remove-ContributorProfile
{
    <#
        Deletes one entry, the whole profile file, or with -RegistrationOnly an
        orphaned registration. A registration is removed only under the deletion
        rule; a foreign or modified one is never touched.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true)] [System.Object] $Location,
        [Parameter()] [AllowNull()] [AllowEmptyString()] [System.String] $Contributor,
        [Parameter()] [System.Management.Automation.SwitchParameter] $RegistrationOnly
    )

    $lock = if ($WhatIfPreference) { Assert-ContributorWritablePath -Path $Location.ProfilePath; $null } else { Enter-ContributorProfileLock -Location $Location }
    try
    {
        $result = [pscustomobject] @{
            ProfilePath  = $Location.ProfilePath
            Removed      = 'nothing'
            Registration = $null
            Messages     = [System.String[]] @()
            WhatIf       = [bool] $WhatIfPreference
        }

        if ($RegistrationOnly)
        {
            $status = if ($null -ne $lock) { Invoke-ContributorRegistrationReconcile -Location $Location } else { Get-ContributorRegistrationStatus -Location $Location }
            $result.Registration = $status
            if ($status -eq 'none')
            {
                return $result
            }

            if ($status -ne 'owned')
            {
                throw ("The registration at '{0}' is {1}; it is never deleted automatically. Nothing was removed." -f $Location.RegistrationPath, $status)
            }

            if ($PSCmdlet.ShouldProcess($Location.RegistrationPath, 'Remove the contributor profile registration'))
            {
                $result.Registration = Remove-ContributorRegistration -Location $Location
                $result.Removed = 'registration'
            }

            return $result
        }

        $desired = $false
        if (-not [System.String]::IsNullOrWhiteSpace($Contributor))
        {
            $read = Read-ContributorProfile -Location $Location
            if ($read.ReasonCode)
            {
                throw ('The contributor profile cannot be changed ({0}): {1} Nothing was written.' -f $read.ReasonCode, $read.Detail)
            }

            if (-not $read.Exists)
            {
                throw 'There is no contributor profile. Nothing was written.'
            }

            $entry = Resolve-ContributorEntrySelector -ContributorProfile $read.Profile -Contributor $Contributor
            if (-not $PSCmdlet.ShouldProcess($Location.ProfilePath, ('Remove the contributor profile entry {0}' -f $entry.Id)))
            {
                return $result
            }

            $null = $read.Profile.Contributors.Remove($entry)
            if ($read.Profile.Contributors.Count -eq 0)
            {
                [System.IO.File]::Delete($Location.ProfilePath)
                $result.Removed = 'file'
            }
            else
            {
                Save-ContributorProfile -Location $Location -ContributorProfile $read.Profile
                $result.Removed = 'entry'
                $desired = Test-ContributorRegistrationDesired -ContributorProfile $read.Profile
            }
        }
        else
        {
            if ([System.IO.File]::Exists($Location.ProfilePath))
            {
                if (-not $PSCmdlet.ShouldProcess($Location.ProfilePath, 'Delete the contributor profile file'))
                {
                    return $result
                }

                [System.IO.File]::Delete($Location.ProfilePath)
                $result.Removed = 'file'
            }
            elseif ($WhatIfPreference)
            {
                return $result
            }
        }

        $sync = Sync-ContributorRegistration -Location $Location -Desired $desired
        $result.Registration = $sync.Status
        $result.Messages = @($sync.Messages)
        return $result
    }
    finally
    {
        if ($null -ne $lock)
        {
            $lock.Dispose()
        }
    }
}

function Get-ContributorProfileReport
{
    <#
        The 30-second check: where the profile lives and whether it syncs, the
        selected entry and why, its levels, the exact sentence for a workspace,
        possible conflict copies, and the registration state. Aliases are
        masked unless -ShowAliases, because an agent-run report enters the
        model's context. Reconciles a pending registration record when the lock
        is free, and changes nothing else.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true)] [System.Object] $Location,
        [Parameter()] [AllowNull()] [AllowEmptyString()] [System.String] $WorkspacePath,
        [Parameter()] [System.Management.Automation.SwitchParameter] $ShowAliases,
        [Parameter()] [AllowNull()] [AllowEmptyString()] [System.String] $GitExecutable
    )

    $read = Read-ContributorProfile -Location $Location

    $registration = 'none'
    if ([System.IO.File]::Exists($Location.RecordPath) -or [System.IO.File]::Exists($Location.RegistrationPath))
    {
        $lock = $null
        if ([System.IO.File]::Exists($Location.RecordPath))
        {
            try
            {
                $lock = Enter-ContributorProfileLock -Location $Location -TimeoutMilliseconds 1000
            }
            catch
            {
                $lock = $null
            }
        }

        try
        {
            $registration = if ($null -ne $lock) { Invoke-ContributorRegistrationReconcile -Location $Location } else { Get-ContributorRegistrationStatus -Location $Location }
        }
        finally
        {
            if ($null -ne $lock)
            {
                $lock.Dispose()
            }
        }
    }

    if ($registration -eq 'owned' -and -not (Test-ContributorRegistrationDesired -ContributorProfile $read.Profile))
    {
        $registration = 'orphaned'
    }

    $workspace = $WorkspacePath
    if ([System.String]::IsNullOrWhiteSpace($workspace))
    {
        $workspace = (Get-Location).ProviderPath
    }

    $selection = [pscustomobject] @{ Entry = $null; Reason = 'none' }
    if ($read.Profile)
    {
        $email = Get-ContributorGitEmail -WorkingDirectory $workspace -GitExecutable $GitExecutable
        $selection = Select-ContributorEntry -ContributorProfile $read.Profile -Email $email
    }

    $entry = $selection.Entry
    $sentence = ''
    if (-not [System.String]::IsNullOrWhiteSpace($WorkspacePath))
    {
        $calibration = Get-ContributorCalibration -WorkspacePath $WorkspacePath -Location $Location -GitExecutable $GitExecutable
        $sentence = Format-ContributorCalibrationSentence -Calibration $calibration
    }

    $conflicts = @()
    if ([System.IO.Directory]::Exists($Location.ContributorDirectory))
    {
        $conflicts = @(
            Get-ChildItem -LiteralPath $Location.ContributorDirectory -Filter '*.json' -File -Force |
                Where-Object -FilterScript { @('profile.json', 'registration.json') -notcontains $_.Name } |
                ForEach-Object -Process { $_.Name }
        )
    }

    $storage = if ($Location.Kind -eq 'canonical' -and $Location.Synced)
    {
        'Canonical target, synced through OneDrive'
    }
    elseif ($Location.Kind -eq 'canonical')
    {
        'Canonical target, not synced'
    }
    else
    {
        'this machine only'
    }

    return [pscustomobject] @{
        ProfilePath      = $Location.ProfilePath
        Kind             = $Location.Kind
        Synced           = $Location.Synced
        Storage          = $storage
        Exists           = $read.Exists
        ReasonCode       = $read.ReasonCode
        Detail           = $read.Detail
        EntryCount       = if ($read.Profile) { $read.Profile.Contributors.Count } else { 0 }
        Selection        = $selection.Reason
        EntryId          = if ($entry) { $entry.Id } else { $null }
        State            = if ($entry) { $entry.State } else { $null }
        Levels           = [System.String[]] @(if ($entry) { $entry.Areas.Values | ForEach-Object -Process { '{0}: {1}' -f $_.Name, $_.Level } })
        Aliases          = [System.String[]] @(if ($entry) { $entry.Aliases | ForEach-Object -Process { if ($ShowAliases) { $_ } else { Hide-ContributorAlias -Alias $_ } } })
        Sentence         = $sentence
        ConflictCopies   = [System.String[]] $conflicts
        Registration     = $registration
        RegistrationPath = $Location.RegistrationPath
    }
}
