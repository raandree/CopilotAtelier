---
name: docx-to-markdown
description: >-
  Read and edit DOCX (Word) files without Word or pandoc. Recipe 1: convert
  DOCX to Markdown via .NET-native ZIP/XML parsing in PowerShell (English
  and German style names). Recipe 2: edit a DOCX in place via OOXML
  unpack → edit-XML → repack, with tracked changes (`w:ins` / `w:del` with
  author + date), comments, and accept-all-changes via LibreOffice headless.
  USE FOR: convert docx to markdown, docx to md, extract text from Word,
  parse docx in PowerShell, read docx without Word, edit docx in place,
  edit Word file without Word, add tracked changes to docx, redline Word
  document, add comment to docx programmatically, accept tracked changes,
  OOXML unpack repack, w:ins, w:del, w:commentReference, docx attachment,
  pandoc unavailable, pandoc broken, docx without pandoc.
  DO NOT USE FOR: creating a DOCX from Markdown (use pandoc-docx-export),
  preserving complex formatting on conversion, images, charts, SmartArt.
---

# DOCX to Markdown Conversion (Without Pandoc)

## When to Use

- Pandoc is unavailable, broken, or installed under a different user profile
- Bulk conversion of DOCX attachments for text extraction
- Only text content matters (not formatting, images, or tables)
- No Word COM automation desired (avoids blocking, hangs, orphaned processes)

## Approach Decision Tree

```
DOCX file in workspace
├── Is pandoc available and working?
│   └── YES → Use pandoc (best quality): pandoc file.docx -t markdown -o file.md
├── Is pandoc broken (wrong path, shim issue)?
│   └── Check: pandoc --version  # If it errors, pandoc is broken
│   └── Common issue: Chocolatey shim points to wrong user profile
│   └── Fix: winget install JohnMacFarlane.Pandoc (reinstall under current user)
└── No pandoc available
    └── Use .NET ZIP/XML parsing (this skill)
```

## How DOCX Files Work

DOCX is a ZIP archive containing XML files:
- `word/document.xml` — main document content (paragraphs, runs, text)
- `word/styles.xml` — style definitions
- Namespace: `http://schemas.openxmlformats.org/wordprocessingml/2006/main` (prefix `w`)
- Text is in `<w:t>` elements inside `<w:r>` (run) inside `<w:p>` (paragraph)
- Styles are referenced via `<w:pPr><w:pStyle w:val="Heading1"/></w:pPr>`

## Recipe: .NET Native DOCX Parsing

### Complete Function (PS 5.1 Compatible)

