---
status: current
last-verified: 2026-08-27
owner: software-engineer
source: .memory-bank/decisions
---

# System patterns

Durable relationships and the Decision record index. Read a linked record only
when the task needs its rationale or consequences. The repository layout lives
in `techContext.md`, not here.

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

## Live relationships

- A multi-agent cycle is one consent, not four; close-out belongs to one stage,
    and stage rules bind only in an agent body. Its failure path is a ring of
    `send: true` handoffs, unbounded because each handoff starts the receiver
    with fresh context: break the ring in frontmatter, detect rings in a test.
- A risk-scaled subagent rule becomes an unconditional handover when its trigger
    list covers the repository's ordinary work. Costly delegation is a user-set
    switch with a named default; the risk list then gates what the agent reports,
    and the shared Definition of Done must name that deferral or re-create it.
- A corporate overlay agent inherits by inlining its base body between markers;
    a link to another `.agent.md` is inert, so a linking overlay runs as a bare
    fragment. Inlining makes it contradict itself, so the reversed defaults are
    named before the block, not only in a later precedence clause. Containment
    belongs in frontmatter; `agents` and `handoffs` can restore removed egress.
- The module carries the Customizations as its payload; `Install-CopilotAtelier`
    deploys them and creates Discovery links, and the Setup script is a
    clone-only shim over it. The Deployment record in the Canonical target is the
    only place reporting which version is deployed, however it was installed.
- Hooks enforce the rules that must hold regardless of model reasoning;
    Instructions carry the judgement calls.
- The `v*` release tag is the version anchor, not a record of the release.
    GitVersion derives the next pre-release number from it and
    `Publish_Release_To_GitHub` writes it, so a skipped release task freezes the
    version the Gallery holds. It sends `[Unreleased]` as the body, cap 125000.
- Authored guidance takes its form from the baseline failure it corrects:
    prohibitions for a skipped discipline, a recipe for output of the wrong shape,
    a structural slot for an omission, a conditional for context-dependent work.
- A hook command string is substituted before the child parses it, so a `$` token
    reaches the interpreter as nothing. Commands are `$`-free: paths from
    `[Environment]::GetEnvironmentVariable(...)`, exit code from
    `Get-Variable -Name LASTEXITCODE -ValueOnly`, each path rooted with
    `[IO.Path]::Combine('/', ...)` so an unset root cannot reach a workspace.
- A Customization ships to two roots no single variable names: `~/.copilot/<type>`
    and `~/.vscode*/agent-plugins/<host>/<owner>/CopilotAtelier`. `PLUGIN_ROOT` is
    unconfirmed, so resolution probes it first, then both concrete locations.
- A capability measured on one configuration is scoped to what was measured and
    encoded as attempt, validate, escalate — never a verdict.
- A fact the model cannot observe is measured by a hook, never composed by it.
    It has no clock, so timestamps come from `SessionStart` and `Stop`.
- A gate that can skip is not a gate. An external-tool check must fail where it
    is supposed to protect — CI — and must be proven to reject a bad input, or
    it reports a green build with nothing behind it.
- Known debt is a shrink-only baseline keyed to the offending item, never a
    disabled check. The gate proves the fix rather than the intent: an item that
    improves fails until its entry is removed, and a new item cannot join it
    silently.
- Frontmatter is the live control surface: Custom agent tools, model priority,
    subagent eligibility, and handoffs; Instruction `applyTo`; Prompt binding.
- A turn fires on three triggers: a user message, a tool call returning, or a
    harness notification. Only an async command's completion notification can be
    armed by the agent, so unprompted periodic reporting is a chained async timer
    and a fully detached process emits none. A `Stop` hook can force a turn.
- A Skill cannot override a Custom agent body: the body is mode instruction and
    the Skill is advisory. A discipline that contradicts the active persona must
    become a persona of its own, where its tools bound what it can finish.
- Memory Bank routing has two eval layers: human-labelled routes test the
    deterministic resolver and context reduction; label-free prompts test
    natural-language selection with pass@k and pass^k. Compaction bypasses both
    lifecycle gates, so a `PreCompact` hook writes an anchor Pre-flight reads.
- Copilot token usage exists only in the cloud session store. No hook payload,
    transcript record, or local `session-store.db` table carries it, so usage
    telemetry is a Skill over `copilot_sessionStoreSql`, never a hook.
- The plugin package and the deployed tree are different shapes and cannot be
    reconciled. Agent Plugins 1.0 fixes skills at root `skills/` and Copilot
    components under `com.github.copilot/`, while discovery needs five siblings
    under `~/.copilot`. The installer maps deployed name to source path, so a
    cross-type relative link resolves in one tree or the other, never both.
