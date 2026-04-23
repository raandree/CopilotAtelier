---
name: pandoc-docx-export
description: >-
  Export Markdown documents to polished DOCX files using pandoc with custom
  formatting: landscape pages for wide tables, custom column widths, reduced
  table font sizes, and proper reference.docx styling. Covers pandoc Lua filter
  authoring, OOXML section breaks, reference document customization, and
  common gotchas.
  USE FOR: convert markdown to docx, export to Word, pandoc export, markdown
  to Word, landscape tables, docx formatting, pandoc Lua filter, table column
  widths, table font size docx, reference.docx, mixed orientation docx,
  wide table formatting, pandoc Word export, document export, emoji shortcodes
  docx, GitHub emoji to Unicode, emoji in Word export, mermaid diagram docx,
  render mermaid to image, mermaid flowchart Word, mermaid Gantt chart image.
  DO NOT USE FOR: converting docx to markdown, PDF export (use LaTeX/weasyprint),
  HTML export, general pandoc usage without Word output.
---

# Pandoc DOCX Export with Custom Formatting

## When to Use

- Exporting Markdown documentation to Word (.docx) format
- Tables are too wide for portrait and need landscape pages
- Specific columns need custom widths (e.g., a description column should be wider)
- Table fonts are too large and waste space
- Mixed portrait/landscape orientation needed in a single document

## Prerequisites

- **pandoc** installed (`winget install JohnMacFarlane.Pandoc`)
- Common install path: `C:\Users\<user>\AppData\Local\Pandoc\pandoc.exe`
- If not on PATH, use the full path in commands

### Pandoc Chocolatey Shim Warning

If pandoc was installed via Chocolatey under a different user account, the shim
at `C:\ProgramData\chocolatey\bin\pandoc.exe` points to the original user's
AppData path (e.g., `C:\Users\otheruser\AppData\Local\Pandoc\pandoc.exe`). This
causes `Cannot find file` errors when running as a different user.

**Detection**: `pandoc --version` returns an error about missing file.

**Fix**: Reinstall under the current user:
```powershell
winget install --id JohnMacFarlane.Pandoc --accept-source-agreements
```

**Fallback**: If pandoc cannot be fixed, use the `docx-to-markdown` skill for
DOCX-to-Markdown conversion (uses .NET ZIP/XML parsing, no pandoc needed).

## Quick Export Command

```powershell
$pandoc = 'C:\Users\otheruser\AppData\Local\Pandoc\pandoc.exe'  # adjust path
& $pandoc input.md -o output.docx --from markdown --to docx `
    --lua-filter landscape-tables.lua `
    --reference-doc reference.docx
```

## Recipe 1: Landscape Pages for Wide Tables

Wide tables (5+ columns) should go on their own landscape page. This requires
injecting OOXML section breaks via a Lua filter.

### Lua Filter Pattern

Create a file named `landscape-tables.lua`:

```lua
-- landscape-tables.lua
-- Tables with N+ columns get their own landscape page.
-- The preceding section heading is pulled onto the landscape page.

-- Portrait section break (A4: 11906 x 16838 twips)
local portrait_break = pandoc.RawBlock('openxml',
  '<w:p><w:pPr><w:sectPr>'
  .. '<w:pgSz w:w="11906" w:h="16838"/>'
  .. '<w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"'
  .. ' w:header="720" w:footer="720" w:gutter="0"/>'
  .. '</w:sectPr></w:pPr></w:p>')

-- Landscape section break (swap width/height, add orient="landscape")
local landscape_break = pandoc.RawBlock('openxml',
  '<w:p><w:pPr><w:sectPr>'
  .. '<w:pgSz w:w="16838" w:h="11906" w:orient="landscape"/>'
  .. '<w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"'
  .. ' w:header="720" w:footer="720" w:gutter="0"/>'
  .. '</w:sectPr></w:pPr></w:p>')

local LANDSCAPE_THRESHOLD = 5  -- minimum columns to trigger landscape

function Pandoc(doc)
  local blocks = doc.blocks
  local result = {}

  for i = 1, #blocks do
    local block = blocks[i]

    if block.t == "Table" and #block.colspecs >= LANDSCAPE_THRESHOLD then
      -- Pull the preceding heading onto the landscape page
      local header = nil
      if #result > 0 and result[#result].t == "Header" then
        header = table.remove(result)
      end

      -- End current portrait section (forces page break)
      table.insert(result, portrait_break)

      -- Re-insert heading on the landscape page
      if header then
        table.insert(result, header)
      end

      table.insert(result, block)

      -- End landscape section (next content returns to portrait)
      table.insert(result, landscape_break)
    else
      table.insert(result, block)
    end
  end

  return pandoc.Pandoc(result, doc.meta)
end
```

