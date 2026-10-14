---
status: accepted
date: 2026-09-02
last-verified: 2026-10-14
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

## Revision, 2026-10-14: what the verifier and the appender measure

The verifier and the appender this decision relies on now exist, and two
independent reviews of them corrected what the first paragraph of this decision
claims for them.

- **Writable roots are not exact.** The profile no longer anchors "exact
  writable roots". The verifier proves two things: every declared root accepts
  new files and folders, and a fixed, named escape set (the user profile, the
  temp folders, the folder of the profile, the folders of the ledger sink and
  the chain head) is not writable outside them. It does not enumerate the
  filesystem, so closing every other path is the deployment's filesystem policy,
  and the controller never reports the writable set as exact.
- **One identity per run, in a fresh process.** A verifier measures the identity
  and network namespace it runs in, so the controller runs it once per role. It
  runs only as the entry script of a `pwsh -NoProfile -File` process, because a
  function or type defined earlier in a session outranks the ones it measures
  with, and it executes the pinned hook command and the pinned appender only
  after the verifier, the control digests, the immutability of the controls and
  the binding of the running identity to its role have passed.
- **The Remote grant.** A contained run registers no hook that records a Remote
  grant, so a contained deployment pins a copy of the plugin whose `hooks.json`
  registers only the guard, names its interpreter by absolute path, and is the
  file at the root of the pinned script. `GrantRecorderUnregistered` measures
  that registration and an empty grants folder, and does not say that no grant
  can exist: the guard honors any well-formed grant file in a folder the run
  owns, so egress and credentials remain the boundary, as the consequences
  above already say.
- **The ledger.** The appender is bound to the profile when validating, keeps
  one canonical form for every record and refuses any other stored line,
  authenticates its pipe at both ends, and the controller appends a
  `FinalReport` record carrying the digest of the report before it seals, which
  the verifier's `-Revalidate` checks.
- **Still open, and written down.** A privilege that is held but disabled and a
  filtered administrator token are not read, so the run identity must be a
  standard account; hook files a host finds outside the pinned file are not
  read; `-Revalidate` does not bind the ledger to a run id; the chain is not
  keyed; and no test used a second Windows account. See
  [`docs/SECURITY-REVIEW.md`](../../docs/SECURITY-REVIEW.md).
