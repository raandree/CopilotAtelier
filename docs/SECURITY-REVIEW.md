# Security reviews

Independent security and quality reviews of changes to Copilot Atelier, newest
first. Each entry records the scope, the verdict, every finding with its
severity and resolution, and the risks that remain.

## 2026-11-14: the module path of every hook line, R12-02 and R12-08 (follow-up of prompt P5)

Brief 18 closes, for the hook lines, the exposure of the guard that the review of brief 12 left
open (R12-02, R12-08). Windows PowerShell 5.1, which runs every hook line under VS Code, and pwsh,
which runs it under the Copilot SDK host, load a command such as `Get-Variable` from the first
module on their module path that exports it, and the account that runs the hook can put a module
there. On copies, a module that exports `Get-Variable`, first on the module path, in the account's
own module folder, or in the working directory of a 5.1 whose documents folder did not resolve,
turned the exit 2 of a denial into exit 0. Every PowerShell hook line, the 15 of `hooks.json` and
the 3 of the contributor-profile asset, now pins the module path of each PowerShell process it runs
in to that interpreter's own `Modules` folder before it resolves a command by name, in the inner
command and in the closing statement, with type names only. `HookContract` accepts only the new
closing statement and runs every payload with a tripwire module of its own where the PowerShell of
each spawn looks first. No hook script changes. The design was chosen out of three, hook lines that
rely on no auto-loaded command (option 1), a `HookContract` that measures with the module path a
logon gives (option 2), and both, and was decided as both, with the tripwire as the second half,
under the owner's delegation for the local branch (the handoff ledger, 2026-11-14); merging brief
18 is the owner's explicit answer. The Custom `security-reviewer` agent reviewed `4667dd7` in a fresh
context, read-only, with probes on copies under TEMP, and said **Request changes**: the pin holds
for the shipped lines, but `HookContract` passed three hand-edited copies of the line that a planted
module then beat (R18-01, Major), two records said more than holds (R18-02 and R18-03, Minor), and
five Nits (R18-04 to R18-08). The controller ruled to fix all eight in one round, under the owner's
delegation (the handoff ledger, 2026-11-14); the fix round does that, and `HookContract` now also
holds the `-Command` text of a pinned line to the pin, with the tripwire as a second net. The same
reviewer re-reviewed the fix round, `34de586`, and said **Approve with changes**: seven findings
resolved, R18-07 deferred as ruled, and one new Minor, R18-09: six hand edits made after the pin
still pass `HookContract` while a planted module or script answers for the guard, and the records
said that more is refused than is. The controller ruled the reviewer's records option under the
owner's delegation (the handoff ledger, 2026-11-14): the records state the full residual and what
the check refuses, and tell operators to keep the inner command text exactly as shipped; holding the
whole `-Command` text to the shipped template goes to the backlog.

### Scope

- Does a module that exports a command of a hook line or of its script still answer for it, when it
  stands first on the module path a spawn inherits, in either personal module folder, or in the
  working directory of a 5.1 whose documents folder does not resolve, under `cmd.exe`, the Windows
  PowerShell 5.1 wrapper of VS Code, and the PowerShell 7 wrapper of the Copilot SDK host?
- Does the closing statement keep its exit code in every case: 0, 1, 2, 7 and -1 from the inner
  program, an inner program that never started, and no native command at all?
- Does the grant recorder record only what the prompt holds, and drop nothing that it holds, while
  such a module stands first?
- Does `HookContract` refuse the old closing statement, and fail a line that resolves a command
  before it pins its module path, naming the spawn?
- Do the hooks README, the CHANGELOG and this entry claim only what is shown?

### Design

- **The pin.** The inner `-Command` of every launcher starts with
  `[Environment]::SetEnvironmentVariable('PSModulePath', [IO.Path]::Combine([AppContext]::BaseDirectory, 'Modules'))`,
  and the closing statement of `windows` and `powershell` makes the same call first, inside its
  expression, where it adds nothing to the array:
  `exit (@(<the call>) + @(Get-Variable -Name LASTEXITCODE -ValueOnly -ErrorAction Ignore) + 2)[0]`,
  `+ 1` for the lifecycle events. The call names only `[Environment]`, `[IO.Path]` and
  `[AppContext]`, types that the language resolves and no module can answer for, and holds no `$`,
  which the outer PowerShell of VS Code would expand. `[AppContext]::BaseDirectory` is `$PSHOME`, the
  folder of the interpreter that runs the call, so 5.1 gets
  `%SystemRoot%\System32\WindowsPowerShell\v1.0\Modules` and pwsh its own `Modules` folder. Measured
  with Windows PowerShell 5.1.26100.33822 and pwsh 7.6.10: a `PSModulePath` set in a running process
  decides where both auto-load the next command from, and the personal folder that pwsh puts first
  at its start goes with the rest of the old value.
- **What it covers.** Every command that a hook line or its script resolves by name, in every
  PowerShell process of the line: the wrapper a host starts and the interpreter the line starts. In
  the interpreter the line starts, the pin is the first statement. In the wrapper, the only name
  resolved before the closing statement is the program the line starts, and the closing statement
  pins before it names `Get-Variable`. That program comes from `PATH`, or from its absolute path in
  a pinned line, and not from a module, with one exception the review measured (R18-02): when the
  `PATH` that VS Code hands its Windows PowerShell 5.1 holds no `powershell`, that 5.1 looks for a
  command of that name in the modules of the path it inherited, before any pin. pwsh puts its own
  folder first on its `PATH`. Apart from that condition, no command is taken from a module before
  the pin.
- **The text of the pin.** `HookContract` holds the `-Command` text of a pinned line to the pin, as
  it holds the line's end to the closing statement (R18-01): the interpreter has to get its text
  with `-Command`, the text has to start with `try { ` and the pin, compared as typed
  (`HookCommandHead`), and it may not name `PSModulePath` again after it, in any case. Refused before
  anything runs (`Get-HookPinProblem`) are a line whose `-Command` text does not start with that
  exact pin, which includes one that resolves a name before the pin through an alias or a
  module-qualified name and one that pins another folder first; a later mention of `PSModulePath`
  by name; a line that runs its script with `-File` or `-EncodedCommand`; a line that names no
  command; and, as before, a closing statement other than the exact one. The rest of the text after
  the pin is not read, and the re-review passed six hand edits there (R18-09): setting the module
  path again under another spelling (a computed name with `[Environment]::SetEnvironmentVariable` or
  `New-Item Env:`, an `Env:PSModuleP*` wildcard), running code by path (`Import-Module` by path, an
  alias to a script by path), and starting a nested pwsh, which puts the account's personal folder
  first again. A line derived from the shipped command holds none of them.
- **The tripwire.** `HookContract` writes a module of its own, `ContainmentTripwire`, which exports
  every command of the Verb-Noun shape that the line, its `-Command` text and the pinned script name
  (`Get-HookTripwireName`), and which, when it is imported, appends to a marker file and ends the
  process with exit 0, as a module that answers for the guard would. The three payloads run with it
  first on `PSModulePath` and in both personal module folders of a decoy profile under `cmd.exe` and
  the PowerShell 7 wrapper. The Windows PowerShell 5.1 wrapper is first asked, once and with no
  command name, under a decoy profile without a documents folder and with the machine's
  `PSModulePath`, or with none where the machine sets none, which folder it looks in first (R18-04,
  R18-06). When it names the relative `WindowsPowerShell\Modules`, the payloads run under it with
  the tripwire in its working directory; when it names a rooted folder, as with a documents folder
  redirected to a fixed path or a `PSModulePath` of the account, or cannot be asked, they run with
  the tripwire first on its path, and the evidence says which. A line that loads it fails, and the
  evidence names each spawn that did. Since the fix round it is a second net: it sees only the names
  a line spells, so an alias, a module-qualified name or a pin to another folder passed it, which is
  why the text is held to the pin.
- **What does not change.** The guard, the grant recorder and every other hook script keep their
  digests, and so does the ledger appender.

### Verdict

**Request changes** for `4667dd7`. The reviewer found the pin holding in every process of all 18
lines, under both interpreters and all three spawns, with a tripwire of 5,383 command names and
decoys named like the modules PowerShell imports by name, in each place a module can sit; the old
lines were bypassed in 11 of 12 runs. Exit codes, the grant recorder and the lifecycle output were
unchanged. It requested changes for the second half of the design: `HookContract` did not hold an
operator's pinned line to the pin (R18-01), and the records claimed a little more than holds. The
fix round answers all eight findings.

**Approve with changes** for the fix round, `34de586`, in a scoped re-review by the same reviewer.
`HookContract` refused each of the reviewer's three copies and the second assignment by name before
anything ran, and the contained shipped line still passed with 0, 2 and 2 under `cmd.exe` and both
wrappers; R18-01 to R18-06 and R18-08 are resolved and R18-07 deferred as ruled. The re-review's own
runs gave 585 passed, 0 failed, 80 skipped for `tests/HookLauncher.Tests.ps1` and 384 passed, 0
failed, 1 skipped for `tests/ContainmentVerifier.HookContract.Tests.ps1`, found no false refusal
of a legitimate line and no defect, and raised R18-09, which the records now carry.

### Findings

| ID | Severity | Where | Finding | Resolution |
|---|---|---|---|---|
| R12-02 | Major | `hooks.json`; the contributor-profile asset; `Test-HookContract`; hooks README, gap 4 and the rows of `HookContract` and `WritableRoots`; this entry; `CHANGELOG.md` | The guard's own exposure under Windows PowerShell 5.1 stayed open after brief 12, for brief 18: a module in `Documents\WindowsPowerShell\Modules` that exports a command of the hook line, such as `Get-Variable`, answers for it, and `HookContract` starts its 5.1 wrapper with the verifier's module path, so it cannot see such a module. pwsh is exposed the same way through `Documents\PowerShell\Modules` | Closed for the hook lines: every PowerShell process of every shipped hook line pins its module path before it resolves a command, so a module in either personal folder, or first on an inherited `PSModulePath`, no longer answers for a command of the line or of its script; `HookContract` holds a pinned line to the pin and fails one that loads its tripwire from any of those places. What acts before the first statement of a line, and the program name of R18-02, stay open; see the remaining risks |
| R12-08 | Major | the same | When the documents folder does not resolve, 5.1 searches the relative `WindowsPowerShell\Modules` in its working directory, and moving `Documents` aside or re-pointing it during a run sends every later hook's 5.1 there or wherever it points | Closed for the hook lines the same way: the pin replaces the whole module path, the relative entry with it, before 5.1 resolves a command, so the state of `Documents` at the hook call no longer decides what answers. `HookContract` stands the tripwire in the working directory of its 5.1 wrapper when that 5.1 names it first. `WritableRoots` still names that entry unmeasured, which stays right for other PowerShell that the identity starts |
| R18-01 | Major | `Get-HookTripwireName`, `New-HookTripwire`, `Test-HookContract`; hooks README, the `HookContract` row; this entry | `HookContract` passed three hand-edited copies of the contained line, and in each a planted module turned the guard's denial into exit 0: E1 resolves `gl` and `echo` before anything else and has no pin, E2 names every command module-qualified and has no pin, and E3 pins a folder of the profile ahead of the interpreter's own. The tripwire exports only the Verb-Noun names a line spells and stands only where a logon module path looks, and nothing read the `-Command` text. CVSS 3.1 estimate 5.3 | Fixed as ruled: `Get-HookPinProblem` holds the `-Command` text to `HookCommandHead`, compared as typed, and refuses a later mention of `PSModulePath` by name, a `-File` or `-EncodedCommand` start and a line without a command; `Test-HookContract` fails such a line before anything runs. The tripwire stays, as a second net, and its claim is narrowed in the evidence, the README row and this entry. E1, E2, E3, a second assignment by name after the pin, and a `-File` line each fail `HookContract`; each of the reviewer's three passed it before the change. All 18 shipped lines pass the text check. The text after the pin stays unread, which the re-review found (R18-09) |
| R18-02 | Minor | this entry, What it covers; hooks README, the launcher paragraph and gap 4; `CHANGELOG.md` | When the `PATH` that VS Code hands its 5.1 lacks the Windows PowerShell folder, the outer 5.1 finds no program `powershell` and looks for a command of that name in the modules of its inherited path, before the closing statement pins; the records said flatly that no module is used before the pin | Fixed in the records, as ruled: the condition is stated where the claim was, and listed among the open items of gap 4 and the remaining risks. The line cannot name 5.1 by an absolute path without `%` or `$`, so it does not change |
| R18-03 | Minor | `com.github.copilot/rules/copilot-authoring.instructions.md` | The Instruction that loads whenever an agent edits a hooks file taught a launcher that resolves `Join-Path` with no pin, holds `$`, and ends with `exit $LASTEXITCODE`, which a wrapper reports as 1 | Fixed: the bullet points at the shipped entries of `hooks.json` and the Launchers section of the hooks README, names the pin, and says why the text holds no `$` and why `windows` and `powershell` end with the closing statement |
| R18-04 | Nit | `Get-HookTripwireEnvironment`, `Test-HookContract`; `tests/HookLauncher.Tests.ps1`; `tests/ContainmentVerifier.HookContract.Tests.ps1` | With `PSModulePath` unset, 5.1 puts its own personal folder first too, or the working-directory entry when there is no documents folder, so the evidence and the skip reasons that said it adds no folder of its own were false | Fixed: where the machine sets no value, the 5.1 wrapper runs without the variable and with the tripwire in its working directory, which this machine's 5.1 names first in that case too (measured); the texts are corrected and the two skips are gone, the planted-module cases running with the variable removed instead |
| R18-05 | Nit | this entry; `New-HookTripwire` | The entry said that the pull request's CI is the first run of the tripwire's POSIX placement; no run reaches it, because off Windows the verifier stops before `HookContract` (`IdentityPrivilege` reads the token on Windows only), and every test of the tripwire was skipped there | Both: new cases that run on every platform hold where the tripwire stands, the environment a spawn gets, `XDG_DATA_HOME` removed so that pwsh takes its personal folder from the decoy `HOME`, and a real pwsh that loads it from the first entry and from its personal folder and not once it pins; the records say that a verification off Windows never reaches the check |
| R18-06 | Nit | `Test-HookContract`; hooks README, the `HookContract` row | The 5.1 wrapper's placement relied on the decoy `USERPROFILE` moving the documents folder, which a documents folder redirected to a fixed path does not, so the tripwire could stand nowhere that 5.1 looks first while the evidence said it did | Fixed: the check asks that 5.1, with the payloads' environment and working directory and a line that names only types, whether its first module-path entry is the relative `WindowsPowerShell\Modules`; only then does the tripwire stand in its working directory, and otherwise it stands first on its path, and the evidence says which |
| R18-07 | Nit | `.memory-bank/decisions/0016-enforce-house-rules-with-hooks.md` | Decision 0016 still names the old closing statement as the current one | Deferred, as ruled, to the Memory Bank commit of phase 3, which adds a dated note |
| R18-08 | Nit | `tests/HookLauncher.Tests.ps1` | The planted-place cases had no positive control, so they would pass without testing anything where the interpreter does not search the place; and the test messages relayed pwsh's raw standard error, whose ANSI escapes stopped Pester's NUnit report at the first one | Fixed: a control per spawn and place runs the launcher without its pins and requires the module to load; and every test message that carries a child's standard error drops escape sequences and turns other characters outside printable ASCII into question marks |
| R18-09 | Minor | `Get-HookPinProblem`; hooks README, the `HookContract` row and gap 4; this entry; `CHANGELOG.md` (re-review) | The check holds only the start of the `-Command` text and refuses a later `PSModulePath` spelled out. Six hand edits after the pin passed `HookContract` while a planted module or script turned a denial into exit 0, and no tripwire loaded in any spawn: the module path set again through `'PSModule' + 'Path'` with `[Environment]::SetEnvironmentVariable` (N1), an `Env:PSModuleP*` wildcard with `Set-Item` (N2), or `New-Item Env:` with a computed name (N3); `Import-Module` by path (N4); an alias to a script by path (N5b); and a nested pwsh, which puts the account's personal folder first again (N6). The records said that assigning the module path again is refused, and named only a change without the name and `Import-Module` by path | Fixed in the records, the reviewer's option 2, as ruled: the `HookContract` row, gap 4, this entry and the CHANGELOG say exactly what the check refuses and name the six forms by kind, the claim that assigning the module path again is refused is gone, and operators are told to keep the inner `-Command` text of every line exactly as shipped and to change a pinned copy only where the containment profile section allows, such as the interpreter named by absolute path. No line derived from the shipped command holds any of the six, and the pinned file is the operator's, closed to the run. The reviewer's option 1, holding the whole `-Command` text to the shipped text, goes to the backlog. No code changes |

### Tests

- Test first, on `7251dad`, before the change: in the three files the change touches, 119 of
  1,232 tests failed, each for its stated reason, and 81 were skipped as before. In
  `tests/HookLauncher.Tests.ps1`, 107 of 657: the contract that every launcher pins the module path
  first (15) and that `windows` and `powershell` are `command` with the new closing statement (10);
  the closing statement, 14 cases under both wrappers with a module that exports `Get-Variable`
  first, where the module was imported in every case; the planted module, 16 cases of a place (first
  on `PSModulePath`, `Documents\WindowsPowerShell\Modules`, `Documents\PowerShell\Modules`, and the
  working directory of a 5.1 without a documents folder) and 48 cases of a name (eight names under
  three spawns, with a denied and an allowed payload each), where the module was imported and a
  denial gave 0; and the grant recorder, 4 cases under both wrappers, where a module that answers for
  `ConvertFrom-Json` handed the recorder a session and a prompt of its own choosing, and one that
  answers for `Select-Object` ended the process before the recorder ran. In
  `tests/ContainmentVerifier.HookContract.Tests.ps1`, 12 of 344: the old closing statement accepted
  and the new one refused (2); a module not stood in the working directory of a spawn (1) and not
  handed on by `Measure-HookWrapper` (1); a line without the inner pin that passed, and evidence
  without the tripwire (2); the spy that found no tripwire where each spawn looks first (1); and
  the three cases that a spawn reaches the tripwire and the two tests of the new functions, which
  failed because those functions were stubs that returned nothing (5).
  `tests/ContributorProfileHooks.Tests.ps1` stayed green (231), because its test that the asset
  carries the launchers of `hooks.json` compared two unchanged files; M11 below shows that it fails
  an asset that is left behind.
- After the change, through the detached launcher: the suites that run the hooks, `Hooks`,
  `HookLauncher`, `HookSdkRuntime`, `RemoteMutationLiteral`, `RemoteMutationGrant`,
  `ContributorProfileHooks` and `ContributorProfileWriter`: 1,799 passed, 0 failed, 80 skipped (the
  `/bin/sh` spawns, which Windows does not have), in 1,707 seconds. Every `ContainmentVerifier*`
  suite with `CustomizationSecurity`, `PluginManifest` and `ChangedFileValidation`, which read
  `hooks.json`: 1,351 passed, 0 failed, 3 skipped by design (a POSIX case, the property test whose
  fresh seed only CI draws, and an elevation type that this token does not have), in 371 seconds.
  The grant recorder's cases need no Grant marker: their payload names no session, so a recorder
  that ran on it says so and records nothing, and no case writes a grant. The full gate runs once,
  after the review.
- Mutants, on copies under TEMP and never in the working tree, each against the tests that should
  catch it, after two control copies passed every one of them (222 and 533 tests): 12 of 12 caught.
  M1, the inner pin dropped from the guard's `windows` line (48 failures: the contract, 12 places,
  32 names, and 2 tripwire cases of `HookContract`); M2, dropped from its `powershell` and `command`
  lines (23, the PowerShell 7 spawns); M3, the pin moved after the statement that resolves the
  script (48); M4, a pin that appends `$PSHOME\Modules` to the inherited path (48); M5, the old
  closing statement in all ten lines (41: the 14 cases of the closing statement, among others); M6,
  the pin after `Get-Variable` in the closing statement (41); M7, the `+ 2` default dropped (9: an
  inner program that never started, and a line without a native command, gave 0 under both
  wrappers, and the verifier refused the line); M8, a verifier
  that accepts the old closing statement too (1); M9, no tripwire in the working directory of the
  5.1 wrapper (1, the spy); M10, a tripwire that exports only the names of the closing statement (2:
  the line without the inner pin passed, because `Set-Variable` loads the real
  `Microsoft.PowerShell.Utility` and its `Get-Variable` before the line names it, and the test of
  the names); M11, the asset left unpinned (1); and M12, the `windows` line of `Stop` left unpinned
  (2).
- The module analysis cache of 5.1, on copies in a scratch folder named by
  `PSModuleAnalysisCachePath` in the child's environment only: with `Get-Variable` hidden from
  `Microsoft.PowerShell.Utility`, the guard's pinned line gave 2 for an allowed and for a denied
  payload; a cache of garbage was ignored. The cache under the user profile was not written.
- PSScriptAnalyzer 1.25.0 with default rules: 0 findings on the verifier and the two changed test
  files. markdownlint-cli2 0.24.1 (markdownlint 0.42.1), from the local npx cache without a network
  call: 0 issues on the three changed documents.
