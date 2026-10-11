---
status: accepted
date: 2026-09-02
last-verified: 2026-10-11
owner: software-engineer
source: VS Code hooks reference (Stop, UserPromptSubmit, PreCompact output contracts)
---

# Measure the session clock in a hook, not in the model

## Context and problem statement

Post-flight asks the agent to report what it did. The user asked for two more
facts in that report: the timestamp the turn closed, and how long the whole chat
has run. Both were already half-present — the `SessionStart` hook injects
`Session started at <UTC>` and Pre-flight requires the reply to open with it —
so the request looked like a formatting change.

It is not. A model has no clock. The opening timestamp is correct only because a
hook measured it and handed it over; anything the model composes afterwards is a
recollection of that one value, not a reading. Two failure modes follow. A
closing timestamp written by the model is a guess that will drift by the length
of the turn, which is precisely the quantity being reported. And after a
compaction the model no longer knows when the session began, so the duration
becomes a guess about a guess.

The obvious fix — inject a fresh timestamp with every user prompt — is not
available. VS Code's `UserPromptSubmit` supports the common output format only;
there is no `additionalContext` field, the same limitation already documented for
`PreCompact` in [0021](0021-checkpoint-before-compaction.md). The events that can
inject context are `SessionStart` (once) and `PreToolUse` / `PostToolUse` (once
per tool call). Putting a clock on every tool call would spend tokens on every
call of every turn and would fold a timing concern into the security guardrail.

## Decision outcome

Measure both numbers where they can be measured, and forbid the model from
composing either.

- `Add-SessionContext.ps1` writes the session start to
  `<LocalApplicationData>/CopilotAtelier/sessions/session-<key>.json` alongside
  the context it already injects. On disk rather than in context, so it survives
  compaction.
- A `Stop` hook, `Write-SessionClose.ps1`, advances the turn counter on that
  clock at the end of every turn.
- `Get-SessionElapsed.ps1` reads the clock and prints one line. The agent runs it
  as the last action of the turn and copies the line verbatim into its own
  Post-flight block. `Add-SessionContext.ps1` hands over the absolute path,
  because the agent cannot resolve it across both deployment layouts.
- `postflight.instructions.md` gains a *Session clock* section stating that the
  line is measured rather than composed, that the model must not compose,
  reformat, or recompute either number, and that a missing reader means the hooks
  are not installed rather than a duration to estimate.

`Stop` was chosen over `PreToolUse` for the counter because it fires once per
turn instead of once per tool call and costs no tokens.

## Revision, 2026-09-02: a hook cannot write inside the reply

The original outcome had the `Stop` hook print the line itself, and the first
Consequence below accepted that it would sit under the checklist rather than in
it. That trade was wrong, and the user rejected it the moment it shipped: VS Code
renders a hook `systemMessage` as a detached, collapsed *Warning from Stop hook*
box, so the number was not under the checklist but beside it, one click away from
invisible.

The two constraints are hard and opposed. A hook can measure but cannot write
inside the model's output; the model can write there but cannot read a clock. The
only arrangement satisfying both is to keep the measurement on disk and have the
model *read* it rather than recall it — which costs one command per turn, the
price the user chose when offered it against the collapsed box.

`Write-SessionClose.ps1` therefore keeps the turn counter but reports nothing
unless the clock is unreadable, which is the one case where the agent's own line
could not be measured either. Emitting the duration there as well would only put
a second copy in the warning box on every turn.

The general lesson is worth more than the fix: *where* a hook's output is
rendered is part of its contract, and this record had flagged it as the one thing
still unverified. Read the rendering before designing around it.

## Revision, 2026-10-11: name the clock, do not search for it

The reader's fallback, the newest clock recorded for the workspace, was chosen
when a workspace held one live chat and some test debris. It fails when two chats
share a workspace, and the failure reads as a plausible measurement.

