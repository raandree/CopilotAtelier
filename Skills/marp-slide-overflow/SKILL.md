---
name: marp-slide-overflow
description: >-
  Detect and fix silent content overflow in Marp slide decks before exporting to PPTX/PDF/PNG (anything taller than the 1280x720 viewBox is clipped with no warning). Also covers pre-rendering mermaid fences to SVG, a PNG-based visual verification workflow, a Puppeteer overflow detector, dense/compact CSS density tiers, a fillRatio decision table, and selectable-text PPTX export. USE FOR: Marp overflow, slide content clipped, content cut off in PPTX, slide overflow detection, Marp scrollHeight, dense/compact class, fillRatio, marp-cli overflow, Marp backgroundColor frontmatter, Marp mermaid not rendering, mermaid-cli mmdc, pre-render mermaid SVG, mermaid missing in PDF/PPTX, verify slide fits PNG, marp --images png, split slide vs shrink, editable PPTX, selectable text PPTX, marp pptx-editable, SOFFICE_PATH, LibreOffice PPTX, searchable PPTX, lessmsi MSI extract, winget 1618. DO NOT USE FOR: Reveal.js, Slidev, PowerPoint authoring, generic CSS layout, font rendering bugs.
---

# Marp Slide Overflow — Detect, Fix, Verify

## When to Use

- A Marp deck exports cleanly to HTML preview but **content is missing in PPTX/PDF/PNG**.
- Tables, code blocks, or long paragraphs look truncated in the rendered output.
- You added content to a slide and aren't sure if it still fits.
- You need a **CI gate** that fails the build if any slide overflows.
- You want a single browser-based view that puts source markdown next to the rendered slide image so you can review the entire deck quickly.

## The Root Cause: Silent Clipping

Marp wraps every slide in:

```html
<svg data-marpit-svg viewBox="0 0 1280 720">
  <foreignObject>
    <section>
      <!-- your slide content -->
    </section>
  </foreignObject>
</svg>
```

The `<section>` has `overflow: hidden` applied by the Marpit theme. Anything taller than 720 px is **silently clipped**. There is no warning in the Marp CLI output, no red error in the VS Code preview, no hint in the PPTX. The bottom of your table just isn't there.

This bites hardest when:

- A code block, table, or markdown list grows over time and crosses the 720 px threshold.
- A custom CSS theme reduces line-height or font-size in some places but not others, making overflow inconsistent.
- The deck builds from a single source file into multiple sub-decks (1h / 2h / 4h pattern), so the same slide may overflow in one variant but not another.

## The Detection Strategy

The **only** reliable way to detect overflow is to render the deck and measure each section's `scrollHeight` against the viewBox height. Line-count or character-count heuristics miss tables, code blocks with long lines, and CSS-driven layouts.

```
Marp source.md
    │
    ▼
marp --html → rendered.html       (one file with N <svg><section> per slide)
    │
    ▼
Headless Chromium (Puppeteer) loads rendered.html
    │
    ▼
For each <section>:
    contentHeight = section.scrollHeight   ← includes clipped overflow
    frameHeight   = svg.viewBox.height     ← the visible frame (720)
    overflowY     = max(0, contentHeight - frameHeight)
    fillRatio     = contentHeight / frameHeight
```

`scrollHeight` reports the **full** content height including the clipped portion, which is exactly the diagnostic we need.

## Gotcha: Marp does not render ` ```mermaid ` fences

Marp CLI has **no built-in mermaid support**. A ` ```mermaid ` fenced code block is emitted into the rendered HTML/PDF/PPTX as a literal `<pre><code class="language-mermaid">…</code></pre>` block — never a diagram, and with no warning. Client-side mermaid.js plugins only work in `--html` output; they leave a static `<pre>` in `--pdf`/`--pptx`. The reliable fix is to **pre-render every ` ```mermaid ` fence to an SVG on disk** during deck assembly (via `mermaid-cli` / `mmdc`) and replace the fence with a `![](…)` image reference, then constrain image height in CSS so the SVG fits the 720 px viewBox.

