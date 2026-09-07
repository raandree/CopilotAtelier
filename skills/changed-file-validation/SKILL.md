---
name: changed-file-validation
description: >-
  Runs an opt-in, bounded validation pass over the files one work batch changed.
  Collects project-scoped paths manually, deduplicates them per session, and
  checks each supported file once: PowerShell parsing and PSScriptAnalyzer in an
  owned, time-bounded worker process, and markdown through a real markdownlint
  plus a partial four-rule native structure check. A receipt names the plan
  identity, each validator with its version and config, and the SHA-256 of the
  exact bytes read, so changed content, a changed plan, or a tampered receipt
  cannot inherit a pass. Missing tools, oversized input, and timeouts stay
  unavailable and unverified.
  USE FOR: validate the files changed in this batch, collect changed paths for a
  later check, read or revalidate a receipt, see what is still unverified.
  DO NOT USE FOR: replacing immediate tests or the full build gate, formatting
  files, whole-project linting after every edit, deployment health checks,
  debugging a failing build (use sampler-build-debug).
compatibility: >-
  Windows PowerShell 5.1 or PowerShell 7 or later. PSScriptAnalyzer is optional
  and reported as unavailable when absent. Markdown lint coverage needs an
  already-installed markdownlint-cli executable; nothing is downloaded or
  installed and no network call is made.
---

# Changed-file validation

Check the files a batch of work actually touched, and say exactly what was
checked and against which bytes.

## Outcome

One project holds a batch of collected paths under
`.copilot-atelier/changed-file-validation/`. Running validation turns each
supported entry into a receipt. A reader can then answer three questions that a
green build log cannot: which files were checked, with which tool at which
version and configuration, and whether the content on disk is still the content
that passed.

## Activation

Nothing here activates itself. There is no hook, no watcher, and no background
process, and no lifecycle event triggers collection.

**Why no hook.** The client's documented hook events are `SessionStart`,
`UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PreCompact`, `SubagentStart`,
`SubagentStop`, and `Stop`. `PostToolUse` is the only plausible collector, and
its payload contract for edit tools is not verified for this implementation, so
wiring it would mean guessing at a field name. Worse, the shipped hooks are
mandatory: `PreToolUse` blocks remote mutation and `Stop` closes the session
clock. An optional collector inside either one turns a validation fault into a
guard fault, and a `Stop` hook that can fail is a route to an unattended retry
loop. Collection therefore stays a command the user or the agent runs on
purpose. Should the `PostToolUse` input contract ever be verified, a collector
belongs in its own hook file, never inside a mandatory one.

Scripts live beside this file under `scripts/` and are also deployed to
`$HOME/.copilot/skills/changed-file-validation/scripts/`.

```powershell
$validation = "$HOME/.copilot/skills/changed-file-validation/scripts"
```

## Manual use

### 1. Collect what changed

```powershell
& "$validation/Add-ChangedFile.ps1" -Path $PWD.Path -ChangedPath @(
    'source/Public/Get-Thing.ps1'
    'README.md'
)
```

Repeat it after every edit. Adding the same file again increments an occurrence
count rather than creating a second entry, so a batch stays one entry per file.
Absolute paths, backslash paths, and forward-slash paths normalize onto the same
entry.

Use `-SessionId` to keep two pieces of work apart:

```powershell
& "$validation/Add-ChangedFile.ps1" -Path $PWD.Path -ChangedPath 'source/A.ps1' -SessionId 'feature-a'
```

### 2. Validate the batch

```powershell
& "$validation/Invoke-ChangedFileValidation.ps1" -Path $PWD.Path |
    Format-Table RelativePath, Action, ValidationState, Outcome
```

Each supported, present file is checked once per unchanged batch. A second run
reports `Reused` and starts no validator, but only while the content *and* the
validation plan are unchanged; `-Force` revalidates regardless. One validation
run executes per session at a time.

### 3. Read the standing of the batch

```powershell
& "$validation/Get-ChangedFileBatch.ps1" -Path $PWD.Path |
    Format-Table RelativePath, FileState, ValidationState, Verified
```

The report re-hashes every file as it runs and writes nothing.

### 4. Clear it when the work is done

```powershell
& "$validation/Clear-ChangedFileBatch.ps1" -Path $PWD.Path
```

## Supported file types

| Extension | Validators |
|---|---|
| `.ps1`, `.psm1`, `.psd1` | `PowerShell.Parse` (AST), `PowerShell.ScriptAnalyzer` |
| `.md` | `Markdown.NativeStructure`, `Markdown.Lint` |
| anything else | none — the entry is recorded as `Unsupported` and is never verified |

`PowerShell.ScriptAnalyzer` records `Error` and `Warning` findings and fails on
`Error` by default. `-FailOnSeverity Warning` makes warnings fail as well, and
changing it changes the validation plan, so an earlier receipt no longer counts.

### What the markdown checks do and do not cover

