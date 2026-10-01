---
status: accepted
date: 2026-07-28
last-verified: 2026-09-29
owner: software-engineer
source: VS Code 1.130 agent customization docs; GitHub Copilot hooks configuration reference (2026-09-29)
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
  is an explicit exit code 2, and `COPILOT_ATELIER_ALLOW_REMOTE=1` is the
  documented per-command override for an authorized push.
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
| Launcher | `windows` on Windows, else `command` | no `windows` key; `command` is copied into `powershell` on Windows |
| `PreToolUse` payload | `tool_name`, `tool_input`, `tool_use_id`, snake_case common fields | same snake_case shape for a PascalCase event; `toolName` and a JSON-string `toolArgs` only for camelCase `preToolUse` |
| Exit `2` | blocks, stderr goes to the model | denies |
| Other non-zero | non-blocking warning | `preToolUse` denies as `hook errored`; other events log and continue |
| Timeout | `timeout`, default 30 s | `timeoutSec`, with `timeout` as its alias; a timeout fails open |
| Reload | not verified | read at session start; an open chat and its subagents keep the old set |
| `SessionStart` output | `hookSpecificOutput.additionalContext` | top-level `additionalContext` only; `hookSpecificOutput` is ignored |

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
  the context.

## Confirmation

`tests/Hooks.Tests.ps1` runs both scripts through a child process exactly as
VS Code invokes them: eight blocked commands, five allowed commands, a
non-terminal tool whose input mentions a blocked command, the override path, the
unreadable-payload path, both Memory Bank states, and the hook configuration
contract. Since 2026-09-29, `tests/HookLauncher.Tests.ps1` also runs every
launcher through `cmd.exe`, `sh`, and an outer PowerShell with stub scripts, and
the real guard through `cmd.exe` with `HOME` unset: a push exits 2, a benign
command and an unreadable payload exit 0.
