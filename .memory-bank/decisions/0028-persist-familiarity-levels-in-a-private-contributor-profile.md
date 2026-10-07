---
status: accepted
date: 2026-10-06
last-verified: 2026-10-06
owner: software-architect
source: software-architect Design Concept interview 2026-10-05 to 2026-10-06 and sign-off 2026-10-06; amendment interview 2026-10-06 (rulings A1 to A7); Decision record 0027; hook host references (VS Code, GitHub, Claude Code), fetched during the interview
supersedes: none
---

# Persist Familiarity levels in a private Contributor profile

## Context and problem statement

Decision record 0027 shipped Phase 1 of contributor calibration: every level is
session-scoped, so a contributor restates it in each session, and a compaction
silently resets every level to `familiar` (CAL-09). It fixed the Phase 2
constraints: a private profile outside every repository, in a subfolder of the
synced CopilotAtelier folder that the installer never manages; a one-file
import for machines without that folder; the git identity as a lookup key, not
as proof; an interview that is offered, never forced; and a sticky, reversible,
deletable opt-out.

Facts verified during the design, each of which shaped it:

- No Copilot host reruns SessionStart after a compaction. VS Code's `source` is
  always `new`, and Copilot CLI knows `startup`, `resume`, and `new`. Neither
  can inject context on each prompt.
- VS Code's PostToolUse carries `hookSpecificOutput.additionalContext`, and
  Copilot CLI's `postToolUse` can inject context, while its `preToolUse` can
  only allow, deny, or modify.
- Remote-SSH, WSL, Dev Containers, and Codespaces run hooks on the remote side.
- On Prox1, one tool-call hook costs p95 576 ms through VS Code's spawn and
  p95 846 ms through the SDK host's.
- Reading the data of a dehydrated OneDrive placeholder downloads it, while an
  attribute query does not.

## Decision outcome

Persist each contributor's Familiarity levels in a Contributor profile, schema
1, at `<Canonical target>/contributor/profile.json`, found by following the
`~/.copilot/hooks` link, with `<LocalApplicationData>/CopilotAtelier/contributor/`
as the fallback on every other machine.

- The SessionStart hook injects levels only for Knowledge areas that the
  workspace declares in `.memory-bank/projectbrief.md` and the profile rates, as
  one data-only sentence with the lowest context-budget priority.
- After a compaction, a PostToolUse hook re-sends the levels once, on the first
  successful tool call after the PreCompact hook advanced a counter *(A7)*. Its
  hook file exists only while the machine's profile has an active entry with
  levels.
- A new `contributor-profile` Skill and five
  `*-CopilotAtelierContributorProfile` commands share one implementation for
  the interview, saving, opt-out, deletion, export, import, and diagnosis.

The architect first recommended a Skill reader that the agent runs on
compaction recovery. The contributor chose the deterministic hook path instead
and accepted its per-call cost on machines with an active profile. An
independent review found 2 Blockers and 5 Majors in the first draft; all are
fixed or ruled, as recorded below.

## Consequences

- On a machine with an active profile, every successful tool call in a session
  started while the registration exists costs about one more hook launch, as
  much as the push guard: 0.8 to 0.9 s through VS Code's spawn and 1.0 to
  1.15 s through the SDK host's on Prox1 on 2026-10-06, a day it ran 26 to
  50 % slower than the one before. Machines without a profile pay nothing
  *(A1, A3)*.
- A session in a workspace that declares Knowledge areas starts up to half a
  hook launch later, about 0.35 s in VS Code on Prox1 *(A1, A2)*.
- After a compaction, plugin-only installs and a reply that makes no tool call
  receive no levels; Claude Code gets the portable Skill only. These gaps are
  measured and reported, not gated.
- A hostile workspace can declare up to 16 common area names to get the
  matching levels into its session. That risk, and the unenforced approval of
  an agent-run write, are accepted as Low by ruling R1.
- `Uninstall-CopilotAtelier` gains one contract: it reconciles the registration
  before removing any file, and stops when it cannot.
- Five public commands enlarge the module's API; renaming one later needs a
  deprecation alias.
- `contributor-profile` becomes a mandatory Skill in every installation profile.
- No Familiarity level can land under a git working tree: every reader and
  writer refuses such a path.

## Confirmation

Implemented by `software-engineer` on 2026-10-06, Amendment 1 included, except
as recorded below: criterion 20 waits for RAANDREE3, and criteria 21 and 22 are
open. The five questions it returned to `software-architect` were ruled on the
same day (*Rulings, 2026-10-06*), and Amendment 1 applies the rulings to the
concept. The signed-off Acceptance criteria 1 to 25 below, as amended, are the
contract; the spike TBD-1 ran before increment 2. Implementation records its
evidence here: the eval results against
`Calibration.Persistence` and `Calibration.PhaseOneGuard`, the
`Calibration.Delivery` matrix, and the latency Meter on Prox1 and RAANDREE3.

### Spike TBD-1, 2026-10-06 on Prox1

`tests/Fixtures/Invoke-CopilotSdkConversation.mjs` drove real sessions of the
runtime that VS Code `07f806f999` bundles (SDK 1.0.15-preview.4) and of the
standalone Copilot CLI 1.0.92 against a fake, local OpenAI-compatible model that
recorded every request, which is exactly what a model reads. A scratch
`COPILOT_HOME` held `hooks/hooks.json` (SessionStart, PreCompact) and, from a
chosen step on, `hooks/contributor-profile.json` (PostToolUse). Probe hooks
logged their input and printed different top-level and `hookSpecificOutput`
markers, and `session.rpc.history.compact` forced each compaction. VS Code Local
was read from its documentation, its built-in Copilot extension, and its hook
log.

| Question | VS Code Local | SDK host | Copilot CLI |
|---|---|---|---|
| Does the first SessionStart text survive a compaction? | Not expected: the extension renders it once, into the first turn's user message, and summarization replaces old turns; criterion 22's manual check confirms | No: it is a separate user message, and the compaction keeps only the user's own messages plus the summary | No, identical |
| Does PostToolUse `additionalContext` reach the model? | Documented; the extension reads only `hookSpecificOutput.additionalContext` | Yes, only the top-level key, appended to the tool result after `Additional guidance from postToolUse hooks:`, also on the first tool call after a compaction; a `hookSpecificOutput` copy in the same object is ignored | Yes, identical |
| Is a second `*.json` in the user hooks folder loaded, and when? | Documented as `~/.copilot/hooks/*.json`; one hook ran per event although `chat.hookFilesLocations` names the same folder; reload timing not verified | Yes, by sessions started after it exists; a session started before never runs it; a session that loaded it keeps running it after the file is deleted | Yes, identical |
| Does PreCompact fire? | Decision 0021 | Yes, `manual` here and `auto` in three earlier sessions on Prox1 | Yes |

No finding contradicts the signed-off concept. The SessionStart text never
survives a compaction in the SDK host or Copilot CLI, so the PostToolUse hook is
the sole carrier after every compaction there, which is the effect TBD-1 named.
The spike adds three implementation facts:

- PostToolUse fires only for a successful tool result, in every host; a failure
  runs `PostToolUseFailure`. The first tool call after a compaction therefore
  means the first successful one, and the compare-and-set counter already
  covers a failed call in between.
- Every PostToolUse payload carries `session_id` and `cwd`, equal to those of
  SessionStart and PreCompact in the same session, plus the whole tool result
  (`tool_result` in the SDK host and Copilot CLI, `tool_response` in VS Code
  Local). `Add-FamiliarityContext.ps1` must find `session_id` and `cwd` without
  parsing a large payload in full.
- `tests/HookSdkRuntime.Tests.ps1` guards these host facts in both runtimes.

### Implementation, 2026-10-06 on Prox1

Increments 2 to 5 are built test-first on `ai/calibration-phase-2`. Pester
covers criteria 1 to 19 and 23 to 25; criteria 13 and 14 are tested as text,
and their behavior waits for the eval. The SDK runtime probe of criterion 22
passes in the bundled runtime and in Copilot CLI 1.0.92: *Contributor levels
delivered by* in `tests/HookSdkRuntime.Tests.ps1` runs the shipped hooks, the
registration template, and the Skill in the deployed layout against the
recording model. The levels appear in the `sessionStart` `hook.end` event and
in the first request; nothing is added to a tool result before a compaction;
the levels return in the first tool result after a forced compaction.

Still open, and not decided in code:

| Criterion | State |
|---|---|
| 20 | Not met: one gated cell over Budget and within Fail on each machine, reproduced (Prox1: SessionStart with one entry in VS Code's spawn; RAANDREE3: PostToolUse in the SDK host's spawn), and TBD-5 answered no; returned to `software-architect` (*Returned to software-architect, second round*) |
| 21 | Not run: the private kit's Phase 2 runner and draft cases are ready, but no machine yields 6 real level restatements per Position (question 5 of the second round); runs are paid |
| 22 | Copilot CLI passes with a real model; VS Code Local is not demonstrated, because Copilot Chat 0.68.0 runs no PreCompact hook for a manual `/compact` or a background compaction; VS Code's agent host re-sent the levels after each of three automatic compactions (*Compactions*); the plugin-install and no-tool-call cells are measured (*Reported delivery cells*) |

### Latency Meter, 2026-10-06 on Prox1

`tests/Fixtures/Measure-CalibrationLatency.ps1` implements the Meter: the
working tree's scripts in the deployed layout under a scratch home, each host's
exact spawn with process start included (VS Code: `powershell.exe -Command`
around the `windows` command; SDK host: `pwsh -c` around the `powershell`
command), two warm-up and ten measured runs per cell, and the push guard on a
benign tool as the same-day proxy. Four runs of the Meter and its prototype on
Prox1, an 8-vCPU virtual machine at 1 % background load, the no-profile cell in
the last two and the proxy in the last three; milliseconds at p95, with p50 in
brackets for the added latency:

| Cell | VS Code spawn | SDK spawn | Budget | Fail |
|---|---|---|---|---|
| SessionStart added: declared areas and a profile | +349 to +380 (+344 to +371) | +189 to +330 (+286 to +309) | +100 | +250 |
| SessionStart added: declared areas, no profile | +164 to +184 (+166 to +171) | +50 to +80 (+127 to +150) | +100 | +250 |
| PostToolUse, nothing pending | 793 to 901 | 1,007 to 1,154 | 600 / 900 | 1,000 |
| Proxy: push guard, benign tool | 855 to 868 | 1,060 to 1,077 | n/a | n/a |

The proxy measured p95 576 ms and 846 ms on 2026-10-05, so Prox1 ran 26 % (SDK)
to 50 % (VS Code) slower on 2026-10-06 than when the budgets were set. The
SessionStart baseline measured p95 831 to 847 ms (VS Code) and 1,049 to 1,188 ms
(SDK), not the 334 ms and 512 ms recorded as Past, which were evidently taken
another way; only the added milliseconds compare.

- **SessionStart.AddedLatency fails.** VS Code is above Fail in all four runs,
  the SDK spawn in three by p95 and in all four by p50. A workspace that
  declares areas still pays +164 to +184 ms in VS Code without any profile,
  because the reader must look before it can report the unrated count.
