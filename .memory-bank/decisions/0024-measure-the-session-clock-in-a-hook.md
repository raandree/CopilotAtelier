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
- A new `Stop` hook, `Write-SessionClose.ps1`, reads that clock at the end of
  every turn, advances the turn counter, and emits one `systemMessage` under the
  checklist: `POST-FLIGHT clock - turn 4 ended <UTC>; chat elapsed 22m (started
  <UTC>).`
- `postflight.instructions.md` gains a *Session clock* section stating that the
  line is hook-supplied, that the model must not write either number, and that
  an absent line means the hooks are not installed rather than a duration to
  estimate.

`Stop` was chosen over `PreToolUse` because it fires once per turn instead of
once per tool call, costs no tokens, and fires at the moment being reported.

## Consequences

- The clock line sits below the checklist rather than inside it. A number the
  model transcribes is a number it can transcribe wrongly; keeping the
  measurement out of its hands is worth the cosmetic split.
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
- The key derivation is duplicated verbatim in both hook scripts. VS Code
  launches each hook by its own path, so a shared helper would need the same
  path probing that `hooks.json` already carries; the two copies must change
  together.
- A missing, corrupt, or unwritable clock costs the duration line only. Every
  path still reports the end timestamp and still exits `0`.

## Confirmation

`tests/Hooks.Tests.ps1` runs 64 passing tests, up from 53. The new cases pin the
elapsed line, the turn counter, the `stop_hook_active` continuation, an absent
clock, a corrupt clock, an unreadable payload, the absent `decision` field, a
`session_id` of `../../pwned`, and four durations chosen where rounding and
truncation disagree. That last set exists because the formatter shipped with a
bug they caught: `[int]1.5` rounds in PowerShell, so a 90-minute chat reported
`2h 30m` until the cast became an explicit floor.

`Invoke-ScriptAnalyzer` over `com.github.copilot/hooks/scripts` is clean, and the
lifecycle suites — `SharedLifecycle`, `DevelopmentCycle`,
`LifecycleInstructions`, `CustomizationFrontmatter` — stay green against the
edited `postflight.instructions.md`.

The `Stop` event itself is verified only through the shipped command string and
the script contract; whether VS Code renders `systemMessage` under the reply as
expected is confirmed by the next session that runs with the hook deployed.
