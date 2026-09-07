function Resolve-CopilotAtelierDeploymentSelection
{
    <#
        .SYNOPSIS
            Reads the Deployment record, applies the selection inheritance
            rules, and resolves the Skill selection a deployment should use.

        .DESCRIPTION
            Combines the caller's explicit selection arguments with the
            selection the target already records, resolves the result, and
            returns it together with the plan filter and the record shape the
            deployment writes.

            Inheritance: without any selection argument the recorded profile and
            per-Skill adjustments are reused unchanged, so a reinstall or update
            never silently re-expands a narrowed installation. With any
            selection argument the per-Skill adjustments are restated in full
            and only the recorded base profile is inherited, so
            -InstallationProfile complete really does return to the complete
            installation.

            The function only reads. Because the recorded selection can change
            between an unlocked read and the deployment itself, a caller resolves
            once before the first write to reject an invalid explicit request,
            then again under the deployment lock to deploy the selection the
            record actually holds.

        .OUTPUTS
            System.Management.Automation.PSCustomObject

        .EXAMPLE
            Resolve-CopilotAtelierDeploymentSelection -ContentPath $content -TargetPath $target -Request @{ InstallationProfile = 'research' }

            Resolves the research selection for that target.
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
        [ValidateNotNullOrEmpty()]
        [System.String]
        $TargetPath,

        [Parameter()]
        [AllowNull()]
        [System.Collections.Hashtable]
        $Request
    )

    $recordedSelection = $null
    try
    {
        $existingRecord = Get-CopilotAtelierDeploymentRecord -TargetPath $TargetPath -Raw

        if ($existingRecord -and $existingRecord.SchemaVersion -eq 1)
        {
            $recordedSelection = $existingRecord.Selection
        }
    }
    catch
    {
        Write-Verbose -Message "No usable recorded Skill selection: $($_.Exception.Message)"
    }

    $selectionParameter = @{ ContentPath = $ContentPath }
    $requestedName = @(
        @('InstallationProfile', 'IncludeSkill', 'ExcludeSkill') |
            Where-Object -FilterScript { $null -ne $Request -and $Request.ContainsKey($_) }
    )

    if ($requestedName.Count -gt 0)
    {
        foreach ($parameterName in $requestedName)
        {
            $selectionParameter[$parameterName] = $Request[$parameterName]
        }

        if ($requestedName -notcontains 'InstallationProfile' -and $recordedSelection -and $recordedSelection.Profile)
        {
            $selectionParameter['InstallationProfile'] = $recordedSelection.Profile
        }
    }
    elseif ($recordedSelection)
    {
        if ($recordedSelection.Profile)
        {
            $selectionParameter['InstallationProfile'] = $recordedSelection.Profile
        }

        foreach ($parameterName in @('IncludeSkill', 'ExcludeSkill'))
        {
            $recordedValue = @($recordedSelection.$parameterName | Where-Object -FilterScript { $_ })

            if ($recordedValue.Count -gt 0)
            {
                $selectionParameter[$parameterName] = $recordedValue
            }
        }
    }

    $resolved = Resolve-CopilotAtelierSkillSelection @selectionParameter

    $planFilter = $null
    $recordSelection = $null

    if (-not $resolved.IsComplete)
    {
        # The deployed directory name, not the source path, is what the plan filters on.
        $planFilter = @{ 'skills' = @($resolved.Skill) }
        $recordSelection = [pscustomobject] @{
            Profile      = $resolved.Profile
            Skill        = @($resolved.Skill)
            IncludeSkill = @($resolved.IncludeSkill)
            ExcludeSkill = @($resolved.ExcludeSkill)
        }
    }

    return [pscustomobject] @{
        Profile               = $resolved.Profile
        Skill                 = @($resolved.Skill)
        AvailableSkill        = @($resolved.AvailableSkill)
        MandatorySkill        = @($resolved.MandatorySkill)
        IsComplete            = $resolved.IsComplete
        PrerequisiteValidated = $resolved.PrerequisiteValidated
        PlanFilter            = $planFilter
        RecordSelection       = $recordSelection
    }
}