- **PostToolUse.CallLatency is over Budget in both spawns and above Fail in the
  SDK spawn**, by 7 to 154 ms. The hook costs about 5 % less than the same-day
  proxy at p50: the cost is the shared launcher on that day's machine, not the
  script, whose common path reads the payload head, runs one regex, and checks
  one file.

Cause of the SessionStart cost, attributed in process under Windows PowerShell
after the launcher's own warm-up: dot-sourcing the reader 18 ms, the Knowledge
areas 80, the location rule 40, the repository check 8, the JSON parse 62, the
schema validation 84, the entry selection 4, the sentence 22, and about 100 more
in the first full calibration call. A third run of the whole step in the same
process costs 10 ms, and the parser costs 66 ms on `{}` but 2 ms on its third
run. The time is the first execution of about 4,600 syntax-tree nodes in a fresh
process, spread over about 20 constructs at 1 to 9 ms each, not the work. Local
tuning, such as loops for pipelines and fewer first-use constructs, is worth an
estimated 30 to 40 ms, short of either line.

Scaled by the same-day proxy ratio, 0.67 (VS Code) and 0.79 (SDK), the
2026-10-05 machine would show about +245 ms and +235 ms for SessionStart, just
under Fail and 2.4 times Budget, and about 550 ms and 830 ms for PostToolUse,
within Budget. That is an estimate: the ratio comes from spawn cost, and the
reader's cold cost need not scale the same way. With ten runs, p95 is the
slowest run, so one slow baseline run moved an SDK result from +288 (p50) to
+189 (p95); the Meter prints both.

### Returned to software-architect

Results that contradict the signed-off concept go back to `software-architect`;
none is redesigned in code. All five, and the interpretations after them, are
ruled in the next section.

1. **SessionStart.AddedLatency fails.** Options: re-baseline Budget and Fail,
   since the cost is paid once per session rather than per call; a validated
   digest beside the profile that every writer maintains and the hook reads
   when the profile's length and write time match, with the full reader as
   fallback, which adds a private artifact with deletion, export, and drift
   consequences; a lighter launcher for every hook under Decision 0016, which
   costs more than the reader adds; local tuning, 30 to 40 ms and not enough
   alone; or fallback A at session start.
2. **PostToolUse.CallLatency misses Budget, and Fail in the SDK spawn,** while
   costing less than the same-day proxy. Options: state the Meter relative to a
   same-day proxy; fallback A, as the concept prescribes when B1 misses its
   budget; or re-baseline.
3. **Context.SentenceSize cannot hold for every profile.** The fixed template
   makes the worst case 1,118 characters at session start and 1,178 re-sent,
   for 16 names of 48 characters at `familiar`;
   `tests/ContributorProfileReader.Tests.ps1` pins both. Raise the budget or
   shorten the template.
4. **The deletion rule blocks a template change.** A registration is deleted
   only when its hash equals the current template's, so the first release that
   changes the template leaves every owned registration undeletable,
   `-RegistrationOnly` included. Option: also accept a file whose hash equals
   the recorded one.
5. **The area-name rule rejects `.NET`,** because a name must start with a
   letter or a digit. Loosening is safe later.

Where the concept is silent, the code interprets it as follows, for
confirmation: combining marks may follow the first character; stored names must
already be trimmed and in NFC; all seven entry fields are required; `Set-`
without `-Contributor` selects by the identity rule, creates an entry when no
entry matches and none is the default, and fails without a git identity when
several entries exist; `-SnoozeInterview` exists only on the Skill script;
`Set-` takes paired `-KnowledgeArea` and `-Level` arrays for one preview and one
write; the first tool call after a compaction is the first successful one.

### Rulings, 2026-10-06

`software-architect` and the repository owner ruled on the five questions and
the seven interpretations in one interview at named-subset depth: seven
questions, then three more after an independent review of the draft (A1
refined, A7 revised, A8 added), each decided on the recommended option. The
questions behind A5, A6, the revised A7, and A8 offered no
`not sure, you pick`, because they govern deletion in the hooks folder, a
persisted injection control, whose entry a write changes, and when Uninstall
may remove scripts; no answer was delegated. Amendment 1 applies the rulings
to the concept below and marks every amended passage with its tag.

| # | Question | Ruling |
|---|---|---|
| A1 | Latency unit | Both latency requirements count in launches of a fixed no-op hook through the same launcher and spawn; the push guard is reported beside it. Each of 20 replicates runs every cell back to back in rotated order, ratios are taken per replicate before the p95, thresholds are inclusive, and a verdict above Budget or Fail counts only when a second Meter run reproduces it (refined after review) |
| A2 | SessionStart.AddedLatency fails | Re-baselined to Budget 0.5 and Fail 1.0 launch; the design stays; a two-entry profile, where git runs, is reported, not gated |
| A3 | PostToolUse.CallLatency misses | Budget 1.1 and Fail 1.25 launch; fallback A applies only when B1 reaches Fail on Prox1 or RAANDREE3 |
| A4 | Context.SentenceSize | Budget [worst] 1,200 for both sentences; the template stays |
| A5 | Deletion rule | A registration is owned through the record and the recorded hash, whatever template it came from; the next writer replaces an owned file from an earlier template |
| A6 | `.NET` | A name may start with `.` directly followed by a letter or a digit, from the first release |
| A7 | Interpretations | 1 to 3 and 5 to 7 confirmed; 4 replaced by the write-selection rule: a write goes only to a positively chosen target, and `-NewContributor` creates a contributor's own entry (revised after review) |
| A8 | OneDrive sync order (review) | Nothing infers from a partial view: a create record without its file stays pending, Uninstall stops on it, and only `-RegistrationOnly` clears it; a delete record without its file is finished; reconciliation never rewrites a record; the two-machine race is documented |

Reasons:

- **A1.** Prox1 ran 26 % (SDK) to 50 % (VS Code) slower on 2026-10-06 than on
  2026-10-05, so the millisecond gates failed on machine load. The scaled
  estimate for 2026-10-05 divides by the proxy ratio, so it cannot show that
  the reader's cost tracks machine speed; that stays an Assumption, which
  RAANDREE3 tests (TBD-5). The review then showed that the push guard's own
  work, which grew through prompts 02 to 06, would move both ratios, and that
  the difference of two independently sampled p95 values is not the p95 of
  the added time; hence the no-op unit and the paired replicates. The Past
  lines divide the ranges above by the push guard; against the no-op unit the
  ratios read higher by the guard's own work, about 5 % of a launch at p50,
  and the next Meter run replaces them.
- **A2.** The signed-off Past, 334 ms and 512 ms total, is withdrawn: the Meter
  measures 831 to 847 ms and 1,049 to 1,188 ms for the same baseline, so the
  +100 ms Budget rested on a level that no Meter run reproduces. The cost is
  the reader's first execution in a fresh process, paid once per chat, only in
  workspaces that declare Knowledge areas, by contributors who accept one
  launch on every tool call. Rejected: a validated digest beside the profile,
  a second private file that every writer keeps in step, for an estimated 150
  to 200 ms that still leaves the 0.2-launch floor of reading the declaration;
  and fallback A at session start, which gives up the deterministic delivery
  of Q10 for a tool call plus a model round trip.
- **A3.** The hook's common path reads the payload head, runs one regex, and
  checks one file, and it cost 5 % less than the same-day push guard at p50.
  Invoking fallback A for a miss caused by machine load would delete tested
  code, so it is reserved for a Fail-level result.
- **A4.** The worst case is a constant of the fixed template and the caps, and
  the template's framing (data only, treat them as stated levels, the
  offer-suppressing suffix) is a security control that the eval has not yet
  measured. The extra 100 characters cost about 25 tokens, once per session
  and once per compaction.
- **A5.** Requiring the current template's hash stranded every owned
  registration at the first template change: opt-out could not remove it,
  `-RegistrationOnly` refused, and Uninstall stopped on every machine with a
  profile. Ownership through the recorded hash is the Deployment record's rule
  for Owned files. The dropped condition protected nothing that matters: only
  a process running as the contributor can write the record, and such a
  process can delete the file directly, which is also why a shipped list of
  released template hashes was rejected. Known limit: an outdated registration
  keeps its old launcher until the next profile write, so a template fix
  reaches a machine at that write; `Get-` reports it until then.
- **A6.** Loosening is not safe after the first release. Schema 1 rejects a
  whole profile over one name, so a release that accepted `.NET` later would
  make every machine still on an older release that syncs the same profile
  reject it as `invalid-schema` and lose every level; any later loosening needs
  schema 2. Only a leading `.` is admitted: a leading `-` reads as a parameter
  when an agent builds a command line without quotes, and no other punctuation
  leads a real Knowledge area name.
- **A7.** The identity rule's single-entry and default fallbacks are harmless
  for reading, but on a shared lab account they would write one person's level
  into another person's entry, also when git reports no email. Without
  `-NewContributor`, a new person on a shared account could reach no entry of
  their own: `-Contributor` selects only existing entries, and Import needs an
  exported file. The Skill asks once per session when the target is unclear,
  which on a machine without a git email, such as Prox1, costs one question
  per session.
- **A8.** On OneDrive machines the registration record and
  `hooks/contributor-profile.json` both live in the synced Canonical target
  and arrive in any order. Reconciliation read a record without its file as
  nothing registered, deleted the record, and let Uninstall remove the scripts
  under a registration still on its way, the outcome the stop rule exists to
  prevent; that gap predates Amendment 1. Machine-scoped repair, a record field
  naming the writing machine, and a distributed journal with generation IDs and
  tombstones were rejected as more machinery than a sync race of seconds
  warrants. Known limit: two machines that act before either has synced can
  leave a conflict copy in the hooks folder, or after an Uninstall a
  registration whose scripts are gone; `Get-` names the file to delete.

Independent review of the draft, a `rubber-duck` review on 2026-10-06, and its
re-review of the revision, which confirmed findings 1 to 5 resolved, found no
new Blocker, and added finding 6:

| # | Severity | Finding | Resolution |
|---|---|---|---|
| 1 | Blocker | The record and the registration file sync through OneDrive in any order, and reconciliation inferred nothing registered from a record without its file | Ruling A8 |
| 2 | Blocker | A7 still wrote to the only entry without a git email, and a new person on a shared account could create no entry | A7 revised: positively chosen targets and `-NewContributor` |
| 3 | Major | The difference of two p95 values is not the p95 of the added time | A1 refined: paired replicates, inclusive thresholds, a reproduced verdict |
| 4 | Major | The push guard's own work sat inside the unit | A1 refined: a fixed no-op hook as the unit |
| 5 | Minor | Missing tags and Amendment log entries | Fixed |
| 6 | Major | A `-NewContributor` entry beside others, without a git email, was unreachable by the hooks, and `-NewContributor` with `-Contributor` was undefined | Fixed as the re-review proposed: a reachable alias or `-Default` is required, and the two parameters exclude each other |

### Amendment 1 implemented, 2026-10-06 on Prox1

`software-engineer` implemented rulings A1 to A8 test-first on
`ai/calibration-phase-2`. Every new test ran red against the code of `b72ac98`
in a scratch worktree, and green on the change: 30 of the 98 writer tests, the
three leading-dot cases of the reader suite, and all 14 cases of the new
`tests/CalibrationMeter.Tests.ps1`. The full gate then passed 3,062 tests with
0 failures.

