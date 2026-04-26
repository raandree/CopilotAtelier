# Copilot Customization via OneDrive

## Purpose

VS Code's GitHub Copilot supports custom agents, instructions, skills, and prompt files — but by default these are stored locally in your VS Code profile or workspace. This means they don't follow you across machines.

By redirecting all four customization locations to **OneDrive**, every machine you sign into gets the same Copilot setup automatically. Write an agent once, use it everywhere.

## Folder Structure

```
~/OneDrive/CopilotAtelier/
├── Agents/          # Custom agents (.agent.md files)
├── Instructions/    # Custom instructions (.instructions.md files)
├── Skills/          # Agent skills (folders with SKILL.md)
├── Prompts/         # Prompt files / slash commands (.prompt.md files)
├── Keybindings/     # keybindings.json merged into your user profile
├── Setup-CopilotSettings.ps1   # Setup script
└── README.md        # This file
```

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
| **outlook-calendar-export** | Export Outlook calendar entries to Markdown files via COM automation in PowerShell. Covers recurring appointments (`IncludeRecurrences`), date range filtering, Markdown generation with metadata tables, index file creation, and UTF-8 encoding best practices. |
| **outlook-email-export** | Export and extract emails from Outlook via COM automation in PowerShell. Covers searching by sender, recipient, CC, subject, or date range across multiple folders. |
| **pester-patterns** | Common Pester 5 test patterns and recipes for PowerShell module testing. Covers mocking file systems, REST APIs, DSC resources, databases, and credentials. |
| **sampler-build-debug** | Debug and troubleshoot Sampler-based PowerShell module builds and Pester 5 test failures. Covers running builds safely, reading Pester results, and diagnosing common failures. |
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

## VS Code Settings Applied

The setup script configures the following in `settings.json`:

### File Locations

```jsonc
"chat.agentFilesLocations":        { "~/CopilotAtelier/Agents": true }
"chat.instructionsFilesLocations": { "~/CopilotAtelier/Instructions": true }
"chat.agentSkillsLocations":       { "~/CopilotAtelier/Skills": true }
"chat.promptFilesLocations":       { "~/CopilotAtelier/Prompts": true }
```

### Feature Flags

| Setting | Value | What It Does |
|---|---|---|
| `chat.includeApplyingInstructions` | `true` | Auto-apply `.instructions.md` files when their `applyTo` glob matches files being worked on |
| `chat.includeReferencedInstructions` | `true` | Follow Markdown links in instruction files and load referenced content into context |
| `github.copilot.chat.agent.thinkingTool` | `true` | Enable the thinking tool so agents can reason through complex problems before acting |
| `github.copilot.chat.search.semanticTextResults` | `true` | Improve search results in agent mode with semantic matching |

### AI Model Preferences

| Setting | Value | What It Does |
|---|---|---|
| `gitlens.ai.vscode.model` | `copilot:claude-opus-4.6-fast` | Use Claude Opus 4.6 (fast) for GitLens AI features (commit messages, explanations) |
| `github.copilot.advanced.model` | `claude-opus-4.6-fast` | Use Claude Opus 4.6 (fast) for inline autocompletions (experimental, may be overridden server-side) |

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

1. Sign into OneDrive so `~/OneDrive/CopilotAtelier/` syncs down
2. Open PowerShell and run:

```powershell
& "$env:USERPROFILE\OneDrive\CopilotAtelier\Setup-CopilotSettings.ps1"
```

3. Restart VS Code

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

## Featured In

- [**The Agentic Operating Model**](https://github.com/raandree/AgenticOperatingModel) — a 1h/2h/4h presentation and workshop on versioned, agent-assisted knowledge work. CopilotAtelier is used as the reference exemplar of a mature personal atelier (Module 3 — *Your Atelier — Customization as Code*; Module 8 — *A Mature Personal Atelier*) and as the cross-machine instruction-sync pattern. The workshop also publishes complementary, project-level material that pairs well with this repo:
  - [Agentic Knowledge-Work Patterns](https://github.com/raandree/AgenticOperatingModel/blob/main/content/materials/agentic-knowledge-work-patterns.md) — ten reusable patterns for applying the operating model beyond code.
  - [Memory Bank Template](https://github.com/raandree/AgenticOperatingModel/tree/main/content/materials/memory-bank-template) — a tool-neutral starter set for per-project memory banks.

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.
