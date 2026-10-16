---
status: accepted
date: 2026-09-02
last-verified: 2026-10-15
owner: software-engineer
source: user request and specification-completion package evidence
---

# Package specification completion as capability-isolated agents

## Context and problem statement

A repository with detailed specifications can drift far from implementation.
The requested workflow must inventory every unmet requirement and corroborated
open issue, assign one implementation worker per work item, add unit and
integration tests, gather live evidence when safe, and run unattended within a
bounded overnight window. It must work across repositories, not only FarmSight.

This is high-agency work over untrusted repository, issue, command, test, and
subagent output. One general agent would combine private source, untrusted data,
write and execution authority, delegation, and potentially live-network access.
A Skill would also be unsafe as the entry point: Skills can auto-trigger, cannot
enforce separate tool surfaces per role, and overlap existing testing, review,
and monitoring Skills.

## Decision outcome

Ship one explicit Prompt and three capability-isolated Custom agents.

- `/complete-specifications` is the only entry point. Its body is deliberately
  small, binds directly to `spec-completion-controller`, and does not override
  the controller's tools.
- The controller is neither user-selectable nor model-selectable. It delegates
  only to `spec-work-implementer` and `spec-completion-reviewer`, freezes a
  closure matrix before implementation, and keeps every non-duplicate
  engineering row in the primary denominator.
- Each work item gets a fresh implementer in an isolated worktree. The
  implementer has an exact local search, edit, and execution allow-list, cannot
  delegate, and has no web, GitHub, browser, or MCP tool.
- Each result and the final accounting get a fresh reviewer. The reviewer has an
  exact read/search-only allow-list and cannot edit, execute, delegate, or use a
  network.
- Repository-defined build and test commands are the only repository-derived
  executable inputs. A changed command cannot execute until an independent
  control review passes.
- Controller and worker effective egress sets are empty. Live mode defaults to
  `off`; when explicitly enabled, a separately constrained live runner owns all
  endpoint access and cannot read repository or model context.
- A direct containment-profile SHA-256 anchors an external verifier, exact
  writable roots, hook paths, identities, empty egress, and optional live
  artifacts. A pinned appender stores a monotonic hash-chained ledger outside
  every repository process's writable roots.
- Missing or unverifiable containment, cleanup, review, accounting, or live
  evidence fails closed. The workflow never pushes or mutates shared or
  production targets unattended.

The package reuses existing Skills for TDD, review, agent security, and
long-running monitoring. It does not add another Skill.

## Consequences

- Selecting the Prompt is deliberate consent to the bounded workflow; ordinary
  repository work cannot trigger it automatically.
- The package specifies but does not deploy the operating-system boundary.
  Running it requires an externally prepared profile, verifier, ledger appender,
  identities, filesystem policy, and optional live runner. Missing controls
  produce `BlockedContainment`.
- Implementation, local-test, live-verification, and total closure percentages
  remain separate. Exclusion views are diagnostic and never replace raw primary
  denominators.
- Issue text comes only from an optional local snapshot and can motivate work
  only when tracked repository evidence corroborates it.
- The shared remote-mutation hook remains defense in depth. Deterministic hook
  resolution, exact-path checks, and expanded Git/GitHub CLI matching remove
  accidental bypasses, while measured empty egress remains the security
  boundary.
- Validation must remain static and executable without invoking the new Prompt
  or any packaged agent. A self-run cannot prove its own containment.

## Confirmation

The package, frontmatter, lifecycle, and complete hook slice passed 237 tests.
The native `build,test` workflow passed 957 tests with 0 failures and 78.86%
coverage against a 65% threshold; 108 environment-declared cases were skipped.
Independent agentic-security reviews ended with 0 Critical and 0 High findings.
The Prompt and its three agents were not invoked.

## Revision, 2026-10-14: what the verifier and the appender measure

The verifier and the appender this decision relies on now exist, and a series of
independent review passes corrected what the first paragraph of this decision
claims for them.

