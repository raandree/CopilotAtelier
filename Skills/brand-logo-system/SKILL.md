---
name: brand-logo-system
compatibility: Requires Windows with Microsoft Edge (used headless as the SVG rasterizer) and PowerShell 5.1+ with System.Drawing for verification. No design tool, font install, or network access is needed.
description: >-
  Designs a project's visual identity and renders it as editable SVG masters
  plus deterministic PNG deliverables, then exports the eleven-slot asset set
  a shared logo library expects. Covers deriving a palette and mark from a
  project's existing artwork, composing primary lockups, glyph-only marks, app
  icons, splash screens and monochrome variants, headless rasterisation at
  exact canvas sizes, and measured verification of dimensions, transparency,
  centring, and small-size legibility.
  USE FOR: create a logo or icon for a repository, design a brand mark or
  glyph, generate an app icon or favicon, build a logo system or brand board,
  produce light, dark and monochrome logo variants, render SVG to PNG at exact
  pixel sizes, add a project to a shared Logos folder, regenerate brand assets
  after the mark changes.
  DO NOT USE FOR: photo editing, marketing copy, architecture diagrams (use
  Mermaid), slide decks (use marp-slide-overflow), application screenshots
  (use windows-gui-screenshot-capture).
---

# Brand Logo System

Produce a complete, reproducible brand asset set for a software project: SVG masters as the source
of truth, PNG files as derived deliverables, and a design board that states the palette, the
concept, and the small-size behaviour. Every claim the board makes must be backed by a render.

## When to use

- "Generate an icon / logo for this repo."
- "Add this project to the shared Logos folder."
- "Make light and dark versions, an app icon, and a favicon."
- "Regenerate the brand assets, the mark changed."

## Outcome

Eleven PNG files in the library folder, named `<Initials> #<N> - <slot>.png`, all rendered from one
brand definition plus two or three glyph fragments, with dimensions, alpha, centring, and
small-size legibility verified by measurement rather than by eye.

## Dependencies

- [`scripts/Export-BrandLogoSet.ps1`](scripts/Export-BrandLogoSet.ps1) - definition-driven renderer.
- Microsoft Edge at `%ProgramFiles(x86)%\Microsoft\Edge\Application\msedge.exe`.
- `System.Drawing` for pixel verification (`Add-Type -AssemblyName System.Drawing`).

## Step 1 - Ground the identity in real artwork

Never invent a brand for a project that already has one. Before designing anything:

1. Search the repository for existing marks: `Assets/`, `docs/`, `.github/`, `*.png`, `*.svg`,
   `image.png`, README image links.
2. If a mark exists, extract its palette by counting pixels rather than sampling by eye:

```powershell
Add-Type -AssemblyName System.Drawing
$bmp = [Drawing.Bitmap]::FromFile($logoPath)
$counts = @{}
for ($y = 0; $y -lt $bmp.Height; $y++) {
    for ($x = 0; $x -lt $bmp.Width; $x++) {
        $p = $bmp.GetPixel($x, $y)
        if ($p.A -lt 200) { continue }
        $key = '{0:X2}{1:X2}{2:X2}' -f $p.R, $p.G, $p.B
        $counts[$key] = 1 + $counts[$key]
    }
}
$bmp.Dispose()
$counts.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 8
```

   Anti-aliasing produces thousands of near-duplicates; the handful with percentage-level shares are
   the real palette. Map them onto `Ink`, `Primary`, `Accent`, `Soft`, `White`.
3. Redraw the mark as clean vector geometry in a `0 0 100 100` viewBox. Compute repetitive geometry
   (gear teeth, radial arrays) mathematically instead of estimating coordinates.
4. Only when no mark exists, design one. State the subject before the tool: the symbol should read
   as what the project *does*.

## Step 2 - Author the brand definition

One `.psd1` plus two glyph fragments per project. Fragments are bare SVG element lists that the
renderer injects into a `<symbol viewBox="0 0 100 100">`.

```powershell
@{
    Name           = 'Contoso'
    Initials       = 'CT'          # filename prefix in the library
    WordmarkLead   = 'Con'         # line 1 / first colour
    WordmarkTail   = 'toso'        # line 2 / accent colour
    Tagline        = 'SHORT CAPITALISED CLAIM'
    Palette        = @{ Ink = '#003F6F'; Primary = '#1164AE'; Accent = '#4A81C2'
                        Soft = '#E6F3FC'; White = '#FFFFFF' }
    GlyphColorPath = 'glyph-color.svg'   # full-colour, self-contained
    GlyphMonoPath  = 'glyph-mono.svg'    # single colour via currentColor
    Concept        = @('Line one.', 'Line two.')   # <= ~50 chars per line
}
```

Rules for the fragments:

- The colour fragment carries its own `fill`/`stroke` values and may include `<defs>` with
  `clipPath`. It is injected into a symbol once per document, so ids do not collide across uses.
