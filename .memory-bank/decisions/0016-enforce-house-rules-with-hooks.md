---
status: accepted
date: 2026-07-28
last-verified: 2026-07-28
owner: software-engineer
source: VS Code 1.130 agent customization docs
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
- An unreadable payload exits 1, not 2. A schema change degrades to a visible
  warning rather than blocking every tool call.

## Confirmation

`tests/Hooks.Tests.ps1` runs both scripts through a child process exactly as
VS Code invokes them: eight blocked commands, five allowed commands, a
non-terminal tool whose input mentions a blocked command, the override path, the
unreadable-payload path, both Memory Bank states, and the hook configuration
contract.
