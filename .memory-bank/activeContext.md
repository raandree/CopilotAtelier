# Active context

## Current work focus

Post-1.1.0 release. As of May 20, 2026 the repository contains 11 agents, **14 instruction files**, 1 reference doc, **29 skills**, and **9 prompts**. Current focus: incremental skill and agent additions tracked under `[Unreleased]` in `CHANGELOG.md`.

## Recent changes (May 20, 2026 — grill-me + ubiquitous-language)

Added the repo-side anchors for slide 31 of the AgenticOperatingModel deck (*Two Patterns for Context — Grill-Me + Ubiquitous Language*):

- **New skill [`Skills/grill-me/SKILL.md`](../Skills/grill-me/SKILL.md)** — adversarial requirements interview, 40–100 questions across twelve mandatory categories, refuses to produce code/designs until a fixed-layout Design Concept is signed off (`SIGNED OFF`). Two-strike push-back protocol: refuse first override politely, comply on the second but log it in `Override log:`. Inspired by but independent of <https://github.com/mattpocockuk/skills>; grounded in Brooks, *The Design of Design* (2010). Pairs with `skill-creator`, `doc-coauthoring`, `ubiquitous-language`.
- **New instruction [`Instructions/ubiquitous-language.instructions.md`](../Instructions/ubiquitous-language.instructions.md)** — activates when `docs/glossary.md`, `glossary.md`, or `(.)memory-bank/glossary.md` is present; `applyTo` also covers `**/*.md`, `**/*.ps1`, `**/*.py`, `**/*.cs`, `**/*.ts`, `**/*.js`. Three-column glossary `Term | Means | Don't say`; five rules (read first; canonical terms only; never use forbidden synonyms; propose new rows instead of inventing; flag drift without silent rewrites). Out-of-scope: UI copy, third-party API field names.
- Counts: skills 28 → 29; instructions 13 → 14.

## Recent changes (May 20, 2026 — review and citation-integrity additions)

