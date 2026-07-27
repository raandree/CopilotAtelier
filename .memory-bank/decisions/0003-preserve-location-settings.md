---
status: accepted
date: 2026-04-23
last-verified: 2026-07-24
owner: software-engineer
source: Setup-CopilotSettings.ps1
supersedes: none
---

# Preserve unrelated location settings

## Context and problem statement

Replacing complete VS Code location maps destroys user configuration, while
retaining historical CopilotAtelier paths registers a Customization twice.

## Decision outcome

Remove only historical CopilotAtelier entries. Preserve unrelated entries and
add exactly one `~/.copilot/prompts` location. Discover Custom agents,
Instructions, and Skills through Discovery links.

## Consequences

- Setup remains non-destructive to unrelated locations.
- Historical duplicate discovery is removed deterministically.
- Prompts retain the one explicit location that VS Code requires.

## Confirmation

Run the Setup sandbox tests and verify zero legacy entries, one Prompt entry,
and unchanged unrelated entries.