`Markdown.NativeStructure` runs in process and enforces four rules: MD047,
`CFV001` unterminated frontmatter, `CFV002` unterminated code fence, and
`CFV003` invalid UTF-8 or a stray control character. It is recorded with
`coverage=partial` and it is **not** a markdownlint substitute. A
`.markdownlint.jsonc` that disables individual rules without setting
`default: false` leaves every other markdownlint rule enabled, and none of those
is implemented here.

`Markdown.Lint` is therefore always part of the plan for a markdown file, and it
runs a real markdownlint or reports itself unavailable. A markdown entry is
`Verified` only when a linter actually ran and passed.

```powershell
& "$validation/Invoke-ChangedFileValidation.ps1" -Path $PWD.Path `
    -MarkdownLintPath 'markdownlint' -MarkdownLintInterface 'markdownlint-cli'
```

| Situation | `Markdown.Lint` reason |
|---|---|
| `-MarkdownLintPath` not supplied | `LinterNotConfigured` |
| the executable cannot be resolved | `ExecutableNotFound` |
| an interface this implementation has not verified | `UnsupportedInterface` |
| a `.js`, `.cjs`, `.mjs`, or `markdownlint-cli2` configuration is near the file | `ExecutableConfigurationPresent` |
| the parsed configuration names a dynamic include, a custom rule, or a module path at any depth | `ExecutableConfigurationPresent` |
| the configuration format has no trusted non-executing parser here | `ConfigurationFormatUnsupported` |
| the configuration does not parse | `ConfigurationUnreadable` |
| the configuration is not a plain rule map | `ConfigurationShapeUnsupported` |
| no declarative configuration exists at the project root | `NoDeclarativeConfiguration` |
| `--version` does not answer with a version | `InterfaceNotVerified` |

Nothing is downloaded, installed, or discovered implicitly, and no network call
is made. `markdownlint-cli2` is reported as unsupported rather than driven
through an interface that has not been implemented and tested here.

## Diagnostics

Every entry reports a `ValidationState` and a `ValidationReason`:

| State | Meaning |
|---|---|
| `Pending` | Collected, not validated yet |
| `Verified` | Every planned check passed against the bytes currently on disk |
| `Failed` | A check reported a defect |
| `Stale` | The file changed after the receipt was written, or moved during the run |
| `PlanChanged` | The checks the file is now due differ from the ones the receipt records |
| `Incomplete` | A tool was unavailable, timed out, refused the input, or the receipt is unusable |
| `Missing` | The collected path no longer exists |
| `Unsupported` | No validator covers this file type |

`Verified` is true only for `Verified`. Every other state, including
`Incomplete` and `PlanChanged`, is unverified.

Each check carries `Validator`, `Executable`, `Version`, `ConfigIdentity`,
`Outcome`, `Reason`, `ExitStatus`, `DiagnosticCount`, `Truncated`, and up to 20
`Diagnostics` with `Line`, `Column`, `Severity`, `RuleId`, and `Message`.

```powershell
$batch = & "$validation/Get-ChangedFileBatch.ps1" -Path $PWD.Path
$batch.Checks.Diagnostics | Format-Table Line, Column, RuleId, Message
```

## What this is not

- **Not a substitute for the tests you owe.** A behavior change still needs its
  own failing-then-passing test, and a shared or persistence change still needs
  the full `./build.ps1 -Tasks build, test` gate. A batch check is a cheap
  supplement that runs between them, never instead of them.
- **Not a build system.** It compiles nothing, resolves no dependency, installs
  nothing, and reaches no network.
- **Not a formatter.** It writes to the batch store and to nothing else. No file
  it validates and no file it was not given is ever rewritten.
- **Not a deployment health check.** `Test-CopilotAtelier` runs no validator
  from here, and none of this runs during install, update, or uninstall.
- **Not proof about content you are reading now.** A receipt is a claim about
  one exact byte sequence. Edit the file and the claim expires immediately.

## What a receipt claims

A receipt is a claim about one exact byte sequence checked under one exact
plan. It records `contentSha256`, `planIdentity`, and every check with its
validator, executable identity, version, and configuration identity.

The **validation plan identity** is a SHA-256 over the checks the file is due,
resolved from static facts only: the extension, `-FailOnSeverity`, the installed
PSScriptAnalyzer version, the SHA-256 of the linter entry point, the bytes of
the declarative markdown configuration, and the SHA-256 of the shipped code that
performs each check. Nothing is executed to resolve it, so
`Get-ChangedFileBatch.ps1` applies exactly the same rule as the validator
without starting a process.

That identity is deliberately bounded, and it is worth knowing where it stops.
It covers the files this skill ships and the linter's own entry point. It does
not reach PSScriptAnalyzer's rule implementations beyond their module version,
and it does not reach the dependency tree under an npm wrapper: a few hundred
bytes of shim are hashed, the packages they load are not, because no supported
interface exposes them to a process-free read.

A receipt is reused, and reported `Verified`, only when all of this holds:

- the shape is intact, the recorded hash is a well-formed SHA-256, every check
  carries the fields and the result values this implementation writes, and
  `contentChangedDuringValidation` is a Boolean by type rather than by coercion;
- the hash matches the bytes on disk right now;
- `contentChangedDuringValidation` is false, even if the bytes match again;
- `planIdentity` equals the plan the file is due now;
- the recorded checks are exactly the planned ones, each present once, with no
  duplicate and no check the plan never asked for;
- every check matches the executable, configuration identity, and expected
  version the plan names;
- every check's exit status agrees with its result: a pass is zero, a failure is
  not, and neither may be missing;
- the recorded outcome is exactly what those checks add up to.

Anything else fails closed, and a result this implementation cannot produce is
treated as unavailable rather than counted towards a pass. Changing
`-FailOnSeverity`, selecting a linter, upgrading one, replacing one in place,
upgrading PSScriptAnalyzer, editing the checker itself, editing
`.markdownlint.jsonc`, and hand-editing the store all invalidate reuse instead
of inheriting a pass.

## Bounds and trust boundary

Validators read the file through an isolated snapshot: the bytes are copied into
a generated directory under a generated, metacharacter-free name, and that copy
is what is hashed and checked. The receipt is therefore bound to the byte
sequence a validator actually read rather than to a path that may have moved
underneath it, and every argument handed to an external tool is a name this
workflow generated. A hostile file name, a glob, or a shell metacharacter in the
project never reaches a command line — which matters on Windows, where a
markdownlint entry point is a `.cmd` shim the command processor re-parses.

Parsing and static analysis run in an owned child worker started with an
explicit argument vector, given its request over standard input, and killed with
its descendants when it outruns the bound. Nothing dot-sources, imports, or runs
the file being checked, and PSScriptAnalyzer is given an inline settings
hashtable, so no project `PSScriptAnalyzerSettings.psd1` and no custom rule
module is ever loaded.

External output is drained and capped while the child is still running, not read
to end afterwards. A child that fails to start, one that outruns the bound, and
one whose descendants hold the pipe open past the drain grace are reported as
unavailable, timed out, or incomplete, with the exit status left null when it is
genuinely unknown. None of them can produce a pass.

| Bound | Default | Control |
|---|---|---|
| Files per batch | 500 | fixed |
| Files per run | 200 | `-MaxFileCount` |
| Input size, checked before any read or hash | 2048 KB | `-MaxFileKilobyte` |
| Validator child wall clock | 60 s | `-TimeoutSecond` |
| Output drain grace after a child exits | 5 s | fixed |
| Retained output per stream | 20000 characters | fixed |
| Concurrent child processes | 1 | fixed |
| Validation runs per session | 1 | fixed; `-ExecutionWaitSecond` bounds the wait |
| Diagnostics per check | 20 | fixed |

Path containment is enforced by walking every existing directory from the
selected project root down to the file, before every read and every write, so a
junction or symbolic link on an intermediate directory cannot redirect the run
outside the project. The guard runs again at validation time, because a batch
collected minutes ago may have gained a link since. A traversal segment, a drive
qualifier, and a leading separator are all refused. A session identifier is
letters, digits, period, underscore, and hyphen only, so it can never name a
path.

Only a declarative markdown lint configuration is honoured, and only after it
has been read by a parser rather than scanned as text: a byte scan is not a
boundary, because JSON can spell `extends` with Unicode escapes. JSON and JSONC
are parsed by a non-executing reader and then checked against a conservative
rule-map schema, so a dynamic include, a custom rule, a module path at any
depth, an unknown key, and an unexpected shape are all refused before the
version probe or the linter starts. A format with no trusted parser here -
YAML, and JSONC on a host without a comment-tolerant JSON reader, which
includes Windows PowerShell 5.1 - is reported `ConfigurationFormatUnsupported`
rather than copied to an executable unread. What survives is passed explicitly,
which is also what disables the linter's own nested and ancestor discovery.

## Store

| Path | Purpose |
|---|---|
| `.copilot-atelier/changed-file-validation/batches.json` | Schema 1 store, scoped to one project root |
| `.copilot-atelier/changed-file-validation/.batches.lock` | Bounded mutation lock, empty and safe to delete when idle |
| `.copilot-atelier/changed-file-validation/.execution-<session>.lock` | Session execution lock, empty and safe to delete when idle |
| `.copilot-atelier/changed-file-validation/snapshot/<id>/` | The bytes one validator run reads, removed as soon as the run ends |

The store is replaced atomically under the lock, and a collector that finds the
lock held waits inside the bound and merges rather than failing, so two sessions
collecting at the same time cannot lose an entry. A store recording another
project root, an unsupported schema version, or unparsable JSON is refused
rather than partially read.

Add `.copilot-atelier/` to `.gitignore`; a batch is local working state.
