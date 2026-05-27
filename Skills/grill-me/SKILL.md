---
name: grill-me
description: >-
  Adversarial requirements interview that grills the user with 40-100
  questions across purpose, users, inputs/outputs, failure modes, edge
  cases, security, performance, ownership, rollback, observability,
  non-goals, and open questions — before any code, design, or diagram is
  written. The interview transcript becomes the spec; pairs with
  spec-driven development and Brooks' *Design of Design*.
  USE FOR: grill me, grill-me, adversarial requirements interview, spec
  interview, requirements interrogation, design concept before code,
  Brooks Design of Design, what could go wrong, edge case interview,
  pre-flight requirements, interview before implementation, refuse to
  code until spec, no code yet, spec-driven dev kickoff.
  DO NOT USE FOR: writing code, writing tests, reviewing diffs,
  generating documentation from existing code, code review, refactoring.
---

# Grill-Me

Turn the agent into an adversarial requirements interviewer **before** any code, design, or diagram is produced. The interview transcript and the **Design Concept** it produces are the deliverable for the turn; everything downstream (code, tests, infrastructure) waits for explicit user sign-off.

## Why

Defects originate in requirements, not in code. Fred Brooks, *The Design of Design* (2010), argues that the cheapest defect to fix is the one caught while the design concept is still text. LLMs default to the opposite behaviour: they generate plausible code from under-specified prompts and bury the unanswered questions in invisible assumptions. Grill-Me is the counter-pattern.

The grill-me transcript becomes the spec. It pairs naturally with spec-driven development workflows where the spec — not the code — is the source of truth.

Prior art: <https://github.com/mattpocockuk/skills> (~13k stars) ships a similar adversarial-interview skill. This skill is independent and self-contained; do not depend on that repo at runtime.

## Protocol

The agent MUST follow these steps in order. Steps 1–3 are non-negotiable.

### 1. Refuse to produce artefacts until the interview is complete

No code. No file edits. No architecture diagrams. No pseudocode. No "here is what I would write". The only output during the interview phase is the next question (or tight cluster of questions) and, at the end, the Design Concept document.

If the user has already pasted code or a partial design, treat it as **input to interrogate**, not as a green light to start building.

### 2. Ask 40–100 questions across all twelve categories

Every category below MUST be covered. Skipping a category is a process violation; if a category is genuinely N/A, ask one question that establishes that and move on.

1. **Purpose & success criteria** — What problem is solved? What does success look like, measurably? What does failure look like?
2. **Users & stakeholders** — Who triggers this? Who consumes the output? Who owns it on-call? Who pays the bill?
3. **Inputs & outputs** — Exact shape, types, units, ranges, encodings, character sets, time zones, locales. What is the upstream source? What is the downstream consumer?
4. **Failure modes & error handling** — What happens on bad input? On partial input? On an upstream outage? Retry? Dead-letter? Crash loud? Degrade silent? Who gets paged?
5. **Edge cases & boundaries** — Empty input. Maximum input. One element. Unicode. Negative numbers. Zero. Leap seconds. DST transitions. Network partitions. Concurrent writers. Idempotency.
6. **Security & privacy** — Who can call this? What authn/authz? PII? PHI? Secrets handling? Threat model? OWASP relevance? Data residency? Audit logging?
7. **Performance & scale** — Expected QPS? P50/P95/P99 latency budget? Payload size? Concurrency limits? Backpressure strategy? Cost ceiling?
8. **Operational ownership** — Who deploys it? Who monitors it? Who patches it? What runbook? What SLO/SLA?
9. **Rollback & reversibility** — Feature flag? Blue/green? Migration reversible? Data loss possible on rollback? "Undo" semantics for the user?
10. **Observability** — What logs? What metrics? What traces? What dashboards? What alerts? What is the success indicator a human can see in 30 seconds?
11. **Out-of-scope / non-goals** — What is explicitly NOT being built? What temptation to scope-creep should we name now and refuse?
12. **Open questions the user cannot answer yet** — Force the user to list them rather than letting the agent silently assume. These become explicit `TBD` items in the Design Concept.

### 3. One question (or one tight cluster) at a time

Never dump 40 questions in a single message. A "tight cluster" is 2–4 questions that genuinely belong together (e.g. P50/P95/P99 latency budget). Wait for the answer. Adjust the next question based on what was learned. The interview should feel like a conversation, not a form.

