<!-- markdownlint-disable MD033 MD041 -->
<!-- Logo floated left; two transparent variants switch by theme via <picture>.
     Judge on github.com — some in-editor previews mis-resolve prefers-color-scheme. -->
<picture>
  <source media="(prefers-color-scheme: dark)"
          srcset="assets/CA-logo-on-dark.png">
  <img align="left" width="300" alt="Copilot Atelier logo"
       src="assets/CA-logo-on-light.png">
</picture>
<!-- markdownlint-enable MD033 -->

**Portable GitHub Copilot customization** — agents, instructions, skills,
prompts, and hooks — synced across machines via OneDrive and linked into the
well-known `~/.copilot/` folders that VS Code and the Copilot CLI both read.

<!-- markdownlint-disable MD033 -->
<br clear="left">
<!-- markdownlint-enable MD033 -->

## Quick Start

You need PowerShell 5.1 or later, VS Code, and the GitHub Copilot Chat extension. No elevation is required.

```powershell
Install-Module -Name CopilotAtelier -Scope CurrentUser
Install-CopilotAtelier -InformationAction Continue
```

Restart VS Code. That is the whole setup — the agents appear in the Chat agent dropdown, skills and prompts appear under `/`, and instructions apply automatically to files matching their `applyTo` glob.

Keep it current with one command:

```powershell
Update-CopilotAtelier -InformationAction Continue
```

