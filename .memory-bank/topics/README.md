---
status: current
last-verified: 2026-07-24
owner: shared
source: .memory-bank/index.md
---

# Memory Bank topics

This optional directory holds durable task-specific or role-specific knowledge
that does not belong in a canonical file or Decision record.

## Admission rules

Create a Memory Bank topic only when all conditions apply:

1. The knowledge must survive the current session.
2. No canonical file or active Custom agent role file owns it.
3. A Memory Bank route or active Custom agent can select it explicitly.
4. The content does not duplicate repository source or another Memory Bank file.

Do not create a Memory Bank topic for transient notes, Session handoffs,
secrets, or facts that repository source already controls.

## Required metadata

Every Memory Bank topic starts with YAML frontmatter containing:

```yaml
status: current
last-verified: YYYY-MM-DD
owner: custom-agent-name
source: repository evidence or source path
```

Use a lowercase hyphenated filename that names one retrieval topic. Split a
file when its sections need different routes or owners, not merely because it
reaches an arbitrary size.

## Routing and retention

- Never load the entire directory by default.
- Select only the Memory Bank topics relevant to the current task.
- Treat repository source as authoritative when a Memory Bank topic conflicts.
- Replace obsolete guidance explicitly or mark it superseded; do not preserve
  contradictory current claims.
- Remove a Memory Bank topic when its content moves into repository source or
  no longer has a durable consumer.