| Ruling | Implementation | Evidence |
|---|---|---|
| A1 to A3 | The Meter's unit is `Invoke-NoOpHook.ps1`, which reads its payload as the shipped hooks do and runs through the SessionStart launcher with the same spawn; 2 warm-up and 20 measured replicates per run, cells rotated by one place per replicate, ratios per replicate before the nearest-rank p95, inclusive thresholds, and `-Repeat 2` merging each gated cell to its least severe verdict | `tests/CalibrationMeter.Tests.ps1` pins the arithmetic and the Budget and Fail levels; results below |
| A4 | The template stays; the worst case is tested at or below 1,200 at both Positions | Reader suite |
| A5 | Ownership through the record and its hash, whichever template; an outdated registration is replaced as a delete followed by a create; `Get-` reports `outdated` | Every crash point of a create, a delete, and a replacement reconciles to owned, outdated, pending, or none; opt-out, `-RegistrationOnly`, and Uninstall remove a registration from a changed template |
| A6 | `.NET` passes the area-name rule in the profile and in `projectbrief.md` | The shared fixture set holds `.NET` valid and `.`, `..`, and `. NET` invalid; the hooks in both editions, the Skill script, and the module agree |
| A7 | `-NewContributor` on `Set-` and on the Skill script; no fallback to the only or the default entry for a write; the reachability check and the preview note; the Skill's once-per-session target question | One test per branch, through the functions and through the module |
| A8 | Reconciliation compares and never rewrites a record, clearing only a delete record whose file is gone; `Get-` changes nothing; a pending registration is left alone, stops Uninstall, and is cleared by `-RegistrationOnly` after confirmation; `Get-` lists registration conflict copies in the hooks folder | Nine delivery orders a second machine can see: no diagnosis, writer, or Uninstall changes the record or the file, and Uninstall stops |

Where the amendment is silent, the code interprets it as follows, for
confirmation:

- `Get-` no longer reconciles at all. Before A8 it completed a pending record
  under the lock, which "never rewrites a record" rules out; a writer or
  Uninstall clears a finished delete record.
- An unreadable record without a file reads as none, as before, and a writer
  replaces it with its own pending record; beside a file it reads as modified.
- A replacement clears the delete record before it writes the create record,
  so its middle state is none.
- A file in the hooks folder is a possible conflict copy of the registration
  when its name starts with `contributor-profile` or, unless it is a cloud
  placeholder, its text names `Add-FamiliarityContext.ps1`; TBD-2 is open.
- `-NewContributor` on a machine without a profile creates the first entry,
  which needs no alias.
- A git address that is not a valid alias counts as no address for the
  write-selection rule.

### Latency Meter as amended, 2026-10-06 on Prox1

Two runs of `Measure-CalibrationLatency.ps1 -Repeat 2`, 15:04 to 15:16 UTC,
load 7 % at start: per run and spawn, 2 warm-up and 20 measured replicates of
all seven cells in rotated order. p95 of the paired per-replicate ratios, in
no-op hook launches, run 1 and run 2; the no-op launch itself measured p50 778
to 790 ms through VS Code's spawn and 1,014 to 1,042 ms through the SDK host's.

| Cell | VS Code spawn | SDK spawn | Budget | Fail | Reproduced verdict |
|---|---|---|---|---|---|
| SessionStart added, one entry | 0.61, 0.53 | 0.45, 0.35 | 0.5 | 1.0 | VS Code over budget; SDK within budget |
| SessionStart added, no profile | 0.39, 0.25 | 0.27, 0.18 | 0.5 | 1.0 | Within budget |
| SessionStart added, two entries (reported) | 0.85, 0.65 | 0.49, 0.44 | n/a | n/a | n/a |
| PostToolUse, nothing pending | 1.12, 1.09 | 1.10, 1.08 | 1.1 | 1.25 | Within budget; run 1's over-budget verdicts were not reproduced |
| Push guard, benign tool (reported) | 1.26, 1.18 | 1.16, 1.11 | n/a | n/a | n/a |

In milliseconds, for the record: SessionStart added p95 +412 to +493 (one
entry), +196 to +308 (no profile), and +504 to +655 (two entries) in VS Code's
spawn; +349 to +482, +181 to +290, and +445 to +502 in the SDK host's.
PostToolUse p95 838 to 884 ms and 1,094 to 1,152 ms.

- **Criterion 20 does not hold on Prox1 for one cell.** SessionStart added
  latency with a one-entry profile in VS Code's spawn is over Budget in both
  runs, 0.53 to 0.61 launch at p95 and 0.48 to 0.50 at p50, and half the Fail
  level. Every other gated cell meets its Budget. A result that contradicts
  the concept goes back to `software-architect`; nothing was tuned in code to
  reach the line.
- The push guard costs 1.11 to 1.26 launches, so against the no-op unit the
  ratios read higher than the Past lines divided by the guard, as ruling A1
  expected.
- TBD-5 needed the RAANDREE3 run, recorded in the next section.

### Latency Meter on RAANDREE3, 2026-10-06

The owner ran the Meter of the pushed head `b7e6502` on RAANDREE3: two runs of
2 warm-up and 20 measured replicates each. Later commits change a few dozen
statements on the measured paths. p95 of the paired per-replicate ratios, in
no-op hook launches, run 1 and run 2:

| Cell | VS Code spawn | SDK spawn | Budget | Fail | Reproduced verdict |
|---|---|---|---|---|---|
| SessionStart added, one entry | 0.27, 0.38 | 0.43, 0.71 | 0.5 | 1.0 | Within budget; the SDK spawn's over-budget run 2 was not reproduced |
| SessionStart added, no profile | 0.12, 0.16 | 0.21, 0.28 | 0.5 | 1.0 | Within budget |
| SessionStart added, two entries (reported) | 0.36, 0.51 | 0.55, 0.84 | n/a | n/a | n/a |
| PostToolUse, nothing pending | 1.05, 1.06 | 1.11, 1.25 | 1.1 | 1.25 | VS Code within budget; SDK over budget in both runs, within Fail |
| Push guard, benign tool (reported) | 1.16, 1.13 | 1.14, 1.31 | n/a | n/a | n/a |

The no-op launch measured p50 1,916 to 1,973 ms through VS Code's spawn and
1,039 to 1,144 ms through the SDK host's. Run 2 was the noisier one: its VS Code
no-op read p95 2,424 ms against p50 1,973.

- **Criterion 20 does not hold.** One gated cell is over Budget on each
  machine, reproduced and within Fail: SessionStart with one entry in VS Code's
  spawn on Prox1, and PostToolUse in the SDK host's spawn on RAANDREE3, whose
  run 2 read 1.25 launch, at the Fail level but not above it. Fallback A,
  reserved for a Fail-level result (A3), does not apply.
- **TBD-5: no.** The reader's cold cost does not scale with the launch cost
  across machines. Against Prox1, RAANDREE3's no-op launch costs 2.4 to 2.5
  times as much through VS Code's spawn and 1.0 to 1.1 times through the SDK
  host's, while the reader's added time is 1.1 to 1.4 times in both, estimated
  as the difference of the medians the Meter prints (one entry minus no
  declaration). Launch cost and script cost diverge by machine and edition, so
  the same reader reads 0.48 to 0.50 launch at p50 on Prox1 and 0.25 to 0.26 on
  RAANDREE3 in VS Code's spawn.
- **In milliseconds,** an active profile adds about 2.0 s to every successful
  tool call in VS Code on RAANDREE3 (PostToolUse p50 1,975 to 2,029 ms),
  beside the push guard's 2.1 to 2.2 s; the Consequences state 0.8 to 0.9 s,
  measured on Prox1. Every hook in VS Code's spawn starts two Windows
  PowerShell processes, VS Code's own and the one the `windows` launcher
  starts. Why Windows PowerShell starts 2.4 times slower on RAANDREE3 than on
  Prox1, while PowerShell 7 does not, was not investigated.

### Returned to software-architect, second round

Five results go back, the last two from the compaction checks and the eval
preparation; none is redesigned in code.

1. **The launch unit does not transfer across machines (TBD-5).** Options: keep
   it and gate per machine, so the machine with the cheapest launch binds; gate
   the calibration step's own time, normalized by a frozen reference script run
   cold through the same spawn, and report the hook's full time beside it,
   leaving the launcher to Decision 0016; or return to milliseconds measured on
   an idle machine, with the no-op launch as the load check. The engineer
   recommends the second: its unit is the same kind of work as the measured
   cost, so it should cancel machine speed and load; it needs a new Meter cell
   and a re-baseline.
2. **Criterion 20 has two reproduced over-Budget cells, both within Fail.**
   Their verdicts depend on the unit, so rule 1 first. Prox1's VS Code cell
   needs about 25 to 90 ms less at p95, against the 30 to 40 ms that local
   tuning was estimated to save. PostToolUse's common path is already minimal:
   it costs less than the push guard in every cell, and RAANDREE3's SDK cell is
   within Budget at p50 (1.06 to 1.08).
3. **The per-call cost on RAANDREE3 is 2.4 times what the Consequences state.**
   Options: accept it and restate the Consequences per machine; a one-process
   `windows` launcher under Decision 0016, which would cut every hook's cost,
   the push guard's included, but is measured on neither machine and must keep
   the cross-shell guarantees of `tests/HookLauncher.Tests.ps1`; or fallback A
   for VS Code only.
4. **VS Code Local runs no PreCompact hook for a manual or a background
   compaction** (*Compactions*), only on its rare foreground fallback.
   The Purpose promises levels after a compaction in module and Setup
   installs; in VS Code Local that does not hold in practice. VS Code's agent
   host, which runs the SDK runtime, does run it and re-sends, so the gap is
   VS Code Local's alone. On 2026-10-07 the owner ruled out asking VS Code for
   a change: only options inside this project's control count. Copilot Chat
   0.68.0's code shows what such an option can use:
   - SessionStart's `additionalContext` is frozen into the first turn's user
     message, which later turns replay; it is not part of the system prompt.
   - A compaction replaces every user message it summarizes with the summary,
     the current turn's included when it compacts partway through a turn; the
     levels survive only when the summary repeats them.
   - A `UserPromptSubmit` hook's `additionalContext` joins the same per-turn
     message, so it would restore the levels at every new prompt without
     PreCompact. No `UserPromptSubmit` hook is registered today, so it adds a
     launch to every prompt for profile users: about 0.8 s on Prox1 and 2 s on
     RAANDREE3 in VS Code, before the reader's time.
   - Partway through a turn, only PostToolUse output after the summary can
     carry the sentence. PostToolUse already runs on every tool call for
     profile users, but needs a re-send trigger that does not depend on
     PreCompact, such as a count of tool calls since the last send.

   Options: keep it as a reported gap, like a reply that makes no tool call;
   re-send at every prompt through `UserPromptSubmit`; re-send through
   PostToolUse every N tool calls; or both. The engineer recommends the
   PostToolUse count: it adds no launch and recovers within N tool calls, at
   the sentence's tokens and the reader's time on every Nth call, and it
   leaves the reported gap for a reply that makes no tool call.
