---
status: current
last-verified: 2026-10-14
owner: software-engineer
source: .memory-bank/decisions and source/
---

# System patterns

Durable relationships and the Decision record index; read a linked record only when the task needs it.

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
| 26 | [Declare runtime tool names next to VS Code names](decisions/0026-declare-runtime-tool-names-next-to-vs-code-names.md) | Accepted | 2026-09-29 |
| 27 | [Calibrate answers to the contributor](decisions/0027-calibrate-answers-to-the-contributor.md) | Accepted | 2026-09-30 |
| 28 | [Persist Familiarity levels in a private Contributor profile](decisions/0028-persist-familiarity-levels-in-a-private-contributor-profile.md) | Accepted | 2026-10-06 |

## Live relationships

- Tool-hook context remains tool-result data, never instruction or authorization;
    verify provenance in host logs and enforce safety outside the model.
- Detached Pester verdicts use `Result -ne 'Passed'`, not failed-test counts:
    load failures can have zero failed tests, and a null result must fail.
    A `Passed` result with no executed tests stays passed.
- A grader must reject invalid or incomplete evidence before scoring quality.
    Preserve scheduled cases in denominators; substring matching is literal.
    Bound input bytes as well as regex time, and carry severity as data rather
    than inferring it from prose. Grader tests do not prove model behavior.
- Agent conformance needs schema, executable behavior, and containment. Tool
    lists prove schema only; agent-host drops unresolved names (0026). Enforce
    no-egress across terminals, delegates, handoffs, MCP, and hooks; prose is no sandbox. A verifier proves only what it measures: accept a plain shape, never refuse a list of characters (two shells read a `#` differently); relay printable ASCII only; compare names ordinally; call its own checks through the function table; say in each Pass what it does not show (0025).
- Sensitive-data work separates read-only intake, local transformation, public
    research, and explicitly shared authenticated actions. Tools are capability,
    not authorization; `agents` grants delegation, not body inheritance. Share Instructions with a drift test.
- Cross-client discovery is not parity. Compose from one authoritative profile
    with strict parsing and capability mappings. Reject unknown grants, remove
    tools whose restrictions cannot be expressed, refuse unsupported workflows, and hash-own variants.
- A local HTTP verdict is feedback, not authority: the transport proves that a
    hash was posted, not who posted it. Bind feedback to the viewed revision and
    retain chat sign-off. Match anchors to parser tokens even under locks; reject disagreement.
    Prove queued writes reached the lock by readiness, not elapsed time. Browser checks stay
    ephemeral and loopback-only; shared authentication and independent review are user-controlled.
- The installer maps Agent Plugins payload paths into five `~/.copilot`
    Discovery siblings. Preserve unowned matches, remove only recorded paths/hashes,
    and separate source from deployment. Windows OneDrive needs account-specific
    metadata; TargetPath overrides it. Selection grants no ownership: omit it for full installs and reread inside the lock.
- A selected artifact is an untrusted observation, never policy: keep candidates
    off automatically loaded surfaces, apply one content rule at intake and at
    promotion, gate an append-only write on an approved preview hash, and bind
    evidence to the stored record and verified block, not a marker.
- Persist each pending operation before atomic replacement and checkpoint after.
    Reconcile observed hashes, not assumed completion. Guard every ancestor
    below the selected root; trusted aliases sit above it. Placeholders are not
    links, and hashes do not provide a transaction or sandbox. A record and a file that sync separately are pending while half arrived, never inferred. A write goes only to a positively chosen target; only reads fall back to a single or default entry.
- Remove verified Discovery links non-recursively, dangling Unix links too. Make POSIX filename fixtures with .NET path APIs; `Join-Path` normalizes. `Remove-Item` of a dot-file needs `-Force` on Linux and macOS, which a Windows gate never shows (PR #32, CI). `Split-Path -Parent` returns an empty string for the parent of a top-level path off Windows, so a fixture writes its path chain out and a test compares it with the chain the code walks (PR #40, CI).
- Hooks enforce unconditional rules; Instructions carry judgement calls. VS Code runs `windows`, the Copilot SDK host `powershell`, else `command`; every
    branch must work on every OS it can reach without `HOME` or `$`. Prove a host's hook contract in its own runtime (`session.rpc.tools.execute`), not from its docs. State hook latency as a step over a no-op hook divided by a hash-pinned frozen reference's step in the same replicate, the reference being the measured step's own kind of work (0028, A9, A17), with one `w` per tag (A16), never in launches: launch costs diverge across machines and editions (TBD-5). Every writer of a shared state file keeps every field and records before it emits (A12). A hook cannot ask the user safely (the Agent Host approves an `ask` under auto-approve, and a hook `allow` approves in VS Code Local), so a user's authorization travels in their own prompt: a Grant marker makes a `UserPromptSubmit` hook record a short-lived, session-bound grant that the guard consumes. A guard masks a string only when everything it flows into treats it as data, and an unknown write target is not a known-inert one (0016, 2026-10-12). A string that holds a backtick stays scanned unless it is single-quoted, because the host shell is unknown and a POSIX shell substitutes a backtick in double quotes; PowerShell and a POSIX shell can still disagree where a quote ends, which is a documented residual (0016, 2026-10-14). Accept a hook live in each harness against a throwaway repository whose origin is a local bare repository: the bare repository's refs and their file times are the oracle, because the model's account of what ran can be incomplete or wrong (0016, 2026-10-13).
- A gate that a run misses ships as not met, with its limitation named in the record, the matrix, and the PR body; nothing a gate reads moves after the miss (0028, A24, A34).
    A further run needs a new amendment, a spending ruling, and an independent review of any egress code first (A31, A38).
- CI preserves hidden ownership metadata and canonical temporary paths. Nested
    Node runners clear `NODE_TEST_CONTEXT` and prove tests ran; external gates fail closed and baselines shrink.
    Deduplicate exact-head PRs only; cancel topic/PR runs, never releases. Changelog-only checks cannot publish; verify unique release headings after the tag-at-HEAD exemption.
    Runs on `main` queue one at a time (about 25 minutes each) and each publishes a preview, so merge pull requests one at a time; keep `progress.md` and `activeContext.md` out of parallel branches, which each rewrite the same milestone list and so conflict in pairs (#32 to #36).
- Incident transfers keep version-scoped diagnostics in the owning Skill and
    final outcomes out of eval input. Structure or zero-load runs do not prove model behavior; runner discovery proves neither native-client nor hosted publication.
- A Skill cannot grant tools or override a Custom agent. Conflicting disciplines
    need capability-bounded personas. Auto-sending handoff cycles can run
    unattended; reject them with a graph test.
- Send multiline patches through exact native standard input: the terminal's
    string pipeline truncated a valid patch to one line; direct input retained all three in the parser probe.
- Role-record migration is copy-only. Routing has deterministic and label-free evals; `PreCompact` anchors recovery. Avoid cross-type links.
