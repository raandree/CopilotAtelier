---
status: current
last-verified: 2026-07-24
owner: shared
source: README.md
---

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
2. A PowerShell Setup script copies `Agents/`, `Instructions/`, `Skills/`, and `Prompts/` into the chosen target and creates Discovery links at `%USERPROFILE%\.copilot\{agents,instructions,skills,prompts}`. The repository-local `.memory-bank/`, tests, references, and documentation are not deployed.
3. Both the VS Code Copilot chat extension and the GitHub Copilot CLI discover Customizations under `~/.copilot`. Prompts additionally require one `chat.promptFilesLocations` entry. Setup removes obsolete repo-owned location aliases so one Instruction cannot be registered through both OneDrive and its Discovery link.
4. The script is idempotent: it preserves unrelated user locations, strips JSONC comments before parsing, recreates Discovery links to track the Canonical target, and creates a timestamped backup on every run. Pre-existing real folders at the link paths are removed silently when empty; when non-empty the script prompts before merging their contents into the target and deleting the folder.
5. When OneDrive is present, the OneDrive folder is used and changes propagate to every signed-in machine. Otherwise the local `~/CopilotAtelier/` folder keeps the library usable on standalone machines. Stale local mirrors from older dual-copy runs are cleaned up automatically.
6. In a working repository, shared Pre-flight reads the Memory Bank index and
   selects task-relevant files. It initializes missing canonical files only
   before durable writes, fails open to complete-base loading when routing is
   unsafe, and creates nothing for read-only or transient tasks.

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
