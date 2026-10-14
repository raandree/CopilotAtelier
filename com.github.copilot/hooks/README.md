# Hooks

Deterministic guardrails that run at fixed points in the agent loop. Unlike an
Instruction, a hook does not depend on the model choosing to obey it: VS Code
executes the command and honours its exit code.

Setup deploys this folder to the Canonical target and links it to
`~/.copilot/hooks`. Hook discovery and event behavior are client-specific;
verify loading in the client being used rather than assuming cross-client parity.

## Launchers

Every entry in `hooks.json` carries three launchers. VS Code runs `windows` on
Windows and `command` elsewhere; it reads `powershell` only when `windows` is
missing. The Copilot SDK host has no `windows` key: its own format knows
`bash`, `powershell`, `exec`, and a cross-platform `command`, and explicit
`bash` or `powershell` entries take precedence on their platforms
([hooks configuration reference](https://docs.github.com/en/copilot/reference/hooks-configuration)).
It therefore runs `powershell` on Windows and `command` elsewhere, and the cloud
agent, which honours only `bash`, falls back to `command`. All three launchers
start their script the same way apart from the interpreter — `pwsh`, or
`powershell` for `windows` — and none may depend on `HOME`, which Windows does
not define. `windows` and `powershell` also end with one statement of their
own, explained below.

Each launcher runs the first of these scripts that exists:

1. `<PLUGIN_ROOT>/com.github.copilot/hooks/scripts/<Script>.ps1`
2. `<USERPROFILE>/.copilot/hooks/scripts/<Script>.ps1`
3. `<HOME>/.copilot/hooks/scripts/<Script>.ps1`
4. `.copilot/hooks/scripts/<Script>.ps1` under the profile folder the operating
   system reports, for a host that passes a stripped environment

`USERPROFILE` comes before `HOME`. Windows always defines `USERPROFILE`, while
`HOME` there is whatever a tool such as Git for Windows set, and a `HOME` that
points at a writable tree would otherwise run a planted script instead of the
deployed one. A `HOME` that does not answer, such as an unreachable UNC path, is
then never probed while `USERPROFILE` holds the script. Probing one took longer
than the 20-second hook timeout, and the Copilot SDK host allows a call whose
hook times out. On Linux and macOS `USERPROFILE` is unset, so `HOME` applies.

An unset root becomes an unresolvable `*` and a relative root is anchored at the
filesystem root, so no candidate ever resolves against the working directory.
When no candidate exists or the script cannot start, the launcher names the
script and the underlying error on standard error and exits `2` for
`PreToolUse`, which blocks, and `1` for the lifecycle events, which warns.
`command` and `powershell` need `pwsh` on `PATH`.

The launcher passes the script's exit code through unchanged, but on Windows
both hosts run it inside an outer PowerShell, which reports any failed native
command as `1`:

| Host | Spawn on Windows | Source |
|---|---|---|
| VS Code Local harness | `powershell.exe -ExecutionPolicy Bypass -NoProfile -NoLogo -Command <windows>` | `HookExecutor` in VS Code's built-in `extensions/copilot/dist/extension.js` |
| Copilot SDK host | `pwsh.exe -nop -nol -c <launcher>`, started by `copilot-runtime.exe` | process captures of `command` (2026-10-02) and `powershell` (2026-10-04) |

VS Code blocks only on `2` and treats every other non-zero exit as a warning,
and the SDK host shows the block reason only on `2`, so `windows` and
`powershell` end with
`; exit (@(Get-Variable -Name LASTEXITCODE -ValueOnly -ErrorAction Ignore) + 2)[0]`
(`+ 1` for the lifecycle events). The outer PowerShell runs it and exits with the
inner code, or with the launcher's own failure code when the inner interpreter
never started. Under `cmd.exe` the statement only reaches the inner `-Command`
after a `try` block that always exits, so when the inner interpreter cannot
start at all, a `cmd.exe` spawn reports `1`, while both PowerShell spawns report
the launcher's failure code. `command` cannot carry it, because `sh`
runs `command` on Linux and macOS and rejects the statement; that is why the SDK
host gets its own `powershell` launcher. It runs that launcher the same way,
passing the text on unexpanded.

## Contents

| File | Event | Purpose |
|---|---|---|
| [`hooks.json`](hooks.json) | — | Hook configuration loaded by VS Code and the Copilot SDK host |
| [`scripts/Block-RemoteMutation.ps1`](scripts/Block-RemoteMutation.ps1) | `PreToolUse` | Blocks remote-mutating and irreversible commands; a Remote grant lets the user's own prompt authorize one |
| [`scripts/Add-RemoteGrant.ps1`](scripts/Add-RemoteGrant.ps1) | `UserPromptSubmit` | Records a Remote grant when the user's own prompt carries a Grant marker |
| [`scripts/Add-SessionContext.ps1`](scripts/Add-SessionContext.ps1) | `SessionStart` | Probes for the Memory Bank, injects the UTC timestamp, starts the session clock and names it in the reader command |
| [`scripts/Write-SessionClose.ps1`](scripts/Write-SessionClose.ps1) | `Stop` | Advances the session clock's turn counter |
| [`scripts/Get-SessionElapsed.ps1`](scripts/Get-SessionElapsed.ps1) | — | Agent-run reader that prints the Post-flight elapsed line of the clock it is given |
| [`scripts/Write-CompactionCheckpoint.ps1`](scripts/Write-CompactionCheckpoint.ps1) | `PreCompact` | Anchors the session on disk before context is truncated, and counts the compaction for contributor calibration |
| [`scripts/Add-FamiliarityContext.ps1`](scripts/Add-FamiliarityContext.ps1) | `PostToolUse` | Re-sends saved familiarity levels after a compaction and, where no `PreCompact` runs, within one turn; registered only by `~/.copilot/hooks/contributor-profile.json` |
| [`scripts/Test-RunContainment.ps1`](scripts/Test-RunContainment.ps1) | — | Measures the containment controls `/complete-specifications` requires, and revalidates its sealed ledger |
| [`scripts/Invoke-LedgerAppender.ps1`](scripts/Invoke-LedgerAppender.ps1) | — | Append-only hash-chained evidence ledger for the same workflow |

## Containment for /complete-specifications

The last two scripts are not VS Code hooks. They are the external verifier and
the pinned ledger appender that the specification completion controller names in
its containment profile, and they live here because this folder already deploys
to a stable path outside every target repository.

That deployed copy is the source for an install, not the control a profile pins.
The account that installs Copilot Atelier can write `~/.copilot/hooks/scripts`,
and the verifier measures whether the identity that runs it can replace or
loosen the profile and every pinned control, so pin copies installed where no
run identity can write.

Decision 0025 records that the package *specifies* the operating-system boundary
without deploying it. These two scripts close part of that gap and deliberately
leave the rest open:

- `Test-RunContainment.ps1` **measures** a boundary. It never creates or repairs
  one. On an ordinary workstation it fails, and that failure is the correct
  answer.
- `Invoke-LedgerAppender.ps1` **stores** evidence so tampering is detectable by
  anyone who does not also control the sink and the chain head. The chain is not
  signed, so it cannot stop an identity that can write both; keeping them outside
  that identity's reach is filesystem policy.

Separate controller and worker identities, an outbound policy that is enabled on
every firewall profile, defaults to Block, and grants no outbound allow rule that
could apply to the run identity, and a filesystem policy that closes the ledger
to the run are still deployment work.

### Containment profile

The profile is non-secret structured data. Every path is absolute, with no dot
segment and no Windows short name, and on Windows no device or extended-length
prefix and no stream name, because each of those is another spelling of a file
that a comparison of text cannot see. Every digest is lowercase 64-hex. Unknown
fields, wildcards, a `schemaVersion` other than the integer `1`, and non-empty
egress lists are refused. Field names are compared exactly, so a name spelled in
another case, or with an invisible character in it, is an unknown field and does
not stand in for the field it imitates. Credential material is not a profile field: it is
measured on the machine, and any that is reachable fails the run.

| Field | Meaning |
|---|---|
| `schemaVersion` | The integer `1`; any other value, and any other type, is refused |
| `verifier`, `hooksConfig`, `hookScript`, `ledgerAppender` | Pinned control, each `{ path, sha256 }`. The verifier that runs must be the pinned file |
| `ledgerSink`, `chainHead` | Ledger paths, which must be closed to the run |
| `controllerEgressAllow`, `workerEgressAllow` | Must both be empty |
| `controllerIdentity`, `workerIdentity` | The account, by name or SID, the verifier must run as for each role; the two must differ |
| `immutableControlPaths` | Further paths that must be closed to the run; the profile, the four pinned controls, and every live artifact are always measured |
| `writableRoots` | The roots the run may write; each must be a directory the run identity can add files and folders to |
| `liveProfile`, `liveRunner`, `liveCommandTemplates` | Required only when live mode is enabled |

`hooksConfig` pins the `hooks.json` of the plugin copy a host loads, which is
`<root>/com.github.copilot/hooks/hooks.json` for the root of `hookScript`; a
byte-identical file anywhere else is not the file a host reads, and is refused.
It registers the remote-mutation guard and nothing else: one `PreToolUse` entry
of type `command`, with no matcher, an integer `timeout`, and the same command
under every key a host reads. That command starts with the absolute path of its
interpreter, because a bare name is looked up in the working directory of the
host and then in PATH, and the interpreter must be closed to the run identity.
The interpreter must be PowerShell, a program named `powershell` or `pwsh`: the
verifier reads what PowerShell loads before its command and cannot read what
another program loads (`cmd.exe` runs the `AutoRun` commands of the registry of
the identity that starts it unless it is given `/d`), so any other program is
refused, a renamed copy of PowerShell and a preview build included.
The shipped file registers more, for the human workflow: session context, the
session clock, and the hook that records a Remote grant from a Grant marker on
the prompt event, whose prompt text in a contained run includes specification
and issue content that is not the operator's own. It also names its interpreter
as `powershell` and `pwsh`. The verifier refuses it for a contained run, so a
contained deployment pins a copy of its own. `hookScript` must sit at
`<root>/com.github.copilot/hooks/scripts/Block-RemoteMutation.ps1`, the layout
the hook command resolves it from, and the pinned command must take its script
from `PLUGIN_ROOT` before any other place, as the shipped command does. The
verifier proves that with a decoy tree and fails a command that does not.

### What each check says

The verifier reports each check as `Pass`, `Fail`, or `Unavailable`, and an
`Unavailable` check fails the run exactly like a `Fail`. A control that was not
measured was not verified: a locked file, a read-only attribute, a missing path,
a firewall profile whose state cannot be read, a canary endpoint that timed out
or was unreachable, a probe that could not be validated, a git that cannot be
resolved to a file the run cannot replace, and a git child that crashed or
printed nothing are all reported as unmeasured, never as protected or clean.

A check that runs a program as this identity, which is the hook command, git and,
in `-Revalidate`, the pinned appender, runs only after the controls it executes
were measured and passed, so a writable or swapped control is never run. Every
other check always runs, and a run that stops at the profile reports each check
as not run instead of leaving it out.

| Check | A Pass says | It does not say |
|---|---|---|
| `ProfileDigest`, `ProfileSchema` | The profile hashes to the digest argument, compared as typed, and satisfies the closed schema | |
| `VerifierBinding` | The verifier that runs is the file the profile pins, by path and digest | |
| `ControlDigest` | Each pinned control hashes to its pinned digest | |
| `ControlImmutability` | This identity cannot replace or loosen the profile, a pinned control, a live artifact, or an immutable path: not by writing it, deleting it, changing its access list or owner, creating it, or through a directory above it or a reparse point, and none lies in or holds a writable root | What an identity other than the one that runs can do. A directory entry is judged as one object, its own rights and those above it, not the rights of what it holds. What the token of this identity holds beyond what the probes show: a disabled privilege and a filtered administrator group are not read (see below). Off Windows only write access is measured |
| `IdentityBinding` | The verifier runs as the account the profile declares for the role, and the two roles differ. The pinned hook command, git and, in `-Revalidate`, the pinned appender run only when this passes, because the immutability above is measured for the identity that verifies | That the account is a standard one: its token is not read (see below) |
| `HookContract` | The pinned `hooks.json` is the plugin's own at the root of the pinned script and registers only the guard. Its one `PreToolUse` entry carries no key but `type`, an integer `timeout` and the command keys (`timeoutSec`, `env`, `cwd` and any other key fail the check, because a host may act on a key the check does not read), is of type `command` with no matcher, and holds the same command text under every command key. That command starts with the absolute path of PowerShell (a program named `powershell` or `pwsh`; this check reads what PowerShell loads first and cannot read what any other program loads, so any other program, `cmd.exe` included, is refused) that this identity cannot replace; has no line break and no `%` or `!`, which a shell expands before it reads the line; has no unquoted `&`, `\|`, `<`, `>`, `^`, `(` or `)` after its program; and has after an unquoted `;` only the statement the shipped command ends with (`exit (@(Get-Variable -Name LASTEXITCODE -ValueOnly -ErrorAction Ignore) + 2)[0]`). It passes `-NoProfile` before its script or command, and no option that loads code first: the same options as the verifier's own launch are allowed. Run from a folder of its own, with `PLUGIN_ROOT` set to the pinned root and the other places it looks emptied, within the timeout, it runs the pinned script, which exits 0, 2 and 2 for a safe, a push and an issue-mutation payload | What a host passes the hook in a real run, and how a host spawns the command. The probe runs the line through `cmd.exe /d /c` (`/d` keeps the `AutoRun` commands of the registry of the identity under test from running ahead of the probe); a host that wraps it in PowerShell, as VS Code does for the `windows` key, reads quoting and separators by that shell's rules, and PowerShell needs a leading `&` before a quoted program path, which this check does not accept, so how a contained deployment pins one command that passes this check and also runs under that wrapper is not settled here. The absolute interpreter path in the pinned command is what stops a host looking its interpreter up in its own working directory |
| `GrantRecorderUnregistered` | The pinned `hooks.json` is of a shape the check reads, registers no prompt hook, and does not contain the name `Add-RemoteGrant` anywhere in the file, at any depth, and the grants folder of this identity is empty | That no grant can exist: the guard honors any well-formed grant file in a folder the run owns, so a run that writes one is not stopped here, and egress and credentials are the boundary against a remote mutation. A recorder under another name (a renamed copy, a wildcard, a name built by an expansion) is not seen. A hook file the host finds outside the pinned file, such as a user-level or workspace hooks folder or an installed copy of the plugin |
| `EgressPolicy` | The three firewall cmdlets come from a module under the system folder, every firewall profile of the active store is enabled and defaults outbound to Block, and no enabled outbound allow rule could apply to this identity by its user condition | A system-wide proxy, and the program, service, port and address scoping of a rule. A host that reaches NetSecurity through the Windows PowerShell compatibility layer resolves it outside the system folder, so the check is unmeasured there until the module loads natively |
| `RemoteUnreachable` | The probe works against a loopback listener, and local policy denied the connection to both canary addresses | A network that is silent or down: a timeout is unmeasured, not closed |
| `CredentialAbsence` | None of the credential and git steering variables is set, `XDG_CONFIG_HOME` among them, and a git that is closed to the run reports no credential helper. git runs only after the checks that gate the hook command passed; otherwise it is not run, and the check is unmeasured. The git child gets the caller's environment without the `GIT_` variables, `SSH_ASKPASS` and `XDG_CONFIG_HOME`, with `HOME` and `USERPROFILE`, and on Windows `PROGRAMDATA`, pinned to the operating system's own folders. Evidence names variables and configuration keys, never their values | The files git itself loads from its own installation, and package feeds, browsers, web and GitHub tooling, and MCP servers, none of which this verifier measures |
| `WritableRoots` | Every declared root accepts new files and folders, and none of the escape set is writable outside them: the user profile, the temp folder, the temp folder of the operating system, the folder of the profile, and the folders of the ledger sink and chain head | The rest of the filesystem, which is not enumerated. Off Windows the write measurement creates and removes a short-lived probe file in each place it measures |
| `LedgerProtection` | This identity cannot replace or loosen the sink or the chain head, or a directory above them | The chain is not signed: whoever can write both files can write a chain that validates |
| `LiveArtifacts` | Live mode only: the live artifacts are pinned and match | |

An elevated administrator holds every right the immutability probes ask for, so
the verifier fails for one by design. Run it as the role identity, a standard
account. The probes ask the operating system with the token the verifier runs
with, and two things in a token are not read: a privilege that is held but
disabled (backup, restore, take ownership), and a filtered administrator token
whose Administrators group is deny-only. Neither shows as a right, so a run
identity that holds either is outside what a Pass says, and removing them from
the account is deployment work.

A verifier measures one identity and one network namespace: the one it runs in.
The controller therefore runs it once per role, `-Role Controller` and
`-Role Worker`, each as the account it measures.

It runs only as the entry script of a process of its own, and refuses a launch
that does not look like one: a function or a type defined earlier in a session
outranks the ones it measures with, so a call from inside another command, from
an interactive session, or from a script that was started for another purpose
could make every measurement read as it likes. It reads the command line: only
options that cannot change what runs first may come before `-File`
(`-NoProfile` is required; `-NonInteractive`, `-NoLogo`, `-ExecutionPolicy`,
`-WindowStyle`, `-WorkingDirectory`, `-MTA` and `-STA` are allowed, and an option
such as `-ConfigurationFile` or `-SettingsFile`, which loads code or a module
path first, is refused, as is any argument that is not an option). It also
reads the call stack, where the script must be the only frame: a `-Command` text
that merely carries `-File` and the script after it lists them on the command
line while its own code runs first, and has a deeper stack. The check calls no
command by name, because command lookup tries an alias before a function, and an
alias named like the check would otherwise make the call do nothing.

That reads the launch. It cannot see code that already runs inside the process
before its first line, such as a .NET startup hook named by `DOTNET_STARTUP_HOOKS`,
and the environment belongs to whatever starts the verifier: only a launcher that
builds it can close that. Start the verifier through
`System.Diagnostics.ProcessStartInfo` with an explicit environment
(`Environment.Clear()`, then only what it needs, and a `PSModulePath` of system
folders). `Start-Process -UseNewEnvironment` is not that: it clears what the
launching process inherited, and still hands the verifier the account's own user
environment and its own module folder, which for the worker role is the run's.
The firewall cmdlets are resolved by name, so `EgressPolicy` measures where they
come from and is unmeasured unless all three come from a module under the
system folder.

```powershell
$digest = (Get-FileHash -Algorithm SHA256 -LiteralPath $profilePath).Hash.ToLowerInvariant()
pwsh -NoProfile -NonInteractive -File $verifierPath -Verify -ProfilePath $profilePath -ProfileSha256 $digest -Role Controller
```

`$verifierPath` is the installed copy the profile pins as `verifier.path`.
Compute the digest yourself and pass it as a direct argument. It is the trust
anchor: a digest the run derives from the file it is about to trust proves
nothing. `-ReportPath` writes the structured result, and must be an absolute
path in a directory that already exists and not be, or lie inside, any file the
verdict depends on. A stream of such a file, a device or extended-length
spelling of it, and on Windows a path whose directory goes through a junction
or a symbolic link are refused as well, because each reaches the file under a
name the text does not show. A hard link in a writable folder to such a file, and a
UNC spelling that loops back to the same machine, are not recognized. They reach
the file under another name, but the report is written with the rights of the run
identity, and a passing `ControlImmutability` means that identity holds no write
right on any control, so the write is refused.

`-LiveMode` is `off` (the default), `read-only`, or `disposable`: the live
validation the caller intends to run. Anything but `off` adds the `LiveArtifacts`
check, which requires `liveProfile`, `liveRunner`, and `liveCommandTemplates` to
be pinned in the profile, each an existing file that matches its digest.

The exit code is 0 when every check passed, and 2 when a check failed or could
not be measured, or when the call is refused: there is no partial success. Any
other code, including 1 from an unhandled error, means the verifier itself failed
and nothing was verified.

### Revalidation

`-Revalidate` is the second use of the verifier, after a run. It runs the same
four gates, and the pinned appender only after they pass.

```powershell
pwsh -NoProfile -NonInteractive -File $verifierPath -Revalidate -ProfilePath $profilePath -ProfileSha256 $digest -Role Controller -FinalReportPath $report
```

| Check | A Pass says | It does not say |
|---|---|---|
| `VerifierBinding`, `ControlDigest`, `ControlImmutability`, `IdentityBinding` | As above | |
| `LedgerChain` | The pinned appender, run bound to the pinned profile, says the sink and the chain head form a valid chain from genesis and that the chain is sealed. The sink is read before and after the appender validates it, and the two reads must hash alike | That what was validated is what was read, against a writer that restores the same bytes between the two reads: `LedgerProtection` for this identity is what excludes a writer. And that the ledger belongs to this run: the verifier does not know a run id, so a sink that holds an earlier sealed run and its report revalidates, and the controller gives each run a sink of its own |
| `FinalReport` | The record directly before the `Seal` is a `FinalReport` record whose `data.sha256` is the digest of the report file, compared as written and in lowercase, the seal chains to it, and the seal is the head the appender validated | That the report says anything true |
| `LedgerProtection` | As above, measured again | |

What the pinned appender says, and the text of the ledger records the verifier
names, reach evidence that a model reads. They are cut to a short length, and
only printable ASCII is relayed: every other character, which includes control
and format characters, the Unicode tag block, variation selectors, fillers and
blanks, and a letter with an accent, becomes a question mark. A record cannot add
lines to the report, hide an instruction in text a person cannot see, or fill it.

### Ledger

The appender is the only writer of the sink and the protected chain head. It
serves one local named pipe, on Windows only. The pipe's access list grants the
appender's own account read and write and the right to create further
instances, grants `-AllowedIdentity` read and write when that names another
account, and denies the network identity. The appender is the pipe's owner, so
no caller can rewrite its security descriptor. Where the pipe cannot be
restricted and authenticated, `-Serve`, `-Append` and `-Seal` refuse. The service
holds the sink open for appending for as long as it runs, so a second appender
on the same ledger is refused.

Each record carries a monotonic sequence, its predecessor's digest, and its own
digest over a canonical serialization. A record is flushed to disk before the
append is acknowledged, so an acknowledged record survives a crash. The converse
does not hold: a crash, a lock or an I/O error between the sink flush and the
head write can leave a record that is stored and was never acknowledged. The
sequence is therefore spent when the record becomes durable, a head that cannot
be written stops the service, and a restart refuses to serve unless the head
names the last record or the one before it.

```powershell
# Service, under the pinned appender identity
Invoke-LedgerAppender.ps1 -Serve -PipeName ca-ledger-run1 -SinkPath $sink -ChainHeadPath $head

# Caller
Invoke-LedgerAppender.ps1 -Append -PipeName ca-ledger-run1 -RecordJson $record -SinkPath $sink -ChainHeadPath $head
Invoke-LedgerAppender.ps1 -Seal -PipeName ca-ledger-run1 -RecordJson $seal -SinkPath $sink -ChainHeadPath $head

# Bound to the profile, which is what the verifier uses
Invoke-LedgerAppender.ps1 -Validate -ProfilePath $profilePath -ProfileSha256 $digest -RequireSealed

# Operator form: proves only that these two files form a valid chain
Invoke-LedgerAppender.ps1 -Validate -SinkPath $sink -ChainHeadPath $head
```

The client authenticates the pipe's owner and access list before it sends the
record. It reports success only after it has rebuilt the digest of the record it
sent, at the acknowledged sequence and on top of the stored record before it, and
found that digest both in the acknowledgement and in the ledger at that
sequence: a server that merely answers `Ok` is not believed, and neither is one
that answers with the sequence and digest of a record that was already stored.
By default the client expects the pipe to belong to the account that would own
what the client creates, which is the right account when both run as one
identity. When the service runs as another account, as in a separate-account
deployment, name it with `-ExpectedServerIdentity` (an account name or a SID),
or the client refuses the real service. Sealing is the server's decision,
carried by the operation the client asks for and not by the type of the record,
and the type `Seal` is reserved for it. Every refusal is one line on standard
error beginning `Ledger appender refused:`, and the exit code is 0 for success
and 2 for a refusal, never a warning. The text after the prefix is cleaned like
the text the verifier relays: only printable ASCII, every other character one
question mark, cut at 200 characters, so a server or a record cannot add a line
to it or hide an instruction in it.

The bound form of `-Validate` takes the sink and the head from the profile's
`ledgerSink` and `chainHead`, requires `-ProfileSha256` to match the bytes it
parsed, and requires the running script to be the appender the profile pins. It
writes one JSON object to standard output and exits 0, or writes nothing there,
one line of reason to standard error, and exits 2. The unbound form reports
`"bound":false` and warns, because it proves only that two files form a chain.

```json
{"valid":true,"records":3,"headSequence":3,"sealed":true,"headRecordSha256":"<hex>","bound":true}
```

A record is exactly `type`, `runId`, `utc`, and `data`. Field names are
compared exactly, by code unit, and a repeated field is refused, so a field named
like a known one does not stand in for it. That is all the schema fixes: the
values of `type`, `runId` and `data` are free text that whoever can append
chooses, tag characters and instructions included, and whatever reads the ledger
must treat them as untrusted text. The ledger is evidence that a record was
written and has not changed, not that what it says is true or safe. `utc` must be
an ISO-8601 instant in UTC, with no fractional digits or one to nine, and a date
that exists (the thirtieth of February and the twenty-fourth hour are refused);
it is checked by parsing it, and it is stored exactly as given and never
rewritten. `data` must be a JSON object, and every number in it must be a JSON
integer within ±(2^53−1): a fraction, an exponent or a wider integer is refused
at append time rather than stored in a form that reads back as another value.

The stored line is the canonical serialization of the record plus `sequence`,
`prevSha256` and `recordSha256`, with the keys in ordinal order, no whitespace,
no byte-order mark and a single `\n`; `recordSha256` is the SHA-256 of the same
text without `recordSha256`. Validation recomputes the chain from genesis over
the stored bytes. A stored line must be byte-for-byte the canonical
serialization of what it parses to and must carry exactly those seven fields,
so a rewritten body, a removed, added or reordered line, an extra or duplicate
field, inserted whitespace, an uppercase digest, a byte-order mark, a blank or
junk line and a half-written final record all fail. The chain head must name the
last record, and its sealed flag must agree with the chain.

A run that finishes appends a `FinalReport` record whose `data.sha256` is the
lowercase SHA-256 of `final-report.md` directly before it seals the ledger, and
`-Revalidate` holds the sealed ledger to that.

The chain is not keyed. A caller that can write the sink and the head can write
a chain that validates; keeping both out of the reach of the run identity is
filesystem policy. A process of the service's own account can still take the
pipe name before the service starts, or join it: it can make an append fail, but
it cannot make a record that was not stored read as stored, because the client
rebuilds the digest of its own record and looks for it in the ledger. Separate
accounts and `-ExpectedServerIdentity` are what tell such a process from the
service.

Two availability limits remain, and neither changes what the ledger says. Any
open handle on the chain head, even one opened with sharing, makes the service's
replace of the head fail, and a head that cannot be written stops the service by
design. And the service reads one request at a time with no deadline for a
connection, so a client that connects and says nothing holds it for as long as it
keeps the connection.

## Block-RemoteMutation

Inspects any tool input that carries executable command text — `command`,
`commandLine`, `cmd`, `script`, `args`, or `arguments`, at any nesting depth —
rather than deciding from the tool name, so an executor whose name contains no
shell keyword is still covered. It blocks a command that pushes to a git remote,
passes `--no-verify`, runs `git reset --hard`, force-cleans untracked files
(a `-n` dry run is allowed), mutates a pull request, issue, release, repository,
workflow, secret, or cache through the GitHub CLI, or calls `gh api` with a
mutating method or a GraphQL mutation. Shell line continuations are folded first
so a split command cannot hide the subcommand.

A command that only mentions a blocked operation in a string literal is not an
invocation, so it is allowed. When the command text parses as PowerShell and
holds no indirect execution, the guard reads the syntax tree and blanks a string
only when everything the string flows into treats it as data:

- an argument of `Write-Output`, `echo`, `Write-Host`, `Select-String`, or another
  `Write-*` cmdlet, when nothing later in the pipeline can run it and the
  pipeline's output is not captured (not part of an assignment, a parenthesis, a
  sub-expression, or an argument, and not stored by `-OutVariable`,
  `-ErrorVariable`, `-WarningVariable`, `-InformationVariable`, or
  `-PipelineVariable` on that cmdlet or one after it);
- an argument of `Set-Content`, `Add-Content`, `Out-File`, or `New-Item`, on the
  same terms, **and only when the file it writes is known**: a literal path that
  names no drive or provider (a list of literals too), or a variable whose every
  assignment is such a literal. Those cmdlets also write to the `Function:` and
  `Alias:` drives, where a string becomes a command that the same command then
  runs, and a file that something runs by itself holds code, not data: anything
  inside `.git`, `.githooks`, `.husky`, `.ssh`, or `.vscode` (its settings, launch,
  and task files and `mcp.json` start programs), a `.code-workspace` file, a
  PowerShell profile (`profile.ps1`, `Microsoft.PowerShell_profile.ps1`), a shell
  start-up file (`.bashrc`, `.bash_profile`, `.bash_aliases`, `.zshrc`, `.zshenv`,
  `.zlogout`, `.profile`, `.envrc`, `.gitconfig`, `config.fish`, a fish
  `conf.d/*.fish`), or a file in a `Startup` folder. A folder counts as well as a
  file in it, because `-Path` and `-Name` together form the path and neither half
  matches alone. A path is compared as the file system resolves it: a drive
  qualifier is removed (`C:.git\hooks` is `.git\hooks`), Windows drops the dots
  and spaces that end a name, and `file::$DATA` and `file:stream` are `file`. A
  wildcard (`*`, `?`, `[`) or a Windows short name (`PROGRA~1`) stands for files
  the text does not name, so such a path is unknown, and a note about a push
  written to `report[1].md` or `C:\PROGRA~1\…` is denied: use the edit tool for
  it. So a path the guard cannot read, or one that names such a place, is not
  trusted. A path
  built with `+`,
  `-f`, or `-join`, taken from `Join-Path`, started with `$env:TEMP`, or held in
  a variable that a loop, a parameter, `[ref]`, or a parameter that stores output
  in a variable (`-OutVariable`, `-Variable`, and any prefix of them, down to
  `-o` or `-v`) can change is unknown, and so is any relative path after a move
  of the location to a place the text does not spell out: a `Set-Location`
  (also written `-Path:(…)`, `cd -`, or `cd +`) with a computed or drive-qualified
  destination, or a `Pop-Location` without a `Push-Location` in the same text.
  PowerShell binds a parameter by name, by alias, or by any unambiguous prefix of
  either, so the guard reads those four cmdlets' parameters from a closed table
  of every name and alias in Windows PowerShell 5.1 and PowerShell 7, which a
  test compares with the cmdlets themselves: a spelling outside the table, an
  ambiguous prefix, or a splatted argument list leaves the file unknown. Name the
  file with a literal (`Set-Content -LiteralPath msg.txt …`) to keep a commit
  message out of the scan;
- the `-m`, `-am`, and `--message` values of `git commit` and `git tag`, with the
  expressions inside a `--message="…$(…)…"` value kept visible, because they run;
- the text arguments of `[System.IO.File]::WriteAllText` and its three sibling
  writers; their first argument is the file, and it must pass the same test as the
  path of `Set-Content`, or the text is scanned;
- a pipeline source that feeds only data-writing cmdlets;
- a literal assigned to a plain variable, when **every use of that variable** is
  one of the above. `$msg = '…gh pr create…'; git commit -m $msg` and
  `$text | Set-Content f` qualify; `schtasks /tr $x`, a member call, an
  expression, a splat, a copy into another variable, or any program the guard
  does not know do not. A variable that is read by name (`Get-Variable`,
  `$ExecutionContext.SessionState`, the `Variable:` drive) disqualifies every
  assigned literal.

A commit message built in a here-string that quotes `gh pr create` therefore
commits without a block. A string that holds a backtick is blanked only when it
is single-quoted, a here-string included: PowerShell reads a backtick in a
double-quoted or bare string as an escape, a POSIX shell reads it as a command
substitution, and the guard cannot tell which shell runs the text. So
``git commit -m 'see `git push` docs'`` commits, and
``git commit -m "see `git push` docs"`` counts as a push: single-quote the
message or leave the backticks out. Anything else is scanned as written, and so
is the whole command when it holds:

- indirect execution: `Invoke-Expression` or `iex`, `Invoke-Command`, a computed
  command name such as `& $name`, `Start-Process` and its aliases, `Start-Job`,
  `Invoke-Item`, a cast to a script block, `pwsh` or `powershell` with
  `-Command` or `-EncodedCommand`, `cmd /c`, `bash -c`, `node -e`, `python -c`,
  and the like, and `wsl`;
- a definition that changes what a name means: `Set-Alias`, `New-Alias`, `sal`,
  `nal`, `New-PSDrive`, a function named like one of the cmdlets above, or any
  use of the `Alias:` or `Function:` drives, such as `$function:deploy = '…'`,
  `Set-Item function:echo …`, or `Set-Content -Path function:deploy …`.

A path or an extension names a different program, so `.\echo.ps1`,
`C:\tools\write-output.cmd`, `.\git.ps1`, and `git.cmd` get no benefit of the doubt.
`Start-Process` for `git` or `gh` is read as the command line it launches; with
arguments the guard cannot read, the call is blocked and no marker lifts it.
Text that does not parse, including a `&&` under Windows PowerShell 5.1, a
command over 64 KB, or a syntax tree over 20,000 nodes, is scanned as written.
So is a string handed to any other program, such as `somecommand 'git push'`:
only the cases above count as data, and everything else errs toward blocking.
The stop-parsing token `--%` counts as an option, so `git --% push origin main`
is a push.

Each git rule anchors on the subcommand position, so a branch name, commit
message, or `--grep` value that merely contains the word does not trip it. A
tool with no command-bearing field exits `0` immediately, so editing a document
that mentions `git push` is never blocked. The reason goes to standard error and
the script exits with `2`, which VS Code treats as a blocking error and shows to
the model; on exit `2` VS Code does not read standard output. The Copilot SDK
host does not read standard error then: it merges one JSON object from standard
output into the deny, so the guard also prints the reason there, as top-level
`permissionDecision` and `permissionDecisionReason` only. The object must not
carry `hookSpecificOutput`. For a PascalCase event such as `PreToolUse`, the
SDK runtime in VS Code 1.140.0 (1.0.15-preview.4) drops an object that does,
and the model reads only `Denied by preToolUse hook: hook exited with code 2`,
as it did until 2026-10-04; it also shows only that for an object with nothing
but `hookSpecificOutput`, for plain text, and for standard error alone.
[`tests/HookSdkRuntime.Tests.ps1`](../../tests/HookSdkRuntime.Tests.ps1) runs
the guard inside that runtime and checks what the model reads. The
command-bearing fields are walked up to 64 levels deep and 20,000 fields and
nested objects, in a payload of up to 1 MB; plain values in arrays, such as a
file list, do not count. Their values are joined in document order and, within
each object, executables before arguments. So
`{"args":["push"],"command":"git"}`, the order a serializer that sorts its keys
writes, still reads as `git push`, while one entry's executable never pairs
with another entry's arguments. When the walk cannot cover a payload,
because it is nested deeper, larger, holds more fields or objects, or is not
valid JSON,
its raw text is also scanned: as written, with JSON escapes decoded, and
without the JSON punctuation, so an argument array such as `["git","push"]`
reads as the command it is. The command-bearing fields are also pulled out of
it and joined the way the walk joins them, so a command split across fields,
such as `{"command":"git","args":["push"]}`, reads as one line too. There they
are also joined across the whole payload, executables first and in reverse,
because a brace in raw text cannot show reliably where an object ends; like the
rest of this path, that errs toward blocking and can pair one entry's
executable with another entry's arguments. A blocked
command found there blocks the call. That path errs toward blocking: a payload
that only mentions a blocked command, such as a document in an unreadable
payload, is blocked too. A text with neither `git` nor `gh` in it is skipped,
because every pattern needs one of them.
Otherwise a payload that is not valid JSON is
allowed with a warning on standard error and exit `0`: the Copilot SDK host
denies a `preToolUse` call on every other non-zero exit, so a payload schema
change would otherwise block every tool call. The whole decision has a time
limit of five seconds, a quarter of the hook timeout, and the walk may use half
of it. Parsing and walking cannot be interrupted, and some patterns slow down
quadratically on one long line of `git` words, so a payload the guard has not
inspected within the limit is blocked rather than left to the timeout, which
would let it through. A payload over 4 MB is blocked without being scanned; no
model writes a tool call that large. A payload over 1 MB that names git on most
lines, such as a large document about git, can still run out of time and be
blocked: JSON escaping puts its whole text on one raw line, where some patterns
slow down quadratically. Under PowerShell 7, which the Copilot SDK host runs
on Windows, a batch of more than about 16,000 command entries, such as
`{"command":"ls","args":["x"]}`, also runs out of time: 32,000 of them
(0.9 MB) are blocked after 5.4 seconds, while Windows PowerShell, which VS Code
runs, allows 64,000 in 2.5 seconds. So the same oversized tool call can pass in
one host and be blocked in the other. Write such a file in parts, or run the
command yourself.

The syntax-tree analysis of a command text runs on the same clock. It stops at
the walk's half of the limit, and the text is then scanned as written: every
operation in it is found, none of it is hidden, and no marker can lift the block,
because the guard did not read the command completely. An analysis that ran
past the hook timeout would be an allow, so none may: 32 KB of one path
variable assigned and written to again and again once took 21 seconds. Where
the limit falls depends on how fast the machine is, so whether a command of
about 60 KB can be granted at all can differ between a cold and a warm run; it
is blocked either way.

### Authorizing a remote mutation

The house rules allow a push, a pull request, and the other blocked remote
mutations when the user asks for them in the current turn. The user authorizes
one without leaving the chat: a Grant marker in their own prompt creates a
Remote grant. An agent cannot write the user's prompt, so it cannot authorize
itself.

```text
Push the branch and open the pull request. [[allow-remote: git push, gh pr create]]
```

- The marker is plain text, `[[allow-remote: <operation>, <operation>]]`, on one
  line and in any case. A marker inside an inline code span or a fenced code
  block is ignored, so a prompt that quotes this page grants nothing.
- Each operation runs once. A trailing `x2` allows it twice, up to 20:
  `[[allow-remote: gh pr create x2]]`. Naming an operation more than once adds
  the counts, so `gh pr create x3, gh pr create x2` allows five, at most 20.
- The operations are `git push`; `git push --force`, which a push with
  `--force`, `--force-with-lease`, `--force-if-includes`, `--delete`,
  `--mirror`, `--prune`, `--all` or its alias `--branches`, `--tags`, any
  unambiguous abbreviation of those long options (git reads `--del` as
  `--delete`), a short option cluster holding `f` or `d`, or a `+ref` or `:ref`
  refspec needs instead, quoted or not; `gh pr` with `create`,
  `merge`, `close`, `comment`, `review`, `edit`, `ready`, or `reopen`;
  `gh issue` with `create`, `close`, `comment`, `edit`, or `reopen`;
  `gh release` with `create`, `delete`, `edit`, or `upload`; `gh repo` with
  `create`, `delete`, `archive`, `rename`, or `edit`; `gh workflow` with `run`,
  `enable`, or `disable`; `gh secret` with `set` or `delete`; `gh cache delete`;
  and `gh api` for a mutating call. Any other phrase is ignored, and so is one
  with a zero-width character or a soft hyphen inside it.
- The guard counts the operations it reads, not the times they run. Code that
  can run an operation more than once therefore asks for every use a marker can
  grant: `[[allow-remote: git push x20]]`. It then spends all of them. That is
  a loop (`foreach`, `for`, `while`, `until`, `do`, `switch` over values, cmd's
  `for /l` and `for %i in (…) do`, a shell `while`, `until`, or `for … do`), a
  pipeline into `ForEach-Object`, `foreach`, `where`, `%`, or `?`, the
  `.ForEach()`, `.Where()`, and `.Invoke()` methods, `xargs`, `-exec`, `watch`,
  `retry`, or `repeat` (also behind `npx`, `sudo`, `doas`, `nohup`, `exec`, `time`,
  `command`, `env`, `setsid`, `timeout`, `stdbuf`, `nice`, `ionice`, or `winpty`
  with up to three words of their own, by a path, or named in quotes behind the
  call operator), `watchexec`, `nodemon`, `entr`, `fswatch`, or
  `inotifywait`, a scheduler or an event handler (`schtasks`, `crontab`,
  `Register-ScheduledTask`, `Register-ObjectEvent`,
  `Register-PSSessionConfiguration`, and their relatives such as
  `Register-ClusteredScheduledTask`), and, in a text that parses, any
  code that is written once and can run any number of times: a script block
  that is a value or an argument
  (`Sort-Object { … }`, `Register-ObjectEvent -Action { … }`, even `& { … }`), a
  function, a class, a `trap`, `. $block` or `& $name`, `Invoke-Expression` or a
  nested shell given a variable, a member that builds code, and inline Python
  or Node code. A text that does not parse, such as a `&&` under Windows
  PowerShell 5.1, counts every brace. Only code counts: a loop or a function
  quoted in a pull request body or a commit message is text, and a quoted
  string never asks for 20 uses. The guard judges the whole command, not the
  statement next to the operation, so `git push 2>&1 | ForEach-Object { "$_" }`
  asks for 20 uses as well. The block message says so; running the operation as
  its own command asks for one. Calling a program through a variable counts too:
  `$gh = 'C:\Program Files\GitHub CLI\gh.exe'; & $gh pr create …` asks for 20,
  while the quoted literal path, `& 'C:\Program Files\GitHub CLI\gh.exe' pr create …`,
  asks for one.
- The grant belongs to the session that received the prompt. It ends with the
  user's next prompt, after 15 minutes at the latest, or when its uses run out.
  A later marker replaces it, so a prompt lists everything its commands need.
- `git reset --hard`, `git clean -f`, and `--no-verify` are never lifted. The
  user runs those in their own terminal.
- The guard prints nothing when a grant covers a command, so the host's own
  approval still applies. Under Allow all or `chat.tools.global.autoApprove` the
  marker is the authorization and no second prompt appears; in Manual mode the
  user still confirms the terminal command.
- A grant covers an operation, not one command: the first matching command the
  agent runs while the grant lasts uses it.

A blocked call tells the agent the exact marker to ask the user for. Without a
marker the agent hands the user the command as a fenced code block for their own
terminal and does not retry it. It never puts the command in a question dialog,
which shows the question as one joined paragraph with no code block and no copy
button.

`COPILOT_ATELIER_ALLOW_REMOTE` is gone. It was read from the environment a host
starts the hook with, so an agent could never set it for one command, and a
value set for the host turned the guard off for every chat of that instance.
The guard ignores it now; never persist it, for example with `setx`.

The grant was accepted live on 2026-10-13 in four new chats against a throwaway
repository with a local bare remote: the Copilot Agent Host, VS Code Local,
Copilot CLI 1.0.96 started as usual, and the same CLI under `--yolo`. Without a
marker the hook denied the push. With `[[allow-remote: git push]]` the push ran
once, and the next push without a marker was denied again (in the CLI's usual
start the agent declined it before the hook saw it). Auto-approval
(`chat.tools.global.autoApprove`, `COPILOT_ALLOW_ALL=1`, `--yolo`) did not lift
the block.

#### Why a prompt marker and not an `ask`

A hook can answer `ask` and let the host show an approval prompt, but that is
not safe in every harness. Live probes on 2026-10-12, with
`chat.tools.global.autoApprove` on:

| Harness | What a hook `ask` did |
|---|---|
| Copilot Agent Host (VS Code 1.141.0) | No prompt. The runtime raised `permission.requested` with `kind: hook` and the same second recorded `approved` with `decisionSource: host_policy`; the commands ran. Allow all and `chat.tools.global.autoApprove` approve every permission kind, `kind: hook` included |
| VS Code Local (Copilot Chat 0.69.0) | A prompt, and it survives `chat.tools.global.autoApprove`. A Skip reaches the agent only as "the user chose to skip the tool call", without the hook's reason |
| Copilot CLI 1.0.96 | A prompt (`kind: hook`), shown although the user environment sets `COPILOT_ALLOW_ALL=1`. A reject reaches the agent as `Denied by user via preToolUse hook prompt: <reason>`. Not tested under `--yolo` with an `ask` |

A hook cannot see the approval mode ([copilot-sdk#2810](https://github.com/github/copilot-sdk/issues/2810)
asks for it), so a guard that asked would run every guarded command unprompted
in the Agent Host for a user who has auto-approval on. A hook `allow` approves
the call in VS Code Local too ([vscode#339589](https://github.com/microsoft/vscode/issues/339589)),
so the guard never prints `allow` either: it blocks, or it exits `0` with
nothing on standard output. [Decision 0016](../../.memory-bank/decisions/0016-enforce-house-rules-with-hooks.md)
holds the evidence.

#### Residual risks

- A grant is a file under the user's profile. An agent that can write there and
  knows its session id, which the session clock path discloses, can forge a
  grant for itself. A Remote grant prevents accidents; it is not a containment
  boundary. Keep these scripts and the grants folder out of the agent's
  auto-approved edit scope (`chat.tools.edits.autoApprove`).
- A variable that holds a force option or a refspec is not resolved, so a
  `git push` grant also covers `git push $flag` and
  `$r = ':old-branch'; git push origin $r`. `git push origin $branch` therefore
  stays a one-use push.
- An interpreter outside the list in [Block-RemoteMutation](#block-remotemutation)
  can run text the guard never sees.
- PowerShell drops a backtick in a word (`` pu`sh `` is `push`, `` --f`orce `` is
  `--force`), and the guard removes backticks from the text it scans. Other
  escape characters inside a command word, such as `g^it` in cmd or `g\it` in a
  POSIX shell, are not undone. A path that reaches a listed file through a
  symlink or a junction is judged by its text, not by where it leads.
- PowerShell and a POSIX shell can disagree about where a quote ends, after a
  backslash before a quote or inside a here-string that holds an apostrophe. The
  guard reads the text as PowerShell, so a string it reads as data can be code to
  a POSIX shell that runs the same text. That needs an unusual command, such as
  one written to exploit the difference; ordinary commands read the same way in
  both.
- A command over 64 KB is scanned as raw text.
- Writing a script and running it in one command is not caught: a string that
  only flows into `Set-Content` or `Out-File` is data, whatever the file is used
  for later. A heuristic for it would reopen the false positive that a command
  writing a commit-message file and running a script has always had. Only the
  files named under [Block-RemoteMutation](#block-remotemutation) (what git, a
  shell, or the system runs by itself) are refused as a place to write data; a
  script file anywhere else is not. The same holds for a
  location, an alias, or a drive left over from an earlier call.
- Code that reads from a file, a script, an alias, a git hook, or a program the
  guard does not know cannot be counted, whatever it does with an operation
  written in the command.
- An alias or a function defined in an earlier call of a persistent terminal
  stays defined, so `echo 'git push …'` can run it later. The guard sees one
  command at a time. The same class was already open for a variable or alias
  standing in for a subcommand.
- A marker anywhere in what you submit counts, including text you pasted. Do not
  paste untrusted content into a prompt that asks for a remote operation.
- A marker authorizes what the user typed, and the guard cannot tell which push
  the user meant. Name the operations narrowly, and use `x2` rather than a long
  grant when two are needed.

## Add-RemoteGrant

Runs at `UserPromptSubmit`, before the turn's first tool call. It reads the
payload's `session_id` and `prompt`, nothing else, and writes the Remote grant
the [Grant marker](#authorizing-a-remote-mutation) asks for. Every path exits
`0` and prints nothing: exit `2` would block the user's prompt in VS Code, whose
Local harness reads only the common output for this event, and a grant that
cannot be written simply leaves the guard blocking. Its launcher exits `1` on a
failure, which warns, like the other non-blocking events.

- It removes the session's earlier grant first, so a grant ends with the next
  prompt even when that prompt carries no marker.
- The grant is `grant-<session key>.json` in `CopilotAtelier/grants` under the
  per-user application data folder (`%LOCALAPPDATA%` on Windows), written to a
  temporary file and moved into place. It holds `schema`, `sessionKey`,
  `issuedAt` and `expiresAt` in Unix seconds, `promptSha256`, and `operations`
  with the uses left. The session key is the `session_id` itself when it is
  already a safe file name in lower case (`a-z0-9_-`, at most 64 characters, as
  every host's GUID is), and otherwise `h-` and the SHA-256 of the id, so two
  different ids never share a file, not even on a file system that ignores case.
  The guard derives it the same way. A payload with no
  `session_id`, or one without a single usable character, gets no grant.
- Files older than a day are removed. Delete a file to revoke its grant.
- The guard consumes a grant under an exclusive open, all of an operation's uses
  or none, and deletes the file when they run out. It accepts only schema 1, its
  own session key, a lifetime of one to 3,600 seconds that has not ended and
  did not begin more than two minutes ahead, known operations, and whole counts
  from 0 to 20; anything else is no grant.
- The grantable operations are listed in both scripts. They must stay identical,
  and a test compares them.

## Add-SessionContext

Resolves the session working directory from the hook payload, probes for
`.memory-bank/index.md`, and returns an authoritative statement of whether a
Memory Bank exists, plus the current UTC timestamp. This removes the recurring
failure where an agent concludes "no Memory Bank" from the workspace summary,
which omits dotfile folders.

It also starts the session clock described below, and hands the agent the
command that reads it: `& '<reader>' -Path '<clock>'`, the absolute paths of
`Get-SessionElapsed.ps1` and of the clock this hook wrote or resumed. The agent
cannot resolve the reader itself — the script sits under `~/.copilot` when
deployed and under the plugin root when installed as a plugin, which is the probe
`hooks.json` already carries. The `-Path` is what keeps the measurement on this
chat's own clock: without it the reader has to choose one, and a parallel chat in
the same workspace can make it choose that chat's (Prox1, 2026-10-08: a chat
closed with the duration of its parallel chat). A hook that wrote or resumed no
clock hands over the reader alone. Both paths are quoted for PowerShell, and an
apostrophe or a typographic single quote in either is doubled, because
PowerShell ends a single-quoted string at all of them.

A resumed session keeps its clock. The Copilot SDK runtime reruns the hook with
`source: resume` when it reloads a chat; when a readable clock of that session
exists, the hook leaves it untouched, injects its original start time, and names
it in the command. Restarting it there reset the elapsed line and the turn count.

The context goes into one JSON object twice, under the key each host reads: a
top-level `additionalContext` for the Copilot SDK host and Copilot CLI, and
`hookSpecificOutput.additionalContext` for the VS Code Local harness. Each host
ignores the other's key, so dropping either one silently removes the context
from that host's sessions.

The JSON is pure ASCII: the hook writes every other character as `\uXXXX`.
Windows PowerShell 5.1 encodes standard output in the console's OEM code page,
and that encoding's best fit turns characters such as U+201C, U+02BC, and U+2032
into a bare ASCII quote. In the workspace path that would break the JSON and let
the rest of a folder name become context; in a quoted path it would end the
string early, after the quoting had done its work. ASCII reads the same in every
code page and in UTF-8, so the context does not depend on how the host decodes
it.

When the workspace declares Knowledge areas under `## Knowledge areas` in
`.memory-bank/projectbrief.md`, one more sentence follows with the
contributor's saved familiarity levels for them, read from the private
Contributor profile of the [`contributor-profile`](../../skills/contributor-profile/SKILL.md)
Skill. It is data only, built from a fixed template, the matched area names,
and the level values; an alias, a path, or an unmatched name never appears in
it. Without a declaration the hook neither reads the profile nor runs git.

### Session context budget

Injected context defaults to a 4096-character limit. Set
`COPILOT_ATELIER_SESSION_CONTEXT_MAX_CHARS` to an integer from 1024 through
16384 to change it; invalid values use the default. Oversized paths are omitted
before any lifecycle guidance, and the clock still runs. This is a character
budget for one hook, not a token count or a live context-window estimate. The
contributor-profile sentence has the lowest priority: it gets only what the
other lines leave, giving up its unrated count, then trailing areas, then
itself, and never shortens another line.

Over the limit, the hook first shortens the Memory Bank line, which carries the
workspace path. If that is not enough it shortens the closing line, which drops
the reader path because that is the path that outgrew the budget, and keeps
`-Path` while the context then fits. Only when it still does not fit does the
closing line lose `-Path` too, and the agent falls back to the reader's own
choice of clock.

There is no master-off profile: all shipped hooks serve lifecycle or safety
obligations. The context budget never disables remote-mutation checks, and no
environment variable turns the guard off: `COPILOT_ATELIER_ALLOW_REMOTE` is
gone. A remote mutation you authorize with a Grant marker runs from the chat
(see [Authorizing a remote mutation](#authorizing-a-remote-mutation)); without
one, run the command in your own terminal.

## The session clock

Post-flight closes every reply with the elapsed duration of the chat. A model has
no clock: a duration it composes is a guess, and after a compaction it no longer
knows when the session began. So the number is measured on disk and read back.

Three pieces share one clock file:

| Field | Written by | Meaning |
|---|---|---|
| `startedUtc` | `SessionStart` | Round-trip timestamp the duration is measured from |
| `workspace` | `SessionStart` | Working directory the session was opened in |
| `turns` | `Stop` | Turns closed so far in this session |
| `lastTurnEndedUtc` | `Stop` | End of the most recent turn |

It lives at `<LocalApplicationData>/CopilotAtelier/sessions/session-<key>.json` —
`%LOCALAPPDATA%` on Windows, `~/.local/share` on Linux, `~/Library/Application
Support` on macOS. Not the temp directory: `/tmp` is world-writable, and a
predictable name there invites another local account to pre-create the path. The
`<key>` is the payload's `session_id` with every character outside
`[A-Za-z0-9._-]` stripped, so none can traverse a directory. The match is
case-sensitive: a case-insensitive one lets U+0130 and U+212A through. When the
payload names no session, the key is a hash of the working directory instead, so
two concurrent windows do not share one clock. Where the host supplies no
session id, two chats of one workspace still share that one clock, and no
`-Path` can tell them apart.

Beside each clock sits `session-<key>.familiarity.json`, the calibration state
of the same session: `compactions`, which `PreCompact` advances; `injected`,
which `Add-FamiliarityContext` records; and `lastTurn`, `lastInjectionUtc`, and
`characters`, which `SessionStart` seeds when it injects levels and
`Add-FamiliarityContext` advances with each re-send. Every writer keeps all five
fields. No calibration hook ever rewrites the clock file, and
`Get-SessionElapsed` never reads the state as a clock.

### Write-SessionClose

The `Stop` hook advances `turns` and records `lastTurnEndedUtc`. It reports
nothing on the happy path. It used to append the duration itself, but VS Code
renders a hook `systemMessage` as a detached, collapsed warning box rather than
part of the reply, so the line the user actually wanted in the checklist was
never in it. Moving the measurement to the agent put it there; leaving the hook
line in as well would only have added a second copy on every turn.

It still speaks up when the clock cannot be read, because that is the one case
where the agent's own line could not be measured either:

```text
POST-FLIGHT clock - no readable session clock, so the elapsed line reads unavailable.
```

The hook emits no `decision` field. Blocking a `Stop` restarts the agent and
bills another turn, which is far too much to pay for a timestamp. Every failure
path still exits `0`.

A `Stop` that fires while `stop_hook_active` is `true` closes a turn some other
blocking hook already resumed, so it does not advance the turn counter.

### Get-SessionElapsed

Not a hook — the agent runs it as the last action of a turn, which is why it
reports plain text rather than the hook JSON contract. It prints one line, meant
to be copied verbatim as the last line of the reply:

```text
POST-FLIGHT elapsed: 16m (started 09:15 UTC, measured 09:31 UTC, turn 3)
```

Read-only: `Stop` owns `turns`, so the reader reports the turn in progress as one
past the closed count and writes nothing back. The command in the session context
hands it the clock to read with `-Path`. Given no `-Path`, or one that names no
file, it chooses a clock in this order, which is what survives a compaction that
dropped the injected command:

1. The clock whose key is `COPILOT_AGENT_SESSION_ID`, when the host sets it and
   that clock exists. The agent host's terminal carries its chat's id in it, and
   that id is the key of the chat's own clock. The value is stripped to the same
   `[A-Za-z0-9._-]` characters and 64-character cap as a payload's `session_id`,
   so it cannot name a file outside the clock directory. This clock comes before
   a newer one of the same workspace, which a parallel chat may have written.
2. The newest clock recorded for the current workspace, a `session-<id>` clock
   before a `session-cwd-<hash>` one.
3. The newest clock overall.

A named clock that exists but cannot be read reports `unavailable` instead of
falling through to another chat's clock, which would read as this chat's. An
unreadable clock yields `POST-FLIGHT elapsed: unavailable (no session clock on
disk).` and exit `0`.

## Write-CompactionCheckpoint

Post-flight is an end-of-turn gate, so a long turn that is compacted mid-run
never reaches it and everything the run learned goes with the conversation. This
hook writes `.memory-bank/session/compaction-<UTC>Z.md` before the truncation,
recording the trigger, the transcript path, and the branch, commit, and changed
paths at that moment, followed by a resume protocol.

It writes nothing when the workspace has no Memory Bank — creating one is
reserved for a durable repository write under the `memory-bank` Skill — and
nothing when the payload names no workspace, because falling back to the spawn
directory would drop a checkpoint into an unrelated repository. Every failure
path still exits `0`, so a hook fault never blocks compaction.

`PreCompact` supports the common output format only: there is no
`additionalContext` field, so a hook cannot inject text into the post-compaction
context. The user-visible half is `systemMessage`; the model-facing half is the
compaction-recovery section of
[`rules/preflight.instructions.md`](../rules/preflight.instructions.md),
which survives because Instructions are re-sent with every request.

It also advances `compactions` in the calibration state beside the session
clock, in every workspace, under the lock that `Add-FamiliarityContext` takes.

## Add-FamiliarityContext

No host reruns `SessionStart` after a compaction, and the Copilot SDK host and
Copilot CLI drop its context when they compact, so saved familiarity levels
would silently revert to `familiar`. This `PostToolUse` hook re-sends them on
the first successful tool call after a compaction that `PreCompact` counted.

VS Code Local runs no `PreCompact` for a manual or a background compaction, so
the hook also re-sends the levels as a backstop: on the first successful tool
call after a turn closes, or more than 5 minutes after the last injection once
the first turn has closed. Only a session whose `SessionStart` injected levels
is armed for it. Backstop re-sends stop once the session has received 12,000
characters of calibration text, about 3,000 tokens; compaction re-sends continue
up to 60,000, above which the session is outside the design's envelope and
nothing more is sent.

`hooks.json` does not register it. The `contributor-profile` Skill writes
`~/.copilot/hooks/contributor-profile.json`, a fixed template with the same
three launchers, while an entry on this machine is on and rates a Knowledge
area, and removes it when none does. Only machines with an active profile pay
the per-call cost, about one more hook launch per successful tool call,
slightly less than the push guard: 0.8 to 2 s, depending on the machine and
the host (Decision record 0028 has the measurements).
Hosts load hook files when a session starts, so a change affects later sessions;
an open chat keeps calling the script, which then finds nothing to send.

The re-send has limits that the design reports and does not gate. A plugin-only
installation has no `~/.copilot/hooks` folder, so no registration can exist and
nothing is re-sent after a compaction, although `SessionStart` still reads the
profile from LocalApplicationData. A reply that makes no tool call before the
next turn receives nothing either, and Claude Code gets the portable Skill only.
`tests/HookSdkRuntime.Tests.ps1` measures the plugin-only and the no-tool-call
cells in the runtime that VS Code bundles and in the standalone Copilot CLI.

The writers own the registration through a record beside the profile that
holds the file's SHA-256, whichever template wrote it, and replace one from an
earlier template with the current template at the next write, so a launcher fix
reaches each machine then. They never touch a file without a record or one that
no longer matches it. On a OneDrive Canonical target the record and the file
sync in either order; a record whose file has not arrived is pending, and
nothing, including `Uninstall-CopilotAtelier`, acts on it until both are there.

Latency is stated in frozen references: a hook's own time over a fixed no-op
hook, divided by the own time of a frozen reference, all three through the same
launcher and spawn, so machine speed and shell edition cancel. The reference,
[`tests/Fixtures/ReferenceHook`](../../tests/Fixtures/ReferenceHook), runs one
fixed calibration with a frozen copy of the profile reader, the same kind of
work as the calibration step itself.
[`tests/Fixtures/Measure-CalibrationLatency.ps1`](../../tests/Fixtures/Measure-CalibrationLatency.ps1)
measures it, and a test pins one SHA-256 over every file of the reference. A
change to a launcher in `hooks.json` or to any file of the reference changes the
measurement, so re-run the Meter and re-baseline Decision record 0028's latency
levels then.

The common path reads `session_id` from the head of the payload, where both
hosts put it ahead of every tool field, one small state file and, in an armed
session, the turn count of the session clock, then exits without writing or
locking anything. When a re-send is due, it parses the payload for `cwd` and
rechecks the profile so an opt-out takes effect at once. It then takes the
state lock, reads the state again, decides again, and records the injection
before it emits the matched levels under both host keys, so a re-send that
could not be recorded is never sent and cannot repeat on every later call. A
compaction re-send ends with
`Re-sent after a compaction; make no offers in this session.` and a backstop
re-send with `Current familiarity levels; make no offers in this session.` It
records the answered compaction count by compare-and-set, so a newer
compaction is never lost. It never emits `decision`, never exits `2`, and
exits `0` on every path.

## Verifying the hooks load

1. Run `Developer: Show Agent Debug Logs` from the Command Palette.
2. Look for `Load Hooks` and confirm `~/.copilot/hooks` is listed.
3. Open the Output panel and select the `GitHub Copilot Chat Hooks` channel to
   read hook output and errors.

### Reading hook evidence

These are Windows observations from 2026-10-08, not a cross-version guarantee.
Use the host's logs, not a model's account of its own context: a compaction
summary can preserve injected text by chance, and a request for exactly one
tool call produced three in Copilot CLI 1.0.92.

#### VS Code Local: VS Code 1.141.0, bundled Copilot Chat 0.69.0

- The Hooks output channel is persisted at
  `%APPDATA%\Code\logs\<yyyyMMddTHHmmss>\window<N>\exthost\GitHub.copilot-chat\GitHub Copilot Chat Hooks.log`.
  Lines have `<time> [info] [#<n>] [<Event>] <verb> ...`; group by `[#<n>]`.
  `Input` carries `session_id`, `cwd`, and `tool_name`; `Output` is the exact
  returned JSON. `Completed (Success) in <n>ms, no output` means nothing was
  returned, not that context was injected.
- The neighboring `GitHub Copilot Chat.log` records compaction through
  `[ConversationHistorySummarizer]` and a `summarizeConversationHistory-full`
  request.
- Each hook input's `transcript_path` identifies
  `%APPDATA%\Code\User\workspaceStorage\<hash>\GitHub.copilot-chat\transcripts\<session_id>.jsonl`.
  It contains user/assistant messages and tool calls, but not tool results.
- In Copilot Chat 0.68.0 and 0.69.0, neither `/compact` nor background
  compaction ran PreCompact in VS Code Local; the checkpoint hook therefore
  wrote nothing there. Do not infer a checkpoint from a compaction entry.

#### Copilot SDK agent host and Copilot CLI 1.0.92

Observed with VS Code 1.141.0 and Copilot CLI 1.0.92 on 2026-10-08:

- `~\.copilot\session-state\<session id>\events.jsonl` records `hook.start`
  and `hook.end` with `hookType` and `output`; that output is exactly what the
  host injected. `session.compaction_start` carries its `trigger`.
- The neighboring `workspace.yaml` names `client_name`: `vscode-agent-host`
  or `github/cli`. Use it to distinguish otherwise similar event streams.
- Copilot CLI starts `sessionStart` at the first prompt, not process launch;
  those were 33 seconds apart in one observed session.
- `/compact` ran neither Stop nor `agentStop` in either host, so the session
  clock's `turns` does not count it. Copilot CLI ran PreCompact with
  `trigger: manual`; VS Code Local did not, as scoped above.

#### Inspecting host versions and hook-written files

In the VS Code 1.141.0 observation, Copilot Chat ships inside VS Code at
`<VS Code install folder>\<commit>\resources\app\extensions\copilot`.
Its `package.json` names the version; `dist\extension.js` is the source to
check when release documentation is silent, for example by searching for
`executePreCompactHook`.

Read a hook-written file, such as a session clock, with `FileShare.ReadWrite`
and `FileShare.Delete`, using a read-only handle so inspection cannot block
the hook's atomic replace. Never write the file to inspect or repair evidence.

## Troubleshooting

- **Hook never fires.** Confirm `hooks.json` is present under
  `~/.copilot/hooks` and that the link resolves. Re-run
  [`Setup-CopilotSettings.ps1`](../../Setup-CopilotSettings.ps1).
- **A workspace `.github/hooks/*.json` never fires.** `chat.hookFilesLocations`
  replaces the default location map rather than extending it. A settings value
  of `{ "~/.copilot/hooks": true }` therefore drops `.github/hooks`, and the
  workspace file loads silently as nothing — no error, no log entry. Add
  `".github/hooks": true` alongside the existing entry, or place the hook in
  `~/.copilot/hooks`. Verified by observing a `Stop` hook that executed only
  after the file moved to the deployed folder.
- **Command not found.** A hook command tries the four literal locations listed
  under [Launchers](#launchers) and never scans an agent-plugin wildcard. When
  none exists it writes `CopilotAtelier hook <Script>.ps1 failed: could not
  resolve the script …`; when the script itself fails, the same prefix carries
  the underlying error instead. A missing `PreToolUse` guard exits `2` and
  blocks; missing lifecycle scripts exit `1` so they warn without trapping the
  agent loop. If you deploy the scripts elsewhere, replace the resolver in
  `hooks.json` with one absolute path.
- **Every tool call is denied with `(hook errored)` in a Copilot SDK session.**
  The SDK host runs `command`, so that branch has to resolve on Windows without
  `HOME` and needs `pwsh` on `PATH`. Launchers from releases before this fix
  looked only at `PLUGIN_ROOT` and `HOME` there and failed closed on every call.
  Redeploy, then start a new session.
- **A Copilot SDK session never receives the SessionStart context.** The
  session's `events.jsonl` shows the `sessionStart` hook ending with
  `success: true`, yet no `Session started at` text reaches the model. The SDK
  host reads only a top-level `additionalContext` and ignores
  `hookSpecificOutput`, the only key the VS Code Local harness reads. Releases
  before this fix wrote only the nested key. Redeploy, then start a new session.
  That `hook.end` event's `output.additionalContext` shows exactly what the host
  injected, and the field is absent when nothing was.
- **A `PreToolUse` block reaches the host as exit `1`.** On Windows both hosts
  run the launcher inside an outer PowerShell `-Command` (see Launchers). That
  outer PowerShell reports only whether its last command succeeded, so exit `2`
  arrives as `1`.
  - The Copilot SDK host fails closed on every non-zero `preToolUse` exit. The
    call is still denied, but as `Denied by preToolUse hook (hook errored)`
    without the reason. Since 2026-10-02 the SDK host runs the `powershell`
    launcher, which hands the code on, and since 2026-10-04 the deny carries
    the reason: `Denied by preToolUse hook: Blocked by Copilot Atelier: …`. A
    deny that reads `Denied by preToolUse hook: hook exited with code 2` comes
    from an older guard, whose JSON on standard output also carried
    `hookSpecificOutput` (see [Block-RemoteMutation](#block-remotemutation));
    redeploy. The launcher reads the guard on every call, so even an open
    session shows the reason from its next call. A session started before the
    2026-10-02 deploy keeps the old hooks and still shows `hook errored`.
  - VS Code blocks only on `2`, so in Local chats on Windows the guard only
    warned until 2026-10-02. The `windows` launcher now ends with an `exit` that
    hands the inner code on.
  - A bare trailing `exit` would not work: it exits `0` and would allow the call.
  - `command` cannot carry the statement, because `sh` runs it too.
- **The hook dies with a PowerShell parser error.** VS Code hands the command to
  a PowerShell shell, which expands the double-quoted `-Command` argument before
  the child process parses it. A `$` token is therefore consumed by the outer
  shell and reaches the child as an empty string — `$b = if ($env:PLUGIN_ROOT)`
  arrives as `= if ()` and fails with `An expression was expected after '('`.
  Every shipped command is written without a single `$`: paths come from
  `[Environment]::GetEnvironmentVariable(...)`, the blocking exit code from
  `Get-Variable -Name LASTEXITCODE -ValueOnly`, and the reported error from
  `Get-Variable -Name _ -ValueOnly`. `cmd.exe` and `sh` parse the same text, so
  it also carries no backtick, inner double quote, or `%`. Keep it that way, or
  the hook silently stops guarding anything.
- **Timeout.** These hooks declare 20 seconds. The configuration gate accepts
  explicit limits from 1 through 30 seconds. The Copilot SDK host reads
  `timeout` as an alias of its own `timeoutSec` and, unlike every other failure,
  lets a timed-out `preToolUse` hook through. Investigate slow filesystem access
  before changing the limit; do not replace a bounded hook with an unlimited one.
  The `PreToolUse` guard limits its own decision to about five seconds and
  blocks what it cannot inspect in that time, so a slow payload cannot ride the
  timeout.
- **A redeployed hook does not take effect.** The Copilot SDK host reads hook
  configuration when a session starts; a chat that was already open, and the
  subagents it starts, keep what they loaded. Start a new chat.
- **Saved levels do not reach a session.** Run
  `Get-CopilotAtelierContributorProfile -WorkspacePath .` in the workspace: it
  shows where the profile lives, which entry the identity rule selects and why,
  the levels, the exact sentence the workspace receives, and the registration
  state. The workspace must declare the area under `## Knowledge areas` in
  `.memory-bank/projectbrief.md`; without a declaration the hook neither reads
  the profile nor runs git. A registration written after a chat opened takes
  effect in the next chat, and after a compaction the levels return on the next
  successful tool call, so a reply without a tool call still lacks them.
  `Remove-CopilotAtelierContributorProfile -RegistrationOnly` clears an
  orphaned or pending registration.
- **Deployment drift.** Run `(Test-CopilotAtelier).Checks` to inspect missing
  scripts, changed files, and Discovery targets. This is read-only and never
  executes a hook as a health check.

## Safety

The `PreToolUse` block is pattern matching over the command string, not a
sandbox. An obfuscated or indirectly invoked push can evade it. Treat it as
defense in depth that removes the accidental path; [`AGENTS.md`](../../AGENTS.md)
still carries the rule itself.

An agent that can edit these scripts can rewrite its own guardrails. Keep the
hook scripts outside the agent's auto-approved edit scope with
`chat.tools.edits.autoApprove` so a change requires manual approval.

## See also

- [Agent hooks in VS Code](https://code.visualstudio.com/docs/agent-customization/hooks)
- [Hooks reference](https://code.visualstudio.com/docs/agents/reference/hooks-reference)
- [`AGENTS.md`](../../AGENTS.md) — the house rules these hooks enforce
