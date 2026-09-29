function Get-EvalText {
    <#
    .SYNOPSIS
        Reads one UTF-8 evaluation input under a byte limit.
    .DESCRIPTION
        Checks the open file's length, then bounds the read itself to handle
        growth without allocating an unbounded string. Recognizes Unicode BOMs.
        This is an ingestion limit, not filesystem containment or a run timeout.
    .PARAMETER LiteralPath
        Exact path to the definition, sample, or reply file.
    .PARAMETER MaxBytes
        Maximum bytes in this file, including its byte-order mark if present.
    .EXAMPLE
        Get-EvalText -LiteralPath 'sample-1.txt' -MaxBytes 1MB
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $LiteralPath,

        [Parameter(Mandatory)]
        [ValidateRange(1, 104857600)]
        [int] $MaxBytes
    )

    $stream = [IO.File]::Open($LiteralPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        $tooLarge = "EvalInputTooLarge: '$LiteralPath' exceeds the $MaxBytes-byte per-file limit."
        if ($stream.Length -gt $MaxBytes) { throw [IO.InvalidDataException]::new($tooLarge) }
        $content = [IO.MemoryStream]::new()
        try {
            # A fixed buffer bounds growth checks without allocating the maximum allowed size up front.
            $buffer = [byte[]]::new(4096)
            do {
                $count = [int][Math]::Min($buffer.Length, $MaxBytes - $content.Length + 1)
                $read = $stream.Read($buffer, 0, $count)
                if ($content.Length + $read -gt $MaxBytes) {
                    throw [IO.InvalidDataException]::new($tooLarge)
                }
                $content.Write($buffer, 0, $read)
            } while ($read -gt 0)
            $content.Position = 0
            $reader = [IO.StreamReader]::new($content, [Text.Encoding]::UTF8, $true)
            try { $reader.ReadToEnd() }
            finally { $reader.Dispose() }
        }
        finally { $content.Dispose() }
    }
    finally { $stream.Dispose() }
}
