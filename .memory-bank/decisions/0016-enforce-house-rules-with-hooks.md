---
status: accepted
date: 2026-07-28
last-verified: 2026-10-06
owner: software-engineer
source: VS Code 1.130 agent customization docs; GitHub Copilot hooks configuration reference (2026-09-29); VS Code build 07f806f999 sources and a process capture (2026-10-02); session logs of the 2026-10-02 live checks; a model-free probe of the bundled Copilot SDK runtime (2026-10-04); fake-model conversations with the bundled runtime and Copilot CLI 1.0.92 (2026-10-06)
---

# Enforce house rules with hooks, not prose alone

## Context and problem statement

VS Code 1.130 recognizes seven Customization types. Copilot Atelier shipped
four. The never-push rule, the Memory Bank probe, and the Pre-flight timestamp
were stated only in auto-applied Instructions, so every enforcement depended on
the model choosing to comply. Pre-flight already documents the recurring failure
where an agent concludes that no Memory Bank exists because the workspace
summary omits dotfile folders.

Hooks run a shell command at fixed lifecycle points and honour its exit code, so
the outcome does not depend on model compliance.

## Decision outcome

Ship a `Hooks/` Customization deployed to `~/.copilot/hooks`:

- `PreToolUse` blocks terminal commands that push to a remote, pass
  `--no-verify`, hard-reset, force-clean, or mutate a GitHub resource. The block
  is an explicit exit code 2. `COPILOT_ATELIER_ALLOW_REMOTE=1` was meant as the
  per-command override for an authorized push, but it cannot reach the hook
  from an agent terminal; see the 2026-10-02 revision.
- `SessionStart` probes the filesystem for `.memory-bank/index.md` and injects
  an authoritative present or absent statement plus the UTC timestamp.

Hooks encode rules that must hold regardless of model reasoning. Instructions
keep the judgement calls.

## Consequences

- A remote mutation now requires an explicit environment override, so an agent
  cannot silently push.
- The Memory Bank probe is deterministic; the model no longer has to remember
  to run it.
- Hook scripts become part of the trust boundary. An agent that can edit them
  can rewrite its own guardrails, so they must stay outside auto-approved edit
  scope.
- The block is pattern matching over the command string, not a sandbox. An
  obfuscated or indirectly invoked push can evade it. Treat the hook as
  defense in depth that removes the accidental path, not as a containment
  boundary; the Instruction still carries the rule.
- Hooks are not part of the agent plugin format used here, so plugin installs
  still need the Setup script for enforcement.
- ~~An unreadable payload exits 1, not 2. A schema change degrades to a visible
  warning rather than blocking every tool call.~~ Superseded 2026-09-29: the
  Copilot SDK host denies on exit 1, so an unreadable payload now exits 0. See
  the revision below.

## Revision, 2026-09-29: a second host reads the same file

