---
status: current
last-verified: 2026-07-25
owner: software-engineer
source: current task evidence
---

# Active context

## Current focus

Extend the `windows-gui-screenshot-capture` Skill with the external-executable
workflow proven while documenting Notepad2.

## Implemented

- The Skill branches by source ownership: modifiable applications use an
  in-process capture mode; existing executables use an external driver.
- External capture uses deterministic fixtures, process-scoped discovery,
  event-driven window and child-control readiness, stable control interfaces,
  state restoration, and started-process cleanup.
- Verification rejects premature or black frames through dimensions,
  non-uniform pixels, scene-aware darkness, expected landmarks, and visual
  review instead of relying on `PrintWindow` success or file size.
- A one-level external-Win32 reference and real-failure regression evals keep
  the main Skill concise and preserve the existing rendering-engine workflow.

## Focused evidence

- Description is 985 characters; the Skill body is 257 lines.
- The 152-line external reference has a `## Contents` table and is linked
  directly from the Skill.
- Seven intended trigger prompts and eight real regression cases cover
  selection, message-pumped readiness, process ownership, capture failure,
  content validation, restoration, dark themes, and the RPA anti-trigger.
- Focused Pester passes 10/10; the helper and test have zero AST errors and
  zero PSScriptAnalyzer findings.
- A clean-process Notepad2 probe confirms Boolean `PostMessage`, process-scoped
  handle discovery, a 61 KB capture, and graceful started-process exit.
- Markdown diagnostics, relative links, Memory Bank health, and
  `git diff --check` pass.
- Three independent review rounds surfaced and resolved orchestration,
  message-pump, helper ownership, interop-signature, unchecked-result, and
  regression-test gaps. Final approval reports no Blocker, Major, or Minor
  findings.
- Setup deployment completed; all five changed Skill artifacts match the
  Canonical target by SHA-256 and the `~/.copilot/skills` Discovery link is a
  valid junction.

## Next step

Restart VS Code or reselect the Custom agent to reload the deployed Skill.
