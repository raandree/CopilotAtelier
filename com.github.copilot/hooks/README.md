# Hooks

Deterministic guardrails that run at fixed points in the agent loop. Unlike an
Instruction, a hook does not depend on the model choosing to obey it: VS Code
executes the command and honours its exit code.

Setup deploys this folder to the Canonical target and links it to
`~/.copilot/hooks`. Hook discovery and event behavior are client-specific;
verify loading in the client being used rather than assuming cross-client parity.

## Launchers

Every entry in `hooks.json` carries three launchers. VS Code runs `windows` on
Windows and `command` elsewhere; it reads `powershell` only when `windows` is
missing. The Copilot SDK host has no `windows` key: its own format knows
`bash`, `powershell`, `exec`, and a cross-platform `command`, and explicit
`bash` or `powershell` entries take precedence on their platforms
([hooks configuration reference](https://docs.github.com/en/copilot/reference/hooks-configuration)).
It therefore runs `powershell` on Windows and `command` elsewhere, and the cloud
agent, which honours only `bash`, falls back to `command`. All three launchers
start their script the same way apart from the interpreter — `pwsh`, or
`powershell` for `windows` — and none may depend on `HOME`, which Windows does
not define. `windows` and `powershell` also end with one statement of their
own, explained below.

Each launcher runs the first of these scripts that exists:

1. `<PLUGIN_ROOT>/com.github.copilot/hooks/scripts/<Script>.ps1`
2. `<USERPROFILE>/.copilot/hooks/scripts/<Script>.ps1`
3. `<HOME>/.copilot/hooks/scripts/<Script>.ps1`
4. `.copilot/hooks/scripts/<Script>.ps1` under the profile folder the operating
   system reports, for a host that passes a stripped environment

`USERPROFILE` comes before `HOME`. Windows always defines `USERPROFILE`, while
`HOME` there is whatever a tool such as Git for Windows set, and a `HOME` that
points at a writable tree would otherwise run a planted script instead of the
deployed one. A `HOME` that does not answer, such as an unreachable UNC path, is
then never probed while `USERPROFILE` holds the script. Probing one took longer
than the 20-second hook timeout, and the Copilot SDK host allows a call whose
hook times out. On Linux and macOS `USERPROFILE` is unset, so `HOME` applies.

An unset root becomes an unresolvable `*` and a relative root is anchored at the
filesystem root, so no candidate ever resolves against the working directory.
When no candidate exists or the script cannot start, the launcher names the
script and the underlying error on standard error and exits `2` for
`PreToolUse`, which blocks, and `1` for the lifecycle events, which warns.
`command` and `powershell` need `pwsh` on `PATH`.

The launcher passes the script's exit code through unchanged, but on Windows
both hosts run it inside an outer PowerShell, which reports any failed native
command as `1`:

| Host | Spawn on Windows | Source |
|---|---|---|
| VS Code Local harness | `powershell.exe -ExecutionPolicy Bypass -NoProfile -NoLogo -Command <windows>` | `HookExecutor` in VS Code's built-in `extensions/copilot/dist/extension.js` |
| Copilot SDK host | `pwsh.exe -nop -nol -c <launcher>`, started by `copilot-runtime.exe` | process captures of `command` (2026-10-02) and `powershell` (2026-10-04) |

VS Code blocks only on `2` and treats every other non-zero exit as a warning,
and the SDK host shows the block reason only on `2`, so `windows` and
`powershell` end with
`; exit (@(Get-Variable -Name LASTEXITCODE -ValueOnly -ErrorAction Ignore) + 2)[0]`
(`+ 1` for the lifecycle events). The outer PowerShell runs it and exits with the
inner code, or with the launcher's own failure code when the inner interpreter
never started. Under `cmd.exe` the statement only reaches the inner `-Command`
after a `try` block that always exits, so when the inner interpreter cannot
start at all, a `cmd.exe` spawn reports `1`, while both PowerShell spawns report
the launcher's failure code. `command` cannot carry it, because `sh`
runs `command` on Linux and macOS and rejects the statement; that is why the SDK
host gets its own `powershell` launcher. It runs that launcher the same way,
passing the text on unexpanded.

## Contents

| File | Event | Purpose |
|---|---|---|
| [`hooks.json`](hooks.json) | — | Hook configuration loaded by VS Code and the Copilot SDK host |
| [`scripts/Block-RemoteMutation.ps1`](scripts/Block-RemoteMutation.ps1) | `PreToolUse` | Blocks remote-mutating and irreversible commands |
| [`scripts/Add-SessionContext.ps1`](scripts/Add-SessionContext.ps1) | `SessionStart` | Probes for the Memory Bank, injects the UTC timestamp, starts the session clock and names it in the reader command |
| [`scripts/Write-SessionClose.ps1`](scripts/Write-SessionClose.ps1) | `Stop` | Advances the session clock's turn counter |
| [`scripts/Get-SessionElapsed.ps1`](scripts/Get-SessionElapsed.ps1) | — | Agent-run reader that prints the Post-flight elapsed line of the clock it is given |
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
the model; on exit `2` VS Code does not read standard output. The Copilot SDK
host does not read standard error then: it merges one JSON object from standard
output into the deny, so the guard also prints the reason there, as top-level
`permissionDecision` and `permissionDecisionReason` only. The object must not
carry `hookSpecificOutput`. For a PascalCase event such as `PreToolUse`, the
SDK runtime in VS Code 1.140.0 (1.0.15-preview.4) drops an object that does,
and the model reads only `Denied by preToolUse hook: hook exited with code 2`,
as it did until 2026-10-04; it also shows only that for an object with nothing
but `hookSpecificOutput`, for plain text, and for standard error alone.
[`tests/HookSdkRuntime.Tests.ps1`](../../tests/HookSdkRuntime.Tests.ps1) runs
the guard inside that runtime and checks what the model reads. The
command-bearing fields are walked up to 64 levels deep and 20,000 fields and
nested objects, in a payload of up to 1 MB; plain values in arrays, such as a
file list, do not count. Their values are joined in document order and, within
each object, executables before arguments. So
`{"args":["push"],"command":"git"}`, the order a serializer that sorts its keys
writes, still reads as `git push`, while one entry's executable never pairs
with another entry's arguments. When the walk cannot cover a payload,
because it is nested deeper, larger, holds more fields or objects, or is not
valid JSON,
its raw text is also scanned: as written, with JSON escapes decoded, and
without the JSON punctuation, so an argument array such as `["git","push"]`
reads as the command it is. The command-bearing fields are also pulled out of
it and joined the way the walk joins them, so a command split across fields,
such as `{"command":"git","args":["push"]}`, reads as one line too. There they
are also joined across the whole payload, executables first and in reverse,
because a brace in raw text cannot show reliably where an object ends; like the
rest of this path, that errs toward blocking and can pair one entry's
executable with another entry's arguments. A blocked
command found there blocks the call. That path errs toward blocking: a payload
that only mentions a blocked command, such as a document in an unreadable
payload, is blocked too. A text with neither `git` nor `gh` in it is skipped,
because every pattern needs one of them.
Otherwise a payload that is not valid JSON is
allowed with a warning on standard error and exit `0`: the Copilot SDK host
denies a `preToolUse` call on every other non-zero exit, so a payload schema
change would otherwise block every tool call. The whole decision has a time
limit of five seconds, a quarter of the hook timeout, and the walk may use half
of it. Parsing and walking cannot be interrupted, and some patterns slow down
quadratically on one long line of `git` words, so a payload the guard has not
inspected within the limit is blocked rather than left to the timeout, which
would let it through. A payload over 4 MB is blocked without being scanned; no
model writes a tool call that large. A payload over 1 MB that names git on most
lines, such as a large document about git, can still run out of time and be
blocked: JSON escaping puts its whole text on one raw line, where some patterns
slow down quadratically. Under PowerShell 7, which the Copilot SDK host runs
on Windows, a batch of more than about 16,000 command entries, such as
`{"command":"ls","args":["x"]}`, also runs out of time: 32,000 of them
(0.9 MB) are blocked after 5.4 seconds, while Windows PowerShell, which VS Code
runs, allows 64,000 in 2.5 seconds. So the same oversized tool call can pass in
one host and be blocked in the other. Write such a file in parts, or run the
command yourself.

### Authorizing a remote mutation

The house rules allow a push when the user asks for it in the current turn, but
an agent cannot lift the block itself. Each host starts the hook with its own
environment: VS Code passes its extension host's environment plus the entry's
`env`, and the Copilot SDK host its runtime's. A variable set in an agent
terminal never reaches the hook. On 2026-10-02, in a Copilot SDK chat,
`COPILOT_ATELIER_ALLOW_REMOTE` set in one tool call was already gone in the next,
because every call ran in a new process, and the probe was still denied. Setting
the variable inside the blocked command cannot work either, because the hook
judges the command before it runs.

So the user runs an authorized push in their own terminal. The agent hands over
the exact command and does not retry it. A value persisted in the user
environment, for example with `setx`, is different: every host started
afterwards inherits it and runs with the guard off, so never persist it.

`COPILOT_ATELIER_ALLOW_REMOTE=1` still allows a blocked command when it is set
in the hook's own environment, for example in the environment VS Code itself
was started with. That turns the guard off for every chat of that instance, so
do not use it to authorize a single command. The hook records every override on
standard error.

## Add-SessionContext

Resolves the session working directory from the hook payload, probes for
`.memory-bank/index.md`, and returns an authoritative statement of whether a
Memory Bank exists, plus the current UTC timestamp. This removes the recurring
failure where an agent concludes "no Memory Bank" from the workspace summary,
which omits dotfile folders.

It also starts the session clock described below, and hands the agent the
command that reads it: `& '<reader>' -Path '<clock>'`, the absolute paths of
`Get-SessionElapsed.ps1` and of the clock this hook wrote or resumed. The agent
cannot resolve the reader itself — the script sits under `~/.copilot` when
deployed and under the plugin root when installed as a plugin, which is the probe
`hooks.json` already carries. The `-Path` is what keeps the measurement on this
chat's own clock: without it the reader has to choose one, and a parallel chat in
the same workspace can make it choose that chat's (Prox1, 2026-10-08: a chat
closed with the duration of its parallel chat). A hook that wrote or resumed no
clock hands over the reader alone. Both paths are quoted for PowerShell, and an
apostrophe or a typographic single quote in either is doubled, because
PowerShell ends a single-quoted string at all of them.

A resumed session keeps its clock. The Copilot SDK runtime reruns the hook with
`source: resume` when it reloads a chat; when a readable clock of that session
exists, the hook leaves it untouched, injects its original start time, and names
it in the command. Restarting it there reset the elapsed line and the turn count.

The context goes into one JSON object twice, under the key each host reads: a
top-level `additionalContext` for the Copilot SDK host and Copilot CLI, and
`hookSpecificOutput.additionalContext` for the VS Code Local harness. Each host
ignores the other's key, so dropping either one silently removes the context
from that host's sessions.

The JSON is pure ASCII: the hook writes every other character as `\uXXXX`.
Windows PowerShell 5.1 encodes standard output in the console's OEM code page,
and that encoding's best fit turns characters such as U+201C, U+02BC, and U+2032
into a bare ASCII quote. In the workspace path that would break the JSON and let
the rest of a folder name become context; in a quoted path it would end the
string early, after the quoting had done its work. ASCII reads the same in every
code page and in UTF-8, so the context does not depend on how the host decodes
it.

### Session context budget

Injected context defaults to a 4096-character limit. Set
`COPILOT_ATELIER_SESSION_CONTEXT_MAX_CHARS` to an integer from 1024 through
16384 to change it; invalid values use the default. Oversized paths are omitted
before any lifecycle guidance, and the clock still runs. This is a character
budget for one hook, not a token count or a live context-window estimate.

Over the limit, the hook first shortens the Memory Bank line, which carries the
workspace path. If that is not enough it shortens the closing line, which drops
the reader path because that is the path that outgrew the budget, and keeps
`-Path` while the context then fits. Only when it still does not fit does the
closing line lose `-Path` too, and the agent falls back to the reader's own
choice of clock.

There is no master-off profile: all four shipped hooks serve lifecycle or
safety obligations. The context budget never disables remote-mutation checks.
Do not persist `COPILOT_ATELIER_ALLOW_REMOTE` in hook configuration or in the
environment VS Code starts with; an authorized push runs in the user's own
terminal.

## The session clock

Post-flight closes every reply with the elapsed duration of the chat. A model has
no clock: a duration it composes is a guess, and after a compaction it no longer
knows when the session began. So the number is measured on disk and read back.

Three pieces share one clock file:

| Field | Written by | Meaning |
|---|---|---|
| `startedUtc` | `SessionStart` | Round-trip timestamp the duration is measured from |
| `workspace` | `SessionStart` | Working directory the session was opened in |
| `turns` | `Stop` | Turns closed so far in this session |
| `lastTurnEndedUtc` | `Stop` | End of the most recent turn |

It lives at `<LocalApplicationData>/CopilotAtelier/sessions/session-<key>.json` —
`%LOCALAPPDATA%` on Windows, `~/.local/share` on Linux, `~/Library/Application
Support` on macOS. Not the temp directory: `/tmp` is world-writable, and a
predictable name there invites another local account to pre-create the path. The
`<key>` is the payload's `session_id` with every character outside
`[A-Za-z0-9._-]` stripped, so none can traverse a directory. The match is
case-sensitive: a case-insensitive one lets U+0130 and U+212A through. When the
payload names no session, the key is a hash of the working directory instead, so
two concurrent windows do not share one clock. Where the host supplies no
session id, two chats of one workspace still share that one clock, and no
`-Path` can tell them apart.

### Write-SessionClose

The `Stop` hook advances `turns` and records `lastTurnEndedUtc`. It reports
nothing on the happy path. It used to append the duration itself, but VS Code
renders a hook `systemMessage` as a detached, collapsed warning box rather than
part of the reply, so the line the user actually wanted in the checklist was
never in it. Moving the measurement to the agent put it there; leaving the hook
line in as well would only have added a second copy on every turn.

It still speaks up when the clock cannot be read, because that is the one case
where the agent's own line could not be measured either:

```text
POST-FLIGHT clock - no readable session clock, so the elapsed line reads unavailable.
```

The hook emits no `decision` field. Blocking a `Stop` restarts the agent and
bills another turn, which is far too much to pay for a timestamp. Every failure
path still exits `0`.

A `Stop` that fires while `stop_hook_active` is `true` closes a turn some other
blocking hook already resumed, so it does not advance the turn counter.

### Get-SessionElapsed

Not a hook — the agent runs it as the last action of a turn, which is why it
reports plain text rather than the hook JSON contract. It prints one line, meant
to be copied verbatim as the last line of the reply:

```text
POST-FLIGHT elapsed: 16m (started 09:15 UTC, measured 09:31 UTC, turn 3)
```

Read-only: `Stop` owns `turns`, so the reader reports the turn in progress as one
past the closed count and writes nothing back. The command in the session context
hands it the clock to read with `-Path`. Given no `-Path`, or one that names no
file, it chooses a clock in this order, which is what survives a compaction that
dropped the injected command:

1. The clock whose key is `COPILOT_AGENT_SESSION_ID`, when the host sets it and
   that clock exists. The agent host's terminal carries its chat's id in it, and
   that id is the key of the chat's own clock. The value is stripped to the same
   `[A-Za-z0-9._-]` characters and 64-character cap as a payload's `session_id`,
   so it cannot name a file outside the clock directory. This clock comes before
   a newer one of the same workspace, which a parallel chat may have written.
2. The newest clock recorded for the current workspace, a `session-<id>` clock
   before a `session-cwd-<hash>` one.
3. The newest clock overall.

A named clock that exists but cannot be read reports `unavailable` instead of
falling through to another chat's clock, which would read as this chat's. An
unreadable clock yields `POST-FLIGHT elapsed: unavailable (no session clock on
disk).` and exit `0`.

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

### Reading hook evidence

These are Windows observations from 2026-10-08, not a cross-version guarantee.
Use the host's logs, not a model's account of its own context: a compaction
summary can preserve injected text by chance, and a request for exactly one
tool call produced three in Copilot CLI 1.0.92.

#### VS Code Local: VS Code 1.141.0, bundled Copilot Chat 0.69.0

- The Hooks output channel is persisted at
  `%APPDATA%\Code\logs\<yyyyMMddTHHmmss>\window<N>\exthost\GitHub.copilot-chat\GitHub Copilot Chat Hooks.log`.
  Lines have `<time> [info] [#<n>] [<Event>] <verb> ...`; group by `[#<n>]`.
  `Input` carries `session_id`, `cwd`, and `tool_name`; `Output` is the exact
  returned JSON. `Completed (Success) in <n>ms, no output` means nothing was
  returned, not that context was injected.
- The neighboring `GitHub Copilot Chat.log` records compaction through
  `[ConversationHistorySummarizer]` and a `summarizeConversationHistory-full`
  request.
- Each hook input's `transcript_path` identifies
  `%APPDATA%\Code\User\workspaceStorage\<hash>\GitHub.copilot-chat\transcripts\<session_id>.jsonl`.
  It contains user/assistant messages and tool calls, but not tool results.
- In Copilot Chat 0.68.0 and 0.69.0, neither `/compact` nor background
  compaction ran PreCompact in VS Code Local; the checkpoint hook therefore
  wrote nothing there. Do not infer a checkpoint from a compaction entry.

#### Copilot SDK agent host and Copilot CLI 1.0.92

Observed with VS Code 1.141.0 and Copilot CLI 1.0.92 on 2026-10-08:

- `~\.copilot\session-state\<session id>\events.jsonl` records `hook.start`
  and `hook.end` with `hookType` and `output`; that output is exactly what the
  host injected. `session.compaction_start` carries its `trigger`.
- The neighboring `workspace.yaml` names `client_name`: `vscode-agent-host`
  or `github/cli`. Use it to distinguish otherwise similar event streams.
- Copilot CLI starts `sessionStart` at the first prompt, not process launch;
  those were 33 seconds apart in one observed session.
- `/compact` ran neither Stop nor `agentStop` in either host, so the session
  clock's `turns` does not count it. Copilot CLI ran PreCompact with
  `trigger: manual`; VS Code Local did not, as scoped above.

#### Inspecting host versions and hook-written files

In the VS Code 1.141.0 observation, Copilot Chat ships inside VS Code at
`<VS Code install folder>\<commit>\resources\app\extensions\copilot`.
Its `package.json` names the version; `dist\extension.js` is the source to
check when release documentation is silent, for example by searching for
`executePreCompactHook`.

Read a hook-written file, such as a session clock, with `FileShare.ReadWrite`
and `FileShare.Delete`, using a read-only handle so inspection cannot block
the hook's atomic replace. Never write the file to inspect or repair evidence.

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
- **Command not found.** A hook command tries the four literal locations listed
  under [Launchers](#launchers) and never scans an agent-plugin wildcard. When
  none exists it writes `CopilotAtelier hook <Script>.ps1 failed: could not
  resolve the script …`; when the script itself fails, the same prefix carries
  the underlying error instead. A missing `PreToolUse` guard exits `2` and
  blocks; missing lifecycle scripts exit `1` so they warn without trapping the
  agent loop. If you deploy the scripts elsewhere, replace the resolver in
  `hooks.json` with one absolute path.
- **Every tool call is denied with `(hook errored)` in a Copilot SDK session.**
  The SDK host runs `command`, so that branch has to resolve on Windows without
  `HOME` and needs `pwsh` on `PATH`. Launchers from releases before this fix
  looked only at `PLUGIN_ROOT` and `HOME` there and failed closed on every call.
  Redeploy, then start a new session.
- **A Copilot SDK session never receives the SessionStart context.** The
  session's `events.jsonl` shows the `sessionStart` hook ending with
  `success: true`, yet no `Session started at` text reaches the model. The SDK
  host reads only a top-level `additionalContext` and ignores
  `hookSpecificOutput`, the only key the VS Code Local harness reads. Releases
  before this fix wrote only the nested key. Redeploy, then start a new session.
  That `hook.end` event's `output.additionalContext` shows exactly what the host
  injected, and the field is absent when nothing was.
- **A `PreToolUse` block reaches the host as exit `1`.** On Windows both hosts
  run the launcher inside an outer PowerShell `-Command` (see Launchers). That
  outer PowerShell reports only whether its last command succeeded, so exit `2`
  arrives as `1`.
  - The Copilot SDK host fails closed on every non-zero `preToolUse` exit. The
    call is still denied, but as `Denied by preToolUse hook (hook errored)`
    without the reason. Since 2026-10-02 the SDK host runs the `powershell`
    launcher, which hands the code on, and since 2026-10-04 the deny carries
    the reason: `Denied by preToolUse hook: Blocked by Copilot Atelier: …`. A
    deny that reads `Denied by preToolUse hook: hook exited with code 2` comes
    from an older guard, whose JSON on standard output also carried
    `hookSpecificOutput` (see [Block-RemoteMutation](#block-remotemutation));
    redeploy. The launcher reads the guard on every call, so even an open
    session shows the reason from its next call. A session started before the
    2026-10-02 deploy keeps the old hooks and still shows `hook errored`.
  - VS Code blocks only on `2`, so in Local chats on Windows the guard only
    warned until 2026-10-02. The `windows` launcher now ends with an `exit` that
    hands the inner code on.
  - A bare trailing `exit` would not work: it exits `0` and would allow the call.
  - `command` cannot carry the statement, because `sh` runs it too.
- **The hook dies with a PowerShell parser error.** VS Code hands the command to
  a PowerShell shell, which expands the double-quoted `-Command` argument before
  the child process parses it. A `$` token is therefore consumed by the outer
  shell and reaches the child as an empty string — `$b = if ($env:PLUGIN_ROOT)`
  arrives as `= if ()` and fails with `An expression was expected after '('`.
  Every shipped command is written without a single `$`: paths come from
  `[Environment]::GetEnvironmentVariable(...)`, the blocking exit code from
  `Get-Variable -Name LASTEXITCODE -ValueOnly`, and the reported error from
  `Get-Variable -Name _ -ValueOnly`. `cmd.exe` and `sh` parse the same text, so
  it also carries no backtick, inner double quote, or `%`. Keep it that way, or
  the hook silently stops guarding anything.
- **Timeout.** These hooks declare 20 seconds. The configuration gate accepts
  explicit limits from 1 through 30 seconds. The Copilot SDK host reads
  `timeout` as an alias of its own `timeoutSec` and, unlike every other failure,
  lets a timed-out `preToolUse` hook through. Investigate slow filesystem access
  before changing the limit; do not replace a bounded hook with an unlimited one.
  The `PreToolUse` guard limits its own decision to about five seconds and
  blocks what it cannot inspect in that time, so a slow payload cannot ride the
  timeout.
- **A redeployed hook does not take effect.** The Copilot SDK host reads hook
  configuration when a session starts; a chat that was already open, and the
  subagents it starts, keep what they loaded. Start a new chat.
- **Deployment drift.** Run `(Test-CopilotAtelier).Checks` to inspect missing
  scripts, changed files, and Discovery targets. This is read-only and never
  executes a hook as a health check.

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
