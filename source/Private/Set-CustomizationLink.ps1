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
            real directory is only replaced after the caller confirms, and its
            contents are merged into the target first without overwriting files
            already there.

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
        $CreateOnly
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

                if (-not $PSCmdlet.ShouldProcess($LinkPath, "Merge into '$TargetPath' and remove"))
                {
                    return
                }

                $answer = Read-Host -Prompt 'Copy its contents into the target and then delete it? [y/N]'

                if ($answer -notmatch '^(y|yes)$')
                {
                    Write-Information -MessageData "Skipped link: user declined to remove '$LinkPath'."

                    return
                }

                foreach ($child in $children)
                {
                    $destinationChild = Join-Path -Path $TargetPath -ChildPath $child.Name

                    if (Test-Path -LiteralPath $destinationChild)
                    {
                        Write-Information -MessageData "  Skip (already present in target): $($child.Name)"

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