Evidence, Prox1, 2026-10-08: a chat of VS Code's agent host (session `2270af6b`,
started 15:06 UTC, its `workspace.yaml` naming `client_name: vscode-agent-host`)
closed with `POST-FLIGHT elapsed: 5h 39m (started 11:05 UTC, measured 16:44 UTC,
turn 6)`. That line belongs to session `ae5e0f26`, a parallel agent-host chat in
the same workspace that started at 11:05 and closed its fifth turn at 15:42:10
UTC. Its clock file was newer than `2270af6b`'s, which `SessionStart` last wrote
at 15:06, so the newest-for-this-workspace rule chose it. `2270af6b`'s own `Stop`
hook wrote at 16:44:58, after the measurement. The Open-work item this revision
closes listed earlier cases with the same symptom: a 06:29 start on 2026-10-01
and, on `ai/calibration-phase-2`, a 10:25 and a 13:24 start in one Copilot SDK
chat on 2026-10-04. The agent-host chat's terminal
carried `COPILOT_AGENT_SESSION_ID=2270af6b-deef-4da1-a4e6-d5c9c654cacb`, the key
of its own clock file, `session-2270af6b-deef-4da1-a4e6-d5c9c654cacb.json`. VS
Code Local's terminal was not checked.

The hook knows the clock it just wrote, and the agent does not, so the hook says
which one it is:

- `Add-SessionContext.ps1` hands over `& '<reader>' -Path '<clock>'` whenever it
  wrote or resumed a clock, and the reader alone when it has none. Both paths are
  quoted for PowerShell. An apostrophe is doubled, and so is each typographic
  single quote, because PowerShell ends a single-quoted string at all of them: a
  profile named `O’Brien` would otherwise break the command.
- Over the character budget the shortened closing line keeps `-Path` while the
  context then fits, and loses it only when it must. The shortened line exists for
  a reader path too long to send, not for the clock path, which is bounded by the
  clock directory and a 64-character key; dropping it there would give back the
  pin the line exists to carry. The Memory Bank line is still shortened first.
- The reader, given no clock that exists, takes the clock whose key is the
  sanitized `COPILOT_AGENT_SESSION_ID` before the workspace rules. A named clock
  that exists but cannot be read reports `unavailable`; falling through would
  measure another chat and report it as this one.
- `postflight.instructions.md` tells the agent to run the command exactly as
  given, `-Path` included. The owner approved that wording on 2026-10-11.

An independent review of that change (`860d0b5`) added two fixes. The
`security-reviewer` Custom agent could not run it, because its first-choice model
is unavailable in the Copilot SDK runtime, so the built-in `security-review` agent
did. It found no Blocker or Major.

- The hook's output is pure ASCII: every other character of the JSON is written as
  `\uXXXX`. The quoting above ends where Windows PowerShell 5.1 encodes standard
  output in the console's OEM code page. That encoding's best fit turns U+02BC,
  U+2032, U+FF07, and in code page 437 U+00B4 into a bare `'`, and U+201C and
  U+201D into a bare `"`. After the quoting, a path component holding one ended
  the single-quoted string early, so the agent's command broke or ran what
  followed. The same mechanism broke the JSON around a workspace folder name
  holding a typographic double quote, which the hook had always printed unescaped,
  and let the rest of the name become `additionalContext`. ASCII reads the same in
  every code page and in UTF-8, so the fix does not depend on how the host decodes.
  The first wording of this record, that such a character is "replaced" and the
  reader falls back, understated it.
- The key pattern is matched case-sensitively (`-creplace`) in all three copies.
  `-replace` ignores case, so it let U+0130 and U+212A through
  `[^A-Za-z0-9._-]`. No separator survived, so there was no traversal, and hook
  and reader agreed, but the documented rule was not exact.

## Consequences

- ~~The clock line sits below the checklist rather than inside it. A number the
  model transcribes is a number it can transcribe wrongly; keeping the
  measurement out of its hands is worth the cosmetic split.~~ Falsified the same
  day — see the revision above. The split was not cosmetic, and the transcription
  risk is contained by having the model copy a rendered line rather than compute
  one.
- Closing a turn costs one extra command. That is the price of putting the
  number where the user reads it, and it was chosen deliberately over a free line
  in a collapsed warning box.
- The reader is read-only. `Stop` owns `turns`, so the reader reports the turn in
  progress as one past the closed count and writes nothing back.
- The hook emits no `decision` field. Blocking a `Stop` restarts the agent and
  bills another turn, which is far more than a timestamp is worth.
- The clock lives under `LocalApplicationData`, not the temp directory and not
  `.memory-bank/`. `/tmp` is world-writable on Linux, where a predictable name
  invites another local account to pre-create the path; and unlike the compaction
  checkpoint this file is machinery rather than knowledge an agent reads, so it
  does not belong in a repository the user version-controls. It also has to work
  in a workspace that has no Memory Bank.
