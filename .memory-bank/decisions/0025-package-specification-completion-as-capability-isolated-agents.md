---
status: accepted
date: 2026-09-02
last-verified: 2026-09-02
owner: software-engineer
source: user request and specification-completion package evidence
---

# Package specification completion as capability-isolated agents

## Context and problem statement

A repository with detailed specifications can drift far from implementation.
The requested workflow must inventory every unmet requirement and corroborated
open issue, assign one implementation worker per work item, add unit and
integration tests, gather live evidence when safe, and run unattended within a
bounded overnight window. It must work across repositories, not only FarmSight.

This is high-agency work over untrusted repository, issue, command, test, and
subagent output. One general agent would combine private source, untrusted data,
write and execution authority, delegation, and potentially live-network access.
A Skill would also be unsafe as the entry point: Skills can auto-trigger, cannot
enforce separate tool surfaces per role, and overlap existing testing, review,
and monitoring Skills.

## Decision outcome

Ship one explicit Prompt and three capability-isolated Custom agents.

- `/complete-specifications` is the only entry point. Its body is deliberately
  small, binds directly to `spec-completion-controller`, and does not override
  the controller's tools.
- The controller is neither user-selectable nor model-selectable. It delegates
  only to `spec-work-implementer` and `spec-completion-reviewer`, freezes a
  closure matrix before implementation, and keeps every non-duplicate
  engineering row in the primary denominator.
- Each work item gets a fresh implementer in an isolated worktree. The
  implementer has an exact local search, edit, and execution allow-list, cannot
  delegate, and has no web, GitHub, browser, or MCP tool.
- Each result and the final accounting get a fresh reviewer. The reviewer has an
  exact read/search-only allow-list and cannot edit, execute, delegate, or use a
  network.
- Repository-defined build and test commands are the only repository-derived
  executable inputs. A changed command cannot execute until an independent
  control review passes.
- Controller and worker effective egress sets are empty. Live mode defaults to
  `off`; when explicitly enabled, a separately constrained live runner owns all
  endpoint access and cannot read repository or model context.
- A direct containment-profile SHA-256 anchors an external verifier, exact
  writable roots, hook paths, identities, empty egress, and optional live
  artifacts. A pinned appender stores a monotonic hash-chained ledger outside
  every repository process's writable roots.
- Missing or unverifiable containment, cleanup, review, accounting, or live
  evidence fails closed. The workflow never pushes or mutates shared or
  production targets unattended.

The package reuses existing Skills for TDD, review, agent security, and
long-running monitoring. It does not add another Skill.

## Consequences

- Selecting the Prompt is deliberate consent to the bounded workflow; ordinary
  repository work cannot trigger it automatically.
- The package specifies but does not deploy the operating-system boundary.
  Running it requires an externally prepared profile, verifier, ledger appender,
  identities, filesystem policy, and optional live runner. Missing controls
  produce `BlockedContainment`.
- Implementation, local-test, live-verification, and total closure percentages
  remain separate. Exclusion views are diagnostic and never replace raw primary
  denominators.
- Issue text comes only from an optional local snapshot and can motivate work
  only when tracked repository evidence corroborates it.
- The shared remote-mutation hook remains defense in depth. Deterministic hook
  resolution, exact-path checks, and expanded Git/GitHub CLI matching remove
  accidental bypasses, while measured empty egress remains the security
  boundary.
- Validation must remain static and executable without invoking the new Prompt
  or any packaged agent. A self-run cannot prove its own containment.

## Confirmation

The package, frontmatter, lifecycle, and complete hook slice passed 237 tests.
The native `build,test` workflow passed 957 tests with 0 failures and 78.86%
coverage against a 65% threshold; 108 environment-declared cases were skipped.
Independent agentic-security reviews ended with 0 Critical and 0 High findings.
The Prompt and its three agents were not invoked.