> [!NOTE]
> The Gallery package is not published yet — `2.0.0` is the first planned release. Until then use the [repository clone](#2-repository-clone) or the [agent plugin](#3-agent-plugin) path.

Full detail: [Setup on a New Machine](#setup-on-a-new-machine) · [Verifying It Works](#verifying-it-works) · [Building from Source](#building-from-source).

## Purpose

VS Code's GitHub Copilot — and the GitHub Copilot CLI — both look for custom agents, instructions, skills, and prompt files under `%USERPROFILE%\.copilot\{agents,instructions,skills,prompts}`. By default these stay local to a single machine and never sync.

CopilotAtelier solves that by storing the canonical files in a single folder named after the module (preferring OneDrive for cross-machine sync) and then linking the well-known `~/.copilot/*` discovery folders to that target with NTFS junctions. Write an agent once, use it from both the VS Code Copilot chat extension and the Copilot CLI, on every machine.

No `chat.*FilesLocations` settings are written for agents, instructions, or skills — those three are auto-discovered by both clients via the junctions. Prompts are the exception: the VS Code chat extension does not auto-discover `~/.copilot/prompts`, so a single `chat.promptFilesLocations` entry is written for that one path. The CLI auto-discovers it on its own. Installation removes repo-owned location entries written by older releases so the same Instruction is not registered through both OneDrive and `~/.copilot`; unrelated user locations are preserved.

Only one canonical location is populated per machine (no duplicate mirror). If an earlier release left a stale local mirror behind, the next run cleans it up when OneDrive is present.

## Folder Structure

```text
~/OneDrive/CopilotAtelier/       # Used when OneDrive is detected (preferred)
~/CopilotAtelier/                # Fallback — used only when OneDrive is not installed
├── Agents/          # Custom agents (.agent.md files)
├── Instructions/    # Custom instructions (.instructions.md files)
├── Skills/          # Agent skills (folders with SKILL.md)
├── Prompts/         # Prompt files / slash commands (.prompt.md files)
└── Hooks/           # Lifecycle hooks (hook config JSON plus scripts)
```

The folder name of the canonical target is `CopilotAtelier`, matching the module name. Repository-only content such as `.memory-bank/`, `tests/`, `Reference/`, the build system, and documentation is not copied into the Canonical target. `Keybindings/keybindings.json` is merged into the VS Code user profile rather than copied there.

## What Each Folder Contains

| Folder | File Type | Purpose |
|---|---|---|
| **Agents** | `*.agent.md` | Custom AI personas with specific tools, instructions, and model preferences. Core agents cover the software development pipeline; supplementary agents serve domain-specific side use cases. Appear in the agents dropdown in Chat. |
| **Instructions** | `*.instructions.md` | Coding standards, conventions, and guidelines. Can auto-apply based on file glob patterns (`applyTo`) or be attached manually. Includes [`copilot-authoring.instructions.md`](Instructions/copilot-authoring.instructions.md), which governs how the files in this repo are authored. |
| **Skills** | `<name>/SKILL.md` | Specialized capabilities with scripts, examples, and resources. Loaded on-demand when relevant. Appear as `/slash` commands. |
| **Prompts** | `*.prompt.md` | Reusable task templates invoked as `/slash` commands. Best for single, repeatable tasks like scaffolding or code review. |
| **Hooks** | `*.json` + `scripts/` | Shell commands run at fixed points in the agent loop. Deterministic guardrails that do not depend on the model choosing to obey them. See [`Hooks/README.md`](Hooks/README.md). |
| **Keybindings** | `keybindings.json` | Shared VS Code keybindings merged idempotently into `%APPDATA%\Code\User\keybindings.json`. See [Keybindings Applied](#keybindings-applied). |

## Available Skills

| Skill | Description |
|---|---|
| **automatedlab-deployment** | Build and deploy Hyper-V lab environments using AutomatedLab. Covers installation, lab definitions, roles (AD, File Server, Routing, PKI, SQL, etc.), networking, and post-deployment configuration. |
| **automatedlab-proxmox** | Diagnose AutomatedLab Windows provisioning and remoting failures on Proxmox/QEMU using orchestrator, hypervisor, guest-agent, Windows setup, and protocol evidence. Covers QEMU command completion, Sysprep/AppX failures, post-restart WinRM ordering, metadata flags, stale modules, and live verification. |
| **datum-configuration** | Comprehensive reference for the Datum PowerShell DSC configuration data module. Covers hierarchical data composition, `Datum.yml` configuration, resolution precedence, merge strategies, knockout prefix, handlers, RSOP computation, and the DscWorkshop reference implementation. Includes ProjectDagger-specific patterns, CommonTasks composite resources, DscConfig.Demo, build pipeline flow, GPO to DSC migration, and ecosystem relationships. |
| **dsc-troubleshooting** | Debug and troubleshoot PowerShell DSC resource failures on target nodes. Covers LCM diagnostics, event log analysis, resource debugging with `Wait-Debugger` and `Enter-PSHostProcess`, cache clearing, common exit codes, installer log analysis, and Windows Server 2025 specific issues (Start-Process UNC path hangs, class-based resource ForceModuleImport failures, SYSTEM profile logs). |
| **german-legal-research** | Legal research and statement drafting for German law (Deutsches Recht). Specializes in tenancy/rental law (Mietrecht), property management, and operating cost disputes. |
| **grammar-check** | Identify grammar, logical, and flow errors in text and suggest targeted fixes. Analyzes spelling, punctuation, subject-verb agreement, tense consistency, and transitions. |
| **memory-bank** | Initialize, route, and check a repository Memory Bank for durable work. Manages seven required version-controlled files plus local prompt history, preserves existing content byte-for-byte, supports explicitly routed Decision records and optional Memory Bank topics, checks provenance and compactness budgets, retains a Full-read fallback, and does nothing for read-only or transient tasks. |
| **citation-integrity** | Verify every external claim, quote, statistic, and reference in generated text against a fetched source. Defines a six-class failure taxonomy (F1 fabricated reference → F6 anchorless claim), a three-layer anchor (locator + ≤25-word quote + stable identifier), a `VERIFIED` / `MISMATCH` / `NOT_FOUND` verdict scheme with no gray zone, and a cross-index triangulation rule for contamination signals. |
| **devils-advocate-review** | Argue against a proposal, design, claim, or draft from a hostile-but-fair position with explicit safeguards against sycophancy. 1–5 rebuttal scoring rubric (concession only at ≥ 4, no consecutive concessions, attack-intensity preservation), named deflection classes (reframe, authority, volume, sentiment, goalpost shift, tu quoque, premature consensus), frame-lock self-check every three rounds, closing report with sycophancy log. |
| **social-signal-sweep** | Recency-bounded sweep (default 30 days) of what people are publicly saying about a topic across GitHub, Hacker News, Reddit, and Stack Overflow, plus a browser-only tier for YouTube and X. Produces a tier-8 lead sheet (platform, date, engagement signal, link, what-to-verify) to seed a deeper investigation — strictly leads-only, never citable. No bundled engine, no API keys, no cookies; uses web fetch, the GitHub tools, and the simple browser. Feeds the `research-analyst` SOURCE phase. |
| **outlook-calendar-export** | Export Outlook calendar entries to Markdown files via COM automation in PowerShell. Covers recurring appointments (`IncludeRecurrences`), date range filtering, Markdown generation with metadata tables, index file creation, and UTF-8 encoding best practices. |
| **outlook-email-export** | Export and extract emails from Outlook via COM automation in PowerShell. Covers searching by sender, recipient, CC, subject, or date range across multiple folders. |
| **pester-patterns** | Common Pester 5 test patterns and recipes for PowerShell module testing. Covers mocking file systems, REST APIs, DSC resources, databases, and credentials, plus Pattern 14 on Pester 5 runspace isolation — helpers used inside `It` must live in `BeforeAll` (symptom: misleading `CommandNotFoundException`); `-ForEach` data must go in `BeforeDiscovery`, not `BeforeAll`. |
| **sampler-build-debug** | Debug and troubleshoot Sampler-based PowerShell module builds and Pester 5 test failures. Covers running builds safely, reading Pester results, and diagnosing common failures. |
| **test-driven-development** | Test-first workflow for PowerShell/DSC: the red-green-refactor loop, writing a failing Pester test before the code, the test pyramid, DAMP-over-DRY readability, choosing what and at which level to test, and treating bug fixes as test-first. Enforces "no production change without a covering test". |
| **debugging-and-error-recovery** | A disciplined general debugging workflow — reproduce, localize, reduce, fix the root cause, then guard with a regression test. Stop-the-line on a red build; fix causes not symptoms; never swallow an error to hide a failure. PowerShell tactics for the call stack, tracing, and error records. |
| **code-review-and-quality** | A reusable five-axis code-review workflow (design, correctness, complexity, tests, clarity) for PowerShell/DSC changes. Severity labels (Blocker/Major/Minor/Nit), change sizing to stay reviewable, must-fix vs opinion, review speed and tone, and an author self-review gate. |
| **sampler-framework** | Comprehensive reference for the Sampler PowerShell module build framework. Covers project structure, `build.yaml` configuration, dependency management, build workflows, and testing patterns. |
| **mecm-dsc-deployment** | Deploy and troubleshoot Microsoft Endpoint Configuration Manager (MECM/SCCM) via DSC using ConfigMgrCBDsc, CommonTasks, and UpdateServicesDsc modules in DscWorkshop/Datum environments. Covers ADK/WinPE product registration, SCCM 2509 silent install, UpdateServicesDsc bugs, Datum merge strategies for Tiny scenarios, cross-domain SQL access, and AutomatedLab operational patterns. |
| **pandoc-docx-export** | Export Markdown documents to polished DOCX files using pandoc with custom formatting: landscape pages for wide tables, custom column widths, reduced table font sizes, and proper `reference.docx` styling. |
| **pdf-to-markdown** | Convert PDF files to well-structured Markdown using .NET-native PDF parsing in PowerShell — no external tools required. Decompresses zlib/deflate content streams, decodes hex-encoded text operators, and reconstructs lines by Y-coordinate positioning. Best suited for structured documents like payslips, invoices, and reports. |
| **sampler-migration** | Step-by-step guide for migrating a legacy PowerShell module project to the Sampler build framework. Covers migrating from AppVeyor, PSDepend, PSDeploy, and Pester 4. |
| **send-outlook-email** | Send emails via the Outlook COM API from PowerShell. Supports plain-text and HTML-formatted emails with subject and body content. |
| **create-outlook-draft** | Create Outlook email drafts from Markdown email files via COM automation in PowerShell. Parses metadata tables (To, CC, Subject), converts Markdown body to styled HTML (tables, bold, lists), and saves drafts to the Outlook Drafts folder. Handles COM lifecycle, locked items, duplicate cleanup, and batch processing. |
| **docx-to-markdown** | Convert DOCX (Word) files to Markdown using .NET-native ZIP/XML parsing in PowerShell — no pandoc, Word COM, or Python required. Extracts paragraph text with heading styles and handles both English and German style names. Fallback when pandoc is unavailable. |
| **xlsx-to-markdown** | Convert XLSX (Excel) files to Markdown tables using .NET-native ZIP/XML parsing in PowerShell — no Excel COM, ImportExcel, or Python required. Handles shared strings, cell references, multi-sheet workbooks, inline strings, and column letter-to-index conversion. |
| **microsoft-todo-tasks** | Create, list, and manage Microsoft To Do tasks via the Graph REST API using raw OAuth2 device code flow in PowerShell. Bypasses the buggy Microsoft.Graph SDK (WAM broker issues, System.Text.Json conflicts) and supports personal Microsoft accounts (live.com). |
| **long-running-job-monitor** | Monitor long-running tests, deployments, and remote jobs with timestamped logs, terminal markers, structured `Summary` / `Liveness` / `ProgressToken` probes, phase-sized stall thresholds, channel-loss recovery, and restart-scoped readiness. |
| **winrm-troubleshooting** | Diagnose WinRM connectivity and post-restart readiness failures. Covers guarded service recovery, listener and certificate configuration, scoped firewall and TrustedHosts changes, authentication, raise-only quotas, event diagnostics, and PowerShell Direct fallback. |
| **marp-slide-overflow** | Detect and fix content overflow in Marp slide decks before exporting to PPTX/PDF/PNG. Provides a Puppeteer-based `scrollHeight`-vs-viewBox detector, a side-by-side HTML review report, a two-tier CSS density pattern (`dense` / `compact`), a `fillRatio` decision table, a mandatory PNG-based visual verification workflow (Recipe 0), a `mermaid-cli` pre-render pattern (Marp has no native mermaid support; client-side mermaid.js fails in PDF/PPTX) with content-hash caching, image-height CSS cap, and mermaid label-quoting gotchas, and Recipe 5 on speaker-note coverage — code-fence-aware slide splitting, directive vs. real-note filtering, section-divider assertions, a drop-in Pester guard, and a `notes-title-map.psd1` pattern for multi-file decks. |
| **whisper-pyannote-transcription** | Transcribe long audio/video on Windows with GPU acceleration using `faster-whisper` (CTranslate2, large-v3) and add speaker labels with `pyannote.audio` 3.1. Covers ffmpeg 16 kHz mono extraction, Python 3.12 venv isolation, CUDA-matched PyTorch wheels (`cu128`), Hugging Face gated-model access, and merging RTTM speaker turns into Whisper segments to produce speaker-labeled SRT, JSON, and grouped transcript text. Documents the Windows `torchcodec` bypass (preload waveform via `torchaudio`) and the `Tee-Object` exit-code trap. |
| **authenticated-web-extraction** | Extract data from sites that require login (LinkedIn, GitHub, Sessionize, Microsoft 365, X, Meetup) using a persistent Playwright + Microsoft Edge profile at `%LOCALAPPDATA%\CareerAuthBrowser\`. Ships a bundled `bootstrap/` (package.json, `open.mjs`, `extract.mjs`, `check-logins`, `dump-cookies`) for one-command profile rebuild. Documents the session-cookie-vanish workaround (re-inject saved cookies on every run), per-site auth-cookie names (`li_at`, `user_session`, `.AspNet.ApplicationCookie`, `auth_token`, `MEETUP_MEMBER`), Edge tracking-prevention flags required for OAuth callbacks, and the profile-lock orphan-process gotcha. |
| **windows-gui-screenshot-capture** | Capture Windows desktop GUI screenshots and assemble screenshot-embedded Markdown user manuals. Branches between self-capturing scene modes for modifiable apps and external drivers for existing or third-party executables. Covers rendering-engine-specific APIs, process-scoped control discovery, event-based dialog/control readiness, GPU and premature black frames, cross-process controls, native dialogs, state restoration, pixel/landmark validation, and final visual review. Ships per-engine and external-Win32 references plus a native-dialog helper. |

## VS Code Settings Applied

`Install-CopilotAtelier` configures the following in `settings.json`:

### File Locations

Discovery is junction-based for agents, instructions, and skills — `chat.agentFilesLocations`, `chat.instructionsFilesLocations`, and `chat.agentSkillsLocations` are not written, because both the VS Code Copilot chat extension and the GitHub Copilot CLI auto-discover the well-known `~/.copilot/{agents,instructions,skills}` paths. Installation removes the historical `~/CopilotAtelier/*` and `~/OneDrive/CopilotAtelier/*` entries for this repository while preserving unrelated user locations. Prompts are the exception: VS Code Copilot Chat reads prompts only from `%APPDATA%\Code\User\prompts` and from paths listed in `chat.promptFilesLocations` (only the CLI auto-discovers `~/.copilot/prompts`), so a single `chat.promptFilesLocations` entry is written for `${userHome}/.copilot/prompts`. The five Customization folders are copied to one Canonical target and NTFS junctions are created under `%USERPROFILE%\.copilot\` so both clients see the same files:

```text
%USERPROFILE%\.copilot\agents       --> <target>\Agents
%USERPROFILE%\.copilot\instructions --> <target>\Instructions
%USERPROFILE%\.copilot\skills       --> <target>\Skills
%USERPROFILE%\.copilot\prompts      --> <target>\Prompts
%USERPROFILE%\.copilot\hooks        --> <target>\Hooks
```

Where `<target>` is `%USERPROFILE%\OneDrive\CopilotAtelier` when OneDrive is installed, otherwise `%USERPROFILE%\CopilotAtelier`.

If one of the `~/.copilot\<name>` folders already exists as a real directory:

- Empty → removed silently and replaced with the junction.
- Non-empty → the script prompts before deleting. On `y`, its contents are merged into the target (existing target files are not overwritten) and then the directory is removed and replaced with the junction. On `n`, the junction is skipped and a warning is printed.

Existing junctions are recreated on every run so they always point at the current target.

#### Claude Code and Agent Skills clients (opt-in)

Run `Setup-CopilotSettings.ps1 -IncludeClaudeCodeLinks` to additionally link `~/.claude/skills` and `~/.agents/skills` to the same `Skills` directory, so Claude Code and other [agentskills.io](https://agentskills.io/) clients discover the library too. This is off by default: VS Code reads all three user-level skill locations, so enabling it registers every Skill more than once in VS Code. Use it on machines where a non-Copilot client is the primary consumer. These two links are create-only — if a path already exists it belongs to that other tool and is left untouched.

### Feature Flags

| Setting | Value | What It Does |
|---|---|---|
| `chat.includeApplyingInstructions` | `true` | Auto-apply `.instructions.md` files when their `applyTo` glob matches files being worked on |
| `chat.includeReferencedInstructions` | `true` | Follow Markdown links in instruction files and load referenced content into context |
| `chat.hookFilesLocations` | `~/.copilot/hooks` | Load the shared lifecycle hooks; merged so user-added hook locations and the Claude Code defaults survive |
| `github.copilot.chat.agent.thinkingTool` | `true` | Enable the thinking tool so agents can reason through complex problems before acting |
| `github.copilot.chat.search.semanticTextResults` | `true` | Improve search results in agent mode with semantic matching |
| `github.copilot.chat.skillTool.enabled` | `true` | Allow Skills that declare `context: fork` to run in a dedicated subagent and return only their result |
| `github.copilot.chat.agent.maxRequests` | `500` | Raise the per-turn agent request budget so long autonomous loops do not stall on the default limit |

### AI Model Preferences

Every agent in [`Agents/`](Agents/) declares `model` as a priority array — `['Claude Opus 5 (copilot)', 'Claude Opus 4.8 (copilot)']` — so a model retirement degrades to the GA fallback instead of breaking all eleven agents at once.

| Setting | Value | What It Does |
|---|---|---|
| `gitlens.ai.vscode.model` | `copilot:claude-opus-5` | Use Claude Opus 5 for GitLens AI features (commit messages, explanations) |

> **Note on model availability**: Opus 5 requires Copilot Pro+, Business, or Enterprise. On other plans VS Code falls back to the next entry in the agent's `model` array, then to its default. Setup also removes the `github.copilot.advanced.model` key written by earlier releases: `github.copilot.advanced` is the completions bag and has no documented `model` member, so the value was never consumed.

## Keybindings Applied

The setup script merges the bindings in [`Keybindings/keybindings.json`](Keybindings/keybindings.json) into `%APPDATA%\Code\User\keybindings.json`. The merge is idempotent (match key: `key + command + when`), preserves user-added bindings, and creates a timestamped backup on every run.

| Key | Command | Purpose |
|---|---|---|
| `Ctrl+K X` | `PowerShell.RestartSession` | Restart the PowerShell integrated console |
| `Ctrl+K N` | `workbench.action.terminal.moveIntoNewWindow` | Pop the active terminal into a new window |
| `Ctrl+K K` | `workbench.action.chat.openInNewWindow` | Pop the Chat view into a new window |
| `Ctrl+Enter` | `workbench.action.chat.submit` | Submit chat prompt (replaces plain `Enter`) |
| `Enter` | `-workbench.action.chat.submit` | Disabled so plain `Enter` always inserts a newline in the chat input |

## Setup on a New Machine

There are three installation paths. The PowerShell Gallery is the recommended one because it carries every customization type and brings versioning and an update command with it.

### 1. PowerShell Gallery (recommended)

```powershell
Install-Module -Name CopilotAtelier -Scope CurrentUser
Install-CopilotAtelier -InformationAction Continue
```

The module ships `Agents`, `Instructions`, `Skills`, `Prompts`, `Hooks`, and `Keybindings` as part of its payload, so a Gallery install carries the same content as a repository clone.

| Command | Purpose |
|---|---|
| `Install-CopilotAtelier` | Deploys the customizations to the canonical target, links the `~/.copilot` discovery folders, and merges the VS Code settings and keybindings. |
| `Update-CopilotAtelier` | Checks the Gallery for a newer version, installs it, and redeploys. `-Force` redeploys the current version; `-SkipDeployment` stages the update for later. |
| `Get-CopilotAtelierVersion` | Reports the installed module version, the deployed version, and whether the deployment is current. |

Both `Install-CopilotAtelier` and `Update-CopilotAtelier` write their progress to the information stream, so add `-InformationAction Continue` when you want to watch each step.

Useful switches:

| Switch | Effect |
|---|---|
| `-IncludeClaudeCodeLinks` | Also links `~/.claude/skills` and `~/.agents/skills`. Off by default; see [Claude Code and Agent Skills clients](#claude-code-and-agent-skills-clients-opt-in). |
| `-SkipCopilotCliEnvironment` | Leaves `COPILOT_ALLOW_ALL` alone. Installation otherwise sets it to `1` at User scope, which is what stops the GitHub Copilot CLI prompting for every tool call. |
| `-WhatIf` | Reports what would change without touching anything. |

Run `Get-Help Install-CopilotAtelier -Full` for the complete parameter reference.

#### Staying up to date

```powershell
Update-CopilotAtelier -InformationAction Continue
```

`Update-CopilotAtelier` compares the installed version against the Gallery, installs a newer one if there is one, and then redeploys from it, so the discovery folders always match the module you have. Use `-Force` to redeploy the current version and `-SkipDeployment` to stage an update you will deploy later.

`Get-CopilotAtelierVersion` answers "is what I have actually deployed?":

```text
Version         : 2.0.0
DeployedVersion : 2.0.0
DeployedOn      : 2026-07-29 10:12:44
TargetPath      : C:\Users\you\OneDrive\CopilotAtelier
IsCurrent       : True
```

`IsCurrent : False` means the module was updated but the customizations on disk still come from an older version — run `Install-CopilotAtelier` to catch them up. The values come from `<target>/.copilotatelier.json`, which every deployment rewrites.

#### More than one machine

When OneDrive is present the canonical target lives inside it, so a second machine that already syncs the folder still needs its own `Install-CopilotAtelier` run to create the `~/.copilot` links and patch VS Code. After that, editing an agent in the synced folder propagates on its own; a module update needs `Update-CopilotAtelier` on each machine.

### 2. Repository clone

1. Clone this repository (or sign into OneDrive if you already keep a synced clone there).
2. Open PowerShell and run the setup script from the cloned location, for example:

```powershell
# From a local clone
& "<path-to-clone>\Setup-CopilotSettings.ps1"

# Or from a OneDrive-synced clone
& "$env:USERPROFILE\OneDrive\CopilotAtelier\Setup-CopilotSettings.ps1"
```

[`Setup-CopilotSettings.ps1`](Setup-CopilotSettings.ps1) dot-sources the module commands from `source/` and runs `Install-CopilotAtelier` against the clone, so the working tree is deployed without building or installing the module first.

3. Restart VS Code.

### What either path does

The customizations are copied into `~/OneDrive/CopilotAtelier/` when OneDrive is detected, or into `~/CopilotAtelier/` otherwise. NTFS junctions (symbolic links on macOS and Linux) at `~/.copilot/{agents,instructions,skills,prompts,hooks}` then point to that target, so both the VS Code Copilot chat extension and the GitHub Copilot CLI pick up the same files. Your VS Code `settings.json` and `keybindings.json` are patched idempotently with timestamped backups, and the deployed version is recorded in `<target>/.copilotatelier.json`. If a stale `~/CopilotAtelier/` mirror exists from a previous dual-copy run, it is removed when OneDrive is now used. If a pre-existing non-empty folder is found at any of the link paths, you are asked before it is deleted (and its contents are copied into the target first).

### 3. Agent plugin

[`plugin.json`](plugin.json) also publishes the Agents and Skills as an agent plugin, which installs directly from the Git URL in VS Code, the GitHub Copilot CLI, and Claude Code:

1. Run **Chat: Install Plugin From Source** from the Command Palette.
2. Enter `https://github.com/raandree/CopilotAtelier`.

Plugin-provided skills appear as `/copilot-atelier:<skill>` and update automatically when VS Code checks for extension updates.

The plugin format does not carry `.instructions.md` files or hooks, so this path gives you agents and skills only. Install the module from the Gallery when you also want the Instructions and the deterministic hook guardrails. The paths are complementary.

## Building from Source

The repository is a [Sampler](https://github.com/gaelcolas/Sampler) project. The module sources live in `source/`, the customization directories stay at the repository root, and the `Copy_Customizations_To_Output` build task copies them into the built module.

```powershell
# First run; resolves the build dependencies into output/RequiredModules
./build.ps1 -ResolveDependency -Tasks build

# Subsequent runs
./build.ps1 -Tasks build
./build.ps1 -Tasks test
```

The version comes from [GitVersion](https://gitversion.net/) via [`GitVersion.yml`](GitVersion.yml), so the built module lands in `output/module/CopilotAtelier/<version>/`. [`.github/workflows/ci.yml`](.github/workflows/ci.yml) packages once on `ubuntu-latest`, tests that artifact on Linux, macOS, Windows, and Windows PowerShell 5.1, and deploys the GitHub release and the Gallery package from `main`. Deployment needs the `GitHubToken` and `GalleryApiToken` repository secrets.

> [!NOTE]
> Run `build.ps1` and `Invoke-Pester` in a detached process rather than the VS Code integrated terminal. See [`Instructions/powershell-execution-safety.instructions.md`](Instructions/powershell-execution-safety.instructions.md).

## Verifying It Works

- **Agents**: In Copilot Chat, check the agents dropdown — your custom agents should appear
- **Instructions**: Type `/instructions` in chat to see the Configure Instructions menu
- **Skills**: Type `/` in chat to see skills as slash commands
- **Prompts**: Type `/` in chat to see prompt files as slash commands
- **Hooks**: Run **Developer: Show Agent Debug Logs** and look for `Load Hooks` listing `~/.copilot/hooks`; hook output goes to the **GitHub Copilot Chat Hooks** channel in the Output panel
- **Chat Customizations editor**: Click the gear icon in the Chat view (or run **Chat: Open Chat Customizations** from the Command Palette) to see all registered agents, instructions, skills, and prompts in one place
- **Debug logs**: If customizations aren't being applied, open the ellipsis (**…**) menu in the Chat view → **Show Agent Debug Logs**

## Troubleshooting Skills

If a skill in the `Skills/` folder is not being discovered by VS Code, check the following:

### YAML Frontmatter Is Required

Every `SKILL.md` file **must** start with YAML frontmatter containing `name` and `description` fields. Without this, VS Code cannot register the skill.

```markdown
---
name: my-skill-name
description: >-
  A description of what the skill does. Include USE FOR and DO NOT USE FOR
  trigger phrases to help Copilot know when to load it.
---

# Skill Title

Content starts here...
```

### Blank Line After Frontmatter

There **must** be a blank line between the closing `---` delimiter and the first line of content. Some parsers fail to separate the metadata from the document body without it.

**Correct:**

```markdown
---
name: my-skill
description: >-
  My skill description.
---

# My Skill
```

**Incorrect:**

```markdown
---
name: my-skill
description: >-
  My skill description.
---
# My Skill
```

### Reload Required

After adding or fixing a skill file, you must **reload VS Code** (or start a new chat session) for the skill to be discovered.

### Verifying Skills Are Loaded

To confirm a skill is registered:

1. In the Chat view, click the gear icon (**Configure Chat**) — or run **Chat: Open Chat Customizations** from the Command Palette
2. Select the **Skills** tab and look for your skill in the list
3. Alternatively, type `/skills` in chat to open the Configure Skills menu

If a skill doesn't appear, open the ellipsis (**…**) menu in the Chat view and choose **Show Agent Debug Logs** to see why it failed to load (usually a frontmatter or `name`/directory mismatch).

## Useful Chat Shortcuts

| Command | Action |
|---|---|
| `/agents` | Configure Custom Agents menu |
| `/instructions` | Configure Instructions and Rules menu |
| `/skills` | Configure Skills menu |
| `/prompts` | Configure Prompt Files menu |
| `/init` | Generate workspace instructions from your codebase |

## Reference

- [`Reference/copilot-cli-model-routing.md`](Reference/copilot-cli-model-routing.md) — 4-tier model-routing policy for the GitHub Copilot CLI (Executors / Implementers / Tech Leads / Architects). Reference-only; not auto-attached. The document was written against the early-2026 lineup; a banner at the top maps the older model IDs (Opus 4.5 / 4.6, GPT-5.1) to the current ones (Opus 4.8, GPT-5.4 / 5.5). A full rewrite is planned post-1.1.0.
- [`Reference/howto-write-skills.md`](Reference/howto-write-skills.md) — condensed two-page primer for authoring `Skills/**/SKILL.md` files: the six-step frame (Name/Trigger/Outcome/Dependencies/Step-by-step/Edge cases), five high-leverage rules, hard limits (1024-char description, 500-line body), description shape, degrees of freedom, eval-driven development, anti-patterns, and links to the canonical Anthropic Agent Skills docs/PDF/engineering blog plus the `anthropics/skills` repo. Pairs with [`Skills/skill-creator/SKILL.md`](Skills/skill-creator/SKILL.md) (the full operating manual, auto-loaded when a skill-authoring task triggers).

## Featured In

- [**The Agentic Operating Model**](https://github.com/raandree/AgenticOperatingModel) — a 1h/2h/4h presentation and workshop on versioned, agent-assisted knowledge work. CopilotAtelier is used as the reference exemplar of a mature personal atelier (Module 3 — *Your Atelier — Customization as Code*; Module 8 — *A Mature Personal Atelier*) and as the cross-machine instruction-sync pattern. The workshop also publishes complementary, project-level material that pairs well with this repo:
  - [Agentic Knowledge-Work Patterns](https://github.com/raandree/AgenticOperatingModel/blob/main/content/materials/agentic-knowledge-work-patterns.md) — ten reusable patterns for applying the operating model beyond code.
  - [Memory Bank Template](https://github.com/raandree/AgenticOperatingModel/tree/main/content/materials/memory-bank-template) — a tool-neutral starter set for per-project memory banks.

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.
