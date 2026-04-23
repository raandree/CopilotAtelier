---
name: docx-to-markdown
description: >-
  Convert DOCX (Word) files to Markdown using .NET-native ZIP/XML parsing in
  PowerShell — no pandoc, Word COM, or Python required. Extracts paragraph
  text with heading styles, handles both English and German style names.
  Fallback approach when pandoc is unavailable or broken.
  USE FOR: convert docx to markdown, docx to md, extract text from Word,
  parse docx in PowerShell, read docx without Word, Word document extraction,
  docx attachment, pandoc unavailable, pandoc broken, docx without pandoc.
  DO NOT USE FOR: creating DOCX files (use pandoc-docx-export skill),
  preserving complex formatting, tables, images, or tracked changes.
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
