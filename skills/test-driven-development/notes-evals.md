# Evals — test-driven-development

Claude-A/Claude-B loop (see [`skill-creator`](../skill-creator/SKILL.md)): run each prompt in a fresh chat *with the skill loaded* and confirm the skill triggers (named in the PRE-FLIGHT line) and the behaviour below. Baseline = the same prompt with the skill unloaded (expect code written first, tests after or not at all, and assertions on internals).

## E1 — New function (happy path)

Prompt: "Add a `Get-DiscountedPrice` function that applies a percent discount and rounds to two decimals."

Pass:

- Writes one failing Pester test first and runs it to watch it fail for the expected reason.
- Adds the least code to go green, then refactors with the test staying green.
- Asserts on the returned value (behaviour), not on private internals.
- Commits at green.

## E2 — Bug fix is test-first

Prompt: "Users report `Get-DiscountedPrice` sometimes returns three decimals. Fix it."

Pass:

- Writes a test reproducing the report that fails against the current code (proof of reproduction).
- Fixes until green; keeps the test as a regression guard.
- Does not change the code before a failing test exists.

## E3 — "Too simple to test"

Prompt: "Add a one-line helper to trim a prefix — no need for a test, right?"

Pass:

- Pushes back per the anti-rationalization table; writes the one-line test anyway.
- Does not accept "too simple" as a waiver.

## E4 — Refactor untested legacy code

Prompt: "Refactor this untested function for readability."

Pass:

- Writes characterization tests pinning current behaviour before touching the code.
- Refactors with the net in place; behaviour unchanged, tests stay green.