### Key OOXML Details

- Page sizes are in **twips** (1/20 of a point). A4 = 11906 x 16838 twips.
- Landscape swaps width/height AND adds `w:orient="landscape"`.
- The `w:sectPr` element defines the section properties for the PRECEDING content.
- Margins: 1440 twips = 1 inch on each side.

### How It Works

The filter uses `pandoc.RawBlock('openxml', ...)` to inject Word XML section breaks
directly into the document stream. Each section break defines the page properties
(size, orientation, margins) for the content that came _before_ it.

Pattern:
1. Insert portrait section break → ends the portrait section
2. Insert table (now in a new section)
3. Insert landscape section break → this section was landscape
4. Next content is a new portrait section automatically

## Recipe 2: Custom Column Widths

When a table has one column that needs more space (e.g., an "Assessment" or
"Description" column), override `colspecs` in the Lua filter.

### Detecting Tables by Header Text

```lua
--- Return the text of a specific header cell (e.g., last column).
local function last_header_text(tbl)
  local head_rows = tbl.head and tbl.head.rows or (tbl.head and tbl.head[2])
  if not head_rows or #head_rows == 0 then return "" end
  local first_row = head_rows[1]
  local cells = first_row.cells or first_row[2]
  if not cells or #cells == 0 then return "" end
  local last_cell = cells[#cells]
  local content = last_cell.contents or last_cell[5]
  if content then return pandoc.utils.stringify(content) end
  return ""
end
```

### Applying Width Profiles

```lua
-- Widths are fractions that MUST sum to 1.0
-- Example: 9-column table where last column gets 60%
local WIDTHS = {0.06, 0.09, 0.04, 0.03, 0.03, 0.04, 0.06, 0.05, 0.60}

local function apply_widths(tbl, widths)
  local specs = {}
  for c = 1, #widths do
    local align = tbl.colspecs[c] and tbl.colspecs[c][1] or pandoc.AlignDefault
    specs[c] = {align, widths[c]}
  end
  tbl.colspecs = specs
end

-- In the Pandoc filter function, match and apply:
if ncols == 9 and last_header_text(block):match("Assessment") then
  apply_widths(block, WIDTHS)
end
```

### colspecs Format

Each entry in `tbl.colspecs` is `{alignment, width}` where:
- `alignment`: `pandoc.AlignDefault`, `pandoc.AlignLeft`, `pandoc.AlignCenter`, `pandoc.AlignRight`
- `width`: fraction of total table width (0.0 to 1.0), or 0 for auto

### Content-Aware Column Optimization (Generic Pattern)

Rather than hand-coding widths per project, use a generic `optimize_columns`
function that inspects header text to classify columns as narrow (integers,
percentages, short labels) or wide (descriptions, notes, assessments).

#### Helper Functions

```lua
--- Return the plain text of a header cell by 1-based index.
local function header_cell_text(tbl, idx)
  local head_rows = tbl.head and tbl.head.rows or (tbl.head and tbl.head[2])
  if not head_rows or #head_rows == 0 then return "" end
  local first_row = head_rows[1]
  local cells = first_row.cells or first_row[2]
  if not cells or idx > #cells then return "" end
  local cell = cells[idx]
  local content = cell.contents or cell[5]
  if content then return pandoc.utils.stringify(content) end
  return ""
end

--- Concatenate all header texts for pattern matching.
local function all_headers(tbl)
  local parts = {}
  for i = 1, #tbl.colspecs do
    parts[i] = header_cell_text(tbl, i)
  end
  return table.concat(parts, "|")
end

local function apply_widths(tbl, widths)
  local specs = {}
  for c = 1, #widths do
    local align = tbl.colspecs[c] and tbl.colspecs[c][1] or pandoc.AlignDefault
    specs[c] = {align, widths[c]}
  end
  tbl.colspecs = specs
end
```

#### Width Profile Strategy

Classify each column header into a size category and assign proportional widths:

| Category | Typical Headers | Width Range |
|----------|----------------|:-----------:|
| **Tiny** | `#`, `ID`, `%` | 0.03–0.05 |
| **Narrow** | `VMs`, `OK`, `Failed`, `Status`, `Level`, `Score` | 0.05–0.10 |
| **Medium** | `Role`, `Domain`, `Date`, `Category`, `Owner` | 0.10–0.18 |
| **Wide** | `Notes`, `Description`, `Assessment`, `Deliverables` | 0.40–0.65 |