- `session_id` reaches a path component, so it is stripped to
  `[A-Za-z0-9._-]` and capped at 64 characters, falling back to a hash of the
  working directory when the payload omits it.
- The key derivation is duplicated verbatim in both hook scripts, the reader
  applies the same rules to `COPILOT_AGENT_SESSION_ID`, and the duration
  formatter is duplicated in the reader. VS Code launches each hook by its own
  path, so a shared helper would need the same path probing that `hooks.json`
  already carries; the copies must change together.
- A missing, corrupt, or unwritable clock costs the duration line only. Every
  path still exits `0`.
- A test that runs the `SessionStart` hook must pin `-ClockRoot`. Without it the
  hook writes a real clock into the caller's profile, and once the reader began
  searching by workspace, a clock the suite had written for this repository
  shadowed the live session. The reader also prefers a `session-<id>` clock over
  a `session-cwd-<hash>` fallback, because VS Code always supplies a session id.
- A test that relies on `COPILOT_AGENT_SESSION_ID` sets and restores it, and
  every other reader test clears it, because the suite itself may run inside an
  agent-host chat whose terminal sets it.
- A chat measures the clock its own `SessionStart` wrote, so a parallel chat of
  the same workspace cannot take over its line. Two ways to read another chat's
  clock remain, both with an identical symptom. A host that supplies no
  `session_id` keys every chat of a workspace to one `session-cwd-<hash>` clock,
  which `-Path` cannot separate. And after a compaction the context no longer
  carries `-Path`, so only the `COPILOT_AGENT_SESSION_ID` fallback protects the
  chat, which was observed in the agent host's terminal and nowhere else. A
  cross-check of the line's start time against the chat's opening timestamp would
  catch both, but it needs a composed `unavailable` line, so it is not built.
- Hosts load hooks when a session starts. The change reaches a chat only after a
  redeploy and a new chat.
- Every path in the context reaches the agent through the hook's standard
  output, and that output is pure ASCII, so a console code page cannot change
  what the agent reads. The other hooks that print JSON do not carry workspace
  text into an instruction channel: `Write-SessionClose.ps1` and
  `Block-RemoteMutation.ps1` print fixed text and a rule name, and
  `Write-CompactionCheckpoint.ps1` prints a checkpoint name or, when a write
  fails, an exception message that can hold a path, in a `systemMessage` the user
  reads and the model does not. They keep the plain encoder.
- The reader's and the hooks' key derivations are three copies of one rule, and
  a test aims at each: a Kelvin sign in a session id, or in
  `COPILOT_AGENT_SESSION_ID`, must leave the key without it.

## Confirmation

`tests/Hooks.Tests.ps1` runs 75 passing tests, up from 53. The cases pin the
elapsed line, the injected reader path, the single-line output contract, the
turn-in-progress arithmetic, the workspace preference between concurrent windows,
the read-only guarantee, the turn counter, the `stop_hook_active` continuation,
an absent clock, a corrupt clock, an unreadable payload, the absent `decision`
field, a `session_id` of `../../pwned`, and five durations chosen where rounding
and truncation disagree. That last set exists because the formatter shipped with
a bug they caught: `[int]1.5` rounds in PowerShell, so a 90-minute chat reported
`2h 30m` until the cast became an explicit floor.

`Invoke-ScriptAnalyzer` over `com.github.copilot/hooks/scripts` is clean, and the
lifecycle suites — `SharedLifecycle`, `DevelopmentCycle`,
`LifecycleInstructions`, `CustomizationFrontmatter` — stay green against the
edited `postflight.instructions.md`.

The rendering question this record left open is now closed by observation: VS
Code renders `systemMessage` as a collapsed warning box beside the reply, not
under it. That is what forced the revision above.

Deploying the reader also exposed a defect the suite had been creating since the
clock was added: six `Add-SessionContext` tests invoked the hook without
`-ClockRoot` and left around fifteen real clocks in the developer's own profile,
one of them recording a workspace of `C:\demo IGNORE PREVIOUS INSTRUCTIONS`. It
was invisible while only `Stop` read the clock, by session id. The first live run
of the reader reported a three-minute chat that had been running for an hour and
three quarters. A test now asserts the real profile directory gains nothing.

