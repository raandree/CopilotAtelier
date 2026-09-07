function Export-CopilotAtelierClientAdapterArtifact
{
    <#
        .SYNOPSIS
            Writes the composed client variants into a build directory this
            module owns, and removes only the files it wrote there before and
            that are still byte for byte the files it wrote.

        .DESCRIPTION
            A build task that rebuilds a directory from scratch is one property
            value away from deleting something it never created. Pointing the
            adapter subdirectory at the built module or the resolved dependency
            directory would have removed unrelated build artifacts, and nothing
            in the path was validated before the delete.

            This function makes the deletion bounded instead, in three ways.

            Every component of every path is guarded. The build output
            directory, the artifact directory, the ownership manifest, each
            client directory, each generated file and each destination is
            checked through the shared regular-path guard before it is read,
            deleted, created, written, or enumerated. A link placed anywhere
            along that chain - not only at the root or at the leaf - is refused,
            so no read and no write ever leaves the owned tree.

            The whole operation is constructed and validated before the first
            mutation. Variants, the manifest schema, its list shape, its
            entries, duplicate manifest paths, duplicate variant destinations
            and every collision are settled first, so a request that is going to
            be refused is refused with the directory exactly as it was found.

            Ownership is proved by content, not by a file name. The manifest
            records the SHA-256 of every file it generated, so a generated file
            a user has since edited is refused rather than silently deleted or
            overwritten, and a file at a destination this build never generated
            is refused rather than adopted - whatever it contains. A schema 1
            manifest carries names only and therefore cannot prove any of that:
            it is refused, with the paths it claims and a migration path, rather
            than adopting the hashes of whatever now sits there.

        .PARAMETER Path
            The adapter artifact directory to own.

        .PARAMETER ParentPath
            The build output directory that must contain Path directly.

        .PARAMETER Variant
            The composed variants to write. Each needs Client, FileName and
            Content.

        .OUTPUTS
            System.String

        .EXAMPLE
            Export-CopilotAtelierClientAdapterArtifact -Path ./output/clientAdapters -ParentPath ./output -Variant $variant

            Writes the variants and returns the full path of each file written.
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $Path,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $ParentPath,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [psobject[]]
        $Variant
    )

    $ErrorActionPreference = 'Stop'

    $manifestName = '.copilot-atelier-adapter-manifest.json'
    $manifestSchema = 2
    $owner = 'CopilotAtelier/Build_Client_Adapter_Variants'
    $reservedName = @('module', 'RequiredModules', 'testResults', 'WikiContent')
    $encoding = [System.Text.UTF8Encoding]::new($false)

    $isWindowsHost = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT
    $comparer = if ($isWindowsHost) { [System.StringComparer]::OrdinalIgnoreCase } else { [System.StringComparer]::Ordinal }
    $comparison = if ($isWindowsHost) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }

    $getHash = {
        param ([System.Byte[]] $Byte)

        $sha256 = [System.Security.Cryptography.SHA256]::Create()

        try
        {
            [System.BitConverter]::ToString($sha256.ComputeHash($Byte)).Replace('-', '').ToLowerInvariant()
        }
        finally
        {
            $sha256.Dispose()
        }
    }

    #region Validate the request itself, before anything on disk is touched.
    $plan = [System.Collections.Generic.List[psobject]]::new()
    $planned = [System.Collections.Generic.HashSet[string]]::new($comparer)

    foreach ($current in $Variant)
    {
        if ($current.Client -notmatch '^[A-Za-z][A-Za-z0-9._-]*$')
        {
            throw "The variant client '$($current.Client)' is not a simple directory name."
        }

        if ($current.FileName -notmatch '^[A-Za-z][A-Za-z0-9._-]*\.agent\.md$')
        {
            throw "The variant file name '$($current.FileName)' is not a plain Custom agent file name."
        }

        if ($current.Content -isnot [System.String])
        {
            throw "The variant '$($current.Client)/$($current.FileName)' carries no string content, so there is nothing to write."
        }

        $relativePath = '{0}/{1}' -f $current.Client, $current.FileName

        if (-not $planned.Add($relativePath))
        {
            throw "Two composed variants both target '$relativePath', so one would silently overwrite the other."
        }

        $plan.Add(
            [pscustomobject] @{
                RelativePath = $relativePath
                Content      = $current.Content
                FullPath     = $null
            }
        )
    }
    #endregion

    #region Establish the owned root and guard every path component under it.
    $fullParent = [System.IO.Path]::GetFullPath(
        $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ParentPath))
    $fullPath = [System.IO.Path]::GetFullPath(
        $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path))

    if (-not (Test-Path -LiteralPath $fullParent -PathType Container))
    {
        throw "The build output directory '$fullParent' does not exist."
    }

    $leaf = [System.IO.Path]::GetFileName($fullPath.TrimEnd([System.IO.Path]::DirectorySeparatorChar))

    if ([System.IO.Path]::GetDirectoryName($fullPath) -ne $fullParent.TrimEnd([System.IO.Path]::DirectorySeparatorChar))
    {
        throw "The adapter artifact directory '$fullPath' is not a direct child of the build output directory '$fullParent'."
    }

    if ($leaf -notmatch '^[A-Za-z][A-Za-z0-9._-]*$')
    {
        throw "The adapter artifact directory name must be a simple directory name, but was '$leaf'."
    }

    if ($leaf -in $reservedName)
    {
        throw "The adapter artifact directory may not be the reserved build directory '$leaf'."
    }

    # Guards the artifact directory and the build output directory above it.
    Assert-CopilotAtelierRegularPath -LiteralPath $fullPath -RootPath $fullParent

    $existingDirectory = $null

    if (Test-Path -LiteralPath $fullPath)
    {
        $existingDirectory = Get-Item -LiteralPath $fullPath -Force

        if ($existingDirectory -isnot [System.IO.DirectoryInfo])
        {
            throw "The adapter artifact path '$fullPath' exists and is not a directory."
        }
    }

    $rootPrefix = $fullPath.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar

    foreach ($entry in $plan)
    {
        $entry.FullPath = [System.IO.Path]::GetFullPath((Join-Path -Path $fullPath -ChildPath $entry.RelativePath))

        <#
            Guards the destination and the client directory between it and the
            owned root, so a link in the middle cannot redirect the write.
        #>
        Assert-CopilotAtelierRegularPath -LiteralPath $entry.FullPath -RootPath $fullPath
    }
    #endregion

    #region Read and validate the whole ownership manifest.
    $manifestPath = Join-Path -Path $fullPath -ChildPath $manifestName
    $owned = [System.Collections.Generic.Dictionary[string, psobject]]::new($comparer)

    if ($existingDirectory)
    {
        Assert-CopilotAtelierRegularPath -LiteralPath $manifestPath -RootPath $fullPath

        if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf))
        {
            throw "The directory '$fullPath' carries no CopilotAtelier adapter ownership manifest, so it is refused rather than cleaned. Remove it by hand if it really is build scratch."
        }

        try
        {
            $manifest = [System.IO.File]::ReadAllText($manifestPath) | ConvertFrom-Json
        }
        catch
        {
            throw "The ownership manifest in '$fullPath' is not readable JSON: $($_.Exception.Message)"
        }

        if ($manifest -isnot [System.Management.Automation.PSCustomObject])
        {
            throw "The ownership manifest in '$fullPath' is not a JSON object."
        }

        if ($manifest.owner -ne $owner)
        {
            throw "The ownership manifest in '$fullPath' names '$($manifest.owner)', not '$owner'."
        }

        if ($manifest.schema -ne $manifestSchema)
        {
            if ($manifest.schema -eq 1)
            {
                $claimed = @(@($manifest.file) | ForEach-Object -Process { "'$_'" }) -join ', '

                if (-not $claimed)
                {
                    $claimed = 'nothing'
                }

                throw "The ownership manifest in '$fullPath' is schema 1, which records file names without content hashes and therefore cannot prove that the files on disk are still the ones this build generated. It claims $claimed. Nothing is adopted and nothing is deleted: review those files, then either remove '$fullPath' yourself or point ClientAdapterSubdirectory at a fresh directory name, and rebuild."
            }

            throw "The ownership manifest in '$fullPath' declares schema '$($manifest.schema)', but this build writes schema $manifestSchema."
        }

        if (-not @($manifest.PSObject.Properties).Where({ $_.Name -eq 'file' }))
        {
            throw "The ownership manifest in '$fullPath' carries no file list."
        }

        foreach ($current in @($manifest.file))
        {
            if ($current -isnot [System.Management.Automation.PSCustomObject])
            {
                throw "The ownership manifest in '$fullPath' lists an entry that is not a path and hash object."
            }

            $relativePath = $current.path
            $recordedHash = $current.sha256

            if ($relativePath -isnot [System.String] -or
                $relativePath -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*(/[A-Za-z0-9][A-Za-z0-9._-]*)*$')
            {
                throw "The ownership manifest in '$fullPath' lists the unsafe entry '$relativePath'."
            }

            if ($recordedHash -isnot [System.String] -or $recordedHash -notmatch '^[0-9a-fA-F]{64}$')
            {
                throw "The ownership manifest in '$fullPath' lists '$relativePath' without a usable SHA-256, so its ownership cannot be proved."
            }

            if ($owned.ContainsKey($relativePath))
            {
                throw "The ownership manifest in '$fullPath' lists '$relativePath' more than once."
            }

            $ownedPath = [System.IO.Path]::GetFullPath((Join-Path -Path $fullPath -ChildPath $relativePath))

            if (-not $ownedPath.StartsWith($rootPrefix, $comparison))
            {
                throw "The ownership manifest in '$fullPath' lists '$relativePath', which resolves outside the owned directory."
            }

            Assert-CopilotAtelierRegularPath -LiteralPath $ownedPath -RootPath $fullPath

            $state = 'Missing'

            if (Test-Path -LiteralPath $ownedPath)
            {
                if ((Get-Item -LiteralPath $ownedPath -Force) -isnot [System.IO.FileInfo])
                {
                    throw "The generated path '$ownedPath' is no longer a file, so it is refused rather than removed."
                }

                if ((& $getHash ([System.IO.File]::ReadAllBytes($ownedPath))) -ne $recordedHash.ToLowerInvariant())
                {
                    throw "The generated file '$ownedPath' was modified after this build wrote it, so it is refused rather than deleted or overwritten. Move the edit somewhere this build does not own, or delete the file, and rebuild."
                }

                $state = 'Present'
            }

            $owned[$relativePath] = [pscustomobject] @{
                RelativePath = $relativePath
                FullPath     = $ownedPath
                State        = $state
            }
        }

        <#
            Enumerating a client directory that is a link would read outside the
            owned root, so the later prune pass is cleared before any write.
        #>
        foreach ($directory in @(Get-ChildItem -LiteralPath $fullPath -Directory -Force))
        {
            Assert-CopilotAtelierRegularPath -LiteralPath $directory.FullName -RootPath $fullPath
        }
    }

    foreach ($entry in $plan)
    {
        if (-not (Test-Path -LiteralPath $entry.FullPath))
        {
            continue
        }

        if ((Get-Item -LiteralPath $entry.FullPath -Force) -isnot [System.IO.FileInfo])
        {
            throw "The destination '$($entry.FullPath)' exists and is not a file."
        }

        if (-not $owned.ContainsKey($entry.RelativePath))
        {
            throw "The file '$($entry.FullPath)' is not recorded in this build's ownership manifest, so the composed variant is not written over it. Move or delete that file yourself, then rebuild."
        }
    }
    #endregion

    #region Mutate, now that the whole operation is known to be safe.
    if (-not $existingDirectory)
    {
        New-Item -Path $fullPath -ItemType Directory -Force | Out-Null
    }
    else
    {
        foreach ($current in $owned.Values)
        {
            if ($current.State -eq 'Present')
            {
                Remove-Item -LiteralPath $current.FullPath -Force
            }
        }

        Remove-Item -LiteralPath $manifestPath -Force
    }

    $written = [System.Collections.Generic.List[string]]::new()
    $generated = [System.Collections.Generic.List[psobject]]::new()

    foreach ($entry in $plan)
    {
        $clientDirectory = [System.IO.Path]::GetDirectoryName($entry.FullPath)

        if (-not (Test-Path -LiteralPath $clientDirectory -PathType Container))
        {
            New-Item -Path $clientDirectory -ItemType Directory -Force | Out-Null
        }

        <#
            UTF-8 without a byte-order mark and with LF endings, so the bytes are
            identical on every platform the build runs on and the hash recorded
            below is the hash of the file that is now on disk.
        #>
        $byte = $encoding.GetBytes($entry.Content)
        [System.IO.File]::WriteAllBytes($entry.FullPath, $byte)

        $written.Add($entry.FullPath)
        $generated.Add(
            [ordered] @{
                path   = $entry.RelativePath
                sha256 = & $getHash $byte
            }
        )
    }

    # No timestamp: the artifact has to be byte-identical across rebuilds.
    $manifestContent = [ordered] @{
        schema = $manifestSchema
        owner  = $owner
        file   = @($generated | Sort-Object -Property { $_.path })
    } | ConvertTo-Json -Depth 4

    [System.IO.File]::WriteAllText($manifestPath, ($manifestContent -replace "`r`n", "`n"), $encoding)

    <#
        Remove client directories the current run no longer produces, but only
        when they are empty, so nothing unowned is ever swept up.
    #>
    foreach ($directory in @(Get-ChildItem -LiteralPath $fullPath -Directory -Force))
    {
        Assert-CopilotAtelierRegularPath -LiteralPath $directory.FullName -RootPath $fullPath

        if (-not @(Get-ChildItem -LiteralPath $directory.FullName -Force))
        {
            Remove-Item -LiteralPath $directory.FullName -Force
        }
    }
    #endregion

    return $written.ToArray()
}
