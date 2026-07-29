function ConvertFrom-Jsonc
{
    <#
        .SYNOPSIS
            Parses a JSONC document into an object.

        .DESCRIPTION
            VS Code writes its configuration files as JSONC: JSON with line
            comments, block comments, and trailing commas. ConvertFrom-Json
            rejects all three, so the text is normalised before it is parsed.

            A document that is empty once the comments are removed returns
            $null rather than raising an error.

        .PARAMETER Text
            The raw JSONC document to parse.

        .OUTPUTS
            System.Management.Automation.PSObject

        .EXAMPLE
            ConvertFrom-Jsonc -Text (Get-Content -Path settings.json -Raw)

            Parses a VS Code settings file that contains comments.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [System.String]
        $Text
    )

    $cleaned = $Text -replace '(?m)^\s*//.*$', ''
    $cleaned = $cleaned -replace '/\*[\s\S]*?\*/', ''
    $cleaned = $cleaned -replace ',(\s*[}\]])', '$1'

    if ([System.String]::IsNullOrWhiteSpace($cleaned))
    {
        return $null
    }

    return ($cleaned | ConvertFrom-Json)
}