```powershell
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Convert-DocxToMarkdown {
    param([string]$DocxPath)
    $mdPath = $DocxPath -replace '\.docx$', '.md'
    if (Test-Path $mdPath) { return 'SKIP' }
    try {
        $zip = [System.IO.Compression.ZipFile]::OpenRead($DocxPath)
        $docEntry = $zip.Entries | Where-Object { $_.FullName -eq 'word/document.xml' }
        if (-not $docEntry) { $zip.Dispose(); return 'NO_CONTENT' }
        
        $stream = $docEntry.Open()
        $reader = New-Object System.IO.StreamReader($stream)
        $xmlContent = $reader.ReadToEnd()
        $reader.Close(); $stream.Close(); $zip.Dispose()
        
        $xml = [xml]$xmlContent
        $nsMgr = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
        $nsMgr.AddNamespace('w', 'http://schemas.openxmlformats.org/wordprocessingml/2006/main')
        
        $sb = New-Object System.Text.StringBuilder
        $paragraphs = $xml.SelectNodes('//w:p', $nsMgr)
        
        foreach ($para in $paragraphs) {
            $style = $para.SelectSingleNode('w:pPr/w:pStyle/@w:val', $nsMgr)
            $text = ''
            
            # Collect text from all runs (including inside hyperlinks)
            $runs = $para.SelectNodes('.//w:r', $nsMgr)
            foreach ($run in $runs) {
                $t = $run.SelectSingleNode('w:t', $nsMgr)
                if ($t) { $text += $t.InnerText }
            }
            
            if (-not $text -and -not $style) {
                [void]$sb.AppendLine()
                continue
            }
            
            # Map styles to Markdown headings
            $styleName = if ($style) { $style.Value } else { '' }
            switch -Wildcard ($styleName) {
                'Heading1'       { [void]$sb.AppendLine("# $text"); [void]$sb.AppendLine() }
                'Heading2'       { [void]$sb.AppendLine("## $text"); [void]$sb.AppendLine() }
                'Heading3'       { [void]$sb.AppendLine("### $text"); [void]$sb.AppendLine() }
                'Heading4'       { [void]$sb.AppendLine("#### $text"); [void]$sb.AppendLine() }
                'ListParagraph'  { [void]$sb.AppendLine("- $text") }
                # German Word uses Überschrift but XML drops the Ü → berschrift
                'berschrift1'    { [void]$sb.AppendLine("# $text"); [void]$sb.AppendLine() }
                'berschrift2'    { [void]$sb.AppendLine("## $text"); [void]$sb.AppendLine() }
                'berschrift3'    { [void]$sb.AppendLine("### $text"); [void]$sb.AppendLine() }
                default {
                    if ($text) { [void]$sb.AppendLine($text); [void]$sb.AppendLine() }
                }
            }
        }
        
        $result = $sb.ToString().Trim()
        if ($result.Length -gt 0) {
            [System.IO.File]::WriteAllText($mdPath, $result, [System.Text.Encoding]::UTF8)
            return 'OK'
        }
        return 'EMPTY'
    } catch {
        return "ERR: $_"
    }
}
```

## Pitfalls and Lessons Learned

### German Style Names
German Word installations use `Überschrift1`, `Überschrift2` etc. for headings.
In the XML, the `Ü` may be stored differently, resulting in `berschrift1`.
Always match with `-Wildcard` and include both English and German variants.

### Pandoc Chocolatey Shim Issue
Pandoc installed via Chocolatey creates a shim at `C:\ProgramData\chocolatey\bin\pandoc.exe`.
If pandoc was originally installed under a different user (e.g., `otheruser`), the shim
points to `C:\Users\otheruser\AppData\Local\Pandoc\pandoc.exe` — which is inaccessible
to the current user. Error: `Cannot find file at 'c:\users\otheruser\...\pandoc.exe'`.

**Fix**: Reinstall pandoc under the current user via `winget install JohnMacFarlane.Pandoc`.

### .//w:r vs w:r XPath
Use `.//w:r` (with leading dot) to select runs relative to the current paragraph,
including runs inside hyperlinks (`w:hyperlink/w:r`). Plain `w:r` may miss nested runs.

### No Table Support
This basic parser does not convert Word tables to Markdown tables. Tables appear
as concatenated text from each cell. For table-heavy documents, pandoc is strongly
preferred.

### PS 5.1 Compatibility
Uses `New-Object` throughout (not `::new()`) for Windows PowerShell 5.1 compatibility.

### Word COM Is Not an Alternative
Do NOT use `New-Object -ComObject Word.Application` for DOCX conversion:
- Blocks the terminal thread
- Hangs on `Documents.Open()` 
- Leaves orphaned `WINWORD.EXE` processes
- Unreliable even in detached processes

## Beyond Reading: Edit a DOCX In Place via OOXML

The markdown-extraction path above is one-way. When you need to **edit an existing DOCX** (insert tracked changes, add comments, fix a few words, accept reviewer changes) without round-tripping through Markdown and losing formatting, use the unpack → edit XML → repack pattern.

A `.docx` is a ZIP archive of XML; `Compress-Archive` / `Expand-Archive` are sufficient on Windows.

### Unpack → edit → repack (PowerShell)

