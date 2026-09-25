---
status: current
last-verified: 2026-09-25
owner: software-engineer
source: .memory-bank/decisions and source/
---

# System patterns

Durable relationships and the Decision record index. Read a linked record only
when the task needs it; the repository layout lives in `techContext.md`.

## Decision index

| # | Decision record | Status | Date |
|---|---|---|---|
| 1 | [Use OneDrive when available](decisions/0001-use-onedrive-sync.md) | Accepted | 2026-04-23 |
| 2 | [Parse JSONC-tolerant settings](decisions/0002-parse-jsonc-settings.md) | Accepted | 2026-04-23 |
| 3 | [Preserve unrelated location settings](decisions/0003-preserve-location-settings.md) | Accepted | 2026-04-23 |
| 4 | [Use Agent-to-agent handoffs](decisions/0004-use-agent-handoffs.md) | Accepted | 2026-04-23 |
| 5 | [Scope Instructions with applyTo](decisions/0005-scope-instructions-with-applyto.md) | Accepted | 2026-04-23 |
| 6 | [Require Skill frontmatter](decisions/0006-require-skill-frontmatter.md) | Accepted | 2026-04-23 |
| 7 | [Use Claude Opus 4.8](decisions/0007-use-claude-opus-4-8.md) | Accepted | 2026-07-02 |
| 8 | [Store Session handoffs separately](decisions/0008-store-session-handoffs.md) | Accepted | 2026-05-27 |
| 9 | [Codify the Markdown house style](decisions/0009-codify-markdown-style.md) | Accepted | 2026-07-02 |
| 10 | [Detach long-running PowerShell](decisions/0010-detach-long-running-powershell.md) | Accepted | 2026-07-07 |
| 11 | [Exempt Non-impacting turns](decisions/0011-exempt-non-impacting-turns.md) | Accepted | 2026-07-16 |
| 12 | [Govern the Ubiquitous Language](decisions/0012-govern-ubiquitous-language.md) | Accepted | 2026-07-22 |
| 13 | [Centralize shared lifecycle behavior](decisions/0013-centralize-shared-lifecycle.md) | Accepted | 2026-07-24 |
| 14 | [Prove Memory Bank routing](decisions/0014-prove-memory-bank-routing.md) | Accepted | 2026-07-24 |
| 15 | [Keep native memory role-gated](decisions/0015-keep-native-memory-role-gated.md) | Accepted | 2026-07-24 |
| 16 | [Enforce house rules with hooks](decisions/0016-enforce-house-rules-with-hooks.md) | Accepted | 2026-07-28 |
| 17 | [Keep MCP curation out of scope](decisions/0017-keep-mcp-curation-out-of-scope.md) | Accepted | 2026-07-28 |
| 18 | [Distribute as a Sampler-built PowerShell module](decisions/0018-distribute-as-powershell-module.md) | Accepted | 2026-07-29 |
| 19 | [Gate Skills on the reference validator](decisions/0019-gate-skills-on-the-reference-validator.md) | Accepted | 2026-08-11 |
| 20 | [Refuse a lossy customization merge](decisions/0020-refuse-lossy-customization-merges.md) | Accepted | 2026-08-11 |
| 21 | [Checkpoint the session before compaction](decisions/0021-checkpoint-before-compaction.md) | Accepted | 2026-08-25 |
| 22 | [Own the pre-code phase with a Custom agent](decisions/0022-own-pre-code-phase-with-agent.md) | Accepted | 2026-08-26 |
| 23 | [Adopt Agent Plugins 1.0 without moving Instructions and Prompts](decisions/0023-adopt-agent-plugins-1-0.md) | Accepted | 2026-08-26 |
| 24 | [Measure the session clock in a hook, not in the model](decisions/0024-measure-the-session-clock-in-a-hook.md) | Accepted | 2026-09-02 |
| 25 | [Package specification completion as capability-isolated agents](decisions/0025-package-specification-completion-as-capability-isolated-agents.md) | Accepted | 2026-09-02 |

## Live relationships

- A grader must reject invalid or incomplete evidence before scoring quality.
    Preserve scheduled cases in denominators; substring matching is literal.
    Bound input bytes as well as regex time, and carry severity as data rather
    than inferring it from prose. Grader tests do not prove model behavior.
- Agent conformance needs schema, executable behavior, and containment. Tool
    lists prove schema only. Enforce no-egress across terminals, delegates,
    handoffs, MCP, and hooks; prose cannot sandbox native Windows execution.
- Sensitive-data work separates read-only intake, local transformation, public
    research, and explicitly shared authenticated actions. Tools are capability,
    not authorization; `agents` grants delegation, not body inheritance. Share
    Instructions through references or inline text with a drift test.
- Cross-client discovery is not parity. Compose from one authoritative profile
    through strict parsing and explicit capability mappings. Reject unknown
    grants, remove inexpressible restrictions' tools, and refuse unsupported
    workflows inside the variant. Generated variants require hash ownership.
- A local HTTP verdict is feedback, not authority: the transport proves that a
    hash was posted, not who posted it. Bind feedback to the viewed revision and
    retain chat sign-off. Compare section anchors with parser tokens on every
    read, including locked mutations; refuse disagreement. Prove queued-write
    tests reached the lock with observable readiness, not elapsed time.
    Browser validation stays ephemeral and loopback-only; sharing authentication
    and independent review are user-controlled, with deferred risks explicit.
- The installer maps Agent Plugins payload paths into five `~/.copilot`
    Discovery siblings. Preserve unowned matches, require recorded paths and
    hashes before removal, and keep source and deployment trees separate.
    Windows OneDrive selection needs account-specific metadata, not a generic variable or folder; TargetPath overrides it.
- Profile narrowing validates Selection without granting ownership. Omit it for
    full installs; reread inherited state inside the existing target lock.
- A selected artifact is an untrusted observation, never policy: keep candidates
    off automatically loaded surfaces, apply one content rule at intake and at
    promotion, gate an append-only write on an approved preview hash, and bind
    evidence to the stored record and verified block, not a marker.
- Persist each pending operation before atomic replacement and checkpoint after.
    Reconcile observed hashes, not assumed completion. Guard every ancestor
    below the selected root; trusted aliases sit above it. Placeholders are not
    links, and hashes do not provide a transaction or sandbox.
- Remove verified Discovery links non-recursively, including dangling Unix
    links. Construct literal POSIX filename fixtures with .NET path APIs, not
    the PowerShell provider's separator-normalizing `Join-Path`. Hooks enforce
    unconditional rules; Instructions carry judgement calls. Hook commands
    resolve exact trusted roots and avoid pre-parse `$` substitution.
- CI preserves hidden ownership metadata and canonical temporary paths. Nested
    Node runners clear `NODE_TEST_CONTEXT` and prove tests ran; external checks fail closed and baselines shrink.
    Deduplicate only an exact-head PR, never a stale one. Cancel topic/PR runs,
    not releases. Changelog-only validation cannot publish; release headings
    are unique and checked after the tag-at-HEAD exemption lapses.
- Incident transfers keep version-scoped diagnostics in the owning Skill and
    final outcomes out of eval input. Structural checks are not agent behavior;
    completed requests with zero Skill loads cannot prove body improvements.
    Runner-specific discovery is not native-client or hosted-publication proof.
- A Skill cannot grant tools or override a Custom agent. Conflicting disciplines
    need capability-bounded personas. Auto-sending handoff cycles can run
    unattended; reject them with a graph test.
- Role-record migration is copy-only. Routing has deterministic and label-free evals; `PreCompact` anchors recovery. Avoid cross-type links.
