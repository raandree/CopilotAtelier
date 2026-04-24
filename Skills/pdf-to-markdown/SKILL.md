---
name: pdf-to-markdown
description: >-
  Convert PDF files to well-structured Markdown using .NET-native PDF parsing
  in PowerShell — no external tools (Python, pdftotext, Word COM) required.
  Decompresses zlib/deflate content streams, decodes hex-encoded text operators
  (BT/ET, Td, Tj), reconstructs lines by Y-coordinate positioning, and produces
  clean Markdown with tables and formatting. Handles German-locale PDFs
  (ISO-8859-1 encoding, umlauts, ß, special chars). Best suited for structured
  documents like payslips, invoices, reports. Also includes an OCR fallback
  (Recipe 4) using pymupdf + Tesseract for scanned / image-only PDFs with a
  two-pass heuristic and Windows installation guide (winget + tessdata_best +
  user-scope TESSDATA_PREFIX).
  USE FOR: convert PDF to markdown, PDF to md, extract text from PDF, parse PDF,
  PDF text extraction, PDF to text, Entgeltabrechnung PDF, payslip PDF, invoice
  PDF, read PDF in PowerShell, decode PDF hex, PDF content stream, deflate PDF
  stream, structured PDF extraction, German PDF, Gehaltsabrechnung, scanned
  PDF, image-only PDF, Microsoft Lens scan, Office Lens, OCR PDF, Tesseract,
  tesseract deu, tessdata_best, pymupdf OCR, TESSDATA_PREFIX, winget Tesseract,
  UB-Mannheim.TesseractOCR, OCR German documents, PDF needs OCR, empty PDF
  text extraction, pdf zu text OCR, Bescheid scannen OCR.
  DO NOT USE FOR: PDFs with complex vector graphics, PDF form filling, PDF
  editing, PDF creation.
---

# PDF to Markdown Conversion

## When to Use

- Extracting text from PDF files in a workspace for downstream analysis
- Converting structured documents (payslips, invoices, reports, letters) to Markdown
- No Python, pdftotext, or external PDF tools available on the system
- PDF contains text-based content (not scanned images)

## Approach Decision Tree

```
PDF file in workspace
├── Is Python + pymupdf/pdfplumber available?
│   └── YES → Use Python (simplest, most reliable)
├── Is pdftotext (xpdf/poppler) available?
│   └── YES → Use pdftotext (fast, preserves layout)
├── Is the PDF small-to-medium (<10MB) and text-based?
│   └── YES → Use .NET native parsing (Recipe 1 below)
```

### Check Tool Availability

```powershell
# Check in priority order
$tools = @(
    @{ Name = 'pdftotext'; Check = { Get-Command pdftotext -EA 0 } }
    @{ Name = 'python+pymupdf'; Check = { python -c "import pymupdf" 2>$null; $LASTEXITCODE -eq 0 } }
    @{ Name = 'python+pdfplumber'; Check = { python -c "import pdfplumber" 2>$null; $LASTEXITCODE -eq 0 } }
)
foreach ($t in $tools) { if (& $t.Check) { Write-Host "Use: $($t.Name)"; break } }
```

## Recipe 1: .NET Native PDF Parsing (No External Tools)

This approach works for text-based PDFs using standard PDF operators. It uses
only .NET classes available in PowerShell 7+ — no NuGet packages needed.

### How PDF Text Storage Works

PDF files store text in **content streams** that are typically zlib-compressed.
Each stream contains PostScript-like operators:

| Operator | Meaning | Example |
|----------|---------|---------|
| `BT` / `ET` | Begin/End text block | |
| `Td` | Set text position (x, y) | `148.80 811.20 Td` |
| `Tf` | Set font and size | `/F001 8.00 Tf` |
| `Tj` | Show text string | `<48656C6C6F>Tj` = "Hello" |
| `TJ` | Show text array (with kerning) | `[(He) -10 (llo)]TJ` |
| `Tw` | Set word spacing | `0 Tw` |

Text strings in `<...>Tj` are **hex-encoded** — each pair of hex digits is one byte.

### Step 1: Extract Content Streams

```powershell
$pdfPath = 'C:\path\to\file.pdf'
$bytes = [System.IO.File]::ReadAllBytes($pdfPath)
$raw = [System.Text.Encoding]::GetEncoding('ISO-8859-1').GetString($bytes)

# Find all stream/endstream blocks
$streamMatches = [regex]::Matches(
    $raw,
    'stream\r?\n(.+?)\r?\nendstream',
    [System.Text.RegularExpressions.RegexOptions]::Singleline
)
Write-Host "Found $($streamMatches.Count) streams"
```

