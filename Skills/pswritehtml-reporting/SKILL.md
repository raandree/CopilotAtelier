---
name: pswritehtml-reporting
description: >-
  Generate polished, interactive HTML reports, dashboards, tables, charts,
  and network diagrams from PowerShell objects with the PSWriteHTML module —
  no HTML, CSS, or JavaScript required. Covers New-HTML, New-HTMLTable
  (DataTables: filtering, paging, conditional formatting), New-HTMLChart,
  Section/Panel/Tab layout, New-HTMLDiagram, Out-HtmlView, large-dataset
  tuning, and HTML email bodies. Cross-platform, dependency-free.
  USE FOR: PSWriteHTML, New-HTML, New-HTMLTable, New-HTMLChart,
  New-HTMLDiagram, Out-HtmlView, HTML report from PowerShell, PowerShell
  dashboard, interactive HTML table, DataTables report, AD/DSC/inventory HTML
  report, conditional formatting table, HTML email body, Save-HTML, Dashimo,
  Emailimo.
  DO NOT USE FOR: sending email (use send-outlook-email), Markdown-to-Outlook
  drafts (use create-outlook-draft), slide decks (use marp-slide-overflow),
  Word/PDF export (use pandoc-docx-export), reading xlsx/pdf/docx (use the
  *-to-markdown skills).
---

# PSWriteHTML Reporting

Turn PowerShell objects into interactive, self-contained HTML reports, dashboards, and email bodies with [PSWriteHTML](https://github.com/EvotecIT/PSWriteHTML) (MIT). Everything nests inside a single `New-HTML { }` scriptblock; no hand-written HTML/CSS/JS.

## When to Use

- Turn `Get-*` output (AD users, services, DSC compliance, inventory, inspection findings) into a browsable report instead of a CSV.
- Build an ops dashboard with sections, panels, tabs, tables, and charts from one script.
- Produce an ad-hoc interactive grid with `Out-HtmlView` (a richer `Out-GridView` that also works cross-platform and headless).
- Draw a network/topology diagram from node/edge data.
- Generate a styled HTML **email body** to hand to a mail sender.

## Install and load

```powershell
Install-Module PSWriteHTML -Scope CurrentUser -Force   # from PowerShell Gallery
Import-Module PSWriteHTML
```

- The Gallery build is dependency-free and minified. Treat the GitHub sources as a dev build only.
- Cross-platform: works on Windows PowerShell 5.1 and PowerShell 7+ (Linux/macOS included) — unlike the Outlook-COM skills, which are Windows-only.
- **Offline by default.** `New-HTML` inlines all CSS/JS so the file opens with no internet. Add `-Online` to link CDN assets instead (smaller file, needs internet to view).

## Container model

`New-HTML` is the root. Omit `-FilePath` and it returns the HTML as a string; pass `-FilePath` to write a file, `-ShowHTML` to open it in the browser.

```powershell
$data = Get-Service | Select-Object Name, Status, StartType, DisplayName

New-HTML -TitleText 'Service report' -FilePath .\services.html -ShowHTML {
    New-HTMLTable -DataTable $data -Filtering -PagingLength 25
}
```

`New-HTMLTable -DataTable` accepts any object array — no pre-formatting needed. `-Filtering` adds per-column search; `-PagingLength` sets rows per page; `-Buttons excelHtml5, searchPanes` adds export/filter buttons; `-SearchBuilder` adds a multi-condition query UI.

## Recipe: conditional formatting

Nest `New-HTMLTableCondition` inside the table's scriptblock. `-Row` styles the whole row; omit it to style just the cell.

```powershell
New-HTML -FilePath .\services.html -ShowHTML {
    New-HTMLTable -DataTable $data {
        New-HTMLTableCondition -Name 'Status' -ComparisonType string `
            -Operator eq -Value 'Stopped' -BackgroundColor Salmon -Color Black -Row
    }
}
```

`-ComparisonType` is `string`, `number`, or `date`; `-Operator` includes `eq`, `ne`, `gt`, `lt`, `ge`, `le`, `between`. For emails (no JavaScript), add `-Inline` so the styling is baked in at generation time.

## Recipe: dashboard layout

`New-HTMLSection` is a titled, collapsible card; `New-HTMLPanel` places children side by side; `New-HTMLTab` creates tabbed views.

```powershell
New-HTML -TitleText 'Ops dashboard' -FilePath .\dashboard.html -ShowHTML {
    New-HTMLSection -HeaderText 'Services' -CanCollapse {
        New-HTMLPanel { New-HTMLTable -DataTable $data -HideFooter }
        New-HTMLPanel {
            New-HTMLChart -Title 'Status split' {
                New-ChartPie -Name 'Running' -Value 42
                New-ChartPie -Name 'Stopped' -Value 8
            }
        }
    }
    New-HTMLTab -Name 'Raw data' { New-HTMLTable -DataTable $data }
}
```

## Recipe: charts

`New-HTMLChart` wraps ApexCharts. Add `New-ChartBar`, `New-ChartLine`, `New-ChartPie`, or `New-ChartDonut` inside it — usually in a `foreach` over your data.

```powershell
$errors = Get-WinEvent -LogName System -MaxEvents 200 |
    Group-Object { $_.TimeCreated.DayOfWeek } |
    Select-Object Name, Count

