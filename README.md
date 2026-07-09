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

**Portable GitHub Copilot customization** — agents, instructions, skills, and
prompts — synced across machines via OneDrive and linked into the well-known
`~/.copilot/` folders that VS Code and the Copilot CLI both read.

<!-- markdownlint-disable MD033 -->
<br clear="left">
<!-- markdownlint-enable MD033 -->

## Purpose

VS Code's GitHub Copilot — and the GitHub Copilot CLI — both look for custom agents, instructions, skills, and prompt files under `%USERPROFILE%\.copilot\{agents,instructions,skills,prompts}`. By default these stay local to a single machine and never sync.

CopilotAtelier solves that by storing the canonical files in a single, repo-derived folder (preferring OneDrive for cross-machine sync) and then linking the well-known `~/.copilot/*` discovery folders to that target with NTFS junctions. Write an agent once, use it from both the VS Code Copilot chat extension and the Copilot CLI, on every machine.

No `chat.*FilesLocations` settings are written for agents, instructions, or skills — those three are auto-discovered by both clients via the junctions. Prompts are the exception: the VS Code chat extension does not auto-discover `~/.copilot/prompts`, so the script writes a single `chat.promptFilesLocations` entry for that one path. The CLI auto-discovers it on its own.

Only one canonical location is populated per machine (no duplicate mirror). If a previous version of the script left a stale local mirror behind, the new run cleans it up automatically when OneDrive is present.

## Folder Structure

```text
~/OneDrive/CopilotAtelier/       # Used when OneDrive is detected (preferred)
~/CopilotAtelier/                # Fallback — used only when OneDrive is not installed
├── Agents/          # Custom agents (.agent.md files)
├── Instructions/    # Custom instructions (.instructions.md files)
├── Skills/          # Agent skills (folders with SKILL.md)
├── Prompts/         # Prompt files / slash commands (.prompt.md files)
├── Keybindings/     # keybindings.json merged into your user profile
├── Setup-CopilotSettings.ps1   # Setup script
└── README.md        # This file
```

The folder name is derived from the repository clone, so renaming the clone renames the synced layout automatically.

## What Each Folder Contains

