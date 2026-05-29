# Mermaid Pre-Rendering for Marp Decks

> Reference for the `marp-slide-overflow` skill. Marp CLI has no built-in mermaid
> support; this file covers how to pre-render ` ```mermaid ` fences to SVG so they
> appear in HTML/PDF/PPTX exports.

## Contents

- [Why Marp does not render mermaid fences](#why-marp-does-not-render-mermaid-fences)
- [Option A — custom engine plugin (not recommended)](#option-a--marp-cli-with-a-custom-engine-plugin)
- [Option B — pre-render to SVG via mermaid-cli (recommended)](#option-b--pre-render-to-svg-via-mermaid-cli-recommended)
- [Mermaid syntax gotchas that only surface during pre-render](#mermaid-syntax-gotchas-that-only-surface-during-pre-render)
- [Detecting the regression](#detecting-the-regression)
- [Sizing pre-rendered diagrams so they dont dominate the slide](#sizing-pre-rendered-diagrams-so-they-dont-dominate-the-slide)

## Why Marp does not render mermaid fences

Marp CLI has **no built-in mermaid support**. A ` ```mermaid ` fenced code block in the markdown is emitted into the rendered HTML/PDF/PPTX as a literal `<pre><code class="language-mermaid">…</code></pre>` block — it is never converted to a diagram. There is no warning, no error, no `[WARN]` in the CLI output.

There are two reliable workarounds; the second is the recommended one.

## Option A — `marp-cli` with a custom engine plugin

Marp exposes `--engine` and Marpit plugins. A community plugin like `markdown-it-textual-uml` or `markdown-it-mermaid` can be wired in, but they all rely on **client-side mermaid.js running in the rendered HTML**, which:

- works only in `--html` output (mermaid.js needs a browser to execute);
- still produces a static `<pre>` in `--pdf` and `--pptx` because marp-cli runs Chromium *before* mermaid.js initialises — the screenshot/PDF is taken too early;
- requires `--allow-local-files` and inlined CDN scripts.

In practice this means mermaid blocks **never appear correctly in PPTX or PDF** with this approach. Do not waste time on it for slide decks that need to export.

## Option B — Pre-render to SVG via `mermaid-cli` (recommended)

Convert every ` ```mermaid ` block to an SVG file on disk during the deck-assembly step, then replace the fence with a plain `![](…)` image reference. Marp embeds SVGs reliably in all three export formats.

```powershell
# Inside build.ps1, after sections are concatenated but before marp is invoked.
$mermaidPattern = '(?ms)^```mermaid\r?\n(.*?)\r?\n```'
$matches = [regex]::Matches($content, $mermaidPattern)

if ($matches.Count -gt 0)
{
    $diagramsDir = Join-Path $Dist 'diagrams'
    $null = New-Item -ItemType Directory -Force -Path $diagramsDir
    $sha = [System.Security.Cryptography.SHA1]::Create()
    $replacements = @{}

    foreach ($m in $matches)
    {
        $src  = $m.Groups[1].Value
        # Content-hash the source so unchanged diagrams are cached between builds.
        $hash = [System.BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($src))).Replace('-','').Substring(0,12).ToLower()
        $svg  = Join-Path $diagramsDir "mmd-$hash.svg"
        if (-not (Test-Path $svg))
        {
            $mmd = Join-Path $diagramsDir "mmd-$hash.mmd"
            Set-Content -Path $mmd -Value $src -Encoding utf8
            & npx --yes -p @mermaid-js/mermaid-cli mmdc -i $mmd -o $svg -b transparent -q 2>$null | Out-Null
            if ($LASTEXITCODE -ne 0 -or -not (Test-Path $svg))
            {
                throw "mermaid-cli failed (hash $hash). Ensure puppeteer can launch Chromium."
            }
        }
        # CRITICAL: use a forward-slash *relative* path, not the Windows absolute path.
        # The Markdown image parser silently fails on backslashed absolute paths and
        # the HTML output shows a broken-image icon (PDF/PPTX may differ).
        $replacements[$m.Value] = "![diagram](diagrams/mmd-$hash.svg)"
    }
    foreach ($k in $replacements.Keys) { $content = $content.Replace($k, $replacements[$k]) }
}
```

## Mermaid syntax gotchas that only surface during pre-render

mermaid-cli will **abort the entire build** on a parse error. The most common offenders in slide content:

- **`{` and `}` inside a node label** — mermaid's flowchart parser treats `{` as the start of a diamond shape. Wrap the label in double quotes: `C["Add-LabMachineDefinition -ProxmoxProperties @{...}"]`.
- **`(` `)` `[` `]` in labels** — same rule; quote the label.
- **Backticks for inline code** — not supported in node labels; use plain text or HTML entities.
- **`<br/>` for line breaks** — works *only* inside quoted labels in recent mermaid versions; quote the label to be safe.

A label that works in GitHub's mermaid renderer may still fail in `mermaid-cli` because GitHub runs a more permissive client-side build. Always render through `mmdc` before shipping.

## Detecting the regression

If a deck previously rendered mermaid (e.g. via a different tool) and now shows code blocks where diagrams should be, grep the rendered HTML:

```powershell
Select-String -Path dist\deck.html -Pattern 'class="language-mermaid"'
```

Any match means the fence survived into the output — pre-rendering is missing or skipped that block.

## Sizing pre-rendered diagrams so they dont dominate the slide

`mmdc` emits SVGs at their **intrinsic** size — a `graph TB` with 4 nodes and 3 subgraphs easily renders 1200 px tall and pushes everything else off the 720 px viewBox. The fix has two parts:

1. **Constrain image height in the deck CSS** so any SVG (or PNG) auto-scales to fit:

   ```yaml
   style: |
     section img { max-width: 100%; max-height: 380px; height: auto; display: block; margin: 0.2em auto; }
     section.dense img, section.compact img { max-height: 320px; }
   ```

   `max-height: 380px` leaves room for a title + footer + 2–3 lines of body text on a 720 px slide. Adjust per layout.

2. **Prefer landscape (`graph LR`) over portrait (`graph TB`)** for slide decks. A landscape diagram uses the wide aspect ratio of 16:9 slides and stays short. If you must use `TB`, keep it to ≤ 4 nodes or split across two slides.

3. **Always verify with per-slide PNGs**, not just the HTML preview — the HTML preview scales the viewport and hides clipping:

   ```powershell
   npx --yes @marp-team/marp-cli@latest --allow-local-files --images png -o dist\png\slide.png dist\deck.assembled.md
   ```

   Then open the PNGs of every slide that contains a diagram or table and confirm the title, body text, and footer page number are all visible. If a diagram + table can't both fit, split into two slides — don't shrink the diagram below readable size.
