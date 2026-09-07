function Get-CopilotAtelierBoundedFile
{
    <#
        .SYNOPSIS
            Enumerates explicitly selected files under a documented count bound
            without ever descending through a reparse point.

        .DESCRIPTION
            Walks the selected paths breadth-first and guards every directory
            against the selected containment root before descending into it, so
            a link inside the root is refused rather than followed. The file
            bound is enforced during the walk rather than after it, so a hostile
            or accidental tree cannot be fully enumerated first.

            An explicitly selected file is guarded against its own parent
            directory as well, so an ancestor link cannot redirect the read to a
            file outside the caller's selection.

        .PARAMETER Path
            One or more explicitly selected files or directories. A directory
            contributes the files below it that carry the requested extension.

        .PARAMETER Extension
            The file extension to collect, including the leading period.

        .PARAMETER MaxFileCount
            The documented upper bound on the number of files a single run reads.

        .PARAMETER Subject
            The noun used in the bound and missing-path error messages.

        .OUTPUTS
            System.IO.FileInfo

        .EXAMPLE
            Get-CopilotAtelierBoundedFile -Path $importDirectory -Extension '.json' -MaxFileCount 200 -Subject 'Skill observation'

            Returns at most 200 JSON files from the selected directory.
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String[]]
        $Path,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $Extension,

        [Parameter(Mandatory = $true)]
        [ValidateRange(1, 100000)]
        [System.Int32]
        $MaxFileCount,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $Subject
    )

    $ErrorActionPreference = 'Stop'

    $file = [System.Collections.Generic.List[System.IO.FileInfo]]::new()

    foreach ($selected in $Path)
    {
        $fullPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($selected)

        if (Test-Path -LiteralPath $fullPath -PathType Container)
        {
            # The selected directory is the containment root: refuse it outright
            # when it is a reparse point, then guard every directory below it
            # before descending so a link cannot redirect the walk.
            Assert-CopilotAtelierRegularPath -LiteralPath $fullPath -RootPath $fullPath -ErrorAction Stop

            $pending = [System.Collections.Generic.Queue[string]]::new()
            $pending.Enqueue($fullPath)

            while ($pending.Count -gt 0)
            {
                $directory = $pending.Dequeue()

                foreach ($child in Get-ChildItem -LiteralPath $directory -Force -ErrorAction Stop | Sort-Object -Property Name)
                {
                    if ($child.PSIsContainer)
                    {
                        Assert-CopilotAtelierRegularPath -LiteralPath $child.FullName -RootPath $fullPath -ErrorAction Stop
                        $pending.Enqueue($child.FullName)
                        continue
                    }

                    if ($child.Extension -ne $Extension)
                    {
                        continue
                    }

                    Assert-CopilotAtelierRegularPath -LiteralPath $child.FullName -RootPath $fullPath -ErrorAction Stop

                    if ($file.Count -ge $MaxFileCount)
                    {
                        throw "The selected $Subject paths hold more than $MaxFileCount files, which is the documented read bound."
                    }

                    $file.Add($child)
                }
            }

            continue
        }

        if (Test-Path -LiteralPath $fullPath -PathType Leaf)
        {
            $parentPath = [System.IO.Path]::GetDirectoryName($fullPath)
            if ([string]::IsNullOrEmpty($parentPath))
            {
                $parentPath = $fullPath
            }
            Assert-CopilotAtelierRegularPath -LiteralPath $fullPath -RootPath $parentPath -ErrorAction Stop

            if ($file.Count -ge $MaxFileCount)
            {
                throw "The selected $Subject paths hold more than $MaxFileCount files, which is the documented read bound."
            }

            $file.Add((Get-Item -LiteralPath $fullPath -Force))
            continue
        }

        throw "The $Subject path '$fullPath' does not exist."
    }

    return @($file | Sort-Object -Property FullName)
}
