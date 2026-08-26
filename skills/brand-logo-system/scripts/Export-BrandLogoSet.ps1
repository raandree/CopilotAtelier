<#
    .SYNOPSIS
        Renders a project brand asset set into the shared logo library layout.

    .DESCRIPTION
        Composes the eleven numbered assets the shared logo library expects
        from a single brand definition and two glyph fragments. Landscape
        assets are 1536x1024 and square assets are 1254x1254, and files are
        named '<Initials> #<N> - <slot>.png'.

        Slot semantics follow the industry meaning: a dark mode asset is the
        reversed artwork for dark surfaces, and a light mode asset is the
        full-colour artwork for light surfaces.

        Transparent slots are written with a real alpha channel.

    .PARAMETER DefinitionPath
        Path to the brand definition .psd1. See the skill for the schema.

    .PARAMETER DestinationPath
        Folder that receives the PNG files. Created when missing.

    .PARAMETER EdgePath
        Path to msedge.exe, used as the headless SVG rasterizer.

    .EXAMPLE
        .\Export-BrandLogoSet.ps1 -DefinitionPath .\brand.psd1 -DestinationPath C:\Logos\Contoso

    .OUTPUTS
        PSCustomObject. One record per rendered asset.
#>
[CmdletBinding(SupportsShouldProcess)]
[OutputType([PSCustomObject])]
param
(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [System.String]
    $DefinitionPath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [System.String]
    $DestinationPath,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [System.String]
    $EdgePath = (Join-Path -Path ${env:ProgramFiles(x86)} -ChildPath 'Microsoft\Edge\Application\msedge.exe')
)

$ErrorActionPreference = 'Stop'

$script:FontStack = "Inter, 'Segoe UI Variable Text', 'Segoe UI', system-ui, sans-serif"

function Get-BrandDefinition
{
    <#
        .SYNOPSIS
            Loads and validates a brand definition and its glyph fragments.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Path
    )

    $resolved = (Resolve-Path -LiteralPath $Path).ProviderPath
    $definition = Import-PowerShellDataFile -LiteralPath $resolved
    $root = Split-Path -Path $resolved -Parent

    foreach ($key in 'Name', 'Initials', 'WordmarkLead', 'WordmarkTail', 'Tagline', 'Palette', 'GlyphColorPath', 'GlyphMonoPath', 'Concept')
    {
        if (-not $definition.ContainsKey($key))
        {
            throw "Brand definition is missing the '$key' key."
        }
    }

    foreach ($colour in 'Ink', 'Primary', 'Accent', 'Soft', 'White')
    {
        if (-not $definition.Palette.ContainsKey($colour))
        {
            throw "Brand palette is missing the '$colour' colour."
        }
    }

    foreach ($pair in @(@('GlyphColorPath', 'GlyphColor'), @('GlyphMonoPath', 'GlyphMono')))
    {
        $fragmentPath = Join-Path -Path $root -ChildPath $definition[$pair[0]]

        if (-not (Test-Path -LiteralPath $fragmentPath -PathType Leaf))
        {
            throw "Glyph fragment not found: '$fragmentPath'."
        }

        $definition[$pair[1]] = [System.IO.File]::ReadAllText($fragmentPath)
    }

    # A detailed mark rarely survives 16 px. A project may supply a reduced
    # glyph; otherwise the small sizes reuse the monochrome one.
    if ($definition.ContainsKey('GlyphFaviconPath'))
    {
        $faviconPath = Join-Path -Path $root -ChildPath $definition.GlyphFaviconPath

        if (-not (Test-Path -LiteralPath $faviconPath -PathType Leaf))
        {
            throw "Glyph fragment not found: '$faviconPath'."
        }

        $definition['GlyphFavicon'] = [System.IO.File]::ReadAllText($faviconPath)
    }
    else
    {
        $definition['GlyphFavicon'] = $definition.GlyphMono
    }

    if (-not $definition.ContainsKey('ScalabilityNote'))
    {
        $definition['ScalabilityNote'] = 'Verify the smallest size against a real render.'
    }

    return $definition
}