When a category is exhausted, announce the move: *"Moving from Inputs & outputs to Failure modes."*

#### Rendering: prefer the interactive question UI

When the `vscode_askQuestions` tool (a.k.a. `vscode/askQuestions`) is available in the current session, the agent MUST use it to render each question or cluster instead of plain markdown checkboxes. Rationale: markdown checkboxes are not interactive — the user cannot click them and is forced to retype answers in prose. The interactive UI lets the user tick options, multi-select, or type freeform and returns structured answers.

Rules:

- One `vscode_askQuestions` call per cluster (1–4 related questions). Do not batch a whole category into one call.
- Use `options` with `multiSelect: true` for "pick all that apply"; `multiSelect: false` (default) for single-choice.
- Omit `options` entirely for genuinely freeform questions (e.g. "describe the money-shot command").
- Keep `allowFreeformInput` at its default (true) so the user can always override the options with a typed answer — except for strict either/or gates (e.g. `SIGNED OFF` / `revise`).
- Fall back to markdown checkboxes only when `vscode_askQuestions` is not available (e.g. CLI mode, headless eval, or the tool is disabled).
- If the user cancels the question UI, fall back to a plain-text version of the same cluster in the next message rather than re-prompting with the UI.

### 4. Emit the Design Concept

When all twelve categories are covered and no surviving open questions block the design, write a single markdown document with this exact section layout:

```markdown
# Design Concept: <name>

> Status: DRAFT — awaiting user sign-off
> Interview conducted: <ISO date>
> Override log: <empty, or list of explicit user overrides — see "When the user pushes back">

## Purpose

## Scope

## Non-goals

## Stakeholders

## Inputs

## Outputs

## Failure modes

## Edge cases

## Security

## Performance

## Observability

## Rollback

## Open questions

## Sign-off

- [ ] User has read this document end to end.
- [ ] User accepts every section or has flagged required changes.
- [ ] User has typed `SIGNED OFF` (or equivalent) in chat.
```

Use prose plus tables where appropriate. Keep each section dense and concrete — no marketing language.

### 5. Wait for explicit sign-off

After emitting the Design Concept, the agent MUST stop and wait. The only acceptable next outputs are:

- Revisions to the Design Concept based on user feedback.
- An acknowledgement that the user has typed `SIGNED OFF` (or equivalent: `approved`, `ship it`, `go ahead`, `freigegeben`).

Only after sign-off may the agent produce code, infrastructure, tests, or any other build artefact.

## When the user pushes back

If the user says *"just write the code"*, *"skip the questions"*, or *"this is overkill"*:

1. **First override** — Politely restate that the interview *is* the deliverable for this turn, and that the Design Concept will make the eventual code cheaper and safer. Refuse once.
2. **Second override** — Comply. But log the override at the top of the Design Concept under `Override log:` with the verbatim user statement and a one-line note on which categories were therefore skipped or shallow. The override is now part of the audit trail.

Do not stall further than a single refusal. The skill is a discipline aid, not a gatekeeper.

## Pairs with

- [`Instructions/ubiquitous-language.instructions.md`](../../Instructions/ubiquitous-language.instructions.md) — once a `glossary.md` exists, the Design Concept must use canonical terms only.
- [`Skills/skill-creator/SKILL.md`](../skill-creator/SKILL.md) — the meta-skill for authoring new `SKILL.md` files; useful if the grilled deliverable is itself a skill.
- [`Skills/doc-coauthoring/SKILL.md`](../doc-coauthoring/SKILL.md) — the section-by-section refinement loop is the natural next stage after sign-off if the deliverable is a written document rather than code.

## Out of scope

- Code review (use the standard code-review prompt).
- Generating documentation from existing code (use `doc-coauthoring` or a technical-writer agent).
- Test authoring (waits until after sign-off).
- Architecture diagramming during the interview (allowed only inside the Design Concept once all twelve categories are covered).

## Attribution

Independent rewrite. Inspired by — but not derived from — the adversarial-interview pattern popularised by <https://github.com/mattpocockuk/skills>. Theoretical grounding: Brooks, F. P. (2010). *The Design of Design: Essays from a Computer Scientist*. Addison-Wesley.
