---
status: accepted
date: 2026-08-25
last-verified: 2026-08-25
owner: software-engineer
source: VS Code hooks reference; Anthropic memory tool docs; Cline Memory Bank docs
---

# Checkpoint the session before compaction

## Context and problem statement

The Memory Bank has a deterministic entry gate and no exit gate. `SessionStart`
probes for the index, but the only durable write point is Post-flight, which
runs "before ending the reply". A turn that is compacted mid-run never reaches
it, so everything the run learned but had not yet written to a file is discarded
with the conversation. Worse, the summary that replaces the transcript still
reports that Pre-flight ran, so the agent believes it holds `activeContext.md`
when it no longer does, and nothing re-applies the routes.

Every comparable system treats context loss as the primary threat. Anthropic
injects "ASSUME INTERRUPTION: Your context window might be reset at any moment"
into the memory tool's system prompt. Cline instructs the user to update the
memory bank *before* the window fills. Claude Code re-reads the project
`CLAUDE.md` from disk after `/compact`. Copilot Atelier covered the risk in one
Prompt's bespoke "Compaction resilience" section, one manually invoked
`/session-handoff`, and the `subagent-dispatch` ledger — all model judgement,
none general, and the handoff has to be requested before saturation, which is
exactly what a mid-turn agent will not do.

VS Code exposes a `PreCompact` event. `Instructions/copilot-authoring.instructions.md`
had listed it as available since the Hooks Customization shipped, and nothing
used it.

## Decision outcome

Split the recovery across the two mechanisms by what each can guarantee.

- `PreCompact` runs `Write-CompactionCheckpoint.ps1`, which writes
  `.memory-bank/session/compaction-<UTC>Z.md` with the trigger, transcript path,
  branch, commit, and changed paths at the moment of truncation, plus a resume
  protocol. It is session ephemera, gitignored beside the existing handoff
  patterns.
- Pre-flight gains a *Compaction recovery* section: distrust the summary, read
  the newest checkpoint, re-read the index and re-apply routes, re-read the
  driving Prompt, Instruction, Skill, and Custom agent from disk, and verify the
  working tree.

The hook owns what must hold regardless of model reasoning; the Instruction
owns the judgement, and is re-sent with every request, so it survives the
truncation that the conversation does not.

## Consequences

- The hook cannot make the model flush its working knowledge before truncation.
  `PreCompact` supports the common output format only — there is no
  `additionalContext` field — so nothing a hook emits reaches the
  post-compaction context. It records what it can observe from the payload and
  from git, which is a recovery anchor, not a handoff.
- Recovery therefore still depends on the model acting on a re-injected
  Instruction. The improvement is that the state now exists on disk either way.
- The checkpoint holds untrusted payload values and is read back by an agent, so
  every field is flattened to a single span with control characters and
  backticks neutralized, and the file states that its tables are data.
- A hook fault must never block compaction, so every path exits `0`, including
  an unwritable session directory.
- The hook writes nothing when the workspace has no Memory Bank or the payload
  names no workspace. Creating a Memory Bank stays reserved for a durable
  repository write under the `memory-bank` Skill, and guessing the workspace
  from the spawn directory would write into an unrelated repository.
- Checkpoints accumulate. The resume protocol closes with a delete step, and
  nothing prunes them automatically.
- `git status --porcelain` lines are trimmed by the sanitizer, so the two-column
  index/worktree status code is not preserved. The recorded paths are the point;
  step 4 sends the reader to `git status` for the split.

## Confirmation

`tests/Hooks.Tests.ps1` covers the new script the same way as the other two,
through a child process fed on standard input: a checkpoint appears under a
staged Memory Bank with the expected filename shape, the trigger and resume
protocol are recorded, the common output contract parses as JSON, a workspace
without a Memory Bank gains no directory, a payload smuggling a newline and a
forged list item cannot forge one in the file, and an unreadable payload still
exits `0`. The configuration contract requires the `PreCompact` event alongside
the existing two.
