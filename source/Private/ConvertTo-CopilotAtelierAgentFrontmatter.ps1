function ConvertTo-CopilotAtelierAgentFrontmatter
{
    <#
        .SYNOPSIS
            Renders parsed Custom agent fields back into the strict YAML subset
            that ConvertFrom-CopilotAtelierAgentFrontmatter accepts.

        .DESCRIPTION
            Re-emitting a raw source line is how a composed file inherits a
            quoting style that no longer matches its new value. This function
            renders from the decoded value instead: a string is single-quoted
            with doubled inner quotes, a boolean stays a plain scalar so it does
            not become the string "true", and a sequence becomes a flow list of
            single-quoted items.

            A field the parser could not interpret is refused rather than
            approximated, and so is a value that would break the block, because
            a frontmatter block that does not reparse is not a profile.

        .PARAMETER Field
            An ordered map of field name to an object carrying Type and Value,
            in the order the fields should be emitted.

        .OUTPUTS
            System.String

        .EXAMPLE
            ConvertTo-CopilotAtelierAgentFrontmatter -Field $field

            Returns the frontmatter lines, without the delimiters.
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.Collections.IDictionary]
        $Field
    )

    $ErrorActionPreference = 'Stop'

    $quote = {
        param
        (
            [System.String] $Text,
            [System.String] $Name
        )

        if ($Text -match "[`r`n]")
        {
            throw "The value of field '$Name' spans more than one line, which the strict frontmatter subset cannot emit."
        }

        "'" + $Text.Replace("'", "''") + "'"
    }

    $line = foreach ($name in $Field.Keys)
    {
        $entry = $Field[$name]

        switch ($entry.Type)
        {
            'Boolean'
            {
                "$($name): $(if ($entry.Value) { 'true' } else { 'false' })"
            }

            'Sequence'
            {
                $item = @(
                    $entry.Value |
                        ForEach-Object -Process { & $quote ([System.String] $_) $name }
                )

                "$($name): [$($item -join ', ')]"
            }

            'String'
            {
                "$($name): $(& $quote ([System.String] $entry.Value) $name)"
            }

            default
            {
                throw "The field '$name' is '$($entry.Type)' and cannot be re-emitted. A field whose shape was not interpreted is never composed into a client variant."
            }
        }
    }

    return (@($line) -join "`n")
}
