# Speaker-Note Coverage — Gotchas and a Pester Guard (Recipe 5)

> Reference for the `marp-slide-overflow` skill. How to audit "does every slide
> have speaker notes?" on multi-file Marp decks without false positives.

## Contents

- [Gotcha A — the ---inside-a-code-fence trap](#gotcha-a--the----inside-a-code-fence-trap)
- [Gotcha B — distinguishing real notes from Marp directives](#gotcha-b--distinguishing-real-notes-from-marp-directives)
- [Gotcha C — section-divider slides are a separate category](#gotcha-c--section-divider-slides-are-a-separate-category)
- [Pester guard (drop-in)](#pester-guard-drop-in)
- [Title-drift / merge pattern (multi-file decks)](#title-drift--merge-pattern-multi-file-decks)
- [What the editorial marker _split_ is](#what-the-editorial-marker-----split-----is)

Marp speaker notes are HTML comments inside a slide:

```markdown
# My Slide

Body content.

<!--
Speaker notes go here. Multi-line is fine.
- Bullet points work too.
-->
```

They render in **presenter mode** (`marp --preview`) and export as **PPTX slide notes** on `marp --pptx`. Invisible in the rendered slide itself.

Two problems show up the moment you try to audit "does every slide have notes?":

## Gotcha A — the `---`-inside-a-code-fence trap

Many decks show YAML or markdown frontmatter as code examples (`.agent.md`, `SKILL.md`, etc.):

````markdown
# Custom Agents

```markdown
---
name: software-engineer
tools: ['editFiles', 'runTests']
---
# Software Engineer Agent
```
````

A naive separator counter that splits on `^---$` will mis-count those inner `---` delimiters as slide breaks and produce phantom "slides" whose H1 is `name: software-engineer`. Any coverage audit must be **code-fence-aware**: track a boolean `inCode` that toggles on every line matching `^\x60{3}` and ignore `---` while `inCode` is true. Mirror what your build script's slide-splitter does — mismatch between auditor and builder is the bug.

## Gotcha B — distinguishing real notes from Marp directives

Marp uses HTML comments for everything: `<!-- version: 4h -->`, `<!-- _class: dense -->`, `<!-- _paginate: false -->`, `<!-- _backgroundColor: #fff -->`, `<!-- _color: ... -->`, plus any editorial markers your build understands (`<!-- _split_ -->` is a common one). A comment-block-presence check that doesn't filter these will falsely report **every** slide as having notes.

The working filter:

- Treat as a *directive* (not a note) any comment whose trimmed inner text matches `^(version:|_class:|_paginate:|_color:|_backgroundColor:|fit|_split_)`.
- Require the inner text to be **> 40 chars** so single-line directives never count as a note.

## Gotcha C — section-divider slides are a separate category

If your deck splits source into per-module files and synthesises section-divider slides (`<!-- _class: section-divider --># Module N`), those usually receive a per-module *appendix* block (`Speaker notes — Module N appendix…`) instead of a per-slide note. Test dividers separately, with their own assertion.

## Pester guard (drop-in)

This is a complete, working pair of `It` blocks. Helpers go in `BeforeAll` (see also `pester-patterns` skill — Pester 5 isolates each `It` in its own runspace, helpers defined as `Describe` siblings are invisible inside `It`).

```powershell
Describe 'Built MARP outputs have speaker notes on every slide' {
    BeforeAll {
        $script:pptxDir = $PSScriptRoot

        function Get-MarpSlide {
            param([Parameter(Mandatory)][string]$Path)
            $lines  = Get-Content -Path $Path -Encoding UTF8
            $sepIdx = [System.Collections.Generic.List[int]]::new()
            $inCode = $false; $sawFm = $false; $inFm = $false
            for ($i = 0; $i -lt $lines.Count; $i++) {
                $t = $lines[$i].TrimEnd()
                if ($t -match '^```') { $inCode = -not $inCode; continue }
                if ($inCode) { continue }
                if ($t -ne '---') { continue }
                if (-not $sawFm) {
                    if ($inFm) { $sawFm = $true; $inFm = $false; continue }
                    $inFm = $true; continue
                }
                [void]$sepIdx.Add($i)
            }
            $slides = [System.Collections.Generic.List[object]]::new()
            for ($n = 0; $n -lt $sepIdx.Count; $n++) {
                $start = $sepIdx[$n] + 1
                $end   = if (($n + 1) -lt $sepIdx.Count) { $sepIdx[$n + 1] - 1 } else { $lines.Count - 1 }
                $body  = if ($start -le $end) { $lines[$start..$end] -join "`n" } else { '' }
                $title = ($lines[$start..$end] | Where-Object { $_ -match '^#\s+(.+)$' } | Select-Object -First 1)
                if ($title) { $title = ($title -replace '^#\s+', '').Trim() }
                [void]$slides.Add([pscustomobject]@{
                    Number    = $n + 1
                    Title     = $title
                    Body      = $body
                    IsDivider = ($body -match '(?s)<!--\s*_class:\s*section-divider\s*-->')
                })
            }
            return , $slides.ToArray()
        }

        function Test-SlideHasNote {
            param([Parameter(Mandatory)][string]$Body)
            foreach ($m in [regex]::Matches($Body, '(?s)<!--(.*?)-->')) {
                $inner = $m.Groups[1].Value.Trim()
                if ($inner -match '^(version:|_class:|_paginate:|_color:|_backgroundColor:|fit|_split_)') { continue }
                if ($inner.Length -gt 40) { return $true }
            }
            return $false
        }
    }

    It 'every slide in <File> has a speaker-note HTML comment block' -ForEach @(
        @{ File = 'marp-1h-keynote.md'   }
        @{ File = 'marp-2h-standard.md'  }
        @{ File = 'marp-4h-workshop.md'  }
    ) {
        $path = Join-Path $script:pptxDir $File
        if (-not (Test-Path $path)) {
            Set-ItResult -Skipped -Because "$File not built yet"; return
        }
        $slides  = Get-MarpSlide -Path $path
        $missing = foreach ($s in $slides) {
            if ($s.IsDivider) { continue }
            if (-not (Test-SlideHasNote -Body $s.Body)) {
                ('  Slide {0}: {1}' -f $s.Number, $(if ($s.Title) { $s.Title } else { '(no H1)' }))
            }
        }
        $missing | Should -BeNullOrEmpty
    }
}
```

## Title-drift / merge pattern (multi-file decks)

If your build assembles a monolith from per-module split files and merges speaker notes by matching the H1 between split and monolith, **titles will drift**. Ship a `notes-title-map.psd1` next to the build script that aliases split-file H1s to monolith H1s:

```powershell
@{
    'Knowing What AI Changed'  = 'Git Provides Traceability'
    'Rollback When Needed'     = 'Checkpoint System — Rollback When Needed'
    'When AI Validates Its Own Lies' = 'The Cheating-Agent Trap'
}
```

When the coverage test catches a slide with no notes, the three remediation paths in order of preference are:

1. **Add the alias** in `notes-title-map.psd1` (if a split-file slide already has the note under a different H1).
2. **Add notes in the split file** (if the slide has a split-file equivalent that's never had notes).
3. **Add notes inline in the monolith** (only for monolith-only slides — cleanest fix because no merge logic involved).

## What the editorial marker `<!-- _split_ -->` is

It's a comment some teams use to mark "this is where the split was made" or "this slide was generated by splitting an oversized parent." Marp ignores it (any HTML comment is invisible in the rendered slide). The build pipeline ignores it too. Include it in the directive blocklist so it never falsely registers as a speaker note.
