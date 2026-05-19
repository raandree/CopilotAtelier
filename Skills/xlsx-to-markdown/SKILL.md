---
name: xlsx-to-markdown
description: >-
  Read, create, and edit XLSX (Excel) files. Recipe 1: convert XLSX to
  Markdown tables via .NET-native ZIP/XML parsing in PowerShell — no Excel
  COM, ImportExcel, or Python required. Beyond Extraction: create new
  workbooks and edit existing ones with openpyxl + pandas (no Excel
  install), the cardinal rule "write Excel formulas, never hardcoded
  computed values", header formatting / freeze panes / number formats, and
  a recalc + error-scan pass via LibreOffice headless that catches every
  #REF! / #DIV/0! / #VALUE! / #N/A / #NAME?.
  USE FOR: convert xlsx to markdown, Excel to markdown, xlsx to md, parse
  Excel in PowerShell, read xlsx without Excel, Excel attachment, create
  xlsx, write xlsx with formulas, openpyxl, pandas to_excel, edit xlsx,
  recalc xlsx, scan xlsx for formula errors, #REF! in xlsx, financial
  model in Excel, freeze header row.
  DO NOT USE FOR: Excel charts and pivot tables, Excel COM automation,
  files requiring style preservation that openpyxl drops.
---

# XLSX to Markdown Conversion

## When to Use
- Converting Excel attachments to text for downstream analysis
- Bulk conversion of many XLSX files (e.g., email attachment processing)
- No Excel installation, ImportExcel module, or Python available
- XLSX files contain tabular data (not charts/images)

## How XLSX Files Work
XLSX is a ZIP archive containing XML files:
- `xl/sharedStrings.xml` — shared string table (most cell text is stored here)
- `xl/worksheets/sheet1.xml`, `sheet2.xml`, etc. — worksheet data
- `xl/workbook.xml` — workbook metadata (sheet names)
- Cell references use Excel notation: A1, B2, AA100 (column letters + row number)
- Cell types: `s` = shared string index, `n` or no type = number, inline string = `<is><t>...</t></is>`

## Recipe: .NET Native XLSX Parsing

### Complete Function (PS 5.1 Compatible)