function Get-SvgDocument
{
    <#
        .SYNOPSIS
            Wraps a body fragment in a sized SVG document carrying both glyphs.
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Collections.Hashtable]
        $Definition,

        [Parameter(Mandatory = $true)]
        [System.Int32]
        $Width,

        [Parameter(Mandatory = $true)]
        [System.Int32]
        $Height,

        [Parameter(Mandatory = $true)]
        [System.String]
        $Label,

        [Parameter(Mandatory = $true)]
        [System.String]
        $Body
    )

    return @"
<svg xmlns="http://www.w3.org/2000/svg"
     xmlns:xlink="http://www.w3.org/1999/xlink"
     width="$Width" height="$Height" viewBox="0 0 $Width $Height"
     role="img" aria-label="$Label">
  <defs>
    <style>
      .ui { font-family: $($script:FontStack); }
    </style>
    <symbol id="glyph-color" viewBox="0 0 100 100">
$($Definition.GlyphColor)
    </symbol>
    <symbol id="glyph-mono" viewBox="0 0 100 100">
$($Definition.GlyphMono)
    </symbol>
    <symbol id="glyph-favicon" viewBox="0 0 100 100">
$($Definition.GlyphFavicon)
    </symbol>
  </defs>
$Body
</svg>
"@
}

function Get-LockupBody
{
    <#
        .SYNOPSIS
            Composes the horizontal glyph-plus-wordmark lockup.
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Collections.Hashtable]
        $Definition,

        [Parameter(Mandatory = $true)]
        [System.String]
        $GlyphId,

        [Parameter(Mandatory = $true)]
        [System.String]
        $GlyphColor,

        [Parameter(Mandatory = $true)]
        [System.String]
        $LeadColor,

        [Parameter(Mandatory = $true)]
        [System.String]
        $TailColor
    )

    return @"
  <use xlink:href="#$GlyphId" x="300" y="340" width="330" height="330"
       style="color:$GlyphColor"/>
  <text x="680" y="480" class="ui" font-size="104" font-weight="700"
        fill="$LeadColor">$($Definition.WordmarkLead)</text>
  <text x="680" y="606" class="ui" font-size="104" font-weight="700"
        fill="$TailColor">$($Definition.WordmarkTail)</text>
"@
}

function Get-SplashBody
{
    <#
        .SYNOPSIS
            Composes a splash or start screen on an opaque background.
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Collections.Hashtable]
        $Definition,

        [Parameter(Mandatory = $true)]
        [System.String]
        $Background,

        [Parameter(Mandatory = $true)]
        [System.String]
        $LeadColor,

        [Parameter(Mandatory = $true)]
        [System.String]
        $RuleColor
    )

    $accent = $Definition.Palette.Accent

    return @"
  <rect width="1536" height="1024" fill="$Background"/>
  <use xlink:href="#glyph-color" x="638" y="196" width="260" height="260"
       style="color:$LeadColor"/>
  <text x="768" y="600" class="ui" font-size="92" font-weight="700"
        text-anchor="middle" fill="$LeadColor">$($Definition.WordmarkLead)</text>
  <text x="768" y="712" class="ui" font-size="92" font-weight="700"
        text-anchor="middle" fill="$accent">$($Definition.WordmarkTail)</text>
  <line x1="430" y1="784" x2="650" y2="784" stroke="$RuleColor" stroke-width="2"/>
  <line x1="886" y1="784" x2="1106" y2="784" stroke="$RuleColor" stroke-width="2"/>
  <text x="768" y="832" class="ui" font-size="24" font-weight="700"
        letter-spacing="3.4" text-anchor="middle" fill="$accent">$($Definition.Tagline)</text>
"@
}

