# Security reviews

Independent security and quality reviews of changes to Copilot Atelier, newest
first. Each entry records the scope, the verdict, every finding with its
severity and resolution, and the risks that remain.

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
  with a fresh seed in CI, which was on that list, is done (see the CHANGELOG).

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
| U-01 | Minor | `Get-HookWrapperProblem` | The reason of a `Violation` or an `Unmeasured` entered the evidence without `Format-RelayedText`, although the path next to it was relayed. The path of the second wrapper is `MainModule.FileName` of the verifier's own `pwsh`, and nothing limits it to printable ASCII. Reproduced with the real `Test-PathProtection` and a wrapper in a folder named with an accent and four tag characters (a hidden "PASS"): they reached a 1,425-character Fail evidence verbatim. The interpreter's path is limited by `Get-HookInterpreter`, so the same pattern for the interpreter is safe for the path (the access check's reason is another matter: W-03). The result can only be Fail or Unavailable, and it needs someone who chooses where the verifier's `pwsh` runs from | Fixed: both reasons go through `Format-RelayedText` with the largest cap the function takes (1,000 characters). Tests with an accent and four tag characters (five `?`) for the Violation and for the Unmeasured, and a length bound; mutations G13 and G14 (either relay dropped) and G15 (the cap cut at one site) were caught, but the delta check showed that the bound did not pin the value of the cap (V-04) |
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
| V-05 | Nit | the docstring of `Get-HookWrapperProblem` | "Like every other text this check did not compose" is false: four `$($_.Exception.Message)` texts of `Test-HookContract` still reach the evidence unrelayed | Fixed: the docstring says "as Measure-HookWrapper does for the texts it relays". Not fixed, recorded: all four lines exist unchanged at `origin/main`, and so do the two closure details of the interpreter (W-03), so relaying them is a separate change, to be made with S-20 |
| W-01 | Nit | this entry | The committed text still held the placeholder "the final gate is the next item", and its introduction said that the change "was gated again" while the only finished gate predated the V fixes | Fixed: the gate on `ecd82fc` is recorded under Tests, and the introduction points there |
| W-02 | Nit | this entry (Tests) | "The delta round changed … one attribute (the `[OutputType]` …)" is wrong: the attribute changed in `01b0e31`, in the first round. `eff87a8` changed comments and one string literal of `Test-HookContract` only | Fixed: the attribute change is placed after the 88-mutation run, where it happened, and the delta round is said to have changed comments and one evidence string |
| W-03 | Nit | this entry (Remaining risks), the U-01 row | "Four `$($_.Exception.Message)` texts" is true but incomplete: the two closure details of the interpreter (lines 2885 and 2891 of the verifier at `ecd82fc`, `$detail`) also pass the access check's reason unrelayed, and that reason is localized .NET text from `GetBaseException().Message`. The interpreter's path is limited to printable ASCII, but the reason is not; the first review's remark that the interpreter pattern "is safe" covered the path only | Fixed in the records: the follow-up reads "four texts and the two closure details of the interpreter", and the U-01 row says that the safety covers the path. Not fixed, recorded: both are older than this change (the same lines exist at `origin/main`), so relaying them is a separate change, with S-20 |
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
  `origin/main`), so relaying them is a separate change, to be made with S-20.
- The suite of the check takes about 85 seconds longer and a verify run about 7 seconds
  longer, on one host; the reviewer did not verify the first figure.
- The Custom `security-reviewer` agent cannot start in this runtime until the first entry
  of its `model` array resolves or the dispatch falls back, so a review here goes to the
  built-in `security-review` agent.
- The remaining risks of the 2026-10-14 and 2026-10-15 entries that this change does not
  touch stay open: S-19, S-20, the escape set of `WritableRoots`, the run id of
  `-Revalidate`, the second Windows account, and T-03, T-13, T-17 and T-18 of R-04.

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
| R-11 | Nit | Both | Probe files on POSIX, an uncaught `Add-Type` failure, uncapped relayed text, no run id. | Partly. The failure is unmeasured, relayed text is cut and cleaned, the probe files are documented; a run id is not bound. |

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
| S-18 | Nit | Docs | The README launcher recipe (`Environment.Clear()` and a `PSModulePath` of system folders) does not do what it says: pwsh adds the account's own module folder first. | Fixed in the README, after reproducing it. The module path is closed only where the verifier measures it (the three firewall cmdlets); adding the folders pwsh searches to the escape set of `WritableRoots` is a follow-up. |
| S-19 | Nit | Docs | "Cannot make a record that was not stored read as stored" has an exception: a server that replays the earlier acknowledgement of a record identical to one already stored. | Fixed in the README: the exception and what the client cannot prove (how many times the record was stored). The reviewer's hardening, `sequence == head before send + 1`, needs the client to read the chain before it sends, and is not done. |
| S-20 | Nit | Both | Two service-side `[Console]::Error.WriteLine` lines print raw exception text; the S-04 and S-05 appender tests are Windows-only although three of the functions are platform-neutral; `..` in the program word is normalized textually. | The `..` item is fixed with S-17. The first is not changed: no client text reaches those lines (`Test-RecordSchema` returns canonicalization errors to the client inside a `try`, and `Add-Record` runs only after it passed), so there is nothing to provoke in a test; part C accepted that as a Nit and still recommends routing both lines through `Format-RefusalText`. The second is a follow-up, because Ubuntu and macOS cannot be run here. |

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
  set of `WritableRoots` is a follow-up.
- A process of the service's own account can take or join the pipe name and make
  an append fail (S-09). An open handle on the chain head stops the service by
  design, and a silent connection holds it for as long as it stays open.
- `-Revalidate` does not bind the ledger to a run id, and the chain is not keyed,
  so whoever can write the sink and the head can write a chain that validates.
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
  sends and is not done.
- Two service-side `[Console]::Error.WriteLine` lines print raw exception text
  (S-20). No client text reaches them, which was traced and not provoked; routing
  both through `Format-RefusalText` is a follow-up, and so is gating the S-04 and
  S-05 appender tests, which are Windows-only although three of the functions are
  platform-neutral.
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
E-08, E-09, E-15, and E-16 stay open. The kit is a seatbelt against accidents and
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
| E-08 | Minor | Leak checks | Advisories (an e-mail, a token, a hex id, a path) are computed and dropped by every caller, and a provenance digest goes out on the judge path. | Open. What to block is the owner's decision. |
| E-09 | Minor | Backend check | The guard encodes ShellPilot 0.4.0's resolution order, but the scripts accept a later module by name, and a session function of the same name shadows it. | Open. Which versions to accept is the owner's decision. |
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
6. Optionally close E-15 and E-16, bind the calibration command's cache path,
   refuse a comparison without a freeze, and switch script tracing and strict
   mode off in the shadow block.

### Remaining risks

- E-08, E-09, E-15, and E-16 stay open until the owner rules on or closes them.
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
