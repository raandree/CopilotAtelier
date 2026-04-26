# Tech context

## Technology stack

| Layer | Technology | Purpose |
|---|---|---|
| IDE | VS Code | Primary development environment |
| AI assistant | GitHub Copilot (Claude Opus 4.7) | Code generation, review, documentation |
| Sync | OneDrive | Cross-machine file synchronization |
| Setup script | PowerShell 5.1+ | Automated VS Code configuration |
| Version control | Git | Repository management |

## VS Code settings configured

### File location settings

```jsonc
// Local copies, always registered
"chat.agentFilesLocations":        { "~/CopilotAtelier/Agents": true }
"chat.instructionsFilesLocations": { "~/CopilotAtelier/Instructions": true }
"chat.agentSkillsLocations":       { "~/CopilotAtelier/Skills": true }
"chat.promptFilesLocations":       { "~/CopilotAtelier/Prompts": true }

// OneDrive mirror, registered additionally when OneDrive is detected
"chat.agentFilesLocations":        { "~/OneDrive/CopilotAtelier/Agents": true }
"chat.instructionsFilesLocations": { "~/OneDrive/CopilotAtelier/Instructions": true }
"chat.agentSkillsLocations":       { "~/OneDrive/CopilotAtelier/Skills": true }
"chat.promptFilesLocations":       { "~/OneDrive/CopilotAtelier/Prompts": true }
```

### Feature flags

| Setting | Value | Purpose |
|---|---|---|
| `chat.includeApplyingInstructions` | `true` | Auto-apply instruction files by glob match |
| `chat.includeReferencedInstructions` | `true` | Follow Markdown links in instruction files |
| `github.copilot.chat.agent.thinkingTool` | `true` | Enable agent reasoning tool |
| `github.copilot.chat.search.semanticTextResults` | `true` | Semantic search in agent mode |
| `github.copilot.chat.agent.maxRequests` | `500` | Maximum tool-call requests per agent turn (default: 5) |

### Keybindings merged

The setup script also merges `Keybindings/keybindings.json` into `%APPDATA%\Code\User\keybindings.json`. Dedup key: `(key, command, when)`; user-added bindings preserved; timestamped backup on every run.

| Key | Command | Purpose |
|---|---|---|
| `Ctrl+K X` | `PowerShell.RestartSession` | Restart the PowerShell integrated console |
| `Ctrl+K N` | `workbench.action.terminal.moveIntoNewWindow` | Pop the active terminal into a new window |
| `Ctrl+K K` | `workbench.action.chat.openInNewWindow` | Pop the Chat view into a new window |
| `Ctrl+Enter` | `workbench.action.chat.submit` | Submit chat prompt |
| `Enter` | `-workbench.action.chat.submit` | Disabled so plain `Enter` inserts a newline in the chat input |

### Model preferences

| Setting | Value |
|---|---|
| `gitlens.ai.vscode.model` | `copilot:claude-opus-4.7` |
| `github.copilot.advanced.model` | `claude-opus-4.7` |

Opus 4.7 is GA in Copilot since 2026-04-16 and is the announced replacement for Opus 4.5 / 4.6. Opus 4.6 Fast (the previous default) was retired on 2026-04-10.

## Agents inventory

### Core SDLC Pipeline Agents

| Agent name | ID | Role | Tools count | Handoffs |
|---|---|---|---|---|
| Software Engineer | `software-engineer` | Development & implementation | 21 | security-reviewer, technical-writer |
| Security & QA | `security-reviewer` | Security audits & production readiness | 17 | software-engineer |
| Technical Writer | `technical-writer` | Articles & documentation | 13 | security-reviewer |
| Technical Troubleshooter | `technical-troubleshooter` | Problem diagnosis & resolution | — | software-engineer, technical-writer |

### Supplementary Domain-Specific Agents

| Agent name | ID | Role |
|---|---|---|
| legal-researcher | `legal-researcher` | German legal research & statement drafting |
| tax-researcher | `tax-researcher` | German tax research, assessment-notice review, tax document drafting |
| QC Inspector | `qc-inspector` | Quality control inspection for Oil & Gas / Energy / Industrial |
| Training Content Writer | `training-writer` | Generic training & workshop content creation |
| DevOps Training Writer | `devops-training-writer` | DevOps-specialized training (inherits from Training Content Writer) |

## Instructions inventory

