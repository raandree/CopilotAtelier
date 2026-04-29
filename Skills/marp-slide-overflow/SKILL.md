---
name: marp-slide-overflow
description: >-
  Detect and fix content overflow in Marp slide decks before exporting to
  PPTX/PDF/PNG. Marp silently clips any slide content taller than the
  1280x720 viewBox — tables, code blocks, long paragraphs disappear with
  zero warning in the binary export. This skill provides a Puppeteer-based
  overflow detector, a side-by-side HTML review report, a two-tier CSS
  density pattern (`dense` / `compact`) for fitting content without
  splitting slides, and a fillRatio decision table for choosing the right
  fix.
  USE FOR: Marp overflow, slide content clipped, slide too tall, Marp
  silently truncates, content cut off in PPTX, Marp PPTX export missing
  content, slide overflow detection, Puppeteer slide check, Marp scrollHeight,
  marpit-svg viewBox, Marp dense class, Marp compact class, fit content to
  slide, slide overflow CI gate, Marp side-by-side review, slide review
  report, fillRatio Marp, Marp class directive, marp-cli overflow,
  marpit overflow hidden, Marp build pipeline overflow, programmatic slide
  overflow check, headless Chromium slide measurement, Marp 720 viewBox.
  DO NOT USE FOR: Reveal.js, Slidev, PowerPoint authoring, generic CSS
  layout problems, PDF page breaks unrelated to Marp, font rendering bugs.
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

## Reference Implementation

A complete reference implementation (Puppeteer detector, side-by-side report generator, density CSS, PowerShell wrapper) lives in [`AgenticOperatingModel/content/pptx`](https://github.com/raandree/AgenticOperatingModel/tree/main/content/pptx):

- `overflow-check.mjs` — Node + Puppeteer detector (Recipe 1)
- `Test-SlideOverflow.ps1` — PowerShell wrapper (orchestrates render → check → report)
- `New-SlideReviewReport.ps1` — Side-by-side HTML report generator (Recipe 4)
- `Build-MarpVersions.ps1` — Build script with `-CheckOverflow` and `-Report` switches
- The `compact` and `dense` CSS variants are in `content/slides/marp-presentation.md` frontmatter (Recipe 2)
