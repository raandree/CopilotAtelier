---
name: marp-slide-overflow
description: >-
  Detect and fix content overflow in Marp slide decks before exporting to PPTX/PDF/PNG. Marp silently clips any content taller than the 1280x720 viewBox — tables, code blocks, long paragraphs disappear with zero warning. Also covers pre-rendering ```mermaid``` fences to SVG (Marp has no native mermaid support; client-side mermaid.js fails in PDF/PPTX). Includes a mandatory PNG-based visual verification workflow (Recipe 0) because text heuristics (li/char counts) and the HTML preview both miss image and table overflow. Provides a Puppeteer-based overflow detector, a side-by-side HTML review report, a two-tier CSS density pattern (`dense`/`compact`), and a fillRatio decision table. USE FOR: Marp overflow, slide content clipped, slide too tall, content cut off in PPTX, slide overflow detection, Puppeteer slide check, Marp scrollHeight, marpit-svg viewBox, Marp dense/compact class, fit content to slide, slide overflow CI gate, fillRatio Marp, marp-cli overflow, headless Chromium slide measurement, Marp backgroundColor frontmatter, Marp class background ignored, Marp gradient not rendered, Marp _class directive background, Marp mermaid not rendering, mermaid in Marp deck, mermaid-cli mmdc, pre-render mermaid SVG, mermaid fence in PPTX, mermaid diagram missing in PDF, broken image Marp mermaid, mermaid parse error braces, verify slide fits PNG, marp --images png verification, per-slide PNG review, slide visual review, PNG overflow gate, table wrapping slide, table cell wrap PPTX, split slide vs shrink. DO NOT USE FOR: Reveal.js, Slidev, PowerPoint authoring, generic CSS layout, font rendering bugs.
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

