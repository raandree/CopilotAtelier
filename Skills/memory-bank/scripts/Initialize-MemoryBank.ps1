#Requires -Version 5.1

<#
.SYNOPSIS
    Initializes the canonical Memory Bank base in a repository.
.DESCRIPTION
    Creates .memory-bank and any missing canonical base files. Existing files
    are preserved byte-for-byte. Writes new files as UTF-8 without a byte-order
    mark and returns one result object per canonical file.
.PARAMETER Path
    Existing repository directory in which to initialize .memory-bank.
.EXAMPLE
    ./Initialize-MemoryBank.ps1 -Path C:/Git/MyProject

    Creates only missing canonical Memory Bank files under MyProject.
.OUTPUTS
    System.Management.Automation.PSCustomObject
#>

[CmdletBinding(SupportsShouldProcess)]
[OutputType([PSCustomObject])]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
    [string]$Path = (Get-Location).Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$initializationDate = [DateTime]::UtcNow.ToString('yyyy-MM-dd')
$templates = [ordered]@{
    'index.md' = @'
---
schema-version: 1
loading-mode: routed
status: accepted
owner: shared
last-verified: INITIALIZATION_DATE
source: repository evidence
---

# Memory Bank index

Read this file first. It routes tasks to the smallest relevant set of Memory
Bank files.

## Full-read fallback

Set `loading-mode` to `full` to restore complete-base loading. Also fail open
when this index is missing or invalid, the task is ambiguous, routes conflict,
a listed file is missing, or a critical fact cannot be found. Full mode also
reads every existing `decisions/*.md` record.

## Routing table

Combine routes when a task spans topics. For durable repository writes, also
read `activeContext.md` before editing.

| Route | Task signals | Read |
|---|---|---|
| `general` | General Q&A with no project decision | Index only |
| `continuation` | Resume, current focus, next step | `activeContext.md`, `progress.md` |
| `scope` | Purpose, scope, requirements, Acceptance criteria | `projectbrief.md` |
| `product` | Users, problem, workflow, experience goal | `productContext.md` |
| `implementation` | Code, configuration, build, test, dependency, deployment | `techContext.md`, `activeContext.md` |
| `architecture` | Design, pattern, decision, migration, integration | `systemPatterns.md`, relevant `decisions/*.md` |
| `status` | Progress, recent change, open work | `progress.md`, `activeContext.md` |
| `language` | Canonical terms in authored artifacts | `glossary.md` |
| `interaction-history` | Session analysis, prompt trends, Memory Bank evals | `promptHistory.md`, `progress.md` |
| `role` | Active Custom agent domain workflow | Only that agent's declared role files |

## Authority order

1. The user's current request controls task constraints.
2. Repository source, configuration, tests, and evidence control facts.
3. Accepted decision records control durable architectural choices.
4. Core Memory Bank files control only their assigned topic.
5. Historical logs never override current source.
'@
    'projectbrief.md' = @'
---
status: current
last-verified: INITIALIZATION_DATE
owner: shared
source: repository evidence
---

# Project brief

## Purpose

To confirm from repository evidence.

## Scope

- In scope: To confirm.
- Out of scope: To confirm.

## Stakeholders

- To confirm.

## Acceptance criteria

1. To confirm.
'@
    'productContext.md' = @'
---
status: current
last-verified: INITIALIZATION_DATE
owner: shared
source: repository evidence
---

# Product context

## Problem

To confirm from repository evidence.

## Users

- To confirm.

## Core workflows

1. To confirm.

## Experience goals

- To confirm.
'@
    'activeContext.md' = @'
---
status: current
last-verified: INITIALIZATION_DATE
owner: active-agent
source: current task evidence
---

# Active context

## Current focus

No active implementation task recorded.

## Evidence

- Memory Bank initialized from the canonical base.

## Next step

Confirm project context from repository evidence before durable edits.
'@
    'techContext.md' = @'
---
status: current
last-verified: INITIALIZATION_DATE
owner: active-agent
source: repository evidence
---

# Tech context

## Stack

- To confirm.

## Environment

- To confirm.

## Constraints

- To confirm.

## Validation

- To confirm.
'@
    'progress.md' = @'
---
status: current
last-verified: INITIALIZATION_DATE
owner: active-agent
source: repository evidence
---

# Progress

## Current status

Memory Bank initialized; project status remains to be confirmed.

## Recent milestones

- Canonical Memory Bank base initialized.

## Stable capabilities

- To confirm.

## Open work

- Confirm project status and capabilities from repository evidence.
'@
    'systemPatterns.md' = @'
---
status: current
last-verified: INITIALIZATION_DATE
owner: active-agent
source: repository evidence
---

# System patterns

## Architecture

To confirm from repository evidence.

## Decisions

### Decision 1: Use the canonical Memory Bank base

- Choice: Keep durable project context in .memory-bank.
- Rationale: Preserve evidence-backed context across sessions.
'@
    'promptHistory.md' = @'
---
status: local
last-verified: INITIALIZATION_DATE
owner: shared
source: Substantive turns
---

# Prompt history

Log Substantive turns only.

Line format:
`YYYY-MM-DD HH:mm UTC | agent-name | one-line intent`

Trim entries older than 90 days.
'@
}

$memoryBankPath = Join-Path $Path '.memory-bank'
if (-not (Test-Path -LiteralPath $memoryBankPath -PathType Container)) {
    if ($PSCmdlet.ShouldProcess($memoryBankPath, 'Create Memory Bank directory')) {
        New-Item -ItemType Directory -Path $memoryBankPath -Force | Out-Null
    }
}

$utf8WithoutBom = [Text.UTF8Encoding]::new($false)
foreach ($template in $templates.GetEnumerator()) {
    $filePath = Join-Path $memoryBankPath $template.Key
    if (Test-Path -LiteralPath $filePath -PathType Leaf) {
        [PSCustomObject]@{
            File = $template.Key
            Path = $filePath
            Action = 'Preserved'
        }
        continue
    }

    if ($PSCmdlet.ShouldProcess($filePath, 'Create canonical Memory Bank file')) {
        $resolvedTemplate = $template.Value.Replace(
            'INITIALIZATION_DATE',
            $initializationDate
        )
        $content = ($resolvedTemplate -replace "`r`n", "`n").TrimEnd("`n") + "`n"
        [IO.File]::WriteAllText($filePath, $content, $utf8WithoutBom)
        $action = 'Created'
    } else {
        $action = 'Planned'
    }

    [PSCustomObject]@{
        File = $template.Key
        Path = $filePath
        Action = $action
    }
}