5. **`Calibration.Persistence` cannot be measured from real restatements.**
   Its Meter needs at least 6 per Position, mined from real restatements.
   The finder, extended to flag level statements, has searched three whole
   histories, 2,706 user messages. Prox1's (619) holds none, and
   RZ1VPFWEB200's (475) held none in a run 18 minutes after the extension,
   though its files cannot prove the finder version. RAANDREE3's (1,612, a
   version 2 run on 2026-10-07) flags 6: 3 state a level, all `new` and in
   three areas, one of them already an approved Phase 1 case; 2 ask for a
   shorter or a longer answer, which the Instruction treats as a one-answer
   override; 1 is not about a Knowledge area. With the three in the approved
   Phase 1 cases, at most 5 real restatements exist, and RAANDREE3's run holds
   none at `expert`. Phase 2 itself removes the need to restate. Options:
   accept persistence cases derived from real cases, with the stated level
   moved into the profile sentence; accept owner-reviewed synthetic cases; or
   lower the count. The engineer recommends derived cases, topped up with
   reviewed synthetic ones for `expert`.

### Compactions, 2026-10-06 on Prox1

The owner ran the check in a scratch workspace that declares Kerberos and
PowerShell DSC, with the branch deployed through Setup and a one-entry profile
rating both.

- **Copilot CLI 1.0.92 (session `1fad021f`, a real model): passes.** The
  SessionStart hook delivered the levels, and no PostToolUse output came
  before the compaction. `/compact` ran PreCompact (`trigger: manual`), which
  wrote the checkpoint. The first successful tool call afterwards re-sent the
  levels with the offer-suppressing suffix, and later calls added nothing. Asked
  which levels it had and where from, the model named both and said they were
  re-sent after a compaction, without reading any file.
- **VS Code Local, Copilot Chat 0.68.0 (session `53bfb281`): not
  demonstrated.** The SessionStart hook delivered the levels, and `/compact`
  compacted the conversation, but no PreCompact hook ran, so the counter never
  advanced and nothing was re-sent. In 0.68.0 PreCompact runs only inside the
  history summarizer (`executePreCompactHook`, with `trigger: "auto"`
  hardcoded) and only when the current request carries hooks; the manual
  command's path does not run it. The agent still named both levels, from the
  compaction summary, which kept them by chance. Decision 0021's checkpoint has
  the same gap for a manual compaction in VS Code Local.
- An automatic compaction in VS Code Local runs no PreCompact either (session
  `b8ba763e`). A workspace setting of 70,000 tokens put the ~60,000-token base
  prompt at about 86 % of the budget, past the 78 to 82 % at which Copilot Chat
  starts a background compaction, so it compacted continuously: one prompt ran
  2,001 model requests and 99 background summarizations on Claude Opus 5.5
  over 3 h 42 min, and no checkpoint or calibration state was written. In
  0.68.0 the background compactor (`_startBackgroundSummarization`) sends its
  summary request directly and never calls `executePreCompactHook`; only the
  foreground fallback does, when a render exceeds the budget while no
  background compaction runs or waits, as when a single tool result pushes the
  context from under 78 % past 100 %. No realistic check exercises it. Never
  set the threshold below about 1.3 times the base prompt.
- **VS Code's agent host on the SDK runtime (session `b35a8857`,
  `client_name: vscode-agent-host`, a real model): re-sends after every
  automatic compaction.** Asked to read every Memory Bank file and a large
  folder in full, the session reached 169,186 to 179,511 of 200,000 tokens
  three times. Each time the runtime ran PreCompact (`trigger: auto`) as the
  compaction started, which wrote a checkpoint, and the first tool call
  afterwards re-sent the levels; later calls added nothing, and the state file
  ends at three compactions and three re-sends. The runtime summarizes in the
  background while the agent keeps calling tools, so two of the re-sends came
  before their compaction finished. They survived it: four minutes after the
  second compaction finished, the agent remarked unprompted that the hook had
  re-sent Kerberos `new` and PowerShell DSC `expert` after the compaction,
  which neither that compaction's summary nor any file it had read stated. The
  compactions were automatic, where criterion 22 names a manual one.

### Reported delivery cells, 2026-10-06 on Prox1

`tests/HookSdkRuntime.Tests.ps1` measures both cells of `Calibration.Delivery`
that are reported, not gated, in the runtime VS Code bundles and in the
standalone Copilot CLI, 8 of 8 passing. Its fixture gained a `send` step that
the fake model answers without a tool call.

- **Compaction, then no tool call:** the reply after a compaction receives no
  levels, because the compaction dropped the SessionStart text and no
  PostToolUse ran; the next successful tool call re-sends them.
- **Plugin-only installation, compaction:** the shipped `hooks.json` under
  `PLUGIN_ROOT` delivers the levels at session start from the
  LocalApplicationData profile; after a compaction nothing re-sends them,
  because no registration can exist without `~/.copilot/hooks`.

### Independent security review, 2026-10-06

`security-reviewer` reviewed `main...b7e6502` read-only: no Critical, High, or
Medium finding; the sentence carries no workspace text, email, or path, the
strict parser, the session-id path containment, the `git config` call, the
creation race, and Uninstall's ordering were found sound, and the trifecta
stays broken at leg 3. Its five Low findings and six test gaps were fixed
test-first; every new test ran red first.

| # | Finding | Resolution |
|---|---|---|
| 1 | A registration delete was not gated on the recorded hash, so a file swapped in after the ownership check would be deleted | The file is hashed again after the delete record is written; a mismatch leaves it as modified, and the record keeps the recorded hash |
| 2 | The SessionStart pre-check backtracked quadratically, and the declaration read ran outside the 3 s step cap: a hostile `projectbrief.md` added 1.3 to 1.6 s | Two linear scans; the step's stopwatch starts before the declaration read |
| 3 | `registration.json` and the registration file were read whole, without the 64 KB cap or the placeholder check | Neither is opened when it is a cloud placeholder or over 64 KB; such a record reads as invalid, such a file matches no record |
| 4 | Uninstall decided that nothing was registered before it took the profile lock | Uninstall takes the lock also when nothing is registered and holds it until the hook scripts are removed; a writer that waited then finds the script gone and registers nothing; a contributor folder Uninstall had to create is removed again |
| 5 | The working-tree guard did not follow junctions or symbolic links | Every writer resolves link targets on the path; the hooks' read keeps the literal walk, so session start pays nothing for it |

## Signed-off Design Concept

Signed off by the repository owner in chat on 2026-10-06, after an interview
that began on 2026-10-05. The interview ran at
depth Full, covering all twelve `grill-me` categories, with 26 questions (Q1 to
Q25 plus the follow-up Q10b), most carrying three to six sub-decisions, and one
security ruling after review (R1). No answer was delegated with
`not sure, you pick`, and the override log is empty. The text below is the
signed-off concept, verbatim apart from its title, its draft status header, the
sign-off annotations on the rating-question ruling and TBD-4, the sign-off
record, and Amendment 1: rulings A1 to A8 of 2026-10-06, marked in place with
their tag and listed in the *Amendment log* before *Sign-off*.

## Purpose

Phase 1 (Decision 0027) calibrates the chat to a Familiarity level per Knowledge
area, but every level is session-scoped: a contributor restates it in each new
session, and a compaction silently resets every level to `familiar` (CAL-09).
Phase 2 persists the levels in a private Contributor profile outside every
repository, so a saved level shapes later sessions without the contributor
restating it.

The promise, and its stated limits:

- **New session:** every host that runs the SessionStart hook (VS Code Local, the
  Copilot SDK host, Copilot CLI), in module, Setup, and plugin installs, on any
  machine whose profile is present.
- **After a compaction:** module and Setup installs, from the first successful
  tool call after the compaction *(A7)*. In a workspace with declared Knowledge
  areas there is
  always a Memory Bank, and Pre-flight's compaction recovery re-reads it with
  tool calls, so the levels normally return before the next reply.
- **Not covered, measured and reported:** plugin-only installs after a
  compaction, a reply that makes no tool call after a compaction, Claude Code,
  and a level stated in chat but never saved.

New Canonical term, added to the Glossary at implementation: **Contributor
profile**, the private file that stores one or more contributors' Familiarity
levels, outside every repository. Don't say: user profile, skill profile,
installation profile (that names the `-InstallationProfile` Skill selection).

## Scope

1. The Contributor profile file, schema 1, its location rule, and its strict
   validation.
2. `Add-SessionContext.ps1` (SessionStart) gains one calibration sentence.
3. `Write-CompactionCheckpoint.ps1` (PreCompact) advances a compaction counter
   in a per-session calibration state file, beside the session clock but never
   inside it.
4. A new PostToolUse script, `Add-FamiliarityContext.ps1`, registered by a
   fixed-template hook file `~/.copilot/hooks/contributor-profile.json` that
   exists only while a profile is on.
5. An optional `## Knowledge areas` section in `.memory-bank/projectbrief.md`,
   and the `memory-bank` Skill's projectbrief template.
6. A new `contributor-profile` Skill: interview, save, opt-out and opt-in,
   delete, export and import, diagnosis. One implementation in its script.
7. Five public commands in the Customization module that wrap that script.
8. One sentence in the `contributor-calibration` Instruction, one line each in
   `/simpler` and `/deeper`, and one clause in Pre-flight step 8. The
   compaction-recovery list gains no step, because re-injection is hook-driven.
9. `Uninstall-CopilotAtelier` removes an owned registration file *(A5)*; the
   `contributor-profile` Skill joins the mandatory Skills.
10. Glossary, hooks README, README, CHANGELOG, Decision record 0028.
11. Eval cases in the private kit and Pester gates in the repository.

## Non-goals

From Decision 0027 and the handoff: profiles shared across a team, levels
inferred by the AI, any cloud service, network access from hooks, and changes to
Phase 1's question rules.

Refused during this interview (Q22): Claude Code hook registration (Claude Code
gets the portable Skill only), a profile-path override for WSL or containers,
injection on every tool call or every turn, synonym or fuzzy matching of area
names, detecting Knowledge areas from repository content, levels inside
subagents, a workspace trust list, removing areas or tombstones, profile checks
in `Test-CopilotAtelier`, a GUI profile editor, restoring session-only levels
that were never saved after a compaction, and extending installation profiles
to select hooks.

## Stakeholders

| Stakeholder | Role | Interest |
|---|---|---|
| Contributor (every module and plugin user, Q2) | Owns their entry; rates, saves, opts out, deletes | States a level once; self-assessment stays private |
| Repository owner (raandree) | Maintains the code; reference scenario | OneDrive machines plus AutomatedLab/Proxmox VMs such as Prox1 (`install` account, no OneDrive, unsynced Canonical target) |
| Several people on one shared lab account | Each imports their own entry or creates one with `-NewContributor` *(A7)* | The right entry is selected; another person's levels never block theirs |
| Project maintainers | Declare Knowledge areas in `projectbrief.md` | The areas their project involves get calibrated |
| Custom agents and the default agent | Consume the sentence; run the Skill | Deterministic levels, no extra questions |
| `software-architect` | Curates the projectbrief Knowledge areas | One owner for the declaration |
| Model provider | Receives matched levels as context | Accepted, as for Phase 1 stated levels (Q17) |

## Inputs

