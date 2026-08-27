# Hooks

Deterministic guardrails that run at fixed points in the agent loop. Unlike an
Instruction, a hook does not depend on the model choosing to obey it: VS Code
executes the command and honours its exit code.

Setup deploys this folder to the Canonical target and links it to
`~/.copilot/hooks`, which VS Code, the GitHub Copilot CLI, and Claude Code all
read as the user-level hook location.

## Contents

| File | Event | Purpose |
|---|---|---|
| [`hooks.json`](hooks.json) | — | Hook configuration loaded by VS Code |
| [`scripts/Block-RemoteMutation.ps1`](scripts/Block-RemoteMutation.ps1) | `PreToolUse` | Blocks remote-mutating and irreversible commands |
| [`scripts/Add-SessionContext.ps1`](scripts/Add-SessionContext.ps1) | `SessionStart` | Probes for the Memory Bank and injects the UTC timestamp |
| [`scripts/Write-CompactionCheckpoint.ps1`](scripts/Write-CompactionCheckpoint.ps1) | `PreCompact` | Anchors the session on disk before context is truncated |

## Block-RemoteMutation

Inspects any tool input that carries executable command text — `command`,
`commandLine`, `cmd`, `script`, `args`, or `arguments`, at any nesting depth —
rather than deciding from the tool name, so an executor whose name contains no
shell keyword is still covered. It blocks a command that pushes to a git remote,
passes `--no-verify`, runs `git reset --hard`, force-cleans untracked files
(a `-n` dry run is allowed), mutates a pull request, issue, release, repository,
workflow, secret, or cache through the GitHub CLI, or calls `gh api` with a
mutating method or a GraphQL mutation. Shell line continuations are folded first
so a split command cannot hide the subcommand.

Each git rule anchors on the subcommand position, so a branch name, commit
message, or `--grep` value that merely contains the word does not trip it. A
tool with no command-bearing field exits `0` immediately, so editing a document
that mentions `git push` is never blocked. The reason goes to standard error and
the script exits with `2`, which VS Code treats as a blocking error and shows to
the model.

### Authorizing a remote mutation

The house rules allow a push when the user asks for it in the current turn. Set
the escape hatch for that command:

```powershell
$env:COPILOT_ATELIER_ALLOW_REMOTE = '1'
```

Unset it afterwards. The hook records every override on standard error.

## Add-SessionContext

Resolves the session working directory from the hook payload, probes for
`.memory-bank/index.md`, and returns an authoritative statement of whether a
Memory Bank exists, plus the current UTC timestamp. This removes the recurring
failure where an agent concludes "no Memory Bank" from the workspace summary,
which omits dotfile folders.

## Write-CompactionCheckpoint

Post-flight is an end-of-turn gate, so a long turn that is compacted mid-run
never reaches it and everything the run learned goes with the conversation. This
hook writes `.memory-bank/session/compaction-<UTC>Z.md` before the truncation,
recording the trigger, the transcript path, and the branch, commit, and changed
paths at that moment, followed by a resume protocol.

It writes nothing when the workspace has no Memory Bank — creating one is
reserved for a durable repository write under the `memory-bank` Skill — and
nothing when the payload names no workspace, because falling back to the spawn
directory would drop a checkpoint into an unrelated repository. Every failure
path still exits `0`, so a hook fault never blocks compaction.

`PreCompact` supports the common output format only: there is no
`additionalContext` field, so a hook cannot inject text into the post-compaction
context. The user-visible half is `systemMessage`; the model-facing half is the
compaction-recovery section of
[`rules/preflight.instructions.md`](../rules/preflight.instructions.md),
which survives because Instructions are re-sent with every request.

## Verifying the hooks load

1. Run `Developer: Show Agent Debug Logs` from the Command Palette.
2. Look for `Load Hooks` and confirm `~/.copilot/hooks` is listed.
3. Open the Output panel and select the `GitHub Copilot Chat Hooks` channel to
   read hook output and errors.

## Troubleshooting

- **Hook never fires.** Confirm `hooks.json` is present under
  `~/.copilot/hooks` and that the link resolves. Re-run
  [`Setup-CopilotSettings.ps1`](../../Setup-CopilotSettings.ps1).
- **A workspace `.github/hooks/*.json` never fires.** `chat.hookFilesLocations`
  replaces the default location map rather than extending it. A settings value
  of `{ "~/.copilot/hooks": true }` therefore drops `.github/hooks`, and the
  workspace file loads silently as nothing — no error, no log entry. Add
  `".github/hooks": true` alongside the existing entry, or place the hook in
  `~/.copilot/hooks`. Verified by observing a `Stop` hook that executed only
  after the file moved to the deployed folder.
- **Command not found.** A hook command has to locate its own script, because
  the two deployment methods put it in different places: the module installs it
  under `~/.copilot/hooks`, and a plugin install lands in
  `~/.vscode*/agent-plugins/<host>/<owner>/CopilotAtelier/com.github.copilot/hooks`.
  Each command therefore probes `PLUGIN_ROOT`, then the module location, then
  the plugin location, and runs the first script that exists. If you deploy the
  scripts anywhere else, replace the probe in `hooks.json` with an absolute path.
- **The hook dies with a PowerShell parser error.** VS Code hands the command to
  a PowerShell shell, which expands the double-quoted `-Command` argument before
  the child process parses it. A `$` token is therefore consumed by the outer
  shell and reaches the child as an empty string — `$b = if ($env:PLUGIN_ROOT)`
  arrives as `= if ()` and fails with `An expression was expected after '('`.
  Every shipped command is written without a single `$`: paths come from
  `[Environment]::GetEnvironmentVariable(...)` and the blocking exit code from
  `Get-Variable -Name LASTEXITCODE -ValueOnly`. Keep it that way, or the hook
  silently stops guarding anything.
- **Timeout.** The default hook timeout is 30 seconds; these hooks declare 20.
  Increase `timeout` if a slow filesystem delays the Memory Bank probe.

## Safety

The `PreToolUse` block is pattern matching over the command string, not a
sandbox. An obfuscated or indirectly invoked push can evade it. Treat it as
defense in depth that removes the accidental path; [`AGENTS.md`](../../AGENTS.md)
still carries the rule itself.

An agent that can edit these scripts can rewrite its own guardrails. Keep the
hook scripts outside the agent's auto-approved edit scope with
`chat.tools.edits.autoApprove` so a change requires manual approval.

## See also

- [Agent hooks in VS Code](https://code.visualstudio.com/docs/agent-customization/hooks)
- [Hooks reference](https://code.visualstudio.com/docs/agents/reference/hooks-reference)
- [`AGENTS.md`](../../AGENTS.md) — the house rules these hooks enforce
