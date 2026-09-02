---
status: accepted
date: 2026-09-02
last-verified: 2026-09-02
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
- The key derivation is duplicated verbatim in both hook scripts, and the
  duration formatter in the reader. VS Code launches each hook by its own path,
  so a shared helper would need the same path probing that `hooks.json` already
  carries; the copies must change together.
- A missing, corrupt, or unwritable clock costs the duration line only. Every
  path still reports the end timestamp and still exits `0`.

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
