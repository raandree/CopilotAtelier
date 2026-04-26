# Progress

## Project status: Release-ready (v1)

The CopilotAtelier project reached functional completeness on February 24, 2026 and has been steadily expanded since. As of April 23, 2026 the repository contains 9 agents, 13 instruction files, 1 reference doc, 20 skills, and 8 prompts, and is ready for public release.

## What works

| Component | Status | Notes |
|---|---|---|
| Setup script | Done | Idempotent, JSONC-tolerant, creates backups |
| Software Engineer Agent | Done | 21 tools, handoffs to security + writer |
| Security & QA Agent | Done | 17 tools, multi-layer assessment framework, CVSS scoring |
| Technical Writer Agent | Done | 13 tools, 6-phase writing workflow, citation standards |
| Technical Troubleshooter Agent | Done | 6-phase SRE-inspired troubleshooting workflow, diagnostic toolbox, postmortem templates |
| Legal Researcher Agent (DE) | Done | German law research: Mietrecht, BGB, 5-phase legal reasoning, case memory bank |
| QC Inspector Agent | Done | Oil & Gas / Energy QC inspection, EU regulatory compliance, ITP/NCR generation |
| Training Content Writer Agent | Done | Bloom's taxonomy, constructive alignment, modular GitHub-hosted training |
| DevOps Training Writer Agent | Done | DevOps-specialized training, inherits from Training Content Writer |
| Tax Researcher Agent (DE) | Done | German tax research & drafting (EStG, AO, objection proceedings, V+V, AfA, deadline calc); case memory bank; mandatory StBerG/RDG disclaimer |
| PowerShell instructions | Done | ~1,233 lines: verbs, functions, error handling, pipelines, formatting |
| Markdown instructions | Done | ~1,426 lines: headings, lists, links, code, tables, best practices |
| YAML instructions | Done | ~974 lines: indentation, scalars, anchors, security, comments |
| C# instructions | Done | ~1,260 lines: naming, formatting, types, modern features, security |
| Changelog instructions | Done | ~1,137 lines: Keep a Changelog + Common Changelog, writing workflow |
| Versioning instructions | Done | ~1,228 lines: SemVer, CalVer, GitVersion, commit conventions |
| Sampler instructions | Done | ~150 lines: enforced rules only (project structure, manifest, build safety, DO/DON'T) |
| Copilot model selection instructions | Done | ~120 lines: 4-tier model routing for Copilot CLI with delegation policy |
| Copilot authoring instructions | Done | Two-tier authoring rules (strict for Instructions/Prompts, relaxed for Agents/Skills); purposeful-emphasis rule; bans maintenance footers |
| Sampler framework skill | Done | ~2,640 lines: comprehensive Sampler reference (build.yaml, deps, CI/CD, DSC/Datum, VSCode, commands) |
| Sampler build-debug skill | Done | Build troubleshooting, Pester 5 mock issues, safe build patterns |
| Sampler migration skill | Done | Legacy-to-Sampler migration checklist, phase-by-phase guide |
| AutomatedLab deployment skill | Done | Hyper-V lab environments, roles, networking, External switch (recommended) + Default Switch (fallback) + NAT switch (`-UseNat`), post-deployment connectivity fix, Chocolatey install pattern, CredSSP documentation, comprehensive cmdlet reference (~1,330 lines) |
| Lab deployment pipeline | Done | Deploy-LabEnvironment.ps1 with External switch, gateway/DNS fix, Chocolatey + software install, LabDeploy prompt (enforces full deploy+wait+validate+report cycle) |
| Send Outlook email skill | Done | Outlook COM API, plain-text and HTML emails, COM lifecycle |
| Code Review prompt | Done | Multi-prompt security review with SARIF + Markdown + CVSS (agent: `security-reviewer`) |
| PR Description prompt | Done | Generate structured PR descriptions from branch diff (agent: `software-engineer`) |
| Module Scaffold prompt | Done | Scaffold new Sampler-based module projects with full directory structure (agent: `software-engineer`) |
| Refactor prompt | Done | Multi-phase refactoring workflow: Analyze → Plan → Implement → Validate (agent: `software-engineer`) |
| Export Emails prompt | Done | Export recent Outlook emails for persons-of-interest (agent: `legal-researcher`) |
| Sync Project Emails prompt | Done | Sync emails, update index/MB, show deadlines (agent: `legal-researcher`) |
| Deadline Action Handoff prompt | Done | Create Outlook drafts + To Do tasks from deadline tables (agent: `legal-researcher`) |
| Lab Deploy prompt | Done | Deploy and validate Hyper-V lab with AutomatedLab (agent: `software-engineer`) |
| Pester instructions | Done | ~620 lines: Pester 5 conventions, mocking, data-driven tests, migration |
| Git instructions | Done | ~380 lines: Conventional Commits, branch naming, .gitignore/.gitattributes |
| JSON instructions | Done | ~350 lines: JSON/JSONC formatting, PowerShell JSON handling, schemas |
| Azure Pipelines instructions | Done | ~500 lines: pipeline structure, triggers, templates, Sampler pattern |
| Pester patterns skill | Done | Ready-to-use test patterns for mocking, DSC, credentials, pipelines |
| Datum configuration skill | Done | ~435 lines: Datum hierarchical DSC configuration data, merge strategies, RSOP, handlers, DscWorkshop, ProjectDagger patterns |
| DSC troubleshooting skill | Done | ~424 lines: LCM diagnostics, event logs, resource debugging, exit codes, patching, remote troubleshooting via AutomatedLab, auto-correct timer interference, phantom Busy state |
| MECM DSC deployment skill | Done | MECM/SCCM via DSC: ConfigMgrCBDsc, ADK/WinPE, SCCM 2509, UpdateServicesDsc, Datum merge, cross-domain SQL, AL patterns, auto-correct interference, file copy double-hop Server 2025, stale CM database |
| WinRM troubleshooting skill | Done | WinRM service recovery, listener config, HTTP.sys conflicts, auth failures, PowerShell Direct fallback |
| Pandoc DOCX export skill | Done | Markdown to DOCX via pandoc: Lua filters, landscape tables, column widths, emoji, Mermaid diagrams |
| Outlook calendar export skill | Done | Export Outlook calendar to Markdown via COM automation with recurring appointment support |
| Outlook email export skill | Done | Export emails from Outlook via COM automation with DASL filters |
| PDF to Markdown skill | Done | .NET-native PDF parsing: zlib/deflate decompression, hex text decoding, Y-coordinate line reconstruction, ISO-8859-1 encoding |
| Grammar check skill | Done | Text proofing for grammar, logic, and flow errors |
| German legal research skill | Done | Legal research for German tenancy/rental law (Mietrecht) and civil law |
| README | Done | Comprehensive setup guide with troubleshooting and skills inventory table |
| Agents README | Done | Pipeline documentation with severity matrix and workflow diagrams |

## What's left to build

| Item | Priority | Notes |
|---|---|---|
| Additional skills | Low | Could add Docker, Azure DevOps, CI/CD patterns |
| Additional prompts | Low | Could add PR review, incident response templates |
| Markdown linting CI | Low | Optional: lint instruction files for consistency |
| Memory Bank maintenance | Ongoing | Update as project evolves |
| Model updates | As needed | Update agent model references when newer models release |
| Additional language instructions | Low | Could add Python, JavaScript, TypeScript, Dockerfile, Bicep |

## Known issues

- **JSONC comments lost**: The setup script strips comments when it rewrites `settings.json`. This is a known trade-off.
- **OneDrive path assumption**: The script assumes `~/OneDrive/` is the OneDrive root. Custom OneDrive paths are not auto-detected.
- **Agent README links**: The Agents README was updated to use correct relative paths and current terminology.
- **(Resolved)** **StrictMode hashtable access** — `Deploy-LabEnvironment.ps1` threw on optional keys. Fixed Feb 26 by switching to index-notation.
- **(Resolved)** **Hardcoded LabSources path** — Skill and prompt had `C:\LabSources`. Fixed Feb 26 with `Get-LabSourcesLocation`.
- **(Resolved)** **Default Switch DHCP unreliable** — VMs got APIPA addresses (169.254.x.x) causing internet-dependent installs to fail. Fixed Feb 27 by switching to External switch (physical NIC) as the recommended pattern. Default Switch retained as documented fallback with full NAT workaround.
- **(Resolved)** **AL Routing role incomplete** — Does not set gateway/DNS on internal VMs. Fixed Feb 27 with mandatory post-deployment gateway/DNS fix section.
- **(Resolved)** **Chocolatey PATH not refreshed** — AL remoting sessions cache old PATH; `choco` not found. Fixed Feb 27 by adding `$env:Path` refresh from Machine/User env vars.

## Evolution of project decisions

1. **Initial creation** → Basic file structure with agents and instructions.
2. **Setup script enhanced** → Added idempotent merging, JSONC handling, backups.
3. **Instructions massively expanded** → Each grew from basic guidelines to comprehensive reference documents.
4. **Agent frontmatter formalized** → Added explicit `name`, `model`, `tools`, `agents`, `handoffs`.
5. **Path standardized** — Default layout is derived from the repo clone name (no hardcoded path). The script uses `~/OneDrive/<repoName>/*` when OneDrive is present, or `~/<repoName>/*` as a fallback — only one location is populated per machine.
6. **Code review prompt formalized** → Multi-prompt workflow with industry-standard schemas (SARIF, CVSS, CWE).
7. **Sampler instructions became the largest file** → ~2,720 lines covering the complete Sampler ecosystem including DSC and Datum.
8. **Lab deployment fully automated** → Parameterized `Deploy-LabEnvironment.ps1` accepts a `$LabConfig` hashtable, `Test-LabDeployment.Tests.ps1` validates post-deployment, `lab-deploy.prompt.md` enables natural language lab requests.
9. **StrictMode compatibility fix** → Hashtable access changed from dot-notation to index-notation for optional keys in `Deploy-LabEnvironment.ps1`.
10. **Dynamic LabSources path** → Replaced hardcoded `C:\LabSources` with `Get-LabSourcesLocation` in skill and prompt files.
11. **LabDeploy prompt enhanced** — Added mandatory Agent Behavior section, `get_terminal_output` tool, deployment monitoring (Step 4), post-deployment validation (Step 5), expanded results reporting (Step 6), and Tool Requirements section. Removed old Automation Notes.
13. **Sampler instructions split** → Moved ~2,500 lines of domain reference from `sampler.instructions.md` to new `sampler-framework` skill. Instructions file slimmed to ~150 lines of enforced rules (structure, manifest, build safety, DO/DON'T). Follows the principle: instructions = auto-applied rules, skills = on-demand expertise.
14. **AutomatedLab skill expanded** → Added ~40 missing cmdlets across 15 new sections: VM Queries & Status, Wait Operations, VM Lifecycle, File Transfer, Session Management, DSC, Testing, Domain Operations, Security & Firewall, PKI/Certificates, Disk & ISO Management, Lab Configuration, Maintenance, Pre/Post Install Activities. Cmdlet Quick Reference table and expanded Roles table. File grew from ~500 to ~820 lines.
15. **External switch rearchitecture** → Default Switch DHCP proved unreliable during real deployment (APIPA addresses). Switched to External switch bound to physical NIC as recommended pattern. Default Switch documented as fallback. Post-deployment fix simplified to gateway/DNS only. Chocolatey install pattern added with PATH refresh. SKILL.md grew to ~1,278 lines.
16. **Agent maxRequests raised to 500** → Setup script now sets `github.copilot.chat.agent.maxRequests` to 500 (default is 5). Necessary for long-running agent tasks like lab deployments with terminal polling.
17. **NAT switch support added** → Documented new AutomatedLab `-UseNat` feature (PR #1812) as Approach D in the deployment skill. Creates Hyper-V NAT gateway automatically — no router VM, no physical NIC binding, no post-deployment fix needed.
18. **DSC troubleshooting skill created** → New `Skills/dsc-troubleshooting/SKILL.md` (~364 lines) covering the full diagnostic workflow for PowerShell DSC resource failures on target nodes.
19. **README skills inventory** → Added an Available Skills table listing all 11 skills with descriptions to the root `README.md`.
20. **CredSSP documentation** → Added comprehensive CredSSP section to AL skill (double-hop explanation, cmdlet table, troubleshooting) and expanded DSC skill's PsDscRunAsCredential section with CredSSP context.
21. **Datum configuration skill created** → New `Skills/datum-configuration/SKILL.md` (~435 lines) covering hierarchical DSC configuration data with Datum: merge strategies, RSOP, handlers, DscWorkshop, and ProjectDagger-specific patterns. README skills table updated to 12 entries.
22. **Five new agents added** → legal-researcher, Technical Troubleshooter, QC Inspector, Training Content Writer, DevOps Training Writer. Agents README reorganized into core SDLC pipeline (4) + supplementary domain-specific (4).
23. **Copilot CLI model routing reference** → `Reference/copilot-cli-model-routing.md` for 4-tier model routing in Copilot CLI (Executors, Implementers, Tech Leads, Architects). Moved out of `Instructions/` on April 21, 2026 — it is not an auto-attach instruction.
24. **Outlook calendar export skill created** → New `Skills/outlook-calendar-export/SKILL.md` covering Outlook COM calendar export to Markdown: recurring appointments (`IncludeRecurrences`), date range filtering, `GetFirst()`/`GetNext()` iteration, UTF-8 no-BOM encoding, index file generation, and BOM damage recovery.
25. **MECM DSC deployment skill** → New `Skills/mecm-dsc-deployment/SKILL.md` for SCCM/MECM deployment via DSC. Multiple iterations for SCCM 2509, remote runspace behavior, PsDscRunAsCredential.
25. **WinRM troubleshooting skill** → New `Skills/winrm-troubleshooting/SKILL.md` covering full WinRM diagnostic workflow.
26. **Pandoc DOCX export skill** → New `Skills/pandoc-docx-export/SKILL.md` for Markdown-to-Word export with Lua filters. Enhanced with content-aware column optimization.
27. **Timestamped agent responses** → All 8 agents now require UTC timestamp at the start of every response.
28. **Git instructions: AI-assisted commits** → Added commit attribution and branch naming conventions.
29. **Markdown instructions: anti-ASCII box art** → Added guideline against using ASCII art for structured data.
30. **Pester instructions: detached execution** → Emphasized using `Start-Process` to avoid VSCode hangs.
31. **README skills inventory expanded** → Available Skills table updated from 12 to 15 entries.
32. **PDF to Markdown skill** → New `Skills/pdf-to-markdown/SKILL.md` for converting PDF files to Markdown using .NET-native parsing. No external tools required — uses `DeflateStream` for zlib decompression, hex decoding for text operators, Y-coordinate ordering for line reconstruction. Handles German-locale PDFs (ISO-8859-1). README skills table updated to 16 entries.
33. **Copilot authoring instructions** → New `Instructions/copilot-authoring.instructions.md` (April 21) defines two-tier authoring rules for this repo's own content (strict for Instructions/Prompts, relaxed for Agents/Skills): purposeful-emphasis rule, banned maintenance footers, no boilerplate intros. Expanded the same day with additional guidance. Followed by a refactor pass (`78ddfdd`) aligning `changelog.instructions.md`, `versioning.instructions.md`, all 4 prompts, and `german-legal-research` skill, plus a cleanup pass (`041a9a6`) stripping boilerplate intro sentences from 10 instruction files.
34. **Troubleshooter → Writer handoff** → Technical Troubleshooter Agent now lists `technical-writer` in `agents:` and exposes a "Publish Runbook" handoff that converts a troubleshooting analysis into a polished runbook / KB article via the Technical Writer agent (commit `3b9044d`).
35. **Prompt frontmatter migration** → Renamed deprecated `mode:` to `agent:` in all 8 prompt files. Updated `copilot-authoring.instructions.md` to reflect the new key. Bound each prompt to a specific custom agent (`security-reviewer`, `software-engineer`, or `legal-researcher`) instead of the generic `agent` value.36. **Agent rename** → `Legal Researcher (DE)` → `legal-researcher` (kebab-case). Consolidated across prompts, `Agents/README.md`, and memory bank.
37. **Tax Researcher agent added** → `Agents/tax-researcher.agent.md` for German tax research and drafting. Persistent case memory bank; mandatory StBerG/RDG disclaimer.
38. **CHANGELOG added** → Top-level `CHANGELOG.md` in Keep a Changelog format, covering the project from first release.
39. **Keybindings merge** → New `Keybindings/keybindings.json` in the repo holds shared VS Code bindings. `Setup-CopilotSettings.ps1` merges them idempotently into `%APPDATA%\Code\User\keybindings.json` via a `(key, command, when)` dedup key; user-added bindings preserved; timestamped backup created on every run. Ships PowerShell restart, terminal/chat window-popout, and the Enter/Ctrl+Enter chat-submit swap.