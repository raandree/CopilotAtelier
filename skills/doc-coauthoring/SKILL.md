---
name: doc-coauthoring
description: >-
  Three-stage workflow for co-authoring a substantive document with a user:
  (1) Context Gathering with meta-questions + info dump + clarifying
  questions; (2) Refinement section-by-section with clarify → brainstorm →
  curate → draft → surgical edits; (3) Reader Testing where a fresh
  assistant or subagent reads the doc cold and answers predicted reader
  questions to surface blind spots. Pairs with `technical-writer`,
  `legal-researcher`, and `tax-researcher` agents.
  USE FOR: co-author a document, write a spec, write a design doc, write a
  PRD, write an RFC, write a decision doc, write a proposal, draft a
  post-mortem, draft a Schriftsatz, section-by-section drafting, reader
  test a document, doc blind spot check, refine doc iteratively, info-dump
  workflow, brainstorm section options, surgical edit, fresh-eyes review.
  DO NOT USE FOR: short emails, code review, README authoring, pure copy
  editing (use `grammar-check`).
---

# Doc Co-Authoring Workflow

Guide a user through writing a long, high-stakes document by alternating between question-driven context gathering, structured per-section drafting, and a fresh-eyes reader test before declaring done. Active guide, not freeform brainstorm.

## When to Use

- User says: "draft a spec", "write a design doc", "help me write a proposal", "draft an RFC", "draft a Schriftsatz", "draft a memo".
- The deliverable will be read by people who weren't in the original conversation.
- The user has context the assistant lacks (org politics, prior incidents, tacit knowledge).
- The doc is long enough that drafting it as one blob produces incoherent results (typically > ~2 pages).

## When NOT to Use

- The user wants a quick paragraph or an email. Just write it.
- The doc is purely factual and the user has zero hidden context (e.g., "summarise these meeting notes"). The intermediate stages waste time.
- The user explicitly asks for freeform back-and-forth. Honour that.

## Opening offer

On first invocation, surface the workflow and let the user opt in:

> I can take you through a structured co-authoring loop in three stages: (1) context gathering, (2) section-by-section drafting with brainstorm + curate, (3) a reader-test pass with a fresh assistant. It usually produces a tighter doc than freeform drafting. Want to use it, or prefer freeform?

If the user declines, write freeform. If accepted, run Stage 1.

## Interaction style

When interviewing the user (clarifying questions in Stage 1, section-choice prompts in Stage 2, reader-test questions in Stage 3), follow the shared convention in [`Reference/interactive-questions.md`](../../Reference/interactive-questions.md): prefer `vscode_askQuestions` over markdown checkboxes when the tool is available.

## Stage 1 — Context Gathering

Goal: close the gap between what the user knows and what you know.

### 1a. Meta-questions (always ask)

1. Document type? (spec, decision doc, RFC, Schriftsatz, post-mortem, …)
2. Primary audience? (engineering peers, executives, an opposing counsel, a regulator, …)
3. What should the reader do or decide after reading?
4. Is there a template, prior doc, or style guide to match?
5. Hard constraints (length, format, jurisdiction, classification)?

State that shorthand answers are fine.

### 1b. Info dump

Invite an unstructured dump of everything the user knows: background, prior decisions, org dynamics, related discussions, timeline pressure, technical constraints, stakeholders. Tell the user not to organise it.

Offer concrete ways to dump: stream of consciousness, links to threads/docs, paste of meeting notes, file attachments. If MCP / connector tools are available (Outlook, GitHub, Sharepoint, Confluence), mention you can pull context directly.

### 1c. Clarifying questions

When the user signals they're done dumping (or after a substantial dump), generate 5-10 numbered clarifying questions targeting actual gaps. Let them answer in shorthand ("1: yes, 2: see #thread, 3: skip…"). Iterate until your follow-up questions are about edge cases and trade-offs, not basics — that's the exit signal.

Ask: "Anything else, or shall we move to drafting?"

## Stage 2 — Refinement (section by section)

Goal: produce one tight section at a time through structured iteration.

### 2a. Agree the section list

