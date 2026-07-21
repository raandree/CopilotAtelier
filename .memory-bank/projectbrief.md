# Project brief: CopilotAtelier

## Overview

CopilotAtelier is a portable GitHub Copilot customization framework that synchronizes custom AI agents, coding instructions, skills, and prompt files across multiple machines. It eliminates the need to manually configure VS Code's Copilot settings on each workstation by storing all customizations in a single repo-derived folder — `~/OneDrive/CopilotAtelier/` when OneDrive is available, or `~/CopilotAtelier/` as a fallback — and redirecting VS Code to use that location. The setup script derives its folder name from the repository, so renaming the repo clone renames the synced layout automatically.

## Core requirements

| # | Requirement | Status |
|---|---|---|
| R1 | Store all Copilot customizations in a single OneDrive-synced folder | Done |
| R2 | Provide a one-command setup script for new machines | Done |
| R3 | Support custom agents with role-specific personas and tools | Done |
| R4 | Support coding instruction files that auto-apply by file glob | Done |
| R5 | Support reusable skills that agents can load on demand | Done |
| R6 | Support prompt files for repeatable slash-command tasks | Done |
| R7 | Idempotent setup (safe to re-run without data loss) | Done |
| R8 | Comprehensive language-specific best practices (PS, MD, YAML, C#, changelog, versioning, Sampler) | Done |

## Target audience

- The repository owner and any machines they sign into with OneDrive
- PowerShell module developers using the Sampler build framework
- Teams needing consistent coding standards enforced via AI-assisted development

## Scope boundaries

- **In scope**: VS Code + GitHub Copilot customization files, setup automation, coding standards
- **Out of scope**: CI/CD pipeline definitions, actual module source code, cloud deployments

## Success criteria

1. Running `Setup-CopilotSettings.ps1` on a fresh machine configures VS Code in under 30 seconds.
2. All custom agents, instructions, skills, and prompts are discoverable in Copilot Chat immediately after restart.
3. Adding a new instruction or agent to OneDrive propagates to all machines automatically.

## Memory-bank always-loaded set

The pre-flight hook reads the following files from `.memory-bank/` when present. New files added here are loaded by every agent on every turn — keep the set small and curated.

| File | Purpose |
|---|---|
| `projectbrief.md` | This file. Scope, requirements, success criteria. |
| `activeContext.md` | Current focus and next steps. |
| `techContext.md` | Technology choices, agent registry. |
| `progress.md` | What works, dated change log. |
| `systemPatterns.md` | Recurring architectural patterns. |
| `productContext.md` | Why the project exists, UX intent. |
| `glossary.md` | **Ubiquitous Language** table (`Term \| Means \| Don't say`). Defines each Canonical term and is loaded automatically on every turn. See [`Instructions/ubiquitous-language.instructions.md`](../Instructions/ubiquitous-language.instructions.md). |
| `promptHistory.md` *(optional)* | Per-turn prompt log. Created on demand. |
