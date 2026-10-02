---
status: accepted
date: 2026-07-28
last-verified: 2026-10-02
owner: software-engineer
source: VS Code 1.130 agent customization docs; GitHub Copilot hooks configuration reference (2026-09-29); VS Code build 07f806f999 sources and a process capture (2026-10-02)
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
| Spawn on Windows | `powershell.exe -ExecutionPolicy Bypass -NoProfile -NoLogo -Command <windows>` (`HookExecutor`, built-in Copilot extension) | `pwsh.exe -nop -nol -c <command>`, started by `copilot-runtime.exe` |
| Exit code on Windows | the outer PowerShell reports a failed native command as `1`; the `windows` launcher passes the inner code on since 2026-10-02 | the outer `pwsh` reports a failed `command` as `1`, denied as `hook errored`; the `powershell` launcher passes the code on since 2026-10-02 (live check pending) |
| `PreToolUse` reason on exit `2` | standard error | one JSON object on standard output, merged into the deny; standard error is ignored |
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
- The Major findings of that review and of its two re-reviews are fixed:
  - The launchers search `USERPROFILE` before `HOME`, so a planted or unreachable
    `HOME` can no longer win or time the guard out.
  - The guard scans the raw payload when it cannot walk it field by field.
  - The guard blocks a payload it has not inspected within five seconds.
    Some patterns slow down quadratically, and a hook timeout lets the call
    through.
- The per-command override in the decision outcome cannot work. An authorized
  push runs in the user's own terminal, and the guard's message, `AGENTS.md`, and
  the hooks README say so. A value persisted in the user environment would
  reach every host started later and turn the guard off there, so it must never
  be persisted.
- The Copilot SDK host gets its own `powershell` launcher, which the reference
  says it prefers on Windows: `command` plus the same statement. On a block the
  guard also prints one JSON deny object on standard output, top-level for the
  SDK host and under `hookSpecificOutput` for VS Code. Whether the SDK host runs
  `powershell` exactly as it ran `command` still needs a live check in a new
  chat; if it does not, a block still arrives non-zero and is denied as
  `hook errored`.

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
where a push now exits 2.