- **Writable roots are not exact.** The profile no longer anchors "exact
  writable roots". The verifier proves two things: every declared root accepts
  new files and folders, and a fixed, named escape set (the user profile, the
  temp folders, the folder of the profile, the folders of the ledger sink and
  the chain head) is not writable outside them. It does not enumerate the
  filesystem, so closing every other path is the deployment's filesystem policy,
  and the controller never reports the writable set as exact.
- **One identity per run, in a fresh process.** A verifier measures the identity
  and network namespace it runs in, so the controller runs it once per role. It
  runs only as the entry script of a `pwsh -NoProfile -File` process, read from
  its command line and its call stack, because a function or type defined
  earlier in a session outranks the ones it measures with. The command line is
  an allow-list (only options that cannot change what runs first may precede
  the script), and the check reaches its own helpers through the function
  table, so an alias or a function of the session cannot stand over it. Code
  that already runs in the process belongs to the launcher, and so does its
  environment, a .NET start-up hook included; only the module path is measured,
  because the firewall check is unmeasured unless its cmdlets come from a module
  under the system folder. It executes the pinned hook command, git and the
  pinned appender only after the verifier, the control digests, the immutability
  of the controls, the binding of the running identity to its role and, since the
  revision of 2026-10-15, the token of that identity have passed.
- **Names are compared exactly.** PowerShell's case-sensitive operators compare
  by culture and ignore characters such as a zero-width space, so every name,
  type, operation and digest that either script reads from a profile, a hook
  file, a ledger or a pipe is compared ordinally. Text that either script relays,
  the verifier's evidence and the appender's refusal line, is cut to printable
  ASCII by rune: a deny-list of invisible characters never closes, an
  allow-list does.
- **The Remote grant.** A contained run registers no hook that records a Remote
  grant, so a contained deployment pins a copy of the plugin whose `hooks.json`
  registers only the guard, names PowerShell (`powershell` or `pwsh`) by
  absolute path and starts it with `-NoProfile`, and is the file at the root of
  the pinned script. Any other program is refused, because what it loads first
  cannot be read, and the probe's own shell runs with `/d` so that no `AutoRun`
  command of the identity answers for the guard. The rest of the hook line is
  accepted by one plain shape, never by a list of characters to refuse: bare
  words of safe characters, non-empty double-quoted words, and at most the one
  pinned exit statement, after a program path that on Windows starts with a drive
  letter and a separator (a network, device or NT path would have the check read
  an access list over the network). A list was shown incomplete twice (a `#` is a
  comment to PowerShell and not to `cmd.exe`, so under a PowerShell host a push
  exited 1 and was not blocked while the `cmd.exe` probe still passed it; a word
  like `-x:` is a parameter to PowerShell), and a seeded test now holds every
  accepted line to the parser of the host. The probe ran through `cmd.exe` alone
  until the revision of 2026-10-16, and neither documented host starts the line
  that way; it now also runs the line under the wrapper of each host.
  `GrantRecorderUnregistered`
  measures that registration and an empty grants folder, and does not say that
  no grant can exist: the guard honors any well-formed grant file in a folder
  the run owns, so egress and credentials remain the boundary, as the
  consequences above already say.
- **The ledger.** The appender is bound to the profile when validating, keeps
  one canonical form for every record and refuses any other stored line,
  authenticates its pipe at both ends, and the client believes an acknowledgement
  only after rebuilding the digest of the record it sent and finding it in the
  ledger. The schema fixes four field names and nothing about their values,
  which stay untrusted text. The controller appends a `FinalReport` record
  carrying the digest of the report before it seals, which the verifier's
  `-Revalidate` checks.
