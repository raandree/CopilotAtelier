---
name: test-driven-development
description: >-
  Test-first workflow for PowerShell and DSC work: the red-green-refactor loop,
  writing a failing Pester 5 test before the code, the test pyramid (unit-heavy),
  DAMP-over-DRY test readability, choosing what and at which level to test, and
  making behaviour changes test-first rather than test-after. Enforces "no
  production change without a covering test" as a checkable gate.
  USE FOR: TDD, test-driven development, test first, red green refactor, write
  the test first, failing test before code, what should I test, test pyramid,
  unit vs integration test, coverage discipline, regression test for a bug,
  characterization test, DAMP tests, arrange act assert, testable design.
  DO NOT USE FOR: Pester recipes and mocking templates (use pester-patterns),
  diagnosing a failing build or test (use sampler-build-debug), Pester syntax
  (see pester.instructions.md), running tests without freezing VS Code (see
  powershell-execution-safety.instructions.md), evaluating skills/prompts/agents
  (use agent-evals).
---

# Test-Driven Development

The discipline of writing the test before the code, for PowerShell modules and DSC configurations. This skill is the workflow — the loop, what to test, and the gates. It is not a Pester tutorial: for mocking recipes and templates use [`pester-patterns`](../pester-patterns/SKILL.md), for Pester 5 syntax see [`pester.instructions.md`](../../Instructions/pester.instructions.md), and to run tests without freezing VS Code see [`powershell-execution-safety.instructions.md`](../../Instructions/powershell-execution-safety.instructions.md).

## When to Use

- Implementing a new function, class, or DSC resource behaviour.
- Fixing a bug — the failing test reproduces it before the fix lands.
- Changing existing behaviour where a regression would go unnoticed.
- Hardening untested legacy code before refactoring it.

## The loop: Red → Green → Refactor

One behaviour at a time. Never write production code with no failing test demanding it.

1. **Red.** Write one small Pester test for the next slice of behaviour. Run it; watch it fail for the reason you expect — an assertion fails, not a typo, missing file, or parse error. A test that passes on first run tests nothing new.
2. **Green.** Write the least code that makes the test pass. Resist gold-plating; the test defines done for this slice.
3. **Refactor.** With the test green, improve names, remove duplication, extract helpers — re-running the test after each step. Green stays green.

Commit at green (see [`git.instructions.md`](../../Instructions/git.instructions.md)); each commit is a working save point.

## What to test, and at which level

Follow the test pyramid — many fast unit tests, fewer integration tests, a thin end-to-end layer:

| Level | Scope | In this repo |
|---|---|---|
| Unit | One function/class, dependencies mocked | Most tests. Pure logic, parameter validation, error paths. |
| Integration | A module against a real boundary | Build tasks, a module against a temp file tree or a local DB. |
| End-to-end | The whole configuration on a node | A DSC config applied to a lab VM; slow, few, high value. |

Test behaviour, not implementation: assert on outputs, state changes, and errors a caller can observe, not on private internals — or the tests break on every refactor.

## Write the failing test first

Arrange-Act-Assert, one behaviour per `It`. Keep tests DAMP (Descriptive And Meaningful Phrases) over DRY — a reader should see the whole scenario without chasing helpers:

```powershell
Describe 'Get-DiscountedPrice' {
    It 'applies the percentage and rounds to two decimals' {
        # Arrange
        $price = 19.99
        # Act
        $result = Get-DiscountedPrice -Price $price -Percent 10
        # Assert
        $result | Should -Be 17.99
    }
}
```

To mock a file system, REST call, DSC resource, or credential, do not hand-roll it — pull the pattern from [`pester-patterns`](../pester-patterns/SKILL.md).

## Bug fixes are test-first too

1. Write a test that reproduces the bug from the report. It must fail against the current code — that failure is proof you have actually reproduced it.
2. Fix the code until the test goes green.
3. Keep the test. It is now a regression guard; if the bug returns, this test catches it.

## Characterization tests for legacy code

Before refactoring untested code, pin its current behaviour: write tests that assert what it does today, even if imperfect. They are the safety net proving the refactor changed structure, not behaviour. Only once the net is in place do you touch the code.

## Anti-rationalization table

| Rationalization | Reality |
|---|---|
| "I'll write the tests after it works." | Test-after rationalises the code you already wrote and skips the cases you did not think of. The failing test first is the spec. |
| "This is too simple to test." | Simple code with a test costs minutes; a silent regression costs hours. Write the one-line test. |
| "The test is hard to write." | Hard-to-test usually means hard-to-use design. Let the test pressure the interface before the code sets it in stone. |
| "It passed the first time, good." | A test that never went red proves nothing. Break the code deliberately once to confirm the test can fail. |

## Red flags

- Writing production code with no failing test currently demanding it.
- A brand-new test passes on the very first run.
- Tests assert on private state, so any refactor turns them red.
- A bug fix ships with no test that fails without the fix.
- `Should` assertions removed or loosened to make a red test pass.

When a red flag fires, stop and restore the loop — do not push code past a broken or absent test.

## Verification

A change is done under this skill only when:

- The new or changed behaviour has a test that failed before the code and passes after it.
- The full suite is green, run in a separate process per [`powershell-execution-safety.instructions.md`](../../Instructions/powershell-execution-safety.instructions.md).
- `Invoke-ScriptAnalyzer` is clean on the changed files.
- The change clears the [Definition of Done](../../Reference/definition-of-done.md).

State the evidence: the test name, that it was red then green, and the passing suite summary.

## Related

- [`pester-patterns`](../pester-patterns/SKILL.md) — mocking recipes and test templates.
- [`sampler-build-debug`](../sampler-build-debug/SKILL.md) — when a build or test fails and needs diagnosis.
- [`agent-evals`](../agent-evals/SKILL.md) — the analogue of TDD for skills, prompts, and agents.
