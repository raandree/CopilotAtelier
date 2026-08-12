# Migrating Pester v4 to v5

Reference for moving an existing suite onto the Pester 5 engine. Run
[`../scripts/Find-PesterV4Pattern.ps1`](../scripts/Find-PesterV4Pattern.ps1)
first to size the work; this file explains what each finding means and what to
replace it with.

## Why a careless migration passes and lies

Pester 5 runs a suite in two phases. **Discovery** executes every
`Describe`/`Context` body to build the test tree; **Run** executes only the
`It` bodies and the `Before*`/`After*` blocks. Three consequences drive the
whole migration:

- Code that used to run "inside a `Describe`" now runs during Discovery, once,
  before any test executes.
- A mock is scoped by **where it is placed**, not by the enclosing
  `Describe`/`Context`.
- `Should -Throw` matches with `-like`, not with `.Contains`.

A file can therefore migrate cleanly enough to pass while asserting something
weaker than it did before. Capture a baseline test count before the first edit
and compare after every file: a count that dropped means a test was silently
skipped, not that the suite got faster.

## Order of work

1. Commit or stash, then record the baseline result count.
2. Run the detection script and treat its output as the worklist.
3. Fix **structure** first (the findings below marked *structural*). Nothing
   else is trustworthy until Discovery is clean.
4. Fix assertions and mocks.
5. Fix the runner: `Invoke-Pester` calls, CI scripts, build tasks.
6. Re-run after every file, not at the end.

## Structural rules

| Finding | Rule |
|---|---|
| `TopLevelCommand` | No command at file top level. Legal only when it builds `-ForEach` data — and then it belongs in `BeforeDiscovery`. |
| `BlockBodyCommand` | No code directly in a `Describe`/`Context` body. Shared setup goes in `BeforeAll`, per-test setup in `BeforeEach`. |
| `LegacyPathDiscovery` | `$MyInvocation.MyCommand.Path` returns nothing inside a Pester 5 `BeforeAll`. Use `$PSScriptRoot` or `$PSCommandPath`. |
| `InModuleScopeWrapper` | Never wrap `Describe`/`Context`/`It` in `InModuleScope`. It skips export validation, hides the exported surface, and slows Discovery. |

Import the code under test inside `BeforeAll`:

```powershell
BeforeAll {
    . $PSScriptRoot/Get-Thing.ps1
    # or the sibling script:  . $PSCommandPath.Replace('.Tests.ps1', '.ps1')
    # or a module:            Import-Module $PSScriptRoot/MyModule.psd1 -Force
}
```

Scope rules that catch people out:

- A variable set in `BeforeAll` is visible to child blocks but **read-only**
  there; each test gets its own copy.
- `BeforeEach`, `It`, and `AfterEach` share one scope, so `AfterEach` can see
  what an `It` created.
- A variable created during Discovery is **not** visible inside `It` or
  `BeforeAll`. Pass it in through `-ForEach`/`-TestCases`.
- Helpers used inside `It` must be defined in `BeforeAll` — see Pattern 14 in
  [`../SKILL.md`](../SKILL.md). The symptom is a misleading
  `CommandNotFoundException`.

## Assertions

| v4 | v5 |
|---|---|
| `Should Be x` | `Should -Be x` |
| `Should BeExactly x` | `Should -BeExactly x` |
| `Should Not BeNullOrEmpty` | `Should -Not -BeNullOrEmpty` |
| `Should Throw 'msg'` | `Should -Throw '*msg*'` |
| `Should Match 'pattern'` | `Should -Match 'pattern'` |

`Should -Throw` is the one that changes meaning rather than syntax: matching is
`-like`, so an unwrapped string demands an exact message and fails on anything
longer.

## Mocks

| v4 | v5 |
|---|---|
| `Assert-MockCalled Foo -Times 1` | `Should -Invoke Foo -Times 1` |
| `Assert-VerifiableMock` / `Assert-VerifiableMocks` | `Should -InvokeVerifiable` |