- The fix round, test first, on `4667dd7` with stubs of the two new functions: 40 of 385 cases of
  `tests/ContainmentVerifier.HookContract.Tests.ps1` failed. Eleven of them failed for a reason in
  the test and not in the code: the ten `windows` and `powershell` lines of the lifecycle events end
  with the failure code 1, which `Get-HookInterpreter` refuses before the pin is read, and an encoded
  command padded with `=` failed the shape. Both were corrected, and the 26 cases then failed for
  their stated reason in a run of their own. In all: the text of the pin, 27 cases (the 18 shipped
  lines, whose `-Command` text was not read yet, 8 refusals, and the joined text); the review's three
  copies, a second assignment after the pin, and a `-File` line, run through `Test-HookContract` (5:
  E1 to E3 and the second assignment passed it, which shows that the check passed them before the
  change, and the `-File` line failed for the canary and not for the pin); the placement of the
  tripwire (5: 5.1 was not asked, so the spy and the two cases of a 5.1 that names a rooted folder or
  cannot be asked saw no question, the evidence lacked what it now says, and the wrapper kept the
  machine's `PSModulePath` where a stand-in machine set none); and the cases that run on every
  platform (3: `XDG_DATA_HOME` left in place, and the machine's value not taken through
  `Get-HookMachineModulePath`). The eight controls of `tests/HookLauncher.Tests.ps1` pass on this
  machine, as they must, and are shown to bite by P01 below. After the change: the HookContract
  suite 384 passed, 0 failed, 1 skipped. Then, through the detached launcher, the suites that run the
  hooks: 1,807 passed, 0 failed, 80 skipped, in 1,894 seconds; and every `ContainmentVerifier*`
  suite with `CustomizationSecurity`, `PluginManifest`, `ChangedFileValidation` and the suites that
  read the edited Instruction, CHANGELOG and documents (`CustomizationFrontmatter`, `SecretScan`,
  `SharedLifecycle`, `SkillSelection`, `PlanReview`, `AuthenticatedWebExtraction`): 1,630 passed,
  0 failed, 3 skipped by design, in 457 seconds. Two older cases changed their line, not their
  assertion: the line that runs its script from a fixed path, and the slow line, now pin first, so
  that they still reach the canary and the clock rather than the text check.
- Mutants of the fix round, on copies under TEMP, after two control copies passed every test they
  ran (277 and 574): 25 of 25 caught. The twelve of phase 2 again (M1 63 failures, M2 25, M3 61, M4
  63, M5 59, M6 59, M7 27, M8 1, M9 2, M10 2, M11 4, M12 3; M1 is the review's C1); the review's E1,
  E2 and E3 applied to the guard's `windows` line in `hooks.json` (32, 23 and 23, among them the
  contract case and the run of the contained shipped hook; E3 there is the review's M-E3); nine of
  the new code: the text check removed (13), its refusal of a second `PSModulePath` removed (2), a
  `-File` line accepted (2), the 5.1 wrapper always given the working-directory placement (2) or the
  answer read the wrong way round (4), the machine's value read directly and not through
  `Get-HookMachineModulePath` (3), `XDG_DATA_HOME` left in place (1), the `-Command` text cut to its
  first word (1), and the check not called from `Test-HookContract` (5); and P01, the planted
  `Personal51` place moved to a folder 5.1 does not search, where the four place cases of that
  folder still passed and its two controls failed. The escape sequences, on a red copy with the old
  closing statement: with the messages unsanitized, Pester's NUnit export stopped on `0x1B` at the
  13th of 14 cases and left a report that does not parse; with them sanitized, the same copy gave a
  report that parses, with all 14 cases.
- The fix round's other checks: PSScriptAnalyzer 1.25.0 found 0 issues in the verifier and the two
  changed test files, and markdownlint-cli2 0.24.1 found 0 issues in the four changed documents.

### Remaining risks

- What a host passes in the environment acts before the first statement of a line, so no pin in
  the line reaches it: a .NET profiler for 5.1 (`COR_PROFILER_PATH`) or a startup hook for pwsh
  (`DOTNET_STARTUP_HOOKS`) loads code into the interpreter first. The environment comes from the
  host and its logon, the class of gap 2.
- The pin trusts the `Modules` folder of `$PSHOME`, so a `$PSHOME` that this identity can write,
  such as a pwsh installed per user, answers for every command of the line. `HookContract` refuses
  such an interpreter in a pinned line; the shipped file's `pwsh` is whichever `PATH` finds.
- The module analysis cache of 5.1, which the account can write, can only point a lookup at a
  module in the pinned folder, so an entry that hides a command makes the line fail closed. Measured
  on a copy of the cache in a scratch folder, with `Get-Variable` hidden from
  `Microsoft.PowerShell.Utility`: the closing statement found no `Get-Variable`, its array kept only
  the default, and the guard's line exited 2 for an allowed and for a denied payload alike; a
  lifecycle line ends with 1, a warning, the same way. A cache of garbage was ignored.
- The shipped `hooks.json` starts a bare `powershell` or `pwsh`, which a host looks up in `PATH`,
  so a folder ahead of the interpreter on `PATH` that this identity can write answers for the whole
  line. A contained deployment pins an absolute interpreter path, which `HookContract` requires; the
  shipped file does not.
- The program name comes before every pin (R18-02): when the `PATH` that VS Code hands its Windows
  PowerShell 5.1 holds no `powershell`, that 5.1 looks for a command of that name in the modules of
  the path it inherited, so a module in its personal folder or its working directory answers for the
  whole line before the closing statement pins; the review measured a denial that exited 0 that way.
  pwsh puts its own folder first on its `PATH`, so the Copilot SDK host's spawn found its program,
  and a pinned line names its interpreter by path. The `PATH` a host passes is the environment class
  above.
- `HookContract` holds a pinned line to the exact pin at the start of its `-Command` text, to the
  exact closing statement, and to no later mention of `PSModulePath` by name, and refuses `-File`,
  `-EncodedCommand` and a line without a command; it does not read the rest of the text (R18-09).
  Code after the pin can therefore still set the module path again under another spelling (a
  computed name with `[Environment]::SetEnvironmentVariable` or `New-Item Env:`, an
  `Env:PSModuleP*` wildcard), run code by path (`Import-Module` by path, an alias to a script by
  path), or start a nested pwsh, which puts the account's personal folder first again; in each of
  the six forms the re-review measured, a planted module or script turned a denial into exit 0 and
  no tripwire loaded. A line derived from the shipped command holds none of them, and the operator
  writes the pinned file, which `ControlImmutability` shows closed to the run: keep the inner
  `-Command` text of every line exactly as shipped, and change a pinned copy only where the hooks
  README allows, such as the interpreter named by absolute path. Holding the whole text to the
  shipped one is in the backlog.
- The tripwire shows that the line loaded none of the Verb-Noun names it spells from the places it
  stood in, under the three payloads, not what a host does: no host ran the line, as before.
- A registration of the contributor-profile hook that was written from the earlier template keeps
  the unpinned line until the next profile write replaces it; `Get-CopilotAtelierContributorProfile`
  reports it as `outdated` until then.
- The new digests, as checked out (`.gitattributes` gives `*.ps1` CRLF and `*.json` LF on every
  system): the verifier `32558cf02a594aa2922f8614bb897cab1d651d4f46932a653c98d77801842842` after the
  fix round, where the reviewed `4667dd7` hashed to
  `e5df18ddf10cf9ecf5a753d0bbe6c1ce5ad632b263277859a4362b5f044ae0d1` and brief 14 to
  `9e150ba828847c773055092ace165478f6d31e2ce477cc9bd2ead69b578f5c65`; `hooks.json`
  `ed05f232b68d0715b5c351d50234f9250ef14b8139801fb5810c9b825512cb14`, was
  `ba20170a7833aacc95d3b7c0e889e98cabfada4f979dd9d3a2f4a18a90400d65`; and the contributor-profile
  asset `e553312ef5d9051e510b08a19894a48f0a4bf819998901e22e7652de01ff1eec`, was
  `773b264a2bc5b904ca6aefc2f57a4402e4c9ed45b39e08488391e571a0f04466`; the fix round changes neither
  file. The guard is unchanged at
  `e94968a0f37f5857514f3f5c01f917df369cedfa9ee97fa07a7ed2c058f157a3`, the appender at
  `f55e163b02fe4db6d318bc3e8c3d8cc6c86c2bf365496ddf22cda5e812030572`, and the grant recorder at
  `51c0f39b8e9252816eda0a2fbd2869b4f17c0773ed6562945701df57ec341218`. Every containment profile
  derives its pinned `hooks.json` again from the shipped file, because the verifier refuses the old
  closing statement, and re-pins it and the verifier; `~/.copilot` has to be refreshed with
  `./Setup-CopilotSettings.ps1`. The longest hook line is now 1,660 characters, the `windows` line
  of `PreCompact`; neither the hooks schema of VS Code 1.146.0 nor the hooks reference of the
  Copilot CLI limits its length, and `cmd.exe` stops at 8,191.
- Not run: Ubuntu and macOS, where the `command` launcher runs under `sh` and pwsh searches
  `~/.local/share/powershell/Modules` first, so the pull request's CI is the first run there of the
  pinned launchers and of the new cases of the tripwire that run on every platform. No verification
  off Windows reaches `HookContract` at all, because `IdentityPrivilege` reads the access token on
  Windows only, so the tripwire's placement there is held by those cases and runs in no check
  (R18-05). Not run either: the spawn code of VS Code and of the Copilot SDK host, a documents folder
  redirected to a fixed path, whose branch of the 5.1 wrapper is tested with a stand-in answer, and a
  deployment with separate accounts.
- The remaining risks of the earlier entries that this change does not touch stay open: the rest of
  R11-01, `DELETE` on the six places of the escape set, the registry re-point of the module folders
  for other PowerShell (gap 2), and the second Windows account.

## 2026-11-14: a run id for `-Revalidate`, the R-11 follow-up (follow-up of prompt P5)

Brief 14 closes, for a profile that names its run, the follow-up that R-11 and the remaining risks
of the review of 2026-10-14 left open: `-Revalidate` did not bind the ledger to a run. Every record
already carried a `runId`, which the client chooses and nothing compared, so the sealed ledger of
another run at the paths a profile names, with that run's final report, revalidated: an earlier
run's ledger left at a sink path that the operator reused, for one, or a ledger copied there. The
containment profile now names its run in `runId`, which moves the profile schema to version 2, and
`-Revalidate` has a check of its own, `LedgerRun`, between `LedgerChain` and `FinalReport`: every
record of the chain that the pinned appender validated must carry the profile's run id once, as a
JSON string equal to it code unit for code unit. The JSON report and the summary line of
`-Revalidate` name the run id. The design was chosen out of five, a run id in the profile, a first
record that the appender writes, a `-RunId` argument, the profile's run id echoed by the appender,
and the profile digest as the run id, and was decided with its seven details under the owner's
delegation for the local branch (the handoff ledger, 2026-11-14); merging brief 14 is the owner's
explicit answer. Only the verifier changes; the appender keeps the digest of brief 13. The Custom
`security-reviewer` agent reviewed `e943713` in a fresh context, read-only, reproduced the red-first
run and the suites on copies, ran six mutants and eight probes of its own on copies under TEMP, and
said **Approve with changes**: no Blocker and no Major, two Minors (R14-01, R14-02), both claims in
the documentation, and nine Nits (R14-03 to R14-11). The controller ruled to fix all eleven as the
reviewer proposed, under the owner's delegation (the handoff ledger, 2026-11-14), and declined one
optional step; the fix round does that. The same reviewer re-reviewed the fix round, `7cc59c8`, and
said **Approve**: R14-01 to R14-11 resolved and no defect added, with two new Nits, R14-12 and
R14-13, which the controller ruled to take before the full gate and which are fixed as well.

### Scope

- Does the sealed ledger of another run, valid as a chain and with a valid final report, fail
  `-Revalidate` under a profile that names this run, while the run's own ledger passes?
- Does a ledger that holds a record of another run fail, wherever that record is?
- Can a run id that only looks like the profile's, or a `runId` that is not a JSON string, pass?
- Is the profile's run id held to a shape that the profile's JSON reader cannot change and that is
  safe to relay, and is a version-1 profile refused with what to add?
- Does the run check run only on a chain that validated, on the bytes that were validated, and is it
  reported as not run otherwise?
- Do the hooks README, the controller agent, the CHANGELOG and this entry claim only what is shown?

### Design

- **Where the run id comes from.** The operator draws it new for every run, a GUID for one, and
  writes it into that run's profile, whose digest the operator hands the run as a direct argument.
  `ControlImmutability`, which `-Revalidate` measures again, shows the profile closed to the
  identity that runs the verifier, so no run identity chooses the value that a ledger is compared
  with.
- **Where it is bound.** `runId` is a required field of the profile, and `schemaVersion` must be the
  integer 2; a version-1 profile is refused with what to add. The value is a string of 1 to 64
  letters, digits, `.`, `_` or `-`, matched case-sensitively. It reaches evidence that a model
  reads, and `ConvertFrom-Json`, which reads the profile, returns a `DateTime` for an ISO date-time
  and for a `/Date(...)/` string (measured with pwsh 7.6.10), so a value with `:` or `/` would not be
  the text the operator wrote; a match that ignores case would read the Kelvin sign as a K.
- **What is compared.** `LedgerRun` reads every record of the bytes that the appender validated,
  tied to them by the record count, with System.Text.Json, and requires each to carry exactly one
  `runId`, a JSON string equal to the profile's by code unit. The appender refuses a `runId` that is
  not a non-empty string when a record is appended, but its reader of stored lines does not check
  the type (measured: a number, an object, null and an empty string read back without error and with
  a matching digest), so a number whose digits are the run id fails here as well, and since the fix
  round so does a string that is valid JSON but no UTF-16 text, such as a lone surrogate escape,
  where reading it threw before. The run id the check is given is held to the profile's shape on its
  parameter too, case-sensitively. The check runs only on a chain that validated, and `FinalReport`
  runs beside it, so the evidence names both.
- **What does not change.** The appender's bound `-Validate` reads only `ledgerSink`, `chainHead` and
  `ledgerAppender` from a profile, so it reads a version-2 profile unchanged, and its `bound` still
  means the paths and the pin. `-Verify` checks the new field as part of the schema and nothing
  more: a start check was not added, because a run that means to deceive could skip it.
- **Compatibility.** A profile is valid only for the verifier whose digest it pins, so its schema
  may change with any change to the verifier, and the CHANGELOG gives the migration; the hooks README
  says so since the fix round (R14-11). A version-1 profile fails `VerifierBinding` against any new
  verifier; an older verifier refuses a version-2 profile, to which `runId` is an unknown field
  (measured). A ledger written before the change revalidates only under a profile that names the one
  run id all its records carry, and only when that run id fits the new shape.

### Verdict

**Approve with changes.** The reviewer found the ruling implemented in all seven details, no run
identity able to choose the expected run id for a given profile, every look-alike, other JSON type,
date string, repeated key and empty ledger it tried failing closed, and every new outside text
relayed. It reproduced the red-first run (81 of 272) and the suites (1,346 passed, 0 failed, 3
skipped), and both digests. The gaps were in what the documentation promised and in what the tests
pinned: three of its six mutants survived, M1 and M6, and M2 on the line of a revalidation that
passed, which the change had declared untested.

### Findings

| ID | Severity | Where | Finding | Resolution |
|---|---|---|---|---|
| R14-01 | Minor | hooks README, CHANGELOG, this entry | All three said that the operator's digest, passed to `-Revalidate` again or compared with the `profileSha256` and the `runId` of the report, binds a revalidation to the run. The second half does not hold against a controller that means to pass another run's evidence: the verifier writes its report with the rights of the controller, to the path the controller chose, and the summary line reaches the operator through the controller | Fixed in the reviewer's wording, in all three places and in the README's sentence on what the operator sees: only the operator's own `-Revalidate` binds a revalidation to the run; the report and the summary line catch a controller that was given the wrong profile, and bind nothing against one that means to pass another run's evidence. The summary line names the run id and not the digest, so the wording says that the report names both |
| R14-02 | Minor | controller agent; hooks README | The agent said that a new run id gives each run a sink and a chain head of its own; a profile written for a new run can still name paths an earlier run used. Then an honest run fails late, and a later run can complete an earlier, unsealed run's ledger with records that carry the earlier run's id, because whoever can append chooses the `runId` | Fixed as proposed: the agent says that the operator gives every run a ledger sink and a chain head that no earlier run used; the README's `ledgerSink` row says the same, and its `LedgerRun` row says that a later run that reuses an unsealed run's paths can complete that run's ledger. The optional controller step, validating the chain before the first append, was declined, for the reason that kept the start check out of `-Verify`. Recorded under Remaining risks |
| R14-03 | Nit | `tests/ContainmentVerifier.Revalidate.Tests.ps1` | Only the order with the other run's id first was tested for a repeated `runId`, so a reader that takes the first value and lacks the branch for a repeated key passed (the reviewer's mutant M1) | Fixed: both orders are tested, and each asserts "carries runId 2 times". M1 is caught |
| R14-04 | Nit | the verifier's main flow; `tests/ContainmentVerifier.Tests.ps1` | Nothing pinned that a profile that fails the schema names no run id in the report or the summary line (M6) | Fixed: the case of a profile that fails on another field asserts that neither names its run id, and a new case gives a run id with a carriage return, a line feed and `Containment Pass`, which reaches neither. M6 is caught |
| R14-05 | Nit | the verifier's summary lines | The line of a revalidation that passed was untested, because no test host passes the machine gates (M2) | Fixed: the two lines are one function, `Format-RevalidationSummary`, tested in process in both forms, with and without a run id; it relays the run id as well. M2 is caught in the function. The call of the line of a revalidation that passed stays unreachable on a test host; since R14-13 both calls take the run id, the role and the count from one set of arguments, which the line a test host reaches shows end to end |
| R14-06 | Nit | `Test-LedgerRun` | A `runId` that is a lone surrogate escape made the read of its text throw, so the script exited 1 without a report, which fails closed but returns no check | Fixed: such a record fails with "record N carries a runId that is not text". Also, as offered, the parameter that carries the profile's run id has a case-sensitive `ValidatePattern` of the run id's shape; a test pins that it equals the schema's, since an attribute cannot name the constant, and the Kelvin sign is refused at binding |
| R14-07 | Nit | `Test-ProfileSchema` | A version-1 profile that already carries `runId` was told that it names no run | Fixed: that hint comes only when `runId` is absent; otherwise the refusal says "version 2 adds 'runId', a run id that is new for each run; set 'schemaVersion' to 2" |
| R14-08 | Nit | the run id's shape; controller agent | The ruled shape admits `.`, `..`, a trailing dot and device names, which are unsafe as file or folder names, and the agent asked for the run id wherever the run is named | Fixed in the agent, which now says never to use the run id as a file or folder name; the ruled shape stays |
| R14-09 | Nit | `tests/ContainmentVerifier.Flow.Tests.ps1` | The `-Verify` flow fixture still built a version-1 profile without `runId` | Fixed: version 2 with a run id, and a test that the fixture satisfies the schema, as every profile the flow gets does |
| R14-10 | Nit | CHANGELOG | The migration note did not say that the run id of an old ledger must fit the new shape | Fixed: "and that fits the new shape" |
| R14-11 | Nit | the commit message; versioning | `fix:` without `!` is defensible only on a policy that was not written down: a profile is valid only for the verifier digest it pins | Fixed: the hooks README states that policy once, in its section on the containment profile, so the next schema change has a written basis. The squash title stays `fix(containment):` |
| R14-12 | Nit | this entry (re-review) | The Verdict above said that two of the reviewer's six mutants survived beside the declared equivalent one; three survived, M1, M6 and M2, and the declared equivalent mutant is the implementer's | Fixed in the reviewer's words |
| R14-13 | Nit | the verifier's main script (re-review) | The call of the line of a revalidation that passed named its own arguments, so an empty run id there alone failed no test (the reviewer's mutant N02), and "M2 is caught" held for the function only | Fixed as proposed, with the proposed alternative test as well: both calls take the run id, the role and the count from one set of arguments, so the end-to-end test of the line a test host reaches covers what the other line gets. A test of the script requires both calls to splat that set and neither to name one of its arguments, a unique prefix included, and the script to name the set nowhere else. N02 is caught in each of the six forms it can now take |

### Tests

- Test first, on `d0548c1`, every group red for its stated reason before the code: 81 of 272 tests
  failed in the five files the change touches most. Through the real service, the sealed ledger of
  `run-b` under a profile that names `run-a`, and a ledger that holds a record of `run-b` among
  records of `run-a`, both revalidated (verdict `Pass`), and so did the same pair written without the
  service; the run's own ledger passed, a positive control. `Test-LedgerRun` did not exist (20
  cases); the revalidation named eight checks and no `LedgerRun` (7 cases); the schema refused
  `runId` and every version but 1 (28 cases); end to end, the report and the summary line named no
  run id and a version-1 profile passed the schema (5 new cases, and 16 earlier cases turned red
  because the old verifier refuses the version-2 fixture); the controller agent did not mention the
  run id (1 case). After the change: 272 passed, 0 failed. Then every `ContainmentVerifier*` suite,
  the appender suite, whose bound validation now reads a version-2 profile, and the controller-text
  suite, through the detached launcher: 1,346 passed, 0 failed, 3 skipped by design (a POSIX case,
  the property test whose fresh seed only CI draws, and an elevation type that this token does not
  have), in 432 seconds. The full gate runs once, after the review.
- Mutants, on copies under TEMP and never in the working tree, each against the suite that should
  catch it, after a control copy without an edit passed every test: 18 of 18 caught. The run check
  never failing a record (16 failures), left out of the flow (3), comparing only the first record
  (13) or only the last (13), comparing with `OrdinalIgnoreCase` (1) or with `-ceq` (1, the
  zero-width space), reading a `runId` as text instead of requiring a JSON string (3), no tie to the
  validated count (1), running after a failed chain (2), and not relaying a record's run id (1);
  version 1 accepted (2), `runId` optional (3), `-notmatch` for `-cnotmatch` (1, the Kelvin sign),
  the shape dropped (10), the profile's value cast with `[string]` (3), and `^`/`$` for `\A`/`\z` (1,
  a trailing line feed); the summary line (1) and the JSON report (1) without the run id. One
  further mutant is equivalent and survived, as expected: reading the first snapshot instead of the
  second, which hold the same bytes whenever the run check runs, because it runs only when the two
  hashed alike.
- PSScriptAnalyzer 1.25.0 with default rules: 0 findings on the verifier and the six changed test
  files. markdownlint: 0 issues.
- The fix round, test first: before the code, 13 tests failed for their stated reasons in the five
  files it touches, which now hold 351. That was the hint for version 1 (1 test),
  `Format-RevalidationSummary`, which did not exist (5), a run id that is no text, which threw, and a
  run id of another shape, the Kelvin sign included, that bound without a refusal (5), the
  version-1 fixture of the flow against the schema (1), and the agent's text (1). The pins of R14-03
  and R14-04 hold behaviour that was already right, so they passed before the code and fail under the
  reviewer's mutants M1 and M6. After the code: 351 passed, 0 failed. Mutants, on copies under TEMP,
  after a control copy passed every test: 29 of 29 caught. That is the reviewer's M1, M2 and M6, the
  18 above again, M17 now on the new function, and eight new ones: no `ValidatePattern` on
  `-RunId`, its default options that ignore case, `^`/`$` in it, no catch around the read of a run
  id, an unreadable run id not reported, the hint for version 1 whatever the profile holds, the run
  id not relayed into the summary line, and the NOT line without the run. One of the 18 ran
  malformed first and was run again. The declared equivalent mutant survived again. Then the
  brief's suites: 1,360 passed, 0 failed, the same 3 skipped, in 450 seconds. PSScriptAnalyzer: 0
  findings on the verifier and the five changed test files; markdownlint: 0 issues.
- The re-review's Nits, test first: the test of the script's two calls failed on `7cc59c8` for its
  stated reason, the call of the line of a revalidation that passed naming its own arguments, and
  passed after the change. Mutants, on copies under TEMP, after a control copy passed: N02 is caught
  in each of the six forms it can now take. An empty run id in the shared set fails the end-to-end
  case 'names the run id in its summary line' and the test of the script. At the call of the line of
  a revalidation that passed, its own arguments, as in N02, an override after the set, a unique
  prefix such as `-Run`, a set of its own, and a change of the set before the call each fail the
  test of the script, and no end-to-end test, since no test host reaches that line. The last form
  passed the first version of that test, which is why it also requires that the script name the set
  only where it builds and splats it. Then the revalidation file and the end-to-end file, through the
  detached launcher: 172 passed, 0 failed. PSScriptAnalyzer: 0 findings on the verifier and the
  changed test file; markdownlint: 0 issues.

### Remaining risks

- An identity that can write the sink and the head can write a chain from genesis that carries the
  run id, a `FinalReport` record for any report, and a seal, and `-Revalidate` passes: the run id is
  not secret, because the controller has to know it to write it and every record shows it, and the
  chain is not keyed. Keying the chain stays a P5 residual without a ruling, and it would help only
  against an identity that cannot read the key.
- No check can tell that a run id was used before, so two runs given one run id are not told apart.
  Drawing a new run id for every run, and so writing a profile for every run, is the operator's
  duty, which the hooks README and the controller agent state.
- A later run whose profile reuses the ledger sink and the chain head of an earlier, unsealed run
  can complete that run's ledger: whoever can append chooses the `runId` of what they append, so
  its records can carry the earlier run's id through the pinned service, and a revalidation under
  the earlier run's profile then passes with content that the later run chose, although no identity
  wrote the sink or the head directly (R14-02). Giving every run a ledger sink and a chain head that
  no earlier run used is the operator's duty, which the hooks README and the controller agent state.
- The controller runs `-Revalidate` itself, with the profile path and digest it was given. A
  controller that names another run's complete evidence, that run's profile, its digest and its
  report, passes, because they agree with one another. Only the operator's own `-Revalidate`, run
  after the run with the profile path and the digest they handed it, binds a revalidation to the run
  they started. The JSON report that the controller returns names the run id and the profile digest,
  and its summary line names the run id. That catches a controller that was given the wrong profile,
  but the controller can write both, so they bind nothing against a controller that means to pass
  another run's evidence (R14-01).
- The appender's bound `-Validate`, run alone, still passes the sealed ledger of another run at the
  paths a profile names; the run is the check of `-Revalidate`.
- The new digest of the verifier, as checked out (CRLF on every system, by `.gitattributes`):
  `9e150ba828847c773055092ace165478f6d31e2ce477cc9bd2ead69b578f5c65`, after the re-review's two
  Nits; the fix round, `7cc59c8`, hashed to
  `66bb9ee2999c13db4255b41f555e08a1e11fb198983f6a06023cf21d23d37970`, and the reviewed `e943713` to
  `e5bb595fcad5aa5a6d6c5dab3b592d23499decff86e10f53a83b9a468a49c324`.
  The appender is unchanged at
  `f55e163b02fe4db6d318bc3e8c3d8cc6c86c2bf365496ddf22cda5e812030572` (brief 13), and `hooks.json` and
  the guard are unchanged. Every containment profile has to move to version 2, with a new run id for
  every run, and re-pin the verifier, and `~/.copilot` has to be refreshed with
  `./Setup-CopilotSettings.ps1`.
- Not run: Ubuntu and macOS, where the pull request's CI is the first run of the ledgers written
  without the service; Windows PowerShell 5.1; a deployment with separate accounts; and a
  revalidation that passes end to end on a real standard account, which no test host here can give.
- The remaining risks of the earlier entries that this change does not touch stay open: the rest of
  R11-01, `DELETE` on the six places of the escape set, the guard's own exposure under Windows
  PowerShell 5.1 (brief 18), and the second Windows account.

## 2026-11-14: the module folders in `WritableRoots`, the S-18 follow-up (follow-up of prompt P5)

Brief 12 does the follow-up that S-18 of the review of 2026-10-14 left open. pwsh puts the account's
own module folder ahead of every folder a launcher names, and the later commands of the verifier
auto-load modules from it, but `WritableRoots` measured only its escape set, which reached that
folder at most through the user profile above it. The check now names a second set beside the
escape set, the module search set: every entry of the verifier's own `PSModulePath`, the `Modules`
folder of `$PSHOME`, and the folders of the user's and of `$PSHOME`'s `powershell.config.json`, with
each file that exists, because a `PSModulePath` key in either file chooses a module folder of the
next start, and, since the fix round, on Windows the two module folders that Windows PowerShell 5.1
adds to its own path. A place of that set fails the check when this identity can write it, or,
since the fix round, replace it, even inside a declared root; a place of either set that does not
exist is judged by the nearest existing place above it; an entry that is relative, or names a
network or device path, is reported unmeasured without being opened; and every path and reason that
the check puts into its evidence is relayed. The four questions of the brief were decided under the
owner's delegation for the local branch (the handoff ledger, 2026-11-14); merging brief 12 is the
owner's explicit answer. The Custom `security-reviewer` agent reviewed `0b7e4ab` in a fresh context,
read-only, ran the suites and 26 mutants of its own on copies, and probed Windows PowerShell 5.1
and pwsh on copies under TEMP. It said **Request changes**: two Majors (R12-01, R12-02), one Minor
(R12-03) and four Nits (R12-04 to R12-07), with a security escalation for the push guard. The
controller ruled on every finding under the owner's delegation (the handoff ledger, 2026-11-14), and
the fix round addresses all seven; the guard's own exposure under Windows PowerShell 5.1 stays open
for brief 18. The same reviewer re-reviewed the fix round, `3eb5d8f`, and said **Request changes**
again: R12-01 and R12-03 to R12-07 resolved, R12-02 partly resolved as ruled, and two new findings,
R12-08 (Major) and R12-09 (Minor). The controller ruled to fix both as the reviewer proposed (the
handoff ledger, 2026-11-14), and the second fix round does; its re-review is pending.

### Measurement

- On this machine (Windows Server 2025, build 26100; pwsh 7.6.10), a pwsh started through
  `ProcessStartInfo` with `Environment.Clear()`, `SystemRoot`, and a `PSModulePath` of the system
  folder only searched the account's `Documents\PowerShell\Modules`, `C:\Program Files\PowerShell\Modules`,
  `$PSHOME\Modules`, and the system folder, in that order. With `PSModulePath` unset, or set to an
  unrelated folder, the first three still came first.
- Under a filtered token of the measuring account (`CreateRestrictedToken` with `LUA_TOKEN`, Medium
  integrity, as the Privilege suite makes one), the account's module folder and its
  `Documents\PowerShell` were writable and the other folders closed. The account is an elevated
  administrator, which holds every right, so the filtered token is the nearer stand-in for a run
  identity.
- pwsh's own merge function puts a `PSModulePath` from the user's `powershell.config.json` first,
  as about_PSModulePath documents, and the account holds `KEY_SET_VALUE` on the `User Shell
  Folders` key that places its documents folder, measured by opening the key; nothing was written.
- No containment profile exists on this machine, and no profile or fixture of the repository
  declares a root that covers a module folder.

### Scope of the review

- Can a place that pwsh auto-loads modules from, or reads its module path from, be writable by this
  identity while `WritableRoots` passes?
- Can an entry of the module search set make the check open a network or device path, or
  authenticate to another machine?
- Can a place that does not exist read closed while this identity could create it?
- Does every path and every reason reach the evidence relayed and cut, and does each list stop at
  1,000 characters?
- Do the hooks README, the CHANGELOG and this entry claim only what is shown?

### Verdict

**Request changes.** The change implements the ruling: the set names what Q1 asks, a writable
module or configuration place fails even when a declared root covers it while the six escape
entries keep their exemption, every entry is judged by its nearest existing ancestor, and every
path and reason of the check is relayed and capped. No error, exception or unknown right yields
Pass. But the records claimed more than was shown. Under the default access list of a profile, the
operator steps of the hooks README left the folders replaceable, and the check passed: on a copy,
the reviewer moved an administrator-owned `Documents\PowerShell` aside through `FILE_DELETE_CHILD`
on `Documents` and created its own (R12-01). And Windows PowerShell 5.1, which runs the hook line
under VS Code, searches `Documents\WindowsPowerShell\Modules` first; a module there turned the exit
2 of a denial into exit 0 in the closing statement of the shipped hook line, and neither the set nor
the residuals named that folder (R12-02).

The re-review of `3eb5d8f` found the code correct where it reaches, the full suite green, and 20 of
its 22 reverts and mutants caught by tests that run on every leg; on a real filesystem the check now
failed the move-aside of R12-01 and passed once the remedy step on `Documents` was applied. But it
found two more ways to a false Pass. When the documents folder does not resolve, Windows PowerShell
5.1 searches the relative `WindowsPowerShell\Modules` in its working directory, where a module
turned the exit 2 of a denial into exit 0, while the set named the folder that 5.1 does not use, so
a closed profile without `Documents` passed (R12-08). And the remedy step left `WRITE_DAC` and
ownership of `Documents` to the identity, which could give itself the removed rights back
(R12-09).

