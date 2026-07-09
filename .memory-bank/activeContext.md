# Active context

## Current work focus

Began adopting the highest-value authoring patterns identified in the 2026-07-09 external skills-repo review (logged in `promptHistory.md`) into [`skill-creator`](../Skills/skill-creator/SKILL.md). This turn added a **Behavioural enforcement** section (anti-rationalization table, red-flags list, evidence/verification close) plus a matching required authoring-checklist item, so every future skill that encodes a skippable discipline pins the agent to its own process rather than letting it take the shortest path. Body 302 → 345 lines (≤ 500); `description` untouched at 1014/1024 chars (triggering unchanged); markdownlint clean; **not committed** (user: "Dont commit"). **Next step (offered, not started)**: the remaining section-2 item — a project-wide `definition-of-done` reference in [`Reference/`](../Reference/) — then the domain-neutral skill gaps (general TDD, debugging-triage, code-review).

## Recent changes (2026-07-09 — skill-creator behavioural-enforcement patterns)

From the review of a public agent-skills pack, folded its strongest transferable authoring patterns into [`skill-creator`](../Skills/skill-creator/SKILL.md) as original, rephrased guidance (no content copied; source not credited in the deliverable per user instruction):

- **New `## Behavioural enforcement: rationalizations, red flags, evidence` section** (after the Pattern catalogue, before "Scripts: solve, don't punt"). Three body patterns for skills that encode a discipline an agent tends to abandon: (1) an **anti-rationalization table** — excuse → rebuttal, so the model meets its own justification already answered; (2) a **red-flags** list — observable symptoms of drift phrased as symptoms not rules, whose firing means stop-and-re-enter; (3) an **evidence / verification (non-negotiable close)** — name the artifact and command that prove success, "looks right" is never enough — mirroring the repo's turn-level post-flight gate at the skill level.
- **Authoring checklist item added** requiring the three sections where a skill encodes a skippable discipline (tests, security, verification, destructive-op guards); explicitly waived for purely subjective-output skills (writing style, summarisation).
- **Deliberately not touched**: the `description` (already 1014/1024, no headroom; triggering unaffected) and `howto-write-skills.md` (the condensed primer — propagation offered as a follow-up).
- **Verification**: body 302 → 345 lines (≤ 500); `markdownlint-cli2` → 0 errors.

## Recent changes (2026-07-08 — long-running-job-monitor status-line enforcement)

Fixed a real failure where an agent that had loaded the skill emitted the START timestamp then went silent, giving status updates with no timestamp/elapsed — including on off-topic turns. Root cause: the rule lived only as descriptive prose in "Reporting format"/"Outcome" with no per-turn trigger and no definition-of-done gate. Body-only fix in [`Skills/long-running-job-monitor/SKILL.md`](../Skills/long-running-job-monitor/SKILL.md):

- **New `## The one rule (non-negotiable)` section** immediately after `## Outcome` — a `> [!IMPORTANT]` callout making the status line `[YYYY-MM-DD HH:mm UTC] elapsed=Xm | phase=… | status=WORKING|STALLED|DONE|FAILED | next=…` the mandatory first line of every in-flight reply; opening without it is a process violation.
- **Per-turn trigger** — the rule fires even when the user's turn is about something else; silence or "it's still going" with no timestamp/elapsed is a missing heartbeat, not "waiting correctly".
- **STATUS LINE checkbox gate** (mirrors pre/post-flight): UTC timestamp, elapsed since the pinned START, phase + status, next milestone, out-of-band target evidence.
- **Supersedes the generic opener** — a bare `[… UTC]` per-turn timestamp is insufficient while a job is in flight.
- **Elapsed-friction removal** — pin START once from the log's `START` line; copy the `.status` sidecar's latest line into the reply.
- **Anti-patterns block** under "Reporting format" (❌ off-topic answer with no status line; ❌ "still going" with no timestamp/elapsed; ✅ lead with the status line then answer); Reporting-format timestamps harmonized to `HH:mm UTC`; section 5 + bottom checklist now point at the gate (progressive disclosure).
- **Verification**: `description` unchanged; body 173 → 221 lines (≤ 500); markdownlint-cli2 0 errors.

## Recent changes (2026-07-07 — long-running-job-monitor skill)

