# PNG-Based Visual Verification (Recipe 0)

> Reference for the `marp-slide-overflow` skill. The only reliable signal that a
> slide actually fits is a rendered PNG of that slide — text heuristics miss the
> cases that matter most.

## Contents

- [Step 1 — Render every slide to PNG](#step-1--render-every-slide-to-png)
- [Step 2 — List slides worth a hand-check](#step-2--list-slides-worth-a-hand-check)
- [Step 3 — Inspect each at-risk PNG and check three invariants](#step-3--inspect-each-at-risk-png-and-check-three-invariants)
- [Step 4 — Re-render PNGs and re-check](#step-4--re-render-pngs-and-re-check-the-same-invariants)
- [Step 3b — Hand the PNGs to a fresh subagent for visual QA](#step-3b--hand-the-pngs-to-a-fresh-subagent-for-visual-qa)
- [Anti-patterns](#anti-pattern-trusting-the-build-script-heuristic)

Text-heuristic overflow checks (counting `<li>` elements, total character length, raw `scrollHeight`) **miss the cases that matter most**: oversized images, tables with wrapped cells, code blocks with long lines. The only reliable signal that a slide actually fits is a rendered PNG of that slide. Bake this into the workflow:

## Step 1 — Render every slide to PNG

```powershell
# After the normal HTML/PDF/PPTX render
npx --yes @marp-team/marp-cli@latest --allow-local-files `
    --images png --image-scale 1 `
    -o dist\png\slide.png dist\deck.assembled.md
```

Produces `dist\png\slide.001.png`, `slide.002.png`, … one 1280×720 PNG per slide. `--image-scale 1` keeps file sizes small; bump to `2` only when you need to read sub-pixel detail.

## Step 2 — List slides worth a hand-check

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

## Step 3 — Inspect each at-risk PNG and check three invariants

For every PNG flagged in step 2, confirm:

1. **Title visible** at the top (H1/H2 not pushed off-screen by a tall image above it).
2. **Footer page number visible** at the bottom-right (proves the bottom edge isn't clipped).
3. **No half-cut rows** at the bottom — last table row, last bullet, last line of a code block must be fully drawn, not sliced through the middle.

If any invariant fails, the fix is one of:

- Add `<!-- _class: dense -->` (~20 px font) or `compact` (~22 px font) — gives ~25–35% more vertical space.
- Tighten the content (collapse bullets, glob cmdlet names, shorten paths).
- Split the slide. **Splitting beats shrinking** below readable size — at 18 px the audience can't read it from row 5 anyway.
- For oversized images: cap with the `section img { max-height: ... }` CSS rule and prefer `graph LR` over `graph TB`.

## Step 4 — Re-render PNGs and re-check the same invariants

Iterate until clean. Never claim "fits the slide" without a fresh PNG.

## Step 3b — Hand the PNGs to a fresh subagent for visual QA

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

## Anti-pattern: trusting the build-script heuristic

A naïve overflow check that counts `<li>` and character length will pass slides that are catastrophically broken (a single oversized SVG, or a 4-row table that wraps to 12 visual rows). Treat such heuristics as **smoke alarms, not gates** — they catch some failures but never certify "fits". The PNG review in steps 1–3 is the only gate.

## Anti-pattern: trusting the HTML/VS Code preview

The browser preview rescales the viewport to fit the window, so a slide that overflows by 200 px in the actual 1280×720 frame looks fine in the preview. PDF/PPTX/PNG exports use the fixed frame and reveal the clipping. Always verify against the rendered PNG, never against the preview.