### Step 2: Decompress Streams (zlib/deflate)

Most PDF streams use FlateDecode (zlib). The first 2 bytes are the zlib header —
skip them to get raw deflate data for .NET's `DeflateStream`:

```powershell
foreach ($i in 0..($streamMatches.Count - 1)) {
    $streamData = [System.Text.Encoding]::GetEncoding('ISO-8859-1').GetBytes(
        $streamMatches[$i].Groups[1].Value
    )
    try {
        # Skip 2-byte zlib header for raw deflate
        $ms = [System.IO.MemoryStream]::new($streamData, 2, ($streamData.Length - 2))
        $ds = [System.IO.Compression.DeflateStream]::new(
            $ms, [System.IO.Compression.CompressionMode]::Decompress
        )
        $sr = [System.IO.StreamReader]::new(
            $ds, [System.Text.Encoding]::GetEncoding('ISO-8859-1')
        )
        $text = $sr.ReadToEnd()
        $sr.Close()
        Write-Host "Stream $i : $($text.Length) chars"
        # The stream with BT/ET text operators is the content stream
        if ($text -match 'BT\r?\n') {
            $contentStream = $text
            Write-Host "  -> This is the text content stream"
        }
    } catch {
        Write-Host "Stream $i : not deflate-compressed"
    }
}
```

### Step 3: Identify the Content Stream

Among the decoded streams, look for the one containing `BT` (Begin Text) operators.
Other streams are typically images, fonts, or metadata:

- **Stream with repeated `0xFF` bytes** → image data (e.g., bitmap mask)
- **Stream with color/coordinate data** → graphics/drawing commands
- **Stream with `BT`/`ET` + `Td` + `Tj`** → **this is the text content stream**

### Step 4: Parse Text Positions and Decode Hex

```powershell
# Pattern: BT block with position (Td) and hex text (Tj)
$pattern = 'BT\r?\n\s*([\d.]+)\s+([\d.]+)\s+Td\r?\n\s*\d+\s+Tw\r?\n\s*<([0-9A-Fa-f]+)>Tj\r?\n\s*ET'
$blocks = [regex]::Matches($contentStream, $pattern)

# Build a map of Y-position -> list of (X, decoded-text)
$lineMap = @{}
foreach ($b in $blocks) {
    $x = [double]$b.Groups[1].Value
    $y = $b.Groups[2].Value  # Keep as STRING to avoid locale decimal issues
    $hex = $b.Groups[3].Value

    # Decode hex pairs to characters
    $decoded = -join (for ($j = 0; $j -lt $hex.Length; $j += 2) {
        [char][Convert]::ToInt32($hex.Substring($j, 2), 16)
    })

    if (-not $lineMap.ContainsKey($y)) {
        $lineMap[$y] = [System.Collections.Generic.List[PSCustomObject]]::new()
    }
    $lineMap[$y].Add([PSCustomObject]@{ X = $x; Text = $decoded })
}
```

### Step 5: Reconstruct Lines (Y-Coordinate Ordering)

PDF Y-coordinates increase upward — highest Y = top of page:

```powershell
$sortedYs = $lineMap.Keys | Sort-Object { [double]$_ } -Descending
$textLines = foreach ($yKey in $sortedYs) {
    $parts = $lineMap[$yKey] | Sort-Object X
    ($parts | ForEach-Object { $_.Text }) -join ''
}
```

### Step 6: Convert to Markdown

Once you have the text lines, analyze the structure and format as Markdown:

- **Separator lines** (all `_` or `-`) → use `---` or table borders
- **Header lines** (larger font, centered) → `#` / `##` headings
- **Columnar data** → Markdown tables (`| col1 | col2 |`)
- **Labeled values** (e.g., `Name: John`) → key-value tables

## Recipe 1b: Fast Line-by-Line Parsing (Batch/Bulk)

For bulk conversion of many PDFs, the regex approach in Steps 4-5 is too slow
and can hang indefinitely on larger files.

> **CRITICAL: The regex patterns in Steps 4-5 cause catastrophic backtracking on large decompressed content streams. For files >250KB or batch processing, use the line-by-line approach below.**

This approach replaces regex with `String.IndexOf` for stream boundary detection
and pure string operations for text extraction.

### Stream Boundary Detection (IndexOf)