The Copilot SDK host loads `~/.copilot/hooks/hooks.json` too, and its contract
differs from VS Code's in ways this record assumed away. Verified against the
[GitHub hooks configuration reference](https://docs.github.com/en/copilot/reference/hooks-configuration),
the [VS Code hooks reference](https://code.visualstudio.com/docs/agents/reference/hooks-reference),
and this machine's SDK session logs:

| Concern | VS Code | Copilot SDK host |
|---|---|---|
| Launcher | `windows` on Windows, else `command` | no `windows` key; `powershell` on Windows when present, else `command` |
| `PreToolUse` payload | `tool_name`, `tool_input`, `tool_use_id`, snake_case common fields | same snake_case shape for a PascalCase event; `toolName` and a JSON-string `toolArgs` only for camelCase `preToolUse` |
| Exit `2` | blocks, stderr goes to the model | denies |
| Other non-zero | non-blocking warning | `preToolUse` denies as `hook errored`; other events log and continue |
| Timeout | `timeout`, default 30 s | `timeoutSec`, with `timeout` as its alias; a timeout fails open |
| Reload | not verified | read at session start; an open chat and its subagents keep the old set |
| `SessionStart` output | `hookSpecificOutput.additionalContext` | top-level `additionalContext` only; `hookSpecificOutput` is ignored |
| Session resume | not observed | reruns `sessionStart` with `source: resume` when it reloads a chat (2026-10-02); `Add-SessionContext` keeps that session's clock since 2026-10-04 |
| Spawn on Windows | `powershell.exe -ExecutionPolicy Bypass -NoProfile -NoLogo -Command <windows>` (`HookExecutor`, built-in Copilot extension) | `pwsh.exe -nop -nol -c <powershell>`, else `<command>`, started by `copilot-runtime.exe`; the text reaches `pwsh` unexpanded (2026-10-04) |
| Exit code on Windows | the outer PowerShell reports a failed native command as `1`; the `windows` launcher passes the inner code on since 2026-10-02 | the outer `pwsh` reports a failed `command` as `1`, denied as `hook errored`; the `powershell` launcher passes the code on since 2026-10-02, confirmed live the same day |
| `PreToolUse` reason on exit `2` | standard error; standard output is not read | one JSON object on standard output, merged into the deny only with a top-level `permissionDecisionReason` and, for a PascalCase event, no `hookSpecificOutput`. Otherwise, and for standard error, plain text, or `decision: block`, the model reads `Denied by preToolUse hook: hook exited with code 2` (SDK 1.0.15-preview.4, runtime 1.0.89-7, probed 2026-10-04). The guard prints only the top-level pair since 2026-10-04 |
| `PreToolUse` JSON deny on exit `0` | `hookSpecificOutput.permissionDecision` only | PascalCase: `hookSpecificOutput` when present, else the top level; camelCase: the top level only, so a nested-only deny is allowed; `decision: block` is allowed in both |
| Hook environment | the extension host's environment plus the entry's `env` | the runtime's environment |
| Override set in an agent terminal | never reaches the hook | never reaches the hook; every tool call runs in a new process |

Consequences for the shipped hooks:

- The PascalCase events keep `Block-RemoteMutation` on the `tool_input` shape in
  both hosts, so it needs no second parser.
- An unreadable payload exits 0 with the warning on standard error. That keeps
  the original intent — a schema change must not block every tool call — in the
  host that denies on 1. VS Code no longer raises its warning box for it; the
  message stays in the hook output channel.
- The SDK host runs the launcher inside an outer PowerShell, which reports a
  block (exit 2) as 1. The call is still denied, but the model sees
  `hook errored` instead of the reason.
- Every launcher branch must resolve on every OS it can reach, without `HOME` on
  Windows. `tests/HookLauncher.Tests.ps1` enforces that.
- `Add-SessionContext` writes its context under both keys in one object. Until
  2026-10-01 it wrote only `hookSpecificOutput`, so no SDK session received
  it: seven sessions logged a successful `sessionStart` hook, and none carried
  the context. VS Code's built-in Copilot extension reads only
  `hookSpecificOutput.additionalContext` in its `SessionStart` handler, so the
  top-level copy cannot double the context in Local chats. A probe session on
  2026-10-01 confirmed the SDK side: the host joined every hook's top-level
  `additionalContext` in order, separated by blank lines, for both event
  casings, and dropped nested and plain-text output. The `sessionStart`
  `hook.end` event in `events.jsonl` records what it injected.

## Revision, 2026-10-02: both hosts wrap the launcher on Windows

Evidence from this machine:

- VS Code's workbench picks the launcher in `f5i`: `windows` on Windows, else the
  per-OS key, else `command`. The built-in Copilot extension's `HookExecutor`
  spawns it through `i3a`. When `ComSpec` is `cmd.exe`, the call is
  `%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -NoProfile -NoLogo -Command <launcher>`.
  Exit `2` is a block, and every other non-zero exit is a warning.
- A process capture during a Copilot SDK tool call showed `copilot-runtime.exe`
  starting `"pwsh.exe" -nop -nol -c "<command launcher>"`.
- In that SDK chat, `COPILOT_ATELIER_ALLOW_REMOTE` set in one tool call was gone
  in the next. The baseline probe was denied with `Hook command failed with code
  1` and the guard's reason on stderr, and the model saw `(hook errored)`.

Consequences:

- In VS Code Local chats on Windows the push guard only warned, because the
  deployed `windows` launcher exited `1` under VS Code's spawn. The post-release
  review of the v6.0.0 launcher fix (assessment log, 2026-10-02) rated this a
  Blocker. The `windows` launcher now ends with
  `; exit (@(Get-Variable -Name LASTEXITCODE -ValueOnly -ErrorAction Ignore) + <failure code>)[0]`,
  which the outer PowerShell runs. `command` cannot carry that statement, because
  `sh` runs `command` too.
- The Major findings of that review and of its re-reviews are fixed:
  - The launchers search `USERPROFILE` before `HOME`, so a planted or unreachable
    `HOME` can no longer win or time the guard out.
  - The guard scans the raw payload when it cannot walk it field by field,
    joining split command fields as the walk does. Both join them in document
    order and, within each object, executables first, so arguments written
    before the command, as sorted keys put them, still read as one command.
    The raw scan also joins them across the whole payload, erring toward
    blocking.
  - The guard blocks a payload it has not inspected within five seconds.
    Some patterns slow down quadratically, parsing and walking a payload with
    very many values cannot be interrupted, and a hook timeout lets the call
    through. So it parses only up to 1 MB, walks only up to 20,000 fields and
    nested objects, and
    blocks a payload over 4 MB unscanned.
- The per-command override in the decision outcome cannot work. An authorized
  push runs in the user's own terminal, and the guard's message, `AGENTS.md`, and
  the hooks README say so. A value persisted in the user environment would
  reach every host started later and turn the guard off there, so it must never
  be persisted.
- The Copilot SDK host gets its own `powershell` launcher, which the reference
  says it prefers on Windows: `command` plus the same statement. On a block the
  guard also prints one JSON deny object on standard output, top-level for the
  SDK host and under `hookSpecificOutput` for VS Code. A live check on
  2026-10-02 confirmed that the SDK host runs `powershell`, so exit 2 arrives,
  but its deny still carries no reason; see the revision below.

## Revision, 2026-10-04: one top-level deny object, verified in the runtime

The live checks could not say why the SDK host dropped the reason, so the
runtime was probed directly. `copilot-sdk/index.js` in VS Code's
`@github/copilot-sdk-win32-x64` package started the bundled
`copilot-runtime.exe` with its own `COPILOT_HOME`, a scratch workspace held the
probe hooks in `.github/hooks`, and `session.rpc.tools.execute` ran a
`powershell` call through the session's `preToolUse` pipeline without a model.
The result's `textResultForLlm` is the text the model reads. Each hook variant
was registered under both event casings:

- Exit `2` with one top-level object, with or without the reason also on
  standard error: the model reads `Denied by preToolUse hook: <reason>`.
- Exit `2` with an object that also carries `hookSpecificOutput`, the shape the
  guard printed: the camelCase entry shows the top-level reason, the PascalCase
  entry only `hook exited with code 2`. That is the A2 failure, since
  `hooks.json` registers `PreToolUse`.
- Exit `2` with only `hookSpecificOutput`, only standard error, plain text, or
  `decision: block`: `hook exited with code 2` in both casings.
- Exit `1` or `3`: `Denied by preToolUse hook from "<source>" (hook errored)`.
- Exit `0` with a JSON deny: honored as the table shows, so an object without
  the shape that casing reads allows the call.

VS Code's `HookExecutor` parses standard output only on exit `0`; on exit `2`
it hands standard error to the model. `hookSpecificOutput` on the block path
therefore never reached VS Code either.

Consequences:

- The guard prints only the top-level `permissionDecision` and
  `permissionDecisionReason` and keeps exit `2` and the reason on standard
  error. Both hosts still block on the exit code alone, so a missing or
  malformed object costs only the reason.
- A JSON deny on exit `0` stays rejected: the camelCase path allowed a
  nested-only deny, and a host that does not parse the object would allow the
  call.
- `tests/HookSdkRuntime.Tests.ps1` runs the shipped launcher and the guard
  inside the installed runtime and asserts the reason the model reads. It needs
  Windows, node, and VS Code, and skips without them, for example on a CI
  runner without VS Code.
- The GitHub reference describes the merge without the `hookSpecificOutput`
  condition; that gap is worth reporting upstream.
- Deployed the same day. In a Copilot SDK chat opened before the deploy, the
  A2 probe was denied with `hook exited with code 2` at 12:11 UTC and with the
  full reason at 12:55 UTC: a session keeps the hooks configuration it started
  with, but the launcher resolves the guard on every call. New chats then
  passed A2 (Copilot SDK, 13:18 UTC) and B2 (Local, 13:24 UTC, `Tool execution
  denied: Blocked by Copilot Atelier: …`).

## Revision, 2026-10-06: context after a compaction, PostToolUse, a second file, and launch cost

The spike TBD-1 of [Decision 0028](0028-persist-familiarity-levels-in-a-private-contributor-profile.md)
drove the bundled runtime and the standalone Copilot CLI 1.0.92 against a fake
local model and read every request it received. Its Confirmation section holds
the method and the per-host table. For this record:

- The SDK host and Copilot CLI place the `SessionStart` context in a separate
  user message, and a compaction drops it: the summary keeps only the user's
  own messages. Every line `Add-SessionContext` injects, including the session
  clock path and the never-push reminder, is gone after a compaction in those
  hosts. The Instructions re-sent with every request still carry the rules.
- `PostToolUse` fires only after a successful tool result. The SDK host appends
  the top-level `additionalContext` to the tool result and ignores a
  `hookSpecificOutput` copy; VS Code Local reads only
  `hookSpecificOutput.additionalContext`. One object carrying both keys serves
  both hosts.
- Every `*.json` in the user hooks folder loads for sessions started after the
  file exists; an open session neither gains a new file nor loses a deleted one.
- `tests/HookSdkRuntime.Tests.ps1` asserts these facts in both runtimes.
- Launching a hook costs p95 about 0.86 s through VS Code's spawn and 1.07 s
  through the SDK host's on Prox1 (the push guard on a benign tool, 2026-10-06;
  576 ms and 846 ms on 2026-10-05), almost all of it the outer shell and the
  launcher's own PowerShell. A script's cold code adds roughly 0.07 ms per
  syntax-tree node it runs for the first time in that process, so Decision
  0028's profile reader, about 4,600 nodes, adds about 0.35 s. Keep the common
  path of a hook small; `tests/Fixtures/Measure-CalibrationLatency.ps1` measures
  it.
- Decision 0028 states hook latency in launches of a fixed no-op hook through
  the same launcher and spawn (its ruling A1), not in milliseconds. A change to
  a launcher in `hooks.json` changes that unit: a lighter launcher raises every
  ratio without any regression, a heavier one hides one. Re-run the Meter and
  re-baseline Decision 0028's latency levels in the same change.

## Confirmation

`tests/Hooks.Tests.ps1` runs both scripts through a child process exactly as
VS Code invokes them: eight blocked commands, five allowed commands, a
non-terminal tool whose input mentions a blocked command, the override path, the
unreadable-payload path, both Memory Bank states, and the hook configuration
contract. Since 2026-09-29, `tests/HookLauncher.Tests.ps1` also runs every
launcher through `cmd.exe`, `sh`, and an outer PowerShell with stub scripts, and
the real guard through `cmd.exe` with `HOME` unset: a push exits 2, a benign
command and an unreadable payload exit 0. Since 2026-10-02 it also runs the
`windows` launcher through VS Code's exact spawn, and the real guard through it,
where a push now exits 2. Since 2026-10-04 `tests/HookSdkRuntime.Tests.ps1`
runs the shipped `PreToolUse` launcher and guard inside the Copilot SDK runtime
that VS Code bundles: the model reads the block reason, and a benign command
passes the hook.
