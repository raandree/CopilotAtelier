---
description: Multi-perspective peer review of a document (RFC, ADR, design doc, paper, long-form article) with a panel of distinct reviewers, a Devil''s Advocate, and a synthesising editor that produces an Accept / Minor / Major / Reject decision.
---

# Peer Review (Multi-Perspective Panel)

Run a structured peer review of the supplied document. The point is not to be
nice. The point is to surface every objection a sophisticated reader would
raise, score them honestly, and converge on a defensible decision.

## Inputs

- **Document**: the artefact under review (path or pasted content).
- **Document type**: paper / RFC / ADR / design doc / article / spec.
- **Audience**: who must accept it.
- **Decision required**: ship / revise / reject / unblock.

If any input is missing, ask once, then proceed with the most useful
assumption.

## Panel

Cast four reviewers. Each one stays in role for the whole review.

1. **Editor-in-Chief (EIC)** — owns the decision. Cares about scope fit,
   audience fit, and whether the document drives the decision it is supposed
   to drive.
2. **Reviewer 1 — Methodology / Architecture** — cares about *how*: is the
   approach sound, are the trade-offs acknowledged, are alternatives
   considered.
3. **Reviewer 2 — Evidence / Implementation** — cares about *whether it
   works*: are claims supported, do examples run, do numbers add up, do
   citations resolve.
4. **Reviewer 3 — Clarity / Audience** — cares about *whether it lands*: can
   the target reader follow it, are terms defined, is the narrative coherent.
5. **Devil''s Advocate (DA)** — applies the `devils-advocate-review` skill.
   Attacks premises, not just arguments. Concedes only at rebuttal score ≥ 4.

## Process

### Phase 1 — Independent pass (no cross-talk)

Each reviewer reads the document and produces:

- Three to five **strengths** (specific, with locator).
- Three to seven **issues**, each tagged with severity:
  - `critical` — blocks acceptance.
  - `major` — must be addressed before acceptance.
  - `minor` — should be addressed.
  - `nit` — optional.
- A **score 0–100** with one-sentence justification.
  - ≥ 80 = Accept
  - 65–79 = Minor revision
  - 50–64 = Major revision
  - < 50 = Reject

The DA does not score. The DA produces a list of surviving attacks per the
Devil''s Advocate closing report.

### Phase 2 — Cross-reviewer matrix

Build a matrix of issues × reviewers. Mark agreement.

- **Consensus issue** — flagged by ≥ 3 reviewers (counts double in the
  decision).
- **Split issue** — reviewers disagree on severity or existence.
- **DA-critical** — a surviving DA attack at premise level, regardless of
  whether the other reviewers raised it.

### Phase 3 — EIC synthesis

The EIC produces the final report. The EIC may not invent new issues; it can
only weight what the panel found. Decision rule:

| Condition | Decision |
|-----------|----------|
| Any `critical` issue OR any DA-critical premise attack unresolved | Reject or Major revision |
| Mean score < 50 | Reject |
| Mean score 50–64, or ≥ 2 `major` issues | Major revision |
| Mean score 65–79, or ≥ 2 `minor` issues with no `major` | Minor revision |
| Mean score ≥ 80 and no `major` issues | Accept |

If the panel splits hard (range > 25 points), the EIC must explain the split
in the report and choose the more conservative decision.

## Output Format

```markdown
# Peer Review — <document title>

**Document type**: <type>  
**Audience**: <audience>  
**Decision required**: <decision>  
**Reviewed**: <ISO date>

## Decision: <Accept / Minor revision / Major revision / Reject>

<One-paragraph rationale tied to the strongest surviving issues.>

## Scores

| Reviewer | Score | Justification |
|----------|-------|---------------|
| R1 Methodology | 72 | ... |
| R2 Evidence | 58 | ... |
| R3 Clarity | 81 | ... |
| Mean | 70 | — |

## Consensus Issues (flagged by ≥ 3 reviewers)

1. **[major]** ... — R1, R2, R3
2. ...

## Devil''s Advocate — Surviving Attacks

1. **Premise**: ...
2. ...

## Per-Reviewer Detail

### R1 — Methodology / Architecture (72)

**Strengths**
- ...

**Issues**
- `[major]` <locator> ...
- `[minor]` <locator> ...

### R2 — Evidence / Implementation (58)

...

### R3 — Clarity / Audience (81)

...

## Required Revisions (for the author)

Grouped by severity, each item actionable:

- **Critical**: ...
- **Major**: ...
- **Minor**: ...
```

## Rules of Engagement

- **No sycophancy.** Scores above 90 require specific, locator-anchored
  evidence. Default ceiling for a first review is 85.
- **No fabricated issues.** Every issue must point to a specific location in
  the document.
- **No memory facts.** If the review depends on a factual claim about an
  external source, hand that claim to the `citation-integrity` skill first.
- **Read-only.** This prompt does not edit the document. It produces a review
  the author then acts on.
- **One pass per invocation.** A re-review (after the author revises) is a
  fresh run of this prompt with the revised document and the previous review
  attached as input.

## Companion Skills / Prompts

- `devils-advocate-review` — supplies the DA reviewer''s behaviour.
- `citation-integrity` — verify any factual claim the document or the review
  depends on.
- `grammar-check` — separate pass, after the substantive review is resolved.
- `code-review.prompt.md` — for code artefacts specifically; this prompt is
  for documents.

## Attribution

The EIC + dynamic reviewers + Devil''s Advocate panel structure, 0–100 rubric
with decision mapping, and consensus-matrix synthesis are inspired by the
Academic Paper Reviewer design in the Academic Research Skills suite
(Imbad0202/academic-research-skills, CC BY-NC 4.0). This prompt is an
independent rewrite generalised to non-academic documents and is not derived
from that project''s source files.