| Folder | File Type | Purpose |
|---|---|---|
| **Agents** | `*.agent.md` | Custom AI personas with specific tools, instructions, and model preferences. Core agents cover the software development pipeline; supplementary agents serve domain-specific side use cases. Appear in the agents dropdown in Chat. |
| **Instructions** | `*.instructions.md` | Coding standards, conventions, and guidelines. Can auto-apply based on file glob patterns (`applyTo`) or be attached manually. Includes [`copilot-authoring.instructions.md`](Instructions/copilot-authoring.instructions.md), which governs how the files in this repo are authored. |
| **Skills** | `<name>/SKILL.md` | Specialized capabilities with scripts, examples, and resources. Loaded on-demand when relevant. Appear as `/slash` commands. |
| **Prompts** | `*.prompt.md` | Reusable task templates invoked as `/slash` commands. Best for single, repeatable tasks like scaffolding or code review. |
| **Keybindings** | `keybindings.json` | Shared VS Code keybindings merged idempotently into `%APPDATA%\Code\User\keybindings.json`. See [Keybindings Applied](#keybindings-applied). |

## Available Skills

| Skill | Description |
|---|---|
| **automatedlab-deployment** | Build and deploy Hyper-V lab environments using AutomatedLab. Covers installation, lab definitions, roles (AD, File Server, Routing, PKI, SQL, etc.), networking, and post-deployment configuration. |
| **datum-configuration** | Comprehensive reference for the Datum PowerShell DSC configuration data module. Covers hierarchical data composition, `Datum.yml` configuration, resolution precedence, merge strategies, knockout prefix, handlers, RSOP computation, and the DscWorkshop reference implementation. Includes ProjectDagger-specific patterns, CommonTasks composite resources, DscConfig.Demo, build pipeline flow, GPO to DSC migration, and ecosystem relationships. |
| **dsc-troubleshooting** | Debug and troubleshoot PowerShell DSC resource failures on target nodes. Covers LCM diagnostics, event log analysis, resource debugging with `Wait-Debugger` and `Enter-PSHostProcess`, cache clearing, common exit codes, installer log analysis, and Windows Server 2025 specific issues (Start-Process UNC path hangs, class-based resource ForceModuleImport failures, SYSTEM profile logs). |
| **german-legal-research** | Legal research and statement drafting for German law (Deutsches Recht). Specializes in tenancy/rental law (Mietrecht), property management, and operating cost disputes. |
| **grammar-check** | Identify grammar, logical, and flow errors in text and suggest targeted fixes. Analyzes spelling, punctuation, subject-verb agreement, tense consistency, and transitions. |
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
| **winrm-troubleshooting** | Debug and troubleshoot Windows Remote Management (WinRM) connectivity failures on Windows servers, including lab VMs managed by AutomatedLab. Covers service state recovery, listener configuration, authentication failures, and PowerShell Direct fallback. |
| **marp-slide-overflow** | Detect and fix content overflow in Marp slide decks before exporting to PPTX/PDF/PNG. Provides a Puppeteer-based `scrollHeight`-vs-viewBox detector, a side-by-side HTML review report, a two-tier CSS density pattern (`dense` / `compact`), a `fillRatio` decision table, a mandatory PNG-based visual verification workflow (Recipe 0), a `mermaid-cli` pre-render pattern (Marp has no native mermaid support; client-side mermaid.js fails in PDF/PPTX) with content-hash caching, image-height CSS cap, and mermaid label-quoting gotchas, and Recipe 5 on speaker-note coverage — code-fence-aware slide splitting, directive vs. real-note filtering, section-divider assertions, a drop-in Pester guard, and a `notes-title-map.psd1` pattern for multi-file decks. |
| **whisper-pyannote-transcription** | Transcribe long audio/video on Windows with GPU acceleration using `faster-whisper` (CTranslate2, large-v3) and add speaker labels with `pyannote.audio` 3.1. Covers ffmpeg 16 kHz mono extraction, Python 3.12 venv isolation, CUDA-matched PyTorch wheels (`cu128`), Hugging Face gated-model access, and merging RTTM speaker turns into Whisper segments to produce speaker-labeled SRT, JSON, and grouped transcript text. Documents the Windows `torchcodec` bypass (preload waveform via `torchaudio`) and the `Tee-Object` exit-code trap. |
| **authenticated-web-extraction** | Extract data from sites that require login (LinkedIn, GitHub, Sessionize, Microsoft 365, X, Meetup) using a persistent Playwright + Microsoft Edge profile at `%LOCALAPPDATA%\CareerAuthBrowser\`. Ships a bundled `bootstrap/` (package.json, `open.mjs`, `extract.mjs`, `check-logins`, `dump-cookies`) for one-command profile rebuild. Documents the session-cookie-vanish workaround (re-inject saved cookies on every run), per-site auth-cookie names (`li_at`, `user_session`, `.AspNet.ApplicationCookie`, `auth_token`, `MEETUP_MEMBER`), Edge tracking-prevention flags required for OAuth callbacks, and the profile-lock orphan-process gotcha. |

## VS Code Settings Applied

The setup script configures the following in `settings.json`:

### File Locations

Discovery is junction-based for agents, instructions, and skills — the script does not write `chat.agentFilesLocations`, `chat.instructionsFilesLocations`, or `chat.agentSkillsLocations` because both the VS Code Copilot chat extension and the GitHub Copilot CLI auto-discover the well-known `~/.copilot/{agents,instructions,skills}` paths. Prompts are the exception: VS Code Copilot Chat reads prompts only from `%APPDATA%\Code\User\prompts` and from paths listed in `chat.promptFilesLocations` (only the CLI auto-discovers `~/.copilot/prompts`), so the script writes a single `chat.promptFilesLocations` entry for `${userHome}/.copilot/prompts` via a merge that preserves any user-added prompt locations. The script copies the four customization folders to a single canonical target and creates NTFS junctions under `%USERPROFILE%\.copilot\` so both clients see the same files:

```text
%USERPROFILE%\.copilot\agents       --> <target>\Agents
%USERPROFILE%\.copilot\instructions --> <target>\Instructions
%USERPROFILE%\.copilot\skills       --> <target>\Skills
%USERPROFILE%\.copilot\prompts      --> <target>\Prompts
```

Where `<target>` is `%USERPROFILE%\OneDrive\CopilotAtelier` when OneDrive is installed, otherwise `%USERPROFILE%\CopilotAtelier`.

If one of the `~/.copilot\<name>` folders already exists as a real directory:

- Empty → removed silently and replaced with the junction.
- Non-empty → the script prompts before deleting. On `y`, its contents are merged into the target (existing target files are not overwritten) and then the directory is removed and replaced with the junction. On `n`, the junction is skipped and a warning is printed.

Existing junctions are recreated on every run so they always point at the current target.

### Feature Flags

| Setting | Value | What It Does |
|---|---|---|
| `chat.includeApplyingInstructions` | `true` | Auto-apply `.instructions.md` files when their `applyTo` glob matches files being worked on |
| `chat.includeReferencedInstructions` | `true` | Follow Markdown links in instruction files and load referenced content into context |
| `github.copilot.chat.agent.thinkingTool` | `true` | Enable the thinking tool so agents can reason through complex problems before acting |
| `github.copilot.chat.search.semanticTextResults` | `true` | Improve search results in agent mode with semantic matching |
| `github.copilot.chat.agent.maxRequests` | `500` | Raise the per-turn agent request budget so long autonomous loops do not stall on the default limit |

### AI Model Preferences

| Setting | Value | What It Does |
|---|---|---|
| `gitlens.ai.vscode.model` | `copilot:claude-opus-4.8` | Use Claude Opus 4.8 for GitLens AI features (commit messages, explanations). Opus 4.8 is the current Copilot release, superseding Opus 4.7 (which replaced Opus 4.5 / 4.6). |
| `github.copilot.advanced.model` | `claude-opus-4.8` | Use Claude Opus 4.8 for inline autocompletions (experimental; may be overridden server-side). |

> **Note on model availability**: Opus 4.8 requires Copilot Pro+, Business, or Enterprise. On other plans VS Code falls back to its default. To pin a different model, edit `Setup-CopilotSettings.ps1` or override these two settings in your `settings.json` after running the script.

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

1. Clone this repository (or sign into OneDrive if you already keep a synced clone there).
2. Open PowerShell and run the setup script from the cloned location, for example:

```powershell
# From a local clone
& "<path-to-clone>\Setup-CopilotSettings.ps1"

# Or from a OneDrive-synced clone
& "$env:USERPROFILE\OneDrive\CopilotAtelier\Setup-CopilotSettings.ps1"
```

The script copies the contents of the clone into `~/OneDrive/CopilotAtelier/` when OneDrive is detected, or into `~/CopilotAtelier/` otherwise, then creates NTFS junctions at `~/.copilot/{agents,instructions,skills,prompts}` pointing to that target so both the VS Code Copilot chat extension and the GitHub Copilot CLI pick up the same files. It also patches your VS Code `settings.json` and `keybindings.json` idempotently with timestamped backups. If a stale `~/CopilotAtelier/` mirror exists from a previous dual-copy run, the script removes it when OneDrive is now used. If a pre-existing non-empty folder is found at any of the `~/.copilot/*` link paths, the script asks before deleting it (and copies its contents into the target first).

3. Restart VS Code.

## Verifying It Works

- **Agents**: In Copilot Chat, check the agents dropdown — your custom agents should appear
- **Instructions**: Type `/instructions` in chat to see the Configure Instructions menu
- **Skills**: Type `/` in chat to see skills as slash commands
- **Prompts**: Type `/` in chat to see prompt files as slash commands
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