```powershell
# Find stream boundaries using IndexOf (much faster than regex)
$idx = 0
while ($true) {
    $sIdx = $raw.IndexOf('stream', $idx)
    if ($sIdx -lt 0) { break }
    $nlIdx = $raw.IndexOf("`n", $sIdx)
    if ($nlIdx -lt 0) { break }
    $dataStart = $nlIdx + 1
    $eIdx = $raw.IndexOf('endstream', $dataStart)
    if ($eIdx -lt 0) { break }
    $dataEnd = $eIdx
    if ($dataEnd -gt $dataStart -and $raw[$dataEnd - 1] -eq "`n") { $dataEnd-- }
    if ($dataEnd -gt $dataStart -and $raw[$dataEnd - 1] -eq "`r") { $dataEnd-- }
    # Process stream...
    $idx = $eIdx + 9
}
```

### Line-by-Line Text Extraction

After decompressing each stream, extract text using pure string operations
instead of regex:

```powershell
$lines = $text.Split("`n")
for ($li = 0; $li -lt $lines.Length; $li++) {
    $line = $lines[$li].Trim()
    # (text)Tj
    if ($line.EndsWith('Tj') -and $line.Contains('(')) {
        $openParen = $line.IndexOf('(')
        $closeParen = $line.LastIndexOf(')')
        if ($openParen -ge 0 -and $closeParen -gt $openParen) {
            $val = $line.Substring($openParen + 1, $closeParen - $openParen - 1)
            if ($val.Length -gt 0) { $allText.Add($val) }
        }
    }
    # <hex>Tj
    elseif ($line.EndsWith('Tj') -and $line.Contains('<')) {
        $openAngle = $line.IndexOf('<')
        $closeAngle = $line.IndexOf('>')
        if ($openAngle -ge 0 -and $closeAngle -gt $openAngle) {
            $hex = $line.Substring($openAngle + 1, $closeAngle - $openAngle - 1)
            if ($hex.Length -ge 2 -and $hex.Length % 2 -eq 0) {
                try { $val = ConvertFrom-HexString $hex; $allText.Add($val) } catch {}
            }
        }
    }
    # [...]TJ array
    elseif ($line.EndsWith('TJ') -and $line.Contains('[')) {
        # Parse brackets, extract paren and hex text
    }
}
```

### Helper: ConvertFrom-HexString (PS 5.1 Compatible)

```powershell
function ConvertFrom-HexString {
    param([string]$Hex)
    $chars = New-Object System.Collections.Generic.List[char]
    for ($i = 0; $i -lt $Hex.Length; $i += 2) {
        $chars.Add([char][Convert]::ToInt32($Hex.Substring($i, 2), 16))
    }
    return -join $chars
}
```

> **Note:** This approach sacrifices Y-coordinate line reconstruction but is 10x faster and sufficient for text extraction.

## Pitfalls and Lessons Learned

### Terminal Blocking
**CRITICAL**: Never use Word COM (`New-Object -ComObject Word.Application`) for
PDF conversion in VS Code terminals. Word COM:
- Blocks the terminal thread while processing
- Hangs on `Documents.Open()` for PDFs (conversion dialog)
- Leaves orphaned `WINWORD.EXE` processes
- Is unreliable even when run in detached processes

Use the .NET native approach instead.

### Locale/Culture Decimal Separator
When using `[double]` values as hashtable keys, use the **raw string** from the
PDF (e.g., `"820.20"`) — not `.ToString()` which may produce `"820,20"` on
German-locale systems, causing all entries to collide into one key.

### PDF Encoding
German PDFs typically use **ISO-8859-1** (Latin-1) encoding for text. This
correctly handles `ü` (`FC`), `ö` (`F6`), `ä` (`E4`), `ß` (`DF`), `§` (`A7`).
Do **not** assume UTF-8 for PDF content streams.

### Hex vs Parenthesis Text
PDFs encode text strings in two forms:
- `<hex>Tj` — hex-encoded (most common in generated PDFs)
- `(text)Tj` — literal parenthesis-encoded (also common)
Check for both patterns when parsing.

### Multi-Page PDFs
Each page may have its own content stream. The page objects in the PDF
cross-reference table link to their content streams. For multi-page documents,
iterate all streams that contain `BT` operators.

### PowerShell 5.1 Compatibility

The code in Steps 4-5 uses PowerShell 7+ syntax that fails in Windows PowerShell 5.1:
- `[System.IO.MemoryStream]::new()` → use `New-Object System.IO.MemoryStream` instead
- `-join (for ($j = 0; ...) { ... })` → extract to a helper function instead
- `[System.Collections.Generic.List[PSCustomObject]]::new()` → `New-Object System.Collections.Generic.List[PSCustomObject]`

Since Outlook COM requires PS 5.1 (`GetActiveObject`), any script combining COM
and PDF conversion must use PS 5.1 compatible syntax throughout.

### Size Cap for Batch Processing

When processing hundreds of PDFs, add a file size cap to prevent hangs:
```powershell
$fi = New-Object System.IO.FileInfo($PdfPath)
if ($fi.Length -gt 10MB) { return 'TOO_LARGE' }
```
Files >10MB with complex content streams can cause memory exhaustion or
extremely long processing times. Sort files by size (smallest first) so
the majority complete quickly.

### Here-String Terminal Corruption

When creating PS scripts via terminal here-strings (`@' ... '@`), pipe
characters (`|`) inside markdown table syntax cause PowerShell parse errors.
Use `StringBuilder` to construct markdown content instead of here-strings
with embedded `|` characters.

### When This Approach Fails
- **Scanned PDFs**: No text operators — need OCR (Tesseract, Azure AI)
- **CIDFont/ToUnicode mapping**: Some PDFs use glyph IDs instead of character
  codes — requires parsing the font's ToUnicode CMap table
- **Complex layouts**: Multi-column, overlapping text, rotated text
- **Encrypted PDFs**: Content streams are encrypted — need decryption first

## Recipe 2: pdftotext (If Available)

The fastest option when xpdf/poppler tools are installed:

```powershell
# Install via chocolatey (requires admin)
choco install xpdf-utils -y