### Findings

| ID | Severity | Where | Finding | Resolution |
|---|---|---|---|---|
| R12-01 | Major | hooks README, the remedy, gaps 1 and 3, row 201; this entry; `CHANGELOG.md` | Under the default profile access list the operator steps close the folders against writing, not against replacement: an account holds `FILE_DELETE_CHILD` on its own `Documents`, the kernel grants `DELETE` on any child of such a folder whatever the child's access list says, and the check passed until the move. Gap 1 said that a Pass describes the next start, and gap 3 promised that the next measurement fails a replacement, which runs after the next start has loaded from it | Fixed, in wording and code, as ruled. The README, this entry and the CHANGELOG take the reviewer's wording. On Windows a place of the module search set counts as writable while this identity holds `DELETE` on it, which folds in `FILE_DELETE_CHILD` on the folder that holds it; elsewhere, where `DELETE` is not measured, while the probe can write the folder that holds it, so that a run off Windows is not made unmeasured. The remedy also removes `FILE_DELETE_CHILD` and `DELETE` for the identity on `Documents`, and since R12-09 `WRITE_DAC` and `WRITE_OWNER` too, with an administrator as its owner. The folders above a place and the registry re-point stay residuals, and `DELETE` on the six escape entries stays in the backlog |
| R12-02 | Major | `Get-ModuleSearchSet`; `Test-HookContract`; README; this entry | Windows PowerShell 5.1's module folders were neither measured nor named as a residual. 5.1 runs the hook line under VS Code, searches `Documents\WindowsPowerShell\Modules` first when started from a logon environment, and auto-loads a module there that shadows a built-in cmdlet such as `Get-Variable` or `ConvertFrom-Json`; `HookContract` starts its 5.1 wrapper with the verifier's module path, so it cannot see such a module | Partly fixed, option 1 of the ruling: on Windows the set also names `<documents>\WindowsPowerShell\Modules` and `%ProgramFiles%\WindowsPowerShell\Modules`, named without asking whether they exist, and `Get-SearchPathProblem` still applies; the remedy covers `Documents\WindowsPowerShell`. Since R12-08, a local documents folder that does not exist names the relative entry that 5.1 then searches in its working directory, which is reported unmeasured. The guard's own exposure stays open, for brief 18: a fourth gap in the README, a line in its row 201, a remaining risk below, the S-18 rows and a limit in the CHANGELOG say so. They also say three things that R12-08 added: 5.1 searches its working directory when the documents folder does not resolve; a Pass of `WritableRoots` describes the state at the check; and every hook call starts 5.1 afresh, so that moving `Documents` aside or re-pointing it during a run reaches the guard, which brief 18 owns |
| R12-03 | Minor | README, the remedy; `Measure-EscapePath` | Only each place of the set is judged, not the modules inside it, and the remedy said nothing about an existing tree | Fixed in the words of the review: the remedy says to start the folders empty or to re-own an existing tree recursively (`takeown /R`, `icacls /reset /T`), and the residuals say that only each place is judged |
| R12-04 | Nit | `Measure-EscapePath`, the walk | "Closed below a file" ignored that an identity that can delete the file can put a folder in its place | Fixed for every entry, because Q3 applies the walk to every entry: a file above an absent place counts as writable when this identity can delete it (`DELETE` on Windows, write access to its folder elsewhere), as unmeasured when that cannot be measured, and as closed otherwise |
| R12-05 | Nit | `Get-ModuleSearchSet`; `Get-ContainmentCheck` | A profile path without a folder part silently dropped the user's configuration folder, and a throw of the set surfaced as exit 1 with no report | Fixed: an empty folder part throws too, and `Get-ContainmentCheck` turns a throw of `Get-ModuleSearchSet` into a `WritableRoots` result of `Unavailable` with the reason relayed, without measuring, so that the run gets its report |
| R12-06 | Nit | README, row 201 and the gaps; this entry; the docstring of `Measure-EscapePath`; `CHANGELOG.md` | Four wordings: `USERPROFILE` re-points the folders too; a symbolic link on the way to a share is opened; only the last component of a path is opened as a link; and the CHANGELOG left out "until it closes them" | Fixed as proposed |
| R12-07 | Nit | `tests/ContainmentVerifier.Flow.Tests.ps1` | No row pinned the trim (the reviewer's mutant M12 survived), and only the POSIX legs pinned the separator (M11) | Fixed: rows for a padded entry and, on Windows, a trailing dot; the separator now follows the platform the check measures, so that rows for `;` and for `:` run on every leg. Both mutants are caught |
| R12-08 | Major | `Get-ModuleSearchSet`; README, row 201 and gap 4; this entry; `CHANGELOG.md` (re-review) | Windows PowerShell 5.1 resolves the documents folder with verification, and when that folder does not exist or cannot be read, it puts the relative `WindowsPowerShell\Modules` first and resolves it against its working directory. With a module there, the shipped closing statement turned a denial (exit 2) into exit 0. The set named the unverified absolute path instead, so a profile closed to the identity and without `Documents` passed. During a run the identity can move `Documents` aside through its profile folder, or re-point it to a folder that does not resolve, and every later hook's 5.1 then searches its working directory | Fixed as proposed. On Windows the documents folder is still named without verification (`DoNotVerify`), and one on a share stays a network entry that is never asked whether it exists; a local documents folder that `Directory.Exists` does not find, or one that cannot be named, now names 5.1's relative entry, which `Get-SearchPathProblem` reports unmeasured, so the check fails closed. The records say that 5.1 searches its working directory when the documents folder does not resolve, that a Pass describes the state at the check, and that every hook call starts 5.1 afresh, so that moving or re-pointing `Documents` during a run reaches the guard, which brief 18 owns |
| R12-09 | Minor | README, the remedy; this entry; `CHANGELOG.md` (re-review) | The remedy step removed `FILE_DELETE_CHILD` and `DELETE` on `Documents`, but an account's full control of its profile includes `WRITE_DAC` there, and an account may own its `Documents`, so after the check it can give itself those rights back and move a closed folder aside; `Documents` is not a place of the set | Fixed as proposed: remove `FILE_DELETE_CHILD`, `DELETE`, `WRITE_DAC` and `WRITE_OWNER` for the identity on `Documents`, and have an administrator own it |

The reviewer's suggestion on defence is adopted as well: both `switch` statements of
`Test-WritableRoot` name `Closed`, and any other state goes to the unmeasured list.

### Earlier findings

| ID | Severity | Where | Finding | Resolution |
|---|---|---|---|---|
| S-18 | Nit | The review of 2026-10-14 | The module path was closed only for the three firewall cmdlets; adding the folders pwsh searches to the escape set of `WritableRoots` was a follow-up | Done for the folders `WritableRoots` measures: the module search set of this entry. Windows PowerShell 5.1's hook line stays open (R12-02, brief 18) |
| R11-01 | Minor | The review of 2026-11-13 | At least 26 exception texts of the verifier, the grants root and the paths of the escape set reached the evidence as they came, and `WritableRoots` joined its unmeasured lines without a cap | Partly resolved: every path and every reason that `WritableRoots` puts into its evidence is relayed, cut at 200 characters, and every list at 1,000, among them the two reasons of `Get-ObjectRight` that take the text of an exception (its lines 616 and 643) as `WritableRoots` uses them. Those reasons still reach `ControlImmutability` and `LedgerProtection` through `Test-PathProtection` as they come, and so do the other exception texts, the event names of `hooks.json` and the grants root: a brief of their own |

### Tests

- Test first, in groups, with the new functions present as stubs that returned nothing and a
  `-ModuleSet` that was ignored, so that each group failed on its assertion: of 124 tests in the
  Flow and Filesystem suites, 34 failed for the stated reason and 90 passed, the controls among
  them. The Flow case of the brief's Task 2 passed `WritableRoots` with a writable module folder
  ("Expected 'Fail', but got 'Pass'"), and its control with a closed one passed throughout; the
  wiring case saw no call of `Get-ModuleSearchSet`; nine cases of the module search set got an empty
  set; five cases of a place that does not exist read Pass where they expect Fail or Unavailable,
  while the controls with a closed folder above, with only the rights to add a file and delete a
  child above, and with a file above passed; ten cases of the module search set in `WritableRoots`
  passed where they expect Fail or Unavailable; and eight rows of `Get-SearchPathProblem` got
  nothing. Then 124 of 124 passed.
- The relay table, 29 rows, was written against that code, before any relay: every row failed for
  the stated reason, unprintable characters in the evidence or a path or a list that was not cut,
  and the other 60 tests of its suite passed. Then 153 of 153 passed. Two cases were added after the
  code they test, the refusal when the host sets no profile path and a configuration folder that is
  not opened and not asked whether its file exists; their mutants fail them.
- Mutants, on copies outside the working tree: 34, all caught. In the first round 6 of 32 survived:
  the relay of each path and reason was hidden by the relay of the joined list, which makes every
  text printable ASCII as well. The rows now use texts of more than 200 characters, so that only the
  cut of each text shows its relay, and all six are caught.
- Every `tests/ContainmentVerifier*.Tests.ps1` with Pester 5.7.1: 1,094 passed, 0 failed, 3 skipped
  by design (a POSIX case, the property test whose fresh seed only CI draws, and an elevation type
  this token does not have), in 252 seconds.
- PSScriptAnalyzer 1.25.0 with default rules: 0 findings on the verifier and both suites.
  markdownlint: 0 issues.
- The new tests are tagged `Unit`, mock every right they read, and build their paths with the
  separators of the platform, so they run on every leg of CI; the rows of network and device entries
  run on Windows only. Nothing ran on Ubuntu or macOS here, and the full gate runs after the review.
- The fix round, test first again, with `Get-ReplacementRight` present as a stub that denied
  everything, a `-Replaceable` switch that was ignored, and the two folder parameters of
  `Get-ModuleSearchSet` unused: of 179 tests in the Flow and Filesystem suites, 18 failed for the
  stated reason and 161 passed. R12-01: four cases of a module place that this identity can replace,
  or whose replacement cannot be measured, read Pass, on Windows by `DELETE` and off Windows by the
  folder above, and so did two relay rows; the control, a closed place off Windows whose `DELETE` is
  not measured, passed throughout, so that a run off Windows is not made unmeasured. R12-04: three
  cases of a file above an absent place read Pass, and two relay rows did too; the control that
  `DELETE` on an existing place of the escape set is still not counted passed. R12-02: the two cases
  that name the 5.1 folders on Windows, the second with a documents folder on a share, did not find
  them; the control that they are not named elsewhere passed. R12-05: the case of a profile path
  without a folder part threw nothing, and the flow case ended in the thrown error. R12-07: the row of
  the POSIX separator failed on this Windows host; the padded row, the trailing-dot row and the row
  of the Windows separator pin what the code already did, so mutants show that they can fail. The
  explicit `Closed` arm: two cases of a state that no branch names read Pass. Then 179 of 179
  passed. The rows of a platform run the verifier's own branch for it through `$script:OnWindows`,
  with every right mocked, so they run on every leg.
- Mutants of the fix round, on copies outside the working tree: the 34 of phase 2 with their text
  moved where the code moved, the reviewer's two survivors, and 23 new ones, 59 in all. 58 were
  caught at once. The phase 2 mutant that drops the refusal of a missing profile path survived,
  because the new refusal of a profile path without a folder part then threw the same "cannot be
  named" for it; both tests now pin their own reason, and it is caught. The reviewer's M11 (a split
  on `;` everywhere) is caught by the row of the POSIX separator and its M12 (no trim) by the padded
  row, on Windows too.
- Every `tests/ContainmentVerifier*.Tests.ps1` with Pester 5.7.1, after the fix round: 1,118 passed,
  0 failed, the same 3 skipped by design, in 257 seconds. PSScriptAnalyzer 1.25.0: 0 findings on the
  verifier and both suites. markdownlint: 0 issues.
- The second fix round, test first on `3eb5d8f`: the row of a local documents folder that does not
  exist found `<documents>\WindowsPowerShell\Modules` named instead of 5.1's relative entry, and the
  case of the reviewer's false Pass, a closed profile without a documents folder, read Pass; the
  other 179 tests passed, the row of a documents folder on a share among them, a control that keeps
  a share a network entry. The case that names the two 5.1 folders now creates its documents
  folder, which 5.1 needs, and a row for a documents folder that cannot be named pins the guard that
  keeps an empty name from `Get-SearchPathProblem`. Then 182 of 182 passed. Mutants: the 59 of the
  first fix round, two with their text moved, and 5 new ones: 63 of 64 caught. A mutant that turns
  a share into the relative entry is caught by the share row; one that asks a share whether it
  exists was not run, because it would reach the network, and by reading the same row fails under
  it. The reviewer's X09, the documents folder resolved with verification, survives, and is now
  equivalent in what the set names, except in two ways no unit test can show without the network
  access the check must not make: it reaches a share to verify it, and for a share it cannot reach
  it names the relative entry instead of the share, both unmeasured. Every
  `tests/ContainmentVerifier*.Tests.ps1`: 1,121 passed, 0 failed, the same 3 skipped, in 244
  seconds. PSScriptAnalyzer: 0 findings. markdownlint: 0 issues.

### Remaining risks

- A module loaded before the check. The check runs in the process it protects: pwsh auto-loads a
  module from these places as soon as a command of the verifier needs one, long before
  `WritableRoots` runs. A Pass says that the places this process searches were neither writable nor
  replaceable when it measured them, not what the measuring process already loaded.
- A re-pointed module folder. The account can re-point its documents folder, and with it its module
  folders and its configuration file, through its own `User Shell Folders` key, and whatever starts
  the next pwsh can re-point them through `USERPROFILE`, or set another `PSModulePath`. The check
  measures where this process looks, not where the next start will.
- Rights the check does not judge. Writable means that this identity can add a file or a folder, or
  delete a child, and for a place of the module search set also that it can replace the place.
  `WRITE_DAC` and `WRITE_OWNER` on a place, `DELETE` on a place of the escape set, and the rights on
  the folders above a place are not judged, beyond the `FILE_DELETE_CHILD` that the kernel folds
  into `DELETE` on a place of the module search set. So a folder that the identity owns reads closed
  and can be reopened, and an identity that holds `FILE_DELETE_CHILD` on a folder further up, as an
  account does on its own profile folder, can move a closed folder aside and create its own. The
  next start loads from it before any check runs, so a later measurement fails it only if what was
  loaded does not interfere. The operator steps of the hooks README (create the folders empty or
  re-own an existing tree, have an administrator own them, grant the run identity read access only,
  remove `FILE_DELETE_CHILD`, `DELETE`, `WRITE_DAC` and `WRITE_OWNER` for it on `Documents`, and
  have an administrator own `Documents`, because an owner holds `WRITE_DAC` whatever the access list
  says and could give itself the removed rights back after the check) close the folders against
  writing and against replacement from `Documents`, not against a rename of `Documents` itself
  through the profile folder, which an account can do by default, and not against the registry
  re-point.
- Only each place is judged, not the modules inside it: a writable module folder or file inside a
  closed place is not seen.
- Windows PowerShell 5.1 runs the hook line (R12-02, R12-08). Under VS Code, Windows PowerShell 5.1
  runs each hook line, the guard's included, and a containment profile normally pins it as the
  guard's interpreter; every hook call starts it afresh. Started from a logon environment, 5.1
  searches `Documents\WindowsPowerShell\Modules` first, and when the documents folder does not
  resolve, because it does not exist or cannot be read, it searches the relative
  `WindowsPowerShell\Modules` in its working directory instead. A module in either place shadows a
  built-in cmdlet: on the reviewer's copies, a module that exports `Get-Variable`, ahead of the
  system folder or in the working directory of a 5.1 whose documents folder did not resolve, turned
  the exit 2 of a denial into exit 0 in the closing statement of the shipped hook line. Under VS Code
  that working directory is likely a workspace the run writes (not measured). `WritableRoots` now
  measures the folder in the documents folder and `%ProgramFiles%\WindowsPowerShell\Modules`, and
  reports the relative entry unmeasured when the documents folder does not exist, but a Pass
  describes the state at the check: an identity that moves `Documents` aside through its profile
  folder during the run sends every later hook's 5.1 to its working directory, one that re-points it
  in its registry sends 5.1 wherever it points, and either reaches the guard. `HookContract` starts its 5.1 wrapper with the
  verifier's own module path, not the one a logon gives 5.1, so nothing tests the hook line as the
  host runs it. The guard's own exposure stays open, for brief 18.
- Only the text decides what is not opened: a drive letter that is mapped or substituted to a share,
  and a symbolic link on the way to a share, are opened like a local path, and the escape set is
  opened wherever it points, a temp folder on a share included.
- How a link is measured. On Windows the probe opens only the last component of a path as a link
  (`FILE_FLAG_OPEN_REPARSE_POINT`) and follows every link above it: a junction or a symbolic link at
  a place, or at the place above an absent one that the walk opens itself, is measured as the link
  and not as its target; a link above an existing place is followed, so that the place is measured
  in the target, which is also where pwsh loads from; and an absent place below a link that the walk
  measured would be created in that link's target. Off Windows the write probe goes through every
  link. It creates and removes a short-lived file in each folder it measures: a place, the nearest
  existing folder above a place that does not exist, and, since the fix round, the folder that holds
  a place of the module search set or a file above an absent place. A sticky bit on such a folder
  can refuse the identity a rename that the probe's write suggests, so the measurement errs towards
  replaceable.
- When the host sets no profile path, or one without a folder part, the folder of the user's
  `powershell.config.json` cannot be named. `WritableRoots` is then unmeasured, with the reason, and
  measures nothing, and the other checks keep their evidence. A `pwsh -File` start always sets one.
- The new digest of the verifier, as checked out (CRLF on every system, by `.gitattributes`):
  `d7d2b02f3202954e8a6a16d010c47786572fffb403ebb02a354c51d4923bf869`. The reviewed commit
  `0b7e4ab` hashed to `2cea2d645d4bc8cbbfadbd88a4f172e19f3060225e47b6d639d7dc1ee0aab8c3`, and the
  re-reviewed `3eb5d8f` to `754a2f9cd8ca3225361b42ee5dd31cd0c4acd9ce441e44228abc770c0f1c7094`. The
  appender is unchanged on this branch at
  `f55e163b02fe4db6d318bc3e8c3d8cc6c86c2bf365496ddf22cda5e812030572` (brief 13), and `hooks.json`
  and the guard are unchanged. Every containment profile has to re-pin the verifier, and
  `~/.copilot` has to be refreshed with `./Setup-CopilotSettings.ps1`.
- The remaining risks of the earlier entries that this change does not touch stay open: the rest of
  R11-01, `DELETE` on the six places of the escape set, the run id of `-Revalidate`, and the second
  Windows account. The run id of `-Revalidate` was bound later that day, for a profile that names
  its run; see the entry on the run id above.

## 2026-11-13: a replayed acknowledgement, S-19 (follow-up of prompt P5)

The Custom `security-reviewer` agent reviewed the change that closes S-19 of the review of
2026-10-14. The ledger client believed an acknowledgement once it had rebuilt the digest of the
record it sent at the acknowledged sequence and found it in the ledger. For a record identical to
one already stored, a server that replayed the earlier acknowledgement therefore passed every
check, and the client could not prove how many times a record was stored. The client now counts
the records in the sink before it sends and believes only a sequence after them. The owner chose
that form out of three: `sequence > n`, the `sequence == n + 1` that the reviewer of 2026-10-14
proposed, and recording S-19 as an accepted residual. The reviewer read the commit `27037b1` in a
fresh context, read-only, ran the suites and nine mutants of its own on copies under TEMP, scripted
the `-Seal` replay and nine states of the sink against a squatter, and said **Approve with
changes**: no Blocker, no Major, two Minors (R13-01, R13-02) and four Nits (R13-03 to R13-06). All
six were fixed in the same change. At the owner's request, the same reviewer then re-reviewed the
fixes in `e58dd0d` and said **Approve**: R13-01 to R13-06 resolved, and three new Nits (R13-07 to
R13-09), which are fixed too.

### Scope

- With one writer at a time, can a server whose pipe passes the client's identity check still make
  `-Append` or `-Seal` report a record that this send did not store?
- Is the count taken before any byte of the record leaves the client, and does every way it can go
  wrong give the right count or refuse without sending?
- Can the read of the sink before the send disturb the running service or change what it stores?
- Do the new tests fail without the change, and do they pin the boundary on both sides?
- Do the hooks README, the CHANGELOG, the comments and the commit message claim only what is shown?

### Verdict

**Approve with changes.** With one writer, the reviewer found no way for a server that passes the
identity check to make the client report a record that this send did not store: a client that waits
for each acknowledgement counts after the previous read-back, so k successful sends name k
different sequences. The S-19 replay is refused for `-Append` and, in a run of the reviewer's own,
for `-Seal`; `aea224e` believes both. Every failure of the count it provoked (a half-written last
line, a byte-order mark, an empty line, invalid UTF-8, a sink held without shared reading, and a
sink hidden by its access list) stopped the client before any byte of the record left it. The count
uses the share mode of the read-back the client already made, opens no handle on the chain head and
writes nothing, and an append through the real service and the service's own open of the sink both
succeeded with such a reader open. What it found was a test gap, wording that drew the window of a
concurrent writer too narrowly, and a count that leaned on `Test-Path`.

### Findings

| ID | Severity | Where | Finding | Resolution |
|---|---|---|---|---|
| R13-01 | Minor | `tests/LedgerAppender.Tests.ps1` | No test told the chosen form, `sequence > n`, from the form that was not chosen: a check written as `sequence == n + 1` passed every test, although it refuses an append that another writer overtook after it was stored, and the controller's retry would then store the record twice | Fixed: an in-process case accepts an append that another writer overtook (n = 0, sequence 2), and fails under that mutant |
| R13-02 | Minor | hooks README, `CHANGELOG.md` | The limit for a concurrent writer was drawn too narrowly. The window runs from the count until the client reads the ledger back, not until its own append, and the client waits for the answer without a deadline: only `Connect` is bounded, at 10 seconds. The README also said that requiring exactly the next sequence would close that limit, which it would not, because the other writer's identical record can be the next one. The design note of the brief said the same; the owner's ruling did not depend on it | Fixed in the README and the CHANGELOG as the reviewer worded it |
| R13-03 | Nit | `Invoke-LedgerAppender.ps1`, the count | Counting zero rested on `Test-Path -PathType Leaf`, whose `$false` also covers a directory and a sink that this identity cannot query. A directory was counted as no records, and the record was sent and refused only at the read-back; a hidden sink was refused before the send only because the `Test-Path` of PowerShell 7.6.10 writes an error that the script's `Stop` preference and `trap` turn into exit 2 | Fixed: `Get-StoredRecordCount` opens the sink and counts zero only for a `FileNotFoundException`, and any other failure refuses before the send with its reason. Red first: a pipe case with a directory as the sink, which the client of `27037b1` sent. Four in-process cases hold the count on every system |
| R13-04 | Nit | `tests/LedgerAppender.Tests.ps1` | That the new comparison runs last, so that the existing refusals keep their messages, was pinned only by a Windows pipe case: its in-process twin passed `-StoredBefore 0`, which is not the state it models | Fixed: the twin passes `-StoredBefore 1`, and fails when the comparison runs first |
| R13-05 | Nit | the message of `27037b1` | "Tests, red first" was too broad: the case that stores the same record twice is a positive control and cannot be red, and the in-process cases failed on `aea224e` only on the missing parameter | Recorded under Tests below and in the report. The commit is not rewritten |
| R13-06 | Nit | this file | The dated entry that closes S-19 and records the new digest was not in the commit | This entry. The older records that still called S-19 open point here |
| R13-07 | Nit | `Get-StoredRecordCount` (re-review) | One string, the exception's message, was both the flag that stops the send and the reason. An exception without text would have read as no error, so the client would have counted zero records and sent; no read failure on this path is known to raise one. And for a denied access, the reason follows the path in .NET's text, so on a long path the cut of the refusal line at 200 characters dropped it | Fixed: the error names the exception's type before its text. Red first: an in-process case whose read throws an exception with an empty message returned no error |
| R13-08 | Nit | this file, `activeContext.md` (re-review) | This entry said that no second review pass was asked for, and `activeContext.md` still placed the branch in local commits, although it was pushed | Fixed: this entry records the re-review, and the Memory Bank says pushed, not merged |
| R13-09 | Nit | `systemPatterns.md` (re-review) | The new pattern said that counting the sink proves which send stored a record, which holds only with one writer | Fixed in the reviewer's words, with the condition and the limit |

### Tests

- Test first, on `aea224e`: the pipe case of the identical replay failed for the stated reason, as
  the client exited 0 with "Appended sequence 1 as b29cc4f7…", and so did the pipe case of a
  half-written sink, whose record the client sent and refused only at the read-back. The in-process
  cases failed on the missing `-StoredBefore`. With the parameter and the count in place and the
  comparison not yet written, the in-process case of the identical replay failed on its assertion
  (an empty answer). The case that stores the same record twice through the real service is a
  positive control and passed throughout. In the fix round, the pipe case of a directory as the sink
  was red on `27037b1` for the stated reason, as the record was sent, and the four in-process cases
  of the count failed until `Get-StoredRecordCount` existed. After the re-review, the in-process
  case of a read that fails with an empty message returned no error on `e58dd0d` (R13-07), and
  passed once the error named the exception's type.
- Mutants, on copies under TEMP and never in the working tree: 5 in the first round and 9 in the fix
  round, all caught. They covered the boundary (`-lt`, n + 1, and `== n + 1`), the comparison moved
  first, a count error ignored, every error counted as zero, an absent sink refused, a count one too
  many, and the count not passed to the check. Of the reviewer's 9 mutants of `27037b1`, two
  survived: `== n + 1` (R13-01, now caught) and a count read from the chain head, which gives the
  same result with one writer. The sink is read for availability, which no test measures.
- The suites of the appender and of the verifier, on `27037b1`: 1,163 passed, 0 failed, 3 skipped
  by design (a POSIX case, the property test whose fresh seed only CI draws, and an elevation type
  that this token does not have). On `e58dd0d`: 1,169 passed, 0 failed, the same 3 skipped, in 431
  seconds. On the final tree, after the re-review: 1,170 passed, 0 failed, the same 3 skipped, in
  449 seconds.
- The full gate, `./build.ps1 -Tasks build, test`, on the tree of `e58dd0d`: 5,866 passed, 0
  failed, 145 skipped. On the final tree, after the re-review and before these results were written
  here (no test reads this file): 5,867 passed, 0 failed, 145 skipped, 91.54 % coverage against a
  threshold of 65 %, 21 build tasks and no error in 52 minutes, and the same 16 warnings as in
  earlier gates.
- PSScriptAnalyzer 1.25.0 with default rules: 0 findings on both changed scripts, at every
  severity. markdownlint: 0 issues.