- The mono fragment must use `currentColor` only, so the renderer can tint it white or brand-colour.
- Punch holes with a second subpath plus `fill-rule="evenodd"` rather than stacking a
  background-coloured shape, which breaks on non-white surfaces.

## Step 3 - Render

```powershell
& '<skill>/scripts/Export-BrandLogoSet.ps1' `
    -DefinitionPath .\source\brand.psd1 `
    -DestinationPath 'C:\Users\<user>\Downloads\Logos\Contoso'
```

Keep the definition and fragments in a `source/` subfolder of the library folder so the set stays
reproducible without modifying the project repository - which matters when the project is not
yours to change.

## Step 4 - Verify by measurement

Never accept a render you have not measured *and* looked at. Assert, per file:

| Check | Rule |
|---|---|
| Count | Exactly 11 files |
| Naming | Matches `^<Initials> #\d+ - .+\.png$` |
| Slot parity | Slot numbers equal a sibling project's slot numbers |
| Size | Landscape 1536x1024, square 1254x1254 |
| Alpha | Transparent slots corner alpha 0; opaque slots corner alpha 255 |
| Bounds | Painted content never reaches the canvas edge |
| Centring | Horizontal skew within ~3% of canvas width |

Then open the board and at least one composed slot with an image viewer. Measurement catches
scaling and alpha faults; only viewing catches a broken layout or an overlapping label.

For small-size legibility, measure ink coverage of the favicon glyph at 32 px and 16 px. Coverage
that collapses toward 0 or saturates toward 100 means the glyph has dissolved or blobbed.

## The eleven slots

| # | Slot | Canvas | Background | Artwork |
|---|---|---|---|---|
| 0 | Full Design Board | 1536x1024 | white | board |
| 1 | Primary logo, dark mode | 1536x1024 | transparent | reversed lockup |
| 2 | Primary logo, light mode | 1536x1024 | transparent | colour lockup |
| 3 | Glyph-only, dark mode | 1254x1254 | transparent | reversed glyph |
| 4 | Glyph-only, light mode | 1254x1254 | transparent | colour glyph |
| 5 | App icon, dark mode | 1254x1254 | transparent | ink tile |
| 6 | App icon, light mode | 1254x1254 | transparent | white tile |
| 7 | Splash, dark mode | 1536x1024 | ink | full lockup |
| 8 | Splash, light mode | 1536x1024 | white | full lockup |
| 9 | Monochrome on white | 1254x1254 | white | one colour |
| 10 | Monochrome white on brand | 1254x1254 | primary | white |

"Dark mode" means the asset is *for* dark surfaces, so it is the reversed artwork. A dark-mode file
previewed on a white background looks nearly empty; that is correct, not a fault.

The slot name for 7 and 8 contains a **double space** (`Splash  start screen`), inherited from a
`/` stripped out of the original library. Reproduce it exactly.

The board's own cell numbering does not match the file slot numbering - the board orders dark
variants first, then light. Sibling boards share this quirk; keep it for family consistency.

## Pitfalls measured in practice

- **Never text-substitute `width=`/`height=` to resize an SVG.** The pattern also matches every
  nested `<use>` and `<rect>`, silently scaling each to the full canvas. Set the attributes on the
  root element only, via `XmlDocument.DocumentElement.SetAttribute`.
- **Do not copy a sibling asset's transparency.** Library assets are frequently opaque PNGs with a
  checkerboard painted into the pixels; one measured set had 0% transparent pixels. Verify with
  `IsAlphaPixelFormat` plus a corner-pixel alpha read, and emit a real alpha channel.
- **Quote `--window-size`.** In PowerShell a comma inside an argument built from subexpressions
  splits it into two arguments, and Edge silently falls back to a default size.
- **A detailed mark dies below about 32 px.** Supply an optional `GlyphFaviconPath` with a chunky
  reduced glyph, and set `ScalabilityNote` to state what actually happens. Do not let the board
  claim the mark "holds its silhouette" unless a 16 px render proves it.
- **Inter is usually not installed** and resolves silently to a fallback. Label the typography block
  with the face that actually renders, and verify by measuring text width against a deliberately
  nonexistent family.
- **Respect `.gitattributes`.** Repositories commonly force `*.svg eol=lf` while `*.ps1` stays
  `crlf`; normalise before committing or `git diff --check` warns on every file.

## Edge cases

- **Project has a logo but no vector source.** Redraw from the raster; never embed the raster.
- **Wordmark is a single word.** Put it in `WordmarkLead` and leave `WordmarkTail` empty; the second
  text line renders empty rather than breaking layout.
- **Palette has fewer than five distinct colours.** Duplicate the nearest neighbour rather than
  inventing a colour the project does not use.
- **Library folder already contains a set.** Delete the PNGs before re-rendering so a renamed slot
  cannot leave an orphan behind.
- **Long wordmark overflows the lockup.** Reduce the wordmark font size in the composer rather than
  shrinking the glyph; the glyph is the recognisable element.
