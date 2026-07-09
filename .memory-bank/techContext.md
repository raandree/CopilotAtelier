# Tech context

## Technology stack

| Layer | Technology | Purpose |
|---|---|---|
| IDE | VS Code | Primary development environment |
| AI assistant | GitHub Copilot (Claude Opus 4.8) | Code generation, review, documentation |
| Sync | OneDrive | Cross-machine file synchronization |
| Setup script | PowerShell 5.1+ | Automated VS Code configuration |
| Version control | Git | Repository management |

## VS Code settings configured

### File location settings

The setup script does **not** write `chat.agentFilesLocations`, `chat.instructionsFilesLocations`, `chat.agentSkillsLocations`, or `chat.promptFilesLocations`. Instead, after copying customization files to the canonical target (`~/OneDrive/CopilotAtelier/` when OneDrive is installed, otherwise `~/CopilotAtelier/`), it creates NTFS junctions under `%USERPROFILE%\.copilot\` so both the VS Code Copilot chat extension and the GitHub Copilot CLI discover the same tree via the well-known path:

```text
%USERPROFILE%\.copilot\agents       -> <target>\Agents
%USERPROFILE%\.copilot\instructions -> <target>\Instructions
%USERPROFILE%\.copilot\skills       -> <target>\Skills
%USERPROFILE%\.copilot\prompts      -> <target>\Prompts
```

Existing junctions are recreated on every run. Pre-existing real folders at the link paths are removed silently when empty; when non-empty the script prompts the user, and on consent merges their contents into the target (without overwriting newer files there) before removing the folder and creating the junction.

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
| `gitlens.ai.vscode.model` | `copilot:claude-opus-4.8` |
| `github.copilot.advanced.model` | `claude-opus-4.8` |

Opus 4.8 is the mid-2026 current Copilot release, superseding Opus 4.7 (which replaced Opus 4.5 / 4.6; Opus 4.6 Fast was retired 2026-04-10). As of 2026-07-02 all 11 agents and both global-default settings declare Opus 4.8.

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
| Career Coach | `career-coach` | Bilingual (EN/DE) career coaching, CV/Lebenslauf writing, job search, application tracking, interview prep, salary negotiation. Five-phase workflow (ASSESS → POSITION → CRAFT → APPLY → ADVANCE); persistent memory bank; ATS-aware; ethics-first. Hands off to `legal-researcher` (Arbeitsrecht) and `technical-writer` (LinkedIn articles) |
| Research Analyst | `research-analyst` | Technical and scientific web research and investigation. Five-phase workflow (SCOPE → SOURCE → VERIFY → SYNTHESIZE → DELIVER); falsifiable research questions; strict source hierarchy (standards / primary lit / code & docs / regulatory / secondary / vendor / OSINT); triangulation rule (≥ 3 independent primary sources for `Established` Tier-1 claims); lateral reading; mandatory archive snapshots; anti-LLM-citation-laundering guardrail; confidence-graded findings (Established / Probable / Contested / Weak / Speculation); persistent investigation dossiers with annotated bibliography and replication-grade query log; hands off to `technical-writer`, `legal-researcher`, `tax-researcher` |
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
| `agent-evals` | `Skills/agent-evals/` | Build evals for skills/prompts/agents: capability vs regression sets, deterministic/LLM-as-judge/human graders, pass@k vs pass^k, `scripts/run-evals.ps1` harness |
| `agent-security-review` | `Skills/agent-security-review/` | On-demand agentic-security checklist: lethal-trifecta test, OWASP Top 10 for LLM Applications quick checks, containment-first checklist, MCP/tool-permission review. Loaded by `security-reviewer` + `software-engineer` |
| `automatedlab-deployment` | `Skills/automatedlab-deployment/` | Build and deploy Hyper-V lab environments using AutomatedLab |
| `authenticated-web-extraction` | `Skills/authenticated-web-extraction/` | Persistent Playwright + Microsoft Edge profile at `%LOCALAPPDATA%\CareerAuthBrowser\` for authenticated extraction (LinkedIn, GitHub, Sessionize, M365, X, Meetup). Bundled `bootstrap/` (`package.json`, `open.mjs`, `extract.mjs`, `check-logins`, `dump-cookies`); documents per-site auth cookie names, session-cookie re-injection workaround, OAuth tracking-prevention flags, and the profile-lock orphan-`msedge.exe` failure mode |
| `citation-integrity` | `Skills/citation-integrity/` | Verify every external claim, quote, statistic, and reference against a fetched source. Six-class failure taxonomy (F1 fabricated → F6 anchorless), three-layer anchor (locator + ≤25-word quote + stable ID), `VERIFIED` / `MISMATCH` / `NOT_FOUND` verdicts (no gray zone), cross-index triangulation for contamination signals |
| `code-review-and-quality` | `Skills/code-review-and-quality/` | Reusable five-axis code review (design, correctness, complexity, tests, clarity) for PowerShell/DSC; severity labels (Blocker/Major/Minor/Nit), change sizing, author self-review against the Definition of Done |
| `create-outlook-draft` | `Skills/create-outlook-draft/` | Create Outlook email drafts from Markdown via COM automation |
| `devils-advocate-review` | `Skills/devils-advocate-review/` | Argue against a proposal, design, claim, or draft from a hostile-but-fair position with anti-sycophancy safeguards. 1–5 rebuttal rubric (concession only at ≥ 4, no consecutive concessions, attack-intensity preservation), named deflection classes, frame-lock self-check, closing report with sycophancy log |
| `datum-configuration` | `Skills/datum-configuration/` | Reference for Datum hierarchical DSC configuration data module |
| `debugging-and-error-recovery` | `Skills/debugging-and-error-recovery/` | General debugging loop: reproduce → localize → reduce → fix root cause → guard with a regression test; stop-the-line, do-not-swallow-errors, flaky-test discipline; PowerShell tactics |
| `docx-to-markdown` | `Skills/docx-to-markdown/` | Convert DOCX to Markdown via .NET-native ZIP/XML parsing (no pandoc/Word) |
| `dsc-troubleshooting` | `Skills/dsc-troubleshooting/` | Debug and troubleshoot PowerShell DSC resource failures on target nodes |
| `german-legal-research` | `Skills/german-legal-research/` | Legal research for German tenancy/rental law and civil law |
| `grammar-check` | `Skills/grammar-check/` | Identify grammar, logical, and flow errors in text |
| `marp-slide-overflow` | `Skills/marp-slide-overflow/` | Detect and fix silent content overflow in Marp slide decks (Puppeteer detector, `dense`/`compact` density, `fillRatio` decision table, side-by-side review, Recipe 0 PNG visual verification, `mermaid-cli` SVG pre-render with content-hash cache and image-height CSS cap) |
| `mecm-dsc-deployment` | `Skills/mecm-dsc-deployment/` | Deploy and troubleshoot MECM/SCCM via DSC (ConfigMgrCBDsc, Datum) |
| `microsoft-todo-tasks` | `Skills/microsoft-todo-tasks/` | Create and manage Microsoft To Do tasks via Graph REST + OAuth2 device flow |
| `outlook-calendar-export` | `Skills/outlook-calendar-export/` | Export Outlook calendar entries to Markdown via COM automation |
| `outlook-email-export` | `Skills/outlook-email-export/` | Export and extract emails from Outlook via COM automation |
| `pandoc-docx-export` | `Skills/pandoc-docx-export/` | Export Markdown to DOCX via pandoc (Lua filters, landscape tables) |
| `pdf-to-markdown` | `Skills/pdf-to-markdown/` | Convert PDF to Markdown via .NET-native PDF parsing (no external tools) |
| `pester-patterns` | `Skills/pester-patterns/` | Ready-to-use Pester 5 test patterns and recipes |
| `pswritehtml-reporting` | `Skills/pswritehtml-reporting/` | Generate interactive HTML reports, dashboards, tables, charts, and network diagrams from PowerShell objects via PSWriteHTML (MIT, dependency-free, cross-platform); `New-HTML` container, DataTables, ApexCharts, Section/Panel/Tab layout, `New-HTMLDiagram`, `Out-HtmlView`, and HTML email bodies (sending delegated to `send-outlook-email`) |
| `sampler-build-debug` | `Skills/sampler-build-debug/` | Debug Sampler builds and Pester 5 test failures |
| `sampler-framework` | `Skills/sampler-framework/` | Comprehensive Sampler PowerShell module build framework reference |
| `sampler-migration` | `Skills/sampler-migration/` | Migrate legacy PowerShell modules to Sampler framework |
| `send-outlook-email` | `Skills/send-outlook-email/` | Send emails via the Outlook COM API from PowerShell |
| `social-signal-sweep` | `Skills/social-signal-sweep/` | Recency-bounded (default 30-day) multi-platform sweep of public discussion (GitHub / Hacker News / Reddit / Stack Overflow + browser tier for YouTube/X) returning a tier-8 lead sheet — leads only, never citable. No engine, API keys, or cookies; uses `web/fetch`, the GitHub tools, and `openSimpleBrowser`. Feeds the `research-analyst` SOURCE phase |
| `test-driven-development` | `Skills/test-driven-development/` | Test-first workflow: red-green-refactor, failing Pester test before code, test pyramid, DAMP-over-DRY, bug-fix-as-test-first, characterization tests for legacy code |
| `whisper-pyannote-transcription` | `Skills/whisper-pyannote-transcription/` | GPU-accelerated audio/video transcription with speaker labels: faster-whisper large-v3 (CUDA float16) + pyannote 3.1 diarization, merged into speaker-labeled SRT/JSON/text. Includes `transcribe.py` and `diarize.py`; documents Windows `torchcodec` bypass and HF gated-model setup |
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
| Peer Review (Multi-Perspective Panel) | `Prompts/peer-review.prompt.md` | any (EIC + 3 reviewers + Devil's Advocate; uses `devils-advocate-review` and `citation-integrity` skills) |
| Session Handoff | `Prompts/session-handoff.prompt.md` | any (`agent: agent`; writes `.memory-bank/session/handoff-<UTC>.md`) |

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