- **Still open, and written down.** Hook files a host finds outside the pinned
  file are not read; the verifier inherits the environment of its launcher;
  `-Revalidate` does not bind the ledger to a run id; the chain is not keyed; a
  process of the service's own account can join the pipe name and make an append
  fail; and no test used a second Windows account. The token of the run identity
  was open here until the revision of 2026-10-15 below, and the pinned hook line
  was not run under the PowerShell hosts until the revision of 2026-10-16 below,
  which still runs no host itself. See
  [`docs/SECURITY-REVIEW.md`](../../docs/SECURITY-REVIEW.md).

## Revision, 2026-10-15: the token of the run identity is read

R-04 of the P5 review, the first item that was open above, is addressed, and not
closed for every claim. The refusal is measured on real tokens. The Pass is
tested through supplied facts and has not been measured on a real standard
account's token (third bullet). The probes of the verifier ask the operating
system whether the token it runs with holds a right, and two things in a token
never show as a right: a privilege that is held but disabled, and the
Administrators group of a filtered administrator token, which is deny-only until
the account is elevated.
`IdentityPrivilege` reads the token of the verifier process and refuses one that
is not a standard account's: elevated, of an elevation type other than default,
above Medium integrity, holding the Administrators group in any state, or
holding a privilege outside the five a filtered administrator token keeps
(`SeChangeNotifyPrivilege`, `SeShutdownPrivilege`, `SeUndockPrivilege`,
`SeIncreaseWorkingSetPrivilege`, `SeTimeZonePrivilege`), enabled or not. A token
that cannot be read, facts that cannot be interpreted, and a thread that
impersonates are unmeasured, which fails the run like a refusal. It is a check of
its own that gates the hook probe, git and the appender in `-Verify` and
`-Revalidate`, so an administrator's identity still binds (`IdentityBinding` is
unchanged) and is refused one check later. It supersedes the four gates that
"One identity per run" names above: there are five. The owner ruled for this
option, out of four, on 2026-10-15 and asked for a rebuild from nothing.

- **The claim is narrower than "a standard account".** The check shows that the
  token read at that moment is a standard account's by those rules. It does not
  show a group that confers power through access lists and not through a
  privilege (a group the token holds disabled, which a process can enable, is
  one: recorded as a follow-up, because it needs a real standard token to show
  that no valid account holds one), what the account stores or can reach over the
  network (egress and credentials stay the boundary), the token after the next
  logon, or whether the launcher gives the run the token it gave the verifier. It
  reads the token of the process, which every program the verifier starts
  inherits. A thread that impersonates is unmeasured: the binding and the probes
  that ask for access answer for the thread, and they are the process's identity
  only until it does.
- **The five privileges are measured on a filtered token, on one build.** A test
  makes a filtered administrator token with `CreateRestrictedToken` (`LUA_TOKEN`),
  reads it by handle, and finds the Administrators group deny-only and exactly
  those five privileges (Windows Server 2025, build 10.0.26100; no other build and
  no client edition). Microsoft describes that token as the standard user access
  token of an administrator's logon. A standard account's own set was not
  measured: it is expected to be some or all of the five, and any subset passes.
  The check refuses the filtered token for its Administrators group alone, which
  is the case no probe that asks for access can see. A service-style account that
  also holds `SeImpersonatePrivilege` and `SeCreateGlobalPrivilege` is refused:
  accepting one would need a field in the profile that pins extra privileges,
  which was not built.
- **The Pass is tested through a seam.** No test host here runs as a standard
  account, and a filtered administrator token is not one, so the Pass path is
  covered by rows that supply the facts, and the refusal by real tokens: the
  elevated token of the host, and filtered tokens the tests make. The test that
  closes it is open: create a throwaway local account, log it on with `LogonUser`,
  read its token by handle with the same reader, and expect a Pass. A hosted CI
  runner is an administrator and could run it; on a development host it creates
  an account, which is the owner's decision.
