---
status: accepted
date: 2026-04-23
last-verified: 2026-07-24
owner: software-engineer
source: productContext.md
supersedes: none
---

# Use OneDrive when available

## Context and problem statement

Customizations must follow the user across machines without requiring another
sync service.

## Decision outcome

Use OneDrive as the preferred storage location for the Canonical target. Fall
back to the user profile when OneDrive is unavailable.

## Consequences

- Cross-machine propagation uses infrastructure already available to the user.
- OneDrive sign-in is required for cross-machine sync.
- OneDrive handles file conflicts; the Setup script still selects only one
  Canonical target per machine.

## Confirmation

Verify the selected target and Discovery links after running
`Setup-CopilotSettings.ps1`.