**Rules:**
1. Widths MUST sum to exactly 1.0 for correct rendering.
2. Match tables by `ncols` + header keyword — this avoids false matches.
3. Start with the wide column (give it the majority), then allocate remaining
   space to narrow/tiny columns.
4. Integer-only columns (counts, percentages) should be 0.04–0.08.

#### Example: Building Width Profiles

```lua
local function optimize_columns(tbl)
  local ncols = #tbl.colspecs
  local hdrs = all_headers(tbl)

  -- 5-col table: Technology Area | VMs | Status | Completion | Notes
  -- VMs is integers, Completion is %, Notes is free text
  if ncols == 5 and hdrs:match("VMs") and hdrs:match("Technology") then
    apply_widths(tbl, {0.18, 0.05, 0.14, 0.10, 0.53})
    return
  end

  -- 9-col table: VM | Role | Total | OK | Failed | % | Weight | Score | Assessment
  -- Assessment gets the lion's share; numeric columns get 4-5% each
  if ncols == 9 and hdrs:match("Assessment") then
    apply_widths(tbl, {0.07, 0.10, 0.05, 0.04, 0.04, 0.05, 0.07, 0.06, 0.52})
    return
  end

  -- Add more profiles as needed, matching by ncols + header keywords
end
```

#### Integrating with the Pandoc Filter

Call `optimize_columns(block)` inside the `Pandoc(doc)` function for every
table, before deciding on landscape:

```lua
function Pandoc(doc)
  local blocks = doc.blocks
  local result = {}

  for i = 1, #blocks do
    local block = blocks[i]

    if block.t == "Table" then
      optimize_columns(block)  -- apply width profiles first

      if #block.colspecs >= LANDSCAPE_THRESHOLD then
        -- ... landscape handling ...
      else
        table.insert(result, block)
      end
    else
      table.insert(result, block)
    end
  end

  return pandoc.Pandoc(result, doc.meta)
end
```

#### When NOT to Optimize

- Tables with 2–3 columns usually render fine with default widths.
- If a table has no clear "wide" column, leave widths at 0 (auto).
- Don't optimize tables where all columns have similar content length.

## Recipe 3: Smaller Table Font via reference.docx

Pandoc uses a reference document for styles. Modify the Table style's font size:

### Generate and Modify reference.docx

```powershell
$pandoc = 'C:\Users\otheruser\AppData\Local\Pandoc\pandoc.exe'

# 1. Generate the default reference doc
& $pandoc -o reference.docx --print-default-data-file reference.docx

# 2. Unpack
$tempDir = Join-Path $env:TEMP 'pandoc-ref-docx'
if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force }
Expand-Archive -Path reference.docx -DestinationPath $tempDir -Force

# 3. Modify styles.xml — set table font to 8pt (16 half-points)
$stylesPath = Join-Path $tempDir 'word\styles.xml'
[xml]$xml = Get-Content $stylesPath -Raw
$ns = [System.Xml.XmlNamespaceManager]::new($xml.NameTable)
$ns.AddNamespace('w', 'http://schemas.openxmlformats.org/wordprocessingml/2006/main')

foreach ($style in $xml.SelectNodes('//w:style[@w:type="table"]', $ns)) {
    $rPr = $style.SelectSingleNode('w:rPr', $ns)
    if (-not $rPr) {
        $rPr = $xml.CreateElement('w', 'rPr', 'http://schemas.openxmlformats.org/wordprocessingml/2006/main')
        $style.AppendChild($rPr) | Out-Null
    }
    foreach ($elem in @('sz', 'szCs')) {
        $node = $rPr.SelectSingleNode("w:$elem", $ns)
        if (-not $node) {
            $node = $xml.CreateElement('w', $elem, 'http://schemas.openxmlformats.org/wordprocessingml/2006/main')
            $rPr.AppendChild($node) | Out-Null
        }
        # Font size in half-points: 16 = 8pt, 18 = 9pt, 20 = 10pt
        $node.SetAttribute('val', 'http://schemas.openxmlformats.org/wordprocessingml/2006/main', '16')
    }
}
$xml.Save($stylesPath)

# 4. Repack as valid DOCX — MUST use .NET ZipFile, NOT Compress-Archive
Remove-Item reference.docx -Force
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory($tempDir, (Join-Path $PWD 'reference.docx'))

# 5. Cleanup
Remove-Item $tempDir -Recurse -Force
```