| Input | Source and trust | Bounds | Handling |
|---|---|---|---|
| Contributor profile | Contributor-owned, cross-workspace; a prompt-injected agent may propose writes | 64 KB | Strict schema 1, whole-file rejection (Q7) |
| Hook payload: `cwd`, `session_id`, `source` | Host | Existing | No `cwd` means no calibration; never the spawn directory |
| `## Knowledge areas` in `.memory-bank/projectbrief.md` | Untrusted workspace | First 64 KB, first 16 valid bullets | Area-name rule; unmatched names never repeated by a hook (Q8, Q9) |
| `git -C <cwd> config --get user.email` | Untrusted workspace can set it; a lookup key, not proof | 2 s, killed on timeout, no prompts | Case-insensitive alias match (Q6) |
| Per-session calibration state, `<LocalApplicationData>/CopilotAtelier/sessions/session-<key>.familiarity.json` | Hooks only | Two counters | PreCompact increments `compactions`; PostToolUse records `injected`; the session clock file is never rewritten by calibration |
| Contributor answers and commands | Contributor | Per command | Same validator as the hook |
| Imported file | Any schema-1 file | 64 KB | Strict validation, then merge (Q14) |

### Location rule (Q4, Q5)

One rule, shared by every reader and writer:

1. Resolve `~/.copilot/hooks` (`USERPROFILE` before `HOME`, as the launchers
   do) to its link target. When the target's parent holds `.copilotatelier.json`,
   that parent is the Canonical target and the profile is
   `<Canonical target>/contributor/profile.json`. It syncs when the Canonical
   target sits in OneDrive.
2. Otherwise, for a plugin-only install, a remote window, a container, or a VM
   without deployment: `<LocalApplicationData>/CopilotAtelier/contributor/profile.json`.
   Import writes there, and every write there reports *saved on this machine
   only* with an export offer.

The installer never manages `contributor/`. Remote-SSH, WSL, Dev Containers, and
Codespaces run hooks on the remote side, where `~` is the remote home, so each
remote is a machine without the folder; there is no path override.

### Schema 1 (Q7, Q14)

| Field | Type | Rule |
|---|---|---|
| `schemaVersion` | integer | Exactly `1` |
| `contributors` | array | 1 to 16 entries |
| `contributors[].id` | string | An immutable GUID created with the entry; unique; the merge and selection key |
| `contributors[].default` | boolean | At most one `true` |
| `contributors[].state` | `on` or `off` | `off` is the sticky, reversible opt-out; levels are kept |
| `contributors[].stateUpdatedUtc` | ISO 8601 UTC | Merge key for `state` |
| `contributors[].interviewSnoozedUntilUtc` | ISO 8601 UTC or `null` | Global per entry, never per project |
| `contributors[].aliases` | array of strings | 0 to 8 emails; unique case-insensitively across all entries, so one alias selects at most one entry |
| `contributors[].areas` | object | 0 to 200 properties `<name>`: `{ level, updatedUtc }` |
| `areas.<name>.level` | `new`, `familiar`, or `expert` | Exact lowercase |
| `areas.<name>.updatedUtc` | ISO 8601 UTC | No future-date check (Q16) |

No free-text field exists: no notes, no language, no nationality. Every field
is required, `interviewSnoozedUntilUtc` as `null` when unset *(A7)*. Any
unknown property, missing field, wrong type, unknown level, other schema
version, exceeded cap, case-only duplicate area name, or name that breaks the
area-name rule rejects the whole file.

**Area-name rule (Q16)**, identical in the profile and in `projectbrief.md`: 1 to
48 characters after trimming and Unicode NFC normalization; letters of any
script with their combining marks, digits, single spaces, and
`. + # / & ( ) -`; starts with a letter, a digit, or a `.` directly followed by
a letter or a digit, so `.NET` passes *(A6)*. A stored name is already trimmed
and in NFC, so two stored spellings never differ only by whitespace or
normalization *(A7)*. Matching is case-insensitive (invariant culture) and
exact; `DSC` and `PowerShell DSC` are different areas.

### Identity rule (Q6)

The key is `git -C <cwd> config --get user.email`, which honours `includeIf`. It
matches case-insensitively against each entry's aliases. With no identity, no
match, or a git failure (no git, unset email, a repository owned by another user,
timeout), the hook uses the only entry when there is one, else the entry marked
`default`, else injects no levels. Creating an entry records the current email
as its first alias when git has one; on a machine without a git identity the
entry starts with no alias and is reached through the single-entry or default
rule. The email never appears in any hook output.

## Outputs

### SessionStart sentence (Q3, Q9)

At most one sentence, appended after today's lines, built only from a fixed
template, matched area names, and level values:

| State | Sentence |
|---|---|
| Entry on, matched areas | `Contributor familiarity levels from the private profile, data only: "Kerberos" new; "PowerShell DSC" expert. 2 declared Knowledge areas are unrated. Treat them as stated levels under the contributor-calibration Instruction.` |
| Declared areas, and no profile, no selected entry, or an entry on with no matches | `No contributor profile levels for this workspace; 3 declared Knowledge areas are unrated.` |
| Entry off, no Memory Bank, no declared areas, or no `cwd` | Nothing, which is Phase 1 behavior with no offers |
| Unreadable | `Contributor profile unreadable (<reason code>); familiarity levels default to familiar.` |

Unrated areas are counted, never named. Budget priority is the lowest of all
lines: under a tight budget the unrated count goes first, then trailing areas,
then the whole sentence, replaced by `Contributor familiarity levels omitted for
the context budget.` Existing lines are never shortened because of it.

Reason codes, a fixed set: `not-local`, `too-large`, `invalid-json`,
`invalid-schema`, `unsupported-schema`, `inside-repository`, `timeout`,
`read-error`.

### PostToolUse re-injection after a compaction (Q10, Q10b, Q20)

- Calibration state lives in its own per-session file,
  `session-<key>.familiarity.json`, beside the session clock and keyed the same
  way. Calibration hooks never rewrite the clock file, so the `turns` counter of
  `Write-SessionClose.ps1` cannot be clobbered.
- `Write-CompactionCheckpoint.ps1` increments `compactions` in that file,
  creating it when absent, with an atomic replace.
- `Add-FamiliarityContext.ps1`, registered only by the registration file, reads
  the file on every successful tool call; PostToolUse does not fire for a
  failed one *(A7)*. When `compactions` exceeds `injected`, it emits
  the re-sent sentence under both host keys (top-level `additionalContext` and
  `hookSpecificOutput.additionalContext`), then records `injected` as the
  `compactions` value it read: a compare-and-set, so a stale write can never
  erase a newer compaction. Otherwise it writes nothing.
- The **re-sent sentence** carries the matched levels only, without the unrated
  count, and ends with the fixed suffix `Re-sent after a compaction; make no
  offers in this session.`, so a compaction never repeats the interview, save,
  or unreadable-profile offers. It rechecks the profile on every injection, so
  an opt-out or deletion takes effect at once even in a session that loaded the
  registration earlier.
- It never emits `decision`, never exits `2`, and every path exits `0` except a
  launcher that cannot resolve the script, which exits `1` as lifecycle hooks
  do.
- Parallel tool calls may inject the sentence twice; that is accepted.

### Registration file (Q20, Q24)

`~/.copilot/hooks/contributor-profile.json` holds one PostToolUse entry with the
three launchers of `hooks.json`, pointing only at the shipped script. Its bytes
are a shipped template; no input reaches them, and its path is fixed, never
read from any record. The writer creates it when the profile gains an entry that
is `on` and rates at least one area, and removes it when no such entry remains;
with no levels there is nothing to re-inject.

Ownership follows the Deployment record's pattern:

1. The writer takes the profile lock, then writes a pending registration record
   (`<contributor folder>/registration.json`) naming the operation, before it
   creates, replaces, or deletes the file; it records the file's SHA-256 and
   completes the record afterwards. Reconciliation compares the record with the
   observed file, never infers from a partial view, and never rewrites a
   record *(A8)*: a create record, pending or complete, whose file is absent is
   pending, because on OneDrive machines the file may still be on its way; a
   delete record whose file is absent is finished and may be cleared; a file
   that matches the recorded hash is owned. A pending registration is reported
   by `Get-`, left alone by writers, a stop for Uninstall, and cleared only by
   `Remove-CopilotAtelierContributorProfile -RegistrationOnly`, which confirms
   first.
2. A file is owned when all three hold: it sits at the fixed path, the record
   says this writer created it, and its current SHA-256 equals the recorded
   hash, whichever shipped template it came from. Only an owned file is ever
   deleted or replaced *(A5)*.
3. A writer that finds an owned file whose bytes differ from the current
   template replaces it with the current template under the same two-phase
   record, for example as a delete followed by a create, so a launcher fix
   reaches every registration at the next write. On the machine that performs
   it, every crash point of a replacement ends owned, outdated, pending, or
   none, never modified, and `Get-` reports an owned file from an earlier
   template as outdated *(A5, A8)*.
4. A file at the fixed path without a record is never overwritten or deleted,
   even when its bytes match the template; the writer reports it.
5. `Uninstall-CopilotAtelier` takes the same lock and reconciles the registration
   before it removes any file. When the registration cannot be reconciled (a
   modified file, a foreign file, a pending registration *(A8)*, or a held
   lock), Uninstall stops before removing anything and names the file, because
   removing the Owned script would leave a hook that warns on every tool call.
   It reads only the record, never levels.
6. No release payload may ship `hooks/contributor-profile.json`.

**Load timing.** VS Code and the SDK host load hook files when a session starts,
and an open chat keeps what it loaded. Creating, removing, or repairing the
registration therefore changes the per-call cost only for sessions started
afterwards. Already-open sessions keep calling the script, which then finds no
active entry and injects nothing. After Uninstall, open chats must be restarted,
which already holds for every shipped hook.

**Shared accounts.** The registration is per machine profile, not per entry.
One person's opt-out stops the per-call cost only when no other entry on that
machine is on and rates an area.

**Repair.** When the profile is deleted by hand, unreadable, or of an
unsupported schema while a registration remains, `Get-` reports an orphaned
registration, and `Remove-CopilotAtelierContributorProfile -RegistrationOnly`
removes it under the ownership rule above, whatever template it came from
*(A5)*. The same command clears a pending registration that never settles,
such as one left by a crash between the record and the file *(A8)*.

Known limit: a plugin-only install has no `~/.copilot/hooks/scripts`, so the
registration cannot resolve the script. Plugin-only users get SessionStart
levels but no re-injection after a compaction.

Known limit *(A8)*: on machines that share a OneDrive Canonical target, two
machines that act before either has synced can leave a conflict copy of the
registration in the hooks folder, which the hosts load as a second hook, or,
when one of them runs Uninstall, a registration whose scripts are gone, which
warns on every tool call. No local check can see an operation that has not
synced. `Get-` lists the conflict copy or the orphaned registration and names
the file to delete.

### Offers (Q11, Q12, Q15)

- **Interview offer:** at most once per session, as one line at the end of the
  first substantive reply, after the task's content and before POST-FLIGHT;
  only when the sentence reports unrated declared areas and the entry is not
  snoozed; never in a Q&A turn, a non-interactive run, or a subagent. Choices:
  *rate now*, *not now* (snooze 14 days on the entry), *turn the profile off*.
  When no entry exists yet, *not now* and *turn the profile off* create a
  minimal one (a new `id`, the current email as alias when git has one, no
  areas) so the choice is remembered; an entry without areas never creates the
  registration file.
