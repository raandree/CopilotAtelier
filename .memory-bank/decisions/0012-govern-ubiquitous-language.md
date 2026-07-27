---
status: accepted
date: 2026-07-22
last-verified: 2026-07-24
owner: software-engineer
source: .memory-bank/glossary.md
supersedes: none
---

# Govern the Ubiquitous Language with the Glossary

## Context and problem statement

Customizations, documentation, tests, and commits need one stable vocabulary
without banning legitimate general technical words.

## Decision outcome

Use `.memory-bank/glossary.md` as the authoritative Glossary. Require the
`Term | Means | Don't say` shape, domain-qualified forbidden phrases, and a
literal exception for external names, paths, commands, and quoted history.

## Consequences

- Authored artifacts use consistent Canonical terms.
- Missing concepts require an explicit Glossary addition.
- Existing unrelated drift is reported rather than silently rewritten.

## Confirmation

Read the Glossary for governed authoring routes and audit new forbidden phrases
for collisions.
