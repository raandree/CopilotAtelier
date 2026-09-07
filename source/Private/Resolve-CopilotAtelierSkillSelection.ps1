function Resolve-CopilotAtelierSkillSelection
{
    <#
        .SYNOPSIS
            Validates an installation profile request and resolves it to a
            closed set of Skill identifiers.

        .DESCRIPTION
            Reads the Skills the payload actually ships, applies the requested
            profile, adds explicit inclusions and their declared dependencies,
            removes explicit exclusions, and refuses a selection that would leave
            a selected Skill without a Skill it requires or would drop a
            mandatory lifecycle or security component.

            A Skill is a directory that carries a SKILL.md entry point. A
            narrowing request - any profile other than complete, or any
            inclusion or exclusion - is validated against the payload: a missing
            mandatory Skill, an unshipped dependency of a selected Skill, and an
            explicitly selected directory without an entry point are all
            refused. An argument-free complete installation deploys the payload
            as it is and reports PrerequisiteValidated as false rather than
            implying it checked anything.

            The function only reads. Every rejection happens before the caller
            writes anything, so an invalid request never reaches the deployment.

        .OUTPUTS
            System.Management.Automation.PSCustomObject

        .EXAMPLE
            Resolve-CopilotAtelierSkillSelection -ContentPath $path -InstallationProfile 'research'

            Returns the resolved Skill selection for the research profile.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $ContentPath,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $InstallationProfile = 'complete',

        [Parameter()]
        [AllowEmptyCollection()]
        [System.String[]]
        $IncludeSkill = @(),

        [Parameter()]
        [AllowEmptyCollection()]
        [System.String[]]
        $ExcludeSkill = @()
    )

    $catalog = Get-CopilotAtelierProfileCatalog
    $requestedInclude = @($IncludeSkill | Where-Object -FilterScript { -not [string]::IsNullOrWhiteSpace($_) })
    $requestedExclude = @($ExcludeSkill | Where-Object -FilterScript { -not [string]::IsNullOrWhiteSpace($_) })

    if (-not $catalog.Profile.Contains($InstallationProfile))
    {
        throw "Unknown installation profile '$InstallationProfile'. Available profiles: $(@($catalog.Profile.Keys) -join ', ')."
    }

    # Profile lookup is case-insensitive; record the catalog spelling, not the caller's.
    $InstallationProfile = @($catalog.Profile.Keys) |
        Where-Object -FilterScript { $_ -eq $InstallationProfile } |
        Select-Object -First 1

    <#
        A declared cycle is a catalog defect, not a user error: closure would
        still terminate, but the map would no longer describe a hierarchy anyone
        can reason about. Reject it here so it cannot reach a deployment.
    #>
    $visiting = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $settled = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($startName in $catalog.Dependency.Keys)
    {
        $walk = [System.Collections.Generic.Stack[object]]::new()
        $walk.Push([pscustomobject] @{ Name = $startName; Entering = $true })
        while ($walk.Count -gt 0)
        {
            $step = $walk.Pop()
            if (-not $step.Entering)
            {
                $null = $visiting.Remove($step.Name)
                $null = $settled.Add($step.Name)
                continue
            }
            if ($settled.Contains($step.Name))
            {
                continue
            }
            if (-not $visiting.Add($step.Name))
            {
                throw "Invalid Skill dependency catalog: dependency cycle through '$($step.Name)'."
            }
            $walk.Push([pscustomobject] @{ Name = $step.Name; Entering = $false })
            if ($catalog.Dependency.Contains($step.Name))
            {
                foreach ($target in $catalog.Dependency[$step.Name])
                {
                    $walk.Push([pscustomobject] @{ Name = $target; Entering = $true })
                }
            }
        }
    }

    $skillRoot = Join-Path -Path $ContentPath -ChildPath (Get-CopilotAtelierDirectoryMap)['skills']
    $availableName = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $usableName = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    if (Test-Path -LiteralPath $skillRoot -PathType Container)
    {
        foreach ($item in Get-ChildItem -LiteralPath $skillRoot -Directory -Force -ErrorAction Stop)
        {
            $availableName[$item.Name] = $item.Name

            # A directory is a Skill only when it carries the entry point a client loads.
            if (Test-Path -LiteralPath (Join-Path -Path $item.FullName -ChildPath 'SKILL.md') -PathType Leaf)
            {
                $usableName[$item.Name] = $item.Name
            }
        }
    }

    $unknownName = @(
        @($requestedInclude + $requestedExclude) |
            Where-Object -FilterScript { -not $availableName.ContainsKey($_) } |
            Select-Object -Unique
    )
    if ($unknownName.Count -gt 0)
    {
        throw "Unknown Skill identifier(s): $($unknownName -join ', '). Run Get-CopilotAtelierProfile to list the Skills this payload ships."
    }

    <#
        An exclusion may name any directory the payload holds, but selecting one
        that has no SKILL.md would deploy a folder no client can load.
    #>
    $unusableName = @(
        $requestedInclude |
            Where-Object -FilterScript { -not $usableName.ContainsKey($_) } |
            Select-Object -Unique
    )
    if ($unusableName.Count -gt 0)
    {
        throw "Cannot select the Skill(s): $($unusableName -join ', '). A selected directory must contain a SKILL.md entry point."
    }

    $excluded = [System.Collections.Generic.HashSet[string]]::new([string[]] $requestedExclude, [System.StringComparer]::OrdinalIgnoreCase)

    $conflicting = @($requestedInclude | Where-Object -FilterScript { $excluded.Contains($_) } | Select-Object -Unique)
    if ($conflicting.Count -gt 0)
    {
        throw "Skill(s) both included and excluded: $($conflicting -join ', '). Choose one side of the request."
    }

    $blocked = @($catalog.MandatorySkill | Where-Object -FilterScript { $excluded.Contains($_) })
    if ($blocked.Count -gt 0)
    {
        throw "Cannot exclude the mandatory lifecycle or security Skill(s): $($blocked -join ', '). The deployed Instructions and Custom agents load them by name."
    }

    $includesEverySkill = $catalog.Profile[$InstallationProfile].IncludesEverySkill

    <#
        Only a narrowing request can leave a selected Skill without something it
        needs, so only a narrowing request has its prerequisites enforced. An
        argument-free complete installation still deploys whatever the payload
        holds, exactly as the releases that predate profiles did - and says so
        through PrerequisiteValidated rather than implying it checked.
    #>
    $prerequisiteValidated = -not $includesEverySkill -or $requestedInclude.Count -gt 0 -or $requestedExclude.Count -gt 0

    $selected = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    if ($includesEverySkill)
    {
        foreach ($name in $availableName.Values)
        {
            $null = $selected.Add($name)
        }
    }
    else
    {
        # A payload may ship a subset of the catalog, so an absent Skill is not an error here.
        foreach ($name in $catalog.Profile[$InstallationProfile].Skill)
        {
            if ($usableName.ContainsKey($name))
            {
                $null = $selected.Add($usableName[$name])
            }
        }
    }

    foreach ($name in $requestedInclude)
    {
        $null = $selected.Add($usableName[$name])
    }

    $missingMandatory = [System.Collections.Generic.List[string]]::new()
    foreach ($name in $catalog.MandatorySkill)
    {
        if ($usableName.ContainsKey($name))
        {
            $null = $selected.Add($usableName[$name])
        }
        else
        {
            $missingMandatory.Add($name)
        }
    }

    if ($prerequisiteValidated -and $missingMandatory.Count -gt 0)
    {
        throw "This payload does not ship the mandatory lifecycle or security Skill(s): $($missingMandatory -join ', '). A narrowed installation cannot leave them out."
    }

    $pending = [System.Collections.Generic.Stack[string]]::new([string[]] @($selected))
    while ($pending.Count -gt 0)
    {
        $name = $pending.Pop()
        if (-not $catalog.Dependency.Contains($name))
        {
            continue
        }
        foreach ($target in $catalog.Dependency[$name])
        {
            if ($usableName.ContainsKey($target) -and $selected.Add($usableName[$target]))
            {
                $pending.Push($usableName[$target])
            }
        }
    }

    foreach ($name in $requestedExclude)
    {
        $null = $selected.Remove($name)
    }

    if ($prerequisiteValidated)
    {
        foreach ($name in $selected)
        {
            if (-not $catalog.Dependency.Contains($name))
            {
                continue
            }
            foreach ($target in $catalog.Dependency[$name])
            {
                if ($selected.Contains($target))
                {
                    continue
                }
                if (-not $usableName.ContainsKey($target))
                {
                    throw "The selected Skill '$name' requires '$target', which this payload does not ship. Exclude '$name' as well, or use a payload that ships '$target'."
                }
                throw "The selected Skill '$name' requires '$target'. Exclude '$name' as well, or drop the exclusion of '$target'."
            }
        }
    }

    $resolved = [string[]] @($selected)
    [System.Array]::Sort($resolved, [System.StringComparer]::Ordinal)

    $sortedInclude = [string[]] @($requestedInclude | Select-Object -Unique)
    [System.Array]::Sort($sortedInclude, [System.StringComparer]::Ordinal)

    $sortedExclude = [string[]] @($requestedExclude | Select-Object -Unique)
    [System.Array]::Sort($sortedExclude, [System.StringComparer]::Ordinal)

    return [pscustomobject] @{
        Profile = $InstallationProfile
        IncludeSkill = @($sortedInclude)
        ExcludeSkill = @($sortedExclude)
        Skill = @($resolved)
        AvailableSkill = @($usableName.Values | Sort-Object)
        MandatorySkill = @($catalog.MandatorySkill | Where-Object -FilterScript { $usableName.ContainsKey($_) })
        PrerequisiteValidated = $prerequisiteValidated
        IsComplete = $includesEverySkill -and $sortedExclude.Count -eq 0
    }
}