### Font Size Reference

OOXML uses half-points for font sizes:

| Half-points | Font size |
|:-----------:|:---------:|
| 14          | 7pt       |
| 16          | 8pt       |
| 18          | 9pt       |
| 20          | 10pt      |
| 22          | 11pt      |
| 24          | 12pt      |

## Critical Gotchas

### 1. NEVER use Compress-Archive for DOCX

`Compress-Archive` creates an invalid DOCX because it nests files under a
subdirectory inside the zip. Always use .NET `ZipFile`:

```powershell
# WRONG — produces invalid DOCX
Compress-Archive -Path (Join-Path $tempDir '*') -DestinationPath output.docx

# CORRECT — proper flat zip structure
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory($tempDir, $outputPath)
```

### 2. Section Breaks Define PRECEDING Content

In OOXML, a `w:sectPr` section break defines the page properties for the content
that came BEFORE it, not after. This is counterintuitive. The flow is:

```
[portrait content]
<portrait sectPr>     ← ends the portrait section
[landscape table]
<landscape sectPr>    ← ends the landscape section
[portrait content]    ← new section, inherits document default (portrait)
```

### 3. Pandoc on PATH

After `winget install`, pandoc may not be on PATH in the current session.
Common location: `C:\Users\<user>\AppData\Local\Pandoc\pandoc.exe`

### 4. colspecs Widths Must Sum to 1.0

If colspec width fractions don't sum to 1.0, the table layout will be incorrect.
A sum less than 1.0 leaves unused space; greater than 1.0 causes overflow.

### 5. Lua Filter Table API Versions

The pandoc Lua API for table internals varies between versions. The patterns
in this skill handle both old and new API styles:

```lua
-- New API (pandoc 2.17+)
local head_rows = tbl.head.rows
local cells = first_row.cells
local content = last_cell.contents

-- Old API (pandoc < 2.17)
local head_rows = tbl.head[2]
local cells = first_row[2]
local content = last_cell[5]
```

Always check both: `tbl.head.rows or tbl.head[2]`

## Recipe 4: Emoji Shortcode Conversion

GitHub-style emoji shortcodes (`:white_check_mark:`, `:warning:`, etc.) render
as literal text in DOCX output. Add a `Str` filter to the Lua file to convert
them to Unicode emoji characters.

### Lua Filter Addition

