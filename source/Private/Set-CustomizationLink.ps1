function Set-CustomizationLink
{
    <#
        .SYNOPSIS
            Points a discovery path at a customization directory.

        .DESCRIPTION
            VS Code, the GitHub Copilot CLI, and Claude Code discover
            customizations through well-known user-level folders. This command
            replaces such a folder with a junction on Windows or a symbolic link
            elsewhere so every client reads the single canonical target.

            An existing link is recreated so it always points at the current
            target. An empty real directory is removed silently. A non-empty
            real directory is only replaced when -Force is supplied, and only
            when every child can be merged without loss: a child that differs
            from the copy already in the target, or a child that is or contains
            a reparse point, stops the merge and is reported instead.

        .PARAMETER LinkPath
            The discovery path to create or refresh.

        .PARAMETER TargetPath
            The customization directory the link resolves to.

        .PARAMETER LinkItemType
            The link flavour to create: Junction on Windows, SymbolicLink
            elsewhere.

        .PARAMETER CreateOnly
            Leaves an existing path untouched. Used for third-party roots such
            as ~/.claude that belong to another tool and must never be adopted,
            merged, or repointed.

        .PARAMETER Force
            Merges a non-empty real directory into the target and replaces it
            with a link. Without it such a directory is left alone and reported,
            because the caller may be unattended: this function is reachable
            from Update-CopilotAtelier -Force, where there is no console to
            confirm on.

        .OUTPUTS
            None.

        .EXAMPLE
            Set-CustomizationLink -LinkPath ~/.copilot/skills -TargetPath ~/OneDrive/CopilotAtelier/Skills -LinkItemType Junction

            Points the Copilot skill discovery folder at the canonical target.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([System.Void])]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $LinkPath,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $TargetPath,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Junction', 'SymbolicLink')]
        [System.String]
        $LinkItemType,

        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $CreateOnly,

        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $Force
    )

    if (-not (Test-Path -LiteralPath $TargetPath))
    {
        Write-Information -MessageData "Skipped link: target missing - $TargetPath"

        return
    }

    $linkParent = Split-Path -Parent $LinkPath

    if (-not (Test-Path -LiteralPath $linkParent))
    {
        New-Item -ItemType Directory -Path $linkParent -Force | Out-Null

        Write-Information -MessageData "Created: $linkParent"
    }

    if (Test-Path -LiteralPath $LinkPath)
    {
        if ($CreateOnly)
        {
            Write-Information -MessageData "Skipped link: '$LinkPath' already exists and belongs to another tool."

            return
        }

        $item = Get-Item -LiteralPath $LinkPath -Force
        $isLink = $item.Attributes.HasFlag([System.IO.FileAttributes]::ReparsePoint)

        if ($isLink)
        {
            <#
                Stale or correct link: remove and recreate so it always points at
                the current target. Never use -Recurse on a reparse point, because
                Windows PowerShell follows the link and deletes the target tree.
            #>
            if ($PSCmdlet.ShouldProcess($LinkPath, 'Remove existing link'))
            {
                try
                {
                    [System.IO.Directory]::Delete($LinkPath, $false)
                }
                catch
                {
                    Remove-Item -LiteralPath $LinkPath -Force
                }

                Write-Information -MessageData "Removed existing link: $LinkPath"
            }
        }
        else
        {
            $children = @(Get-ChildItem -LiteralPath $LinkPath -Force -ErrorAction SilentlyContinue)

            if (-not $children)
            {
                if ($PSCmdlet.ShouldProcess($LinkPath, 'Remove empty directory'))
                {
                    Remove-Item -LiteralPath $LinkPath -Force

                    Write-Information -MessageData "Removed empty directory: $LinkPath"
                }
            }
            else
            {
                Write-Information -MessageData ''
                Write-Information -MessageData "Directory '$LinkPath' is not empty ($($children.Count) item(s))."
                Write-Information -MessageData "It must be replaced with a link to '$TargetPath'."

                <#
                    No console read. This function is reachable unattended
                    through Update-CopilotAtelier -Force, and a prompt there does
                    not fail, it waits forever on a host that may have no input
                    at all. The opt-in is a parameter, so an unattended caller
                    either supplies it or is told what to supply.
                #>
                if (-not $Force)
                {
                    Write-Information -MessageData "Skipped link: '$LinkPath' is not empty. Re-run with -Force to merge it into '$TargetPath' and replace it with a link."

                    return
                }

                if (-not $PSCmdlet.ShouldProcess($LinkPath, "Merge into '$TargetPath' and remove"))
                {
                    return
                }

                <#
                    Decide the whole merge before touching anything. The previous
                    version copied what it could and then deleted the directory,
                    so a child it had skipped was destroyed with it. Every child
                    that cannot be merged without loss is collected here and the
                    merge is abandoned intact.
                #>
                $blocker = [System.Collections.Generic.List[System.String]]::new()

                foreach ($child in $children)
                {
                    if ($child.Attributes.HasFlag([System.IO.FileAttributes]::ReparsePoint))
                    {
                        $blocker.Add("$($child.Name) is a reparse point; copying it would follow the link out of '$LinkPath'.")

                        continue
                    }

                    if ($child.PSIsContainer)
                    {
                        <#
                            Get-ChildItem does not descend through a reparse point
                            without -FollowSymlink, so this finds a nested link
                            without walking into whatever it addresses.
                        #>
                        $nestedLink = @(
                            Get-ChildItem -LiteralPath $child.FullName -Recurse -Force -ErrorAction SilentlyContinue |
                                Where-Object -FilterScript {
                                    $_.Attributes.HasFlag([System.IO.FileAttributes]::ReparsePoint)
                                }
                        )

                        if ($nestedLink)
                        {
                            $blocker.Add("$($child.Name) contains $($nestedLink.Count) reparse point(s), the first at '$($nestedLink[0].FullName)'.")

                            continue
                        }
                    }

                    $destinationChild = Join-Path -Path $TargetPath -ChildPath $child.Name

                    if (-not (Test-Path -LiteralPath $destinationChild))
                    {
                        continue
                    }

                    if ((Test-CustomizationChildMatch -Path $child.FullName -DestinationPath $destinationChild))
                    {
                        continue
                    }

                    $blocker.Add("$($child.Name) differs from the copy already in '$TargetPath'.")
                }

                if ($blocker.Count -gt 0)
                {
                    Write-Information -MessageData "Skipped link: '$LinkPath' cannot be merged without losing content."

                    foreach ($reason in $blocker)
                    {
                        Write-Information -MessageData "  $reason"
                    }

                    Write-Information -MessageData "Reconcile those item(s) by hand, then re-run. Nothing was copied or removed."

                    return
                }

                foreach ($child in $children)
                {
                    $destinationChild = Join-Path -Path $TargetPath -ChildPath $child.Name

                    if (Test-Path -LiteralPath $destinationChild)
                    {
                        Write-Information -MessageData "  Skip (identical copy already in target): $($child.Name)"

                        continue
                    }

                    Copy-Item -LiteralPath $child.FullName -Destination $destinationChild -Recurse -Force

                    Write-Information -MessageData "  Copied: $($child.Name) -> $TargetPath"
                }

                Remove-Item -LiteralPath $LinkPath -Recurse -Force

                Write-Information -MessageData "Removed: $LinkPath"
            }
        }
    }

    if ($PSCmdlet.ShouldProcess($LinkPath, "Create $LinkItemType to '$TargetPath'"))
    {
        New-Item -ItemType $LinkItemType -Path $LinkPath -Target $TargetPath | Out-Null

        Write-Information -MessageData "${LinkItemType}: $LinkPath -> $TargetPath"
    }
}