- **Rating questions:** one per unrated area, with the choices new, familiar,
  expert, or skip, read from `projectbrief.md` and validated by the area-name
  rule, then one preview and one write.
- **Save offer:** after a level changes through words, `/simpler`, or `/deeper`,
  at most once per area per session, only when this session received a
  contributor-profile sentence and only for a declared area: `Save Kerberos =
  new to your profile? (yes / no)`.
- **Rating and save questions are not technical decision questions.** They offer
  no `not sure, you pick` option. A contributor who writes the phrase gets
  *skip* or *no*, because Decision 0027 rules out levels inferred by the AI.
  This is the architect's ruling, accepted at sign-off; it leaves Phase 1's
  question rules unchanged.
- **Unreadable profile:** the agent mentions it once per session, at the end of
  the first reply, with the reason code and the `Get-` command.

### Pre-flight clause (Q21)

The PRE-FLIGHT acknowledgment names the profile state as counts only, for
example `profile: 3 levels, 2 unrated`, `profile: unreadable (invalid-json)`, or
`profile: none` when the session context carries no sentence.

### Commands (Q13, Q14)

| Command | Behavior |
|---|---|
| `Get-CopilotAtelierContributorProfile [-WorkspacePath] [-ShowAliases]` | Location, synced or this machine only, selected entry and why, levels, the exact sentence for the workspace, possible conflict copies of the profile and of the registration *(A8)*, an orphaned, pending, or outdated registration *(A5, A8)*; aliases masked (`r***@contoso.com`) unless `-ShowAliases` |
| `Set-CopilotAtelierContributorProfile` | Paired `-KnowledgeArea` and `-Level` arrays for one preview and one write, unequal lengths failing before any write *(A7)*; `-State On\|Off`, `-AddAlias`/`-RemoveAlias`, `-Default`; `-NewContributor` creates the caller's own entry *(A7)*; manages the registration file |
| `Export-CopilotAtelierContributorProfile -Path [-Contributor]` | Writes a schema-1 file; refuses a destination inside a git working tree |
| `Import-CopilotAtelierContributorProfile -Path` | Strict validation, then merge; `-WhatIf` previews |
| `Remove-CopilotAtelierContributorProfile [-Contributor] [-RegistrationOnly]` | Deletes an entry, the file, or only an orphaned or pending registration *(A8)*; `ConfirmImpact = 'High'`; removes a registration file only under the ownership rule *(A5)* |

`-Contributor` accepts an `id` or an alias and must resolve to exactly one entry;
anything else fails before any write.

**Write selection (A7):** a write that changes one entry, through `Set-` or
the Skill script's interview, save, and opt-out, goes only to a positively
chosen target: the entry `-Contributor` names; else the entry whose alias
matches the git email; else a new entry, either the first one when no profile
exists or one that `-NewContributor` creates. `-NewContributor` excludes
`-Contributor` and gives the entry a new `id`. Because the hooks reach an
entry only by alias, as the only entry, or as the default, a new entry beside
others must be reachable: it takes the git email as its first alias, or the
alias that `-AddAlias` gives in the same call, or becomes the default through
`-Default`; without one of them it fails before any write and explains that
the hooks select entries by git email. It also fails when its alias already
belongs to an entry, and at the 16-entry cap; when its only alias is not the
email git reports here, its preview says that the hooks reach it only where
git reports that alias. Every other case, a single entry with no git email
included, writes nothing and names `-Contributor`, `-NewContributor`, and
Import. When the target is unclear, the Skill asks once per session, offering
the contributor's entry, a new entry of their own, or Import, and uses the
answer for the rest of the session. The identity rule still governs what the
hooks read. The snooze is set only by the Skill script's `-SnoozeInterview`,
which the interview's *not now* runs; the five commands do not expose it.

**Merge (Q14):** an imported entry matches the local entry with the same `id`,
else the one entry that shares an alias with it. When its aliases point to two
different local entries, when an alias would belong to two entries afterwards, or
when any union would exceed a cap, Import refuses the whole file and writes
nothing. An unmatched entry is added up to the cap. Per area, the newer
`updatedUtc` wins, an equal one keeps the local value, and an area on one side
only is kept. `state` follows the newer `stateUpdatedUtc`; the later snooze wins;
aliases form a union; `default` stays local. Only `profile.json` is ever read as
the profile; other `*.json` files in the folder are listed as possible conflict
copies and are never deleted automatically.

**Writes (Q15):** a lock file, a temporary file, and an atomic replace; a lock
not acquired within 5 seconds writes nothing and fails clearly. Every write on a
Windows OneDrive path pins the file (`attrib +P`).

## Quantified requirements

```text
Tag: Calibration.Persistence
Type: Quality Requirement
Gist: A saved Familiarity level shapes later replies without being restated.
Stakeholder: Contributor
Scale: Percent of eval samples in which a level saved earlier shapes the reply
       without the contributor restating it, with the sentence at [Position]:
       session start, or after a tool result following a compaction.
Meter: Persistence cases in the private eval kit, at least 6 per Position,
       mined from real restatements; K = 3; pinned gpt-5.5 judge; compared arms
       run together.
Past [Phase 1]: 0 % <- Decision 0027, CAL-09 (levels are session-scoped)
Goal [Phase 2 release, each Position]: 100 % pass^3 <- Interview Q1, 2026-10-05
Fail: below 90 % of samples <- Interview Q1
Authority: Repository owner

Tag: Calibration.Delivery
Type: Quality Requirement
Gist: The sentence reaches the model's context wherever the promise applies.
Stakeholder: Contributor
Scale: Cells of [Host: VS Code Local, Copilot SDK host, Copilot CLI] x
       [Install channel: module or Setup, plugin] x
       [Event: new session, compaction then a tool call, compaction then no
       tool call] in which the sentence reaches the context.
Meter: Pester through each launcher; the SDK runtime probe
       (session.rpc.tools.execute, hook.end); one manual check each in VS Code
       Local and Copilot CLI; recorded in Decision record 0028.
Past: no cell <- Phase 1
Goal: every cell inside the Purpose's promise <- Review finding 2
Report, not gate: plugin x compaction, and compaction then no tool call
Authority: Repository owner

Tag: Calibration.PhaseOneGuard
Type: Quality Requirement
Gist: Phase 1 behavior survives a profile sentence in context.
Scale: Passing samples of the 17 Phase 1 cases with a sentence present.
Meter: Phase 1 eval cases, K = 3, the same frozen grader and judge.
Past: 51 of 51 <- Decision 0027
Goal: 51 of 51 <- Interview Q1
Fail: below 51 of 51

Tag: SessionStart.AddedLatency
Type: Resource Requirement
Scale: p95 over paired replicates of the session-start hook's added time, in
       no-op hook launches, under [Host spawn] and [Profile: one entry, none,
       two entries]. Each replicate's value is the time with declared areas
       minus the time without a declaration, divided by that replicate's
       launch of a fixed no-op hook through the same launcher and spawn. (A1)
Meter: tests/Fixtures/Measure-CalibrationLatency.ps1: 2 warm-up replicates,
       then 20 measured replicates, each running the baseline, every subject,
       the no-op hook, and the push guard back to back in rotated order
       through the host's exact spawn, process start included; nearest-rank
       p95; on Prox1 and RAANDREE3; recorded in Decision record 0028. A value
       at or below Budget meets it, a value above Fail fails, and a verdict
       above Budget or Fail counts only when a second Meter run reproduces it.
       The push guard is reported, not used as the unit. (A1)
Past [VS Code spawn, Prox1, one entry]: 0.53 to 0.61 launch (p50 0.48 to 0.50)
Past [SDK spawn, Prox1, one entry]: 0.35 to 0.45 launch (p50 0.31)
Past [VS Code spawn, Prox1, none]: 0.25 to 0.39 launch (p50 0.20 to 0.21)
Past [SDK spawn, Prox1, none]: 0.18 to 0.27 launch (p50 0.15 to 0.16)
Past [VS Code spawn, Prox1, two entries]: 0.65 to 0.85 launch
Past [SDK spawn, Prox1, two entries]: 0.44 to 0.49 launch
       <- amended Meter, two runs on 2026-10-06, p95 of 20 paired
       replicates; the no-op launch measured p50 778 to 790 ms (VS Code) and
       1,014 to 1,042 ms (SDK)
Past [VS Code spawn, RAANDREE3, one entry]: 0.27 to 0.38 launch (p50 0.25 to 0.26)
Past [SDK spawn, RAANDREE3, one entry]: 0.43 to 0.71 launch (p50 0.37 to 0.38)
Past [VS Code spawn, RAANDREE3, none]: 0.12 to 0.16 launch (p50 0.10)
Past [SDK spawn, RAANDREE3, none]: 0.21 to 0.28 launch (p50 0.18 to 0.19)
Past [VS Code spawn, RAANDREE3, two entries]: 0.36 to 0.51 launch
Past [SDK spawn, RAANDREE3, two entries]: 0.55 to 0.84 launch
       <- amended Meter of b7e6502, two runs on 2026-10-06; the no-op launch
       measured p50 1,916 to 1,973 ms (VS Code) and 1,039 to 1,144 ms (SDK)
Budget [one entry, none]: 0.5 launch <- Ruling A2, 2026-10-06
Fail [one entry, none]: 1.0 launch <- Ruling A2, 2026-10-06
Report, not gate: [two entries], where the identity rule runs git <- Ruling A2
Rationale: Paid once per chat, only where a workspace declares Knowledge
       areas, by contributors who accept one launch per tool call (Q20). At
       Fail the hook costs a whole extra launch; fallback A costs more, a tool
       call plus a model round trip.
Assumption: The reader's cold cost scales with the launch cost, both being
       cold PowerShell start-up; RAANDREE3 tests it (TBD-5).
Risk: A lighter shared launcher shrinks the unit and raises this ratio without
       any regression; re-run the Meter and re-baseline when a launcher in
       hooks.json changes.
Authority: Repository owner

Tag: PostToolUse.CallLatency
Type: Resource Requirement
Scale: p95 over paired replicates of one non-injecting PostToolUse hook's
       time divided by the same replicate's no-op hook launch, under
       [Host spawn]. (A1)
Meter: As SessionStart.AddedLatency.
Past [VS Code spawn, Prox1]: 1.09 to 1.12 launch (838 to 884 ms)
Past [SDK spawn, Prox1]: 1.08 to 1.10 launch (1,094 to 1,152 ms)
       <- amended Meter, two runs on 2026-10-06, p95 of 20 paired
       replicates; the push guard read 1.18 to 1.26 (VS Code) and 1.11 to
       1.16 (SDK) launch
Past [VS Code spawn, RAANDREE3]: 1.05 to 1.06 launch (2,067 to 2,198 ms)
Past [SDK spawn, RAANDREE3]: 1.11 to 1.25 launch (1,155 to 1,389 ms)
       <- amended Meter of b7e6502, two runs on 2026-10-06; the push guard
       read 1.13 to 1.16 (VS Code) and 1.14 to 1.31 (SDK) launch
Budget: 1.1 launch <- Ruling A3, 2026-10-06
Fail: 1.25 launch <- Ruling A3, 2026-10-06
Rationale: The common path reads the payload head, runs one regex, and checks
       one file, so it costs barely more than a no-op launch, within the
       Meter's noise; above 1.25 the script's own work has become significant.
Assumption: Only machines with a profile that is on pay it (Q20).
Authority: Repository owner

Tag: Context.SentenceSize
Type: Resource Requirement
Scale: Characters of the calibration sentence at [Position: session start,
       re-sent after a compaction].
Meter: Pester fixtures for the worst case (16 names of 48 characters at
       familiar) and a typical case (5 areas).
Past: 0; existing context 615 of 4,096 <- measured 2026-10-05
Past [worst, fixed template]: 1,118 at session start, 1,178 re-sent
       <- tests/ContributorProfileReader.Tests.ps1, 2026-10-06
Budget [worst, either Position]: 1,200 <- Ruling A4, 2026-10-06
Budget [typical]: 300 <- Interview Q9, Q18

Tag: Instruction.Size
Type: Resource Requirement
Scale: Characters and lines of the contributor-calibration Instruction.
Meter: tests/ContributorCalibration.Tests.ps1.
Past: 3,763 characters, 48 lines <- measured 2026-10-05
Budget: 4,096 characters, 60 lines, caps not raised <- Interview Q18
```