- Nothing ran on Ubuntu or macOS here; the in-process cases run there in the pull request's CI.

### Remaining risks

- The trust boundary does not move. Only the appender's own account, or an administrator, can own
  a pipe that the client accepts, and that account can stop the service and write a chain that
  validates, because the chain is not keyed. The change removes a quiet way to make the client
  over-count while the service runs.
- A record identical to the client's that another writer appends after the client's count and
  before the client reads the ledger back is believed, and the client waits for the answer without
  a deadline. `sequence == n + 1` would not close this, and it would refuse every overtaken append.
- The client cannot prove that a record was not stored more often than it was sent, because the
  service's own account can append any record.
- A count that meets the half-written last line of another writer's append refuses before the
  send; the read-back after the send already had that race.
- The new digest of the appender, as checked out (CRLF on every system, by `.gitattributes`):
  `f55e163b02fe4db6d318bc3e8c3d8cc6c86c2bf365496ddf22cda5e812030572`. The reviewed commit
  `27037b1` hashed to `d1b763e680f39c07ccfe9e907781e150659dac2952962441b1d6b91dc5db06ce`, and the
  re-reviewed `e58dd0d` to `f0795f80364a253d5b87b5af3a0d2f6b7269de8a5e81e5215e6bfcae1122677b`. The
  verifier is unchanged at `d283ad9b099936a63bf52063b14a1b3a8a322da7732f619ae69c88c722581c24`. Every
  containment profile has to re-pin the appender, and `~/.copilot` has to be refreshed with
  `./Setup-CopilotSettings.ps1`.
- Not run: Ubuntu and macOS, Windows PowerShell 5.1, a live concurrent writer, and a second Windows
  account. The fix of R13-07 to R13-09 was not reviewed again; the reviewer said none of them
  needed another pass.
- The remaining risks of the earlier entries that this change does not touch stay open: R11-01, the
  escape set of `WritableRoots`, the run id of `-Revalidate`, and the second Windows account.
  The run id of `-Revalidate` was bound on 2026-11-14, for a profile that names its run; see the
  entry on the run id of that date.

## 2026-11-13: relayed exception texts, S-20, V-05 and W-03 (follow-up of prompt P5)

The Custom `security-reviewer` agent reviewed the change that closes S-20 of the review of
2026-10-14 and V-05 and W-03 of the review of 2026-10-16. The ledger appender now relays the
exception text of its two lines about a dropped connection through `Format-RefusalText`, and the
`HookContract` check of the verifier relays its four exception texts and the two closure details
of the interpreter through `Format-RelayedText`; the S-04 and S-05 functions that need no pipe are
tested on every system. The reviewer read the commit `8549642` in a fresh context, read-only,
reverted both scripts in a copy under TEMP to watch the new tests fail, ran cap mutants of its own,
and said **Approve with changes**: no Blocker, no Major, two Minors (R11-01, R11-06) and four Nits
(R11-02 to R11-05). R11-02 to R11-06 were fixed in the same change, R11-01 and the event names of
R11-03 are a recorded follow-up, and no second review pass was asked for.

### Scope

- Can a text from outside the two scripts still reach the two appender lines or the six verifier
  texts without the relay, and can a relay throw or change a verdict or a status?
- Do the new tests fail without the change and for the right reason, and do they pin the caps of
  200 characters and of 1,000 over the six closure details together?
- Does the gating meet the second half of S-20: the platform-neutral functions run on every
  system, and the cases that need the pipe stay Windows-only through `BeforeDiscovery` and `-Skip`,
  never `#requires`? Is anything in the new tests likely to fail on Ubuntu or macOS?
- Does the change alter an evidence string or a standard-error line beyond the relayed part?
- What must the records not claim?

### Verdict

**Approve with changes.** The eight relays are correct: the only outside text in either appender
line is the exception's message, both relay functions accept null and empty text, `-Limit 1000` is
inside the range `Format-RelayedText` takes, `EnumerateRunes` replaces ill-formed UTF-16 instead of
throwing, and no status string or branch condition changed. With both scripts reverted to
`0859e9e`, all eight relay tests failed for the intended reason, and the reviewer's six cap mutants
and a cap per reason failed too. With the platform probe forced off, 39 appender tests ran and 94
were skipped, nothing in the new tests is tied to Windows, and neither file uses `#requires`. What
it found was a path that still reached three of the six texts unrelayed, a test that did not run
the lines as the service runs them, a pipe-free case left Windows-only, and claims of the draft
changelog that went past the evidence. It also found the same class at sites this change does not
touch.

### Findings

