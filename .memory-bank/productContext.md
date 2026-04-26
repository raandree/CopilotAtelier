# Product context

## Why this project exists

VS Code's GitHub Copilot supports custom agents, instructions, skills, and prompt files, but by default these are stored locally in the VS Code profile or workspace. This means customizations do not follow the developer across machines. CopilotAtelier solves this by redirecting all four customization locations to a single repo-derived folder — the OneDrive-synced folder when available, or a plain user-profile folder otherwise — ensuring every machine gets the same Copilot setup automatically.

## Problems it solves

1. **Configuration drift** — Without centralization, each machine accumulates its own divergent set of Copilot customizations.
2. **Onboarding friction** — Setting up a new machine previously required manually recreating all agent definitions, instruction files, and skills.
3. **Inconsistent coding standards** — Without shared instruction files, AI-assisted code on different machines may follow different conventions.
4. **Lost knowledge** — Custom skills and prompt templates were tied to individual workspaces and easily lost.

## How it works

1. All customization files live under a single repo-derived folder organized into four subdirectories: Agents, Instructions, Skills, Prompts. When OneDrive is signed in the folder is `~/OneDrive/CopilotAtelier/`; otherwise the script falls back to `~/CopilotAtelier/`. Only one location is populated per machine — no dual mirror.
2. A PowerShell setup script (`Setup-CopilotSettings.ps1`) patches VS Code's `settings.json` to point all four Copilot file-location settings at the chosen folder (OneDrive when present, local profile otherwise).
3. The script is idempotent: it merges new entries into existing settings, strips JSONC comments before parsing, and creates a timestamped backup on every run.
4. The chosen target folder is populated by copying the repo contents on every run. When OneDrive is present, the OneDrive folder is used and changes propagate to every signed-in machine. When OneDrive is absent, the local `~/CopilotAtelier/` folder is used so the library still works on standalone machines. Stale local mirrors from older dual-copy runs are cleaned up automatically.

## User experience goals

- **Zero-friction portability**: sign into OneDrive, run one script, restart VS Code — done.
- **Write once, use everywhere**: create an agent or instruction file once and it appears on every machine.
- **Non-destructive**: the setup script never removes user-added settings; it only merges.
- **Discoverable**: all agents appear in the Copilot agents dropdown; all skills and prompts appear as `/slash` commands.

## Target personas

| Persona | Use case |
|---|---|
| PowerShell module developer | Consistent coding standards, Sampler build expertise, security reviews |
| Multi-machine developer | Same Copilot experience on desktop, laptop, and VM |
| Team lead | Distributing coding standards and review processes via shared OneDrive |