> **Full recipe** — `mmdc` pre-render script, mermaid syntax gotchas (`{}`/`()`/`[]` in labels, `<br/>`, backticks), regression detection, and diagram-sizing CSS: [`references/mermaid-prerender.md`](references/mermaid-prerender.md).

## Recipe 0: PNG-based visual verification (mandatory before claiming "fixed")

Text-heuristic overflow checks (counting `<li>` elements, total character length, raw `scrollHeight`) **miss the cases that matter most**: oversized images, tables with wrapped cells, code blocks with long lines. The **only** reliable signal that a slide actually fits is a rendered PNG of that slide:

1. Render every slide to PNG (`marp --images png --image-scale 1`) — one 1280×720 PNG per slide.
2. Flag at-risk slides programmatically (tables, images/SVGs, code blocks > ~6 lines, lists > ~7 bullets).
3. For each at-risk PNG check three invariants: **title visible** at top, **footer page number visible** at bottom-right, **no half-cut rows** at the bottom edge.
4. Fix (`dense`/`compact` class, content trim, or split), re-render, re-check until clean. Hand the PNGs to a fresh subagent with an adversarial prompt for a final pass.

> **Full recipe** — render/at-risk-detection scripts, the three-invariant checklist, the adversarial subagent QA prompt, and the "smoke alarm vs. gate" anti-patterns (heuristics and the HTML preview both lie): [`references/png-verification.md`](references/png-verification.md).

## Recipe 1: Minimal Overflow Detector (Node + Puppeteer)

The only reliable programmatic overflow check renders the deck to HTML and measures each `<section>`'s `scrollHeight` against the `viewBox` height in headless Chromium (`scrollHeight` includes the clipped overflow). A ~60-line `overflow-check.mjs` Puppeteer script emits per-slide `overflowY` / `overflowX` / `fillRatio` and exits non-zero when any slide overflows — wire it into the build as a gate.

> **Full recipe** — the complete `overflow-check.mjs` detector, its `package.json`, and the render → measure → cleanup build wiring: [`references/overflow-detector.md`](references/overflow-detector.md).

## Recipe 2: Two-Tier CSS Density Pattern

When a slide overflows, the first instinct is to split it. Resist that — slide count usually has semantic meaning (e.g. agenda timing). Instead, define **two density tiers** in the deck's frontmatter and tag overflowing slides with the appropriate class:

```css
/* Default slide: section { font-size: 24px } */

/* Tier 1: dense — moderate overflow (fillRatio 1.00–1.20) */
section.dense {
    font-size: 20px;
}
section.dense h1 { font-size: 1.4em; margin-bottom: 0.2em; }
section.dense h3 { font-size: 1.0em; margin-top: 0.2em; margin-bottom: 0.1em; }
section.dense pre { padding: 8px; font-size: 0.85em; }
section.dense blockquote { margin-top: 0.3em; margin-bottom: 0.3em; }

/* Tier 2: compact — heavy overflow (fillRatio 1.20–1.30) */
section.compact {
    font-size: 18px;
}
section.compact h1 { font-size: 1.3em; margin-bottom: 0.15em; padding-bottom: 0.1em; }
section.compact h2 { font-size: 1.15em; }
section.compact h3 { font-size: 0.95em; margin-top: 0.15em; margin-bottom: 0.1em; }
section.compact p  { margin-top: 0.4em; margin-bottom: 0.4em; }
section.compact pre { padding: 6px; font-size: 0.8em; }
section.compact table { font-size: 0.65em; }
section.compact th, section.compact td { padding: 3px 6px; }
section.compact blockquote { margin: 0.25em 0; padding: 0.4em 0.6em; }
section.compact ul, section.compact ol { margin-top: 0.25em; margin-bottom: 0.25em; }
section.compact li { margin-top: 0.1em; }
```

