# Active context

## Current work focus

The project is release-ready. As of April 23, 2026 the repository contains 9 agents, 13 instruction files, 1 reference doc (Copilot CLI model routing), 20 skills, and 8 prompts. Current focus: release preparation (documentation refresh and CHANGELOG).

## Recent changes (April 23, 2026)

### Keybindings merge

- New `Keybindings/keybindings.json` in the repo holds shared VS Code bindings. `Setup-CopilotSettings.ps1` now merges them idempotently into `%APPDATA%\Code\User\keybindings.json` using `(key, command, when)` as the dedup key; user-added bindings are preserved; a timestamped backup is created on every run.
- Bindings shipped: `Ctrl+K X` restart PowerShell session; `Ctrl+K N` pop terminal into a new window; `Ctrl+K K` pop chat into a new window; `Ctrl+Enter` submits chat; plain `Enter` disabled for chat submission so it inserts a newline instead.

### Release-prep documentation pass

- Refreshed `techContext.md` inventories: 20 skills (was 15), 13 instructions (added `copilot-authoring`, `powershell-execution-safety`), 8 prompts with agent bindings, 9 agents (added `tax-researcher`).
- Expanded `systemPatterns.md` applyTo list and the troubleshooter → writer handoff edge.
- Added `Agents/README.md` section for the Tax Researcher (DE) agent.
- Added top-level `CHANGELOG.md` (Keep a Changelog format) covering the project from first release.

## Recent changes (April 22, 2026)

### New agent: Tax Researcher (DE)

- `Agents/tax-researcher.agent.md` — German tax research & drafting (EStG, AO, V+V, AfA, objection proceedings, estimation assessments, deadline calculation, ELSTER). Persistent case memory bank (`.memory-bank/case-est-*.md`). Mandatory StBerG/RDG disclaimer on every substantive output.

### Agent rename

- `Legal Researcher (DE)` → `legal-researcher` (kebab-case, consistent with handoff naming). Propagated to prompts (`deadline-action-handoff`, `export-emails`, `sync-project-emails`), `Agents/README.md`, and memory bank.

### Deadline-action-handoff prompt rewrite

- Added execution contract, compaction resilience, phase-by-phase instructions, a summary-email phase, clarified draft-handling rules, and a disk-persisted handoff payload that survives across chats.

### Setup script hardening

- Creates the VS Code user directory if missing.
- Improves backup handling for `settings.json`.

### Prompt frontmatter migration

- Renamed deprecated `mode:` attribute to `agent:` in all 8 prompt files (VS Code deprecation).
- Updated `copilot-authoring.instructions.md` to document the new `agent` key.
- Bound each prompt to a specific custom agent instead of the generic `agent` value:

| Prompt | Agent |
|---|---|
| `code-review` | `security-reviewer` |
| `deadline-action-handoff` | `legal-researcher` |
| `export-emails` | `legal-researcher` |
| `sync-project-emails` | `legal-researcher` |
| `lab-deploy` | `software-engineer` |
| `module-scaffold` | `software-engineer` |
| `pr-description` | `software-engineer` |
| `refactor` | `software-engineer` |

## Previous changes (April 21, 2026)

### New instructions (1)

| File | Date | Description |
|---|---|---|
| `copilot-authoring.instructions.md` | April 21 | Meta-instruction governing how Instructions, Prompts, Skills, and Agents in this repo are authored. Two-tier scope: strict for Instructions/Prompts, relaxed for Agents/Skills. Purposeful-emphasis rule; bans maintenance footers. Expanded later the same day (commit `78ddfdd`) with additional authoring guidance. |

### Authoring-rule rollout (follow-up to copilot-authoring)

| Commit | Scope | Description |
|---|---|---|
| `78ddfdd` | Instructions + Prompts + 1 Skill | Refactor pass aligning `changelog.instructions.md`, `versioning.instructions.md`, all 4 prompts (`CodeReview`, `ModuleScaffold`, `PRDescription`, `Refactor`), and `german-legal-research` SKILL with the new authoring rules. |
| `041a9a6` | 10 instruction files | Removed boilerplate "When working with..." introductory sentences from `azurepipelines`, `changelog`, `csharp`, `git`, `json`, `markdown`, `pester`, `powershell`, `versioning`, `yaml` instructions for clarity and conciseness. |

### Agent handoff wiring (1)

| Commit | Agent | Change |
|---|---|---|
| `3b9044d` | Technical Troubleshooter | Added `technical-writer` to `agents:` list and a new "Publish Runbook" handoff that turns a troubleshooting analysis into a polished runbook / KB article via the Technical Writer agent. No new agent file — rewires the existing `technical-writer` agent. Commit message ("Add technical-writer agent") is misleading. |

## Previous changes (March 31, 2026)

### Skill updates (2)

| Skill | Date | Change |
|---|---|---|
| `dsc-troubleshooting` | March 31 | +60 lines: WinMgmt restart hang via Invoke-LabCommand (reboot from host), phantom Busy LCM state after force reboot, new section 4.3.1 — ApplyAndAutoCorrect consistency timer interfering with long-running SetScript |
| `mecm-dsc-deployment` | March 31 | +114 lines: DSC auto-correct interference during SCCM installs (SetupWpf detection), file copy double-hop on Server 2025 (robocopy UNC hang), stale CM_S00 database blocking installation |

## Previous changes (March 24–29, 2026)

### New skills (1)

| Skill | Date | Description |
|---|---|---|
| `pdf-to-markdown` | March 29 | Convert PDF files to Markdown using .NET-native PDF parsing in PowerShell — no external tools required. Handles zlib/deflate streams, hex-encoded text operators, Y-coordinate line reconstruction, ISO-8859-1 encoding for German PDFs |

