---
name: brand-logo-system
compatibility: Requires Windows with Microsoft Edge (used headless as the SVG rasterizer) and PowerShell 5.1+ with System.Drawing for verification. No design tool, font install, or network access is needed.
description: >-
  Designs a project's visual identity, renders SVG masters and PNG
  deliverables, exports the eleven-slot set a shared logo library expects, and
  wires the chosen variants into the project itself. Covers palette
  extraction, lockups, glyph marks, app icons, monochrome variants, and
  measured verification.
  USE FOR: create a logo or icon for a repository, design a brand mark or
  glyph, generate an app icon or favicon, build a brand board, produce light,
  dark and monochrome variants, render SVG to PNG at exact sizes, add a
  project to a shared Logos folder, regenerate assets after the mark changes,
  put the mark in a README header or fix one that wastes space, give a package
  its icon so a gallery entry stops showing a placeholder, set a repository
  social preview.
  DO NOT USE FOR: photo editing, marketing copy, architecture diagrams (use
  Mermaid), slide decks (use marp-slide-overflow), screenshots (use
  windows-gui-screenshot-capture), logos inside generated reports (use
  pswritehtml-reporting).
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
- "Put the logo in the README." / "The header takes too much space."
- "Our package has no icon on the gallery."

## Outcome

Eleven PNG files in the library folder, named `<Initials> #<N> - <slot>.png`, all rendered from one
brand definition plus two or three glyph fragments, with dimensions, alpha, centring, and
small-size legibility verified by measurement rather than by eye. When the user names a project to
integrate, that repository also carries the variants it needs and renders them in its README,
package metadata, and social preview.

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

## Step 5 - Integrate into the project

Steps 1-4 produce a library set and touch no repository. Integration is the opposite: it writes
into a project. Do it only when the user asks for it and only against a repository they have named.

### Ask which project, do not infer one

The library folder holds many projects and a session often has several repositories in view, so the
target is rarely implied by "add the logo". Ask before writing, following
[`Reference/interactive-questions.md`](../../Reference/interactive-questions.md): use
`vscode_askQuestions` when it is available, and fall back to plain bullets when it is not.

Ask, in one cluster:

- Which repository receives the assets. Offer the open workspace folders as options, and leave
  freeform input on so the user can name a path that is not open.
- Which surfaces to wire: README header, package or manifest icon, GitHub social preview.

Never guess from "this repo" when more than one repository is open, and never write into a
repository the user has not named. A brand commit in the wrong project is noise the owner has to
find and revert.

### Copy only what the project uses

Copy into a repository-local `assets/` folder, and keep the library set as the source. A project
needs the wordmark pair, the glyph pair, one icon, and the social preview; it does not need the
board or the splash slots. Add an `assets/README.md` recording the palette, the file table, and the
rule for choosing a variant, so the next contributor does not recolour a mark by hand.

### README header

Float the wordmark left so the intro fills the space beside it, rather than stacking a centred
block above the text:

```html
<!-- markdownlint-disable MD033 MD041 -->
<picture>
  <source media="(prefers-color-scheme: dark)"
          srcset="assets/logo-wordmark-dark.png">
  <img align="left" width="300" alt="<Project> logo"
       src="assets/logo-wordmark-light.png">
</picture>
<!-- markdownlint-enable MD033 -->

<the intro paragraph, which wraps to the right of the mark>

<!-- markdownlint-disable MD033 -->
<br clear="left">
<!-- markdownlint-enable MD033 -->
```

- **A `<table>` cannot do this on github.com.** The obvious two-column layout draws a 1px border on
  every cell from GitHub's markdown CSS, and the inline style or `border="0"` that would remove it
  is stripped by the sanitiser. The float is the only borderless option that survives.
- `<br clear="left">` ends the float. Without it the next section wraps around the mark.
- The wordmark contains the project name, so it replaces the `<h1>` rather than sitting above one.
  That is why `MD041` stays disabled for the whole file while `MD033` is re-enabled after the
  picture. Re-adding a text heading beside a wordmark prints the name twice.
- Serve both variants through `<picture>`. Editor markdown previews mis-resolve
  `prefers-color-scheme`, so judge the result on github.com, not in the preview pane.

### Package and repository metadata

| Surface | Asset | Rule |
|---|---|---|
| PowerShell module `IconUri`, npm `icon`, NuGet `icon` | `icon-256.png` | A direct image URL, never a repository or release page. Raw hosting: `https://raw.githubusercontent.com/<owner>/<repo>/<branch>/assets/icon-256.png` |
| GitHub social preview | `social-preview.png` | 1280x640, opaque. Uploaded in repository settings; it is not a committed reference |
| Favicon or docs site | reduced glyph | Below 32 px use the chunky favicon glyph, not the detailed mark |

Size decides the variant, not the surface: at roughly 128 px and below the wordmark loses its
lettering, so use the glyph; below 32 px use the icon.

### Verify the integration

- Every referenced path resolves from the repository root. A README image that 404s on github.com
  still renders locally from a stale working copy.
- The metadata URL returns an image, not an HTML page. A repository URL pasted into `IconUri` is
  the common failure and the gallery silently shows a placeholder.
- Open the rendered README on github.com in both colour themes.
- Record the change where the project records changes; a header swap is user-visible.

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
- **The user says "add the logo" with several repositories open.** Ask which one. Do not infer from
  the active editor or the last repository discussed.
- **The project is not yours to change.** Render into the library only, and hand the user the
  README block and the metadata line to paste. Integration is opt-in, never a side effect of
  producing the assets.
- **The README already has a header.** Replace it rather than adding a second mark, and say in the
  change record what the old header was, so the swap is reviewable.
- **The repository is private.** A raw metadata URL will not resolve for anyone outside it. Say so
  rather than shipping a link that works only for the owner.
