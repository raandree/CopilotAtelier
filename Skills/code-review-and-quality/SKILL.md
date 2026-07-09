---
name: code-review-and-quality
description: >-
  A reusable five-axis code-review workflow for PowerShell/DSC changes: review
  for design, correctness, complexity, tests, and clarity/naming; size changes
  to stay reviewable; label findings by severity (Blocker / Major / Minor / Nit);
  separate must-fix from opinion; and keep review turnaround fast. The bar is
  "would a senior engineer approve this?"
  USE FOR: code review, review this change, PR review, reviewer checklist, review
  standards, severity labels, nit vs blocker, change sizing, reviewable diff,
  what to look for in a review, approve or request changes, review feedback tone,
  self-review before pushing.
  DO NOT USE FOR: the multi-phase PowerShell security review with SARIF/CVSS (use
  the code-review prompt or the security-reviewer agent), agentic/LLM security
  review (use agent-security-review), adversarial critique of a design or document
  (use devils-advocate-review), multi-perspective document peer review (use the
  peer-review prompt).
---

# Code Review & Quality

A structured workflow for reviewing a code change — as the reviewer, or as the author self-reviewing before asking for one. Scope is general engineering quality, PowerShell/DSC-flavoured. For a dedicated security audit use the [`code-review`](../../Prompts/code-review.prompt.md) prompt (SARIF + CVSS via the security-reviewer agent) or [`agent-security-review`](../agent-security-review/SKILL.md) for LLM/agent wiring; for adversarial design critique use [`devils-advocate-review`](../devils-advocate-review/SKILL.md).

## When to Use

- Reviewing a pull request or a diff before it merges.
- Self-reviewing your own change before you push or open a PR.
- Setting or applying a consistent review standard across a team.

## The five axes

Review every change against these, in order — design first, because a well-named typo is cheap and a well-tested wrong design is not:

1. **Design.** Does the change belong here? Does it fit the module's structure and surrounding patterns, or bolt on a parallel way of doing the same thing? Is the public surface (parameters, output objects) the one you want to live with?
2. **Correctness.** Does it do what it claims across the real input range — empty, `$null`, pipeline vs parameter, large input, non-ASCII, wrong types? Are error paths handled (`-ErrorAction Stop`, `try/catch`) rather than swallowed?
3. **Complexity.** Is it as simple as it can be for what it does? Flag dead code, needless indirection, and cleverness a maintainer must decode. Do not require more generality than the task needs.
4. **Tests.** Is the new behaviour covered by a test that would fail without the change? Do the tests assert behaviour, not internals? See [`test-driven-development`](../test-driven-development/SKILL.md) and [`pester-patterns`](../pester-patterns/SKILL.md).
5. **Clarity & naming.** Approved verbs (`Get-Verb`) and intention-revealing names; comments explain the reason, not the mechanics; consistent terminology. See [`powershell.instructions.md`](../../Instructions/powershell.instructions.md).

## Severity labels

Label every comment so the author knows what blocks the merge:

| Label | Meaning | Blocks merge? |
|---|---|---|
| Blocker | Bug, security hole, data loss, broken build or test. | Yes |
| Major | Wrong design or missing tests that will cost later. | Yes |
| Minor | Real but small; safe to fix in a follow-up. | No |
| Nit | Style or preference. Prefix the comment with "Nit:". | No |

Separate must-fix from opinion. If a comment is your preference, say so; do not hold a change hostage to taste. Praise what is genuinely good — review is not only fault-finding.

## Size the change

Small changes get real reviews; large ones get rubber-stamped. Keep a reviewable diff focused on one logical change; split unrelated refactors, renames, and reformatting into their own commits or PRs so the substance is not buried in noise. If a change is too big to review well, the right feedback is "split this", not a shallow approval.

## Speed and tone

- Review promptly — a change in review blocks the author; a fast, focused pass beats a slow, exhaustive one.
- Be specific: cite the file and line, and propose the concrete alternative rather than a vague objection.
- Critique the code, not the author. Ask questions where intent is unclear instead of asserting fault.

## Author self-review first

Before requesting review, clear the [Definition of Done](../../Reference/definition-of-done.md): `Invoke-ScriptAnalyzer` clean, Pester green (separate process), approved verbs, Memory Bank and CHANGELOG updated. Read your own diff top to bottom first — most Nits should never reach the reviewer.

## Anti-rationalization table

| Rationalization | Reality |
|---|---|
| "It works, so it's fine to approve." | Working is the floor. Design, tests, and clarity are what the review is for. |
| "The diff is huge but it's mostly mechanical." | Mechanical noise hides real changes. Ask for a split so the substance is reviewable. |
| "I'll just fix it myself and approve." | Silent rewrites erase the author's intent and the review trail. Comment; let them fix. |
| "No tests, but I trust the author." | Trust is not coverage. Untested behaviour is unverified behaviour. |

## Red flags

- Approving a change you did not read end to end.
- A diff too large to review, approved anyway.
- Blocking a merge over pure preference, unlabelled as a Nit.
- No tests accompany a behaviour change, and it passes review.
- Review comments attack the person rather than the code.

## Verification

A review is done when:

- All five axes were considered and every comment is severity-labelled.
- No Blocker or Major is left unresolved before approval.
- The change (author side) clears the [Definition of Done](../../Reference/definition-of-done.md).
- The decision is explicit: approve, or request changes with the specific must-fix list.

## Related

- [`code-review`](../../Prompts/code-review.prompt.md) prompt and the security-reviewer agent — deep security review with SARIF + CVSS.
- [`agent-security-review`](../agent-security-review/SKILL.md) — reviewing agent, LLM, or MCP wiring.
- [`devils-advocate-review`](../devils-advocate-review/SKILL.md) — adversarial critique of a design or claim.
- [`test-driven-development`](../test-driven-development/SKILL.md), [`pester-patterns`](../pester-patterns/SKILL.md) — the testing axis.