Apply to a slide via Marp's per-slide directive:

```markdown
---
<!-- _class: compact -->

# Slide That Used to Overflow

| col | col | col |
|-----|-----|-----|
| ... | ... | ... |
```

**Empirical capacity** (measured against the same content):

- Default → 100 %
- `dense`   → ~120 %
- `compact` → ~133 %

So `compact` gives ~13 % more capacity than `dense` and ~33 % more than the default theme.

## Recipe 3: fillRatio Decision Table

Read the `fillRatio` column from the detector and pick the smallest fix that works:

| fillRatio | What it means | Recommended fix |
|-----------|---------------|-----------------|
| ≤ 1.00     | Fits with room to spare | Nothing |
| 1.00–1.05 | Tiny overflow (rounding) | `<!-- _class: dense -->` |
| 1.05–1.20 | Moderate overflow | `<!-- _class: dense -->` |
| 1.20–1.30 | Heavy overflow | `<!-- _class: compact -->` |
| 1.30–1.40 | Severe overflow | `compact` + minor content trim |
| > 1.40    | Way over | Trim first (drop a section, condense bullets), then `compact`; split only if content is genuinely two ideas |

> **Rule of thumb**: anything below 5 px (`overflowY < 5`) is rendering rounding noise — leave it alone, the PPTX will look fine.

## Recipe 4: Side-by-Side Review Report

The detector tells you **which** slide overflows, but not **what** is being clipped. To review every slide visually without flipping through the binary PPTX:

1. Export the deck to PNGs once: `npx @marp-team/marp-cli@latest deck.md --images png --allow-local-files -o png-out/slide`. Marp produces `slide.001`, `slide.002`, etc. (no extension — rename with `Get-ChildItem | Where-Object { $_.Extension -ne '.png' } | Rename-Item -NewName { $_.FullName + '.png' }`).
2. Re-parse the source markdown into per-slide blocks (see "Phantom Section" gotcha below).
3. Generate one HTML file per deck variant with two columns per slide: `<pre>` of the source markdown, `<img>` of the rendered PNG, plus an OVERFLOW / fits badge from the detector results.
4. Add a sticky toolbar at the top with one-click links to the overflowing slides.

Open the HTML in any browser and scroll. Overflowing slides get a red left-border and a striped clip-marker bar across the bottom of the PNG, making them obvious at a glance. This is far faster than opening the PPTX, especially for decks with > 50 slides.

## Recipe 4b: Selectable-Text PPTX (`--pptx-editable`)

Marp's default `--pptx` export rasterises **one image per slide** — pixel-perfect but the
text is not selectable, searchable, or editable in PowerPoint. marp-cli's experimental
`--pptx-editable` flag instead emits **real text shapes** by shelling out to LibreOffice
(`soffice`).

```powershell
# Image PPTX (default): every slide is a bitmap, ~MBs, text NOT selectable
npx @marp-team/marp-cli@latest deck.md --allow-local-files -o deck.pptx

# Editable PPTX: real text shapes, ~KBs, selectable/searchable
$env:SOFFICE_PATH = 'C:\Program Files\LibreOffice\program\soffice.exe'  # if not on PATH
npx @marp-team/marp-cli@latest deck.md --pptx --pptx-editable --allow-local-files -o deck.editable.pptx
```

Key facts:

- **Requires LibreOffice.** marp shells out to `soffice`; it honours the `SOFFICE_PATH`
  env var, otherwise it must be on `PATH`. No LibreOffice = the flag silently does nothing
  useful or errors.
- **Ship both.** Keep the image PPTX when pixel fidelity matters; ship the editable PPTX
  when the audience needs to copy text, search, or re-style. They are different artefacts,
  not a replacement.
- **Fidelity caveat — code blocks reflow.** Prose, titles, headings, footers, and slide
  numbers render near-identically to the image deck. **Code/monospace blocks reflow and
  wrap** because LibreOffice does not embed the deck's monospace webfont. This is inherent
  to the experimental feature, not a bug you can fix in CSS.
