# Active context

## Current work focus

Authored a new on-demand skill, `windows-gui-screenshot-capture`, packaging the
reusable capability proven in the `D:\guitest` GUI-screenshot-docs
proof-of-concept: capture screenshots of a Windows desktop GUI programmatically
(the right capture API per rendering engine) and assemble them into a
screenshot-embedded Markdown user manual, generalised to real apps.

## What changed this session

- New skill folder `Skills/windows-gui-screenshot-capture/`:
  - `SKILL.md` — six-step frame; capture-API-per-engine matrix; the
    GPU-composited-returns-black rule; the self-capturing `-CaptureDir` /
    `--capture` scene mode; native MessageBox (`#32770`) capture; a gotchas
    table (STA, WinForms DPI-unaware + `Form.Size` bitmap, WPF `SizeToContent`,
    Avalonia headless font); anti-rationalization + red-flags + verification.
  - `references/engine-recipes.md` — six per-engine snippets (WPF / WinForms /
    Win32 / WebView2 / Avalonia / WinUI 3), `## Contents` TOC, each pointing to
    the POC file for the full implementation.
  - `scripts/DialogCapture.ps1` — the POC's native-dialog helper copied
    verbatim (origin noted), ready to dot-source.
  - `notes-evals.md` — 6 intended-trigger + 3 decoy eval prompts.
- Registered in the README Available Skills table and the `techContext.md`
  Skills inventory; skill count 38 → 39; CHANGELOG `[Unreleased]` Added entry.

## Verification

- Description 955/1024 chars; SKILL.md 209 lines (≤ 500); `engine-recipes.md`
  112 lines with a `## Contents` TOC; references one level deep; folder name ==
  `name:`.
- `DialogCapture.ps1` AST parse: 0 errors. `markdownlint-cli2`: 0 issues across
  the 3 Markdown files. Cross-skill overlap audit: no competing screenshot / GUI
  skill; `DO NOT USE FOR:` fences mobile, screen-video, and generic tutorials.

## Next step

Optionally run the `skill-creator` Claude-B eval (fresh chat, real catalogue) to
confirm the skill triggers by name. Not committed per user request
("Dont commit!"); re-run [Setup-CopilotSettings.ps1](../Setup-CopilotSettings.ps1)
to deploy the new skill to the `.copilot/skills` junction.