Propose 3-7 sections appropriate to the doc type. Examples:

- **Decision doc:** Context → Decision → Alternatives Considered → Consequences → Open Questions.
- **Technical spec:** Problem → Goals / Non-goals → Approach → Trade-offs → Migration → Risks.
- **Schriftsatz / legal memo:** Sachverhalt → Rechtliche Würdigung → Anträge → Anlagen.
- **Post-mortem:** Timeline → Impact → Root cause → What went well → Action items.

Confirm the structure. Create a placeholder skeleton in the target file (or as an artifact) with `[To be written]` per section. Suggest starting with the section that has the most unknowns — usually the core decision or the technical approach. Summaries last.

### 2b. Per-section loop

For each section, run five steps:

1. **Clarify.** 3-7 numbered questions targeting what this specific section needs. Shorthand answers welcome.
2. **Brainstorm.** Propose 5-20 numbered options for what this section could include. Cover obvious points and missed angles. Offer more on request.
3. **Curate.** User indicates keep/remove/combine. Parse freeform feedback too ("keep 1-3, drop 5, merge 7+8"). Note their priorities — they transfer to later sections.
4. **Gap check.** "Anything missing for this section?"
5. **Draft.** Edit the placeholder in place. Ask the user to read and tell you what to change — specifically not to edit it directly, so you learn their style. They may still edit; if they do, note the deltas as style signal for later sections.

Iterate by **surgical edits** (one block at a time). Do not reprint the whole document. If iteration plateaus after ~3 rounds, ask: "Anything we can cut without losing meaning?"

Mark the section done. Move to the next.

### 2c. Coherence pass

At ~80% of sections complete, read the whole document and surface: contradictions, redundant content, generic filler, sentences that don't carry weight. Apply or propose fixes.

## Stage 3 — Reader Testing

Goal: catch blind spots before someone outside the conversation reads it.

### 3a. Predict reader questions

Generate 5-10 questions a real reader would ask after reading the doc cold. Include the obvious ("what is this proposing?") and the harder ("what happens to the X system after this change?").

### 3b. Run the test

Two options depending on tooling:

- **With subagent / fresh chat available.** Spawn a subagent (use `runSubagent`) passing only the document text and one question. Repeat per question. Capture answers.
- **No subagent.** Tell the user to open a fresh chat (https://chat.openai.com or a clean Copilot chat), paste the doc, and ask the predicted questions one at a time. Report findings back.

Also ask the fresh reader explicitly:

- What in this doc is ambiguous or unclear?
- What background knowledge does the doc assume?
- Are there contradictions or inconsistencies?

### 3c. Triage and fix

For each wrong answer or surfaced gap, loop back to Stage 2 for the affected section. Re-run reader testing on changed sections. Done when the fresh reader answers correctly and surfaces no new gaps.

## Final review

Before declaring complete:

1. User does a final read-through. They own the doc.
2. User verifies facts, links, names, numbers.
3. User confirms the doc achieves the stated impact (the Stage-1 question 3 answer).

Optional close-out tips for the user:

- Link the originating chat as an appendix so readers can audit how the doc was assembled.
- Push depth into appendices; keep the main body lean.
- Treat the first release as a draft — update with real-reader feedback.

## Tone and operating rules

- Direct, procedural. Don't sell the workflow — just run it.
- Explain rationale only when it changes user behaviour ("don't edit the draft directly so I learn your style").
- Always give the user agency to skip a stage or revert to freeform.
- Use surgical edits (`str_replace` semantics), never reprint the whole doc.
- Never use placeholders like `[fill in details]` in the final draft. If a section can't be drafted, ask, don't fake.

## Common pitfalls

- **Skipping Stage 1.** Drafting without context produces plausible-sounding nonsense.
- **Brainstorming as a single dense paragraph.** Numbered lists are essential for the curate step.
- **Iterating forever on Section 1.** Move on when the section is good enough; coherence pass catches residuals.
- **Skipping Stage 3.** The fresh-reader test is the single most valuable step; subagents make it cheap.
- **Treating the doc as the assistant's output.** It's the user's deliverable. They own facts, claims, and final wording.
