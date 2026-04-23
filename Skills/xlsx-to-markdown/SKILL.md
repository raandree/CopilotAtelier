---
name: xlsx-to-markdown
description: >-
  Convert XLSX (Excel) files to Markdown tables using .NET-native ZIP/XML
  parsing in PowerShell — no Excel COM, ImportExcel module, or Python required.
  Handles shared strings, cell references, multi-sheet workbooks, inline
  strings, and column letter-to-index conversion.
  USE FOR: convert xlsx to markdown, Excel to markdown, xlsx to md, parse
  Excel in PowerShell, read xlsx without Excel, xlsx to table, spreadsheet
  to text, extract Excel data, xlsx extraction, Excel attachment, costing
  sheet, Excel export.
  DO NOT USE FOR: creating XLSX files, Excel formulas, charts, pivot tables,
  Excel COM automation, or files requiring format/style preservation.
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