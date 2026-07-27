---
status: accepted
date: 2026-07-24
last-verified: 2026-07-24
owner: software-engineer
source: VS Code 1.130 toolNames.ts and package.json
supersedes: unqualified-native-memory-guidance
---

# Keep native memory role-gated

## Context and problem statement

Eight Custom agents described VS Code native memory but none exposed the
`memory` tool. Adding it broadly would grant access to cross-workspace user
notes to agents that also process untrusted content and have execution or
outbound-capable tools.

## Decision outcome

Keep `memory` out of Custom agent tool allowlists unless a role-specific eval
demonstrates a necessary workflow and an agent-security review proves adequate
containment. Qualify native-memory guidance as conditional and keep the
version-controlled Memory Bank authoritative for shared project knowledge.

## Consequences

- Custom agents cannot directly read or write VS Code native memory.
- Users may supply native notes explicitly or use another active agent that
  exposes the tool.
- A future grant requires a scoped capability case and a new lethal-trifecta
  review; convenience alone is insufficient.

## Confirmation

`tests/SharedLifecycle.Tests.ps1` requires every native-memory reference to
state that `memory` is unavailable, preserve Memory Bank authority, and retain
the existing least-privilege tool allowlist.