| File | Applies to | Approximate size |
|---|---|---|
| `powershell.instructions.md` | `*.ps1, *.psm1, *.psd1` | ~1,233 lines |
| `markdown.instructions.md` | `*.md` | ~1,426 lines |
| `yaml.instructions.md` | `*.yml, *.yaml` | ~974 lines |
| `csharp.instructions.md` | `*.cs, *.csx` | ~1,260 lines |
| `changelog.instructions.md` | `CHANGELOG.md` and variants | ~1,137 lines |
| `versioning.instructions.md` | `GitVersion.yml, *.psd1, CHANGELOG.md` | ~1,228 lines |
| `sampler.instructions.md` | `build.yaml, build.ps1, RequiredModules.psd1, ...` | ~150 lines |
| `copilot-authoring.instructions.md` | `Instructions/*.instructions.md, Prompts/*.prompt.md, Skills/**/SKILL.md, Agents/*.agent.md` | meta-rules for this repo's own content |
| `powershell-execution-safety.instructions.md` | `*.ps1, *.psm1, *.psd1, *.Tests.ps1, build.yaml, build.ps1, ...` | detached execution + Pester-in-subprocess rules |
| `pester.instructions.md` | `*.Tests.ps1, *.tests.ps1` | ~620 lines |
| `git.instructions.md` | `.gitconfig, .gitignore, .gitattributes, COMMIT_EDITMSG` | ~380 lines |
| `json.instructions.md` | `*.json, *.jsonc` | ~350 lines |
| `azurepipelines.instructions.md` | `azure-pipelines.yml, .azuredevops/*.yml` | ~500 lines |
| `Reference/copilot-cli-model-routing.md` | Reference doc (not auto-attached) | Copilot CLI 4-tier model routing |

## Skills inventory

| Skill | Directory | Purpose |
|---|---|---|
| `automatedlab-deployment` | `Skills/automatedlab-deployment/` | Build and deploy Hyper-V lab environments using AutomatedLab |
| `create-outlook-draft` | `Skills/create-outlook-draft/` | Create Outlook email drafts from Markdown via COM automation |
| `datum-configuration` | `Skills/datum-configuration/` | Reference for Datum hierarchical DSC configuration data module |
| `docx-to-markdown` | `Skills/docx-to-markdown/` | Convert DOCX to Markdown via .NET-native ZIP/XML parsing (no pandoc/Word) |
| `dsc-troubleshooting` | `Skills/dsc-troubleshooting/` | Debug and troubleshoot PowerShell DSC resource failures on target nodes |
| `german-legal-research` | `Skills/german-legal-research/` | Legal research for German tenancy/rental law and civil law |
| `grammar-check` | `Skills/grammar-check/` | Identify grammar, logical, and flow errors in text |
| `mecm-dsc-deployment` | `Skills/mecm-dsc-deployment/` | Deploy and troubleshoot MECM/SCCM via DSC (ConfigMgrCBDsc, Datum) |
| `microsoft-todo-tasks` | `Skills/microsoft-todo-tasks/` | Create and manage Microsoft To Do tasks via Graph REST + OAuth2 device flow |
| `outlook-calendar-export` | `Skills/outlook-calendar-export/` | Export Outlook calendar entries to Markdown via COM automation |
| `outlook-email-export` | `Skills/outlook-email-export/` | Export and extract emails from Outlook via COM automation |
| `pandoc-docx-export` | `Skills/pandoc-docx-export/` | Export Markdown to DOCX via pandoc (Lua filters, landscape tables) |
| `pdf-to-markdown` | `Skills/pdf-to-markdown/` | Convert PDF to Markdown via .NET-native PDF parsing (no external tools) |
| `pester-patterns` | `Skills/pester-patterns/` | Ready-to-use Pester 5 test patterns and recipes |
| `sampler-build-debug` | `Skills/sampler-build-debug/` | Debug Sampler builds and Pester 5 test failures |
| `sampler-framework` | `Skills/sampler-framework/` | Comprehensive Sampler PowerShell module build framework reference |
| `sampler-migration` | `Skills/sampler-migration/` | Migrate legacy PowerShell modules to Sampler framework |
| `send-outlook-email` | `Skills/send-outlook-email/` | Send emails via the Outlook COM API from PowerShell |
| `winrm-troubleshooting` | `Skills/winrm-troubleshooting/` | Debug WinRM connectivity failures, auth issues, PowerShell Direct fallback |
| `xlsx-to-markdown` | `Skills/xlsx-to-markdown/` | Convert XLSX to Markdown via .NET-native ZIP/XML parsing (no Excel/ImportExcel) |

## Prompts inventory

| Prompt | File | Agent |
|---|---|---|
| Code Review | `Prompts/code-review.prompt.md` | `security-reviewer` |
| Lab Deploy | `Prompts/lab-deploy.prompt.md` | `software-engineer` |
| Module Scaffold | `Prompts/module-scaffold.prompt.md` | `software-engineer` |
| PR Description | `Prompts/pr-description.prompt.md` | `software-engineer` |
| Refactor | `Prompts/refactor.prompt.md` | `software-engineer` |
| Export Emails | `Prompts/export-emails.prompt.md` | `legal-researcher` |
| Sync Project Emails | `Prompts/sync-project-emails.prompt.md` | `legal-researcher` |
| Deadline Action Handoff | `Prompts/deadline-action-handoff.prompt.md` | `legal-researcher` |

## Development setup

1. Clone or sync the repository so `~/CopilotAtelier/` is available. OneDrive is optional; if signed in, `~/OneDrive/CopilotAtelier/` is also registered.
2. Run `Setup-CopilotSettings.ps1` in PowerShell
3. Restart VS Code
4. Verify via Copilot Chat diagnostics (right-click → Diagnostics)

## Dependencies

- **VS Code** with GitHub Copilot extension
- **OneDrive** signed in and syncing
- **PowerShell 5.1+** for setup script
- **Git** for version control
