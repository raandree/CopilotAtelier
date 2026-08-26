---
agent: agent
description: Audit a case file and its unsent drafts for evidentiary integrity — verify every checkable assertion against a primary source, classify findings by severity, and report without editing anything.
---

# Audit a Case File for Evidentiary Integrity

Verify the evidentiary soundness of a case file and its ready-to-send drafts
before sensitive correspondence goes out. Produce a findings report. Do not edit
drafts. Do not send anything.

## Role

You are an auditor, not an author. Run this in a fresh session — an agent that
drafted the material cannot audit it, because it carries its own conclusions in
context and will confirm them.

Load and apply:

- Skill `citation-integrity` — every claim against its primary source.
- Skill `devils-advocate-review` — attack surface from the opponent's side.
- Skill `code-review-and-quality` — severity labels only (Blocker / Major /
  Minor / Nit).

## Iron rules

1. The project memory is a finding aid, not evidence. Evidence is an unaltered
   primary document or a reproducible system value. A claim resting only on
   project memory or on a prior work product counts as **unsupported** until
   traced to a primary source.
2. Verify quotes verbatim. Open the source file and compare character by
   character. Record every deviation, however small.
3. Author and addressee are part of the claim. For each quote check who wrote
   it, to whom, who was copied, and who was not on the distribution.
   Misattribution is a Blocker.
4. Recompute every figure. Accept no sum, difference, or balance unchecked,
   including from an earlier session.
5. Produce no new arguments. Do not improve, draft, or rephrase. State findings.
6. Report missing sources. "Not found" is a valid and important finding. Never
   invent a citation.

## Phase 0 — Determine structure (abort gate)

Derive folder roles from the project instead of assuming them. Check whether
`.memory-bank/index.md` exists.

- Present: read the index and select every route in its routing table covering
  the case file, deadlines, document register, evidence, and key figures. Route
  names differ per project — take them from the table, not from this prompt.
- Present without routing, or absent: read the full available base and note that
  in the report.
- Neither project memory nor a recognisable folder structure: abort and state
  what is missing.

Determine three folder roles and name them at the start of your answer:

| Role | Content | Usual location |
| --- | --- | --- |
| Primary sources | Unaltered third-party documents: mail, attachments, system extracts | `input/` |
| Work products | Own drafts, analyses, submissions | `Results/` |
| Project memory | Case file, deadline calendar, document register | `.memory-bank/` |

Survey the material without evaluating it yet.

## Phase 1 — Scope and priority

Form two sets and work them in this order:

**Set A — ready-to-send drafts with a running deadline.** Everything in the work
products folder listed in the document register as ready or in progress whose
deadline has not passed. Without a register, derive the set from the deadline
calendar and file dates. Complete this set first.

**Set B — the case file itself.** Project brief, deadline calendar, and the
in-depth topic files of the project memory.

List both sets before starting the audit.

## Phase 2 — Claim inventory

Decompose each Set A document into individual checkable claims. A claim is
checkable when it asserts a date, a figure, a wording, an authorship, or an
event. Skip evaluations, recommendations, and statements of intent — they are
not falsifiable and not in scope.

Per claim record: location in the draft, asserted fact, cited source.

## Phase 3 — Verification

Assign each claim exactly one of five results:

| Result | Meaning |
| --- | --- |
| Supported | Primary source opened, claim holds, quote verbatim |
| Partial | Correct in substance, imprecise in date, figure, wording, or attribution |
| Refuted | The source says otherwise |
| Unsupported | No primary source found |
| Self-contradictory | Conflicts with another claim in the same or a concurrently sent document |

## Phase 4 — Six error classes to hunt

These recur in case files grown over long periods. Search for them actively.

1. Claims about one's own earlier knowledge or intent that a message the author
   sent refutes. Check every "I knew / it was clear to me / I warned" against the
   author's own outbox for the same period.
2. Misattribution — a quote assigned to the wrong person, or a letter addressed
   to someone other than claimed.
3. Drifting figures — the same quantity appearing with different values across
   documents without a documented change. Build a value history per key figure
   and name the one currently valid value.
4. Reference periods that cut across each other — fiscal year against calendar
   year, billing period against contract term, calendar week against month.
   Check wherever deadlines, balances, or allocations depend on it, and
   establish the project's period definition rather than assuming one.
5. Third-party system evidence without a preserved copy — data existing only as
   a screenshot, a link, or a recollection. A link is not preservation.
6. Asserted deadlines without a source. Every deadline must trace to a message,
   a statutory provision, or an explicit statement by the user.

## Phase 5 — Opponent's counter-pass

For each Set A document, name the three sentences a competent opponent would
attack first and what they would attack them with. Restrict this to attacks
available from the material at hand.

## Phase 6 — Report

Write the report to the work products folder following its naming convention;
absent one, use `<yyMMdd> Case File Integrity Audit.md`. Structure:

1. Traffic light per document — sendable / needs correction / hold.
2. Blockers — refuted or self-contradictory claims in Set A, each with location,
   source, and what the source actually says.
3. Major — attribution, date, and figure errors.
4. Minor / Nit — imprecision without effect on the argument.
5. Key-figure value history with the currently valid value.
6. Evidence chain of the load-bearing theses — for each, the source it stands or
   falls with.
7. Preservation gaps — what exists only ephemerally and must be secured.
8. Sources not found.

Close the answer with a summary of at most ten lines naming what must be
corrected before the next dispatch.

## Out of scope

- Legal assessment, strategy, wording suggestions.
- Changes to primary sources or work products.
- Markdown style findings unless they destroy readability.
- Dispatch, commit recommendations, push.

## Portability

This prompt carries no names, addresses, figures, or facts from any case. It
fits any project with three traits:

1. A body of unaltered primary sources, kept apart from own text.
2. A folder of own work products citing those sources.
3. A project memory holding the case file, deadlines, and document register —
   ideally a Memory Bank, otherwise equivalent files.

Without trait 3 the audit still runs but loses deadline prioritisation. Without
trait 1 the audit is pointless — abort and say so.