- **New skill [`Skills/long-running-job-monitor/SKILL.md`](../Skills/long-running-job-monitor/SKILL.md)** (161-line body, description 982/1024 chars). Six load-bearing techniques: (1) instrument the job into a self-timestamping log (`START` / per-phase / silent-phase heartbeats / unique `<JOB>-DONE`/`-FAILED` marker, tee'd to `$env:TEMP`); (2) run it so it survives and self-notifies — sync-no-timeout preferred, async only for indefinite processes, **never a self-`Start-Sleep`/poll loop in the agent's own foreground command**; (3) verify progress **out of band** and read-only against the target (hypervisor/cloud API, QEMU guest-agent, SSH/WinRM/CIM, DB, HTTP health, `kubectl`, `az`/`aws`); (4) optional background monitor sidecar sampling every 300 s into a `.status` file; (5) a WORKING/STALLED/DONE/FAILED heuristic with strict timestamps + a phase-sized threshold; (6) completion + cleanup verifying the real end-state. Reporting format baked in.
- **Supporting files**: [`references/out-of-band-verification.md`](../Skills/long-running-job-monitor/references/out-of-band-verification.md) (per-domain read-only probes + change-detector pattern, `## Contents` TOC), [`scripts/Start-JobMonitor.ps1`](../Skills/long-running-job-monitor/scripts/Start-JobMonitor.ps1) (parameterized sidecar, **0 PSScriptAnalyzer findings**, 0 AST parse errors), and [`notes-evals.md`](../Skills/long-running-job-monitor/notes-evals.md) (five Claude-A/Claude-B evals: deploy-and-notify, is-it-stuck, buffered-stdout, mid-run death, remote-channel-drop).
- **New `systemPatterns.md` Decision 10** ("Long-running command execution (agent reliability)") — the sync-no-timeout-vs-async execution foundation + the never-self-`Start-Sleep` rule that the skill **extends** rather than duplicates; cross-links [`Instructions/powershell-execution-safety.instructions.md`](../Instructions/powershell-execution-safety.instructions.md).
- **Remote-execution coverage (follow-up)** — added a *Remote jobs (SSH / WinRM / PowerShell Direct)* subsection, an edge case, a checklist item, and a fifth eval: run the job detached on the remote, keep the instrumented log + liveness probe remote, verify via an independent control plane, and treat a dropped SSH/WinRM channel as reconnect-and-recheck (channel death is not job death).
- **Verification**: SKILL.md 173 lines (≤ 500), description 1006 chars (≤ 1024), folder name == `name:`, all three markdown files lint clean (`markdownlint-cli2`, 0 errors), the sidecar is PSScriptAnalyzer- and AST-clean.

## Recent changes (2026-07-07 — pswritehtml-reporting skill)

New skill answering "is PSWriteHTML worth integrating?" — verdict was yes as a skill (not an instruction), so the skill was authored.

- **New skill [`Skills/pswritehtml-reporting/SKILL.md`](../Skills/pswritehtml-reporting/SKILL.md)** — turns PowerShell objects into self-contained interactive HTML via [PSWriteHTML](https://github.com/EvotecIT/PSWriteHTML). Covers the `New-HTML { }` container (offline-inlined by default, `-Online` for CDN; returns a string or writes via `-FilePath`/`-ShowHTML`) and seven recipes: `New-HTMLTable` (DataTables filtering/paging/`-SearchBuilder`), `New-HTMLTableCondition` (conditional formatting, `-Inline` for email), `New-HTMLSection`/`Panel`/`Tab` layout, `New-HTMLChart` + `New-ChartBar`/`Line`/`Pie`/`Donut`, `New-HTMLDiagram` + `New-DiagramNode -To`/`New-DiagramLink`, `Out-HtmlView`, and an HTML email-body recipe that delegates sending to `send-outlook-email`. Includes `New-HTMLTableOption -DataStore JavaScript` large-dataset tuning, a gotchas list, and a `Test-Path`/`Select-String` verification step.
- **Security guardrail baked in.** A `> [!WARNING]` block steers away from the module's plaintext `-PasswordFromFile` SMTP pattern toward `[PSCredential]`/Mailozaurr OAuth2, per the repo's PowerShell security rules.
- **Accuracy.** PSWriteHTML is not installed locally; every command name was verified against Evotec's published examples (advanced-reporting, all-your-html-tables, emailimo, diagrams blogs) before authoring — no invented parameters.
- **Overlap fences.** `DO NOT USE FOR` delegates sending to `send-outlook-email`, Markdown-to-Outlook drafts to `create-outlook-draft`, slide decks to `marp-slide-overflow`, Word/PDF to `pandoc-docx-export`, and document conversion to the `*-to-markdown` skills.
- **Verified**: markdownlint clean (0 problems); description 1005/1024 chars; body 192/500 lines.
- **Counts**: skills 32 → 33 on the origin branch; with `long-running-job-monitor` from HEAD the repo now has **34** skills after this merge. Not yet wired into `send-outlook-email` (reciprocal cross-ref) or the QC Inspector agent — offered as follow-ups.

## Recent changes (2026-07-02 — agentic-security updates, uncommitted)

- **Security & QA agent — new Layer 6: LLM & Agentic Systems Security.** [`Agents/Security & Quality Assurance Agent.agent.md`](../Agents/Security%20&%20Quality%20Assurance%20Agent.agent.md): OWASP LLM Top 10 (LLM01/02/05/06/08 in depth, the rest screened), the lethal-trifecta blocking check (break a leg, not a guardrail; "95% = failing grade"; prompt injection ≠ jailbreaking), prompt-injection-via-tool-output, and a containment-first review (sandbox / egress allow-list / scoped least-privilege identity / no blanket PATs; ~93% approval fatigue). Added a flowchart node, two compliance-checklist lines, an *LLM & Agentic Systems Compliance Report Template*, OWASP GenAI + Simon Willison references, and a pointer to the new `agent-security-review` skill. Model → 4.8.
- **`mcp-builder` — new *Tool security* section.** Lethal trifecta per server, least-privilege / scoped creds, untrusted tool output, egress allow-listing, "audited connector ≠ audited data", confused-deputy; cross-links `agent-security-review`.
- **Two new skills (30 → 32).** `agent-security-review` (reusable agentic-review checklist; loaded by security-reviewer + software-engineer) and `agent-evals` (capability vs regression sets; deterministic / LLM-as-judge / human graders; pass@k vs pass^k; `scripts/run-evals.ps1`; `assets/evals.sample.json`; "start from 20–50 real failures").
- **software-engineer wired** to `agent-security-review` (Security design principle) and `agent-evals` (Testing Strategy).
- **Context engineering + AAIF.** `howto-write-skills.md` + `skill-creator` name context engineering as the discipline behind progressive disclosure; AAIF (Linux Foundation) added beside agentskills.io.
- **New repo-root `AGENTS.md`** — portable house rules (pre/post-flight, never push, approved-verb PS, Pester-first, authoring, current model) for cross-tool use.
- **Model sweep 4.7 → 4.8** across all 11 agents plus the global default (`Setup-CopilotSettings.ps1` gitlens + completions), `README.md`, `techContext.md`, and the `copilot-authoring` / `session-handoff` examples. The CLI routing reference was also updated (Opus → 4.8 with 4.7 fallback + 4.8-1m; deprecated GPT-5.1 family → GPT-5.5; Sonnet 4.6 / Haiku 4.5 / gpt-5.2-5.3 / Gemini left per the confirmed lineup).
- **Markdown lint policy codified.** New [`.markdownlint.jsonc`](../.markdownlint.jsonc) — repo now lints clean (0 violations under `markdownlint-cli2`; editor confirmed clean). Disables the stylistic rules the repo intentionally uses (long lines, compact tables, bare fences, blank-line spacing, duplicate generic headings, etc.), keeps + auto-fixes MD047 trailing newline. Also fixed 4 bare fences (`text`) and 5 trailing newlines.

## Known follow-ups from this pass

- **CLI routing reference lineup updated (2026-07-02).** [`Reference/copilot-cli-model-routing.md`](../Reference/copilot-cli-model-routing.md) bumped: Opus → 4.8 (4.7 fallback, 4.8-1m long-context) and the deprecated GPT-5.1 family → GPT-5.5. Per the confirmed lineup, Sonnet 4.6, Haiku 4.5, `gpt-5.2` / `gpt-5.3-codex` / `gpt-5.2-codex`, and `gemini-3-pro-preview` are left as-is pending the planned full rewrite.
- **Markdown correctness follow-up (deferred).** [`.markdownlint.jsonc`](../.markdownlint.jsonc) disables (but flags) genuine issues for a future pass: MD051 link fragments (×5), MD056 table-column count (×1), MD041 first-line heading (×1), MD038 spaces-in-code (×4). Everything else lints clean.
- **This work is uncommitted** on `ai/agentic-security-updates` per "dont commit!" — commit/push on explicit request only.

## Recent changes (June 11, 2026 — brand assets + README logo)

Integrated a Copilot Atelier brand kit into the docs via the `brand-docs` prompt; branch `ai/brand-docs` (from `main`), not pushed.

- **Four transparent brand PNGs in [`assets/`](../assets/)**, generated with the prompt's .NET colour-to-alpha helper from the Desktop design-board export (`CA #0…#10`). Logo source = board tile #1 (navy "Copilot" + teal "Atelier"); the dark-theme variant lifts the navy ink to near-white `#EAF1F8` and keeps the teal accent. Glyphs use the darker teal (#3) for light backgrounds and the brighter teal (#4) for dark. All four are `Format32bppArgb`, corner alpha 0, auto-cropped: `CA-logo-on-light.png` (1399×364), `CA-logo-on-dark.png` (1399×364), `CA-glyph-on-light.png` (692×816), `CA-glyph-on-dark.png` (684×808). Verified by compositing each on `#0d1117` and `#ffffff`.
- **README header rebranded.** [`README.md`](../README.md) H1 changed from "Copilot Customization via OneDrive" to "Copilot Atelier"; a `prefers-color-scheme` `<picture>` floats the logo left (width 300) with the intro wrapping right and `<br clear="left">` after it. No bordered box. Inline HTML wrapped in `markdownlint-disable MD033 MD041`.
- **[`Agents/README.md`](../Agents/README.md)** gains a right-floated glyph corner mark (`../assets/CA-glyph-on-*.png`, width 96).
- **New [`.gitattributes`](../.gitattributes)** (repo had none) per [`Instructions/git.instructions.md`](../Instructions/git.instructions.md): `* text=auto`, EOL pins for PS/MD/YAML/JSON, and `binary` for png/jpg/jpeg/gif/ico/webp/zip/nupkg.
- Throwaway `.work/` generator and `_chk-*` composites deleted; `git status` shows only `README.md`, `Agents/README.md` (modified) plus `.gitattributes`, `assets/` (new). Design-board sources not shipped.

## Recent changes (June 8, 2026 — merged origin/main into feature/marp-pptx-editable)

- **Merge resolution.** Integrated `origin/main` (2 commits: the `social-signal-sweep` skill #17 + Marp emoji / HTML-comment gotchas) into the 4-commit `feature/marp-pptx-editable` branch. Three conflicts resolved: (1) [`marp-slide-overflow/SKILL.md`](../Skills/marp-slide-overflow/SKILL.md) Recipe 5 — kept this branch's reference-pointer architecture and carried main's new **Gotcha D** (a premature `-->` leaking the rest of a note onto the slide) into [`references/speaker-note-guard.md`](../Skills/marp-slide-overflow/references/speaker-note-guard.md); main's emoji `display: block` gotcha auto-merged cleanly into the SKILL body; (2) `activeContext.md` and (3) `progress.md` — history unions (both branches' dated entries kept, chronological). Adopted main's June 8 / 30-skill counts. Not pushed.

## Recent changes (June 8, 2026 — social-signal-sweep skill)

New skill for recency-bounded social lead generation, plus a pointer wiring it into the research pipeline.

- **New skill [`Skills/social-signal-sweep/SKILL.md`](../Skills/social-signal-sweep/SKILL.md)** — surveys what people publicly say about a topic over a bounded recent window (default 30 days) across GitHub (native GitHub tools), Hacker News (Algolia API), Reddit (public JSON), Stack Overflow (Stack Exchange API), plus a browser-only tier (YouTube, X). Returns a **tier-8 lead sheet** (platform, date, engagement signal, link, what-to-verify) under a hard *leads-only, never citable* contract — engagement measures attention, not accuracy, and no sweep result may raise a claim above `Weak` on its own. No bundled engine, no API keys, no scraping cookies — uses only `web/fetch`, the GitHub tools, and `openSimpleBrowser`. Body 221 lines; description 1000 chars.
- **`research-analyst` wired** — new SOURCE-phase *Recency sweep for lead generation* bullet in [`Agents/research-analyst.agent.md`](../Agents/research-analyst.agent.md) points at the skill and reaffirms tier-8 leads stay `Weak`/`Speculation` until VERIFY triangulates against a higher-tier source. No `tools:` change needed — the agent already declares `web/fetch`, `github`, `web/githubTextSearch`, and `openSimpleBrowser`.
- **Counts**: skills 29 → 30.

## Recent changes (May 31, 2026 — marp Recipe 4b Bug 4: speaker notes dropped)

- **[`marp-slide-overflow`](../Skills/marp-slide-overflow/SKILL.md) — Recipe 4b gains Bug 4 (LibreOffice drops speaker notes) + python-pptx graft fix.** Added a fourth LibreOffice HTML→PPTX corruption bug after Bug 3, before the "Verify the text really is selectable" subsection. Symptom: `--pptx-editable` round-trips through LibreOffice which emits a PPTX with **no `ppt/notesSlides/` parts and no notes master** — native `--pptx` notes are silently gone. Not CSS-fixable (notes never reach the slide body). Detection: ZIP-inspect for `ppt/notesSlides/notesSlideN.xml` (0 = dropped). Fix: render a throwaway **native** PPTX from the *same editable assembled markdown* (identical slide count/order), then graft notes slide-by-slide with new `Copy-PptxNotes.py` (python-pptx auto-install; recreates notes slides, master, rels, `[Content_Types].xml`). Verify via python-pptx count. Bug-count intro updated three→four. `Copy-PptxNotes.py` added to Reference Implementation list. Description USE-FOR gains `editable PPTX notes, speaker notes dropped, pptx-editable notes missing, copy pptx notes, python-pptx notes` (dropped `marp --images png, searchable PPTX, lessmsi MSI extract, winget 1618` to keep 1022/1024 chars). Reference impl proven in `raandree/PSConfProxmoxSession` (build.ps1 region "3b" + build/Copy-PptxNotes.py): 41/41 slides carry notes. Keeps "ship both / never mutate the canonical deck" framing. No count change.

## Recent changes (May 29, 2026 — marp Recipe 4b editable-PPTX rendering fixes ported from session handoff)

- **[`marp-slide-overflow`](../Skills/marp-slide-overflow/SKILL.md) — Recipe 4b fidelity caveat replaced with real root cause + two proven fixes.** Ported from a `D:/rai` session handoff. The old "code/monospace blocks reflow — inherent, not fixable in CSS" bullet was wrong. New content: a `### Fix LibreOffice rendering bugs (editable path only)` subsection documenting **Bug 1** (LibreOffice drops digit glyphs from **bold** numeric table cells — `Haiku 4.5`→`Haiku .`, `$1.618455`→`$ .` — fixed by `table th, table strong, table b { font-weight: normal !important; }`; wider-substitute-font workaround explicitly rejected because it clips leading digits, `101,747`→`0 ,747`) and **Bug 2** (inline-code webfont can't be embedded → pin `code, pre, pre code` to `"Liberation Mono", "DejaVu Sans Mono", "Courier New", monospace !important`). Added two Key-facts bullets: never mutate the canonical deck (inject fixes into an editable-only assembled copy such as `dist/deck.editable.assembled.md`), and the silent `exit 1` with no error text when the target `.pptx` is open in PowerPoint. Deployed copy at `~/.copilot/skills/marp-slide-overflow/SKILL.md` re-synced. No count change.

## Recent changes (May 28, 2026 — marp editable-PPTX Recipe 4b + Pass-B split)

- **[`marp-slide-overflow`](../Skills/marp-slide-overflow/SKILL.md) — Recipe 4b added and skill split into `references/`.** New **Recipe 4b: Selectable-Text PPTX (`--pptx-editable`)** sits between Recipe 4 and the Phantom-Leading-Section gotcha: `--pptx` rasterises slides (text not selectable); `--pptx-editable` shells to LibreOffice (`soffice`) for real text shapes. Covers `SOFFICE_PATH` discovery, `<a:t>` verification via `System.IO.Compression`, and `lessmsi` MSI extraction when `winget` returns exit 1618. Description gains editable-PPTX keywords (now 983/1024 chars). Body trimmed 746 → 397 lines by extracting four recipes into one-level-deep references: [`mermaid-prerender.md`](../Skills/marp-slide-overflow/references/mermaid-prerender.md) (116), [`png-verification.md`](../Skills/marp-slide-overflow/references/png-verification.md) (112), [`overflow-detector.md`](../Skills/marp-slide-overflow/references/overflow-detector.md) (90), [`speaker-note-guard.md`](../Skills/marp-slide-overflow/references/speaker-note-guard.md) (157); each left as a 1–2-line pointer. Removes `marp-slide-overflow` from the Pass-B candidate list.

## Recent changes (May 27, 2026 — session-handoff prompt + storage convention)

New cross-session handoff workflow plus the storage convention it implies.

- **New prompt [`Prompts/session-handoff.prompt.md`](../Prompts/session-handoff.prompt.md)** — `agent: agent` (any active agent can produce one); writes a compact, pointer-based handoff document so a fresh session can resume without re-investigating context (context saturation, model switch, machine handover). Seven required sections: Header (UTC, **pattern: `closing` / `forward` / `return`**, source agent, model, branch, worktree, last SHA, dirty files, parent-handoff path for `return` only), Mission, State pointers (paths only — never inline duplicated content from Memory Bank / `plan.md` / `CHANGELOG.md` / commits), Suggested next agent (in-repo agent, `agent` / `ask`, **or a different harness/tool — `Claude Code` / `Codex` / `Copilot CLI` / `Cursor`**), Suggested skills (loaded-this-session + pre-load-for-next), Open questions, Redaction note (API keys, tokens, mailbox content, `%LOCALAPPDATA%\CareerAuthBrowser\` profile data). Three explicit patterns shape document content: closing (this session ends), forward (this session continues; child takes an out-of-scope sub-task), return (child reports learnings back to parent). Focus statement is mandatory: arguments → unambiguous derivation from `activeContext.md` → otherwise Mission empty + "Next-session focus undefined" becomes the first Open question (no fabricated missions). One handoff per invocation; never overwrites a prior file.
- **Storage convention**: `.memory-bank/session/handoff-<UTC>.md` where `<UTC>` is `YYYY-MM-DDTHHmmZ`. The folder also hosts `deadline-handoff-<yyyy-MM-dd-HH-mm>.md` produced by `sync-project-emails` Phase 7a. New repo-root [`.gitignore`](../.gitignore) excludes both patterns; the folder's [`README.md`](session/README.md) is tracked and documents purpose, lifecycle, and how the next session consumes a handoff.
- **`systemPatterns.md` Decision 8** disambiguates the two meanings of "handoff" in this repo: Decision 4 = in-session agent-to-agent UI transfer (`handoffs:` in agent frontmatter); Decision 8 = cross-session document. Same word, different problems.
- **Path fix in two legacy prompts** ([`deadline-action-handoff`](../Prompts/deadline-action-handoff.prompt.md), [`sync-project-emails`](../Prompts/sync-project-emails.prompt.md)) — the four references to `memory-bank/session/...` (no leading dot) were writing to a non-existent untracked folder at repo root. Corrected to `.memory-bank/session/...` so both prompts now share the canonical location with the new `session-handoff` prompt. The other `memory-bank/...` references in those prompts (for `activeContext.md`, `progress.md`, `projectbrief.md`) remain a separate pre-existing dot-prefix bug not in scope here.
- **Counts**: prompts 9 → 10.

## Recent changes (May 22, 2026 — skill-creator rewrite + Pass-B skill splits)

Rework of `skill-creator` and the three largest skills, driven by the Anthropic Agent Skills [overview](https://platform.claude.com/docs/en/agents-and-tools/agent-skills) + [authoring best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices) and Simon Scrapes' six-step framework video.

- **`skill-creator` rewritten** ([`Skills/skill-creator/SKILL.md`](../Skills/skill-creator/SKILL.md), 296 lines, description 1014/1024 chars). New material: six-step authoring frame (Name / Trigger / Outcome / Dependencies / Step-by-step / Edge cases), third-person description rule, degrees-of-freedom calibration (high/medium/low), one-level-deep references rule, `## Contents` TOC for refs >100 lines, six-pattern catalogue, evaluation-driven development with Claude-A/Claude-B loop, "solve don't punt" for scripts, plan-validate-execute, cross-skill overlap-audit recipe, mechanical "splitting an oversized SKILL.md" recipe.
- **Pass B — three oversized skills split into `references/`**: `sampler-framework` 2656 → 372 lines (12 refs), `automatedlab-deployment` 1815 → 353 lines (7 refs), `datum-configuration` 927 → 389 lines (4 refs). All references one level deep from SKILL.md; references >100 lines headed with `## Contents` TOC. SKILL.md bodies are now navigation maps: When-To-Use, recipe summaries, 1–2-line pointers to deep references.
- **Remaining Pass-B candidates** (>500 lines, no references): `pester-patterns` 872, `german-legal-research` 785, `sampler-migration` 729, `pandoc-docx-export` 718, `winrm-troubleshooting` 694, `mecm-dsc-deployment` 662, `outlook-email-export` 644, `pdf-to-markdown` 630, `dsc-troubleshooting` 627, `whisper-pyannote-transcription` 565. Tracked for follow-up. (`marp-slide-overflow` split May 28, 2026.)

## Recent changes (May 22, 2026 — marp + pester skill expansions)

Two skill expansions triggered by real findings while auditing Marp deck speaker-note coverage:

- **[`marp-slide-overflow`](../Skills/marp-slide-overflow/SKILL.md) — Recipe 5 added.** Speaker-note coverage gotchas and a drop-in Pester guard. Three gotchas: (A) `---` inside a code fence creates phantom slides — auditors must mirror the build's code-fence-aware slide splitter; (B) Marp directives (`version:`, `_class:`, `_paginate:`, `_color:`, `_backgroundColor:`, `fit`, `_split_`) are HTML comments too — filter by prefix blocklist plus inner-text length > 40 chars; (C) section-divider slides typically have per-module appendix notes, not per-slide notes — assert them separately. Includes a title-drift / merge pattern with a `notes-title-map.psd1` alias file for multi-file decks. Explains the editorial marker `<!-- _split_ -->`.
- **[`pester-patterns`](../Skills/pester-patterns/SKILL.md) — Pattern 14 added.** Pester 5 isolates each `It` in its own runspace; helper functions defined as `Describe` siblings of `It` blocks are invisible inside `It` (symptom: misleading `CommandNotFoundException`). Fix: define helpers in `BeforeAll`, share state via `$script:`. Three related gotchas: bare `$foo` in `BeforeAll` won't survive into `It`; `-ForEach` data must go in `BeforeDiscovery`, not `BeforeAll`; inlining helpers in every `It` is the cargo-cult workaround.

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

- **Model choice**: `Claude Opus 4.8 (copilot)` is the current model across all 11 agents and both global-default settings (`gitlens.ai.vscode.model`, `github.copilot.advanced.model` in `Setup-CopilotSettings.ps1`), plus `README.md`, `techContext.md`, the `copilot-authoring` example, and the `session-handoff` example (all bumped 2026-07-02). `Reference/copilot-cli-model-routing.md` is also current (Opus → 4.8, GPT-5.1 family → 5.5; Sonnet 4.6 / Haiku 4.5 / gpt-5.2-5.3 / Gemini unchanged per the confirmed lineup, pending its planned full rewrite).
- **OneDrive path**: Optional. When present, `~/OneDrive/CopilotAtelier/` is registered in addition to the mandatory `~/CopilotAtelier/` local mirror.
- **No CI/CD**: This is a configuration repository. Markdown linting could be added.

## Important patterns and preferences

- **Instruction files are comprehensive, not minimal** — each covers the full breadth of best practices for its language/domain.
- **Agents use zero-confirmation policies** — designed to execute autonomously without asking permission.
- **Skills use trigger phrases** — `USE FOR` / `DO NOT USE FOR` in descriptions help Copilot decide when to load them.
- **Setup script is non-destructive** — merges settings rather than replacing them, creates backups.
- **Agents organized into core SDLC pipeline + supplementary** — 4 core agents (Software Engineer, Security & QA, Technical Writer, Technical Troubleshooter) + 7 supplementary domain-specific agents (Legal Researcher, Tax Researcher, QC Inspector, Training Content Writer, DevOps Training Writer, Career Coach, Research Analyst).
