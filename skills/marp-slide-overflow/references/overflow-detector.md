# Minimal Overflow Detector — Node + Puppeteer (Recipe 1)

> Reference for the `marp-slide-overflow` skill. Render the deck to HTML, then
> measure each `<section>`'s `scrollHeight` against the `viewBox` height in
> headless Chromium. This is the only reliable overflow signal.

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