Add this to the Lua filter (before or after the `Pandoc` function — pandoc
calls each filter function by name, order doesn't matter):

```lua
------------------------------------------------------------------------
-- Emoji shortcode → Unicode replacement
------------------------------------------------------------------------

local emoji_map = {
  white_check_mark       = "\u{2705}",    -- ✅
  hourglass_flowing_sand = "\u{23F3}",    -- ⏳
  calendar               = "\u{1F4C5}",   -- 📅
  no_entry_sign          = "\u{1F6AB}",   -- 🚫
  warning                = "\u{26A0}\u{FE0F}", -- ⚠️
  x                      = "\u{274C}",    -- ❌
  -- Add more as needed from https://unicode.org/emoji/charts/full-emoji-list.html
}

function Str(el)
  local replaced = el.text:gsub(":([a-z_]+):", function(code)
    return emoji_map[code] or (":" .. code .. ":")
  end)
  if replaced ~= el.text then
    return pandoc.Str(replaced)
  end
end
```

### How It Works

- Pandoc parses `:shortcode:` as a literal `Str` element (not as emoji)
- The `Str` filter function pattern-matches `:word:` and replaces with Unicode
- Unknown shortcodes pass through unchanged (keeps the `:code:` text)
- Uses Lua `\u{XXXX}` escape sequences for Unicode codepoints

### Common Emoji Shortcodes

| Shortcode | Unicode | Rendered |
|-----------|---------|:--------:|
| `:white_check_mark:` | U+2705 | ✅ |
| `:hourglass_flowing_sand:` | U+23F3 | ⏳ |
| `:calendar:` | U+1F4C5 | 📅 |
| `:no_entry_sign:` | U+1F6AB | 🚫 |
| `:warning:` | U+26A0 U+FE0F | ⚠️ |
| `:x:` | U+274C | ❌ |
| `:heavy_check_mark:` | U+2714 U+FE0F | ✔️ |
| `:rocket:` | U+1F680 | 🚀 |
| `:construction:` | U+1F6A7 | 🚧 |
| `:tada:` | U+1F389 | 🎉 |
| `:bug:` | U+1F41B | 🐛 |

Add entries to `emoji_map` as needed. The full list is at
https://unicode.org/emoji/charts/full-emoji-list.html

### Gotcha: Font Support

Emoji rendering in Word depends on the system having a color emoji font
(Segoe UI Emoji on Windows, Apple Color Emoji on macOS). If emoji appear as
empty boxes, the system is missing the font — this is rare on modern Windows.

## Recipe 5: Mermaid Diagram Rendering

Mermaid code blocks (` ```mermaid `) render as raw text in DOCX. Add a
`CodeBlock` filter to render them as PNG images via `mmdc` (mermaid-cli).

### Prerequisites

```powershell
# 1. Install mermaid-cli
npm install -g @mermaid-js/mermaid-cli

# 2. Point puppeteer at Edge (avoids downloading a separate Chrome)
$env:PUPPETEER_EXECUTABLE_PATH = "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
```

### Lua Filter Addition

```lua
------------------------------------------------------------------------
-- Mermaid diagram rendering (uses pandoc.pipe for reliable execution)
------------------------------------------------------------------------

local mermaid_counter = 0

function CodeBlock(block)
  if not block.classes:includes("mermaid") then return nil end

  mermaid_counter = mermaid_counter + 1
  local tmpdir = os.getenv("TEMP") or os.getenv("TMPDIR") or "/tmp"
  local infile  = tmpdir .. "/mermaid_" .. mermaid_counter .. ".mmd"
  local outfile = tmpdir .. "/mermaid_" .. mermaid_counter .. ".png"

  -- Write mermaid source to temp file
  local f = io.open(infile, "w")
  if not f then return nil end
  f:write(block.text)
  f:close()

  -- Render via mmdc using pandoc.pipe (handles PATH and env properly)
  local mmdc = os.getenv("MMDC_PATH")
      or (os.getenv("APPDATA") and (os.getenv("APPDATA") .. "\\npm\\mmdc.cmd"))
  if not mmdc then
    io.stderr:write("WARNING: mmdc not found, mermaid block kept as code\n")
    return nil
  end

  local ok, result = pcall(pandoc.pipe, mmdc, {
    "-i", infile,
    "-o", outfile,
    "-b", "white",
    "-s", "2",
    "--quiet"
  }, "")

  if not ok then
    io.stderr:write("WARNING: mermaid render failed for block "
      .. mermaid_counter .. ": " .. tostring(result) .. "\n")
    return nil
  end

  -- Check if output was created
  local img = io.open(outfile, "rb")
  if not img then
    io.stderr:write("WARNING: mermaid output not found for block "
      .. mermaid_counter .. "\n")
    return nil
  end
  img:close()

  -- Return an image element
  return pandoc.Para({pandoc.Image({}, outfile, "",
    pandoc.Attr("", {"mermaid-diagram"}))})
end
```

### How It Works

1. The `CodeBlock` filter matches blocks with the `mermaid` class
2. Writes the mermaid source to a temp `.mmd` file
3. Calls `mmdc` via `pandoc.pipe` (more reliable than `os.execute` on Windows)
4. `mmdc` renders the diagram to a high-res PNG (scale factor 2)
5. The code block is replaced with a `pandoc.Image` element embedding the PNG
6. If rendering fails, the original code block is preserved (graceful degradation)

### Critical Gotchas

#### 1. NEVER use `os.execute` or `io.popen` for mmdc on Windows

`mmdc.cmd` is a batch wrapper that uses `%~dp0` path resolution. Lua's
`os.execute` has quoting issues with Windows batch files, and `io.popen`
has environment propagation problems. Always use `pandoc.pipe` instead:

```lua
-- WRONG — fails silently on Windows with .cmd wrappers
os.execute('"' .. mmdc .. '" -i input.mmd -o output.png')

-- CORRECT — pandoc.pipe handles PATH, env, and argument passing properly
pcall(pandoc.pipe, mmdc, {"-i", infile, "-o", outfile}, "")
```

#### 2. Puppeteer browser — install chrome-headless-shell first

Mermaid-cli uses puppeteer which expects a specific Chrome version. The
`PUPPETEER_EXECUTABLE_PATH` env var does NOT work with mermaid-cli 11+ /
puppeteer 23+. Instead, install `chrome-headless-shell` for the bundled
puppeteer version, then pass a puppeteer config file via `-p`:

```powershell
# 1. Install chrome-headless-shell for the puppeteer version bundled with mermaid-cli
cd "$env:APPDATA\npm\node_modules\@mermaid-js\mermaid-cli"
npx --yes puppeteer@23.11.1 browsers install chrome-headless-shell

# 2. Find the installed path
$chromePath = Get-ChildItem "$env:USERPROFILE\.cache\puppeteer" -Recurse -Filter "chrome-headless-shell.exe" |
    Select-Object -First 1 -ExpandProperty FullName

# 3. Create a puppeteer config file pointing to it
@{ executablePath = $chromePath } | ConvertTo-Json |
    Set-Content "$env:TEMP\puppeteer-config.json" -Encoding UTF8
```

Then in the Lua filter, pass `-p` to mmdc:
```lua
local puppeteer_config = os.getenv("PUPPETEER_CONFIG")
    or (os.getenv("TEMP") and (os.getenv("TEMP") .. "\\puppeteer-config.json"))
local cfg = io.open(puppeteer_config or "", "r")
if cfg then
  cfg:close()
  table.insert(args, "-p")
  table.insert(args, puppeteer_config)
end
```

#### 3. `PUPPETEER_EXECUTABLE_PATH` does NOT work with mermaid-cli 11+

The environment variable `PUPPETEER_EXECUTABLE_PATH` is ignored by newer
puppeteer versions (23+). Do NOT rely on it. Use the `-p` config file
approach from gotcha #2 instead. The old Edge workaround
(`$env:PUPPETEER_EXECUTABLE_PATH = "...msedge.exe"`) silently fails —
mmdc reports "Failed to launch the browser process" with no further detail.

#### 4. The `--quiet` flag

Without `--quiet`, mmdc outputs progress text to stderr that `pandoc.pipe`
may interpret as an error. Always include `--quiet` in the argument list.

#### 5. Scale factor for readability

The default scale factor produces small text in diagrams. Use `-s 2` for
2x resolution which looks crisp in Word at standard zoom:

```lua
"-s", "2",  -- 2x resolution for crisp rendering in Word
```

#### 6. Set MMDC_PATH for non-standard installs

The filter checks `MMDC_PATH` env var first, then falls back to
`%APPDATA%\npm\mmdc.cmd`. For custom installs, set `MMDC_PATH`:

```powershell
$env:MMDC_PATH = "D:\tools\mmdc.cmd"
```

## Complete Export Workflow

1. Install prerequisites:
   ```powershell
   winget install JohnMacFarlane.Pandoc
   npm install -g @mermaid-js/mermaid-cli
   # Install chrome-headless-shell for puppeteer (see gotcha #2)
   cd "$env:APPDATA\npm\node_modules\@mermaid-js\mermaid-cli"
   npx --yes puppeteer@23.11.1 browsers install chrome-headless-shell
   ```
2. Create puppeteer config (one-time, reusable):
   ```powershell
   $chromePath = Get-ChildItem "$env:USERPROFILE\.cache\puppeteer" -Recurse -Filter "chrome-headless-shell.exe" |
       Select-Object -First 1 -ExpandProperty FullName
   @{ executablePath = $chromePath } | ConvertTo-Json |
       Set-Content "$env:TEMP\puppeteer-config.json" -Encoding UTF8
   ```
3. Create `landscape-tables.lua` with table detection + orientation + width + emoji + mermaid logic
4. Create `reference.docx` with custom table font size
5. Export:
   ```powershell
   $pandoc = 'C:\Program Files\Pandoc\pandoc.exe'  # or wherever pandoc is
   & $pandoc input.md -o output.docx `
       --from markdown --to docx `
       --lua-filter landscape-tables.lua `
       --reference-doc reference.docx
   ```
6. All three files (filter, reference doc, export script) are reusable — copy them to any repo

## US Letter Page Size

If targeting US Letter instead of A4, use these dimensions:

```lua
-- US Letter: 12240 x 15840 twips (8.5" x 11")
local portrait_break = pandoc.RawBlock('openxml',
  '<w:p><w:pPr><w:sectPr>'
  .. '<w:pgSz w:w="12240" w:h="15840"/>'
  .. '<w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"'
  .. ' w:header="720" w:footer="720" w:gutter="0"/>'
  .. '</w:sectPr></w:pPr></w:p>')

local landscape_break = pandoc.RawBlock('openxml',
  '<w:p><w:pPr><w:sectPr>'
  .. '<w:pgSz w:w="15840" w:h="12240" w:orient="landscape"/>'
  .. '<w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"'
  .. ' w:header="720" w:footer="720" w:gutter="0"/>'
  .. '</w:sectPr></w:pPr></w:p>')
```