Marp CLI has **no built-in mermaid support**. A ` ```mermaid ` fenced code block in the markdown is emitted into the rendered HTML/PDF/PPTX as a literal `<pre><code class="language-mermaid">…</code></pre>` block — it is never converted to a diagram. There is no warning, no error, no `[WARN]` in the CLI output.

There are two reliable workarounds; the second is the recommended one.

### Option A — `marp-cli` with a custom engine plugin

Marp exposes `--engine` and Marpit plugins. A community plugin like `markdown-it-textual-uml` or `markdown-it-mermaid` can be wired in, but they all rely on **client-side mermaid.js running in the rendered HTML**, which:

- works only in `--html` output (mermaid.js needs a browser to execute);
- still produces a static `<pre>` in `--pdf` and `--pptx` because marp-cli runs Chromium *before* mermaid.js initialises — the screenshot/PDF is taken too early;
- requires `--allow-local-files` and inlined CDN scripts.

In practice this means mermaid blocks **never appear correctly in PPTX or PDF** with this approach. Do not waste time on it for slide decks that need to export.

### Option B — Pre-render to SVG via `mermaid-cli` (recommended)

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

### Mermaid syntax gotchas that only surface during pre-render

mermaid-cli will **abort the entire build** on a parse error. The most common offenders in slide content:

- **`{` and `}` inside a node label** — mermaid's flowchart parser treats `{` as the start of a diamond shape. Wrap the label in double quotes: `C["Add-LabMachineDefinition -ProxmoxProperties @{...}"]`.
- **`(` `)` `[` `]` in labels** — same rule; quote the label.
- **Backticks for inline code** — not supported in node labels; use plain text or HTML entities.
- **`<br/>` for line breaks** — works *only* inside quoted labels in recent mermaid versions; quote the label to be safe.

A label that works in GitHub's mermaid renderer may still fail in `mermaid-cli` because GitHub runs a more permissive client-side build. Always render through `mmdc` before shipping.

### Detecting the regression

If a deck previously rendered mermaid (e.g. via a different tool) and now shows code blocks where diagrams should be, grep the rendered HTML:

```powershell
Select-String -Path dist\deck.html -Pattern 'class="language-mermaid"'
```

Any match means the fence survived into the output — pre-rendering is missing or skipped that block.

### Sizing pre-rendered diagrams so they don't dominate the slide

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

## Recipe 0: PNG-based visual verification (mandatory before claiming "fixed")

Text-heuristic overflow checks (counting `<li>` elements, total character length, raw `scrollHeight`) **miss the cases that matter most**: oversized images, tables with wrapped cells, code blocks with long lines. The only reliable signal that a slide actually fits is a rendered PNG of that slide. Bake this into the workflow:

### Step 1 — Render every slide to PNG

```powershell
# After the normal HTML/PDF/PPTX render
npx --yes @marp-team/marp-cli@latest --allow-local-files `
    --images png --image-scale 1 `
    -o dist\png\slide.png dist\deck.assembled.md
```

Produces `dist\png\slide.001.png`, `slide.002.png`, … one 1280×720 PNG per slide. `--image-scale 1` keeps file sizes small; bump to `2` only when you need to read sub-pixel detail.

### Step 2 — List slides worth a hand-check

Not every slide needs a visual review. Programmatically pick the ones that historically overflow: anything containing a table, an image (mermaid SVG), a code block of more than ~6 lines, or a list of more than ~7 bullets.

```powershell
$assembled = 'dist\deck.assembled.md'
$lines = Get-Content $assembled
$slide = 1; $atRisk = @(); $tableRows = 0; $codeLen = 0; $bullets = 0; $hasImg = $false; $inCode = $false
foreach ($l in $lines) {
    if ($l -match '^---\s*$' -and -not $inCode) {
        if ($hasImg -or $tableRows -ge 4 -or $codeLen -ge 7 -or $bullets -ge 7) { $atRisk += $slide }
        $slide++; $tableRows = 0; $codeLen = 0; $bullets = 0; $hasImg = $false; continue
    }
    if ($l -match '^```')         { $inCode = -not $inCode; continue }
    if ($inCode)                  { $codeLen++; continue }
    if ($l -match '^\s*\|.*\|')   { $tableRows++ }
    if ($l -match '^\s*[-*]\s')   { $bullets++ }
    if ($l -match '!\[')          { $hasImg = $true }
}
Write-Host "At-risk slides: $($atRisk -join ', ')"
```

Subtract any frontmatter `---` blocks from the count — the deck's YAML header opens and closes with `---` and adds 2 to the slide index if you don't strip it. Easiest fix: start counting from the first `<!-- _class: -->` directive or the first H1.

### Step 3 — Inspect each at-risk PNG and check three invariants

For every PNG flagged in step 2, confirm:

1. **Title visible** at the top (H1/H2 not pushed off-screen by a tall image above it).
2. **Footer page number visible** at the bottom-right (proves the bottom edge isn't clipped).
3. **No half-cut rows** at the bottom — last table row, last bullet, last line of a code block must be fully drawn, not sliced through the middle.

If any invariant fails, the fix is one of:

- Add `<!-- _class: dense -->` (~20 px font) or `compact` (~22 px font) — gives ~25–35% more vertical space.
- Tighten the content (collapse bullets, glob cmdlet names, shorten paths).
- Split the slide. **Splitting beats shrinking** below readable size — at 18 px the audience can't read it from row 5 anyway.
- For oversized images: cap with the `section img { max-height: ... }` CSS rule and prefer `graph LR` over `graph TB`.

### Step 4 — Re-render PNGs and re-check the same invariants

Iterate until clean. Never claim "fits the slide" without a fresh PNG.

### Step 3b — Hand the PNGs to a fresh subagent for visual QA

After you've stared at the deck for an hour, your eyes see what you expect, not what's there. Spawn a subagent with the at-risk PNGs and a deliberately adversarial prompt. The fresh-eyes pass routinely catches issues the author missed.

Use `runSubagent` (when available) with a prompt along these lines:

```
Visually inspect these slide PNGs. Assume there are problems — your job is to find them.

For EACH PNG, check:
  1. Title visible at the top? (not pushed off-screen, not clipped)
  2. Footer page number visible at the bottom-right?
  3. Bottom row of any table / list / code block fully drawn? (no half-cut rows)
  4. Any element overlapping another? (text through shapes, citations on top of content)
  5. Any text overflow at the right edge of the slide?
  6. Mermaid SVG fully inside the slide frame, with readable node labels?
  7. Low-contrast text or icons against the background?
  8. Inconsistent gaps (large empty area beside cramped content)?

Report ALL issues found, including minor ones. Group by slide number.
Do not declare a slide clean if you found zero issues on first inspection — look again more critically.

Images:
  - dist/png/slide.012.png  (expected: title "Hyper-V vs Proxmox", 4-row comparison table)
  - dist/png/slide.018.png  (expected: mermaid diagram + 3 bullets)
  - ...
```

When no subagent is available, fall back to opening the PNGs side-by-side and walking the same checklist yourself, slide by slide.

**Verification loop.** Fix → re-render only the affected slides (`marp --images png ... --slides 12,18`) → re-run the same QA prompt on the new PNGs. One fix often creates another problem (a split slide pushes everything down by one). Do **not** declare success until a full clean pass yields no new issues.

**Anti-pattern: subagent rubber-stamping.** If the subagent reports "all clean" on the first pass, treat it as a smoke alarm, not a clean bill of health. Either the prompt was too soft or the PNGs were too few. Add the adversarial framing ("assume there are problems") and re-run.


### Anti-pattern: trusting the build-script heuristic

A naïve overflow check that counts `<li>` and character length will pass slides that are catastrophically broken (a single oversized SVG, or a 4-row table that wraps to 12 visual rows). Treat such heuristics as **smoke alarms, not gates** — they catch some failures but never certify "fits". The PNG review in steps 1–3 is the only gate.

### Anti-pattern: trusting the HTML/VS Code preview

The browser preview rescales the viewport to fit the window, so a slide that overflows by 200 px in the actual 1280×720 frame looks fine in the preview. PDF/PPTX/PNG exports use the fixed frame and reveal the clipping. Always verify against the rendered PNG, never against the preview.

## Recipe 1: Minimal Overflow Detector (Node + Puppeteer)

`overflow-check.mjs`:

```js
#!/usr/bin/env node
import { resolve } from 'node:path';
import { existsSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

const args = process.argv.slice(2);
const jsonMode = args.includes('--json');
const htmlPath = resolve(args.find(a => !a.startsWith('--')));
if (!existsSync(htmlPath)) { console.error('not found:', htmlPath); process.exit(2); }

const puppeteer = (await import('puppeteer')).default;
const browser = await puppeteer.launch({ headless: 'new', args: ['--no-sandbox'] });
const page = await browser.newPage();
await page.setViewport({ width: 1600, height: 900 });
await page.goto(pathToFileURL(htmlPath).href, { waitUntil: 'networkidle0' });
await page.evaluate(async () => { if (document.fonts) await document.fonts.ready; });

const results = await page.evaluate(() => {
    return Array.from(document.querySelectorAll('section')).map((section, idx) => {
        const svg = section.closest('svg[data-marpit-svg]');
        let frameW = 1280, frameH = 720;
        if (svg) {
            const vb = (svg.getAttribute('viewBox') || '').split(/\s+/).map(Number);
            if (vb.length === 4) { frameW = vb[2]; frameH = vb[3]; }
        }
        const contentH = section.scrollHeight;
        const contentW = section.scrollWidth;
        const titleEl = section.querySelector('h1, h2, h3');
        return {
            slide: idx + 1,
            title: titleEl ? titleEl.textContent.replace(/\s+/g, ' ').trim() : '',
            frameWidth: frameW, frameHeight: frameH,
            contentWidth: contentW, contentHeight: contentH,
            overflowX: Math.max(0, contentW - frameW),
            overflowY: Math.max(0, contentH - frameH),
            fillRatio: Number((contentH / frameH).toFixed(3)),
            overflows: (contentW - frameW) > 1 || (contentH - frameH) > 1
        };
    });
});

await browser.close();
const overflowing = results.filter(r => r.overflows);
if (jsonMode) {
    process.stdout.write(JSON.stringify(results, null, 2));
} else {
    console.log(`${results.length} slides: ${results.length - overflowing.length} fit, ${overflowing.length} overflow`);
    for (const o of overflowing) {
        console.log(`  Slide ${o.slide} "${o.title}"  Y=${o.overflowY}px X=${o.overflowX}px fill=${o.fillRatio}`);
    }
}
process.exit(overflowing.length > 0 ? 1 : 0);
```

Companion `package.json`:

```json
{
  "name": "marp-overflow-tools",
  "version": "1.0.0",
  "private": true,
  "type": "module",
  "dependencies": { "puppeteer": "^23.10.4" }
}
```

Wire it into the build:

```powershell
# 1. Render the deck once to HTML
npx --yes @marp-team/marp-cli@latest deck.md --html --allow-local-files -o _check.html

# 2. Measure
node overflow-check.mjs _check.html
# exit 0 = all fit, 1 = at least one overflows, 2 = error

# 3. Cleanup
Remove-Item _check.html
```

> **First run only**: `npm install` pulls Puppeteer (~150 MB Chromium). Subsequent runs are fast. Bake the install check into your wrapper script so users don't have to know.

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

Marp speaker notes are HTML comments inside a slide:

```markdown
# My Slide

Body content.

<!--
Speaker notes go here. Multi-line is fine.
- Bullet points work too.
-->
```

They render in **presenter mode** (`marp --preview`) and export as **PPTX slide notes** on `marp --pptx`. Invisible in the rendered slide itself.

Two problems show up the moment you try to audit "does every slide have notes?":

### Gotcha A — the `---`-inside-a-code-fence trap

Many decks show YAML or markdown frontmatter as code examples (`.agent.md`, `SKILL.md`, etc.):

````markdown
# Custom Agents

```markdown
---
name: software-engineer
tools: ['editFiles', 'runTests']
---
# Software Engineer Agent
```
````

A naive separator counter that splits on `^---$` will mis-count those inner `---` delimiters as slide breaks and produce phantom "slides" whose H1 is `name: software-engineer`. Any coverage audit must be **code-fence-aware**: track a boolean `inCode` that toggles on every line matching `^\x60{3}` and ignore `---` while `inCode` is true. Mirror what your build script's slide-splitter does — mismatch between auditor and builder is the bug.

### Gotcha B — distinguishing real notes from Marp directives

Marp uses HTML comments for everything: `<!-- version: 4h -->`, `<!-- _class: dense -->`, `<!-- _paginate: false -->`, `<!-- _backgroundColor: #fff -->`, `<!-- _color: ... -->`, plus any editorial markers your build understands (`<!-- _split_ -->` is a common one). A comment-block-presence check that doesn't filter these will falsely report **every** slide as having notes.

The working filter:

- Treat as a *directive* (not a note) any comment whose trimmed inner text matches `^(version:|_class:|_paginate:|_color:|_backgroundColor:|fit|_split_)`.
- Require the inner text to be **> 40 chars** so single-line directives never count as a note.

### Gotcha C — section-divider slides are a separate category

If your deck splits source into per-module files and synthesises section-divider slides (`<!-- _class: section-divider --># Module N`), those usually receive a per-module *appendix* block (`Speaker notes — Module N appendix…`) instead of a per-slide note. Test dividers separately, with their own assertion.

### Pester guard (drop-in)

This is a complete, working pair of `It` blocks. Helpers go in `BeforeAll` (see also `pester-patterns` skill — Pester 5 isolates each `It` in its own runspace, helpers defined as `Describe` siblings are invisible inside `It`).

```powershell
Describe 'Built MARP outputs have speaker notes on every slide' {
    BeforeAll {
        $script:pptxDir = $PSScriptRoot

        function Get-MarpSlide {
            param([Parameter(Mandatory)][string]$Path)
            $lines  = Get-Content -Path $Path -Encoding UTF8
            $sepIdx = [System.Collections.Generic.List[int]]::new()
            $inCode = $false; $sawFm = $false; $inFm = $false
            for ($i = 0; $i -lt $lines.Count; $i++) {
                $t = $lines[$i].TrimEnd()
                if ($t -match '^```') { $inCode = -not $inCode; continue }
                if ($inCode) { continue }
                if ($t -ne '---') { continue }
                if (-not $sawFm) {
                    if ($inFm) { $sawFm = $true; $inFm = $false; continue }
                    $inFm = $true; continue
                }
                [void]$sepIdx.Add($i)
            }
            $slides = [System.Collections.Generic.List[object]]::new()
            for ($n = 0; $n -lt $sepIdx.Count; $n++) {
                $start = $sepIdx[$n] + 1
                $end   = if (($n + 1) -lt $sepIdx.Count) { $sepIdx[$n + 1] - 1 } else { $lines.Count - 1 }
                $body  = if ($start -le $end) { $lines[$start..$end] -join "`n" } else { '' }
                $title = ($lines[$start..$end] | Where-Object { $_ -match '^#\s+(.+)$' } | Select-Object -First 1)
                if ($title) { $title = ($title -replace '^#\s+', '').Trim() }
                [void]$slides.Add([pscustomobject]@{
                    Number    = $n + 1
                    Title     = $title
                    Body      = $body
                    IsDivider = ($body -match '(?s)<!--\s*_class:\s*section-divider\s*-->')
                })
            }
            return , $slides.ToArray()
        }

        function Test-SlideHasNote {
            param([Parameter(Mandatory)][string]$Body)
            foreach ($m in [regex]::Matches($Body, '(?s)<!--(.*?)-->')) {
                $inner = $m.Groups[1].Value.Trim()
                if ($inner -match '^(version:|_class:|_paginate:|_color:|_backgroundColor:|fit|_split_)') { continue }
                if ($inner.Length -gt 40) { return $true }
            }
            return $false
        }
    }

    It 'every slide in <File> has a speaker-note HTML comment block' -ForEach @(
        @{ File = 'marp-1h-keynote.md'   }
        @{ File = 'marp-2h-standard.md'  }
        @{ File = 'marp-4h-workshop.md'  }
    ) {
        $path = Join-Path $script:pptxDir $File
        if (-not (Test-Path $path)) {
            Set-ItResult -Skipped -Because "$File not built yet"; return
        }
        $slides  = Get-MarpSlide -Path $path
        $missing = foreach ($s in $slides) {
            if ($s.IsDivider) { continue }
            if (-not (Test-SlideHasNote -Body $s.Body)) {
                ('  Slide {0}: {1}' -f $s.Number, $(if ($s.Title) { $s.Title } else { '(no H1)' }))
            }
        }
        $missing | Should -BeNullOrEmpty
    }
}
```

### Title-drift / merge pattern (multi-file decks)

If your build assembles a monolith from per-module split files and merges speaker notes by matching the H1 between split and monolith, **titles will drift**. Ship a `notes-title-map.psd1` next to the build script that aliases split-file H1s to monolith H1s:

```powershell
@{
    'Knowing What AI Changed'  = 'Git Provides Traceability'
    'Rollback When Needed'     = 'Checkpoint System — Rollback When Needed'
    'When AI Validates Its Own Lies' = 'The Cheating-Agent Trap'
}
```

When the coverage test catches a slide with no notes, the three remediation paths in order of preference are:

1. **Add the alias** in `notes-title-map.psd1` (if a split-file slide already has the note under a different H1).
2. **Add notes in the split file** (if the slide has a split-file equivalent that's never had notes).
3. **Add notes inline in the monolith** (only for monolith-only slides — cleanest fix because no merge logic involved).

### What the editorial marker `<!-- _split_ -->` is

It's a comment some teams use to mark "this is where the split was made" or "this slide was generated by splitting an oversized parent." Marp ignores it (any HTML comment is invisible in the rendered slide). The build pipeline ignores it too. Include it in the directive blocklist so it never falsely registers as a speaker note.

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