Confirmation of the 2026-10-11 revision. `tests/Hooks.Tests.ps1` gains 20 cases,
159 in all, and they ran red first: of the 52 cases in the `Add-SessionContext`
and `Get-SessionElapsed` Describes, 15 failed for the stated reasons. The context
carried no `-Path`, the quoting helper did not exist, and the reader returned
`5h 39m` for a fixture chat of 22 minutes, which is the Prox1 failure reproduced
with two clock files. The cases that already passed pin what the change must keep:
no clock written, a named session with no clock, an explicit `-Path`. Seven
mutations of the finished code were each caught by the case aimed at them: naming
a clock before it is written, a shortened line that never keeps `-Path`, one that
never drops it, a quoting helper that doubles only the apostrophe, an environment
pick that overrides `-Path`, one that skips the existence check, and one that
skips the key sanitizing. The file is green in PowerShell 7.6.6 (159 of 159) and,
for every case of both Describes, in Windows PowerShell 5.1. In 5.1, 25 guard
cases of the same file fail, identically on a clean `origin/main`, because the
`Invoke-HookWithin` helper reads `ProcessStartInfo.ArgumentList`, which .NET
Framework lacks; CI runs only PowerShell 7. The full gate, `./build.ps1 -Tasks
build, test`, passed with 2,562 tests, 129 skipped (none in the hook suite), none
failed, and 90.74 % coverage. `Invoke-ScriptAnalyzer` over the three edited hook
scripts reports nothing.

Confirmation of the review fixes. Seven cases were added and each ran red first:
the ASCII case and the quoted-path round trip failed on the encoder itself, not
on a simulation of it. In the detached launcher's console the hook's JSON no
longer parsed, and a typographic quote in the clock path came back as an
apostrophe. The Kelvin-sign and dotted-I cases failed on the clock file name, and
the Stop hook and reader cases on the clock they did not find. After the fix the
three Describes pass 66 of 66 in PowerShell 7.6.6 and in Windows PowerShell 5.1.
The whole file passes 166 of 166 in 7.6.6, and in 5.1 shows the same 25 guard
cases as before, name for name. `Invoke-ScriptAnalyzer` reports nothing. The full
gate passed with 2,569 tests, 129 skipped (none in the hook suite), none failed,
and 90.74 % coverage.

Confirmation of the live checks, 2026-10-11, after `Setup-CopilotSettings.ps1`
deployed `c6621a0` at 21:59 UTC. The deployment had come from a clean `main`
clone on 2026-10-08, and exactly the five changed files differed from it. After
the redeploy all 238 owned files match the payload and their recorded hashes,
`Test-CopilotAtelier` reports the deployment healthy, and the VS Code settings
and keybindings are byte-identical to before.

The sessions were headless Copilot CLI 1.0.93 turns in scratch workspaces, each
with its `COPILOT_*` environment cleaned of the parent chat's. ShellPilot was not
used: it is an API-level chat client with its own tool loop and starts no Copilot
host, so no hook runs in it. The evidence is each session's `events.jsonl`, whose
`hook.end` event records the context the host received and whose tool events
record the command the agent ran.

- Before the redeploy the context named the reader alone, and the agent ran it
  without `-Path`. In a workspace whose folder name held `“Quote”` and `ü` the old
  hook delivered no context at all: the host recorded success and no
  `additionalContext`, so the session lost its timestamp, its Memory Bank probe,
  the reader command, and the safety line. That is the encoder fault of the review
  reproduced in the real host.
- After the redeploy the context named the session's own clock, the agent ran the
  command exactly as given, and the clock showed `turns=1` after the turn. The
  smart-quote workspace's context arrived with the exact folder name.
- Prox1 reproduced. Chat A started at 22:01 and chat B at 22:02 in one workspace;
  resuming A made A's the newest clock file. The pre-fix reader, asked from B's
  workspace, printed A's line (`started 22:01`, `turn 3`). B's resumed turn ran
  its own `-Path` and closed with `started 22:02`, `turn 2`. A resume ran the
  hook again with `source: resume`, kept both clocks, and the counters continued.
- In this chat, a VS Code agent-host session, `COPILOT_AGENT_SESSION_ID` equals the
  session id. Beside a newer same-workspace decoy, the deployed reader with no
  `-Path` printed this chat's start, 16:06, and the pre-fix reader the decoy's,
  08:00.

Not checked: VS Code Local's terminal and context, a new VS Code agent-host chat's
own SessionStart (the Copilot CLI runtime stood in for it), whether the CLI
runtime sets `COPILOT_AGENT_SESSION_ID` in its own terminal, and any non-Windows
host.