```powershell
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Convert-XlsxToMarkdown {
    param([string]$XlsxPath)
    $mdPath = $XlsxPath -replace '\.xlsx$', '.md'
    if (Test-Path $mdPath) { return 'SKIP' }
    try {
        $zip = [System.IO.Compression.ZipFile]::OpenRead($XlsxPath)
        
        # Step 1: Read shared strings
        $sharedStrings = @()
        $ssEntry = $zip.Entries | Where-Object { $_.FullName -eq 'xl/sharedStrings.xml' }
        if ($ssEntry) {
            $stream = $ssEntry.Open()
            $reader = New-Object System.IO.StreamReader($stream)
            $ssXml = [xml]$reader.ReadToEnd()
            $reader.Close(); $stream.Close()
            $ns = New-Object System.Xml.XmlNamespaceManager($ssXml.NameTable)
            $ns.AddNamespace('s', 'http://schemas.openxmlformats.org/spreadsheetml/2006/main')
            $siNodes = $ssXml.SelectNodes('//s:si', $ns)
            foreach ($si in $siNodes) {
                $text = ''
                $tNodes = $si.SelectNodes('.//s:t', $ns)
                foreach ($t in $tNodes) { $text += $t.InnerText }
                $sharedStrings += $text
            }
        }
        
        # Step 2: Process each worksheet
        $sheetEntries = $zip.Entries | Where-Object {
            $_.FullName -match '^xl/worksheets/sheet\d+\.xml$'
        } | Sort-Object Name
        if ($sheetEntries.Count -eq 0) { $zip.Dispose(); return 'NO_SHEETS' }
        
        $sb = New-Object System.Text.StringBuilder
        $sheetNum = 0
        
        foreach ($sheetEntry in $sheetEntries) {
            $sheetNum++
            $stream = $sheetEntry.Open()
            $reader = New-Object System.IO.StreamReader($stream)
            $sheetXml = [xml]$reader.ReadToEnd()
            $reader.Close(); $stream.Close()
            
            $ns2 = New-Object System.Xml.XmlNamespaceManager($sheetXml.NameTable)
            $ns2.AddNamespace('s', 'http://schemas.openxmlformats.org/spreadsheetml/2006/main')
            
            $rows = $sheetXml.SelectNodes('//s:sheetData/s:row', $ns2)
            if ($rows.Count -eq 0) { continue }
            
            if ($sheetNum -gt 1) { [void]$sb.AppendLine() }
            [void]$sb.AppendLine("## Sheet $sheetNum")
            [void]$sb.AppendLine()
            
            # Step 3: Parse cell references and values
            $allRows = New-Object System.Collections.Generic.List[string[]]
            $maxCols = 0
            
            foreach ($row in $rows) {
                $cells = $row.SelectNodes('s:c', $ns2)
                $rowData = @{}
                $maxColIdx = 0
                
                foreach ($cell in $cells) {
                    $ref = $cell.GetAttribute('r')
                    # Convert column letters to index (A=0, B=1, ..., AA=26)
                    $colLetters = ($ref -replace '\d+', '')
                    $colIdx = 0
                    for ($ci = 0; $ci -lt $colLetters.Length; $ci++) {
                        $colIdx = $colIdx * 26 + ([int][char]$colLetters[$ci] - 64)
                    }
                    $colIdx-- # zero-based
                    if ($colIdx -gt $maxColIdx) { $maxColIdx = $colIdx }
                    
                    # Resolve cell value
                    $cellType = $cell.GetAttribute('t')
                    $vNode = $cell.SelectSingleNode('s:v', $ns2)
                    $val = ''
                    if ($vNode) {
                        if ($cellType -eq 's' -and $sharedStrings.Count -gt 0) {
                            $ssIdx = [int]$vNode.InnerText
                            if ($ssIdx -lt $sharedStrings.Count) {
                                $val = $sharedStrings[$ssIdx]
                            }
                        } else {
                            $val = $vNode.InnerText
                        }
                    }
                    # Check for inline string
                    $isNode = $cell.SelectSingleNode('s:is/s:t', $ns2)
                    if ($isNode) { $val = $isNode.InnerText }
                    
                    $rowData[$colIdx] = $val
                }
                
                if ($maxColIdx + 1 -gt $maxCols) { $maxCols = $maxColIdx + 1 }
                $rowArray = New-Object string[] ($maxColIdx + 1)
                foreach ($key in $rowData.Keys) { $rowArray[$key] = $rowData[$key] }
                $allRows.Add($rowArray)
            }
            
            if ($allRows.Count -eq 0) { continue }
            
            # Step 4: Build Markdown table
            $isFirst = $true
            foreach ($r in $allRows) {
                # Pad to max columns
                if ($r.Length -lt $maxCols) {
                    $padded = New-Object string[] $maxCols
                    for ($pi = 0; $pi -lt $r.Length; $pi++) { $padded[$pi] = $r[$pi] }
                    $r = $padded
                }
                $cleaned = $r | ForEach-Object {
                    if ($_) { $_ -replace '\|', '\|' } else { '' }
                }
                [void]$sb.AppendLine('| ' + ($cleaned -join ' | ') + ' |')
                if ($isFirst) {
                    $sep = $r | ForEach-Object { '---' }
                    [void]$sb.AppendLine('| ' + ($sep -join ' | ') + ' |')
                    $isFirst = $false
                }
            }
        }
        
        $zip.Dispose()
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

## Batch Conversion

```powershell
$xlsxFiles = Get-ChildItem $BasePath -Recurse -Filter '*.xlsx' -EA 0
$ok = 0; $fail = 0; $skip = 0; $count = 0
foreach ($f in $xlsxFiles) {
    $count++
    $fi = New-Object System.IO.FileInfo($f.FullName)
    if ($fi.Length -gt 5MB) { $skip++; continue } # Size cap
    $r = Convert-XlsxToMarkdown -XlsxPath $f.FullName
    switch ($r) {
        'OK' { $ok++ }
        'SKIP' { $skip++ }
        default { $fail++ }
    }
    if ($count % 50 -eq 0) {
        Write-Output "Progress: $count / $($xlsxFiles.Count) | OK: $ok"
    }
}
```

## Pitfalls and Lessons Learned

### File Size Cap (5MB)
Large XLSX files (5MB+) with many shared strings can cause the XML parser to
consume >1.5GB RAM and take minutes to process. Add a size check:
```powershell
$fi = New-Object System.IO.FileInfo($XlsxPath)
if ($fi.Length -gt 5MB) { return 'TOO_LARGE' }
```
Sort files smallest-first to process the majority quickly.

### Shared Strings Are Required
Most XLSX generators store cell text in `xl/sharedStrings.xml` and reference
it by index. If you skip shared strings, most cells appear empty or show
numeric indices instead of text.

### Column Letter Conversion
Excel uses letters for columns: A-Z (1-26), then AA-AZ (27-52), BA-BZ, etc.
The conversion formula:
```powershell
$colIdx = 0
for ($ci = 0; $ci -lt $colLetters.Length; $ci++) {
    $colIdx = $colIdx * 26 + ([int][char]$colLetters[$ci] - 64)
}
$colIdx-- # zero-based
```

### Sparse Rows
XLSX only stores non-empty cells. A row with data in columns A and E will only
have 2 `<c>` elements, not 5. You must pad the array to `maxCols` to align
the Markdown table.

### Pipe Characters in Cell Content
Cell values containing `|` will break Markdown table formatting. Escape them:
```powershell
$val = $val -replace '\|', '\|'
```

### Date and Number Formatting
XLSX stores dates as serial numbers (e.g., 44927 = 2023-01-01) and formatted
numbers as raw values. This basic parser does not apply number formats — dates
appear as integers. For date conversion, check the cell's style reference
against `xl/styles.xml` format codes.

### PS 5.1 Compatibility
All code uses `New-Object` instead of `::new()` and avoids `for`-in-expression
syntax to ensure Windows PowerShell 5.1 compatibility (required when combining
with Outlook COM scripts).

### File Lock Errors
When multiple conversion processes run simultaneously, `WriteAllText` may fail
with "file in use" errors if two processes try to write the same `.md` file.
This is harmless — the file was already written by the other process. Log and
continue.

## Beyond Extraction: Create and Edit XLSX with Formulas

The ZIP/XML reader above is one-way. When the task is to **produce or modify** an XLSX (add a sheet, write formulas, fix a value, add formatting), use `openpyxl` for cell-level work and `pandas` for bulk data. Both install via pip; no Excel installation required.

```powershell
uv pip install openpyxl pandas
```

### The cardinal rule: write formulas, not computed values

A spreadsheet's whole point is recalculation. The most common failure mode when an assistant generates a sheet is computing totals / averages / growth rates in Python and writing the *result* as a hardcoded number. When the user changes an input, the totals don't update. Always write the formula and let Excel recalculate.

```python
import openpyxl
wb = openpyxl.Workbook(); ws = wb.active
ws.append(["Item", "Qty", "Price", "Line total"])
ws.append(["Pen", 3, 2.50, "=B2*C2"])      # ✅ formula — reacts to changes
ws.append(["Pad", 5, 4.00, "=B3*C3"])
ws["D4"] = "=SUM(D2:D3)"                       # ✅ not Python's sum()
# ws["D4"] = 22.5                              # ❌ hardcoded total; breaks the moment a price changes
wb.save("order.xlsx")
```

### Edit an existing workbook in place

```python
from openpyxl import load_workbook
wb = load_workbook("existing.xlsx")          # preserves formulas, formatting, charts
ws = wb["Sheet1"]
ws["B5"] = 42                                # change a value
ws.insert_rows(2); ws.delete_cols(7)         # structural edits
new = wb.create_sheet("Notes")
new["A1"] = "Generated 2026-05-19"
wb.save("existing.xlsx")
```

**Trap:** `load_workbook(..., data_only=True)` reads the *last cached* calculated values and **strips formulas on save**. Use it only for reading; never for round-trip edits.

### Recalculate formulas (openpyxl does not compute)

openpyxl writes formula strings but never evaluates them. The saved file's cached values stay stale until something opens it. To force recalculation in CI / a script:

```powershell
# Requires LibreOffice (winget install TheDocumentFoundation.LibreOffice)
soffice --headless --calc --convert-to xlsx --outdir recalc\ in.xlsx
```

LibreOffice opens the file, recomputes every formula, and writes the result. Then scan for errors:

```python
from openpyxl import load_workbook
wb = load_workbook("recalc/in.xlsx", data_only=True)
ERRORS = {"#REF!", "#DIV/0!", "#VALUE!", "#N/A", "#NAME?", "#NULL!", "#NUM!"}
found = []
for ws in wb.worksheets:
    for row in ws.iter_rows():
        for c in row:
            if isinstance(c.value, str) and c.value in ERRORS:
                found.append((ws.title, c.coordinate, c.value))