```powershell
function Edit-Docx {
    param([string]$InPath, [string]$OutPath, [scriptblock]$EditScript)

    $tmp = Join-Path $env:TEMP "docx-$([guid]::NewGuid().ToString('N'))"
    Copy-Item $InPath "$tmp.zip"
    Expand-Archive -Path "$tmp.zip" -DestinationPath $tmp -Force
    Remove-Item "$tmp.zip"

    # $EditScript receives the unpack directory; it edits XML in place.
    & $EditScript $tmp

    # Repack. `[System.IO.Compression.ZipFile]` lets us control the inner path
    # layout exactly; Compress-Archive prepends an extra folder level that Word rejects.
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    if (Test-Path $OutPath) { Remove-Item $OutPath }
    [System.IO.Compression.ZipFile]::CreateFromDirectory($tmp, $OutPath)
    Remove-Item -Recurse -Force $tmp
}
```

The edit happens against `<unpack>/word/document.xml`. Element names are namespaced (`w:` for the main WordprocessingML namespace). Use `Select-Xml` with a namespace manager or string-replace for surgical changes.

### Tracked changes

Insertions and deletions are explicit XML elements wrapping the affected `<w:r>` (run). Replace `30 days` with `60 days` as a tracked edit:

```xml
<w:r><w:t>The term is </w:t></w:r>
<w:del w:id="1" w:author="AI Assistant" w:date="2026-05-19T00:00:00Z">
  <w:r><w:delText>30</w:delText></w:r>
</w:del>
<w:ins w:id="2" w:author="AI Assistant" w:date="2026-05-19T00:00:00Z">
  <w:r><w:t>60</w:t></w:r>
</w:ins>
<w:r><w:t> days.</w:t></w:r>
```

Key rules:

- Inside `<w:del>`, text is `<w:delText>`, not `<w:t>`.
- Each `w:id` must be unique within the document. Use `Get-Random` or a counter.
- Use `w:author="AI Assistant"` so a human reviewer can see what the assistant proposed and accept/reject deliberately.
- Preserve the original `<w:rPr>` (run properties — bold, font, size) inside the new runs to keep formatting intact.
- When deleting an entire paragraph, also mark the paragraph mark deleted (`<w:del>` inside `<w:pPr><w:rPr>`) or accepting changes leaves an empty paragraph.

### Accept all tracked changes

There is no pure-PowerShell way to accept tracked changes. Three options:

- **LibreOffice headless** (preferred): `soffice --headless --convert-to docx:"MS Word 2007 XML" --outdir out\ in.docx` after setting the LibreOffice option `Edit → Track Changes → Manage → Accept All`. Scriptable via a small `.bas` macro or the `unoconv` wrapper.
- **Word COM** — only acceptable when no other Word automation runs in the same script (still subject to the hang/orphan issues above). Use `$doc.Revisions.AcceptAll()` and dispose with `Marshal::ReleaseComObject`.
- **Manual XML pass** — walk `document.xml`, replace every `<w:ins>...</w:ins>` with its inner runs, delete every `<w:del>...</w:del>`. Works for simple docs; breaks on nested rejections.

### Comments

Comments live in `word/comments.xml` (the comment bodies) and are referenced from `document.xml` with `<w:commentRangeStart/>`, `<w:commentRangeEnd/>`, and `<w:commentReference/>`. To add a comment programmatically: append a `<w:comment>` to `comments.xml`, then wrap the target run(s) in the three reference elements with the same `w:id`. If `comments.xml` does not exist (no comments yet), create it and add a `Relationship` to `word/_rels/document.xml.rels` plus a `Content-Type` entry to `[Content_Types].xml`.

### Validation

After repacking, open in Word once before shipping. Word's "file is corrupt" dialog is the only reliable validator on Windows. For CI, install `libreoffice` and run `soffice --headless --cat out.docx > $null` — a non-zero exit means the file is invalid.

### When to use this vs. pandoc

| Goal | Tool |
|---|---|
| DOCX → Markdown | `pandoc` (see top of this file) |
| Markdown → DOCX | `pandoc-docx-export` skill |
| Edit a few words in an existing DOCX without losing formatting | OOXML unpack/repack (this section) |
| Add tracked changes or comments programmatically | OOXML unpack/repack (this section) |
| Bulk accept reviewer changes | LibreOffice headless |