Conditions (Q18): profile at most 64 KB, 16 entries, 8 aliases, and 200 areas
per entry; `projectbrief.md` read up to 64 KB and 16 bullets; calibration step
within 3 s; git within 2 s.

## Design options and recommendation

### Injection scope (Q3)

| Option | Privacy | Persistent injection | Repositories without a Memory Bank | Verdict |
|---|---|---|---|---|
| **A: only declared and rated areas** | Minimal | Broken: a planted name resurfaces only where declared | Phase 1 behavior | **Chosen** |
| B: whole profile, 16 areas, everywhere | Full self-assessment in every chat | Live in every workspace (OWASP LLM01) | Calibrated | Rejected |
| C: A plus contributor-marked areas everywhere | Partial | Narrowed | Partly calibrated | Deferred; additive later |

### Compaction coverage (Q10, Q10b)

Impact on `Calibration.Persistence` after a compaction, from Past 0 % toward
Goal 100 %. These are architect estimates, not measurements; the credibility
column rates them from 0.0 to 1.0.

| Option | Impact | Credibility | Per-call cost | Tokens per compaction | Notes |
|---|---|---|---|---|---|
| A: Skill reader on compaction recovery | 70 % ± 20 | 0.3 | none | 1 sentence + 1 command | Depends on the model noticing the compaction |
| **B1: PostToolUse after a PreCompact counter** | 90 % ± 10 | 0.5 | ~0.6 s VS Code, ~0.85 s SDK, profile users only | 1 sentence | Misses a reply that makes no tool call after compaction; Pre-flight's compaction recovery makes tool calls in every workspace that declares areas |
| B2: B1 plus every turn | 95 % ± 5 | 0.5 | same | 1 sentence per turn | More tokens |
| B3: inside the push guard | 90 % VS Code, unknown SDK | 0.3 | none | 1 sentence | Couples calibration to the security guard |
| C: generated Instruction file | 95 % | 0.6 | none | full levels every request | Breaks scope A; managed folder; loads twice in SDK chats |
| D: accept the gap | 0 % | 0.9 | none | none | Fails the Goal |

The architect recommended A on cost. The contributor chose B1 for deterministic,
hook-driven delivery; Q20 then limited its per-call cost to machines with a
profile that is on. A remains the fallback if B1 reaches the Fail level of
`PostToolUse.CallLatency` on Prox1 or RAANDREE3 *(A3)*.

### Location (Q4)

Following the hooks link (chosen) needs no installer change and survives a
custom `-TargetPath`. A fixed `~/.copilot/contributor` linked by the installer
would add a sixth Discovery link to create, verify, remove, and reconcile.

### Durable choices and their reversibility

| Choice | Reversibility |
|---|---|
| Schema 1 fields (including `id` and global alias uniqueness) and the area-name rule | Tightening breaks existing files. Loosening is safe only for old files read by new code: an older release rejects a profile that uses the looser rule as `invalid-schema`, so after the first release any loosening needs schema 2 *(A6)* |
| Location under `contributor/` | Movable only with a migration step |
| Five public command names | Public API; renaming needs deprecation aliases |
| `## Knowledge areas` in `projectbrief.md` | Moving it later touches every project's Memory Bank |
| Registration file name, reserved in payloads | Changing it needs a migration of existing registrations |
| Registration ownership through the recorded hash | A template change needs no migration: the next writer replaces each owned registration *(A5)* |

### Delivery increments

1. **Spike (TBD-1):** whether the SessionStart text survives a compaction in
   VS Code Local and the SDK host; prove the PostToolUse `additionalContext`
   contract in the SDK runtime; confirm that both hosts load a second `*.json`
   file from `~/.copilot/hooks` and when they reload it. Value: confirms B1's
   carrier before code.
2. **Profile core:** schema, validator, location rule, identity rule, Skill
   script, five commands, and the drift-test fixture set.
3. **SessionStart sentence and Knowledge areas:** hook change, projectbrief
   section, template, Pre-flight clause. Value: persistence across sessions.
4. **Compaction re-injection:** PreCompact counter, calibration state file,
   PostToolUse script, registration file and its two-phase record, Uninstall
   reconciliation. Value: CAL-09 fixed.
5. **Offers:** Instruction sentence, Prompt lines, interview and save flows.
6. **Measurement:** eval groups 1 to 4, the delivery matrix, the latency Meter,
   live proofs.

## Failure modes

| Failure | Behavior |
|---|---|
| Cloud-only OneDrive placeholder | Attribute check only; `not-local`; no download |
| File over 64 KB | `too-large`, never read in full |
| Unparseable, invalid, or newer schema | `invalid-json`, `invalid-schema`, or `unsupported-schema`; familiar levels; writers refuse to overwrite a newer schema |
| Profile path inside a git working tree | `inside-repository`; every writer refuses |
| git missing, slow, refused, or hostile `include.path` | 2 s cap, killed; identity fallback |
| Calibration step slower than 3 s | `timeout`; no levels |
| No `cwd` in the payload | No calibration |
| Lock not acquired within 5 s | The writer fails clearly and writes nothing |
| Calibration state file missing or unreadable | PreCompact creates it; when it cannot, no re-injection after that compaction |
| Two calibration hooks write the state file at once | Atomic replace and compare-and-set; at worst a duplicate sentence, never a lost compaction or a clobbered clock |
| Ambiguous or over-cap import | Import refuses the whole file and writes nothing |
| Crash between the registration record and the file | A delete record without its file is cleared; a create record without its file stays pending, Uninstall stops on it, and `-RegistrationOnly` clears it *(A8)* |
| Record and registration file arriving through OneDrive in either order | Pending, foreign, or modified until both arrive; nothing acts on the partial view, and Uninstall stops on it *(A8)* |
| Two machines sharing the Canonical target act before either syncs | A conflict copy in the hooks folder, or after an Uninstall a registration whose scripts are gone; documented, reported by `Get-`, repaired by deleting the named file *(A8)* |
| Foreign or modified registration file | Never overwritten or deleted; reported; Uninstall stops before removing anything |
| Owned registration from an earlier template | `Get-` reports it as outdated; the next writer replaces it; opt-out, `Remove- -RegistrationOnly`, and Uninstall delete it *(A5)* |
| A write without a positively chosen target | Nothing is written; the command names `-Contributor`, `-NewContributor`, and Import, and the Skill asks once per session *(A7)* |
| Registration left behind by a deleted or unreadable profile | `Get-` reports it; `Remove- -RegistrationOnly` removes it |
| Registration script unresolvable in an open session | Launcher exits `1`, a warning, until the chat restarts; Uninstall reconciles first |
| Any hook fault | Exit `0`, session never blocked, profile never written by a hook |

## Edge cases

- Several people on one account: each imports an entry; the email selects;
  without a match the single or default entry applies, so another person's
  levels may apply, and a stated level corrects that for the session. One
  person's opt-out stops the per-call cost only when no other entry is on.
- A machine without a git identity: an entry with no alias, reached through the
  single-entry or default rule.
- One person with several emails or `includeIf` folders: aliases.
- A workspace without a Memory Bank or declared areas: nothing is read or run.
- Unicode names such as `Mietrecht` pass; quotes, backticks, `; = < > * _`, and
  control characters fail. `.NET` passes; `.`, `..`, and `. NET` fail *(A6)*.
- A second person on a shared account whose git email matches no entry, or who
  has none: the hooks still read by the identity rule, but a write needs a
  positively chosen target, and `-NewContributor` creates their own entry
  without a prior export. The hooks reach that entry only through a git email
  that differs from the other person's, for example through `includeIf`, or
  as the default; where both share one git identity, the identity rule cannot
  tell them apart *(A7)*.
- Machines with skewed clocks: the fast clock wins merges for a while;
  documented, not rejected.
- Multi-root workspace: the payload's `cwd` only.
- Parallel tool calls after a compaction: a duplicate sentence, accepted.
- A level stated in chat but never saved reverts after a compaction.
- An empty profile (no areas) is valid.

## Security

Lethal-trifecta review with `agent-security-review` (Q17):

| Component | Private data | Untrusted content | Outbound channel | Result |
|---|---|---|---|---|
| Hooks (SessionStart, PostToolUse, PreCompact) | Profile | `projectbrief.md`, repository git config | None: no network, `git config --get` runs no repository code | Broken at leg 3 |
| Session after injection | Matched levels only | Workspace, web | Agent tools | Present; residual Low |
| Writer via the agent | Profile | Conversation | Approved terminal call | Integrity only; residual Low |

Controls:

- Minimization: only declared and rated areas; never an email, a path, an
  unmatched name, or file content (LLM02).
- Template-only sentences with quoted names framed as data, the strict
  area-name rule, and no free-text fields (LLM01).
- Writes only through the Skill's script as a terminal call the contributor
  approves, with a preview (LLM06).
- `Get-` masks aliases by default, because agent-run output enters the model's
  context.
- Export and every writer refuse a destination inside a git working tree.
- The registration file is a fixed template at a fixed path, deleted or
  replaced only when the record and the recorded hash agree, and a replacement
  writes only the current shipped template; a record can never redirect a
  deletion *(A5)*.
- The edit-approval guidance for hook scripts extends to
  `skills/contributor-profile/scripts/`.

Residual risks, accepted as Low by ruling R1 after the independent review
reopened them:

1. A hostile repository declares up to 16 common names to get the matching
   levels into its session, where its content may try to exfiltrate them.
2. A prompt-injected agent writes a level or a name, either through an approval
   the contributor does not read or through an auto-approve setting; an
   approved terminal call is not an enforced authorization boundary.
3. Matched levels reach the model provider, as Phase 1 stated levels already do.

Why Low: a matched name reaches the hook's sentence only in a workspace that
itself declares that exact string, so a planted name gains no reach beyond a
workspace that already contains it. What remains for an attacker is the hook's
framing of at most 48 characters of restricted grammar per name, and a probe of
at most 16 self-assessed preferences. A trust list would close residual 1 but
would record which projects the contributor works in, which Q17 rejected;
out-of-band confirmation would close residual 2 at one manual step per save.

## Performance