- **Size tell.** The editable PPTX is typically ~40x smaller than the image PPTX (text
  shapes vs. embedded bitmaps) — a quick sanity check that the editable path actually ran.

### Verify the text really is selectable (not just a relabeled image PPTX)

A PPTX is a ZIP; slide text lives in `<a:t>` runs inside `ppt/slides/slideN.xml`. Zero
`<a:t>` runs means you got an image deck.

```powershell
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [IO.Compression.ZipFile]::OpenRead((Resolve-Path 'deck.editable.pptx').Path)
$slide1 = ($zip.Entries | Where-Object FullName -like 'ppt/slides/slide*.xml' | Sort-Object FullName)[0]
$sr = New-Object IO.StreamReader($slide1.Open()); $xml = $sr.ReadToEnd(); $sr.Close(); $zip.Dispose()
([regex]::Matches($xml, '<a:t>(.*?)</a:t>')).Count   # > 0 => selectable text
```

### Visually diff editable vs. image (reuse the PNG workflow)

1. Reference PNGs from marp: `npx @marp-team/marp-cli@latest deck.md --images png --allow-local-files -o ref/slide.png`.
2. Render the editable PPTX to PDF, then to PNG: `soffice --headless --convert-to pdf --outdir ed deck.editable.pptx`, then `pdftoppm -png -r 96 ed/deck.editable.pdf ed/slide` (pdftoppm ships with poppler / MiKTeX).
3. Pair `ref/slide.NNN.png` against `ed/slide-NN.png` in a two-column HTML report (Recipe 4) and scroll. Expect prose to match and code blocks to differ.

