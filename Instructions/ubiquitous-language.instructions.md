---
applyTo: "**/docs/glossary.md,**/glossary.md,**/memory-bank/glossary.md,**/*.md,**/*.ps1,**/*.py,**/*.cs,**/*.ts,**/*.js"
description: "Enforces the Ubiquitous Language (DDD) pattern: when a glossary.md exists in the workspace, use only canonical terms in code, comments, tests, docs, and commits; never introduce forbidden synonyms."
---

# Ubiquitous Language

Enforce the **Ubiquitous Language** pattern from Eric Evans' *Domain-Driven Design* (2003): the team, the code, and the documents speak the same vocabulary. The repository's `glossary.md` is the single source of truth for that vocabulary.

This instruction is active whenever a glossary file is present at one of the canonical locations:

- `docs/glossary.md`
- `glossary.md` (repo root)
- `memory-bank/glossary.md` (or `.memory-bank/glossary.md`)

## What a Ubiquitous Language file looks like

A checked-in markdown table with exactly these columns:

| Term | Means | Don't say |
|------|-------|-----------|
| Canonical name for the concept | One-sentence definition | Comma-separated forbidden synonyms |

Example:

| Term       | Means                                                                 | Don't say                          |
|------------|-----------------------------------------------------------------------|------------------------------------|
| Tenant     | A paying organisation that owns one or more projects.                 | customer, account, org, workspace  |
| Project    | A billable unit of work owned by exactly one tenant.                  | workspace, repo, site              |
| Reviewer   | A human who approves a change request before merge.                   | approver, gatekeeper, sign-off     |

The table may have additional optional columns (e.g. `Status`, `Owner`, `First introduced`), but the three above are mandatory.

## Rules the agent MUST follow when a glossary exists

1. **Read first.** Before planning any change to code, documentation, tests, or commit messages, read the glossary end-to-end. Treat it as part of the always-loaded context for the turn.
2. **Use canonical terms only.** In every artefact you author or modify — source code, identifiers, comments, log messages, test names, variable names, documentation, commit messages, PR titles, chat replies — use only terms from the `Term` column.
3. **Never use a forbidden synonym.** If a token appears in any `Don't say` cell, do not introduce it. If the user uses a forbidden synonym in their prompt, translate it to the canonical term in your reply and note the translation once (e.g. *"I'll treat 'customer' as `Tenant` per the glossary."*). Do not nag the user about it on every turn.
4. **Missing concept → propose, do not invent.** If you need a word for a concept that is not in the glossary, stop. Propose a new row (`Term | Means | Don't say`) and ask the user to approve adding it. Do not invent a synonym, do not silently reuse the closest existing term.
5. **Drift detection without scope creep.** If you encounter existing code or docs that use a forbidden synonym, flag it (one line, locator + suggested canonical term). Do not silently rewrite unrelated code in the same turn — the rewrite is a separate, user-approved task.

## Worked example

Glossary excerpt:

| Term     | Means                                                | Don't say              |
|----------|------------------------------------------------------|------------------------|
| Tenant   | A paying organisation that owns projects.            | customer, account, org |
| Project  | A billable unit of work owned by exactly one Tenant. | workspace, repo, site  |
| Archive  | Soft-delete a Project so it is read-only.            | delete, remove, purge  |

### Good

```csharp
public Task<Project> CreateProjectAsync(TenantId tenantId, string name) { ... }

// Archived Projects remain readable for 90 days before purge.
public Task ArchiveProjectAsync(ProjectId projectId) { ... }
```

```text
git commit -m "feat(tenant): archive Project on tenant suspension"
```

### Bad

```csharp
public Task<Workspace> CreateWorkspaceAsync(CustomerId customerId, string name) { ... }

// Deleted workspaces are gone forever.
public Task DeleteWorkspaceAsync(WorkspaceId id) { ... }
```

```text
git commit -m "feat(customer): remove workspace on account suspension"
```

Every identifier and every word in the comment and commit message in the *Bad* example is a forbidden synonym. The *Good* example uses the canonical terms exclusively.

## Out of scope

This instruction does **not** govern:

- User-facing UI copy where product/marketing has chosen a different surface vocabulary on purpose. (The internal code, tests, and architecture docs still use the canonical term; only the rendered string differs, and that translation lives in the UI layer.)
- Field names returned by third-party APIs that the team does not control. (Map them to the canonical term at the boundary; do not rename the upstream API.)
- Localisation strings in language resource files.
- Historical commit messages or already-merged code (drift detection only flags; rewrites are separate tasks).

## When the glossary is missing

If none of the canonical locations contain a glossary file, this instruction is dormant — it does not synthesise a vocabulary. The companion behaviour is to suggest adding `docs/glossary.md` the first time the team disagrees about a term; that is a discussion, not an automatic edit.