See `SessionStart.AddedLatency`, `PostToolUse.CallLatency`,
`Context.SentenceSize`, and `Instruction.Size`. Without declared areas the
SessionStart hook neither reads the profile nor runs git. The per-call cost
exists only in sessions started while a registration file exists.

## Observability

- `Get-CopilotAtelierContributorProfile -WorkspacePath .` prints the exact
  sentence: the 30-second check.
- The PRE-FLIGHT acknowledgment names counts only.
- Hooks write reason codes only to the hook output channel, never levels or
  emails.
- The SDK host's `events.jsonl` `hook.end` event records the injected text
  locally.
- No telemetry; the private eval is the measurement.

## Rollback

- Opt-out (`state: off`) stops injection and offers at once. It removes the
  per-call cost for sessions started afterwards, and only when no other entry on
  the machine is on and rates an area. Levels are kept; opting back in restores
  them.
- `Remove-CopilotAtelierContributorProfile` deletes an entry, the file, or only
  an orphaned or pending registration, the registration under the ownership
  rule *(A5, A8)*.
- `Uninstall-CopilotAtelier` keeps the profile as personal content, reconciles
  and removes an owned registration first, whatever template it came from
  *(A5)*, and stops before removing anything when it cannot. Open chats must be restarted afterwards, as for every
  shipped hook.
- A release rollback leaves profile files unused and harmless; an unknown
  schema version degrades to familiar.

## Acceptance criteria

1. The hook, the Skill script, and all five commands resolve the same profile
   path for one fixture set, following the location rule.
2. Every schema violation in a shared fixture set (at least one per rule) yields
   no levels and exactly one reason code in every entry point; a valid fixture
   yields identical levels in every entry point. The set holds `.NET` as a
   valid name and `.`, `..`, and `. NET` as invalid ones *(A6)*.
3. No hook output contains file bytes other than matched area names and level
   values, and never an email, a path, or an unmatched workspace name.
4. A profile path with a `.git` ancestor yields `inside-repository`, and every
   writer and Export refuse it.
5. A file with the recall-on-data-access, recall-on-open, or offline attribute
   is never opened for reading; the hook reports `not-local`.
6. The identity rule selects the matched, single, or default entry as specified,
   and git is killed after 2 s.
7. The hook reads only the `## Knowledge areas` section, at most 64 KB and the
   first 16 valid bullets, and ignores invalid bullets.
8. The SessionStart sentence matches the Outputs table in every state, and
   degrades in the stated order without shortening any existing line.
9. Without declared areas, the SessionStart hook neither reads the profile nor
   runs git.
10. PreCompact increments `compactions` in the calibration state file; the first
    PostToolUse after it emits the re-sent sentence under both host keys and
    records `injected` by compare-and-set; other calls emit nothing; a test that
    interleaves a stale PostToolUse write with a newer PreCompact never loses
    the newer compaction; no calibration hook rewrites the session clock file;
    neither hook emits `decision` or exits `2`.
11. The registration file exists exactly while an entry is on and rates at
    least one area. A file this writer creates matches the shipped template
    byte for byte, and the next writer replaces an owned file from an earlier
    template with the current one. Its record is written as pending before the
    file changes and reconciled after a simulated crash at each step, the
    steps of a replacement included, to owned, outdated, pending, or none,
    never to modified. A file is deleted or replaced only when the fixed path,
    the record, and the recorded hash agree; a foreign or modified file is
    reported and never touched. A test that changes the template proves that
    opt-out, `-RegistrationOnly`, and Uninstall still remove an owned
    registration *(A5)*. A test delivers the record and the file in every
    order a second machine can see them through OneDrive, and proves that no
    reconciliation rewrites a record, no writer acts on the partial view, and
    Uninstall stops on it *(A8)*.
12. No release payload contains `hooks/contributor-profile.json`.
13. The `contributor-calibration` Instruction carries the save-offer rule within
    4,096 characters and 60 lines; `/simpler` and `/deeper` carry the save-offer
    line; Pre-flight step 8 names profile counts only.
14. Rating and save questions offer no `not sure, you pick`, and a delegated
    reply saves nothing; the re-sent sentence after a compaction carries no
    unrated count and suppresses every offer for the rest of the session.
15. The five commands have comment-based help and unit tests that satisfy the
    QA suite; every writing command supports `-WhatIf`; Remove- uses
    `ConfirmImpact = 'High'`; Get- masks aliases unless `-ShowAliases`;
    `-Contributor` that does not resolve to exactly one entry fails before any
    write. Every writer follows the write-selection rule, with one test per
    branch: a single entry without a git email, and an unmatched git email,
    write nothing without a positively chosen target; `-NewContributor`
    creates a second entry without a prior export, the identity rule selects
    it in a later session, and it fails without a reachable alias or
    `-Default` and together with `-Contributor`. Unequal `-KnowledgeArea` and
    `-Level` arrays fail before any write *(A7)*.
16. Import applies every merge rule, with one fixture per rule, and refuses the
    whole file, writing nothing, for an ambiguous match, a duplicated alias, or
    a cap overflow.
17. Writers use a lock, a temporary file, and an atomic replace; a 5 s lock
    timeout writes nothing.
18. The `contributor-profile` Skill is mandatory in every installation profile.
19. Install, Update, and `-Repair` never read or write `contributor/`.
    Uninstall reads only the registration record, takes the profile lock,
    reconciles the registration before removing any file, and stops with the
    file named when it cannot.
20. The latency budgets hold on Prox1 and RAANDREE3 per the Meter as amended:
    no-op hook launches as the unit, 20 paired replicates in rotated order,
    inclusive thresholds, and a verdict above Budget or Fail reproduced in a
    second run; the two-entry cell and the push guard are reported, and the
    results are recorded in Decision record 0028 *(A1 to A3)*.
21. Eval: `Calibration.Persistence` 100 % pass^3 at each Position; Phase 1 51 of
    51 with a sentence present; the offer and safety groups meet the same gates
    (TBD-4, resolved at sign-off).
22. `Calibration.Delivery`: every cell inside the promise delivers the sentence,
    and the two reported cells are measured and recorded. The SDK runtime probe
    shows the PostToolUse `additionalContext` reaching the model and the
    `sessionStart` `hook.end` event carrying the sentence; one manual
    compaction each in VS Code Local and Copilot CLI shows the re-injection.
23. The Glossary defines Contributor profile; the hooks README, README, and
    CHANGELOG describe the change; Decision record 0028 is accepted and indexed.
24. A test runs every writer against a temporary git repository and proves that
    no Familiarity level lands under a git working tree.
25. Every script that derives the session clock path (SessionStart, Stop,
    PreCompact, PostToolUse, and the elapsed reader) derives the same path for
    one shared fixture set.

## Open questions

| ID | Question | Owner | Effect |
|---|---|---|---|
| TBD-1 | Does the first SessionStart text survive a compaction in VS Code Local and the SDK host? | software-engineer, spike before increment 2 | Only how often PostToolUse is the sole carrier |
| TBD-2 | What OneDrive names a conflict copy | software-engineer, observed once on two machines | None; only `profile.json` is read |
| TBD-3 | Exact wording of the Instruction, Pre-flight, and Prompt sentences within the caps | software-engineer, measured by the eval | Wording only |
| TBD-4 | Gates for the offer and safety eval groups | Resolved at sign-off: equal to `Calibration.Persistence` | Measurement only |
| TBD-5 | Does the reader's cold cost scale with the launch cost across machines, the Assumption under `SessionStart.AddedLatency`? | software-engineer, the RAANDREE3 Meter run | Whether one hook launch is a fair unit on both machines; if not, back to software-architect (A1) |

Delegated answers: none.

### Independent review resolution

A `rubber-duck` review of the first draft, completed on 2026-10-06, reported:

| # | Severity | Finding | Resolution |
|---|---|---|---|
| 1 | Blocker | Hosts load hook files at session start, so registration changes cannot act on open sessions, and Uninstall can strand a cached hook | Fixed: load timing stated; the script rechecks the profile on every injection; Uninstall reconciles first, and open chats restart as for every hook |
| 2 | Blocker | The Purpose promised persistence everywhere, while B1 misses plugin-only installs and replies without a tool call, and the Meter could not see it | Fixed: the Purpose states its limits; `Calibration.Delivery` adds a host x channel x event matrix with gated and reported cells |
| 3 | Major | The registration and its record had no ordering, crash reconciliation, collision rule, or lock shared with Uninstall | Fixed: a two-phase record, a fixed path, a triple hash check, refusal of foreign files, a shared lock, and Uninstall stopping when it cannot reconcile |
| 4 | Major | No stable entry identity or global alias uniqueness; ambiguous merges and cap overflow were undefined; no entry possible without a git identity | Fixed: immutable `id`, globally unique aliases, zero aliases allowed, `-Contributor` resolving to exactly one entry, import refusing ambiguity and overflow |
| 5 | Major | Offers repeated after a compaction; a boolean flag could lose a newer compaction; calibration writes could clobber the clock's turn counter | Fixed: a separate state file with compare-and-set counters, and a re-sent sentence that suppresses offers |
| 6 | Major | The residual trifecta and the unenforced approval boundary were rated Low | Ruling R1: kept Low by the contributor, with the argument recorded under Security |
| 7 | Major | One person's opt-out cannot remove the per-call cost on a shared account; no repair for a stranded registration | Fixed: the claim is narrowed in Rollback; `Get-` reports and `Remove- -RegistrationOnly` repairs |

## Amendment log

Amendment 1, 2026-10-06: rulings A1 to A8. A1 to A7 answer the questions
that implementation returned; the refined A1, the revised A7, and A8 answer
the independent review of the draft. The reasons are under
*Rulings, 2026-10-06* in the Confirmation.

| Ruling | Passages amended |
|---|---|
| A1 | `SessionStart.AddedLatency` and `PostToolUse.CallLatency`: Scale, Meter, Past; Consequences; criterion 20; Open questions: TBD-5 |
| A2 | `SessionStart.AddedLatency`: Budget, Fail, Report, Rationale, Assumption, Risk; Consequences; criterion 20 |
| A3 | `PostToolUse.CallLatency`: Budget, Fail, Rationale; Compaction coverage: the fallback condition; Consequences; criterion 20 |
| A4 | `Context.SentenceSize`: Scale, Past, Budget |
| A5 | Scope 9; Registration file: ownership, replacement, repair; Commands: `Get-`, `Remove-`; Failure modes; Durable choices; Security; Rollback; criterion 11 |
| A6 | Area-name rule; Durable choices; Edge cases; criterion 2 |
| A7 | Decision outcome; Purpose; Stakeholders; Schema 1; area-name rule; PostToolUse re-injection; Commands: `Set-`, write selection, snooze; Failure modes; Edge cases; criterion 15 |
| A8 | Registration file: reconciliation, replacement, Uninstall, repair, known limit; Commands: `Get-`, `Remove-`; Failure modes; Rollback; criterion 11 |

## Sign-off

- [x] The user read this document end to end.
- [x] The user accepted every section, including the ruling on rating and save
  questions and the TBD-4 gates.
- [x] The user typed `SIGNED OFF` in chat on 2026-10-06.

Amendment 1:

- [x] The user read the Amendment log and every passage it marks.
- [x] The user accepted rulings A1 to A8.
- [x] The user typed `SIGNED OFF` in chat on 2026-10-06.
