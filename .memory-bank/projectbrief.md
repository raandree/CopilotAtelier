# Project brief: CopilotAtelier

## Overview

CopilotAtelier is a portable GitHub Copilot customization framework that synchronizes custom AI agents, coding instructions, skills, and prompt files across multiple machines. It eliminates the need to manually configure VS Code's Copilot settings on each workstation by storing all customizations in `~/CopilotAtelier/` (and optionally `~/OneDrive/CopilotAtelier/` when OneDrive is available) and redirecting VS Code to use those locations. The setup script derives its folder name from the repository, so renaming the repo clone renames the synced layout automatically.

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