Reviewed [Imbad0202/academic-research-skills](https://github.com/Imbad0202/academic-research-skills) (CC BY-NC 4.0) for reusable patterns. Adopted three independent rewrites (not copies; attribution noted in each file):

- **New skill [`citation-integrity`](../Skills/citation-integrity/SKILL.md)** — claim extraction → three-layer anchor (locator + ≤25-word quote + stable identifier) → fetch → verdict (`VERIFIED` / `MISMATCH` / `NOT_FOUND`, no gray zone). Six-class failure taxonomy (F1 fabricated reference, F2 plausible-but-wrong attribution, F3 identifier hallucination, F4 partial hallucination, F5 claim-not-supported, F6 anchorless claim). Iron rule: no memory verification — every `VERIFIED` verdict must point to a passage retrieved during the session. Cross-index triangulation (Crossref + OpenAlex / Semantic Scholar + publisher) required before declaring F1.
- **New skill [`devils-advocate-review`](../Skills/devils-advocate-review/SKILL.md)** — hostile-but-fair reviewer with anti-sycophancy guardrails. 1–5 rebuttal scoring rubric (concession only at ≥ 4; no consecutive concessions; attack-intensity preservation), named deflection classes (reframe, authority, volume, sentiment, goalpost shift, tu quoque, premature consensus), frame-lock self-check every three rounds, closing report with sycophancy log (concession rate, consecutive-concession events, frame-lock interventions) and `accept` / `revise` / `reject` recommendation.
- **New prompt [`peer-review.prompt.md`](../Prompts/peer-review.prompt.md)** — multi-perspective peer review of any document (RFC, ADR, design doc, paper, long-form article) with EIC + Methodology/Architecture + Evidence/Implementation + Clarity/Audience + Devil's Advocate panel. 0–100 rubric mapped to Accept (≥ 80) / Minor (65–79) / Major (50–64) / Reject (< 50); consensus matrix; deterministic EIC decision rule with hard-split escalation; chains into `devils-advocate-review` for DA behaviour and into `citation-integrity` for any factual claim.
- **Counts**: skills 26 → 28; prompts 8 → 9. Folders already exist under `Skills/`; will be picked up by the next `Setup-CopilotSettings.ps1` run via the existing junction wiring (`~/.copilot/skills`, `~/.copilot/prompts`).
- **[`research-analyst`](../Agents/research-analyst.agent.md) wired to the new skills.** Claim-Level Verification Recipes table gains an *Any cited reference (operational gate)* row that hands every supporting citation to `citation-integrity` before an `Established`/`Probable` grade and adopts the F1–F6 failure taxonomy as the canonical vocabulary for *Known Limits*. The *Adversarial Self-Review* subsection now requires running the finding through `devils-advocate-review` against itself, with the Devil's Advocate closing report (surviving attacks + sycophancy log + recommendation) attached to the dossier's *Adversarial review* field; surviving premise-level attacks are dossier-blocking. New *Panel-Review the Dossier* handoff invokes the `peer-review` prompt before publishing.

## Recent changes (May 19, 2026 — skill expansion pass)

- **3 new skills** added: [`skill-creator`](../Skills/skill-creator/SKILL.md) (meta-skill: how to author/iterate `SKILL.md` files, progressive disclosure, trigger-keyword pattern, 1024-char cap, lightweight evals), [`mcp-builder`](../Skills/mcp-builder/SKILL.md) (build MCP servers end-to-end with tool naming, schemas, pagination, MCP Inspector testing, 10-question eval rubric, Windows stdio gotchas), [`doc-coauthoring`](../Skills/doc-coauthoring/SKILL.md) (three-stage workflow: context gathering → section-by-section refinement → reader testing with a fresh subagent).
- **4 existing skills broadened**:
  - [`docx-to-markdown`](../Skills/docx-to-markdown/SKILL.md) now also covers OOXML in-place edits, tracked changes (`<w:ins>` / `<w:del>`), comments, and LibreOffice-headless accept-all.
  - [`pdf-to-markdown`](../Skills/pdf-to-markdown/SKILL.md) now also covers merge/split/rotate/watermark/encrypt/decrypt/create-from-scratch (reportlab)/AcroForm-fill via `pypdf` + `qpdf`.
  - [`xlsx-to-markdown`](../Skills/xlsx-to-markdown/SKILL.md) now also covers create/edit with `openpyxl` + `pandas`, the "always write Excel formulas, never hardcoded computed values" rule, and a LibreOffice-headless recalc + `#REF!`/`#DIV/0!`/`#VALUE!`/`#N/A`/`#NAME?` scan.
  - [`marp-slide-overflow`](../Skills/marp-slide-overflow/SKILL.md) Recipe 0 gains a Step 3b that hands at-risk PNGs to a fresh subagent for adversarial visual QA (8-point checklist).
- **6 skill descriptions audited against the 1024-char CLI cap** after the broadening pass; all six finalised between 952 and 1016 chars. (Marp's pre-existing 1619-char description is a separate, known issue tracked from May 6.)
- **Skill count: 23 → 26.**

## Recent changes (May 13, 2026)

### `research-analyst` agent — methodology grounding pass

- Applied a follow-up revision to [`Agents/research-analyst.agent.md`](../Agents/research-analyst.agent.md) after researching canonical methodology sources (PRISMA 2020, Cochrane Handbook v6.5 ch. 7/8/25, GRADE, AMSTAR 2, SIFT, IFCN, FAIR, Equator Network, Verification Handbook 3, Bellingcat resources). Twelve targeted insertions:
  - Confidence scale now maps to **GRADE** four-tier certainty (High/Moderate/Low/Very Low) with `Contested`/`Speculation` retained as research-specific overlays.
  - Workflow header cites **PRISMA 2020** (Page MJ et al. BMJ 2021;372:n71) instead of vague "PRISMA-style".
  - Lateral reading is now explicitly the **SIFT method** (Caulfield 2019; Caulfield & Wineburg, *Verified*, 2023) with the four moves (Stop / Investigate the source / Find better coverage / Trace claims) spelled out.
  - OSINT recipes expanded with **InVID/WeVerify, FotoForensics, EXIFTool, Sentinel Hub / EO Browser** toolchain and multi-archive evidence preservation.
  - New **Investigating Disinformation and Information Operations** subsection (actor analysis, bots, patient-zero, closed-group monitoring, synthetic media + C2PA, network attribution).
  - Source-provenance checks gained **ORCID/ROR**, **IFCN Code of Principles**, **FAIR**-aligned persistent-identifier-first rule, and a pre-registration check (OSF, AsPredicted, ClinicalTrials.gov, EU CTR, DRKS, PROSPERO).
  - Verification recipes gained four new rows: **AMSTAR 2** for systematic reviews, **RoB 2** for RCTs, **ROBINS-I** for non-randomized intervention studies, **Equator Network** reporting-guideline lookup, and a **conflicts-of-interest extraction** recipe per Cochrane Handbook §7.8.
  - New **Non-Reporting Biases** subsection imports the Cochrane Handbook §7.2.3 taxonomy with empirical effect sizes.
- Sources that returned HTTP 403/404 (RFC 7089 Memento, Tetlock superforecasting field guide, Wikipedia SIFT) were *not* cited; their candidate additions (probabilistic-calibration, multi-archive Memento protocol, citation-context analysis) are deferred until reachable.

### New agent: `research-analyst` (initial commit `af03b9d`, May 13 earlier)

- [`Agents/research-analyst.agent.md`](../Agents/research-analyst.agent.md) — technical and scientific web research and investigation agent designed to upstream-feed the SDLC pipeline and the domain agents with fact-checked, source-traced findings instead of plausible-sounding LLM prose.
- Five-phase workflow (SCOPE → SOURCE → VERIFY → SYNTHESIZE → DELIVER); 8-tier source hierarchy; ≥ 3 independent primary sources for `Established` Tier-1 claims; per-claim verification recipes; anti-LLM-citation-laundering rule; investigation memory bank (`investigation-<slug>.md` + `-sources.md` + `-querylog.md` + `-notes.md`); dossier template with replication log; mandatory archive snapshots.
- Handoffs: `technical-writer` (Publish as Article), `legal-researcher` (Escalate German-Law Angle), `tax-researcher`. Agent count: 10 → 11. Registered in `Agents/README.md` (position 11, supplementary tier), `techContext.md` agents table, and `progress.md` "What works". Lints clean.

## Recent changes (May 8, 2026)

### All 10 agent `tools:` arrays normalized and expanded

- Three classes of pre-existing breakage resolved: invalid namespaced IDs in `legal-researcher`; look-alike names silently dropped in `career-coach` / `tax-researcher`; `qc-inspector` shipped with only 4 tools. Every bare name then migrated to the VS Code 1.105 fully-qualified form (`search/`, `edit/`, `web/`, `vscode/`, `read/`, `execute/` namespaces).
- Universal additions: `read/readFile`, `search/fileSearch`, `search/listDirectory`, `search/textSearch`, `read/viewImage`, `vscode/askQuestions`, `todo`, `execute/getTerminalOutput`. Engineering preset adds `web/githubTextSearch`, `vscode/runCommand`, `vscode/installExtension` (+ `vscode/getProjectSetupInfo` for sw-eng + troubleshooter). Software-engineer also gets the Jupyter set. Required `agent` tool added to the 5 files declaring an `agents:` list.
- Canonical names discovered from the Copilot extension's `package.json` `languageModelToolSets` and the `legacyToolReferenceFullNames` aliases in `workbench.desktop.main.js`. All 10 agent files lint clean.

## Recent changes (May 7, 2026)

- **Setup script**: re-added `chat.promptFilesLocations` writer for the prompts junction (VS Code Copilot chat does not auto-discover `~/.copilot/prompts`, only the CLI does); persists `COPILOT_ALLOW_ALL=1` at User scope so `gh copilot` does not block on per-tool confirmation prompts.
- **Pre-flight contract hardened**: probe for `.memory-bank/` is now a separate numbered step (step 1) in [`Instructions/preflight.instructions.md`](../Instructions/preflight.instructions.md) and in the embedded block in every agent. The workspace summary is explicitly labelled **not authoritative** for hidden folders. The acknowledgment must name the probe used and its result. Triggered by an agent in this very workspace announcing "no Memory Bank" from the workspace listing alone.

## Recent changes (May 19, 2026)

- **`marp-slide-overflow` skill expanded** — added mermaid pre-render section (Option B with `mermaid-cli`, content-hash SVG cache, relative-path image substitution, label-quoting gotchas, `section img { max-height }` cap, prefer `graph LR`) and **Recipe 0** (mandatory PNG-based visual verification: render all slides via `marp --images png`, flag at-risk slides by heuristic, hand-check three invariants — title, footer page number, no half-cut rows; iterate). Text heuristics and HTML preview are explicitly demoted to smoke alarms, not gates. README and techContext updated.

## Recent changes (May 6, 2026)

- **Junction-based discovery**: `Setup-CopilotSettings.ps1` no longer writes `chat.agentFilesLocations` / `chat.instructionsFilesLocations` / `chat.agentSkillsLocations`. After copying customizations to the canonical target it creates NTFS junctions at `%USERPROFILE%\.copilot\{agents,instructions,skills,prompts}` so both the VS Code Copilot chat extension and the GitHub Copilot CLI discover the same tree.
- **Skill descriptions trimmed**: 11 `SKILL.md` files exceeded the CLI's 1024-char `description:` cap. All 23 skills now ≤ 1024 chars (max 1010).

## Recent changes (May 2–5, 2026)

- **New skill `whisper-pyannote-transcription`** (May 2, expanded May 5) — end-to-end GPU transcription + speaker diarization on Windows. 17 documented pitfalls. Recipe 3b (segment + glossary, mixed-language split) and Recipe 5 (evidence-grade majority-voting transcription) added May 5.
- **New skill `authenticated-web-extraction`** (May 3) — persistent Playwright + Edge profile harness with session-cookie-vanish workaround, OAuth callback flags, generic task pattern. Used by `career-coach`.
- **New agent `career-coach`** (May 3) — bilingual (EN/DE) career coaching, CV/Lebenslauf, ATS-aware, ethics-first; hands off to `legal-researcher` and `technical-writer`.

## Recent changes (April 22–29, 2026)

- **New skill `marp-slide-overflow`** (April 29) — Puppeteer-based overflow detector, two-tier CSS density pattern, CI gate.
- **Keybindings merge** (April 23) — `Keybindings/keybindings.json` merged idempotently by `Setup-CopilotSettings.ps1` into `%APPDATA%\Code\User\keybindings.json`.
- **Release-prep doc pass** (April 23) — refreshed techContext / systemPatterns / Agents README for the 9-agent / 20-skill state.
- **New agent `tax-researcher`** (April 22) — German tax research with persistent case memory bank and StBerG/RDG disclaimer.
- **Agent rename** (April 22): `Legal Researcher (DE)` → `legal-researcher` (kebab-case, consistent with handoff naming).
- **Deadline-action-handoff prompt rewrite**, setup-script hardening, prompt frontmatter migration `mode:` → `agent:` with each prompt bound to a specific custom agent.

## Recent changes (April 21, 2026)

- **`copilot-authoring.instructions.md`** — meta-instruction governing how Instructions, Prompts, Skills, and Agents are authored. Two-tier scope (strict for Instructions/Prompts, relaxed for Agents/Skills); purposeful-emphasis rule; bans maintenance footers. Refactor pass aligned existing instructions/prompts/skills with the new rules.
- **Technical Troubleshooter** wired to `technical-writer` with a new "Publish Runbook" handoff.

## Earlier history

Earlier entries (March 4 – March 31, 2026) are preserved in `progress.md` under "Evolution of project decisions" (decisions 1–48). They cover the original 5 agents (`legal-researcher`, Technical Troubleshooter, QC Inspector, Training Content Writer, DevOps Training Writer) added March 4–8, the Copilot CLI model-routing reference, and the skill expansions for `dsc-troubleshooting`, `mecm-dsc-deployment`, `pdf-to-markdown`, `outlook-calendar-export`, `winrm-troubleshooting`, `pandoc-docx-export`, and related instruction updates.

## Next steps

- Consider adding more skills (e.g., Docker, CI/CD patterns, Azure DevOps)
- Consider adding language instructions for Python, JavaScript, TypeScript
- Consider creating a GitHub Actions or Azure Pipelines CI to lint the instruction files
- Monitor VS Code updates for new Copilot extensibility features
- Memory Bank maintenance is ongoing

## Active decisions and considerations

- **Model choice**: Claude Opus 4.7 is the current default for agents and the model id configured in `Setup-CopilotSettings.ps1`. The Copilot CLI model-routing reference (`Reference/copilot-cli-model-routing.md`) still describes the pre-4.7 lineup and is flagged for a fuller refresh post-1.1.0.
- **OneDrive path**: Optional. When present, `~/OneDrive/CopilotAtelier/` is registered in addition to the mandatory `~/CopilotAtelier/` local mirror.
- **No CI/CD**: This is a configuration repository. Markdown linting could be added.

## Important patterns and preferences

- **Instruction files are comprehensive, not minimal** — each covers the full breadth of best practices for its language/domain.
- **Agents use zero-confirmation policies** — designed to execute autonomously without asking permission.
- **Skills use trigger phrases** — `USE FOR` / `DO NOT USE FOR` in descriptions help Copilot decide when to load them.
- **Setup script is non-destructive** — merges settings rather than replacing them, creates backups.
- **Agents organized into core SDLC pipeline + supplementary** — 4 core agents (Software Engineer, Security & QA, Technical Writer, Technical Troubleshooter) + 7 supplementary domain-specific agents (Legal Researcher, Tax Researcher, QC Inspector, Training Content Writer, DevOps Training Writer, Career Coach, Research Analyst).