> **Provisioning LibreOffice on a locked/non-admin box:** if `winget install
> TheDocumentFoundation.LibreOffice` fails with MSI error **1618** ("another installation
> is already in progress") and you cannot elevate, download the LibreOffice MSI and extract
> it portably with `lessmsi x <msi> C:\LO_portable\` — no Windows Installer engine, no
> admin. Point `SOFFICE_PATH` at `C:\LO_portable\SourceDir\LibreOffice\program\soffice.exe`.
> First headless run self-initialises; isolate its profile with
> `-env:UserInstallation=file:///C:/LO_portable/profile`.

## Critical Gotcha: The Phantom Leading Section

When a Marp build script writes a slide separator (`---`) **immediately after the closing `---` of the YAML frontmatter**, Marp emits an empty leading `<section>` in the rendered HTML. Any tool that maps source-markdown slide indices to rendered slide numbers must include that phantom — otherwise everything is **off-by-one** for the rest of the deck.

### Detection

In your rendered HTML:

```powershell
$h = Get-Content rendered.html -Raw
[regex]::Matches($h, '<section\b').Count   # rendered section count
```

In your source markdown, count `---` separators (excluding the two frontmatter delimiters) and add 1 for the first slide. If the rendered count is exactly **one higher** than that, you've got a phantom.

### Fix in source-markdown slicer

When parsing the source for a side-by-side report, **always add an empty slide entry on the very first separator after the frontmatter**, even if the buffer is empty:

```powershell
# Wrong (off-by-one):
if ($cur.Count -gt 0) { $slides.Add(($cur -join "`n")) }

# Right (matches Marp pagination):
$slides.Add(($cur -join "`n").Trim("`n"))   # always add, even if empty
```

This was a real bug found in production tooling — slides 1..N had source/rendered swapped by one position, which made debugging "why does slide 23 show slide 22's content" extremely confusing until the section count and separator count were compared.

## Critical Gotcha: Frontmatter `backgroundColor` Wins Over Class CSS

Marp's YAML frontmatter `backgroundColor:` (and `color:`) directive is **not** translated to a CSS rule — it is injected as an **inline `style="..."` attribute on every `<section>` element**. Inline styles beat any class-based selector in the `style:` block, regardless of specificity. This silently breaks two common patterns:

1. **Section dividers with a coloured background**

   ```yaml
   ---
   marp: true
   backgroundColor: "#ffffff"
   color: "#1e293b"
   style: |
     section.section-divider {
       background: linear-gradient(135deg, #0c4a6e, #0369a1);
       color: #ffffff;
     }
     section.section-divider h1 { color: #ffffff; }
     section.section-divider h2 { color: #bae6fd; }
   ---
   ```

   The gradient is **never rendered**. The section still has the white inline background. The h1 stays `#ffffff` → **white-on-white, invisible headline**. The h2 stays `#bae6fd` → **light cyan on white, fails WCAG contrast** (~1.4:1, looks like a faded watermark).

2. **`<!-- _class: lead -->` slides expecting a tinted background**

   Same root cause — the `section.lead { background: ... }` rule is overridden by the inline style.

### How to detect it

Render the deck once with `marp-cli --html` and grep the output:

```powershell
$h = Get-Content rendered.html -Raw
# Inline style attribute on a section (not data-style):
$rx = [regex]'(?<![-\w])style="([^"]*)"'
$rx.Matches($h) | Select-Object -First 3 | ForEach-Object { $_.Groups[1].Value }
# You will see: ...background-color:#ffffff;background-image:none;color:#1e293b
```

The `background-image:none` part is the smoking gun — it actively **erases** any `background: linear-gradient(...)` set by a class rule.

Visual symptom in the side-by-side review report: the section-divider PNG looks identical to a regular content slide, with the heading text either missing or barely legible.

### Fix options

**Option A — Tune class-based text colours to the inline background (recommended).** Accept that frontmatter wins, treat dividers as same-background-as-body, and use **dark text on the white background**:

```css
section.section-divider {
  display: flex;
  flex-direction: column;
  justify-content: center;
  align-items: center;
  text-align: center;
  /* no background — frontmatter wins anyway */
  color: #1e293b;
}
section.section-divider h1 { color: #0c4a6e; border-bottom: none; }
section.section-divider h2 { color: #0369a1; }
```

This preserves the visual rhythm (centred, larger heading, no border) without fighting the engine.

**Option B — Drop the frontmatter directive and set both palettes in the `style:` block.** Move `backgroundColor`/`color` out of YAML and into a base `section { ... }` rule, where class-based rules can override on equal footing:

```yaml
---
marp: true
# no backgroundColor, no color here
style: |
  section { background-color: #ffffff; color: #1e293b; }
  section.section-divider {
    background: linear-gradient(135deg, #0c4a6e, #0369a1);
    color: #ffffff;
  }
---
```

Now both rules are class-based and the divider gets its gradient. Trade-off: Marp's per-slide `<!-- _backgroundColor: ... -->` comment directive stops working (it relies on the YAML form), so use this only when you do not need per-slide background overrides.

**Option C — Per-slide `<!-- _backgroundColor: ... -->` comment.** Apply a one-off inline override on each divider slide. Verbose for many dividers but the only path that gives you a *different* background per slide while keeping the global default.

### The lesson

Never rely on `section.<class> { background: ... }` to override a YAML `backgroundColor:`. Either match the text palette to the inline background (Option A) or move backgrounds entirely into the `style:` block (Option B). Always check at least one section-divider / lead slide in the side-by-side review report after any palette change — a low-contrast headline is the canary that frontmatter is silently winning.

## Recommended Workflow

```
Edit source.md
    │
    ▼
Build version files (if multi-version deck)
    │
    ▼
overflow-check (gate)  ──────▶  any overflow? ──── yes ──▶  Apply fix:
    │                                                          • dense / compact directive
    │                                                          • content trim
    │                                                          • last resort: split
    │ no
    ▼
Side-by-side review report (visual sanity check before publishing)
    │
    ▼
Export PPTX / PDF / PNG
    │
    ▼
Commit
```

Wire `overflow-check` into your build script so the build **exits non-zero** on any overflow. This makes it impossible to commit a deck with silently-clipped content.

## Recipe 5: Speaker-Note Coverage — Gotchas and a Pester Guard

Marp speaker notes are HTML comments inside a slide; they render in presenter mode and export as PPTX slide notes, but are invisible in the rendered slide. Auditing "does every slide have notes?" has three traps: (A) `---` inside a code fence creates phantom slides — the auditor must be **code-fence-aware** and mirror the build's slide-splitter; (B) Marp directives (`version:`, `_class:`, `_paginate:`, `_color:`, `_backgroundColor:`, `fit`, `_split_`) are HTML comments too — filter by prefix blocklist plus inner-text length > 40 chars; (C) section-divider slides typically carry a per-module *appendix* note, so assert them separately.

> **Full recipe** — the three gotchas in depth, a drop-in Pester 5 guard (`Get-MarpSlide` + `Test-SlideHasNote` in `BeforeAll`), the `notes-title-map.psd1` title-drift pattern for multi-file decks, and the `<!-- _split_ -->` marker explanation: [`references/speaker-note-guard.md`](references/speaker-note-guard.md).

## Operational Gotchas

- **Puppeteer first-run cost**: `npm install` pulls ~150 MB of Chromium. Make your wrapper script bootstrap deps automatically (`Test-Path node_modules` → run `npm install` if missing) so users don't have to remember.
- **Web fonts**: Wait for `document.fonts.ready` before measuring. If you measure too early, custom fonts haven't loaded and the section reports the wrong height.
- **Multi-version decks**: Run the check against **every** generated variant, not just the source. The same slide may fit in the 4h variant (which uses a `dense` class on the previous slide that affects layout) but overflow in the 1h variant where surrounding context is different.
- **PPTX export uses Chromium too**: Marp CLI renders PPTX via headless Chromium, so what Puppeteer measures is exactly what ends up on the slide. There is no measurement-vs-export drift.
- **5 px tolerance**: Treat `overflowY < 5` as rendering rounding noise. Trying to chase those last few pixels usually produces fragile content.

## Anti-Patterns

| Anti-pattern | Why it fails |
|--------------|--------------|
| Counting markdown lines or characters as a heuristic | Tables, fenced code, and CSS layouts blow this up immediately |
| Eyeballing the VS Code Marp preview | The preview reflows freely; PPTX clips at exactly 720 px |
| Inserting a global smaller `font-size` on `section` | Loses visual rhythm; default 24 px is correct for most slides — only the dense ones need the override |
| Splitting every overflowing slide | Inflates slide count, breaks agenda timing, hides the real problem (slide is doing too many jobs at once) |
| Removing the `overflow: hidden` from the theme | Content escapes the slide bounds in the PPTX, looks broken |
| Off-by-one slide indexing without accounting for the phantom section | Reviewer compares the wrong source against the wrong rendered slide and trusts the wrong fix |
| Setting `section.<class> { background: ... }` while frontmatter declares `backgroundColor:` | Frontmatter is injected as an inline `style` attribute and beats any class rule; the class background is dead code, and any white-on-coloured text colour set alongside it becomes invisible on the actual (white) background |

## Reference Implementation

A complete reference implementation (Puppeteer detector, side-by-side report generator, density CSS, PowerShell wrapper) lives in [`AgenticOperatingModel/content/pptx`](https://github.com/raandree/AgenticOperatingModel/tree/main/content/pptx):

- `overflow-check.mjs` — Node + Puppeteer detector (Recipe 1)
- `Test-SlideOverflow.ps1` — PowerShell wrapper (orchestrates render → check → report)
- `New-SlideReviewReport.ps1` — Side-by-side HTML report generator (Recipe 4)
- `Build-MarpVersions.ps1` — Build script with `-CheckOverflow` and `-Report` switches
- The `compact` and `dense` CSS variants are in `content/slides/marp-presentation.md` frontmatter (Recipe 2)