Behaviour changes that survive a pure token replacement:

- **Placement is scope.** A mock in `BeforeAll` covers that block and its
  children; a mock inside an `It` covers only that `It`. Re-check every
  `-Times`/`-Exactly` after moving one.
- **Counting follows the caller.** `Should -Invoke` defaults to `It` scope when
  called from `It`, `BeforeEach`, or `AfterEach`, and to the containing
  `Describe`/`Context` scope when called from `BeforeAll`/`AfterAll`. Override
  with `-Scope It`, `-Scope Context`, or `-Scope Describe` when the assertion
  and the calls live in different blocks.
- **Commands called inside a module need `-ModuleName`.** A plain `Mock` only
  intercepts calls made from the test script:

  ```powershell
  Mock -ModuleName MyModule -CommandName Get-Content -MockWith { 'stub' }
  Should -Invoke -ModuleName MyModule -CommandName Get-Content -Times 1
  ```

  Inside an `InModuleScope MyModule { ... }` block the `-ModuleName` is
  implicit and must be omitted.
- **`-ParameterFilter` needs no `param()` block.** Reference the mocked
  command's parameters directly, for example `{ $Path -eq 'C:\temp' }`.
- **Read bound parameters with `$PesterBoundParameters`** inside a mock body
  (Pester 5.2+). The mock hook overwrites `$PSBoundParameters`.

## The runner

| v4 parameter | v5 |
|---|---|
| `-Script` | `-Path` (paths only; a hashtable is rejected) |
| `-TestName` | `-FullNameFilter` |
| `-Show` | `-Output` with `None`, `Normal`, `Detailed`, or `Diagnostic` |
| `-PesterOption` | removed |
| `-Strict` | removed |

Anything beyond a bare path belongs in the configuration object:

```powershell
$configuration = New-PesterConfiguration
$configuration.Run.Path = './tests'
$configuration.Run.PassThru = $true
$configuration.Run.Exit = $false
$configuration.Output.Verbosity = 'Detailed'

$result = Invoke-Pester -Configuration $configuration

if ($result.FailedCount -gt 0)
{
    throw ('Pester failed {0} test(s).' -f $result.FailedCount)
}
```

`-PassThru` and `-Configuration` are different parameter sets; set
`Run.PassThru` instead of combining them. For CI that still consumes the v4
result shape, convert with `ConvertTo-Pester4Result`, or emit NUnit output with
`ConvertTo-NUnitReport`.

## Validation gate

Run the suite after **every** file, through the detached launcher described in
Pattern 0 of [`../SKILL.md`](../SKILL.md), and require:

- zero failed tests;
- **zero Discovery errors** — a Discovery error means the structural work in
  this file is incomplete, and it suppresses whole files rather than single
  tests;
- a test count equal to the baseline.

## Completion checklist

- [ ] Baseline count captured before the first edit.
- [ ] Detection script clean, or every remaining finding adjudicated in writing.
- [ ] No command at file top level except `-ForEach` data in `BeforeDiscovery`.
- [ ] Code under test imported in `BeforeAll` via `$PSScriptRoot`.
- [ ] Every `Should` dashed; every `Should -Throw` wrapped in `*`.
- [ ] `Assert-MockCalled` and `Assert-VerifiableMock(s)` replaced, and every
      `-Times` re-checked against the new mock placement.
- [ ] Commands called inside a module mocked with `-ModuleName`.
- [ ] `InModuleScope`, if kept at all, sits inside an `It`.
- [ ] Runner and CI scripts moved to the configuration object.
- [ ] Suite green, no Discovery errors, count matches the baseline.
- [ ] `#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5.0' }`
      added or updated where the file declared a v4 requirement.

## See Also

- [Migrating from Pester v4 to v5](https://pester.dev/docs/migrations/v4-to-v5)
- [Breaking changes in v5](https://pester.dev/docs/migrations/breaking-changes-in-v5)