# Or via winget (search for available package)
winget search pdftotext

# Extract with layout preservation
pdftotext -layout input.pdf output.txt

# Then convert the text file to Markdown manually or with formatting logic
```

## Recipe 3: Python pymupdf (If Available)

```powershell
# Install
pip install pymupdf

# Extract
python -c "
import pymupdf
doc = pymupdf.open('input.pdf')
for page in doc:
    print(page.get_text())
"
```

## Recipe 4: Scanned / Image-only PDFs — Tesseract OCR Fallback

When `pymupdf`/`pdftotext` return mostly empty text (e.g. < ~40 chars per page
after stripping headers), the PDF is **image-based** (typical for phone scans
via Microsoft Lens, Office Lens, CamScanner, Adobe Scan). Use pymupdf to
**render pages to PNG at 300 DPI** and pipe them through Tesseract.

### Windows installation (non-admin friendly)

```powershell
# 1) Install Tesseract via winget (system scope — --scope user fails)
winget install --id UB-Mannheim.TesseractOCR --silent `
  --accept-source-agreements --accept-package-agreements

# 2) The installer's tessdata in 'Program Files\Tesseract-OCR\tessdata'
#    is NOT writable without admin. Install extra languages to user scope:
$userTess = "$env:LOCALAPPDATA\tessdata"
New-Item -ItemType Directory -Path $userTess -Force | Out-Null
Copy-Item 'C:\Program Files\Tesseract-OCR\tessdata\eng.traineddata' $userTess -Force
Copy-Item 'C:\Program Files\Tesseract-OCR\tessdata\osd.traineddata' $userTess -Force

# 3) Download high-quality language model (tessdata_best, LSTM trained):
Invoke-WebRequest `
  -Uri 'https://github.com/tesseract-ocr/tessdata_best/raw/main/deu.traineddata' `
  -OutFile "$userTess\deu.traineddata" -UseBasicParsing

# 4) Persist TESSDATA_PREFIX for the user
[Environment]::SetEnvironmentVariable('TESSDATA_PREFIX', $userTess, 'User')
$env:TESSDATA_PREFIX = $userTess
$env:PATH += ';C:\Program Files\Tesseract-OCR'

tesseract --list-langs   # should list deu, eng, osd
```

Use `tessdata_best` (not the default `tessdata_fast` from the installer) for
best accuracy on German documents. File size ~9 MB per language.

### Detection heuristic — does the PDF need OCR?

A PDF with a text layer returns non-trivial text per page. Image-only PDFs
return a few characters of header noise or nothing. Good threshold:

```python
import re
def needs_ocr(pdf_path, body_text):
    # Strip page-break headers first
    body = re.sub(r"## Seite \d+", "", body_text).strip()
    # Dynamic threshold: < 40 chars per page = image-based
    import pymupdf
    pages = len(pymupdf.open(pdf_path))
    return len(body) < max(30, 40 * pages)
```

Run a **two-pass extraction**: first pass with pymupdf text, then re-process
any file below the threshold with OCR. This catches PDFs that have *some*
extractable text (page numbers, watermarks) but need OCR for the real content.

