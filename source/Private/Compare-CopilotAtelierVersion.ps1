function Compare-CopilotAtelierVersion
{
    <#
        .SYNOPSIS
            Orders two module versions, including their prerelease labels.

        .DESCRIPTION
            Compares two version strings such as 6.1.0 and 6.1.0-preview0024 by
            Semantic Versioning 2.0.0 precedence: the numeric version first, then
            a release above any of its prerelease versions, then the labels
            identifier by identifier, numeric identifiers by value and the others
            in ordinal order.

            Windows PowerShell 5.1 has no SemanticVersion type and a
            System.Version cannot hold a label, so the comparison is implemented
            here and behaves the same in Windows PowerShell 5.1 and PowerShell 7.

            Returns 1 when Version is newer than OtherVersion, -1 when it is
            older, and 0 when both have the same precedence.

        .PARAMETER Version
            The version to rank.

        .PARAMETER OtherVersion
            The version to rank it against.

        .OUTPUTS
            System.Int32

        .EXAMPLE
            Compare-CopilotAtelierVersion -Version '6.1.0-preview0024' -OtherVersion '6.1.0-preview0018'

            Returns 1, because preview0024 follows preview0018.
    #>
    [CmdletBinding()]
    [OutputType([System.Int32])]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $Version,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $OtherVersion
    )

    $left = ConvertFrom-CopilotAtelierVersion -Version $Version
    $right = ConvertFrom-CopilotAtelierVersion -Version $OtherVersion

    # System.Version ranks a missing component below zero, which would put 6.1 below 6.1.0.
    $leftNumber = [System.Version]::new($left.Version.Major, $left.Version.Minor, [System.Math]::Max($left.Version.Build, 0), [System.Math]::Max($left.Version.Revision, 0))
    $rightNumber = [System.Version]::new($right.Version.Major, $right.Version.Minor, [System.Math]::Max($right.Version.Build, 0), [System.Math]::Max($right.Version.Revision, 0))

    $order = $leftNumber.CompareTo($rightNumber)
    if ($order -ne 0)
    {
        return [System.Math]::Sign($order)
    }

    if ($left.Prerelease -ceq $right.Prerelease)
    {
        return 0
    }

    if (-not $left.Prerelease)
    {
        return 1
    }

    if (-not $right.Prerelease)
    {
        return -1
    }

    $leftIdentifier = $left.Prerelease.Split('.')
    $rightIdentifier = $right.Prerelease.Split('.')
    $sharedCount = [System.Math]::Min($leftIdentifier.Count, $rightIdentifier.Count)

    for ($index = 0; $index -lt $sharedCount; $index++)
    {
        $leftPart = $leftIdentifier[$index]
        $rightPart = $rightIdentifier[$index]
        $leftIsNumeric = [System.Text.RegularExpressions.Regex]::IsMatch($leftPart, '\A[0-9]+\z')
        $rightIsNumeric = [System.Text.RegularExpressions.Regex]::IsMatch($rightPart, '\A[0-9]+\z')

        if ($leftIsNumeric -and $rightIsNumeric)
        {
            # Length first, so identifiers beyond the range of Int64 still order by value.
            $leftPart = $leftPart.TrimStart('0')
            $rightPart = $rightPart.TrimStart('0')
            $order = $leftPart.Length.CompareTo($rightPart.Length)
            if ($order -eq 0)
            {
                $order = [System.String]::CompareOrdinal($leftPart, $rightPart)
            }
        }
        elseif ($leftIsNumeric)
        {
            $order = -1
        }
        elseif ($rightIsNumeric)
        {
            $order = 1
        }
        else
        {
            $order = [System.String]::CompareOrdinal($leftPart, $rightPart)
        }

        if ($order -ne 0)
        {
            return [System.Math]::Sign($order)
        }
    }

    return [System.Math]::Sign($leftIdentifier.Count.CompareTo($rightIdentifier.Count))
}