New-HTML -FilePath .\errors.html -ShowHTML {
    New-HTMLChart -Title 'Events by weekday' {
        foreach ($row in $errors) {
            New-ChartBar -Name $row.Name -Value $row.Count
        }
    }
}
```

## Recipe: network diagram

`New-HTMLDiagram` wraps vis-network. `New-DiagramNode -Label -To` defines a node and its links in one call; `New-DiagramLink` adds styled/labelled edges separately.

```powershell
New-HTML -TitleText 'Network' -FilePath .\net.html -ShowHTML {
    New-HTMLDiagram -Height '600px' {
        New-DiagramNode -Label 'Firewall' -To 'Core switch' -ColorBackground Bisque
        New-DiagramNode -Label 'Core switch' -To 'Server 1', 'Server 2'
        New-DiagramNode -Label 'Server 1'
        New-DiagramNode -Label 'Server 2'
        New-DiagramLink -From 'Server 1' -To 'Server 2' -Label 'replication' -Dashes $true
    }
}
```

Nodes take `-Shape` (box, circle, diamond, hexagon, …), `-IconSolid` / `-IconBrands` / `-IconRegular` (Font Awesome), `-Image`, and `-ID` (use `-ID` when two nodes share a `-Label`). `New-DiagramOptionsPhysics -Enabled $false` freezes auto-layout.

## Recipe: ad-hoc grid (Out-HtmlView)

A drop-in `Out-GridView` alternative that renders an interactive DataTable and works headless / cross-platform.

```powershell
Get-Process | Select-Object -First 20 Name, Id, CPU, WS |
    Out-HtmlView -Filtering -SearchBuilder
```

## Recipe: HTML email body

PSWriteHTML generates the body; a separate skill sends it. Write the report to a file and read it back as a string:

```powershell
$tmp = Join-Path ([IO.Path]::GetTempPath()) 'report.html'
New-HTML -FilePath $tmp {
    New-HTMLText -Text "Backup summary — $(Get-Date -Format 'yyyy-MM-dd')" -FontSize 18 -FontWeight bold
    New-HTMLTable -DataTable $data -HideFooter
}
$htmlBody = Get-Content $tmp -Raw
# Hand $htmlBody to the Outlook COM sender — see the send-outlook-email skill.
```

Email clients ignore JavaScript, so interactive DataTable features degrade to a static styled table — expected. For fully email-optimised (inline-CSS) output, PSWriteHTML also ships the Emailimo command set (`Email`, `EmailHeader`, `EmailBody`, `EmailText`, `EmailTable`, `EmailList`).

> [!WARNING]
> The `Email` command can also send over SMTP directly. Do **not** use its plaintext `-Password ... -PasswordFromFile` pattern. Pass a `[PSCredential]`, or send with Mailozaurr `Send-EmailMessage` using OAuth2 — basic-auth SMTP is disabled on Exchange Online and most modern tenants.

## Large datasets

For tables above a few thousand rows, switch the data store to JavaScript so the browser stays responsive, and control how dates/arrays serialise:

```powershell
New-HTML -FilePath .\big.html -ShowHTML {
    New-HTMLTableOption -DataStore JavaScript -DateTimeFormat 'yyyy-MM-dd HH:mm' -ArrayJoin -ArrayJoinString ', '
    New-HTMLTable -DataTable $huge -SearchBuilder -PagingLength 50
}
```

`-DataStore AjaxJSON` writes data to side-car JSON files (needs a web server; not portable). Default `HTML` store is fine for small reports and required for email.

## Gotchas

- **Nothing renders** — every builder must be inside the `New-HTML { }` block. A `New-HTMLTable` called on its own emits nothing useful.
- **File didn't open** — `-ShowHTML` opens the browser; without it the file is written silently. `-FilePath` is required to write to disk.
- **Duplicate diagram nodes merge** — nodes with the same `-Label` overwrite each other; give each a unique `-ID`.
- **Date sorting looks wrong** — the JavaScript (DataTables) date tokens differ from .NET tokens. Set `-DateTimeSortingFormat` on the table (moment.js tokens like `DD.MM.YYYY`), or use `-Inline` conditions for email.
- **Huge offline files** — inlined assets plus `-BundleImages` on diagrams can produce multi-MB files. Use `-Online` when the report will be viewed with internet access.

## Verify the output

The output is a real file — check it, don't assume:

```powershell
Test-Path .\services.html                       # file was written
(Get-Item .\services.html).Length -gt 0          # non-empty
Select-String -Path .\services.html -Pattern '<table' -Quiet   # table rendered
```

Open it in a browser (or `-ShowHTML`) and confirm the table/chart/diagram is present and interactive.

## See also

- [`send-outlook-email`](../send-outlook-email/SKILL.md) — send the generated `$htmlBody` via Outlook COM (Windows).
- [`pandoc-docx-export`](../pandoc-docx-export/SKILL.md) / [`marp-slide-overflow`](../marp-slide-overflow/SKILL.md) — when the deliverable is Word/PDF or slides, not HTML.