## Earlier changes (March 19–23, 2026)

### New skills (1)

| Skill | Date | Description |
|---|---|---|
| `outlook-calendar-export` | March 23 | Export Outlook calendar entries to Markdown via COM automation: recurring appointments, date range filtering, UTF-8 no-BOM encoding, index generation |

## Earlier changes (March 12–18, 2026)

### New skills (3)

| Skill | Date | Description |
|---|---|---|
| `mecm-dsc-deployment` | March 13 | Deploy and troubleshoot MECM/SCCM via DSC using ConfigMgrCBDsc, CommonTasks, and UpdateServicesDsc in DscWorkshop/Datum environments |
| `winrm-troubleshooting` | March 14 | Debug WinRM connectivity failures: service state recovery, listener config, HTTP.sys conflicts, auth failures, PowerShell Direct fallback |
| `pandoc-docx-export` | March 16 | Export Markdown to DOCX via pandoc with Lua filters for landscape tables, custom column widths, emoji, Mermaid diagrams |

### Skill updates (6)

| Skill | Date | Change |
|---|---|---|
| `datum-configuration` | March 12 | General updates |
| `dsc-troubleshooting` | March 12, 16 | Updated; enhanced PsDscRunAsCredential diagnostics and SCCM 2509 compatibility |
| `mecm-dsc-deployment` | March 16–17 | Enhanced remote runspace behavior, SCCM 2509 post-install troubleshooting, PsDscRunAsCredential handling for ConfigMgrCBDsc |
| `automatedlab-deployment` | March 16 | Added RSAT installation workaround for client OSes using scheduled tasks |
| `pester-patterns` | March 13 | Updated alongside MECM skill |
| `pandoc-docx-export` | March 18 | Content-aware column optimization for table formatting |

### Instruction updates (3)

| File | Date | Change |
|---|---|---|
| `pester.instructions.md` | March 13 | Emphasize using `Start-Process` for detached Pester execution |
| `git.instructions.md` | March 14 | Added AI-assisted commit strategy with attribution and branch naming conventions |
| `markdown.instructions.md` | March 16 | Added guidelines against using ASCII box art for structured data |

### Agent updates

- March 13: Added timestamped response requirement (`[YYYY-MM-DD HH:mm UTC]`) to all 8 agents
- March 14: Software Engineer Agent updated with AI-assisted commit strategy

### README updated

- Added 3 new skills to the Available Skills table (mecm-dsc-deployment, pandoc-docx-export, winrm-troubleshooting), bringing the total from 12 to 15.

## Previously undocumented changes (March 4–8, 2026)

The following were committed before the memory bank was created but were never captured:

### New agents (5)

| Agent | Date | Description |
|---|---|---|
| `legal-researcher.agent.md` | March 4 | German legal research and statement drafting (Mietrecht, BGB) |
| `Technical Troubleshooter Agent.agent.md` | March 5 | Systematic problem diagnosis using hypothetico-deductive method, Google SRE-inspired 6-phase workflow |
| `QC Inspector Agent.agent.md` | March 8 | Quality control inspection for Oil & Gas, Energy, and Industrial sectors |
| `Training Content Writer.agent.md` | March 8 | Generic training and workshop content creation with Bloom's taxonomy |
| `DevOps Training Writer.agent.md` | March 8 | DevOps-specialized training (inherits from Training Content Writer) |

### New instruction

| File | Date | Description |
|---|---|---|
| `Reference/copilot-cli-model-routing.md` | March 8 | Model selection rules for Copilot CLI — 4-tier routing (Executors, Implementers, Tech Leads, Architects) with delegation policy. Moved from `Instructions/` to `Reference/` on April 21, 2026 and renamed (dropped `.instructions` suffix) to stop it pretending to be a VS Code auto-attach instruction. |

## Next steps

- Consider adding more skills (e.g., Docker, CI/CD patterns, Azure DevOps)
- Consider adding language instructions for Python, JavaScript, TypeScript
- Consider creating a GitHub Actions or Azure Pipelines CI to lint the instruction files
- Monitor VS Code updates for new Copilot extensibility features
- Memory Bank maintenance is ongoing

## Active decisions and considerations

- **Model choice**: Claude Opus 4.7 is the current default for agents and the model id configured in `Setup-CopilotSettings.ps1`. Opus 4.7 is GA in Copilot since 2026-04-16; the prior default (`claude-opus-4.6-fast`) was retired 2026-04-10. The Copilot CLI model-routing reference (`Reference/copilot-cli-model-routing.md`) still describes the pre-4.7 lineup and is flagged for a fuller refresh post-1.1.0.
- **OneDrive path**: Optional. When present, `~/OneDrive/CopilotAtelier/` is registered in addition to the mandatory `~/CopilotAtelier/` local mirror. The folder name is derived from the repo clone name, so renaming the clone renames the layout automatically.
- **No CI/CD**: This is a configuration repository. Markdown linting could be added.

## Important patterns and preferences

- **Instruction files are comprehensive, not minimal** — Each covers the full breadth of best practices for its language/domain.
- **Agents use zero-confirmation policies** — All agents are designed to execute autonomously without asking for permission.
- **Skills use trigger phrases** — `USE FOR` and `DO NOT USE FOR` in descriptions help Copilot decide when to load them.
- **Setup script is non-destructive** — It merges settings rather than replacing them, and creates backups.
- **Agents organized into core SDLC pipeline + supplementary** — 4 core agents (Software Engineer, Security & QA, Technical Writer, Technical Troubleshooter) + 4 supplementary domain-specific agents.