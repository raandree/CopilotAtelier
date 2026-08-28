$script:repoRoot = Split-Path -Parent $PSScriptRoot

$script:overlayCase = @(
    @{
        OverlayName = 'software-engineer-contoso.agent.md'
        BaseName    = 'software-engineer.agent.md'
    }
)

BeforeAll {
    $script:agentsPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'com.github.copilot/agents'

    <#
        A Markdown link from one agent to another is inert. VS Code resolves
        referenced *instructions* files into the prompt; an .agent.md is not
        one, so an overlay that only links its base inherits nothing at all.
        The base body is therefore inlined between markers, and this function
        reproduces the single transformation applied to it — drop the H1 and
        demote every H2 — so that drift fails here rather than silently in a
        chat session.
    #>
    function script:Get-ExpectedInheritedBody
    {
        [CmdletBinding()]
        [OutputType([string])]
        param
        (
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string]$Path
        )

        $line = @(Get-Content -LiteralPath $Path -Encoding UTF8)
        $delimiter = @(
            for ($index = 0; $index -lt $line.Count; $index++)
            {
                if ($line[$index] -eq '---') { $index }
            }
        )

        if ($delimiter.Count -lt 2)
        {
            throw "Missing frontmatter delimiters: $Path"
        }

        # Skip the closing delimiter, the H1, and the blank line beneath it.
        $body = $line[($delimiter[1] + 3)..($line.Count - 1)]

        return (($body | ForEach-Object { $_ -replace '^## ', '### ' }) -join "`n").Trim()
    }

    function script:Get-InlinedBody
    {
        [CmdletBinding()]
        [OutputType([string])]
        param
        (
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string]$Path,

            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string]$BaseName
        )

        $content = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        $pattern = '(?s)<!-- BEGIN INHERITED: {0} -->(?<body>.*?)<!-- END INHERITED: {0} -->' -f [regex]::Escape($BaseName)
        $match = [regex]::Match($content, $pattern)

        if (-not $match.Success)
        {
            return $null
        }

        # Git rewrites line endings on checkout, so compare content, not encoding.
        return ($match.Groups['body'].Value -replace "`r`n", "`n").Trim()
    }
}

Describe 'Custom agent inheritance' -Tag 'Unit' {
    It '<OverlayName> inlines <BaseName> between inheritance markers' -ForEach $script:overlayCase {
        $overlayPath = Join-Path $script:agentsPath $OverlayName

        script:Get-InlinedBody -Path $overlayPath -BaseName $BaseName |
            Should -Not -BeNullOrEmpty -Because 'a Markdown link to an .agent.md is never resolved into the prompt, so the base body has to be carried inline'
    }

    It '<OverlayName> carries the current <BaseName> body verbatim' -ForEach $script:overlayCase {
        <#
            Byte-exact so that any edit to the base agent breaks this test and
            forces a re-sync. An overlay quietly running a stale copy of its
            base is the failure this guards.
        #>
        $overlayPath = Join-Path $script:agentsPath $OverlayName
        $basePath = Join-Path $script:agentsPath $BaseName

        script:Get-InlinedBody -Path $overlayPath -BaseName $BaseName |
            Should -BeExactly (script:Get-ExpectedInheritedBody -Path $basePath)
    }

    It '<OverlayName> states which rules win when the overlay and <BaseName> disagree' -ForEach $script:overlayCase {
        $content = Get-Content -LiteralPath (Join-Path $script:agentsPath $OverlayName) -Raw -Encoding UTF8

        $content | Should -Match '(?i)only \*\*adds\*\* constraints'
        $content | Should -Match '(?i)stricter'
    }

    It '<OverlayName> names the overridden inherited defaults before the inlined block' -ForEach $script:overlayCase {
        <#
            The inlined base states its own defaults verbatim, so the overlay
            contradicts itself by construction. A precedence clause 180 lines
            later resolves it only if the reader gets there; naming the reversed
            defaults up front puts the correction ahead of the contradiction.
        #>
        $content = Get-Content -LiteralPath (Join-Path $script:agentsPath $OverlayName) -Raw -Encoding UTF8
        $markerIndex = $content.IndexOf(('<!-- BEGIN INHERITED: {0} -->' -f $BaseName))

        $markerIndex | Should -BeGreaterThan 0
        $preamble = $content.Substring(0, $markerIndex)

        $preamble | Should -Match '(?i)override'
        $preamble | Should -Match 'review: on'
    }
}
