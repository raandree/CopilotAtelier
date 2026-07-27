---
status: accepted
date: 2026-07-07
last-verified: 2026-07-24
owner: software-engineer
source: Instructions/powershell-execution-safety.instructions.md
supersedes: synchronous-pester
---

# Detach long-running PowerShell entry points

## Context and problem statement

Pester and build entry points can block the VS Code terminal or PowerShell
Extension while buffering output.

## Decision outcome

Run Pester and build entry points through the cross-platform detached launcher,
write unique logs under `$env:TEMP`, and inspect completion on demand. Keep
ordinary one-shot commands synchronous and reserve asynchronous terminal mode
for indefinite processes.

## Consequences

- Tests and builds cannot freeze the controlling editor process.
- Result files provide deterministic completion evidence.
- Foreground sleep loops and hand-written polling are prohibited.

## Confirmation

Verify launcher metadata, result code, persistent log, and the real target
state for long operations.