### Python OCR script (pymupdf + Tesseract subprocess)

```python
import os, pathlib, subprocess, sys, tempfile
import pymupdf

TESS = r"C:\Program Files\Tesseract-OCR\tesseract.exe"
os.environ["TESSDATA_PREFIX"] = os.environ.get(
    "TESSDATA_PREFIX") or os.path.expandvars(r"%LOCALAPPDATA%\tessdata")

def ocr_pdf(pdf: pathlib.Path, lang: str = "deu+eng") -> str:
    doc = pymupdf.open(pdf)
    parts = []
    for i, page in enumerate(doc, 1):
        # 300 DPI grayscale is the sweet spot: accurate + small files
        pix = page.get_pixmap(dpi=300, colorspace=pymupdf.csGRAY)
        # IMPORTANT: do NOT use NamedTemporaryFile(delete=False) on Windows.
        # Tesseract may still hold the file handle when os.unlink runs,
        # causing "Permission denied". Use mkstemp + explicit close + unlink.
        fd, img = tempfile.mkstemp(suffix=".png")
        os.close(fd)
        pix.save(img)
        try:
            out = subprocess.run(
                [TESS, img, "stdout", "-l", lang, "--psm", "6"],
                capture_output=True, text=True, encoding="utf-8",
                env=os.environ,
            )
            parts.append(f"\n\n---\n\n## Seite {i}\n\n{out.stdout.strip()}")
        finally:
            try: os.unlink(img)
            except OSError: pass
    return "".join(parts).strip() + "\n"
```

### Tesseract `--psm` (Page Segmentation Mode) cheat sheet

| PSM | Use for |
|-----|---------|
| `3` | Fully automatic (default) — multi-column docs |
| `6` | **Single uniform block of text** — best for letters, invoices, statements |
| `4` | Single column of variable-size text |
| `11`/`12` | Sparse text (receipts, ID cards) |

For German business documents (invoices, payslips, tax forms, rental
statements), **`--psm 6`** gives the best results.

### Language packs

Use `-l deu+eng` for documents that mix German body text with English
acronyms (common in IT, banking, logistics). Order matters: list the
*dominant* language first. For legal/tax documents in Germany, `deu+eng`
catches both the German prose and English abbreviations like "IBAN", "BIC".

### Running via `uv` (zero-install Python)

When no pinned Python environment exists, use `uv` for on-demand deps:

```powershell
uv run --with pymupdf python scripts\ocr_pdf.py
```

This downloads pymupdf into an ephemeral cache on first use (~50 ms after
warmup) and runs the script — no `pip install`, no venv to manage. On
Windows, `python` in PATH is often the Microsoft Store stub (not a real
Python); `uv run` sidesteps this entirely.

### Common Windows pitfalls

| Pitfall | Symptom | Fix |
|---|---|---|
| `tempfile.NamedTemporaryFile(delete=False)` | `Permission denied` when deleting after tesseract ran | Use `mkstemp` + explicit `os.close(fd)` + `os.unlink` in `finally` |
| winget `--scope user` | `No applicable installer found` | Install system scope (default); dependencies use user-scope tessdata instead |
| `Access to 'C:\ProgramData\chocolatey\lib-bad' is denied` | choco install fails without admin | Prefer `winget` for Tesseract; no admin needed |
| tessdata permission denied | Program Files tessdata not writable | Put extra languages in `%LOCALAPPDATA%\tessdata` + set `TESSDATA_PREFIX` |
| Python launcher `py` not installed | `py: The term … is not recognized` | Use `python`, `python3`, or (preferably) `uv run` |
| Microsoft Store Python stub | `python` prints install banner and exits 1 | Use `uv run`; do not rely on `where.exe python` output |

### Quality vs. effort tradeoff

| Approach | Speed | Accuracy (DE docs) | When |
|---|---|---|---|
| `pymupdf` text extraction | 🚀🚀🚀 | 100% (if text layer present) | First attempt always |
| Tesseract `tessdata_fast` | 🚀🚀 | ~92% | Large batches, print-quality scans |
| Tesseract `tessdata_best` | 🚀 | ~97% | Phone scans, handwritten mixed, umlauts critical |
| Azure AI Document Intelligence | 🐢 (network) | ~99% + structure | Tables, forms, receipts with layout recovery |

For tax/legal documents where a single misread digit (e.g. `7,55` vs. `2,55 €`)
changes the tax owed, **always use `tessdata_best`** and **spot-check the OCR
output against the scanned image** for critical amounts.
