# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This project does not currently use versioned releases; tagged releases will follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html) once publishing begins.

## [Unreleased]

### Added

- **New agent: `career-coach`** — [`Agents/career-coach.agent.md`](Agents/career-coach.agent.md). Bilingual (EN/DE) career coaching, CV/resume/Lebenslauf writing, cover-letter drafting, job search, application-pipeline tracking, interview preparation, salary negotiation, and LinkedIn/Xing optimization. Five-phase workflow (ASSESS → POSITION → CRAFT → APPLY → ADVANCE) with a persistent memory bank (`profile.md`, `career-strategy.md`, `applications.md`, `deadlines.md`, plus per-job dossiers and per-interview prep files). ATS-aware formatting rules, STAR/CAR/XYZ achievement framing, region-aware CV conventions (US/UK/IE/CA/AU resume vs. DE/AT/CH Lebenslauf vs. EuroPass vs. Academic CV), and an explicit ethics-first rule: never fabricates experience, qualifications, metrics, or credentials. Integrates `pdf-to-markdown` / `docx-to-markdown` / `xlsx-to-markdown` for ingestion, `pandoc-docx-export` for final DOCX rendering, `create-outlook-draft` / `send-outlook-email` for application emails, `outlook-calendar-export` for interview tracking, `microsoft-todo-tasks` for follow-ups, `grammar-check` for proofreading, `whisper-pyannote-transcription` for mock-interview debriefs, `marp-slide-overflow` for portfolio decks, and `authenticated-web-extraction` for LinkedIn/GitHub/Sessionize ingestion. Hands off to `legal-researcher` for German employment-law matters and to `technical-writer` for LinkedIn / thought-leadership pieces. Carries a mandatory StBerG/RDG-style disclaimer for any output with legal, financial, or contractual recommendations. Brings the agent count to 10.
- **New skill: `authenticated-web-extraction`** — [`Skills/authenticated-web-extraction/SKILL.md`](Skills/authenticated-web-extraction/SKILL.md) plus a bundled `bootstrap/` folder (`package.json`, `scripts/open.mjs`, `scripts/extract.mjs`, `tasks/check-logins.mjs`, `tasks/dump-cookies.mjs`) so the harness can be recreated on a new machine in one PowerShell snippet. Persistent Playwright + Microsoft Edge profile at `%LOCALAPPDATA%\CareerAuthBrowser\` for pulling data out of sites that require login (LinkedIn, GitHub, Sessionize, Microsoft 365, X, Meetup). Documents cookie-based auth detection (markup-stable, unlike DOM selectors), per-site auth cookie names (`li_at`, `user_session`, `.AspNet.ApplicationCookie`, `auth_token`, `MEETUP_MEMBER`), the session-cookie-vanish workaround (Chromium discards session-only cookies on shutdown — promote and re-inject on every run; documented as the reason Sessionize logs out between runs without it), Edge launch flags required for OAuth callbacks (`TrackingPrevention`, `ThirdPartyStoragePartitioning`, `FedCm`, `AutomationControlled`), the profile-lock orphan-`msedge.exe` failure mode, and a generic task-harness pattern for adding new extractions. Default rule: extract → propose → user pastes manually; never mutate user accounts. Brings the skill count to 23.

- **New skill: `whisper-pyannote-transcription`** — [`Skills/whisper-pyannote-transcription/SKILL.md`](Skills/whisper-pyannote-transcription/SKILL.md) plus companion `transcribe.py` and `diarize.py`. End-to-end pipeline to transcribe long recordings on a Windows GPU workstation and attach speaker labels: ffmpeg extracts a 16 kHz mono WAV; `faster-whisper` large-v3 (CTranslate2, float16) produces `.txt` / `.srt` / `.json`; `pyannote/speaker-diarization-3.1` produces an `.rttm`; segments are merged by max-overlap into `.diarized.json` / `.diarized.srt` / `.diarized.txt`. Documents 11 concrete pitfalls including the CPU-only PyPI torch wheel default (use `--index-url .../whl/cu128`), the dual HF gated-model agreement (`speaker-diarization-3.1` **and** `segmentation-3.0`), the Windows `torchcodec` failure with Gyan.FFmpeg full builds (preload waveform via `torchaudio.load` and pass `{waveform, sample_rate}` to the pipeline), the Python 3.12 venv constraint (3.13/3.14 lack ctranslate2/pyannote wheels), and the `Tee-Object` non-ASCII exit-code trap (verify outputs by file size, not exit code). RTX 4080 Laptop transcribes ≈ 2 h of audio in ≈ 30 min. Brings the skill count to 22.
- **New skill: `marp-slide-overflow`** — [`Skills/marp-slide-overflow/SKILL.md`](Skills/marp-slide-overflow/SKILL.md). Detects and fixes content overflow in Marp slide decks before exporting to PPTX/PDF/PNG, where Marp silently clips anything taller than the 1280×720 viewBox. Ships a Puppeteer-based `scrollHeight`-vs-viewBox detector (with CI-gate exit codes), a two-tier CSS density pattern (`dense` / `compact`) to fit content without splitting slides, a `fillRatio` decision table for picking the smallest fix, and a side-by-side HTML review report. Documents the phantom-leading-section gotcha that causes off-by-one mapping between source markdown and rendered slides. Brings the skill count to 21.

### Changed

- **`marp-slide-overflow` skill** — added a "Critical Gotcha: Frontmatter `backgroundColor` Wins Over Class CSS" section. Marp injects YAML `backgroundColor:` / `color:` as inline `style="..."` attributes on every `<section>` (including `background-image:none`), which silently defeats any `section.<class> { background: ... }` rule in the `style:` block. Symptoms: section-divider gradients never rendered, white-on-white headings, low-contrast subheadings. Documents detection (grep inline `style` attributes in rendered HTML), three fix options (tune class text colours to the inline background, move palette into `style:` block, or use per-slide `<!-- _backgroundColor: ... -->`), and adds a row to the anti-patterns table. Description keywords expanded.

## [1.1.0] — 2026-04-26

First public release alongside [`raandree/AgenticOperatingModel`](https://github.com/raandree/AgenticOperatingModel) (the workshop in which CopilotAtelier is the reference exemplar of a mature personal atelier).

### Changed

- **Setup script now uses a single target location instead of dual-copying.** When OneDrive is detected, `Setup-CopilotSettings.ps1` registers and populates only `~/OneDrive/<repoName>/*`; otherwise it falls back to `~/<repoName>/*`. Previously both locations were always populated, which doubled disk usage and created drift risk when one copy was edited out-of-band. Stale `~/<repoName>/` trees from earlier dual-copy runs are removed automatically when OneDrive is now used. README and memory bank updated accordingly.

### Added

- **Keybindings merge** — [`Keybindings/keybindings.json`](Keybindings/keybindings.json) is now merged idempotently by `Setup-CopilotSettings.ps1` into `%APPDATA%\Code\User\keybindings.json`. Match key is `(key, command, when)`; user-added bindings are preserved; a timestamped backup is created on every run. Bindings: `Ctrl+K X` restart PowerShell session, `Ctrl+K N` pop terminal to new window, `Ctrl+K K` pop chat to new window, and a chat-submit swap so `Ctrl+Enter` sends and plain `Enter` inserts a newline in the chat input.
- Top-level `CHANGELOG.md` (this file).
- Tax Researcher (DE) agent section in `Agents/README.md`.
- README "Featured In" section linking to the [Agentic Operating Model](https://github.com/raandree/AgenticOperatingModel) workshop and its companion patterns / memory-bank-template artefacts.
- Memory-bank documentation pass: refreshed inventories (20 skills, 13 instructions, 9 agents, 8 prompts) and expanded the `systemPatterns.md` applyTo list.

### Changed

- **Default model bumped to Claude Opus 4.7** across `Setup-CopilotSettings.ps1` (`gitlens.ai.vscode.model`, `github.copilot.advanced.model`), all 9 agent frontmatters, and supporting documentation. Opus 4.7 went GA in Copilot on 2026-04-16 and is Anthropic's announced replacement for Opus 4.5 / 4.6. The previous default `claude-opus-4.6-fast` was retired by GitHub on 2026-04-10 and would no longer resolve. Memory bank, [`README.md`](README.md), and [`Instructions/copilot-authoring.instructions.md`](Instructions/copilot-authoring.instructions.md) updated accordingly.
- **README clarified** to describe the actual dual-mirror layout (`~/CopilotAtelier/` always-populated local mirror plus an optional `~/OneDrive/CopilotAtelier/` mirror when OneDrive is detected) instead of describing the workflow as OneDrive-only. "Setup on a New Machine" now starts from a local clone.
- [`Reference/copilot-cli-model-routing.md`](Reference/copilot-cli-model-routing.md) carries a banner noting the April 2026 model-lineup changes (Opus 4.7 GA, GPT-5.5 GA, GPT-5.1 family deprecated, Opus 4.6 Fast retired). A full rewrite is planned post-1.1.0.

### Fixed

- Removed stale "German employment law skill" entry from [`.memory-bank/progress.md`](.memory-bank/progress.md) — the skill is not present in the repository (only [`german-legal-research`](Skills/german-legal-research) is).

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
- Default model set to Claude Opus 4.6 for GitLens AI and Copilot inline completions. *(Superseded in 1.1.0 — Opus 4.6 Fast was retired by GitHub on 2026-04-10; the new default is Opus 4.7.)*

[1.1.0]: https://github.com/raandree/CopilotAtelier/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/raandree/CopilotAtelier/releases/tag/v1.0.0