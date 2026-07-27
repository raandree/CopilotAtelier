---
schema-version: 1
loading-mode: routed
status: accepted
owner: shared
last-verified: 2026-07-25
source: Instructions/preflight.instructions.md
---

# Memory Bank index

Read this authority map first; it is not a summary of every topic.

## Full-read fallback

Use Full mode when `loading-mode: full`, this index is missing or invalid, the
task is ambiguous, routes conflict, a listed file is missing, or a critical fact
cannot be found. Report the fallback. Full mode reads this index,
`projectbrief.md`, `productContext.md`, `activeContext.md`, `techContext.md`,
`progress.md`, `systemPatterns.md`, every `decisions/*.md`, and local
`promptHistory.md` and `glossary.md` when present. Missing optional files are
not failures.

## Authority order

1. The current request controls task constraints.
2. Repository source, configuration, tests, and evidence control facts.
3. Accepted Decision records control durable choices.
4. Core files control only their routed topic.
5. `progress.md` and `promptHistory.md` are historical evidence.

On conflict, read controlling source, report it, and curate stale knowledge
separately.

## Routing table

Combine routes when a task spans topics. For a durable repository write, also
read `activeContext.md` before editing.

| Route | Task signals | Read |
|---|---|---|
| `general` | General Q&A with no project-specific decision | Index only |
| `continuation` | Resume, current focus, next step, handoff | `activeContext.md`, `progress.md` |
| `scope` | Purpose, scope, requirements, Acceptance criteria | `projectbrief.md` |
| `product` | Users, problem, workflow, experience goal | `productContext.md` |
| `implementation` | Code, configuration, build, test, dependency, deployment | `techContext.md`, `activeContext.md` |
| `architecture` | Design, pattern, decision, migration, integration | `systemPatterns.md`, relevant `decisions/*.md` |
| `status` | Progress, recent change, open work | `progress.md`, `activeContext.md` |
| `language` | Canonical terms in code, tests, documentation, or commits | `glossary.md` |
| `interaction-history` | Session analysis, prompt trends, Memory Bank evals | `promptHistory.md`, `progress.md` |
| `role` | Active Custom agent domain workflow | Only that agent's declared role files |

`topics/*.md` are optional and load only through an explicit route or active
Custom agent. Never read `promptHistory.md` routinely.
