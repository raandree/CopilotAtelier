---
name: evidence-package-assembly
description: >-
  Assembles paginated evidence packages (Anlagen) for authorities, courts,
  and insurers on Windows: verifies documents against the claims made about
  them, decides which sheets may be omitted, renders a Markdown cover with a
  locator index to PDF via pandoc and headless Edge, merges with pypdf, and
  verifies page ranges, text layer, and the sources' own page numbering.
  USE FOR: Anlage bauen, Beweispaket, Belege zusammenstellen, evidence
  package, exhibit bundle, Deckblatt, Fundstellenverzeichnis, locator index,
  Markdown nach PDF, markdown to PDF on Windows, pandoc Edge headless,
  print-to-pdf erzeugt keine Datei, Edge headless exit 0 kein PDF, PDFs
  zusammenfuehren, welche Seiten darf ich weglassen, Seiten aus Kontoauszug
  entfernen, Schwaerzung, redact bank statement, Seitenzaehlung lueckenlos.
  DO NOT USE FOR: extracting text from PDFs (use pdf-to-markdown), Markdown
  to Word (use pandoc-docx-export), slides (use marp-slide-overflow), legal
  argumentation (use german-legal-research).
compatibility: >-
  Windows with pandoc on PATH and Microsoft Edge installed. Python via `uv`
  for pypdf and pymupdf. No Adobe Acrobat, Word, or LibreOffice required.
---

# Evidence Package Assembly

Turn a pile of source documents into one PDF an examiner can navigate, verify, and trust. The output is a single file whose first pages tell the reader what is inside, where to find it, and what was left out.

## When to Use

- Building an `Anlage` for a Finanzamt, court, insurer, or opposing counsel.
- Bundling bank statements, invoices, or correspondence as proof of a factual claim.
- The user asks which pages can be dropped from a statement, or whether to redact.
- Markdown must become PDF on Windows without LaTeX, Word, or a paid tool.

## Outcome

One PDF containing a cover sheet with a locator index, followed by the source documents in a stated order, where every page range on the cover matches the built file, every omission is disclosed, and every source document's own page numbering is complete.

## Workflow

Run the phases in order. Phase 1 is not optional — it catches claims that do not survive contact with the documents.

### Phase 1 — Verify before assembling

Never trust an internal note about what a document shows. Extract the text and check each claim.

```powershell
uv run --with pymupdf python -c "import pymupdf; d=pymupdf.open('beleg.pdf'); print(''.join(p.get_text() for p in d))"
```

Grep the extraction for the exact strings the note promises: payee names, purposes of payment, place names, addresses. Record what is confirmed and correct what is not. A cover sheet that promises a booking the file does not contain is worse than no cover sheet.

### Phase 2 — Decide what to include

The decision rule is **the source document's own page numbering**, not topical relevance.

| Sheet | Rule |
|---|---|
| Carries `Seite X von N`, `Seite X/N`, `Blatt X` | Include, even when the page shows nothing relevant. Removing it leaves a visible gap and invites the reproach of selective presentation. |
| Carries no page number and no transaction content | Omit. It sits outside the sequence, so removal leaves no gap. Typically terms-and-conditions notices, technical trailer lines, advertising inserts. |

Detect the numbering before deciding:

```powershell
uv run --with pymupdf python -c "import pymupdf,re; d=pymupdf.open('beleg.pdf'); [print(i, re.findall(r'Seite\s*\d+\s*(?:von|/)\s*\d+', p.get_text())) for i,p in enumerate(d,1)]"
```

Two corollaries:

- A page that carries the account holder's address is evidence in its own right, whatever else is on it. Keep it.
- Keep at least one item that cuts against the argued position when the record contains one, and name it on the cover. A visibly unfiltered selection is worth more than a clean one.

### Phase 3 — Redaction

Default: do not redact. Redacting a bank statement breaks the running balance and makes the document unverifiable, which destroys more evidential value than the privacy gain is worth.

Redact only for special categories of personal data (health, religion, trade union, political opinion, sexual life) that are genuinely unrelated to the matter. A single pharmacy or supermarket line is not a special category. When redacting, use `page.add_redact_annot()` plus `page.apply_redactions()` in pymupdf — a black rectangle drawn over text leaves the text layer intact and readable.

State on the cover which route was taken. Silence invites the question.

### Phase 4 — Write the cover

Four sections, in this order:

1. Header block: parties, object, file reference, period, which request this answers.
2. Scope: representative selection or complete, offer to supply the remainder, redaction status, and an explicit list of omitted sheets with the reason.
3. Locator index: part number, document, period, page range in the assembled PDF.
4. Evidence table: what each part shows, in the examiner's language, quoting the exact booking texts.

Optionally a table of recurring items across parts, mapping each proof to the parts that carry it. This is what turns 40 pages of statements into an argument.

### Phase 5 — Render and merge

Render the cover, count its pages, fill the page ranges, render again, then merge. See [Build recipe](#build-recipe).

### Phase 6 — Verify the built file

Check all four:

- Page count and per-part ranges match the cover.
- No page lost its text layer.
- Each source document's own numbering is complete in the output.
- The cover renders as intended — rasterise page 1 and look at it.

## Build recipe

### Markdown to PDF via pandoc and headless Edge

```powershell
pandoc cover.md -s --embed-resources --css 'pdf-print.css' `
    --metadata pagetitle='Anlage 11' -o "$env:TEMP\cover.html"

$profileDir = Join-Path $env:TEMP ('edgepdf-' + [guid]::NewGuid().ToString('N').Substring(0,8))
$edgeArgs = @(
    '--headless=new'
    '--disable-gpu'
    '--no-first-run'
    "--user-data-dir=$profileDir"
    '--virtual-time-budget=10000'
    '--no-pdf-header-footer'
    "--print-to-pdf=$env:TEMP\cover.pdf"
    ('file:///' + ("$env:TEMP\cover.html" -replace '\\','/'))
)
Start-Process -FilePath 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe' `
    -ArgumentList $edgeArgs -Wait -WindowStyle Hidden
```

**Edge produces no file and still exits 0** when invoked without `--headless=new`, without a private `--user-data-dir`, or with the call operator instead of `Start-Process -Wait`. The call appears to succeed; only the missing output reveals the failure. Always test for the file afterwards and throw if it is absent.

`scripts/Build-EvidencePackage.ps1` wraps this with the guard in place.

### Merge and verify

`scripts/merge-and-verify.py` takes a JSON manifest and prints the page range of every part, so the cover can be filled from its output:

```json
{
  "cover": "C:/Temp/cover.pdf",
  "out": "output/anlage-11.pdf",
  "parts": [
    { "id": "11.1", "file": "input/Targobank 2022-01.pdf", "skip": [8] },
    { "id": "11.2", "file": "input/ING 2022-03.pdf", "skip": [4] }
  ]
}
```

`skip` lists source page numbers to omit. The script reports them, so the omission stays visible in the build log.

## Markdown authoring gotchas for the cover

These bite when pandoc renders the cover, not when the Markdown is read.

| Symptom | Cause | Fix |
|---|---|---|
| Title appears twice | `--metadata title` emits an H1 on top of the document's own H1 | Use `--metadata pagetitle` |
| Header lines run into one paragraph | Markdown ignores single newlines | End each line with a backslash, not with two trailing spaces |
| One table column is absurdly wide | Pipe-table widths come from the dash counts in the separator row | Set dash lengths proportionally; keep a space either side of each pipe so markdownlint MD060 still passes |
| A date turns into a numbered list | `17. April 2022` at the start of a line parses as an ordered list marker | Write `17.04.2022`, or escape as `17\.` |
| Heading orphaned at the page foot | No break control | `h2 { break-after: avoid; page-break-after: avoid; }` in the print CSS |

## Edge cases

- **Photographed evidence.** A phone photo of a signed letter can be placed on an A4 page with `page.insert_image(rect, filename=..., keep_proportion=True)`. It will have no text layer. Say so in the record and do not OCR it — a wrong text layer over a signed document is worse than none.
- **Attachment size limits.** Authority mailboxes commonly reject above 10–20 MB, and a rejected message never arrived. Report the built size and split into numbered part-sendings when close to the limit.
- **Source has no page numbering at all.** Fall back to transaction continuity: include every page carrying bookings or balances, omit only sheets with neither.
- **Cover grows past two pages.** Re-render, re-read the page count, and rebuild the ranges. Never hand-adjust the ranges after a content edit.

## Anti-patterns

- Building the package before verifying the documents against the claims made about them.
- Dropping a numbered page because it looks irrelevant.
- Redacting a statement so that its balances no longer reconcile.
- Omitting sheets silently.
- Presenting a selection scrubbed of everything unfavourable.
- Writing page ranges by hand instead of taking them from the merge output.
- Treating a zero exit code from headless Edge as proof that a PDF exists.