- **Review.** An independent review of the first build said Approve with changes:
  no Blocker or Major, ten Minors and two Nits (`docs/SECURITY-REVIEW.md`, the
  entry of 2026-10-15). The fixes are in the same change: the shape check of a SID
  and of the group list, the thread that impersonates, the bounds of the native
  parsers with crafted buffers, the reason a token was not read, the exact set of
  five privileges, and the wording above. A delta check of the fixes said Approve
  with changes again (no Blocker or Major, two Minors, four Nits) and found no new
  false Pass. Not done: a disabled group other than Administrators, a cross-check
  of the integrity level against the label in the group list, the Pass on a real
  standard token, and three small follow-ups of the delta check (the branch of
  `ThreadImpersonates` that fails closed has no test, two tests accept any
  exception, and the reason text is localized).

## Revision, 2026-10-16: the hook line is run under the wrappers of the documented hosts

The first follow-up after R-04 is built: the probe of `HookContract` no longer
stops at `cmd.exe`. The review of 2026-10-14 called the wrapper measurement "the
real fix for the whole class", because a line that `cmd.exe` and PowerShell read
differently passes a probe that only `cmd.exe` runs, and the host that wraps it in
PowerShell does not block. `HookContract` now runs the pinned line through
`cmd.exe /d /c`, as before, and on Windows then under Windows PowerShell 5.1 and
under the PowerShell that runs the verifier, started the way the table of hosts in
the hooks README gives for VS Code and the Copilot SDK host
(`-ExecutionPolicy Bypass -NoProfile -NoLogo -Command <line>` and
`-nop -nol -c <line>`, the line as the one argument that follows), and requires 0,
2 and 2 under each. It is still one check, so the gates, the controller's list of
checks and the profile schema are unchanged. The owner ruled for this option, out
of five (a profile key that names the hosts, replacing `cmd.exe`, keeping the
residual, and refusing only a quoted program path were the others), on 2026-10-16,
and took the recommended details: each wrapper is shown closed to the run identity
by the test the pinned interpreter gets, before anything runs under it; all three
spawns are required for every profile; and the wrappers run only after `cmd.exe`
passed, and both run even if the first one fails.

- **A quoted program path now fails by measurement.** On 2026-10-16 the shipped
  line, with its interpreter named by an unquoted absolute path without a space,
  gave 0, 2, 2 under all three spawns. With the path quoted it gave 0, 2, 2 under
  `cmd.exe` and 1, 1, 1 under both wrappers (a parse error, which does not block),
  and the check passed it before; with a leading `&` the wrappers gave 0, 2, 2 and
  `cmd.exe` gave 255. Only an unquoted path without a space works under all
  three, so PowerShell 7 at its default path (under `Program Files`) cannot be the
  pinned interpreter on Windows. S-24 is closed. S-33 stays a recorded Nit: its two
  spellings fail closed before the wrappers.
- **The claim is narrower than "run under the hosts".** The two spawns are rebuilt
  from the README's table with `ProcessStartInfo.ArgumentList`, and no host ran
  the line. VS Code's own spawn code, the Copilot SDK runtime, a host update that
  changes its form, the `bash`, `linux` and `osx` keys, macOS, Linux and other
  hosts were not run. The wrapper programs are the verifier's choice, by absolute
  path: the system `powershell.exe` and the PowerShell that runs the verifier. A
  host finds its own through its search path, which the launcher owns. A test
  holds the argument lists to the README's table. The measurement is of one host,
  with Windows PowerShell 5.1.26100.33648 and PowerShell 7.6.7.
- **The wrappers are programs run as the identity under test.** One that identity
  can replace could answer 0, 2 and 2 for the guard, so each is shown closed (the
  program, its folder and every folder above it) before anything runs under it. A
  wrapper that can be replaced fails the check, and one that is absent or cannot be
  measured leaves it unmeasured. A Microsoft Store install of PowerShell 7, whose
  folder is not readable, is expected to be unmeasured; that was not tried. What a
  spawn wrote is never relayed, only its exit code.
- **Cost.** About 7 seconds more for each verify run (three payloads under each
  wrapper, warm, one host) and about 85 seconds more for the `HookContract` suite.