if found:
    raise SystemExit(f"Formula errors: {found}")
```

Fix every `#REF!` / `#DIV/0!` before declaring the workbook ready. A `#REF!` is a deleted-row/column footprint; `#DIV/0!` means a denominator hits zero and needs an `IFERROR` wrapper.

### Common formatting (when the user asks for it)

```python
from openpyxl.styles import Font, PatternFill, Alignment
from openpyxl.utils import get_column_letter
ws["A1"].font = Font(bold=True, color="FFFFFF")
ws["A1"].fill = PatternFill("solid", fgColor="1F4E79")
ws["A1"].alignment = Alignment(horizontal="center")
ws.column_dimensions["A"].width = 22
ws.freeze_panes = "A2"                       # freeze header row
```

For data analysts: use pandas (`df.to_excel("out.xlsx", index=False)`) when the deliverable is just data; switch to openpyxl when formulas, formatting, or multiple sheets matter.

### Verification checklist before handing off a workbook

- [ ] Every calculation is a formula, not a hardcoded value.
- [ ] LibreOffice recalc pass ran; no `#REF!` / `#DIV/0!` / `#VALUE!` remain.
- [ ] Currency / percentage / date columns have explicit number formats (`ws.cell(...).number_format = "#,##0.00"`).
- [ ] Header row is frozen and bold (matches the convention of pre-existing templates when editing one).
- [ ] Test by changing an input cell in Excel/LibreOffice and confirming dependent cells update.