function Get-MonochromeBody
{
    <#
        .SYNOPSIS
            Composes a single-colour lockup on an opaque background.
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Collections.Hashtable]
        $Definition,

        [Parameter(Mandatory = $true)]
        [System.String]
        $Background,

        [Parameter(Mandatory = $true)]
        [System.String]
        $MarkColor
    )

    return @"
  <rect width="1254" height="1254" fill="$Background"/>
  <use xlink:href="#glyph-mono" x="417" y="250" width="420" height="420"
       style="color:$MarkColor"/>
  <text x="627" y="800" class="ui" font-size="104" font-weight="700"
        text-anchor="middle" fill="$MarkColor">$($Definition.WordmarkLead)</text>
  <text x="627" y="920" class="ui" font-size="104" font-weight="700"
        text-anchor="middle" fill="$MarkColor">$($Definition.WordmarkTail)</text>
  <line x1="330" y1="978" x2="560" y2="978" stroke="$MarkColor" stroke-width="2"
        stroke-opacity="0.55"/>
  <line x1="694" y1="978" x2="924" y2="978" stroke="$MarkColor" stroke-width="2"
        stroke-opacity="0.55"/>
  <text x="627" y="1022" class="ui" font-size="22" font-weight="700"
        letter-spacing="3" text-anchor="middle" fill="$MarkColor"
        fill-opacity="0.85">$($Definition.Tagline)</text>
"@
}

