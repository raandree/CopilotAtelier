# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This project does not currently use versioned releases; tagged releases will follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html) once publishing begins.

## [Unreleased]

### Added

- **Keybindings merge** — [`Keybindings/keybindings.json`](Keybindings/keybindings.json) is now merged idempotently by `Setup-CopilotSettings.ps1` into `%APPDATA%\Code\User\keybindings.json`. Match key is `(key, command, when)`; user-added bindings are preserved; a timestamped backup is created on every run. Bindings: `Ctrl+K X` restart PowerShell session, `Ctrl+K N` pop terminal to new window, `Ctrl+K K` pop chat to new window, and a chat-submit swap so `Ctrl+Enter` sends and plain `Enter` inserts a newline in the chat input.
- Top-level `CHANGELOG.md` (this file).
- Tax Researcher (DE) agent section in `Agents/README.md`.
- Memory-bank documentation pass: refreshed inventories (20 skills, 13 instructions, 9 agents, 8 prompts) and expanded the `systemPatterns.md` applyTo list.

## [1.0.0] — 2026-04-22

First public-ready state of the CopilotAtelier.

### Added

#### Agents (9)

- **Software Engineer** — multi-phase SDLC workflow (Analyze → Design → Implement → Validate → Reflect → Handoff) with quality gates and handoffs to Security & QA and Technical Writer.
- **Security & Quality Assurance** — five-layer assessment framework (SAST, Dependency & Supply Chain, Secrets, Configuration, Threat Intel), CVSS-based risk scoring, and PASS/FAIL/CONDITIONAL production-readiness decisions.
- **Technical Writer & Documentation** — six-phase writing workflow with journalistic integrity, CRAAP source evaluation, and multiple article templates.
- **Technical Troubleshooter** — six-phase Google SRE–inspired diagnostic workflow (Report → Triage → Examine → Diagnose → Test → Cure), with handoffs to Software Engineer and Technical Writer.
- **Legal Researcher (DE)** — German tenancy law (Mietrecht) and civil law research and drafting, persistent case memory bank, mandatory RDG disclaimer.
- **Tax Researcher (DE)** — German tax research & drafting (EStG, AO, V+V, AfA, objection proceedings, deadline calculation, ELSTER); persistent case memory bank; mandatory StBerG/RDG disclaimer.
- **QC Inspector** — quality control for Oil & Gas / Energy / Industrial; EU regulatory compliance (PED, ATEX, CBAM, CSDDD, CRA); inspection-document generation (ITP, NCR, audit reports).
- **Training Content Writer** — modular GitHub-hosted training content built on Bloom's revised taxonomy and constructive alignment.
- **DevOps Training Writer** — DevOps/SRE/Platform Engineering training; inherits from Training Content Writer.

#### Instructions (13)

Auto-applied coding standards for PowerShell, Markdown, YAML, C#, Changelog, Versioning, Sampler, Pester, Git, JSON, and Azure Pipelines. Plus two meta-rule files: `copilot-authoring.instructions.md` (governs how this repo's own instructions, prompts, skills, and agents are authored) and `powershell-execution-safety.instructions.md` (enforces detached execution and Pester-in-subprocess to avoid VS Code hangs).

#### Skills (20)

- Build & automation: `sampler-framework`, `sampler-build-debug`, `sampler-migration`, `pester-patterns`.
- DSC / lab infrastructure: `automatedlab-deployment`, `datum-configuration`, `dsc-troubleshooting`, `mecm-dsc-deployment`, `winrm-troubleshooting`.
- Document conversion: `docx-to-markdown`, `xlsx-to-markdown`, `pdf-to-markdown`, `pandoc-docx-export`.
- Outlook / Microsoft 365 automation: `create-outlook-draft`, `outlook-calendar-export`, `outlook-email-export`, `send-outlook-email`, `microsoft-todo-tasks`.
- Writing / legal: `grammar-check`, `german-legal-research`.

#### Prompts (8)

- `code-review` (agent: `security-reviewer`) — PowerShell security review producing SARIF + Markdown + CVSS output.
- `lab-deploy`, `module-scaffold`, `pr-description`, `refactor` (agent: `software-engineer`) — day-to-day development workflows.
- `export-emails`, `sync-project-emails`, `deadline-action-handoff` (agent: `legal-researcher`) — legal-case email and deadline workflows.

#### Reference

- `Reference/copilot-cli-model-routing.md` — 4-tier Copilot CLI model routing (Executors, Implementers, Tech Leads, Architects) with delegation policy. Reference-only; not auto-attached.

#### Setup

- `Setup-CopilotSettings.ps1` — one-command VS Code configuration. Derives folder name from the repo clone, registers `~/<repoName>/*` locations always, plus `~/OneDrive/<repoName>/*` when OneDrive is detected. Idempotent (merges settings instead of replacing), JSONC-tolerant (strips comments before parsing), and creates a timestamped backup on every run. Creates the VS Code user directory if missing.
- Feature flags configured: `chat.includeApplyingInstructions`, `chat.includeReferencedInstructions`, `github.copilot.chat.agent.thinkingTool`, `github.copilot.chat.search.semanticTextResults`, `github.copilot.chat.agent.maxRequests=500`.
- Default model set to Claude Opus 4.6 for GitLens AI and Copilot inline completions.

[Unreleased]: https://github.com/raandree/CopilotAtelier/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/raandree/CopilotAtelier/releases/tag/v1.0.0