| ID | Severity | Where | Finding | Resolution |
|---|---|---|---|---|
| R11-01 | Minor | `Test-RunContainment.ps1`, outside `Test-HookContract` | The class this change fixes for `Test-HookContract` remains at the verifier's other 24 `$($_.Exception.Message)` sites (20 reach the evidence directly or through a reason or a list, two go to `Write-Verbose`, two are "Containment refused" lines on standard error) and at two more that take a base exception's message. `ControlImmutability` and `WritableRoots` join every unmeasured line without a cap. Two paths come from this account's own settings: the grants root, from the LocalAppData known folder that this account can redirect (the reviewer read the ACL of the key and wrote nothing), and the temporary folder of the escape set. NTFS names allow tag characters | Not fixed, recorded as a follow-up: brief 11 names only the eight texts of this change. The reviewer's fix is to relay each text (200 characters each, 1,000 for a joined list), relay the grants root and the paths of the escape set, and add a syntax-tree test that fails on any exception message put into the evidence outside `Format-RelayedText` |
| R11-02 | Nit | `Test-HookContract` | The path of the interpreter still reached three of the six texts unrelayed: `Get-HookInterpreter` accepts a tab inside a quoted program word and a path of any length (the reviewer's probe passed one of 5,012 characters). The source is the digest-pinned hooks.json. The U-01 and W-03 rows say that the path is limited to printable ASCII, which is not exact | Fixed: the check relays the path once, at 1,000 characters, and every evidence string that names it uses the relayed text (five strings, the Pass included). Two tests, red first: a quoted path with a tab, and a path of 5,000 characters that is cut at 1,000. Two mutants caught: the path not relayed, and the path cut at the default of 200. The U-01 and W-03 rows point here |
| R11-03 | Nit | `Test-HookContract`, and `Test-GrantRecorderUnregistered` | The event names of hooks.json go into the evidence raw and uncounted, while the same function relays the keys it does not read and the hook type; and the new docstring sentence, "a text this check did not compose", read as a rule for every text | The sentence now names what is relayed: the message of an exception, a reason of the access check and the path of the interpreter. Not fixed, with R11-01: the event names |
| R11-04 | Nit | `tests/LedgerAppender.Tests.ps1`, the test of the service's two lines | The test was sound in finding and evaluating each line, but it ran without the script's `Set-StrictMode -Version 3.0`, and `$_` held a bare `IOException`, while `.Wait()` raises a `MethodInvocationException` around an `AggregateException`. A failure under strict mode, or a line that read `.Message` in place of `GetBaseException().Message`, would have passed | Fixed: the line runs under strict mode 3, and each error has the shape the service meets, with the chosen text only where the line reads. Three mutants caught: either line reading the other message, and a line that fails only under strict mode |
| R11-05 | Nit | `tests/LedgerAppender.Tests.ps1`, 'refuses a stored line whose extra field name only a culture folds into type' | The case runs `-Validate` in a child process and needs no pipe, the appender does not refuse that mode off Windows, and it covers `Read-StoredRecord`, which the new function tests do not; it was still Windows-only | Fixed: its `-Skip` is removed. The pull request's CI is its first run on Ubuntu and macOS |
| R11-06 | Minor | `CHANGELOG.md`, the draft | Four claims went past the evidence: that the tests run on Ubuntu and macOS (nobody had seen that run), that they are the tests of the S-04 and S-05 fixes that need no pipe (they are new in-process tests of three functions), that 24 other exception texts remain (at least 26 do), and that the closure details are .NET exception text (they are the reasons of the access check, which can carry it) | Fixed in the entry as the reviewer worded it |

### Tests

- Test first: on `0859e9e` the eight relay tests failed for the intended reason, each verifier
  case with 12 unprintable code units in its evidence and the two appender lines at 586 and 578
  characters where 249 and 241 were expected, and with the change they passed. The two R11-02
  tests failed the same way (a tab in the evidence, a path not cut) and passed with the fix.
- The new function tests of `Test-OrdinalEqual`, `Test-UtcInstant` and `Test-Acknowledgement`
  passed on their first run, because they cover code that already worked, so mutants proved that
  they can fail: `-ceq` in place of the ordinal comparison (3 tests failed), an instant checked by
  its shape only (5), and an acknowledgement that does not rebuild the record that was sent (1, and
  the positive control still passed). Nine more mutants caught the caps and the lines: two exception
  texts cut at 1,000, the closure details cut at 200 and per reason, and the five R11-02 and R11-04
  mutants above. Every mutant ran on a copy under TEMP, never in the working tree; the baselines
  passed (27, then 30, tests).
- The suites of the appender and of the verifier, on `8549642`: 1,156 passed, 0 failed, 3
  skipped by design (a POSIX case, the property test whose fresh seed only CI draws, and an
  elevation type this token does not have). The reviewer ran them too: the appender 133 of 133,
  `HookContract` 329 and 1 skipped by design.
- The full gate, `./build.ps1 -Tasks build, test`, on the final tree: 5,855 passed, 0 failed,
  145 skipped, 91.54 % coverage against a threshold of 65 %, 21 build tasks and no error in 51
  minutes, and the same 16 warnings as in earlier gates.
- PSScriptAnalyzer 1.25.0 with default rules was clean at every severity on the four files, before
  and after the fixes.
- Nothing ran on Ubuntu or macOS here, which have neither WSL nor Docker on this host; the pull
  request's CI is the first run of the new tests there.

### Remaining risks

- R11-01: at least 26 exception texts of the verifier, the event names of hooks.json, the grants
  root and the paths of the escape set still reach the evidence or standard error as they come.
  Most are localized .NET text around a path an operator chose, and two of the paths come from
  settings this account can change.
- The appender's two lines were evaluated from the syntax tree of the script with chosen errors,
  outside the service; no case drove them over the pipe. The review of 2026-10-14, not this
  change, traced that no client text reaches them, so for them the relay is hardening.
- The new digests: the verifier
  `d283ad9b099936a63bf52063b14a1b3a8a322da7732f619ae69c88c722581c24` and the appender
  `9ad77258631eb21f664140523acb682d1d278626ba726ce57bfb65411070064b`, the files as checked out
  (CRLF on every system, by `.gitattributes`). Every containment profile has to re-pin both, and
  `~/.copilot` has to be refreshed with `./Setup-CopilotSettings.ps1`.
- Not run: Ubuntu and macOS, Windows PowerShell 5.1, the live service under real faults of the
  pipe, the known-folder redirection end to end (it needs a registry write), how long the .NET
  message of the read test is on a localized Windows, and a second review pass of the fixes.
- The remaining risks of the earlier entries that this change does not touch stay open: S-19, the
  escape set of `WritableRoots`, the run id of `-Revalidate`, and the second Windows account.
  S-19 was closed later that day; see the entry on S-19 above. The run id of `-Revalidate` was
  bound on 2026-11-14, for a profile that names its run; see the entry on the run id of that date.

## 2026-11-09: the R-04 closing test on a standard account's token

Not a review: the measurement that the entry of 2026-10-15 left open, run on the owner's
yes on Prox1 (Windows Server 2025 Datacenter, build 26100; PowerShell 7.6.9). A one-off
script created a throwaway local account, added it to `Users` and no other group, logged it
on with `LogonUser` (interactive logon), read the token by handle with the verifier's own
reader (`ConvertTo-TokenFact` over `NativeToken.Read`, loaded from the verifier at digest
`dd415737…2415` the way the Pester suites load it), and judged it with the unchanged
`Test-IdentityPrivilege`. The same run removed the account, and no profile was created.

- **Result: Pass.** Not elevated, elevation type Default, Medium integrity (`S-1-16-8192`),
  no Administrators group, and two of the five privileges: `SeChangeNotifyPrivilege`
  (enabled) and `SeIncreaseWorkingSetPrivilege` (disabled). Windows also answered that the
  token is not in the Administrators role.
- **Groups.** Apart from the integrity label `S-1-16-8192`, which equals the integrity
  level, every group was enabled, and none was deny-only. So neither suggestion of the
  2026-10-15 review (match the label against the level, and list the groups a process could
  re-enable) would have refused this account.
- **Still open.** One build and one logon type: a client edition, another build, a batch or
  service logon, and an account in more groups were not measured. The test is not part of
  the suites, because it creates an account.

## 2026-10-18: a second colon in the program path, S-33 (follow-up of prompt P5)

The built-in `security-review` agent reviewed the change that closes S-33, the Nit that the
review of 2026-10-14 left open: `Get-HookInterpreter` of `Test-RunContainment.ps1` refuses a
program path that holds a second colon, after the one that ends the drive letter. The Custom
`security-reviewer` agent could not start (the model its definition names is not available in
this runtime), so, as for the change of 2026-10-16, the built-in agent took it. The reviewer
read the commit `d4aa90b` (`git diff 1de0c04..d4aa90b`), read-only and in a fresh context, ran 111
program words (196 lines, quoted and not) through the old and the new function in separate
processes, compared what `CreateFileW` opens for the raw word and for the normalized path, and
said **Approve with changes**: no vulnerability, one Minor (Z-03) and five Nits (Z-01, Z-02,
Z-04 to Z-06). Every finding was fixed in the same change. No second review pass was asked
for: the fixes change two test rows, one reason string, comments and records, and not the
logic of the rule.

### Scope

- Can a program word pass `Get-HookInterpreter` whose measured path (`GetFullPath`, later opened
  with `CreateFileW`) is not the file the word appears to name, other than the documented residual
  of a mapped drive or a `subst`?
- Does the new rule refuse anything that a legitimate deployment needs, change another message
  that a test or a consumer reads, or sit in the wrong place among the other rules?
- Do the new test rows fail without the rule, and for the right reason, and are they enough?
- Do the README, the CHANGELOG, decision 0025 and the Memory Bank claim more than the code and
  the measurements show?

### Verdict

**Approve with changes.** The reviewer found no security vulnerability. The rule only removes
lines from the accepted set: in its samples nothing went from refused to accepted, and no
returned path changed. It sits after the `IsPathFullyQualified`, dot-segment and drive rules and
before the program-word and name rules, it cannot refuse a real Windows program path (a file name
has no colon there), it is linear (39 ms on 4,000,000 characters without a colon), and no
accepted program word it could build opens a file other than the one the text names. What it
found was an inaccurate sentence about what the old spellings did, an over-broad claim, two
missing test rows, three stale places in this file, and a wording that read literally forbade
the drive's own colon.

### Findings

| ID | Severity | Where | Finding | Resolution |
|---|---|---|---|---|
| Z-01 | Nit | CHANGELOG, commit message | They said that the two old quoted spellings "failed closed later, at 'the interpreter does not exist'". Measured: `File.GetAttributes` throws an IOException with HRESULT 0x8007007B (error 123) for both, and `Get-ObjectRight` maps only a file-not-found and a directory-not-found error to Absent, so both end as Unknown and `HookContract` ends at "could not be shown to be closed" (Unavailable), never at "does not exist". Only a stream on the program itself (`powershell.exe:x`) is a file-not-found, and the name rule already refused that. I re-checked the three `GetAttributes` results. Decision 0025 and the S-33 row said "or could not be measured", which is the right half | Fixed: the CHANGELOG, decision 0025 and the commit message say that the check ended at "could not be measured" (Unavailable) |
| Z-02 | Nit | the five rows | All five used an upper-case `C:`, so the drive-letter class of the rule was untested: two changes that narrow it (`[A-Z]` only, and `C` only) survived all five rows and would let `"c:\:\...` and `"D:\Tools\a:b\..."` through. `Match = 'colon'` is also a part of "semicolon" | Fixed: two rows (a lower-case drive letter, and a folder name on drive D), and every row now matches the phrase `second colon`. The changes S12 (upper case only), S13 (`C` only) and S14 (lower case only) are caught, S12 by the lower-case row alone and S13 by the two new rows, and S15 (the reason says "colon" without "second") is caught too |
| Z-03 | Minor | decision 0025, commit message | "The drive rule now closes every spelling of a program path that starts on a local drive" is stronger than the change shows. The function still accepts, with `Problem = $null`, quoted spellings that name no file or another folder than the one shown: a folder name with a trailing space or made of a dot and a space (error 3), a wildcard, a pipe or a tab (error 123), `C:\\?\UNC\server\share\...` (it collapses to `C:\?\UNC\...`, error 123, no network access), and an unquoted `...\v1.0\...\powershell.exe` (error 3). The reviewer measured 39 such lines among 76 accepted ones, and the other 37 open the file the text names (volume and file index compared for the raw word and the normalized path, 0 mismatches). They fail closed at the measure, and a quoted program path cannot pass the wrapper runs anyway, so there is no security impact | Fixed in the claim: decision 0025, the CHANGELOG and this entry say that the rule closes the spellings with a second colon, and the other spellings are recorded as the same Nit |
| Z-04 | Nit | this file | Three places still called S-33 open (the 2026-10-16 entry: "stays a recorded Nit"; the S-33 row: "Not fixed, a recorded follow-up"; a remaining risk of the 2026-10-14 entry: "a follow-up with a one-line fix and two test rows"), and the row described another fix than the one built: `\A[A-Za-z]:[\\/][^:]*\z` in the drive rule, where the built one is a separate rule with its own reason | Fixed: the three places point to this entry, and the row says what was built |
| Z-05 | Nit | the comments and the reason in the verifier, README, CHANGELOG, decision 0025 | "No colon after the drive letter" read literally forbids the drive's own colon, since `C:` is a colon right after the drive letter. The texts also said that the old rule "read only the first two characters", where it read three (`C:\`) | Fixed: "a second colon, after the one that ends the drive letter" everywhere (the reason of the check now says "has a second colon, after the one of the drive letter"), and "three characters" |
| Z-06 | Nit | `progress.md` | The front matter `last-verified` was not bumped | Fixed |

### Tests

- Test first: the five rows of the first build were red against the old function (5 failed, 105
  passed) and green with the rule (110 passed). For the fixes the seven rows were red on the old
  reason (7 failed, 105 passed) and green with the new one (112 passed).
- Mutation checks: 15 changes of `Get-HookInterpreter`, applied one at a time to the verifier,
  each in a child process over the `Hook interpreter` tests, the file restored byte for byte
  after each. The rule never fires, fires only for a quoted word, fires only for an unquoted
  word, needs a separator after the colon, looks at the last component only, looks right after
  the drive only, takes a backslash after the drive only, needs a character before the colon,
  counts the colon of the drive, loses the second colon in the reason (two ways), still returns
  the path with the problem, and three changes that narrow the drive letter. All 15 were
  caught and none survived; the first 11 were run and caught before the review.
- Differential run: 200,000 generated lines (seed 20261018) through the function of
  `origin/main` and the new one: 90,498 accepted by both, 92,391 refused by both, 17,111
  accepted and then refused, every one with a colon after the drive letter, 0 refused and then
  accepted, 0 with another path, 0 thrown, and 0 words with a colon after the drive that the
  new function still accepts. The reviewer repeated it on a sample of 20,000 lines (1,700
  changed, the same pattern) and on 7,000 random edits of a real path (10,240 lines): 820 fewer
  accepted, exactly the lines with a colon after the drive, and none that opens another file.
- Full `build,test` gate on `d4aa90b` (the first build): 5,374 passed, 0 failed, 147 skipped,
  90.84 % coverage against a threshold of 65 %, 21 build tasks and no error, 48 minutes, and the
  same 16 warnings as in earlier gates. The fixes after it change two table rows, one reason
  string, comments and records, so the owner ruled a focused run and no second full gate (CI runs
  the whole suite again on the pull request): the 13 `ContainmentVerifier*` suites, the four
  Memory Bank suites, `SharedLifecycle`, `CiAdmission`, `PluginManifest`, `PluginManifestRollover`,
  `SoftwareEngineerAgent` and `DevelopmentCycle`, 23 files in all: 1,060 passed, 0 failed, 2
  skipped. The `Hook interpreter` tests alone: 112 passed.
- PSScriptAnalyzer 1.24.0 was clean at every severity on the verifier and the suite.
- Nothing could run on Ubuntu or macOS here. The `Hook interpreter` tests are skipped there.

### Remaining risks

- Quoted spellings that name no file still pass the text rules and fail closed at the measure
  (Z-03): a wildcard, a pipe, a tab, a folder name with a trailing space or made of a dot and a
  space, and `C:\\?\UNC\...`. Refusing the characters that Windows rejects in a name would make
  the rule complete for them; no verdict depends on it.
- A drive letter that is a mapped network drive or a `subst` cannot be seen textually, and
  measuring it needs the mappings of the verifier's own logon session. The reviewer's host maps
  `Z:` to a network share, which is exactly this residual; no `Z:` path and no UNC path was
  opened.
- Not run: the wrapper runs for the accepted quoted spellings (a quoted program path cannot pass
  them), Windows PowerShell 5.1 and POSIX, and a second review pass of the fixes.
- The Custom `security-reviewer` agent cannot start in this runtime until the first entry of its
  `model` array resolves or the dispatch falls back.
- The remaining risks of the 2026-10-14, 2026-10-15 and 2026-10-16 entries that this change does
  not touch stay open: S-19, S-20, the escape set of `WritableRoots`, the run id of
  `-Revalidate`, the second Windows account, and the unrelayed exception texts. The property test
  with a fresh seed in CI, which was on that list, is done (see the CHANGELOG). S-20 and the
  unrelayed exception texts of the hook check were closed on 2026-11-13; see the entry of that
  date. S-19 was closed on 2026-11-13 too; see the entry on S-19 of that date. The run id of
  `-Revalidate` was bound on 2026-11-14, for a profile that names its run; see the entry on the run
  id of that date.

## 2026-10-16: the pinned hook line under the wrappers of the documented hosts (follow-up of prompt P5)

The built-in `security-review` agent reviewed the change that runs the pinned hook line
under the wrappers of the two documented hosts: the `HookContract` check of
`Test-RunContainment.ps1`, the second follow-up of the P5 review after R-04. The Custom
`security-reviewer` agent could not start: the model its definition names is not
available in this runtime, the dispatch does not fall back to the next entry, and the
model was not overridden. The reviewer read the three commits of the first build
(`fd66a5e`, `7ffe3d4`, `d2da113`), read-only and in a fresh context, ran a Node `spawn`
built from the arguments it read in VS Code's spawn code, and said **Approve with
changes**: no Blocker, no Major, three Minors (U-01 to U-03) and four Nits (U-04 to
U-07). Every finding was fixed in the same change, test first, with a mutation check for
each rule a test can reach. The same agent then checked the fixes (`d2da113..f2e46e9`)
and said **Approve with changes** again: no code defect, one Minor and four Nits (V-01
to V-05). They were fixed in the same change too. A last confirmation of those fixes
(`f2e46e9..ecd82fc`) said **Approve**: no code issue, and four Nits in the records
(W-01 to W-04), fixed in the same change. The final gate is recorded under Tests.

### Scope

- Can `HookContract` report a Pass for a line that a documented host would not block,
  or for a wrapper program that the run identity can replace?
- Is the order right: the closure of the interpreter and of each wrapper before any
  process of the probe starts, `cmd.exe` first, and each wrapper measured even if the
  first one fails?
- Do the two rebuilt spawns hand the line on as the hosts do (arguments, the line as one
  argument, environment), and do they give the exit codes the hosts would see?
- Does anything a spawn writes, or a path the verifier does not control, reach the
  evidence unrelayed?
- The failure modes: a hang, a time-out, a missing wrapper, a Microsoft Store install,
  the cost in time.
- Do the tests fail when a control is removed, and do they behave on Ubuntu and macOS,
  where the Windows-only suites skip?
- Do the hooks README, the controller text, decision 0025, the changelog and this file
  claim more than the code and the measurements show?

### Verdict

First build: **Approve with changes**: no Blocker, no Major, 3 Minors, 4 Nits. Apart
from the missing invariant of U-06, which no production path reaches, the reviewer found
no way for the check to report a Pass for a line that a documented host would not block,
or for a wrapper that the run identity can replace. The weaknesses it found were a path
that reached the evidence unrelayed, statements that went beyond the evidence, and two
rules that no test could see.

Delta check of the fixes, on `f2e46e9` (`d2da113..f2e46e9`): **Approve with changes**: no
code defect, no Blocker, no Major, 1 Minor (V-03) and 4 Nits (V-01, V-02, V-04, V-05).
All seven first findings stay fixed in code and tests, and nothing in the delta opens a
new false Pass or a new path for misleading evidence. The reviewer re-ran its U-01
reproduction on a copy of HEAD, scripted `Test-HookContract` with 0, 1 and 3 wrappers
listed, scripted four quoted-path cases, and tokenised both commits to show that the
`[OutputType]` change is attribute-only. What it found was wording in the records and in
the comments of the script, one test that did not pin the cap, and a first sweep for U-03
that was not repository-wide.

Final confirmation of the delta fixes, on `ecd82fc` (`f2e46e9..ecd82fc`): **Approve**:
V-01 to V-05 are resolved, `eff87a8` changes no behaviour beyond one evidence string, and
the reviewer found no code issue. Four Nits remain, all in the records (W-01 to W-04), and
none needed a change of the verifier, so the gate that ran on `ecd82fc` stays valid for the
code.

### Findings

| ID | Severity | Where | Finding | Resolution |
|---|---|---|---|---|
| U-01 | Minor | `Get-HookWrapperProblem` | The reason of a `Violation` or an `Unmeasured` entered the evidence without `Format-RelayedText`, although the path next to it was relayed. The path of the second wrapper is `MainModule.FileName` of the verifier's own `pwsh`, and nothing limits it to printable ASCII. Reproduced with the real `Test-PathProtection` and a wrapper in a folder named with an accent and four tag characters (a hidden "PASS"): they reached a 1,425-character Fail evidence verbatim. The interpreter's path is limited by `Get-HookInterpreter`, so the same pattern for the interpreter is safe for the path (the access check's reason is another matter: W-03). The result can only be Fail or Unavailable, and it needs someone who chooses where the verifier's `pwsh` runs from | Fixed: both reasons go through `Format-RelayedText` with the largest cap the function takes (1,000 characters). Tests with an accent and four tag characters (five `?`) for the Violation and for the Unmeasured, and a length bound; mutations G13 and G14 (either relay dropped) and G15 (the cap cut at one site) were caught, but the delta check showed that the bound did not pin the value of the cap (V-04). Corrected on 2026-11-13 (R11-02): a quoted program word may hold a tab and has no length limit, so the interpreter's path is not limited to printable ASCII; the check now relays it |
| U-02 | Minor | this file | S-21 called the wrapper run "a follow-up", S-24 said "Partly … the check still passes a quoted path", and Remaining risks said the probe "is not a measurement under either" and that a quoted path "passes the check" | Fixed: this entry, and the S-21 and S-24 rows and the two bullets of the 2026-10-14 entry are annotated with the date and a pointer |
| U-03 | Minor | the runtime evidence of the check, README, CHANGELOG, decision 0025 | Four places said that exit 1 "does not block" under both wrappers. That holds for VS Code only (1.142.0, `HookExecutor`: an exit code of 2 blocks, any other non-zero code is a warning). The README's own statement for the Copilot SDK host is that it fails closed on every non-zero exit and denies the call. The verdict is right either way, but the sentence the controller reads was wrong for the second wrapper | Fixed: the runtime evidence says that VS Code treats exit 1 as a warning and the SDK host denies every call on it; the README, the CHANGELOG, decision 0025 and the S-21 and S-24 rows of this file say the same. Tests assert the wording and refuse "does not block"; mutations Q01 and Q02 were caught. The sweep for these four places missed four more (V-03) |
| U-04 | Nit | comments of the check, README, CHANGELOG, decision 0025 | "Neither documented host starts `cmd.exe`" is true only by default. VS Code 1.142.0 (`X8a`) uses the PowerShell form only when `ComSpec` names `cmd.exe` and `SystemRoot` or `WINDIR` is set; otherwise it uses `shell:true`, which Node starts as `cmd.exe /d /s /c "<line>"` when `ComSpec` is unset or names `cmd.exe`, and as `<ComSpec> -c <line>` when it names another shell (this entry first said only the first form: V-01). It also finds PowerShell through `%SystemRoot%` and not through a search path. No verdict gap: the `cmd.exe` leg stays required | Fixed: the text says "by default" and names the condition, and says that VS Code starts Windows PowerShell from `%SystemRoot%\System32` and the SDK host starts `pwsh` by name. The fallback forms (`cmd.exe /d /s /c` and `<ComSpec> -c`) and the `POWERSHELL_UPDATECHECK=Off` that VS Code sets are listed among what no run covered. The facts about VS Code were read in its 1.142.0 bundle on this host, and none was run |
| U-05 | Nit | four evidence strings, the Pass evidence, the quoted-path note, a docstring | (a) The closure failures said "the hook command was not run under it", but nothing ran at all, since closure precedes the canary, and a reader could take the `cmd.exe` leg to have passed. (b) The Pass evidence said the program of each wrapper comes from the README's table, but it is this check's own choice by absolute path. (c) The quoted-path note was keyed on "a wrapper failed" and not on the codes, so a quoted line that fails under a wrapper for another reason, a time-out for one, still asserted a parse error. (d) A docstring said an absent wrapper is judged "as for the interpreter", but an absent interpreter is Fail and an absent wrapper is Unavailable | Fixed: (a) says "so the hook command was not run" in all four strings; (b) says that the arguments are the table's and the program is this check's own choice; (c) states what is known, that PowerShell reads a quoted program path as an expression and that a wrapper that exits 1 for every payload has not parsed the line, and no longer asserts a parse error; (d) names both outcomes. Tests assert the wording; mutations W01 to W04, P01, Q01 and Q02 were caught |
| U-06 | Nit | `Test-HookContract` | The verdict has no invariant on how many wrappers it measured. In a scratch run with `Get-HookWrapper` returning an empty list, `Test-HookContract` returned Pass. No production path reaches it: `Get-HookWrapper` returns a literal pair, and tests hold it at two | Fixed: on Windows, a count other than two is `Unavailable`, with the count in the evidence and before anything runs. Rows for 0, 1 and 3, and five mutations (N01 to N05) that were caught |
| U-07 | Nit | `ContainmentVerifier.HookContract.Tests.ps1` | Nothing asserted that `NoDefaultCurrentDirectoryInExePath` reaches a wrapper spawn, and none of the 72 mutations touched it: on a scratch mirror that skipped it under a wrapper, "running a line under a wrapper" still passed 12 of 12. No security effect, since the paths are absolute, but the docstring promises the same environment | Fixed: two tests under each wrapper (the variable is set, and it survives an attempt to remove it); mutation E01 was caught |
| V-01 | Nit | README, CHANGELOG, decision 0025, the U-04 row and a remaining risk of this entry, two comments of the verifier | "Otherwise VS Code runs `cmd.exe /d /s /c "<line>"`" is false for a `ComSpec` that names another shell: `X8a` falls back to Node's `shell:true`, and Node reads the host's own `ComSpec`. With it set to the path of `pwsh`, the spawn was `pwsh.exe -c <line>`, a form that runs the profile. It is `cmd.exe /d /s /c` only when `ComSpec` is unset or names `cmd.exe`. The first report said "reproduced" for the unset and default cases only, and the records copied it. A sentence of the changelog also read as a double negative and dropped the `SystemRoot` and `WINDIR` condition | Fixed: each says that the PowerShell form needs `ComSpec` to name `cmd.exe` and `SystemRoot` or `WINDIR` to be set, and that otherwise Node runs the line as `cmd.exe /d /s /c` (`ComSpec` unset or `cmd.exe`) or as `<ComSpec> -c <line>` (another shell), a form that no leg of the check runs and that the launcher owns. The two comments of the script now say the same, and that the first spawn only approximates the first form (it runs a script file under `cmd.exe /d /c`) |
| V-02 | Nit | CHANGELOG, decision 0025, the README row, the runtime note of the check, this entry | Facts that were only read were worded as done or measured: (a) "a push went ahead", though no push ran; (b) the host treatment of exit 1 sat inside text that ends "measured on 2026-10-16"; (c) the runtime note stated both host behaviours as fact; (d) this entry said that the reviewer "ran VS Code's own spawn call from Node" (it ran a Node `spawn` built from the arguments it read in `X8a`) and that "the kill of the process tree held" (it read `Kill($true)`; no time-out occurred in its runs, and it observed only the clean-up of the temporary folder); (e) the U-07 row said "one test under each wrapper", where there are two | Fixed: (a) "would go ahead"; (b) the parse error is the measured part, and what exit 1 does is read, as the README states and the VS Code bundle shows; (c) the note begins "As the hooks README states" and says "would go ahead", with a test and mutations Q01 to Q05; (d) and (e) reworded |
| V-03 | Minor | the S-25 row of this file, decision 0025 (the `#` example), three comments of the suite | The sweep for U-03 was incomplete: they still said that exit 1 for a push "does not block" or "was not blocked" under both wrappers, where the README says that the SDK host fails closed on every non-zero exit | Fixed: the S-25 row is annotated like S-21 and S-24, and the decision and the comments say that VS Code treats exit 1 as a warning and the SDK host denies the call. The sweep this time covered `docs/`, `.memory-bank/`, `tests/`, `com.github.copilot/`, `skills/`, `source/`, `.github/`, the changelog and the README, for "does not block", "not blocked", "goes ahead" and "went ahead". What remains is intended or about other things: the assertions that refuse the old wording, quotations of it in this file, a historical finding in `assessment-log.md`, and hooks that never block a session |
| V-04 | Nit | the relay test of `ContainmentVerifier.HookContract.Tests.ps1`, mutation G15 | The cap was not pinned. The six assertions of the test, run by hand against mutated copies of `Get-HookWrapperProblem`, passed when `-Limit 1000` was dropped at either site (the default is 200) and when each reason was cut at 1,000 on its own (up to about 6 KB for six reasons); only G13 to G15 were caught, and G15 (`-Limit 1` at one site) is not an edit anyone would make | Fixed: the test holds six reasons of 3,000 characters and a length between 1,050 and 1,500, so the default cap and a cap on each reason fail. Mutations G16 to G19 (the default cap and a cap on each reason, at either site) were added and caught, one failing test each |
| V-05 | Nit | the docstring of `Get-HookWrapperProblem` | "Like every other text this check did not compose" is false: four `$($_.Exception.Message)` texts of `Test-HookContract` still reach the evidence unrelayed | Fixed: the docstring says "as Measure-HookWrapper does for the texts it relays". Not fixed, recorded: all four lines exist unchanged at `origin/main`, and so do the two closure details of the interpreter (W-03), so relaying them is a separate change, to be made with S-20. Closed on 2026-11-13; see the entry of that date |
| W-01 | Nit | this entry | The committed text still held the placeholder "the final gate is the next item", and its introduction said that the change "was gated again" while the only finished gate predated the V fixes | Fixed: the gate on `ecd82fc` is recorded under Tests, and the introduction points there |
| W-02 | Nit | this entry (Tests) | "The delta round changed … one attribute (the `[OutputType]` …)" is wrong: the attribute changed in `01b0e31`, in the first round. `eff87a8` changed comments and one string literal of `Test-HookContract` only | Fixed: the attribute change is placed after the 88-mutation run, where it happened, and the delta round is said to have changed comments and one evidence string |
| W-03 | Nit | this entry (Remaining risks), the U-01 row | "Four `$($_.Exception.Message)` texts" is true but incomplete: the two closure details of the interpreter (lines 2885 and 2891 of the verifier at `ecd82fc`, `$detail`) also pass the access check's reason unrelayed, and that reason is localized .NET text from `GetBaseException().Message`. The interpreter's path is limited to printable ASCII, but the reason is not; the first review's remark that the interpreter pattern "is safe" covered the path only | Fixed in the records: the follow-up reads "four texts and the two closure details of the interpreter", and the U-01 row says that the safety covers the path. Not fixed, recorded: both are older than this change (the same lines exist at `origin/main`), so relaying them is a separate change, with S-20. Closed on 2026-11-13 with S-20, the path of the interpreter included, which is not limited to printable ASCII after all (R11-02); see the entry of that date |
| W-04 | Nit | `com.github.copilot/hooks/README.md` lines 50, 1171 and 1190 | They said flatly that both hosts run the launcher in an outer PowerShell, or that VS Code hands the command to a PowerShell shell, where the `HookContract` row says that VS Code does so only when `ComSpec` names `cmd.exe` and `SystemRoot` or `WINDIR` is set | Fixed: "by default" in the three places. The `HookContract` suite, the only one that reads this README, was run again: 239 passed, 0 failed |

What the reviewer confirmed sound:

- **No false Pass** apart from U-06. The precedence is Fail over Unavailable over Pass;
  both wrappers are measured once `cmd.exe` passed, and skipping them after a `cmd.exe`
  failure is safe because that is already a Fail; exit codes are compared exactly; a
  throw is Unavailable; a payload that takes as long as the hook's time-out is a Fail;
  the POSIX probe is unchanged.
- **Order and trust.** Nothing is spawned before both closures, and a test with
  `Invoke-HookPayload` mocked asserts zero calls. `Get-HookWrapper` runs once, and the
  object that was closed is the object that is spawned, so the window between check and
  use equals the interpreter's. `MainModule.FileName` keeps the spelling of the launch: a
  `pwsh` launched through a junction reported the junction path, so the reparse-point rule
  gives a Fail and does not measure another file.
- **The same argument and environment as the hosts.** A Node `spawn` built from the
  arguments the reviewer read in VS Code's spawn code (VS Code's own code did not run),
  with the shipped line, gave 0, 2, 2 with an unquoted program path, 1, 1, 1 with a
  quoted one and 0, 2, 2 with a leading `&`: the results of the .NET `ArgumentList` spawn.
  The `pwsh -nop -nol -c` form matches too, and a `pwsh` 7 interpreter at a path without a
  space gives 0, 2, 2 under `cmd.exe` and both wrappers. Every spawn uses one
  `Invoke-HookPayload` path and one environment dictionary.
- **Relay.** What a spawn writes is never read into the evidence, and a test with a real
  parse error asserts that.
- **Failure modes.** About 1.0 to 1.3 seconds per payload under a wrapper, a worst case
  bounded under four minutes (from the time-outs in the code), and the clean-up of the
  temporary folder held. The kill of the process tree was read in the code, and no
  time-out occurred in the reviewer's runs.
- **Closure under a filtered token.** Re-running the author's script, both wrappers came
  out closed, the temporary-file control was writable, and the elevated token was not
  closed.
- **Tests on Ubuntu and macOS.** The new tests sit inside the skipped `Describe`, the
  data blocks are static, and the top-level `BeforeAll` only parses function text.

It could not verify: the Copilot SDK host's real spawn and its handling of exit codes
(there is no `copilot-runtime` on this host, so only the README's captures exist); a run
on a standard-account token (`IdentityPrivilege` refuses this administrator, so only the
closure under a filtered token was measured); a Microsoft Store `pwsh`; Ubuntu and macOS;
Constrained Language Mode and AppLocker; the mutations, the test file and the gate; and
the claim of about 85 seconds more for the suite.

What the delta check confirmed sound:

- **U-01.** Re-run on a copy of HEAD, the evidence was 1,229 characters, none outside
  printable ASCII, and ended in `...`. Both sites are relayed, and 1,000 is the largest
  cap `Format-RelayedText` takes.
- **U-06.** With the spawns replaced and 0, 1 and 3 wrappers listed, `Test-HookContract`
  gave Unavailable each time, with the count in the evidence and no spawn. The check sits
  before the closure loop and the work folder.
- **U-05.** All four closure strings say "so the hook command was not run", which is true
  because closure precedes every spawn. In four scripted cases (both wrappers 1, 1, 1;
  one wrapper over the time-out; one wrapper 0, 0, 0; unquoted with a wrapper 0, 0, 0) the
  quoted-path note appeared only with a quoted path and a failing wrapper. It no longer
  asserts a parse error, so it is true wherever it can appear: a quoted program path fails
  to parse in both builds, so a wrapper that ran gives 1 for every payload, and a time-out
  cannot be caused by the quote, which the note does not claim.
- **U-07.** The second test removes the inherited variable, so it is not vacuous when the
  ambient environment already sets it. E01 is exactly the mutant that had survived.
- **`[OutputType]`.** Tokenised without comments, both commits hold 71 functions and three
  differ (`Get-HookWrapper`, `Get-HookWrapperProblem`, `Test-HookContract`);
  `Get-HookWrapper` differs in one token of 152, `pscustomobject` to `object`, so that
  change is attribute-only.
- **The 16 new mutations.** Fifteen are sensible edits; G15 was the weak one (V-04).
- **The tests and the records.** The row for 0 wrappers relies on `switch` returning
  nothing, which it confirmed in a throwaway `pwsh` 7 process. The numbers of the entry
  were internally consistent (the 13 new tests are 4 + 4 + 2 + 3, and the 11 that failed
  before the fix match the 11 tests that assert new behaviour). S-21, S-24 and the two
  bullets of 2026-10-14 were annotated, and no "neither host starts `cmd.exe`" or "search
  path" sentence remained.

It could not verify: the gate and test counts, the analyzer and the 88 mutations (it ran
none of them, to keep the gate that was running free of contention); the SDK host's
behaviour (the README's statement only); that VS Code treats the exit-code kind 3 as a
non-blocking warning (it read the mapping and did not run VS Code); a run on a
standard-account token, a Microsoft Store `pwsh`, Ubuntu and macOS; and the costs of about
85 and 7 seconds.

What the final confirmation confirmed sound:

- **V-01 to V-05.** The README row, the changelog, decision 0025, the U-04 and V-01 rows and
  both comments of the script match `X8a` and Node's behaviour, and "went ahead" and "goes
  ahead" are gone. A grep over the whole tree except `.git` and `output` leaves only the
  assertions that refuse the old wording, quotations of it in this entry, unrelated "does not
  block the chat" hits, and a historical finding in `assessment-log.md`. The docstring of
  V-05 is true.
- **V-04.** Evaluated by hand against a copy of the final verifier, without running Pester:
  the committed code passes both rows (evidence of 1,201 and 1,161 characters, against bounds
  of 1,050 and 1,500), and each mutation fails its own row (G13 15,292, G14 15,252, G15 202,
  G16 401, G17 361, G18 5,303 and G19 5,263 characters). A cap of 500, and the first reason
  only, fail too.
- **`eff87a8`.** Of 71 functions only `Test-HookContract` differs in tokens, comments
  excluded; the tokens outside the functions are identical, and exactly one string literal
  differs. In the suite 2 of 128 blocks differ, the relay test and the quoted-path real-run
  test, and both were tightened. `ecd82fc` touches no `.ps1` or `.json` file.
- **The new note.** It is true against README lines 62 and 1174; "so a push would go ahead"
  is the inference that the README supports at line 1184; the bundle of VS Code labels a
  kind 3 result a non-blocking error (read, not run).
- **The Tests section.** All 95 `Find` strings occur exactly once in a copy of the final text
  and the 12 touched mutations parse after mutation; Q01 to Q05 are each caught by an
  assertion of the note test. The 83 that were not run again target `Get-HookWrapper` (8),
  `Get-HookWrapperProblem` (16), `Invoke-HookPayload` (6), `Measure-HookWrapper` (20) and
  `Test-HookContract` (33), and none of that code changed except the one string that only Q01
  to Q05 touch; the change to the suite only adds or tightens assertions.

It could not verify: the gate and test counts, the analyzer and the 12 re-runs (it ran no
Pester and no analyzer); the SDK host's behaviour; what VS Code does with a kind 3 result
beyond its label; that no assertion was weakened outside the two changed blocks (it relied on
the other 126 being token-identical); a standard-account run, a Microsoft Store `pwsh`,
Ubuntu and macOS; and the costs of about 85 and 7 seconds.

### Tests

- Mutation checks: 72 changes of the verifier were applied one at a time for the first
  build, each in a child process over the focused suite, and the file was restored byte
  for byte after each. Two of them survived the first suite (M13 and T21) and got tests,
  and all 72 were caught in the end. For the review fixes the set grew to 88, with 16 new
  changes: G13 to G15 (the relay of a reason and its cap), W01 to W04 (the wording of the
  closure strings), N01 to N05 (the wrapper count), E01 (the environment variable under a
  wrapper), P01 (the Pass evidence) and Q01 and Q02 (the quoted-path note). All 88 were
  caught and none survived, and the file had the same sha256 after the run. One attribute,
  the `[OutputType]` of `Get-HookWrapper`, was changed after that run, for the analyzer, and
  no logic (`01b0e31`). The delta round (V-01 to V-05, `eff87a8`) changed comments and one
  evidence string, and no logic. It added seven
  mutations, Q03 to Q05 (the quoted-path note) and G16 to G19 (the default cap, and a cap
  on each reason, at either site), and rewrote Q01 and Q02 for the new text. A dry run
  showed that all 95 apply to the final text, once each, and parse. The 12 that touch the
  changed lines (G13 to G19 and Q01 to Q05) were run again on the final text: all 12 were
  caught, none survived, and the file had the same sha256 after the run. The other 83 were
  not run again, because the code they change did not change and no assertion was
  weakened.
- The `HookContract` suite: 177 passed and 47 failed before the first build's code, 226
  passed after it; 228 passed and 11 failed before the review fixes, all of them
  assertion failures of the new tests, and 239 passed after them. In the delta round the
  quoted-path note test failed first (238 passed, 1 failed) and the suite passes 239 again.
- The 13 `ContainmentVerifier*` suites: 920 passed, 0 failed, 2 skipped on the first build;
  933 passed, 0 failed, 2 skipped after the fixes (the 13 new tests of the `HookContract`
  suite), in 250 seconds; and 933 passed, 0 failed, 2 skipped again after the delta
  round, in 244 seconds.
- Full `build,test` gate on `d2da113`: 5,328 passed, 0 failed, 147 skipped, 90.84 %
  coverage against a threshold of 65 %, 21 build tasks and no error, 47 minutes. The 16
  warnings are the 15 simulated crashed launches of the Meter tests and one simulated
  backend failure of the trigger eval, as in earlier gates.
- Full `build,test` gate on `f2e46e9` (the fixes of the first review): 5,341 passed, 0
  failed, 147 skipped, 90.84 % coverage, 21 build tasks and no error, 48 minutes; 13 more
  than on `d2da113`, which are the 13 new tests, and the same 16 warnings. The delta round
  came after it, so there is one more gate.
- Full `build,test` gate on `ecd82fc` (after the delta round): 5,341 passed, 0 failed, 147
  skipped, 90.84 % coverage, 21 build tasks and no error, 46 minutes; the same count as on
  `f2e46e9`, because the delta round added no test, and the same 16 warnings. The commits
  after it change only documents and records, and no code or test.
- PSScriptAnalyzer 1.24.0 was clean at every severity, `Information` included, on the
  verifier and the suite after the fixes and again after the delta round; before the
  first fixes it reported one `Information` finding, the declared output type of
  `Get-HookWrapper`.
- Nothing could run on Ubuntu or macOS here. The new blocks are skipped there as blocks.

### Remaining risks

- No host ran the line. The two spawns are rebuilt from the README's table. VS Code's own
  spawn code was read and not run, and the reviewer's Node `spawn` reproduction is the
  closest measurement; how the Copilot SDK host starts the line and answers an exit code
  is the README's statement, which no run confirmed. The forms that VS Code falls back to
  (`cmd.exe /d /s /c "<line>"` when `ComSpec` is unset or names `cmd.exe`, and
  `<ComSpec> -c <line>` for another shell) and the `POWERSHELL_UPDATECHECK=Off` that it
  sets were not run. A host update that changes its form is seen only when the table is
  updated.
- The wrappers were shown closed under a filtered administrator token only. The Pass has
  not been measured on a real standard-account token, which is also the open item of
  R-04 and has the same closing test.
- The measurement is of one host (Windows Server 2025, build 10.0.26100, Windows
  PowerShell 5.1.26100.33648 and PowerShell 7.6.7). A Microsoft Store `pwsh`, whose folder
  is not readable, is expected to be Unavailable and was not tried; Constrained Language
  Mode, AppLocker, other builds of either PowerShell and a build that reads a line
  differently are not covered.
- The `bash`, `linux` and `osx` keys, macOS and Linux were not run, and the POSIX probe is
  unchanged.
- A contained profile that pins a quoted program path now fails. Only an unquoted program
  path without a space works under all three spawns, so PowerShell 7 at its default path
  under `Program Files` cannot be the pinned interpreter on Windows. Whether a profile of
  the owner pins one is not known. Every contained profile has to re-pin the verifier
  digest, and `~/.copilot` has to be refreshed with `./Setup-CopilotSettings.ps1`.
- The wrapper programs are the verifier's choice, by absolute path. VS Code starts Windows
  PowerShell from `%SystemRoot%\System32` and the SDK host starts `pwsh` by name, so both
  depend on an environment that the launcher owns.
- S-33 stayed a recorded Nit: its two spellings fail closed before the wrappers. Closed on
  2026-10-18; see the entry of that date.
- Four `$($_.Exception.Message)` texts of `Test-HookContract` and the two closure details of
  the interpreter (the access check's reason, which is localized .NET text) still reach the
  evidence unrelayed (V-05, W-03). They are older than this change (the same lines exist at
  `origin/main`), so relaying them is a separate change, to be made with S-20. Closed on
  2026-11-13; see the entry of that date.
- The suite of the check takes about 85 seconds longer and a verify run about 7 seconds
  longer, on one host; the reviewer did not verify the first figure.
- The Custom `security-reviewer` agent cannot start in this runtime until the first entry
  of its `model` array resolves or the dispatch falls back, so a review here goes to the
  built-in `security-review` agent.
- The remaining risks of the 2026-10-14 and 2026-10-15 entries that this change does not
  touch stay open: S-19, S-20, the escape set of `WritableRoots`, the run id of
  `-Revalidate`, the second Windows account, and T-03, T-13, T-17 and T-18 of R-04. S-20 was
  closed on 2026-11-13; see the entry of that date. S-19 was closed on 2026-11-13 too; see the
  entry on S-19 of that date. The run id of `-Revalidate` was bound on 2026-11-14, for a profile
  that names its run; see the entry on the run id of that date.

## 2026-10-15: the token of the run identity, R-04 (follow-up of prompt P5)

The Custom `security-reviewer` agent reviewed the change that addresses R-04, the
first follow-up of the P5 review: the `IdentityPrivilege` check of
`Test-RunContainment.ps1`. It read the three commits of the first build (`8330c34`,
`9fd3a5e`, `1f741a2`), read-only, in a fresh context and with no network call, and
said **Approve with changes**: no Blocker, no Major, ten Minors (T-01 to T-10) and two
Nits (T-11 and T-12). Every finding but T-03 and one part of T-01 was fixed in the
same change, test first, with a mutation check for each control a test can reach. The
same agent then checked the fixes (`840a438`) and said **Approve with changes** again:
no Blocker or Major, two Minors and four Nits (T-13 to T-18). The change was pushed as pull
request #42 and squash-merged on 2026-10-16 (`3481536`).

### Scope

- Can `IdentityPrivilege`, or the gates that depend on it, report a Pass for a token
  that is not a standard account's?
- Would it refuse, or fail to measure, a valid standard account (Windows 10, 11 and
  Server; a local, a domain or a Microsoft account)?
- Is the native reading correct: the layout of the token structures on x64, x86 and
  ARM64, the growth of the buffers, the SID pointers, the handles and the generated
  type?
- Do the tests fail when a control is removed, and do they behave on Ubuntu and
  macOS, where the Windows-only suites skip?
- Do the hooks README, the controller text, decision 0025, the changelog and this
  file claim more than the code and the measurements show?

### Verdict

First build: **Approve with changes**: no Blocker, no Major, 10 Minors, 2 Nits. The
reviewer found no way for the check, or the gates that depend on it, to report a Pass
for a token that is not a standard account's, in the model that was stated: a
trusted launcher, and facts that come from the native reader. The weaknesses it
found were hardening gaps, test gaps and statements that went beyond the evidence.

Delta check of the fixes, on `840a438`: **Approve with changes**: no Blocker, no Major,
2 Minors and 4 Nits. The reviewer found no new false Pass: every path the fixes changed
(the SID shape, the empty-group rule, the thread rule and the SID-position rule)
rejects more than before, and none adds a way to accept. It checked the new SID shape
against 22 realistic SIDs (`S-1-5-5-0-1234567`, `S-1-15-2-…`, `S-1-18-1`,
`S-1-16-8192` and others) and all were accepted. It confirmed that every original
finding is fixed, or open by a choice that the records state. The code and tests of
the delta were not changed after that check, so that the code the reviewer approved
is the code the final gate ran on; the findings that need code are follow-ups.

### Findings

| ID | Severity | Where | Finding | Resolution |
|---|---|---|---|---|
| T-01 | Minor | `Get-TokenFactProblem` | The shape of a group SID took any Unicode digit and a leading zero, so text that is not the canonical SID would not equal the Administrators SID; an empty group list was accepted; the integrity level was not cross-checked with the label in the group list | Fixed: ASCII digits, no leading zero, and at least one group, with rows and mutations. The cross-check is not done (see Remaining risks) |
| T-02 | Minor | `ReadProcess`, `IdentityBinding` | The check judges the token of the process, while the binding and the probes that ask for access answer for the thread (`WindowsIdentity.GetCurrent()`), and nothing tied the two | Fixed: `ThreadImpersonates` (`OpenThreadToken`, `ERROR_NO_TOKEN`) makes a thread that impersonates `Unavailable`, with the reason; tested with `WindowsIdentity.RunImpersonated`. A launcher that gives the verifier a more restricted token of the same account than it gives the run stays unseen, and the README says the launcher is trusted |
| T-03 | Minor | `Test-IdentityPrivilege` | A group the token holds disabled (neither enabled nor deny-only), other than Administrators, is not judged, and a process can enable it | Not fixed, recorded: refusing it could refuse a valid account, and no host here has a standard token to show which groups a valid one holds disabled. The README and the controller text say it is not shown |
| T-04 | Minor | this file | The R-04 row and the Remaining-risks bullet pointed to an entry that did not exist | Fixed: this entry |
| T-05 | Minor | controller text, a code comment, `activeContext.md`, decision 0025 | Four gates were named where there are five, and `activeContext.md` still listed R-04 as not done | Fixed in each |
| T-06 | Minor | README, decision 0025, changelog, controller text | Claims beyond the evidence: "none can be made from an administrator's", "closed", "Fixed", and the five privileges stated without a build | Fixed: scoped to no test host here and to a filtered token on Windows Server 2025, build 10.0.26100; "addressed" for the refusal and open for the Pass; the closing test is named (a throwaway local account read through `LogonUser`) |
| T-07 | Minor | README | "Nothing runs as an identity that holds a privilege no probe can show" was broader than the code, which gates the hook command, git and the appender and runs every other check whatever the token holds | Fixed: "no program the verifier starts" |
| T-08 | Minor | `Privilege.Tests.ps1` | A test with its assertions behind `if` blocks asserted nothing on every host here (elevation type Default) | Fixed: it skips explicitly on that type and asserts otherwise |
| T-09 | Minor | `Privilege.Tests.ps1` | The exact set of five was never asserted, so a name added to it survived, and the cap on a relayed privilege name was untested | Fixed: the set is asserted, 31 other privilege names of `winnt.h` are refused row by row, and the cap is tested; five mutations that add a name were caught |
| T-10 | Minor | `Initialize-NativeToken` | The bounds of the group and privilege arrays, the growth of the buffer and the position of a SID were untested, and nothing required a SID to lie after its structure | Fixed: `ParseGroups`, `ParsePrivileges` and `ParseIntegrityRid` are public and tested with crafted buffers; a SID has to lie after its structure; `Read(handle, firstSize)` makes the growth path run, which no list of a token here needs in 512 bytes and a domain account's groups do, and a counter shows it ran; a count, a length and a position are each guarded and tested |
| T-11 | Nit | `Get-CallerTokenFact` | Every failure ended as `Unavailable` with no reason, so a false `Unavailable` could not be traced | Fixed: the reason is in the evidence, relayed as printable ASCII and cut; the verdict is unchanged |
| T-12 | Nit | `Privilege.Tests.ps1` | The first block left `$script:OnWindows` true, and a helper called `WindowsIdentity.GetCurrent()` without asking the platform; Ubuntu and macOS were safe only because Pester does not run the `BeforeAll` of a block whose tests are all skipped | Fixed: the value is saved and restored, and the helper asks the platform |
| T-13 | Minor | `ThreadImpersonates` | Only `ERROR_NO_TOKEN` returns false and every other error throws, but nothing reaches that throw (the reviewer's probe showed that anonymous impersonation does not), so a later edit that turned it into `return false` would reopen the gap that T-02 closed | Not fixed, recorded: make the decision a pure method that takes the result and the error and test 1008, 5 and 1347 |
| T-14 | Minor | records | The records were committed after the code, so the tree at `840a438` still said R-04 was not done, decision 0025 still said "closed by measurement", and this entry said "a mutation check for each control the fixes added" while listing controls that were not mutated | Fixed: the records are committed together, and the wording is "each control a test can reach" |
| T-15 | Nit | README | "No program the verifier starts runs as an identity that holds a privilege no probe can show" is imprecise: a Pass allows four of the five privileges while they are disabled, which a process can enable | Fixed: "outside the five" |
| T-16 | Nit | changelog | "The elevated token of the Windows runner of CI included" states a fact that was not measured | Fixed: it names the host that was measured, and says that the runner is expected to be refused and was not measured. Measured afterwards: the Windows leg of CI on pull request #42 (run 38862088537, Windows Server 2025, an administrator with UAC off) ran the end-to-end refusal and the tests on real filtered tokens, and they passed, so the changelog now says so |
| T-17 | Nit | `Privilege.Tests.ps1` | Two new tests (a privilege that has no name, an integrity SID of more than one sub-authority) accept any exception | Not fixed, recorded: pin `Win32Exception` with error 1313 and `FormatException` |
| T-18 | Nit | `Get-CallerTokenFact` | `Win32Exception.Message` is localized and the relay turns non-ASCII characters into `?` | Not fixed, recorded: add the native error code to the reason |

What the reviewer confirmed sound: the native layout (`TOKEN_GROUPS` at the size of a
pointer, `TOKEN_PRIVILEGES` at 4 with entries of 12, `TOKEN_MANDATORY_LABEL`), the
information classes, the exact four-byte read of `TokenElevation`, the bounded growth
loop, the `SidText` bounds, the freeing of every buffer and handle, the ordinal
comparisons, the fail direction (every read or shape failure is `Unavailable`, and a
Pass needs no reason), the wiring in both flows and in the not-run report, and the
size of the controller text. It did not verify the Pass on a real standard token, the
privilege set on other Windows builds, x86 and ARM64, or the Ubuntu and macOS legs.

### Tests

- Mutation checks: 109 changes of the verifier were applied one at a time, each in a child
  process over the five focused suites, and the file was restored byte for byte after each:
  the 67 of the first build and 42 for the fixes. All 109 were caught and none survived. Not
  mutated, because no test can reach them: the 1 MiB cap on a grown buffer, the error codes
  inside `ReadBuffer` and `PrivilegeNameOf`, `openAsSelf` of `OpenThreadToken`, and the
  branch of `ThreadImpersonates` that throws on an unexpected error (T-13).
- The 13 `ContainmentVerifier*` suites after the fixes: 868 passed, 0 failed, 2 skipped (791
  passed before them). One skip is the elevation-type test, which skips on a token of the
  default type; the other is a POSIX-only case that was skipped before.
- Full `build,test` gate on `840a438`: 5,276 passed, 0 failed, 147 skipped, 90.84 %
  coverage against a threshold of 65 %, 21 build tasks and no error, 45 minutes. The 16
  warnings are the 15 simulated crashed launches of the Meter tests and one simulated
  backend failure of the trigger eval, as in earlier gates. The records, the README
  sentence of T-15 and the changelog sentence of T-16 changed after it, and no code or test
  did. The first gate, on `1f741a2` before the fixes, passed too (5,199 passed, 0 failed,
  146 skipped, 90.84 %) and is superseded.
- Nothing could run on Ubuntu or macOS here. The new blocks that read tokens are
  skipped there as blocks.

### Remaining risks

- The Pass has not been measured on a real standard-account token: no test host here
  runs as one, and a filtered administrator token is refused for its Administrators
  group. The closing test creates a throwaway local account, logs it on with
  `LogonUser`, reads its token by handle with the same reader and expects a Pass. A
  hosted CI runner is an administrator and could run it; on a development host it
  creates an account, which is the owner's decision.
- The five privileges were measured on a filtered token of one build (Windows Server
  2025, 10.0.26100). A standard account's own set is expected to be some or all of
  them, and any subset passes. Another build or a client edition may differ.
- A group the token holds disabled, other than Administrators, is not judged (T-03),
  and the integrity level is not cross-checked with the label in the group list. Both
  need a real standard token to show that no valid account is refused. The reviewer's
  suggestions, neither of which can refuse a valid account: require that an
  `S-1-16-n` in the group list equals the integrity level when one is there, and list
  the groups a process could re-enable in the Pass evidence without refusing them,
  which would produce the measurement that is missing the first time a real standard
  token is read.
- Three small follow-ups of the delta check, none a false Pass: test the branch of
  `ThreadImpersonates` that throws on an unexpected error (T-13), pin the exception of
  two tests (T-17), and add the native error code to the reason that a token was not
  read, because the message is localized (T-18).
- The launcher is trusted to give the run the token it gave the verifier. A launcher
  that starts the verifier under a more restricted token of the same account passes
  here and gives the agent more.
- The buffer growth is tested by forcing a small first buffer, and not on a token of a
  domain account whose groups need it. x86 and ARM64 were reasoned about against
  `winnt.h` and not run.

## 2026-10-14: containment verifier and ledger appender, after the fix round (prompt P5)

The built-in `security-review` agent reviewed the containment verifier
(`Test-RunContainment.ps1`) and the ledger appender (`Invoke-LedgerAppender.ps1`)
repeatedly, read-only and in a fresh context, with no network call. The first
review (2026-10-12, change set `e42985b`) said **Block** with 13 findings, C-01 to
C-13. The fix round rebuilt the branch on `main` after the Remote grant change
(`#38`), fixed each finding test first with a mutation check per control, and the
same agent then reviewed it again: pass 1 (the verifier at `7804e31`) said
**Approve with changes** with 11 findings, R-01 to R-11; pass 2 (the whole
branch at `ad93f66`, including the appender, which pass 1 had not read) said
**Approve with changes** with 11 findings, S-01 to S-11; and pass 3 checked each
round of fixes in turn, in six parts: A the verifier fixes of pass 2 (S-12 to
S-16), B the appender fixes, the part A fixes and the interpreter allow-list
(S-17 to S-20), and C to F bounded delta checks of the four fixes that followed
(S-21 to S-24, S-25 to S-29, S-30 to S-32, and S-33). Every delta check but the last
found something in what the previous round had added, and the two Majors among them
(S-21 and S-25) were in the same function, `Get-HookInterpreter`. The last one, part
F, said **Approve**. All are recorded below. The Custom `security-reviewer` agent was
not tried, because its first model was unavailable in this runtime in earlier
reviews. Nothing was pushed.

### Scope

- Can a run read as contained when it is not; can ledger evidence be suppressed,
  spoofed, or altered without `-Validate` failing; can the verifier itself be made
  to run something other than what it measured; and does the documentation claim
  more than the code measures?
- Pass 2 added what the fixes introduced: the fresh-process requirement, the
  absolute interpreter path, the plugin-root tie, the whole-document scan, the
  report-path rules, the per-process native type, and the appender in full.
- Pass 3 added what the pass 2 fixes introduced: the launch check and its call
  stack, the closed entry keys, the ordinal grammar, the acknowledgement rebuild,
  the relayed-text policy, the hook-line rules, and the module origin of the
  firewall cmdlets. Parts C to F added what the hook-line fixes introduced: the
  shape that the line after the program has to have, the program word and the drive
  rule, and what the Pass evidence says about the hosts.

### Verdict

First review: **Block** (5 Blockers, 7 Majors, 1 Minor). Pass 1: **Approve with
changes** (no Blocker, 3 Majors, 7 Minors, 1 Nit). Pass 2: **Approve with
changes** (no Blocker or Major, 7 Minors, 4 Nits). Pass 3 part A: **Approve with
changes** (no Blocker or Major, 4 Minors, 1 Nit). Pass 3 part B: **Approve with
changes** (no Blocker or Major, 1 Minor, 3 Nits). Pass 3 part C: **Approve with
changes** (no Blocker, 1 Major, 3 Minors). Pass 3 part D: **Approve with changes**
(no Blocker, 1 Major, 3 Minors, 1 Nit). Pass 3 part E: **Approve with changes** (no
Blocker or Major, 2 Minors, 1 Nit). Pass 3 part F, a bounded delta check of the part
E fixes: **Approve** (no must-fix finding, 1 Nit). Each set of findings was fixed
before the next pass; the Nit of part F is a recorded follow-up and was not fixed,
so that the code the last reviewer approved is the code that was gated.

### Findings

First review, resolved in the fix round:

| ID | Severity | Area | Finding | Resolution |
|---|---|---|---|---|
| C-01 | Blocker | Verifier | The role identities were required but never read. | Fixed. `IdentityBinding` resolves each role identity and fails unless it is the verifying identity and the two roles differ; tested with the real token (Controller Pass, Worker Fail). |
| C-02 | Blocker | Verifier | "Immutable" meant only that the leaf could not be opened for write. | Fixed. Each right that replaces or loosens an object is asked of the kernel for the object, its parent and every ancestor, with reparse points and writable-root overlap; a sharing violation reads as granted, so the check works beside a live appender. |
| C-03 | Blocker | Verifier | The hook probe ran a command from a configuration whose digest or immutability had failed, and never compared the resolved script. | Fixed. It runs only after the verifier, the digests, the immutability and the identity binding pass, on bytes it hashed itself, with `PLUGIN_ROOT` set to the pinned root and a decoy tree; see R-01 and R-06 for what pass 1 then required. |
| C-04 | Blocker | Appender | The pipe could be taken in a gap, and the client authenticated nobody. | Fixed. A pending instance is always kept and a creation failure is fatal; the creator owns the pipe and the network identity is denied; the client checks the owner and access list before it sends and checks the acknowledgement against the ledger. The owner comparison replaces a process-id lookup. |
| C-05 | Blocker | Appender | Validation did not close the stored line, so text could be planted in it. | Fixed. A stored line must be byte-for-byte the canonical form of what it parses to, with exactly seven fields. |
| C-06 | Major | Appender | A restart adopted whatever the sink held. | Fixed. The start is refused unless the head names the last record or the one before it. |
| C-07 | Major | Appender | A head failure left a persisted, unacknowledged record and a stale sequence. | Fixed. Persist, advance, publish; a head failure stops the service. |
| C-08 | Major | Appender | The canonical form was not a function of the data. | Fixed. Ordinal keys, raw tokens, integers within ±(2^53−1); the vectors were cross-checked with an independent implementation. |
| C-09 | Major | Verifier | The egress check passed a disabled firewall profile and read a timeout as closed. | Fixed. Profiles must be enabled and default to Block, allow rules are read (an alias principal fails closed), and a timeout is unmeasured. The premise that a filtering-platform block returns an access error is unverified and fails closed to unmeasured. |
| C-10 | Major | Verifier | The caller's environment decided some results. | Fixed. git is resolved to an absolute path that must be closed to the run, the steering variables are reported and dropped, a sentinel and an exit code are required, and values are never printed. |
| C-11 | Major | Verifier | Live artifacts were not in the immutability set, and the writable-roots check claimed more than it measured. | Fixed. They are measured; the check makes two proofs and no longer claims the set is exact. The P2 grant is reconciled by `GrantRecorderUnregistered` (an assumption on a delegated choice; see R-06). |
| C-12 | Major | Both | The verifier could not revalidate the chain, and `-Validate` took any path. | Fixed. `-Validate` is bound to the profile and can require a seal; `-Revalidate` runs it, reads the sink before and after, and checks the `FinalReport` record. |
| C-13 | Minor | Both | A set of smaller defects. | Fixed, apart from a signed chain. |

Pass 1 (verifier at `7804e31`):

| ID | Severity | Area | Finding | Resolution |
|---|---|---|---|---|
| R-01 | Major | Verifier | The hook probe started a shell in the caller's working directory and PATH, and the shipped command begins with a bare `powershell`, so a program planted in the repository ran before any verdict. | Fixed. The probe runs in a folder of its own with the shell told not to search the working directory; the command must start with the absolute path of an interpreter the run cannot replace. |
| R-02 | Major | Verifier | `IdentityBinding` did not gate the hook command or the appender, which run as the caller. | Fixed. It gates both. |
| R-03 | Major | Verifier | Nothing required a fresh process, so a function or type defined earlier in a session outranked the verifier's own. | Fixed. It runs only as the entry script of a `-NoProfile -File` process; the native probe is a per-process type; the temp folder of the operating system joins the escape set. |
| R-04 | Minor | Verifier | Token privileges and elevation are never read. | **Addressed on 2026-10-15** (see the entry of that date): `IdentityPrivilege` reads the token of the process and refuses one that is not a standard account's. The refusal is measured on real tokens; the Pass has not been measured on a real standard token. |
| R-05 | Minor | Verifier | The report path was compared as text. | Fixed. Stream, device and extended-length spellings and, on Windows, a link above the report are refused. |
| R-06 | Minor | Verifier | The grant check passed a shape it could not read, and its name overstated it. | Fixed. Renamed `GrantRecorderUnregistered`; an unread shape is unmeasured; the pinned `hooks.json` must be the plugin's own file. Hook files a host finds elsewhere are not read. |
| R-07 | Minor | Verifier | The hook contract read one string of one entry. | Partly. Type, matcher, timeout and equal text under every key are required and each probe is timed; keys are not probed one by one. |
| R-08 | Minor | Verifier | A directory entry is one object, and other registered hooks are unpinned. | Partly. Only the guard may be registered and the directory-leaf right has a test; a directory entry is still one object, documented. |
| R-09 | Minor | Tests | Cases that could not fail, and one that failed off Windows. | Fixed. Eight network cases repaired (half the finding was redaction of credential-shaped fixtures, which are now distinctive and not credential-shaped), a ledger contract suite built on the real appender, the link branch and the digest case tested. |
| R-10 | Minor | Docs | Claims beyond measurement; a loose `schemaVersion`. | Fixed. |
| R-11 | Nit | Both | Probe files on POSIX, an uncaught `Add-Type` failure, uncapped relayed text, no run id. | Partly. The failure is unmeasured, relayed text is cut and cleaned, the probe files are documented; a run id is not bound. The run id was bound on 2026-11-14; see the entry on the run id of that date. |

Pass 2 (the whole branch at `ad93f66`, the appender included). It found no Blocker
and no Major, and set the pass 1 findings as follows: R-01, R-02, R-06 and R-09
resolved; R-03, R-05, R-07, R-08, R-10 and R-11 partly, each open part being a
finding below or documented; R-04 not resolved, acceptable as a documented
residual for this change set and not as the end state.

| ID | Severity | Area | Finding | Resolution |
|---|---|---|---|---|
| S-01 | Minor | Verifier | The fresh-process check accepts a `-Command` launch that carries a trailing `-File <script>`, which runs planted code before the script. | Fixed (`3676fce`): the check also reads the call stack (one frame under `-File`, two under `-Command`). Part A found the check skippable and the options before `-File` unread: S-12 and S-13. |
| S-02 | Minor | Verifier | The fresh process still inherits `PSModulePath` and `DOTNET_STARTUP_HOOKS`, which outrank what it measures with. | Split. The module-path half is measured: `EgressPolicy` is unmeasured unless the three firewall cmdlets come from a module under the system folder (`b2cf267`). The start-up hook and the rest of the launcher's environment are documented as the launcher's job, because a hook can unset its own variable; the reviewer accepted that for the start-up hook only. |
| S-03 | Minor | Verifier | `HookContract` reads some keys of the guard's entry and ignores the rest. | Fixed (`3676fce`): the entry is a closed set of keys, and `timeoutSec`, `env`, `cwd`, a capitalized `Timeout` and a key whose name only looks like a known one all fail. |
| S-04 | Minor | Both | The "closed" grammar is closed only up to culture equivalence (`-ceq` treats a zero-width character as nothing), and `utc` is a shape, not an instant. | Fixed in the verifier (`3676fce`) and the appender (`73621c5`): ordinal comparisons, `\A...\z` patterns, `utc` parsed as an instant. Part A found one more culture-ordered site in the verifier, `Get-PathChain`, fixed in `b2cf267`. |
| S-05 | Minor | Appender | The acknowledgement check accepts a replay: a server that answers a new record with the sequence and digest of a stored one. | Fixed (`d384c89`): the client rebuilds the digest of the record it sent and requires it in both the acknowledgement and the ledger. |
| S-06 | Minor | Verifier | `Format-RelayedText` leaves supplementary-plane format characters, the Unicode tag block among them. | Fixed for the tag block (`3676fce`). Part A showed that the category deny-list still passed other invisible characters (S-15), so it is now an allow-list (`b2cf267`). |
| S-07 | Minor | Verifier | The git child process is not gated by `IdentityBinding`. | Fixed (`3676fce`): git runs only after the checks that gate the hook command. |
| S-08 | Nit | Appender | The client prints the server's refusal text raw. | Fixed (`feb91a3`, `4c287be`): one line of printable ASCII, every other character one `?`, cut at 200 characters. |
| S-09 | Nit | Appender | A process of the service's own account can join the pipe name. | Not fixed, accepted. With S-05 fixed it can make an append fail but cannot make an unstored record read as stored. The reviewer's fix, `FirstPipeInstance` and a pending instance at start, is a follow-up. |
| S-10 | Nit | Verifier | Report-path aliases are still accepted: a hard link to a protected file, and a UNC spelling of the same machine. | Not fixed, accepted. The report is written with the rights of the run identity, which holds no write right on any control when `ControlImmutability` passes. |
| S-11 | Nit | Verifier | `Get-HookInterpreter` judges the first word only. | Fixed in three steps: the rest of the line (`3676fce`); `%`, `!`, parentheses and the semicolon tail (S-14, `b2cf267`); and a program not named `powershell` or `pwsh` is refused (`982fe1d`). |

Pass 3, part A (the verifier fixes at `6c5fc7f`). It confirmed that the fixes close
the mechanisms reported, found S-12 to S-16, and judged the documentation-only
resolution of S-02 acceptable for the start-up hook and not for the module path.

| ID | Severity | Area | Finding | Resolution |
|---|---|---|---|---|
| S-12 | Minor | Verifier | The process check is a call by name, and command lookup tries an alias before a function, so `Set-Alias Get-FreshProcessProblem Out-Null` made it do nothing. | Fixed (`b2cf267`): the check and the option reader contain no command and are reached through the function table. A structural test counts the commands in them, and an end-to-end launch with the alias prelude is refused. |
| S-13 | Minor | Verifier | The options before `-File` were scanned for `-NoProfile`, not allow-listed: `-ConfigurationFile` ran a planted `Get-Date` at a call stack of one, and `-WorkingDirectory -nop` swallowed what looked like `-NoProfile`. | Fixed (`b2cf267`): only options that cannot change what runs first are allowed, an option that takes a value takes the next argument, and the hook-line check uses the same reader. |
| S-14 | Minor | Verifier | A `%` in the hook command line expands in `cmd` before `&` is read, and an unquoted `;` or parenthesis lets a host's PowerShell run a second program. | Fixed (`b2cf267`): `%` and `!` are refused anywhere, parentheses outside quotes are refused, and after an unquoted `;` only the one statement the shipped command ends with is accepted. A test derives the commands from the shipped `hooks.json`. |
| S-15 | Minor | Verifier | `Format-RelayedText` is a deny-list: variation selectors, Hangul fillers, the Braille blank and the wider spaces pass. | Fixed (`b2cf267`): printable ASCII only, every other rune one `?`. The appender's refusal text follows the same policy. |
| S-16 | Nit | Docs | The README said `Start-Process -UseNewEnvironment` gives a clean launcher. | Fixed (`7f6504b`): it clears what the child inherits, not the module path or the start-up hook; the advice is a launcher that builds its own environment. |

Found while fixing S-11, not by the reviewer; its severity is my own judgement and
part B is asked to confirm it:

| ID | Severity | Area | Finding | Resolution |
|---|---|---|---|---|
| (none) | Minor | Verifier | The probe shell ran `cmd.exe /c`, and `cmd.exe` runs the `AutoRun` commands of the registry of the identity that starts it unless it is given `/d`, so a hostile identity could answer for the guard from there. | Fixed (`982fe1d`): the probe runs `cmd.exe /d /c`, and a test reads `%CMDCMDLINE%` from inside the probe. The same commit makes the hook interpreter an allow-list (`powershell` or `pwsh`), since what any other program loads cannot be read. |

Pass 3, part B (the appender fixes, the part A fixes and the interpreter
allow-list, at `7f6504b`). No Blocker and no Major. S-04 (appender), S-08, S-12,
S-13, S-15, S-16 and the module-path half of S-02 were confirmed resolved, S-05
resolved with one residual (S-19), S-14 and S-11 partly (the rest is S-17), and S-09,
S-10 and the two availability limits accepted. It confirmed that the interpreter
allow-list refuses everything the shipped hook does not need and refuses
nothing it does need, that no other launch in either script runs the identity's
start-up configuration, and that the `AutoRun` claim is right as far as the text
of `cmd /?` goes (no value exists on the host and nothing was written to the
registry, so it was not demonstrated). `Test-UtcInstant` never accepts a
non-instant; it refuses a valid leap second (`23:59:60Z`), year 0000 and a
fraction of ten digits, all fail closed.

| ID | Severity | Area | Finding | Resolution |
|---|---|---|---|---|
| S-17 | Minor | Verifier | The hook-line scan reads `cmd.exe` rules only: `-Command "$(calc.exe)"`, `"$env:PLUGIN_ROOT"`, a backtick inside quotes and `-Command x '"' ; calc.exe '"'` were accepted, and a PowerShell wrapper or a POSIX shell reads them differently from a scan that toggles on the ASCII double quote. | Fixed (`25cedd4`): no `$` or backtick anywhere, no `'` outside double quotes, and, beyond what was asked, nothing outside printable ASCII (checked on the text as given; PowerShell reads curly quotes as quotes) and no dot segment in the program path. The 15 shipped command strings carry none of them. Thirteen new rows failed first; five mutations, one per rule, broke exactly those rows. |
| S-18 | Nit | Docs | The README launcher recipe (`Environment.Clear()` and a `PSModulePath` of system folders) does not do what it says: pwsh adds the account's own module folder first. | Fixed in the README, after reproducing it. The module path is closed only where the verifier measures it (the three firewall cmdlets); adding the folders pwsh searches to the escape set of `WritableRoots` is a follow-up. The follow-up was done on 2026-11-14 for the folders `WritableRoots` measures; Windows PowerShell 5.1's hook line stays open (R12-02, brief 18). See the entry of that date. |
| S-19 | Nit | Docs | "Cannot make a record that was not stored read as stored" has an exception: a server that replays the earlier acknowledgement of a record identical to one already stored. | Fixed in the README: the exception and what the client cannot prove (how many times the record was stored). The reviewer's hardening, `sequence == head before send + 1`, needs the client to read the chain before it sends, and is not done. Closed on 2026-11-13, as `sequence > n` with n counted from the sink before the send; see the entry on S-19 of that date. |
| S-20 | Nit | Both | Two service-side `[Console]::Error.WriteLine` lines print raw exception text; the S-04 and S-05 appender tests are Windows-only although three of the functions are platform-neutral; `..` in the program word is normalized textually. | The `..` item is fixed with S-17. The first is not changed: no client text reaches those lines (`Test-RecordSchema` returns canonicalization errors to the client inside a `try`, and `Add-Record` runs only after it passed), so there is nothing to provoke in a test; part C accepted that as a Nit and still recommends routing both lines through `Format-RefusalText`. The second is a follow-up, because Ubuntu and macOS cannot be run here. Closed on 2026-11-13; see the entry of that date. |

Pass 3, part C (a bounded delta check of `25cedd4` and `c7e886e`). It confirmed S-18 and S-19 resolved and S-17 resolved for the characters it names, and showed that the class was not closed: **one Major, three Minors**. It also confirmed that the ASCII rule refuses nothing a shipped-shape command carries (the commands resolve `PLUGIN_ROOT` at run time), that the order of the checks is safe, and that the rule makes the culture-sensitive `IndexOf('"', 1)` and `StartsWith('\\')` safe, because they now see only ASCII. It accepted as follow-ups S-20 (both bullets), the escape-set addition and the S-19 hardening, and R-04 stays accepted.

| ID | Severity | Area | Finding | Resolution |
|---|---|---|---|---|
| S-21 | Major | Verifier | The hook-line scan was still a list of characters to refuse. A `#` before the closing statement is a comment to PowerShell and not to `cmd.exe`, so under both documented hosts the statement that turns the guard's exit code into the hook's never runs, a push exits 1, which VS Code treats as a warning and the Copilot SDK host as a denial (corrected on 2026-10-16: the entry said it "does not block"), and `HookContract` still passes with 0, 2, 2 (reproduced on the shipped `windows` command). An unterminated quote, a doubled quote inside a quoted part and, under a POSIX shell, a quote after a backslash passed too and were read three ways. The claim that the verifier refuses command text two shells could read differently was false. | Fixed (`44396e8`): the scan accepts one shape instead of refusing a list. After the program only bare words of letters, digits and `. _ : \ / -` and double-quoted words with no double quote inside (and no backslash before the closing one) may follow, then at most the one pinned exit statement after an unquoted `;`. Eighteen tests failed first, among them an end-to-end row that inserts the hash into the shipped command; four mutations, one per addition, broke exactly those 18. The shipped commands and the derived-from-shipped tests still pass. The reviewer's larger fix, running the pinned line under the PowerShell wrappers the README's host table lists (after checking the wrapper binary is closed to the run identity), so that the whole class fails by measurement, was a follow-up and was built on 2026-10-16 (see the entry of that date). |
| S-22 | Minor | Verifier | An unquoted program word may hold `;`, `,` or `=`, and a closing quote may be glued to the next word: `cmd.exe` started a decoy `a.cmd` beside `a;b\powershell.exe` with the rest as its arguments, so the measured path and the started program differ. | Fixed (`44396e8`): an unquoted program word holds only the safe characters, and the shape refuses text glued to a closing quote. The decoy has to sit in a directory above the interpreter, which `Test-PathProtection` requires closed to the run, so only a deployer or a package could plant it. |
| S-23 | Minor | Docs | Sentences that claimed more than the code measures: "refuses the characters on which the two shells could disagree"; the probe's `cmd.exe` "which a host may not" (both documented hosts wrap the line in PowerShell, and `cmd.exe` is the exception); the 5.1 measurement holds only when the whole line is given as one argument; the `HookContract` Pass evidence named no shell. | Fixed: the README, the controller text, the changelog entry and the Pass evidence now say that the probe ran through `cmd.exe /d /c`, that a PowerShell host reads the line by other rules, and which model the 5.1 measurement used. |
| S-24 | Minor | Verifier | A quoted program path passes `HookContract` and the `cmd.exe` probe and fails open under both documented hosts: PowerShell needs a leading `&` before a quoted path, the check refuses the `&`, and the wrappers exit 1, which VS Code treats as a warning and the Copilot SDK host as a denial of every call (corrected on 2026-10-16: the entry said it "does not block"). The README called it "not settled" while the check returned Pass. | Partly (`44396e8`): the Pass evidence now says so when the program path is quoted, and the README tells a deployment to pin an unquoted path until a form that works under both is settled. The check still passed a quoted path then; returning Unavailable or Fail for it was the reviewer's other option, and a follow-up. Closed on 2026-10-16: a quoted path now fails by measurement under both wrappers (see the entry of that date). |

Pass 3, part D (a bounded delta check of `44396e8` and `6a6af58`). It confirmed S-21 and S-22 resolved for everything named in part C, S-23 partly (S-29) and S-24 accepted as a follow-up, and found **one more Major**: the shape still let a word that starts with a dash through. The reviewer generated 12,000 lines, ran them through the verbatim function, and parsed every accepted line with the real parsers of Windows PowerShell 5.1 and 7.6.6: of 7,814 accepted lines, 126 deviated, all of them dash words. It also confirmed that the quote loop and the shape agree on where the head of the line ends, that the shape refuses nothing the shipped `PreToolUse` command needs, and that the program-word rule is enough for `;`, `,`, `=` and a glued quote.

| ID | Severity | Area | Finding | Resolution |
|---|---|---|---|---|
| S-25 | Major | Verifier | A bare word may start with `-`. PowerShell reads `-name:` as a parameter that binds to the next word or, as the last word, fails to parse, and splits `-Z.7` in two, where `cmd.exe` passes each through whole. Reproduced on the shipped body: ` -x:` before the closing statement made both PowerShell wrappers exit 1 for a push, which VS Code treats as a warning and the Copilot SDK host as a denial (corrected on 2026-10-16: the entry said it "does not block"), while the `cmd.exe` probe still measured 0, 2, 2. | Fixed (`032d6c4`): a word that starts with a dash is an option name of letters only (the reviewer's regex, character for character; its generated set gave 0 deviations). Six rows and an end-to-end row failed first. The reviewer's method is now a seeded test: every line the shape accepts out of 4,000 generated ones has to parse, with the parser of the host, as one command whose words are the words the shape saw. Under the part C shape it finds 533 deviating lines, such as `-d.f0` and `-bf0YZc1.`; under the new one, none. |
| S-26 | Minor | Verifier | A network path is two separators in any mix. The check refused only `\\` and `//`, so `\/server\share\powershell.exe` and `/\server\share\powershell.exe` reached `Test-PathProtection`, which would read the access list over the network as the verifier's own identity. | Fixed (`032d6c4`): two separators in any mix, quoted or not. |
| S-27 | Minor | Verifier | Off Windows the shape and the program word allow backslashes that a POSIX shell reads as escapes: `/opt/x\y/pwsh` runs `/opt/xy/pwsh`, a sibling directory that was never measured. | Fixed (`032d6c4`): off Windows a backslash anywhere in the line is refused, tested with the platform switched so that the rule runs on every host. Verified at the level of `sh` word splitting (Git's `sh.exe`); the POSIX probe itself was not run on a POSIX host. |
| S-28 | Nit | Verifier | A line with an empty word (`... -Command exit ""`) made the option reader throw, so the verifier ended with exit code 1 and nothing verified instead of refusing the line with its reason. Fail-closed, not a hole. | Fixed (`032d6c4`): `[AllowEmptyString()]`. |
| S-29 | Minor | Docs | "Read alike" was too strong until S-25 and S-27 were fixed; the README contradicted itself about the POSIX backslash; the controller was told that the quoted-path caveat exists but not what to do with it. | Fixed (`8a95351`): the README cells, the changelog entry and the help comment describe the shape, and the controller records a quoted program path in the report as a limitation of the hook. |

The reviewer accepted as follow-ups the wrapper measurement (run the pinned line under the PowerShell hosts and require 0, 2, 2 there too, which is the real fix for the whole class: S-25 would have failed by measurement), S-24 as Unavailable or Fail (with the controller sentence, now done), S-20, the escape-set addition, the S-19 hardening and R-04.

Pass 3, part E (a bounded delta check of `032d6c4` and `8a95351`). It confirmed S-25, S-27 and S-28 resolved and S-26 and S-29 partly, and found **no Blocker or Major, two Minors and a Nit**. It generated two fresh sets of 12,000 lines (seeds 20261014 and 777, with tabs inside quotes, `-nop -noni -c`, `-File` forms, tails and hostile characters inserted at random) and parsed every accepted line with Windows PowerShell 5.1 and PowerShell 7.6.6: 0 deviations in 15,296 accepted lines under each parser. It gave Git's `sh.exe` 220 accepted heads without a backslash (0 differences) and compared the arguments that `cmd.exe /d /c`, the 5.1 wrapper and the 7 wrapper hand to a script for 140 `-File` lines: they matched except for one word, an empty quoted word.

| ID | Severity | Area | Finding | Resolution |
|---|---|---|---|---|
| S-30 | Minor | Verifier | A quoted NT-prefixed program path passes the program-word rules: `"\??\UNC\server\share\powershell.exe"` and `"\??\C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"`. `\??\` has one separator, so the network-path rule does not see it, .NET calls it fully qualified, and the unquoted-word rule applies only to unquoted words (the unquoted spelling was refused only because `?` is not in its character class). The reviewer measured that `CreateFileW`, the call that measures the rights, opens `\??\C:\...` as the NT path it names, so `Test-PathProtection` would read a remote access list as the identity of the verifier (the network side was not exercised). A path with one `?` became `D:\?\...` on the working drive of the verifier. | Fixed (`f6cd56a`): on Windows the program word, quoted or not, has to start with a drive letter and a separator (the reviewer's rule; the `[\\/]{2}` rule stays for its message and for POSIX paths). Four rows failed first (three accepted lines and one message); with the rule switched off the same four fail. |
| S-31 | Nit | Verifier | An empty quoted word is read differently under Windows PowerShell 5.1: for `-File x.ps1 ""` the `cmd.exe` probe and the 7 wrapper give the script one empty argument and the 5.1 wrapper gives none. For `-Command "body"` it changes nothing. The property test compares parse trees and cannot see it. | Fixed (`f6cd56a`): the quoted word must not be empty (`+` in the shape) and the empty-word test expects the shape refusal. Two tests failed first, and with the old quantifier put back the same two fail. The option reader keeps `[AllowEmptyString()]` with a direct test; removing it breaks only that test. |
| S-32 | Minor | Docs | "Not a network or device path" was false for `\??\` and "read alike" false for an empty quoted word under 5.1 until S-30 and S-31 were fixed, and the README said the PowerShell half was "tested and not only reasoned" without saying that the test checks the structure PowerShell reads and not what a wrapper hands on to the program. | Fixed in the documentation commit: the README `HookContract` row, the help comment, the controller text and the changelog entry say that the shape is expected to be read alike, what the test and the review measured, and that on Windows the drive letter decides which program path is read. |

The reviewer accepted as follow-ups the wrapper measurement (S-25 and S-31 would have failed by measurement), S-24 as Unavailable or Fail, S-20, the escape-set addition, the S-19 hardening and R-04, and added one: run the property test once in CI with a fresh printed seed (done on 2026-10-18, see the CHANGELOG). It also asked for a tail, a `-File` form and a tab inside a quote in the property test, which `f6cd56a` has. I ran a differential check of my own on `8a95351` with those features: 90,000 generated lines and 150,000 one-character mutants of accepted ones gave 108,798 accepted lines, with 0 deviations under PowerShell 7.6.6 and under Windows PowerShell 5.1.

Pass 3, part F (a bounded delta check of `f6cd56a` and `d8eddb4`): **Approve, with no must-fix finding** and one Nit. The reviewer extracted the verbatim function and constants by AST and read each line with `cmd.exe /d /c` and with the 5.1 and 7.6.6 wrappers. It confirmed S-30, S-31 and S-32 resolved:

- **S-30.** Of 46 spellings that must be refused, quoted and not (`\??\` local and `UNC`, `\?\`, `\\?\`, `\\.\`, `//?/`, `//./`, `\/`, `/\`, `C:`, `C:foo`, `C::\`, a stream on the file, a non-ASCII drive letter, rooted without a drive, a bare name, a relative path, a leading space or tab in a quoted word), 44 are refused and the two that pass are S-33. The function has 22 returns and only one returns a path, and the drive rule comes before the loop and the shape, so no earlier rule lets a word through. `GetFullPath` does not change the object: for forward slashes, a doubled separator, a trailing dot, dots plus a space, a trailing space and lower case, opening the raw word and the measured path with `CreateFileW`, as the verifier does, gives the same volume and file index.
- **S-31.** The arguments that `-File echoargs.ps1` receives under the three readers were compared for 28 targeted quoted words (a space, two spaces, a lone tab, `"a "`, `" a"`, `"-"`, `"--"`, `"-x"`, `"a\b"`, `"a" "b"`, and quoted `-File`, `-Command`, `;`, `=`, `,`, `:`, `/`, `.`, `..`): every accepted one is the same, and a lone backslash, `"a\"`, `"\\"` and `"a\\"` are refused. Of 200 random `-File` lines (68 with a whitespace-only quoted word), 198 are the same; the other two are artifacts of the reviewer's generator (a mutation put a backslash into the script path, so all three readers fail, with different exit-code mapping), not an argument difference.
- **The property test.** Sound. Run by AST against the verbatim function it generates 4,000 lines and accepts 1,841 (468 with the pinned statement, 617 with `-File`, 637 with `-Command`, 319 with a tab inside a quote, 424 with a whitespace-only quoted word, none with an empty one) with 0 deviations; the reviewer's own 24,000 further lines gave 16,576 accepted and 0 deviations under 7.6.6 and 5.1. It checks parse structure only, which the documentation now says.
- **S-32.** Nothing in the README row, the help comment, the controller text or the changelog entry claims more than the code measures. The one statement not verified end to end is that a share is read over the network: the reviewer confirmed the local `\??\C:` resolution and not the network side.

| ID | Severity | Area | Finding | Resolution |
|---|---|---|---|---|
| S-33 | Nit | Verifier | A quoted program path may carry a colon after the drive. `"C:\:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"` and `"C:\Windows\System32\WindowsPowerShell\v1.0:x\powershell.exe"` pass the drive rule. The unquoted spellings are refused, because the program-word rule allows `:` only as the drive's, and that rule does not apply to a quoted word. `CreateFileW` returns error 123 (invalid name) for both, so they name no file, and the verifier then fails closed at "the interpreter does not exist" or "could not be measured". A colon on the file itself is refused by the name rule. Only the claim that the drive rule closes every spelling falls short. I reproduced it against the verbatim function: both are accepted and `File.Exists` is false for both; the unquoted spellings and the NT path are refused (and `File.Exists` is true for the NT path, which is what made S-30 matter). | **Fixed on 2026-10-18** (see the entry of that date): a separate rule after the drive rule, with its own reason and seven rows in the `refuses <Why>` table, and not the form proposed below; the "fails closed at 'the interpreter does not exist'" of the finding is corrected there too (the two spellings end at "could not be measured"). Before that: **Not fixed, a recorded follow-up**, which is also the reviewer's classification ("before merge: nothing"). The fix is one line, `\A[A-Za-z]:[\\/][^:]*\z` for the drive rule, with two quoted rows (`C:\:\...` and `...v1.0:x\...`) in the `refuses <Why>` table that must fail without it. I left it, because the fix would put a code change on the commit after the last approval and restart the final gate for a path that fails closed; it is the first item to take together with the wrapper measurement. |

Recorded as a residual, not a finding: a drive letter that is a mapped network drive or a `subst` cannot be seen textually, and measuring it needs the mappings of the verifier's own logon session. The reviewer accepted every deferred item again: the wrapper measurement, S-24 as Unavailable or Fail, the fresh printed seed for the property test in CI (done on 2026-10-18), S-20, the escape-set addition, the S-19 hardening and R-04. Not assessed by part F: the POSIX probe branch and macOS, the off-Windows tests and the Pester suite itself (it ran only the property test body), the network side of S-30, how VS Code and the SDK host spawn the command beyond the README's table, two-account behaviour, WFP, the unsigned chain and R-04.

### Documentation

The hooks README, the changelog entry and the controller text were corrected
twice to say what each check proves and what it does not. After pass 2: the check
names, the one-identity-per-run rule, the privileges that are not read, the
fresh-process requirement, the ledger as the appender behaves, and the claims of
the pass 2 report that went beyond the code (E1 to E9). After pass 3: the launch
options, the hook-line rules and the PowerShell-only interpreter, the ASCII
relay, the module origin of the firewall cmdlets, the acknowledgement rebuild,
`-ExpectedServerIdentity`, the fact that the record schema fixes four field names
and nothing about their values, the availability limits of the appender, and the
S-09 and S-10 residuals. After pass 3 parts B to F: the hook line as a shape and not
a list, the probe named as `cmd.exe` and not as a host, the model of the Windows
PowerShell 5.1 measurement, what the evidence says about a quoted program path and
what the controller does with it, the drive rule for the program path and the
non-empty quoted word, what the seeded test and the review measured (the structure
PowerShell reads, not what a wrapper hands on), the launcher recipe (pwsh adds the
account's own module folder first), the identical-record exception of the
acknowledgement check, and the POSIX backslash. Decision 0025 carries a revision
that withdraws "exact writable roots" and records the pass 3 rules.

### Tests

Every control a finding names has a test that fails when it is removed, shown by
switching each off in turn (the mutation runs of each round are listed in the pull
request description). The twelve verifier suites and the appender suite together
have 767 passing tests and one that is skipped off POSIX. The final full
`build,test` gate, run on `d8eddb4` (the commit after it changes only records),
passed: 5,063 passed, 0 failed, 146 skipped, 90.84 % coverage against a threshold
of 65 %, 21 build tasks and no error. The gates that ran before it on earlier
commits (4,673 and 4,861 passed on the first rounds, none failed) are not its
result, and four more were stopped because the next review pass required a code
change. Nothing could run on Ubuntu or macOS here.

### Remaining risks

- Addressed on 2026-10-15: a privilege that is held but disabled, and a filtered
  administrator token, were not read (R-04). `IdentityPrivilege` reads the token
  now and refuses one that is not a standard account's; see the entry of that
  date for what stays open (the Pass on a real standard token, a disabled group
  other than Administrators, and the launcher).
- A grant file a run writes itself is not stopped by the hook: egress and
  credentials are the boundary. Hook files a host finds outside the pinned file
  are not read.
- The launcher's environment is the launcher's job: `DOTNET_STARTUP_HOOKS` and
  any other carrier that outranks the measurement cannot be measured from inside.
  Only the module path of the firewall cmdlets is measured (S-02). pwsh adds the
  account's own module folder ahead of the system ones whatever `PSModulePath` a
  launcher sets (reproduced), so a module that the verifier's other commands would
  auto-load from it is not measured; adding the folders pwsh searches to the escape
  set of `WritableRoots` is a follow-up. It was done on 2026-11-14 for the folders
  `WritableRoots` measures; Windows PowerShell 5.1's hook line stays open (R12-02,
  brief 18). See the entry of that date.
- A process of the service's own account can take or join the pipe name and make
  an append fail (S-09). An open handle on the chain head stops the service by
  design, and a silent connection holds it for as long as it stays open.
- `-Revalidate` does not bind the ledger to a run id, and the chain is not keyed,
  so whoever can write the sink and the head can write a chain that validates.
  The run id was bound on 2026-11-14, for a profile that names its run; see the entry on the run id
  of that date. The chain is still not keyed.
- Addressed on 2026-10-16: the probe ran the pinned hook line through
  `cmd.exe /d /c` alone, and both documented hosts wrap the line in PowerShell.
  `HookContract` now also runs it under Windows PowerShell 5.1 and the PowerShell
  that runs the verifier, built from the README's table of hosts, and requires 0, 2,
  2 under each; see the entry of that date for what stays open (no host ran the
  line).
- The hook line is accepted by a shape that `cmd.exe`, PowerShell and a POSIX shell
  should read alike. The PowerShell half of the shape's claim is tested with the
  host's parser over generated lines, which checks the structure PowerShell reads and
  not what a wrapper hands on to the program it starts; the review checked that by
  hand for sampled `-File` lines (`cmd.exe`, Windows PowerShell 5.1 and 7 agree, once
  an empty quoted word is refused). Nothing was run on a POSIX host or on VS Code.
- Addressed on 2026-10-16: a quoted program path, which a path with a space needs
  (PowerShell 7 under `Program Files`), passed the check and the probe and failed
  under both hosts. It now fails by measurement under both wrappers (exit 1, a
  warning in VS Code and a denial of every call in the Copilot SDK host), so a
  profile that pins one has to pin an unquoted path without a space. The interpreter
  is judged by its name and not by an identity.
- On Windows the program path has to start with a drive letter and a separator. A
  quoted path with a colon after the drive (`"C:\:\...\powershell.exe"`,
  `"C:\...\v1.0:x\powershell.exe"`) passes that text rule and names no file, so the
  verifier fails closed (S-33, a follow-up with a one-line fix and two test rows; closed on
  2026-10-18, see the entry of that date). A
  drive letter that is a mapped network drive or a `subst` cannot be seen textually;
  measuring it needs the mappings of the verifier's own logon session.
- A server that replays the earlier acknowledgement of a record identical to one
  already stored passes the client's acknowledgement check, so the client cannot
  prove how many times a record was stored (S-19). The reviewer's hardening,
  `sequence == head before send + 1`, needs the client to read the chain before it
  sends and is not done. Closed on 2026-11-13; see the entry on S-19 of that date.
- Two service-side `[Console]::Error.WriteLine` lines print raw exception text
  (S-20). No client text reaches them, which was traced and not provoked; routing
  both through `Format-RefusalText` is a follow-up, and so is gating the S-04 and
  S-05 appender tests, which are Windows-only although three of the functions are
  platform-neutral. Closed on 2026-11-13; see the entry of that date.
- No test used a second Windows account, and the firewall results depend on a
  premise about the filtering platform that was not verified. Nothing could run on
  Ubuntu or macOS here, and most of the appender tests are Windows-only.
- Package feeds, browsers, web tooling and MCP servers are not measured.

## 2026-10-12: hand-resolved merge of `main` into the calibration branch (hook scripts)

The built-in `security-review` agent reviewed, read-only and in a fresh context,
the merge commit `ef96c2d`, which brought `origin/main` (prompts 03 and 08) into
`ai/calibration-phase-2` with 9 hand-resolved conflicts, three of them in hook
scripts that run at every session start and close. It ran nothing and made no
network call. The Custom `security-reviewer` agent was not tried, because its
first model was unavailable in this runtime in earlier reviews. The owner chose
`review: on` for this change after the pull request was open.

### Scope

- Did the resolution keep both sides' behaviour; do the hooks keep their
  contracts (one JSON object, exit 0, pure ASCII, syntax that Windows PowerShell
  5.1 reads); can a session id or a path alter the command that the context hands
  to the agent, or move the clock or the state file; and which merged behaviours
  have no test.

### Verdict

**Approve with changes.** No Blocker: no lost behaviour, no broken hook contract,
and no injectable command or path traversal. One Major and one Minor were fixed
with this entry. A follow-up change closes three of the four test findings
(M-03, M-05, and M-06); M-04, a hardening item, stays open.

### Findings

| ID | Severity | Area | Finding | Resolution |
|---|---|---|---|---|
| M-01 | Major | Hooks | Main's case-sensitive session-key rule reached only the copies that main knew. Two hooks of the calibration side still derived the key with the case-insensitive `-replace`, so a session id holding U+0130 or U+212A named another state file in the PreCompact and PostToolUse hooks than in SessionStart and Stop, and the compaction count and the backstop used a different file than the one SessionStart seeded. | Fixed. The three sites use `-creplace`; a session id with those letters runs through every hook in both editions, and a static check demands the rule in all five scripts. |
| M-02 | Minor | Hooks | The re-send after a compaction wrote plain JSON, so Windows PowerShell 5.1's OEM code page turned a non-ASCII area name into a byte that is no UTF-8, or into a quote. | Fixed. The hook escapes every character above ASCII as SessionStart does; a test with an umlaut and U+02BA checks both editions, and a test keeps the two copies of the helper verbatim. |
| M-03 | Minor | Tests | No test combines the shortened closing line with a calibration sentence, so the documented 1024-character minimum is no longer exercised with a sentence. | Fixed in the follow-up. At the 1024-character minimum, a reader path of 225 characters with a clock path of 360 or of 430 ends the shortened lines with the sentence or with the omitted notice; two more cases set the limit to the character, so a sentence fits exactly or gives up its last area. Mutations: moving the closing-line shortening below the calibration block fails the first two, `-1` changed to `-0` fails the "one character over" case, and `-2` fails the exact fit, each in both editions. |
| M-04 | Nit | Hooks | The key alphabet allows a dot, so a session id of the form `X.familiarity` gives a clock path equal to the state path of `X`; it needs a host-assigned id of that shape. | Open. |
| M-05 | Nit | Tests | The shortened closing line's quoting is tested only with a quote-free path. | Fixed in the follow-up. A clock root with an apostrophe and a right single quotation mark is read back by the PowerShell parser from the shortened line. A mutation that drops the quote doubling there fails the new test while the existing tests stay green. |
| M-06 | Nit | Tests | The only guard of the state-file filter in the elapsed reader asserts `turn 1`, which an unfiltered reader might also print (speculative, confidence 4). | Closed, not a gap. The cast of `$null` to `[datetimeoffset]` throws in both editions, so a reader that took the state file prints `unavailable`, and the existing assertion fails; removing the filter confirmed it in both editions. The test now also compares the printed start time with the clock's. |

### Not assessed

- Windows PowerShell 5.1 for `Hooks.Tests.ps1`, which a gate runs in the Pester
  host's edition only. Run once under 5.1 on 2026-10-12: 143 passed, 25 failed.
  All 25 failures are in the `Block-RemoteMutation` timeout Context, whose helper
  uses `ProcessStartInfo.ArgumentList` and `Process.Kill($true)`, which exist only
  in PowerShell 7. Every test of the session hooks passed, the new quoting test
  (M-05) among them.
- The OEM best-fit table itself, and the agent terminal's own encoding.

## 2026-10-12: independent review of the egress controls of the private eval kit (prompt 06c)

The built-in `security-review` agent reviewed, read-only and in a fresh context,
the code that Amendment 6 added to the private eval kit: the model allowlist and
backend check, the reply scan and the labeller's prompt check, the batch call
sites in the runner, the judge, and the labeller, the label lock, the run freeze,
and the held-out selection. It ran no kit script, opened no data file, made no
network call, and quoted no case, reply, or label text. The Custom
`security-reviewer` agent was not tried, because its first model was unavailable
in this runtime in earlier reviews. This entry closes the first risk that the
entry below leaves open, "no independent review of the new code". The fixes were
made in the kit by a background agent, test-first and with the kit's offline
self-checks only, and the same reviewer checked them in four rounds. The kit
lives outside every git working tree, no shipped file changed, and no run or
model call was made.

### Scope

- The five questions of prompt 06c: can any model id, URL, header, or
  environment value other than the allowlist and the Copilot default reach the
  batch call; can a reply, a situation, or a message reach a model without the
  reply scan or the prompt check; does the blocking rule set miss a case that the
  shape rules would have caught; can a labels file or the held-out selection
  change after the freeze without the verifier failing; and which controls have a
  test that would still pass if the control were removed.

### Verdict

**Approve with changes, after four rounds.** The first reading found 2 Blockers
and 5 Majors and advised no further paid call before E-01 and E-02 were fixed.
The fixes closed both Blockers; the second round found 2 new Majors (E-12, E-13)
and a regression (E-14), the third round fixed them, and the fourth found no
Blocker and no unconditional Major. Nothing found blocks a further paid run if it
starts as `pwsh -NoProfile -File … -RequireFreeze`, and the reviewer lists what
must happen before the next freeze under *Before the next freeze*. The minors
E-15 and E-16 stay open, and the owner ruled on E-08 and E-09 on 2026-10-20
(see the findings). The kit is a seatbelt against accidents and
kit defects, not a boundary against the owner's own account: the freeze ledger
lives in the kit, so only a freeze digest recorded outside it makes the freeze
tamper-evident against the same user.

### Findings

| ID | Severity | Area | Finding | Resolution |
|---|---|---|---|---|
| E-01 | Blocker | Egress | A session default parameter value for the batch command, by name, wildcard, or alias, binds a parameter such as the API base past the guard, which checked only the call's own options, two environment variables, and the session context; ShellPilot replays it to its workers. | Closed. The guard refuses a matching entry, and every call site runs the batch in a child scope with the defaults disabled; verified against the exact, wildcard, alias, cased, and padded key forms. See E-12 for the residual. |
| E-02 | Blocker | Integrity | The verdict cache is frozen as a byte prefix and may grow, but the reader let the last record per key win, so an appended repeat with the other verdict changed the grade and the held-out comparison while the verifier stayed silent. | Closed. The reader keeps the first record and refuses a repeated key; the freeze writer and the verifier reject a key that repeats one in the frozen prefix. |
| E-03 | Major | Integrity | The verifier re-hashed only what the freeze lists, so a label file added after it passed, and the freeze file itself was unanchored. | Closed as far as one folder allows: an anchor ledger records the freeze's digest, and the verifier fails on a missing ledger entry, an empty file list, and a kit label file absent from the freeze. The ledger sits beside the freeze, so a rewrite of both by the same user still verifies; the next freeze therefore records the freeze's digest outside the kit and checks it with `-ExpectedSha256` before each paid step, and a damaged ledger line now fails closed. A missing ledger file still reads as "unfrozen" without `-RequireFreeze`. |
| E-04 | Major | Integrity | Calibrating the judge never asked for a frozen run folder and trusted a label file's own sidecar. | Closed. In a frozen folder the label file must be a frozen artifact with its frozen hash. |
| E-05 | Major | Integrity | Neither the lock nor the freeze hashed the reply files that labels reference, or the item list. | Closed. The lock carries a manifest of the referenced files' digests, and the freeze lists them and the item list. |
| E-06 | Major | Path handling | The labeller joined an item's sample path to the kit folder without a containment check, so a parent-relative path was read and sent. | Closed. The labeller and the calibration command resolve the path, links included, and refuse one outside the kit; the two joins of the list builder that the first fix missed use the same resolver since round 3. A check-then-read race and the symlink branch (no elevation here to test it) remain. |
| E-07 | Major | Leak checks | The owner's term list, the control for names and addresses, is required nowhere: a missing file was skipped silently, and nothing asserted a non-empty scan context. | Closed. An empty scan context is refused centrally, the runner and the labeller print its counts, and a freeze requires the file and pins the candidate and seed files. The file does not exist today, so the next freeze stops until it does. |
| E-08 | Minor | Leak checks | Advisories (an e-mail, a token, a hex id, a path) are computed and dropped by every caller, and a provenance digest goes out on the judge path. | Ruled by the owner on 2026-10-20: block the high-precision subset (a non-example e-mail, secret prefixes, any provenance digest, UNC and profile paths) and print per-run counts by rule. Not built; it binds the next freeze. |
| E-09 | Minor | Backend check | The guard encodes ShellPilot 0.4.0's resolution order, but the scripts accept a later module by name, and a session function of the same name shadows it. | Ruled by the owner on 2026-10-20: accept 0.4.0 or later and call the module's own command by exact name, `& (Get-Command Invoke-ShpBatch -Module ShellPilot)`. Not built; it binds the next freeze. Residual: a newer version that changes the destination setting is not detected, because the reviewer's version and `.psm1` SHA-256 pin was not chosen. |
| E-10 | Minor | Held-out check | The header claimed that the selection depends on no reply's content, but eligibility reads the reply, and the independence test mutated a property the function never reads. | Closed. The claim is corrected and the test replaced by checks that mutate reply content. |
| E-11 | Nit | Output | The calibration command printed the judge's quote and label text to the host, where a transcript keeps it. | Closed. It prints ids and counts; the text sits behind an explicit switch. |
| E-12 | Major | Egress (found in round 2) | A session default for `-ErrorAction`, also by wildcard, turned an uncaught `throw` in a guard into a statement that the caller continued past when the guard was a bare call, which silenced every guard, the E-01 refusal included. | Closed in round 3 by three independent layers: the runner and the labeller read the incoming defaults and exit with code 2 when they would bind the batch; nine scripts shadow the session defaults with a disabled table before anything else runs; and the 28 advanced functions that throw set a stopping error preference first. A session alias named like a guard, or a script trace, is ambient code of the E-09 class; `pwsh -NoProfile` closes both. |
| E-13 | Major | Integrity (found in round 2) | The cache path was never required to equal the frozen one, so a judge, a grade, or a comparison could read another file while the freeze verified the original. | Closed for the judge, the grade, and the held-out comparison. The calibration command keeps its own cache path, which the reviewer would bind too (open). |
| E-14 | Minor | Integrity (regression of the E-03 fix, found in round 2) | The completeness check demanded that every kit label file be in the freeze, but a held-out import creates label files after it. | Closed. Only the held-out labels are exempt from the run freeze and the import anchors them; run both verifiers. |
| E-15 | Minor | Egress (found in round 4) | The default expressions in the parameter blocks of the entry scripts use a cmdlet that runs before the shadow. | Open. Use the .NET path combiner; `pwsh -NoProfile` closes it meanwhile. |
| E-16 | Minor | Integrity (found in round 4) | The frozen-folder check binds the label file, the cache, and the token limit, but not the eval file, the instruction, the fixture, or the reader path. | Open. An integrity gap, not an egress path. |

### Tests

The kit's offline self-checks grew from 171 to 394 checks for the privacy guards,
from 15 to 25, 18 to 30, 49 to 56, 17 to 80, 15 to 32, and 66 to 108 for the
judge run, the runner, the label tools, the freeze tools, the held-out sheet, and
the judge protocol, and the repository-records check stays at 9. Each new test
failed without its fix, shown by scratch reversions or in-test mutations, and the
author reran all eight after the last round. The reviewer's list of 14 controls
whose test would still pass if the control were removed is now covered for the
ones this entry fixes; still uncovered are the model pattern's trailing-newline
case, the GitHub host's equality against a prefix match, the reply and identifier
arm of the labeller's prompt check, and the advisories that no caller acts on.

### Before the next freeze

1. Create the owner's term file beside the kit; the freeze refuses without it,
   and it does not exist today.
2. Record the freeze's SHA-256 in the decision record, outside the kit, and run
   the freeze verifier with `-ExpectedSha256` before each paid step.
3. Count repeated keys in the real verdict cache with a count-only script,
   because a repeat now stops a read.
4. Treat the pre-fix held-out set and the freezes of 2026-10-10 as unverifiable,
   since they have no anchor, and redo them.
5. Start the kit as `pwsh -NoProfile -File … -RequireFreeze`.
6. Bind the three choices the reviewer disputed, as the owner ruled on
   2026-10-20: the calibration command's cache path, a comparison without a
   freeze, and a missing ledger that reads as unfrozen. Build the blocking
   subset of E-08 and the exact-name call of E-09.
7. Optionally close E-15 and E-16, and switch script tracing and strict mode
   off in the shadow block.

### Remaining risks

- E-15 and E-16 stay open until the owner closes them; E-08 and E-09 are ruled
  (2026-10-20) and bind the next freeze, and the owner accepted E-09's residual.
  The kit is a seatbelt against accidents and kit defects, not a boundary against
  an operator or an agent that can run a shell.
- The runner's Run mode, the labeller, and the freeze writer were checked with
  stand-ins and sandbox copies, and never run for real after the fixes.
- The freezes of 2026-10-10 are unverifiable by design, and the next freeze needs
  the owner's term file and every referenced reply file inside the kit. A cache
  that already repeats a key now stops a read.
- Build and fixture scripts of the kit count as data files from now on: the
  reviewer's structural reading shows that such scripts can hold case and reply
  text, and one probe of the fixing step printed up to 70 characters of each of
  eight statements of one of them into that agent's context. Nothing else of the
  kind was found.
- Provider-side retention and training use stay UNVERIFIED (TBD-11), and what was
  sent cannot be recalled.
- Not assessed: provider handling, proxy or TLS interception, a real run, and the
  owner's session defaults, which decide whether E-01 was live.

## 2026-10-10: egress controls of the private eval kit (Amendment 6, A27)

A self-review by the `software-engineer` Custom agent of the controls that close
findings F-03, F-04, and F-06 of the entry below. It is not an independent
review: the independent-review switch was off, so none was run, and the work is
named for one under *Remaining risks*. The kit lives outside every git working
tree; no case, reply, or label text is quoted here, and no shipped file changed.
Decision record 0028 records the run that used the controls.

### Scope

- A model allowlist, a backend check, and a fixed batch-option list, called
  immediately before every batch call in the runner, the judge, and the
  labeller; the reply scan before a reply is sent; the labeller's prompt check;
  and a SHA-256 lock on every labels file, refused by the freeze when missing or
  edited.
- The question: does the kit now refuse a further provider, an alternative
  backend, a leaking reply, and an unlocked label file before the first paid
  call, and is each refusal tested against a stand-in so that a refusal is
  distinguishable from an inert test?

### Verdict

**Controls hold, with limits named below.** Every control is covered by a test
that failed without it: the privacy-guard suite grew from 86 to 171 checks, and
removing the guard call from the runner's Run mode, as a mutation, failed 3 of
them. Each refusal test has a positive control that reaches the stand-in, and a
smoke test of the real writer and judge path ran before the run (0.05 USD).

### Findings

| ID | Severity | Area | Finding | Resolution |
|---|---|---|---|---|
| F-03 | Major | Code control | A further provider or an alternative backend was not refused. | Closed. The allowlist (Anthropic, OpenAI, Google, and xAI ids), the backend check (no `SHELLPILOT_API_BASE`, no GitHub host other than github.com, no ApiBase or GitHubHost in a loaded ShellPilot context), and a 13-option batch list run before every batch call; `-ApiBase` is not a parameter of the runner or the labeller; a static test proves the call precedes every `Invoke-ShpBatch`. |
| F-04 | Minor | Leak checks | Replies were not scanned before they left, and the labeller was outside the guard test. | Closed. A history name, a private term, or a whole candidate source message blocks a reply, which is withheld and never sent; the scan reads past the case checker's 16,384-character stop. The labeller is under the guard test, and its prompt carries no identifier. |
| F-06 | Minor | Integrity | Only the final labels file was hash-locked. | Closed. 9 labels files are locked; the labeller locks its own output; Calibrate requires a lock for every protocol; the freeze refuses an unlocked or edited file and records each one. |
| F-09 | Minor | Leak checks | A scan that blocks on every path, identifier, or e-mail shape would withhold ordinary technical replies. | Accepted. Those shapes are advisories; only history names, private terms, and source messages block. |
| F-10 | Nit | Backend check | The ShellPilot session context is read only when the module is already loaded, so the check never imports it. | Accepted. A context set later in the same process is seen at the next call, since the check runs before every batch. |

### Remaining risks

- **No independent review of the new code.** It touches a disclosure boundary;
  a `review: on` pass over `PrivacyGuard.ps1` and the two callers is
  recommended before any further paid run. Done on 2026-10-12: see the entry
  above.
- The scan catches only what its rules and the private term list name: names and
  addresses absent from that list, and letters-only Base64, remain the owner's
  read.
- Provider-side retention and training use are UNVERIFIED (TBD-11, recorded as
  UNVERIFIED by the owner on 2026-10-10), and what was sent cannot be recalled.
- A model id on the allowlist can still be served by an upstream the kit cannot
  see; the allowlist names recipients, not infrastructure.
- A reply under attack could steer one judge vote; the votes are not independent
  against an injection inside it, and the fixed reading of 10 passing replies
  found no text addressed to a grader.

## 2026-10-10: labelling path of the private eval kit

The built-in `security-review` agent reviewed, read-only and in a fresh context,
the path by which 40 calibration items reached seven AI labellers. It had no
model or network call, did not run the kit's scripts, and quoted no case or
reply text. The Custom `security-reviewer` agent was unavailable because its
first model was not offered. Decision record 0028 rules on it as A27.

### Scope

- The labelling scripts and their prompt, the way the model gateway routes each
  labeller, the leak checks on the labelling input, where the labels are stored,
  and the label combination rule. File names only; the kit lives outside every
  git working tree.
- The question: what widens when real-derived items reach Google and xAI, and is
  the record's Security section still accurate?
- Out of scope: provider-side data handling, which cannot be checked offline.

### Verdict

**Approve with changes.** No Blocker and no exploitable defect. The labeller call
holds no tool, file, or write channel, is stateless, and sends six authored
fields. The gaps are in the record's wording and in unenforced controls.

### Findings

| ID | Severity | Area | Finding | Resolution |
|---|---|---|---|---|
| F-01 | Major | Record | The Security section called the widened path "the same provider and model" and omitted the labeller prompt, the recipients, and the submission counts. | Fixed in Decision 0028: a new Security paragraph; the case count is 6, 5 of them in the 40 items. |
| F-02 | Major | Data handling | The retention and training use of Google and xAI traffic through the gateway, and the plan tier, are UNVERIFIED. | Open as TBD-11, owner, before the next freeze. |
| F-03 | Major | Code control | The rule that a further provider needs a ruling is not enforced: the model id is free-form and nothing refuses an alternative backend. | Required before the next freeze: a model and backend allowlist (Delivery increments item 10). |
| F-04 | Minor | Leak checks | Replies are not scanned before they leave, and the labeller is outside the guard test. | Required before the next freeze (item 10). |
| F-05 | Minor | Review scope | The labelling scripts post-date the 2026-10-09 review's files. | Closed by this entry. |
| F-06 | Minor | Integrity | Only the final labels file is hash-locked, not the seven labeller files. | Required before the next freeze (item 10). |
| F-07 | Minor | Independence | The labellers are independent runs, not independent against an injection in a reply. | Stated in the Security section and in A26. |
| F-08 | Nit | Path handling | A sample path is joined without a containment check; the input is kit-internal. | Optional. |

### Remaining risks

- Provider-side retention and training use are UNVERIFIED, and what was sent
  cannot be recalled. The owner accepted the disclosure on 2026-10-10, subject
  to this review.
- Names and postal addresses absent from the private term list, and letters-only
  Base64, are still caught only by the owner's read.
- The reference labels are mostly AI consensus; two labellers share the judge's
  provider and one wrote the replies.
- A string that works on a model class could steer several labellers at once.

## 2026-10-09: privacy boundary of the private eval kit

The built-in `security-review` agent reviewed the private calibration eval kit in
a fresh, read-only context. It could not write files, so the parent saved each
report. The Custom `security-reviewer` agent was unavailable because its first
model was not offered. The reviewer re-ran its own reproductions after each fix
instead of reading the diff.

### Scope

- The kit's case checker, the runner's location and destination guards, the
  case-set checker, and the repository records that describe them, at
  `ai/calibration-phase-2`. File names only; the kit lives outside every git
  working tree and its content never enters this repository.
- The question: does Decision record 0028 criterion 28 hold, meaning no eval
  case records a history name, a path, a session identifier, or source text?
- Out of scope by design: the private eval data and the protected run folders,
  whose manifest the reviewer hashed before and after every round and found
  unchanged.

### Verdict

| Round | Verdict | Blocker | Major | Minor |
|---|---|---|---|---|
| 1 | Request changes | 0 | 2 | 1 |
| Verification 1 | Request changes | 0 | 2 | 2 |
| Verification 2 | Request changes | 0 | 2 | 1 |
| Verification 3 | Request changes | 0 | 0 | 1 |

Every Major was verified fixed by the reviewer. The one Minor left in round 3
was fixed afterwards and checked by the author's own tests, not by a fourth
review round. The reviewer confirmed criterion 28 for the current case set and
kit location, as scoped by the remaining risks below.

### Findings

| ID | Severity | Area | Finding | Resolution |
|---|---|---|---|---|
| P-01 | Major | Case checker | Forms of a prohibited identifier were accepted. | Fixed: structural, rule-based checks with safe labels, whole-token short terms, and a size cap. |
| P-02 | Major | Runner | No operational refusal to read or write inside a git working tree. | Fixed: a guard before every read and write, links resolved, failing closed. |
| P-03 | Minor | Decision 0028 | One subsection named the source machine. | Fixed in the working tree; an earlier commit keeps it. |
| V-01 | Major | Case checker | A dotted property name spoofed the digest exemption. | Fixed: exemptions match structural path segments. |
| V-02 | Major | Runner | A case id could write outside the accepted work folder. | Fixed: case ids must be plain path components, and every destination must stay below the work folder. |
| V-03 | Minor | Case checker | Labels and diagnostics echoed rejected text. | Fixed with S-03. |
| V-04 | Minor | Case checker | Short candidate identifiers were not collected. | Fixed. |
| S-01 | Major | Case checker | The expectation exemption applied to any nested property of that name. | Fixed: it applies to the one top-level field only. |
| S-02 | Major | Case checker, runner | A repeated JSON key hid an earlier value from every check. | Fixed: both load the eval through a reader that refuses repeated keys. |
| S-03 | Minor | Case checker | Source-text labels and one detail line echoed content. | Fixed: labels are source-aware and details are counts. |
| S-04 | Minor | Reader | A key pair differing only by case made the conversion error name the keys. | Fixed with a failing test first; no review round followed. |

### Remaining risks

- Personal names and postal addresses that are not on the private term list
  still depend on the owner's read of each case. The owner accepted this on
  2026-10-09.
- Base64 made only of letters is not recognized as an opaque token. The owner
  accepted this on 2026-10-09.
- One earlier commit keeps the old source attribution. The owner accepted
  keeping the history as it is on 2026-10-09.
- The reviewer did not live-test every filesystem alias form. The author's
  check covers a junction. The owner deferred a live alias test to a later
  round.
- Sending a case to the model provider remains an intentional disclosure.

## 2026-10-01: contributor calibration

The `security-reviewer` Custom agent reviewed the change set in a fresh,
read-only context, with the diff handed over as a file. It applied the five
axes of the `code-review-and-quality` Skill (design, correctness, complexity,
tests, clarity) with the severities Blocker, Major, Minor, and Nit, and an
agentic security lens: the lethal trifecta and the OWASP Top 10 for LLM
Applications. In the fix round it verified each fix by re-running its original
reproduction, not by reading the diff.

### Scope

- The `ai/contributor-calibration` branch from `a592832` to `6b00681`: the
  always-on
  [`contributor-calibration`](../com.github.copilot/rules/contributor-calibration.instructions.md)
  Instruction, the `/simpler` and `/deeper` Prompts, the edits to `grill-me`,
  `software-architect`, `gilb-requirements-engineering`, and `memory-bank`, the
  Glossary terms, Decision record 0027, and
  `tests/ContributorCalibration.Tests.ps1`.
- Two private helpers that never enter the repository: a script that searches
  the local chat history for eval candidates and redacts them, and the
  behavior-eval runner that sends approved, anonymized prompts to the model
  backend and grades the replies with a pinned LLM judge. Their findings are
  listed here without their content.
- Out of scope by design: the private eval data, which holds chat excerpts.

### Verdict

| Round | Reviewed state | Verdict | Blocker | Major | Minor | Nit |
|---|---|---|---|---|---|---|
| 1 | `6b00681` | Fail | 0 | 4 | 9 | 6 |
| 2, fix round | fixes on top of `0996292`, committed as `21d4d50` | Pass | 0 | 0 | 11 | 2 |

The round-2 counts are new findings against the fixes and the runner, raised
after all four Majors were verified closed. All of them are resolved: F-04 in
`21d4d50`, the helper findings in the private helpers themselves, and F-03 on
2026-10-02.

The change set adds no leg of the lethal trifecta: no private-data scope, no
untrusted-content ingestion, and no outbound channel. Its two Instruction
Majors were an injection surface and an excessive-agency path.

### Findings

| ID | Severity | Area | Finding | Resolution |
|---|---|---|---|---|
| CAL-01 | Major | Instruction | `not sure, you pick` could hand over irreversible, destructive, security-relevant, or authorization decisions (LLM06, excessive agency). | Fixed: a delegated answer never authorizes such an action; the agent states the consequence and asks for an explicit answer. |
| CAL-02 | Major | Instruction | The delegation trigger had no provenance, so a fetched page, a file, or tool output containing the phrase could forge it (LLM01 leading to LLM06). | Fixed: delegation counts only when the contributor writes the phrase. |
| CAL-03 | Major | Private search helper | Path redaction left names in unquoted paths with spaces, in POSIX and home paths, and in one-segment paths; the self-check claimed coverage it lacked. | Fixed, with checks that failed first. |
| CAL-04 | Major | Private search helper | Secret redaction missed PowerShell credential parameters, HTTP authorization headers, passwords written in prose, and AWS access key IDs. | Fixed, with checks that failed first. |
| CAL-05 | Minor | Private search helper | Phone numbers and German tax and court file numbers stayed in clear text, while the header promised redaction. | Fixed; the header now states that names and postal addresses are not redacted and every candidate needs a human read. |
| CAL-06 | Minor | Private search helper | A rerun silently overwrote the annotated review file. | Fixed: `-WhatIf` support and timestamped output names. |
| CAL-07 | Minor | Private search helper | A second chat snapshot was appended instead of replacing the first, misaligning later edits. | Fixed, with a two-snapshot fixture. |
| CAL-08 | Minor | Instruction | At `new`, one bundle of defaults could include irreversible or security-relevant choices. | Fixed: only reversible, low-impact details are bundled. |
| CAL-09 | Minor | Instruction, Decision record | A compaction silently resets every level to `familiar`. | Documented in Decision record 0027 and the README. No Instruction line, by ruling: unmeasured always-on text, and the Phase 2 profile removes the need. The reviewer accepted the ruling. |
| CAL-10 | Minor | README | "Nothing about you is stored" claimed more than the mechanism guarantees. | Fixed: no familiarity level is written to a repository. |
| CAL-11 | Minor | Tests | The tests proved wording only; nothing guarded that `/simpler` keeps the delegation option or that no Customization drops a safety step at a level. | Fixed: both guards added. |
| CAL-12 | Minor | `AGENTS.md` | The tool-neutral entry point did not mention a third always-on Instruction. | Fixed. |
| CAL-13 | Minor | Private search helper | A rerun mined the sessions that reviewed earlier candidates. | Fixed: several sessions can be excluded, and `-Since` limits the search. |
| CAL-14 | Nit | `software-architect` | It restated the Instruction instead of citing it. | Fixed. |
| CAL-15 | Nit | `gilb-requirements-engineering` | "level" was ambiguous next to Familiarity level. | Fixed: "target level". |
| CAL-16 | Nit | Private search helper | It redacted a whole transcript before truncating it. | Fixed. |
| CAL-17 | Nit | Private search helper | Over-long messages inflated the reported denominator. | Fixed: counted separately. |
| CAL-18 | Nit | Private search helper | The IBAN rule left the last group in clear text. | Fixed. |
| CAL-19 | Nit | Tests | Encoding and helper-call style were inconsistent. | Encoding fixed; the call style stays by ruling, as valid Pester usage. The reviewer accepted the ruling. |
| F-01 | Minor | Private search helper | UNC and drive-root paths with one segment leaked their leaf name. | Fixed. |
| F-02 | Minor | Private search helper | The new rules over-redacted prose after a path and ordinary sentences about tokens. | Fixed, with checks that the prose stays. |
| F-03 | Minor | Instruction | Every decision question offered `not sure, you pick`, although a delegated answer cannot authorize an irreversible action. | Fixed on 2026-10-02: a question that authorizes such an action offers no such option. |
| F-04 | Minor | Tests | The safety sweep matched single lines, so wrapped, reordered, or conditional wording escaped it. | Fixed: it matches sentences, with three positive controls. |
| F-05 | Minor | Private search helper | The default session exclusion matched only in a top-level Copilot CLI session. | Fixed: chat files written in the last ten minutes are skipped, which covers the running session. |
| E-01 | Minor | Private eval runner | A reply containing the fence marker could close the judge prompt's fence early. | Fixed: fence markers inside a reply are neutralized. |
| E-02 | Minor | Private eval runner | One truncated line in the verdict cache broke every mode. | Fixed: unreadable lines are skipped with a warning. |
| E-03 | Minor | Private eval runner | A label path could point at any file and send its content to the judge model. | Fixed: a path outside the eval folder is refused before any model call. |
| E-04 | Minor | Private eval runner | A call that reported no cost did not count against the budget. | Fixed: such a call counts a conservative estimate. |
| E-05 | Minor | Private eval runner | Results did not identify the verdict cache that produced them. | Fixed: the cache hash is recorded with the results. |
| E-06 | Nit | Private eval runner | Two summary metrics used different denominators. | Fixed. |
| E-07 | Nit | Private eval runner | A multi-turn prompt dropped its middle turns. | Fixed: only the last speaker marker splits the prompt. |
| U-01 | Minor | Private search helper, older code | The base64 rule mangled URL paths. | Fixed: a run without digits is left alone. |

### Evidence for the Instruction fixes

The Instruction changes went through the private behavior eval, run with
`claude-opus-5` and graded by a pinned `gpt-5.5` judge that agreed with human
labels on 38 of 40 replies. With the CAL fixes the Instruction passed all 51
samples on the 17 cases, against 52.1% without it, and the final wording passed
39 of 39 samples on the 8 cases its rewording could affect. For F-03, the
current and the fixed wording ran side by side: both kept the
`not sure, you pick` option on 10 of 10 decision questions, and on a probe that
needs a push both asked for an explicit answer without offering the option, in
2 of 2 replies each. The fix removes a contradiction in the text; it changed no
measured behavior.

### Strengths the reviewer recorded

- The privacy invariant is designed in, not asserted: the Instruction, the
  `memory-bank` Skill, the Glossary, and a test all keep familiarity levels out
  of repository files.
- Safety is kept separate from presentation: a level changes wording and depth,
  never a warning, a test, or a review.
- The documentation matches what shipped, and the reporting includes results
  that moved against the change.
- The private helpers make no network call of their own, and the eval runner
  disables every tool, so it cannot become an exfiltration path.

### Remaining risks

- The behavior eval stays private because its cases come from personal chats,
  so its numbers cannot be reproduced from this repository.
- `claude-opus-5` sometimes answers an English message in German when a thin,
  single-turn context carries German-region cues. The rate drifts between runs,
  and an explicit language rule made it worse.
- Until the Phase 2 profile exists, a contributor restates levels after every
  new session and every compaction.
- The `security-reviewer` agent ran read-only, so this review has no entry yet
  in its `.memory-bank/assessment-log.md`.