function Get-BoardBody
{
    <#
        .SYNOPSIS
            Composes the landscape design board.
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Collections.Hashtable]
        $Definition
    )

    $ink = $Definition.Palette.Ink
    $primary = $Definition.Palette.Primary
    $accent = $Definition.Palette.Accent
    $soft = $Definition.Palette.Soft
    $white = $Definition.Palette.White
    $lead = $Definition.WordmarkLead
    $tail = $Definition.WordmarkTail

    $builder = [System.Text.StringBuilder]::new()

    [void]$builder.Append(@"
  <rect width="1536" height="1024" fill="$white"/>
  <text x="32" y="52" class="ui" font-size="28" font-weight="800"
        letter-spacing="0.4"><tspan fill="$ink">$($Definition.Name.ToUpperInvariant())</tspan><tspan
        fill="$accent"> &#8212; LOGO SYSTEM</tspan></text>
  <use xlink:href="#glyph-color" x="1074" y="18" width="44" height="44"/>
  <line x1="1134" y1="24" x2="1134" y2="58" stroke="$soft" stroke-width="1.2"/>
  <text x="1154" y="47" class="ui" font-size="13" font-weight="600"
        fill="$primary">$($Definition.Tagline)</text>
  <line x1="32" y1="88" x2="1504" y2="88" stroke="$soft" stroke-width="1.2"/>
"@)

    $row1 = @(
        @{ X = 32; Number = 1; Label = 'PRIMARY LOGO'; Sub = 'DARK MODE' }
        @{ X = 428; Number = 2; Label = 'GLYPH ONLY'; Sub = 'DARK MODE' }
        @{ X = 644; Number = 3; Label = 'FAVICON'; Sub = 'SQUARE' }
        @{ X = 810; Number = 4; Label = 'APP ICON'; Sub = 'DARK MODE' }
        @{ X = 1026; Number = 5; Label = 'SPLASH / START SCREEN'; Sub = 'DARK MODE' }
    )

    $row2 = @(
        @{ X = 32; Number = 6; Label = 'PRIMARY LOGO'; Sub = 'LIGHT MODE' }
        @{ X = 428; Number = 7; Label = 'GLYPH ONLY'; Sub = 'LIGHT MODE' }
        @{ X = 644; Number = 8; Label = 'APP ICON'; Sub = 'LIGHT MODE' }
        @{ X = 860; Number = 9; Label = 'MONOCHROME'; Sub = 'ONE COLOUR ON WHITE' }
        @{ X = 1176; Number = 10; Label = 'MONOCHROME'; Sub = 'WHITE ON BRAND' }
    )

    foreach ($set in @(@{ Cells = $row1; Y = 114 }, @{ Cells = $row2; Y = 482 }))
    {
        foreach ($cell in $set.Cells)
        {
            $badgeX = $cell.X + 11
            $textX = $cell.X + 30

            [void]$builder.Append(@"

  <circle cx="$badgeX" cy="$($set.Y)" r="11" fill="none" stroke="$accent" stroke-width="1.3"/>
  <text x="$badgeX" y="$($set.Y + 4)" class="ui" font-size="12" font-weight="700"
        text-anchor="middle" fill="$primary">$($cell.Number)</text>
  <text x="$textX" y="$($set.Y - 2)" class="ui" font-size="13" font-weight="700"
        letter-spacing="1.1" fill="$primary">$($cell.Label)</text>
  <text x="$textX" y="$($set.Y + 16)" class="ui" font-size="10.5" font-weight="600"
        letter-spacing="1.1" fill="#7A8CA8">$($cell.Sub)</text>
"@)
        }
    }

    # Row 1 artwork. The dark cells sit on an ink panel so the reversed
    # artwork is visible on the white board.
    [void]$builder.Append(@"

  <rect x="32" y="150" width="380" height="280" rx="10" fill="$ink"/>
  <use xlink:href="#glyph-mono" x="60" y="220" width="130" height="130"
       style="color:$white"/>
  <text x="210" y="268" class="ui" font-size="34" font-weight="700" fill="$white">$lead</text>
  <text x="210" y="312" class="ui" font-size="34" font-weight="700" fill="$accent">$tail</text>

  <rect x="428" y="150" width="200" height="280" rx="10" fill="$ink"/>
  <use xlink:href="#glyph-mono" x="478" y="230" width="100" height="100"
       style="color:$white"/>

  <use xlink:href="#glyph-favicon" x="697" y="200" width="44" height="44"
       style="color:$primary"/>
  <use xlink:href="#glyph-favicon" x="711" y="266" width="16" height="16"
       style="color:$primary"/>
  <text x="719" y="300" class="ui" font-size="10.5" font-weight="600"
        letter-spacing="1.1" text-anchor="middle" fill="#7A8CA8">16 PX ACTUAL</text>

  <rect x="840" y="190" width="140" height="140" rx="32" fill="$ink"/>
  <use xlink:href="#glyph-color" x="858" y="208" width="104" height="104"/>

  <rect x="1026" y="150" width="478" height="280" rx="10" fill="$ink"/>
  <use xlink:href="#glyph-color" x="1227" y="176" width="76" height="76"/>
  <text x="1265" y="296" class="ui" font-size="26" font-weight="700"
        text-anchor="middle" fill="$white">$lead</text>
  <text x="1265" y="330" class="ui" font-size="26" font-weight="700"
        text-anchor="middle" fill="$accent">$tail</text>
  <line x1="1090" y1="358" x2="1180" y2="358" stroke="$accent" stroke-width="1.2"/>
  <line x1="1350" y1="358" x2="1440" y2="358" stroke="$accent" stroke-width="1.2"/>
  <text x="1265" y="386" class="ui" font-size="10" font-weight="700"
        letter-spacing="1.4" text-anchor="middle" fill="$accent">$($Definition.Tagline)</text>

  <line x1="32" y1="452" x2="1504" y2="452" stroke="$soft" stroke-width="1.2"/>
"@)

    # Row 2 artwork.
    [void]$builder.Append(@"

  <use xlink:href="#glyph-color" x="44" y="540" width="130" height="130"/>
  <text x="192" y="592" class="ui" font-size="34" font-weight="700" fill="$ink">$lead</text>
  <text x="192" y="636" class="ui" font-size="34" font-weight="700" fill="$accent">$tail</text>

  <use xlink:href="#glyph-color" x="478" y="552" width="100" height="100"/>

  <rect x="674" y="550" width="140" height="140" rx="32" fill="$white"
        stroke="$soft" stroke-width="2"/>
  <use xlink:href="#glyph-color" x="692" y="568" width="104" height="104"/>

  <rect x="860" y="550" width="300" height="150" rx="10" fill="$white"
        stroke="$soft" stroke-width="1.2"/>
  <use xlink:href="#glyph-mono" x="886" y="586" width="72" height="72"
       style="color:$primary"/>
  <text x="972" y="618" class="ui" font-size="21" font-weight="700" fill="$primary">$lead</text>
  <text x="972" y="646" class="ui" font-size="21" font-weight="700" fill="$primary">$tail</text>

  <rect x="1176" y="550" width="328" height="150" rx="10" fill="$primary"/>
  <use xlink:href="#glyph-mono" x="1204" y="586" width="72" height="72"
       style="color:$white"/>
  <text x="1290" y="618" class="ui" font-size="21" font-weight="700" fill="$white">$lead</text>
  <text x="1290" y="646" class="ui" font-size="21" font-weight="700" fill="$white">$tail</text>

  <line x1="32" y1="756" x2="1504" y2="756" stroke="$soft" stroke-width="1.2"/>
  <text x="32" y="788" class="ui" font-size="13" font-weight="700"
        letter-spacing="1.1" fill="$primary">CONCEPT</text>
"@)

    $conceptY = 816

    foreach ($line in $Definition.Concept)
    {
        [void]$builder.Append(@"

  <text x="32" y="$conceptY" class="ui" font-size="12.5" font-weight="500" fill="$ink">$line</text>
"@)
        $conceptY += 20
    }

    $swatches = @(
        @{ X = 470; Colour = $ink; Role = 'Ink' }
        @{ X = 536; Colour = $primary; Role = 'Primary' }
        @{ X = 602; Colour = $accent; Role = 'Accent' }
        @{ X = 668; Colour = $soft; Role = 'Soft' }
        @{ X = 734; Colour = $white; Role = 'White' }
    )

    [void]$builder.Append(@"

  <text x="440" y="788" class="ui" font-size="13" font-weight="700"
        letter-spacing="1.1" fill="$primary">COLOR PALETTE (STRICT)</text>
"@)

    foreach ($swatch in $swatches)
    {
        $stroke = if ($swatch.Colour -eq $white) { " stroke=`"$soft`" stroke-width=`"1.2`"" } else { '' }

        [void]$builder.Append(@"

  <circle cx="$($swatch.X)" cy="852" r="26" fill="$($swatch.Colour)"$stroke/>
  <text x="$($swatch.X)" y="898" class="ui" font-size="11" font-weight="700"
        text-anchor="middle" fill="$ink">$($swatch.Colour)</text>
  <text x="$($swatch.X)" y="914" class="ui" font-size="10"
        text-anchor="middle" fill="#7A8CA8">$($swatch.Role)</text>
"@)
    }

    [void]$builder.Append(@"

  <text x="800" y="788" class="ui" font-size="13" font-weight="700"
        letter-spacing="1.1" fill="$primary">TYPOGRAPHY</text>
  <text x="800" y="866" class="ui" font-size="52" font-weight="800" fill="$ink">Aa</text>
  <text x="884" y="826" class="ui" font-size="13" font-weight="700" fill="$ink">Inter / DM Sans / Public Sans</text>
  <text x="884" y="846" class="ui" font-size="11" font-weight="500" fill="#7A8CA8">Geometric sans, neutral tracking</text>
  <text x="884" y="866" class="ui" font-size="11" font-weight="500" fill="#7A8CA8">Substitute shown: Segoe UI Variable</text>
  <text x="800" y="894" class="ui" font-size="12" font-weight="500" fill="$ink">ABCDEFGHIJKLMNOPQRSTUVWXYZ</text>
  <text x="800" y="914" class="ui" font-size="12" font-weight="500" fill="$ink">abcdefghijklmnopqrstuvwxyz</text>
  <text x="800" y="934" class="ui" font-size="12" font-weight="500" fill="$ink">0123456789 !?&amp;@#</text>

  <text x="1160" y="788" class="ui" font-size="13" font-weight="700"
        letter-spacing="1.1" fill="$primary">SCALABILITY</text>
  <use xlink:href="#glyph-color" x="1160" y="812" width="72" height="72"/>
  <use xlink:href="#glyph-color" x="1252" y="826" width="58" height="58"/>
  <use xlink:href="#glyph-favicon" x="1330" y="842" width="42" height="42"
       style="color:$primary"/>
  <use xlink:href="#glyph-favicon" x="1392" y="858" width="26" height="26"
       style="color:$primary"/>
  <text x="1196" y="902" class="ui" font-size="11" font-weight="700"
        text-anchor="middle" fill="$ink">1024 px</text>
  <text x="1281" y="902" class="ui" font-size="11" font-weight="700"
        text-anchor="middle" fill="$ink">128 px</text>
  <text x="1351" y="902" class="ui" font-size="11" font-weight="700"
        text-anchor="middle" fill="$ink">32 px</text>
  <text x="1405" y="902" class="ui" font-size="11" font-weight="700"
        text-anchor="middle" fill="$ink">16 px</text>
  <text x="1160" y="922" class="ui" font-size="10" fill="#7A8CA8">$($Definition.ScalabilityNote)</text>
"@)

    return $builder.ToString()
}

function Convert-SvgToPng
{
    <#
        .SYNOPSIS
            Rasterizes an SVG document with headless Microsoft Edge.
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Markup,

        [Parameter(Mandatory = $true)]
        [System.String]
        $OutputPath,

        [Parameter(Mandatory = $true)]
        [System.Int32]
        $Width,

        [Parameter(Mandatory = $true)]
        [System.Int32]
        $Height,

        [Parameter(Mandatory = $true)]
        [System.String]
        $BackgroundArgb,

        [Parameter(Mandatory = $true)]
        [System.String]
        $WorkingPath,

        [Parameter(Mandatory = $true)]
        [System.String]
        $Browser
    )

    $svgPath = Join-Path -Path $WorkingPath -ChildPath ('{0}.svg' -f [System.Guid]::NewGuid())
    $profilePath = Join-Path -Path $WorkingPath -ChildPath ('profile-{0}' -f [System.Guid]::NewGuid())

    [System.IO.File]::WriteAllText($svgPath, $Markup, [System.Text.UTF8Encoding]::new($false))

    $arguments = @(
        '--headless=new'
        '--disable-gpu'
        '--hide-scrollbars'
        '--no-first-run'
        "--user-data-dir=$profilePath"
        '--force-device-scale-factor=1'
        "--window-size=$Width,$Height"
        "--default-background-color=$BackgroundArgb"
        '--virtual-time-budget=4000'
        "--screenshot=$OutputPath"
        ([System.Uri]$svgPath).AbsoluteUri
    )

    & $Browser @arguments 2>$null | Out-Null

    if (-not (Test-Path -LiteralPath $OutputPath -PathType Leaf))
    {
        throw "Rendering produced no file for '$OutputPath'."
    }

    return $OutputPath
}

if (-not (Test-Path -LiteralPath $EdgePath -PathType Leaf))
{
    throw "Microsoft Edge was not found at '$EdgePath'."
}

$brand = Get-BrandDefinition -Path $DefinitionPath
$palette = $brand.Palette
$transparent = '00000000'
$opaque = 'FFFFFFFF'

$slots = @(
    @{ Number = 0; Name = 'Full Design Board'; Width = 1536; Height = 1024; Background = $opaque
        Body = { Get-BoardBody -Definition $brand } }
    @{ Number = 1; Name = 'Primary logo (wordmark + icon), dark mode'; Width = 1536; Height = 1024; Background = $transparent
        Body = { Get-LockupBody -Definition $brand -GlyphId 'glyph-mono' -GlyphColor $palette.White -LeadColor $palette.White -TailColor $palette.Accent } }
    @{ Number = 2; Name = 'Primary logo (wordmark + icon), light mode'; Width = 1536; Height = 1024; Background = $transparent
        Body = { Get-LockupBody -Definition $brand -GlyphId 'glyph-color' -GlyphColor $palette.Primary -LeadColor $palette.Ink -TailColor $palette.Accent } }
    @{ Number = 3; Name = 'Glyph-only, dark mode'; Width = 1254; Height = 1254; Background = $transparent
        Body = { "  <use xlink:href=`"#glyph-mono`" x=`"127`" y=`"127`" width=`"1000`" height=`"1000`" style=`"color:$($palette.White)`"/>" } }
    @{ Number = 4; Name = 'Glyph-only, light mode'; Width = 1254; Height = 1254; Background = $transparent
        Body = { '  <use xlink:href="#glyph-color" x="127" y="127" width="1000" height="1000"/>' } }
    @{ Number = 5; Name = 'App icon (rounded square), dark mode'; Width = 1254; Height = 1254; Background = $transparent
        Body = { @"
  <rect x="100" y="100" width="1054" height="1054" rx="232" fill="$($palette.Ink)"/>
  <use xlink:href="#glyph-color" x="257" y="257" width="740" height="740"/>
"@ } }
    @{ Number = 6; Name = 'App icon (rounded square), light mode'; Width = 1254; Height = 1254; Background = $transparent
        Body = { @"
  <rect x="100" y="100" width="1054" height="1054" rx="232" fill="$($palette.White)"
        stroke="$($palette.Soft)" stroke-width="6"/>
  <use xlink:href="#glyph-color" x="257" y="257" width="740" height="740"/>
"@ } }
    @{ Number = 7; Name = 'Splash  start screen, dark mode'; Width = 1536; Height = 1024; Background = $opaque
        Body = { Get-SplashBody -Definition $brand -Background $palette.Ink -LeadColor $palette.White -RuleColor $palette.Accent } }
    @{ Number = 8; Name = 'Splash  start screen, light mode'; Width = 1536; Height = 1024; Background = $opaque
        Body = { Get-SplashBody -Definition $brand -Background $palette.White -LeadColor $palette.Ink -RuleColor $palette.Soft } }
    @{ Number = 9; Name = 'Mono one colour on white'; Width = 1254; Height = 1254; Background = $opaque
        Body = { Get-MonochromeBody -Definition $brand -Background $palette.White -MarkColor $palette.Primary } }
    @{ Number = 10; Name = 'Mono white on brand'; Width = 1254; Height = 1254; Background = $opaque
        Body = { Get-MonochromeBody -Definition $brand -Background $palette.Primary -MarkColor $palette.White } }
)

if (-not (Test-Path -LiteralPath $DestinationPath -PathType Container))
{
    if ($PSCmdlet.ShouldProcess($DestinationPath, 'Create folder'))
    {
        $null = New-Item -Path $DestinationPath -ItemType Directory -Force
    }
}

$workingPath = Join-Path -Path $env:TEMP -ChildPath ('brand-logo-set-{0}' -f [System.Guid]::NewGuid())
$null = New-Item -Path $workingPath -ItemType Directory -Force

try
{
    foreach ($slot in $slots)
    {
        $fileName = '{0} #{1} - {2}.png' -f $brand.Initials, $slot.Number, $slot.Name
        $outputPath = Join-Path -Path $DestinationPath -ChildPath $fileName

        if (-not $PSCmdlet.ShouldProcess($outputPath, 'Render asset'))
        {
            continue
        }

        $markup = Get-SvgDocument -Definition $brand -Width $slot.Width -Height $slot.Height `
            -Label ('{0} {1}' -f $brand.Name, $slot.Name) -Body (& $slot.Body)

        $null = Convert-SvgToPng -Markup $markup -OutputPath $outputPath -Width $slot.Width `
            -Height $slot.Height -BackgroundArgb $slot.Background -WorkingPath $workingPath `
            -Browser $EdgePath

        [PSCustomObject]@{
            Slot = $slot.Number
            Name = $slot.Name
            Size = '{0}x{1}' -f $slot.Width, $slot.Height
            Path = $outputPath
        }
    }
}
finally
{
    Remove-Item -LiteralPath $workingPath -Recurse -Force -ErrorAction SilentlyContinue
}
