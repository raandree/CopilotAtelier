function Test-CustomizationChildMatch
{
    <#
        .SYNOPSIS
            Reports whether a merge candidate is already present in the target
            in a form that can be discarded without losing anything.

        .DESCRIPTION
            Set-CustomizationLink merges a non-empty discovery directory into
            the canonical target before replacing it with a link. A child that
            exists in both places may only be dropped when the target copy is
            provably the same content, so this answers that question and nothing
            else.

            Two files match when their hashes are equal. Anything else - a
            directory on either side, or a file facing a directory - is reported
            as a mismatch, because proving a whole tree equal is more expensive
            than asking the caller to reconcile it.

        .PARAMETER Path
            The child under the discovery directory.

        .PARAMETER DestinationPath
            The path the child would occupy in the target.

        .OUTPUTS
            System.Boolean

        .EXAMPLE
            Test-CustomizationChildMatch -Path ~/.copilot/prompts/a.md -TargetPath ~/CopilotAtelier/Prompts/a.md

            Returns $true when both files hold identical content.
    #>
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $Path,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $DestinationPath
    )

    $source = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    $destination = Get-Item -LiteralPath $DestinationPath -Force -ErrorAction Stop

    if ($source.PSIsContainer -or $destination.PSIsContainer)
    {
        return $false
    }

    if ($source.Length -ne $destination.Length)
    {
        return $false
    }

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -eq
        (Get-FileHash -LiteralPath $DestinationPath -Algorithm SHA256).Hash
}
