---
agent: software-engineer
description: Systematic multi-phase refactoring workflow with analysis, planning, implementation, and validation.
---

# Structured Code Refactoring

Perform a systematic, multi-phase refactoring of code with analysis, planning, implementation,
and validation steps.

## Instructions

Follow this structured workflow to refactor code safely and effectively. Each phase must
complete before moving to the next.

## Phase 1 — Analyze

1. **Read the code** to be refactored. Understand its current structure, responsibilities,
   and dependencies.

2. **Identify the problems** — look for:
   - Long functions (>50 lines)
   - Deeply nested conditionals (>3 levels)
   - Code duplication (similar logic in multiple places)
   - Mixed responsibilities (one function doing too many things)
   - Poor naming (unclear variable/function names)
   - Magic numbers or hardcoded values
   - Missing error handling
   - Tight coupling between components
   - Dead code or unused variables
   - Overly complex expressions

3. **Check for tests** — before refactoring, verify:
   - Are there existing tests covering this code?
   - What is the current test coverage?
   - Will the refactoring break any existing tests?

4. **Document findings** — list each problem with:
   - File and line number
   - Description of the issue
   - Severity (must-fix, should-fix, nice-to-have)

## Phase 2 — Plan

1. **Determine the refactoring strategy** — select from common patterns:
   - **Extract Function/Method**: Move a block of code into a named function
   - **Rename**: Improve naming for clarity
   - **Consolidate Conditionals**: Simplify complex if/else chains
   - **Replace Magic Numbers**: Extract to named constants
   - **Reduce Nesting**: Use early returns, guard clauses
   - **Split Function**: Break a large function into smaller focused ones
   - **Remove Duplication**: Extract shared logic into a common function
   - **Introduce Parameter Object**: Replace long parameter lists with a single object
   - **Replace Flags with Polymorphism**: Use parameter sets or types instead of boolean flags

2. **Order the changes** — plan the sequence of edits to minimize risk:
   - Start with renames and formatting (low risk)
   - Then structural changes (medium risk)
   - Then behavioral changes (higher risk)

3. **Identify acceptance criteria** — what must remain true after refactoring:
   - All existing tests still pass
   - Public API/interface unchanged (unless explicitly modernizing)
   - No new PSScriptAnalyzer warnings
   - Behavior is identical (refactoring changes structure, not behavior)

4. **Present the plan** to the user with:
   - List of changes in order
   - Risk assessment for each change
   - Estimated impact (files and lines affected)

## Phase 3 — Implement

1. **Make one change at a time** — each edit should be atomic and independently verifiable.

2. **Follow the planned order** — do not skip ahead or combine steps.

3. **Preserve behavior** — after each change:
   - The code should produce the same output
   - Error handling should remain equivalent
   - Pipeline behavior should be unchanged

4. **Apply coding standards** — use the project's instruction files for:
   - Naming conventions
   - Formatting rules
   - Error handling patterns
   - Documentation requirements

5. **Add or update tests** if the refactoring:
   - Introduces new functions (add unit tests)
   - Changes function signatures (update existing tests)
   - Extracts logic that was previously untested (add coverage)

## Phase 4 — Validate

1. **Run existing tests** to verify nothing is broken:
   ```powershell
   .\build.ps1 -Tasks test
   ```

2. **Run linting** to check for new warnings:
   ```powershell
   Invoke-ScriptAnalyzer -Path ./source -Recurse -Severity Warning,Error
   ```

3. **Compare behavior** — if possible, run the code before and after to verify identical results.

4. **Review the diff** — summarize what changed:
   - Functions added/removed/renamed
   - Parameters changed
   - Lines of code before vs after
   - Complexity reduction (fewer nested levels, shorter functions)

5. **Report results** in a summary:

```markdown
## Refactoring Summary

### Changes Made
| # | Change | Type | Files |
|---|---|---|---|
| 1 | Extracted validation logic into `Test-Parameters` | Extract Function | `Get-Widget.ps1` |
| 2 | Renamed `$x` to `$widgetCount` | Rename | `Get-Widget.ps1` |

### Metrics
| Metric | Before | After |
|---|---|---|
| Total lines | 250 | 230 |
| Max function length | 85 | 32 |
| Max nesting depth | 5 | 2 |
| Functions | 3 | 5 |
| PSScriptAnalyzer warnings | 4 | 0 |

### Test Results
- All existing tests pass: ✅
- New tests added: 2
- Coverage change: 72% → 81%
```
