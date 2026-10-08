---
status: accepted
date: 2026-10-06
last-verified: 2026-10-07
owner: software-architect
source: software-architect Design Concept interview 2026-10-05 to 2026-10-06 and sign-off 2026-10-06; amendment interview 2026-10-06 (rulings A1 to A7); Amendment 2 rulings 2026-10-07 (A9 to A13), signed off by the repository owner in chat on 2026-10-07; Decision record 0027; hook host references (VS Code, GitHub, Claude Code), fetched during the interview; Amendment 3 rulings 2026-10-07 (A14 to A18), signed off by the repository owner in chat on 2026-10-07
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
  started while the registration exists costs one more hook launch. That launch
  is the shared hook launcher's cost, not this design's: it is what the push
  guard costs on the same machine, and it varies by machine and shell edition
  far more than by anything here. Measured on 2026-10-06: 0.84 to 0.88 s
  through VS Code's spawn and 1.09 to 1.15 s through the SDK host's on Prox1;
  2.07 to 2.20 s and 1.16 to 1.39 s on RAANDREE3, where Windows PowerShell
  starts about 2.4 times slower than on Prox1 for reasons this design did not
  investigate. The calibration script's own share is about 70 to 120 ms on both
  machines, and up to 290 ms in the noisiest SDK run. Machines without a
  profile pay nothing *(A1, A3, A11)*.
- A session in a workspace that declares Knowledge areas starts later by about
  0.41 to 0.49 s (Prox1, VS Code), 0.35 to 0.48 s (Prox1, SDK), 0.52 to 0.75 s
  (RAANDREE3, VS Code), and 0.45 to 0.81 s (RAANDREE3, SDK), measured
  2026-10-06 *(A1, A2, A11)*.
- After a compaction, the levels return at the first successful tool call where
  PreCompact runs, and within one turn where it does not, which is VS Code
  Local for manual and background compactions. Plugin-only installs and a reply
  that makes no tool call before the next turn still receive nothing; Claude
  Code gets the portable Skill only. These gaps are measured and reported, not
  gated *(A12)*.
- Backstop re-sends add calibration text to a long session, bounded at 12,000
  characters for all Positions together, about 3,000 tokens. A session reaching
  that bound makes no further backstop re-sends; compaction re-sends continue
  up to a second ceiling of 60,000 characters *(A12)*.
- A tool call that actually re-sends costs more than one that does not, because
  the hook re-reads the declaration and the profile: the work measured at p95
  +0.41 to +0.49 s on Prox1 and +0.52 to +0.75 s on RAANDREE3 through VS Code's
  spawn. Before A12 that was paid once per compaction; now it is paid at most
  once per turn, and at most once per 5 minutes. It is reported per machine and
  spawn, not gated *(A12)*.
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
preparation; none is redesigned in code. All five are ruled in
*Rulings, 2026-10-07* below (A9 to A13); this section stays as the question
those rulings answer.

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

### Rulings, 2026-10-07

`software-architect` and the repository owner ruled on the five results of the
second round in one pass at named-subset depth — purpose, inputs and outputs,
failure modes, edge cases, rollback, non-goals — because these are contained
changes to a signed-off concept: no new system, no new public contract, and no
new persisted schema beyond three fields in an existing private per-session
state file. An independent `security-reviewer` pass then reviewed the draft,
and its twelve findings are folded into the text below. The questions behind A9
and A12 offered a `not sure, you pick` option; A10, A11, and A13 follow from
them or restate measured fact, and no answer was delegated. Nothing here
authorizes an irreversible, destructive, or security-relevant action. Amendment
2 applies the rulings to the concept below and marks every amended passage with
its tag.

| # | Question | Ruling |
|---|---|---|
| A9 | The launch unit does not transfer across machines (TBD-5) | Both latency requirements change unit: the calibration step's own time, in **frozen reference scripts** run cold through the same launcher and spawn, each measured as a paired difference against the no-op hook in the same replicate. The hook's full wall-clock time and the no-op launch are reported in milliseconds beside it. The launcher itself is Decision 0016's, not this record's |
| A10 | Criterion 20 has two reproduced over-Budget cells | Both verdicts are **withdrawn, not waived**: they are artefacts of the unit A9 retires. Every launch-unit Past line becomes history and binds nothing. Criterion 20 re-opens and is decided by one re-baseline run under A9's rule. No code tuning is ordered; fallback A stays un-invoked, because no cell reached Fail |
| A11 | The per-call cost on RAANDREE3 is 2.4 times the Consequences | **Restate the Consequences per machine and per spawn**, as measured ranges with the machine, spawn and date named, and attribute the cost to the shared hook launcher rather than to the calibration script. The one-process `windows` launcher is **not** adopted here: it is a Decision 0016 change to a launcher the push guard shares, measured on neither machine, and it would re-baseline every level in this record. Fallback A for VS Code only is rejected |
| A12 | VS Code Local runs no PreCompact for a manual or a background compaction | Add a **backstop re-send** to the existing PostToolUse hook, triggered by a new turn **or** 5 minutes since the last injection, whichever comes first, bounded by a session character budget that the hook enforces itself. The trigger reads counters that shipped hooks already maintain, so the common path performs no new write. Every writer of the per-session state file preserves all five fields, and an injection is emitted only after its own state write has succeeded under the lock. `UserPromptSubmit` is rejected. The Purpose is narrowed to what this delivers: first successful tool call where PreCompact runs, within one turn where it does not |
| A13 | `Calibration.Persistence` cannot be measured from real restatements | Accept **derived cases, topped up with owner-reviewed synthetic ones**, at an unchanged count of at least 6 per Position, with at least 3 `real-derived` per Position, every case carrying a `provenance` field, and at least one case per Familiarity level per Position. `provenance` carries an opaque local digest, never a history name, path, or message text, and every derived case passes the existing redaction step. The Goal and Fail levels do not move. The weakened evidence is recorded as a named limitation |

Reasons:

- **A9.** A hook's wall-clock time sums two cost families that scale
  differently: process start-up, which varies enormously by machine and shell
  edition — RAANDREE3 starts Windows PowerShell about 2.4 times slower than
  Prox1, while PowerShell 7 does not — and cold script execution, which barely
  varies, the reader's own added time being only 1.1 to 1.4 times Prox1's on
  RAANDREE3. Both tags measured the second family and divided by the first, so
  the quotient was a property of the machine's shell start-up speed rather than
  of the design, and both failures are already visible in the evidence: the
  cheapest-launch machine binds, the same reader reading 0.48 to 0.50 launch at
  p50 on Prox1 and 0.25 to 0.26 on RAANDREE3 through the same VS Code spawn;
  and a slow launch hides a heavy script, which is worse than a false alarm
  because nothing reports it. Rejected: keeping the unit and gating per
  machine, which preserves the defect and lets the fleet's fastest machine set
  the line for every machine; and milliseconds on an idle machine with the
  no-op launch as a load check, which reintroduces the load sensitivity A1 was
  created to remove — Prox1 ran 26 to 50 % slower on 2026-10-06 than on
  2026-10-05 — because a load check is a precondition that tells you to discard
  a run, not what the run means. Dividing cold script time by cold script time
  cancels machine speed, shell edition, and load to first order, both terms
  moving together, and leaves the launcher's cost with Decision 0016, which
  owns it, states that a lighter launcher raises every ratio without any
  regression, and already requires a re-baseline here when a launcher in
  `hooks.json` changes. The new unit's transfer is verified, not assumed: the
  old Assumption was carried for weeks and then falsified, so the re-baseline
  rule makes the reference script's own cross-machine ratio a checkable output
  of the run (TBD-6).
- **A10.** The two cells are 0.53 to 0.61 against Budget 0.5, and 1.11 to 1.25
  against Budget 1.1, the second clearing its Budget by one per cent in run 1
  and by fourteen per cent in the noisier run 2. Neither tells us anything
  about the design once A9 removes the denominator that produced them.
  Withdrawing is not waiving: the cells are not declared acceptable, they are
  declared unmeasured, and criterion 20 re-opens until the re-baseline run
  decides it. The launch-unit Past lines stay in the Confirmation as the
  evidence for A9 and bind nothing. No tuning is ordered: the 30 to 40 ms of
  local tuning was costed against a line that no longer exists, and tuning code
  to reach a threshold that the same amendment is redefining is the failure
  mode A1's reason warned about. Tuning remains available and is explicitly
  deferred; if the re-baseline run lands close to its Budget, it is the first
  lever, not a redesign. Fallback A stays un-invoked, because A3 reserved it
  for a Fail-level result on Prox1 or RAANDREE3 and no cell reached Fail under
  any unit — which must be stated, because the 1.25 reading sits exactly on the
  old Fail level and reads like a trigger.
- **A11.** The Consequences stated one machine's number as though it were
  universal and are wrong about RAANDREE3 by a factor of 2.4; the fix for an
  inaccurate disclosure is an accurate disclosure. The cost is not this
  design's to spend: almost all of it is the shared hook launcher starting two
  PowerShell processes, which the push guard pays identically on the same
  machine, this record's script accounting for roughly 70 to 120 ms of it. The
  contributor already accepted it in Q20 in the correct currency, one hook
  launch per tool call on machines with an active profile, and the level that
  matters is gated elsewhere, so restating a sentence leaves nothing unguarded.
  The one-process `windows` launcher is rejected for this record and
  recommended as separate work: it changes a launcher that the push guard
  shares, and Decision 0016 records that a launcher exit-code defect previously
  degraded the push guard to a warning in VS Code Local, a Blocker in
  post-release review; it must preserve `tests/HookLauncher.Tests.ps1`'s
  cross-shell guarantees (`cmd.exe`, `sh`, an outer PowerShell, `HOME` unset)
  and the exit-code contract across both hosts; it is measured on neither
  machine, so adopting it here would trade a known cost for an unknown one; and
  Decision 0016 already states that such a change re-baselines every level in
  this record, which would invalidate the re-baseline A9 orders, in the same
  release. It is nonetheless the largest single improvement available — it
  would cut every hook on Windows, the push guard included — and belongs in its
  own Decision record against Decision 0016, with its own Meter run and the
  cross-shell tests as its gate; that is not a dependency of this release.
  Fallback A for VS Code only is rejected: it would fork the delivery design by
  host, reduce `Calibration.Delivery` coverage in the host most sessions use,
  and trade deterministic hook delivery for a tool call plus a model round
  trip, for a cost the contributor accepted and without the Fail-level result
  A3 reserved it for.
- **A12.** The Purpose promises levels after a compaction in module and Setup
  installs, and in VS Code Local that promise does not hold for a manual or a
  background compaction, which are the common cases; only the rare foreground
  fallback runs PreCompact. The owner ruled out asking VS Code for a change, so
  the only question is which project-controlled signal replaces it.
  `UserPromptSubmit` is rejected: it adds a hook launch to every prompt for
  every profile user, about 0.8 s on Prox1 and 2 s on RAANDREE3 in VS Code
  before the reader's time, a cost the owner never accepted because Q20 scoped
  it to tool calls, and it fires only at prompt boundaries, so it misses a
  compaction partway through a turn — exactly the VS Code Local background case
  the evidence recorded. A count of tool calls is the right idea with the wrong
  mechanism: it would turn today's read-only common path into a
  read-modify-write under a lock, on the hot path, in the very requirement that
  the first two returned questions are about, and add lock contention for
  parallel tool calls. Two counters that shipped hooks already maintain give
  the same trigger for free: `turns` in the session clock file, written by
  `Write-SessionClose.ps1` at every Stop, which criterion 10 permits reading
  and forbids only rewriting; and the last injection's timestamp, which the
  calibration hook records in `session-<key>.familiarity.json`, a file it
  already reads on every call and writes only when it injects. So the trigger
  is a new turn, or 5 minutes since the last injection, whichever comes first:
  the turn leg gives a deterministic promise in the unit the contributor
  perceives, at most one reply going uncalibrated, and the time leg is the
  fallback in any host where Stop does not fire. The common path gains exactly
  one small file read and no write. This realizes option B2 of the *Compaction
  coverage* table — impact 95 % ± 5, credibility 0.5, "more tokens" its only
  recorded downside — without the `UserPromptSubmit` launch B2 was assumed to
  need. The inject path's cost moves and must therefore be measured: it
  re-reads the declaration and the profile, the work measured at p95 +412 to
  +493 ms on Prox1 and +517 to +750 ms on RAANDREE3 through VS Code's spawn,
  and A12 moves it from once per compaction to once per turn plus the 5-minute
  leg, while `PostToolUse.CallLatency`'s Scale deliberately excludes it. The
  Meter therefore gains a reported inject-path cell and the Consequences name
  the per-turn cost; it is reported rather than gated because it is the same
  reader the session-start tag already gates, and gating it twice would make
  one tuning decision answerable to two thresholds. The token cost is bounded
  by construction rather than by hope: backstop re-sends stop at 12,000
  characters of calibration text, about 3,000 tokens, roughly 5 % of the
  ~60,000-token base prompt this record measured and 1.5 % of a 200,000-token
  window. Compaction re-sends count toward that total but are never suppressed
  by it — the promise wins, the backstop yields — and carry a ceiling of their
  own at 60,000 characters, because they are otherwise unbounded in principle:
  the record documents a real session with 99 background compactions, above
  which the session is outside the design's envelope. Without these bounds the
  backstop would feed the context pressure that causes compactions in the first
  place. Six details are correctness issues rather than preferences, the first
  two being defects an independent review found in the first version of this
  ruling: every writer of the state file preserves all five fields, because
  both existing writers emit a hardcoded two-field object and would otherwise
  reset the character budget and re-arm the backstop at every compaction; an
  injection is emitted only after its own state write succeeded, because the
  backstop's two legs are standing conditions and an unrecorded injection would
  re-fire on every later call while `characters` never advanced; the time leg
  is armed only from the first turn boundary, the turn leg being already safe
  at turn 1; the backstop is gated on a seeded `lastInjectionUtc` rather than
  on the state file existing, because `Write-CompactionCheckpoint.ps1` creates
  that file unconditionally; a resumed session merges rather than initializes,
  because `Add-SessionContext.ps1` preserves the clock on `source: resume` and
  can meet an existing state file; and the backstop suffix must neither lie,
  since a compaction suffix on a turn where nothing compacted would be false in
  text the model treats as stated fact, nor cost characters, so it is 59
  characters, exactly as long as the compaction suffix. The Purpose is narrowed
  to the truth, because a promise the mechanism cannot keep is worse than a
  stated limit.
- **A13.** The finder searched three whole histories, 2,706 user messages, and
  found at most 5 usable restatements: 3 state a level, all `new`, one already
  an approved Phase 1 case; 2 are one-answer overrides, which the Instruction
  treats differently and which carry no durable level. None is at `expert`. A
  Meter that demands 6 real restatements per Position against a population of 3
  cannot be satisfied, and the shortage is structural, because Phase 2 exists
  precisely to remove the need to restate, so the population shrinks rather
  than grows. Lowering the count is rejected: fewer samples widen the
  confidence interval on a 100 % pass^3 Goal, the one place this design cannot
  afford noise. Synthetic-only is rejected: it would let the authors choose
  both the question and the answer, with nothing anchoring the set to how the
  contributor actually writes. Derived cases are the honest middle. A derived
  case takes a real restatement verbatim and moves the stated level out of the
  message and into the profile sentence, everything else unchanged — the
  cleanest A/B this design could ask for, the level's source being the only
  variable, and exactly what Phase 2 claims to do. The same derived case is
  valid at both Positions, because a Position describes where the sentence sits
  in context and not what the contributor wrote, so 3 real restatements yield 3
  `real-derived` cases per Position. The discipline that makes the set
  trustworthy: a `provenance` field on every case; at least 3 `real-derived`
  per Position, so the set stays anchored; and at least one case per
  Familiarity level per Position, because `new`, `familiar`, and `expert` drive
  different rows of the Instruction's table while the real population is
  entirely `new`. The discipline that keeps it private, this being the only
  place in Amendment 2 where data lands somewhere it was not before:
  `provenance` on a derived case carries an opaque local digest, a salted hash
  of the source message stable enough to re-derive locally, and never a history
  name, a file path, a session identifier, or message text, because a field
  that names where a real chat message came from would undo the anonymization
  the eval pipeline already performs; a derived case passes the existing
  redaction step before it becomes a case, as `docs/SECURITY-REVIEW.md` already
  records for the history searcher and the runner; and the eval kit stays
  outside every git working tree, under the same refusal criteria 4 and 24
  impose on the profile, its location recorded here (TBD-8), because placing
  the kit out of review scope is a statement about review effort and not a
  licence to let chat excerpts land in a repository. The overlap with the
  approved Phase 1 case is intentional and allowed, the Phase 2 instance
  differing in the one variable under test; it must not be counted twice toward
  `Calibration.PhaseOneGuard`, whose 51 of 51 stays its own set. The limitation
  is recorded rather than smoothed over: a Meter fed partly by authored cases
  is weaker evidence than one fed entirely by observed behaviour, and the owner
  accepted that trade in signing A13.

An independent `security-reviewer` pass over the draft of this amendment,
2026-10-07, read-only against this record, the four hook scripts, and
`docs/SECURITY-REVIEW.md`, returned **approve with changes, no Blocker**: no
new security boundary is crossed by A12, the lethal trifecta stays broken at
leg 3, and the three new state fields carry no level, email, path, or workspace
text. The Majors were correctness and accounting defects in the first version
of the draft, all resolved in the text above:

| # | Severity | Finding | Resolution |
|---|---|---|---|
| 1 | Major | Both existing writers emit a hardcoded two-field state object, so a PreCompact write would erase the three new fields, reset the character budget, and re-arm the backstop at every compaction | Fixed: every writer preserves all five fields, with a criterion-10 test that a PreCompact after a backstop injection leaves them intact |
| 2 | Major | The save path returns without writing on a 5 s lock timeout. The backstop's legs are standing conditions, so an unrecorded injection would re-fire on every later call while `characters` never advanced — the bound failing on exactly the path it exists for | Fixed: the inject path takes the lock, re-reads, re-decides, writes, and only then emits; a failed write emits nothing. `characters` is a monotonic maximum under compare-and-set |
| 3 | Major | The inject path re-reads the declaration and profile — the +412 to +750 ms step — and A12 moves it from once per compaction to once per turn, while the amended Scale excludes it by construction. Gated nowhere, reported nowhere | Fixed: a reported inject-path Meter cell, the per-turn cost named in the Consequences, and criterion 29 |
| 4 | Major | The re-baseline rule was not mechanical: "worst reproduced p95" was undefined between max-across-runs and the reproduced value, the report-only `[two entries]` cell was not excluded, and the 1.5 factor was below the 1.65 spread it cited | Fixed: `w` is the maximum over gated cells of each cell's lower run; the factor is 1.75, stated as needing to exceed the spread |
| 5 | Major | A13 would put verbatim real messages plus a history and message identifier into the eval kit, whose location the record never states, while criteria 4 and 24 impose a working-tree refusal on the profile | Fixed: `provenance` carries an opaque local digest only, derived cases pass the existing redaction step, the kit is placed outside every git working tree, criterion 28 and TBD-8 added |
| 6 | Minor | A resumed session meets an existing state file, which "initialise when it injects" would reset, losing a pending compaction re-send | Fixed: seed when absent, merge otherwise, `compactions` and `injected` untouched |
| 7 | Minor | The stated reason for seeding `lastTurn` was wrong — the turn leg is already safe at turn 1; the real turn-1 duplication risk is the time leg, armed from session start | Fixed: reason corrected, time leg armed from the first turn boundary |
| 8 | Minor | "No state file, no backstop" does not survive a compaction, because PreCompact creates the file unconditionally | Fixed: the gate is a seeded `lastInjectionUtc`, not file existence |
| 9 | Minor | `Context.SessionBudget`'s Gist was falsified by its own Fail line; compaction re-sends alone could reach ~116,000 characters in the documented 99-compaction session | Fixed: Gist names the exemption, and a 60,000-character second ceiling bounds it |
| 10 | Minor | A10 conflated two runs: 1.11 is run 1 at one per cent over, while the noisier run 2 read 1.25, fourteen per cent over | Fixed; the withdrawal stands on A9's reasoning either way |
| 11 | Minor | Criterion 14 was unamended and bound offer suppression only to the compaction Position, which A4 classified as a security control | Fixed: criterion 14 extended to every re-send Position |
| 12 | Minor | The backstop sentence was never printed, and its suffix was 12 characters longer, putting the worst case at ~1,190 against Budget 1,200 | Fixed: the sentence is printed in the Outputs table, and the suffix shortened to 59 characters so the worst case stays at 1,178 |

The reviewer confirmed that every figure quoted from this record's measurement
tables reproduces faithfully, that no amended criterion contradicts an
unamended one, and that criteria 22 and 25 stay coherent with A12.

### Amendment 2 implemented, 2026-10-07 on Prox1

`software-engineer` built steps 1 and 2 of *Delivery increments* item 7
test-first on `ai/calibration-phase-2` and ran the Prox1 half of step 3. Every
new test of new behavior failed for its expected reason before the code
existed. The four tests that guard against an over-eager backstop passed
against the old hook, which never fired one, so each was shown instead to fail
against a deliberately broken hook before the hook was restored. The full gate
passed 3,138 tests; its one failure was this record's own `status`, which commit
`61ce515` had set to a value the Memory Bank routing test does not allow, now
`accepted` again.

**A9, the unit.** `tests/Fixtures/Invoke-ReferenceHook.ps1` reads standard
input as the no-op hook does, parses it with `ConvertFrom-Json`, matches one
regular expression, tests one path, and runs 24 groups of straight-line code:
4,002 syntax-tree nodes, with no loop and no function. Its SHA-256 over its LF
text, `269b070a3964a2b51129dade3c63b1e412528928280c52d17421a613a1d4d798`, is
pinned beside the levels in `Get-CalibrationMeterBudget`, so a change to the
script fails `tests/CalibrationMeter.Tests.ps1` until the pin and the levels
change in the same commit (criterion 26), and the Meter refuses to run on an
unpinned script. The Meter gains the reference cell, the inject-path cell, a
common-path cell that starts from an armed session with nothing due, every
cell's step in milliseconds, both stop lines, and a reproduced row per gated
cell that names its lower run. Ruling A10's withdrawal shows as
`no level (A10)`. `tests/Helpers/CalibrationMeter.ps1` carries steps 2, 3, and
5 of the re-baseline rule as tested functions.

The reference script's own time is about half the estimate: about 130 ms on
Prox1 in both editions, 118 to 135 ms in Windows PowerShell and 105 to 149 ms
in PowerShell 7, from 10 alternating pairs after 2 warm-up pairs, launched
directly rather than through a host spawn. Decision 0016's 0.07 ms per node
predicted 280 ms; straight-line code runs at about 0.033 ms per node, and the
reader's nodes are heavier. The rule publishes the measured value as Past, so
the estimate binds nothing, but a smaller unit carries relatively more launch
jitter: a smoke run without warm-up met a replicate whose reference script
finished before its no-op hook. The Meter now reports such a run as
`unit unmeasurable`, with its milliseconds, instead of dividing by it.

**A12, the backstop.** Built in the record's order. First, all three writers,
`Write-CompactionCheckpoint.ps1`, the PostToolUse save path, and the new
SessionStart seed, share `Read-CalibrationState`, `Save-CalibrationState`, and
`Enter-CalibrationStateLock`, copied verbatim and held together by a drift
test, so every write keeps all five fields. Second, the inject path takes the
lock, reads again, decides again, writes, and only then emits; a lock held past
its timeout emits nothing. Then the SessionStart seed and the resume merge, the
two signals with the 5-minute signal armed from the first turn boundary, the
seeded `lastInjectionUtc` gate, both bounds, and the 59-character suffix
through `Format-ContributorCalibrationSentence -Backstop`. Criteria 10, 14,
and 27 each have a test in both editions.

Choices made within the text, for `software-architect` to confirm:

- `lastInjectionUtc` is the time of the injection. For a new session that is
  the session start; a resumed session's recorded start can be hours old and
  would fire the 5-minute signal at once.
- A re-send that finds nothing to send, after an opt-out, is still recorded,
  so the standing condition does not reread the profile on every call.
- The calibration step runs before the lock, because the reader can take
  seconds and PreCompact waits only 5 s for it. The locked decision never turns
  a backstop into a compaction re-send; a compaction counted meanwhile gets its
  own re-send on the next call, and the compaction answered is the count read
  before the step, as the stale-write test requires.
- A bound suppresses once `characters` reaches it, so the last re-send before a
  bound can cross it by one sentence, at most 1,178 characters.
- Above 60,000 the record of the condition is the state file itself:
  `characters` at or above 60,000, with the unanswered compactions left in
  `compactions`.
- The state file and the clock's `turns` are read with one pattern per field,
  not `ConvertFrom-Json`, whose module load cost the armed common path about
  100 ms when the hook was launched alone. Launched alone, the armed path still
  costs 59 to 78 ms more than the unarmed one (10 pairs per edition on Prox1);
  through the launcher, which has already loaded that module, the whole armed
  common path is 108 to 118 ms at p50 (step 3 below), within the 70 to 120 ms
  the unarmed path cost on 2026-10-06. A malformed file still reads as
  unreadable.

**The Meter's session files.** The Meter's note that a host spawn cannot
redirect LocalApplicationData was wrong. Both editions resolve it through
`USERPROFILE`, and Windows PowerShell falls back to the temp directory when the
folder is missing; 143 clocks of earlier Meter runs had collected there. The
Meter now creates `AppData\Local` in each scratch home, and the stray clocks
are deleted.

**Step 4.** The Consequences and the Purpose already carry the amended text.
The separate Decision record for the one-process `windows` launcher cannot be
filed as proposed, because a record here is accepted or superseded
(`tests/MemoryBankRouting.Tests.ps1`). The proposal and its four gates are
recorded as open work in `progress.md` until the owner accepts it, when it
becomes a record of its own against Decision 0016.

**Step 3 on Prox1, 2026-10-07.** Two runs of the amended Meter, 20 replicates
after 2 warm-up replicates each, on an idle machine. Steps over the no-op hook
in milliseconds, p50 and p95, per spawn:

| Cell | VS Code spawn | SDK spawn |
|---|---|---|
| No-op launch, absolute p50 | 775 to 777 | 1,015 to 1,019 |
| Frozen reference script, the unit | 76 to 84; 97 to 111 | 84 to 89; 115 to 120 |
| SessionStart, one entry, added | 450 to 455; 482 to 550 | 367 to 370; 390 to 500 |
| SessionStart, no profile, added | 186 to 193; 209 to 301 | 161 to 163; 184 to 188 |
| PostToolUse, common path, armed | 108 to 111; 124 to 232 | 117 to 118; 155 to 158 |
| PostToolUse, inject path | 565 to 566; 612 to 681 | 478 to 491; 505 to 541 |
| Push guard, benign tool | 106 to 107; 145 to 159 | 91 to 100; 124 to 128 |

Both stop lines are clear in every run: the SessionStart step reaches at most
550 ms against 1,000, and the PostToolUse common path at most 232 ms against
400. The SDK spawn's gated ratios reproduce within the rule's spread, p95 6.21
to 6.95 for one entry, 2.43 to 3.45 for no profile, and 1.65 to 2.30 for the
common path. The VS Code spawn's first run has no ratio at all: in 1 of its 20
replicates the reference script finished no slower than the no-op hook, so the
rule has no lower run for any VS Code cell. Through the launcher the reference
script's own time is about 80 ms, less than launched alone, because the
launcher has already loaded the modules its `ConvertFrom-Json` and
`Select-Object` would load. A unit that small sits inside the launch's jitter.
Nothing here points at the design; it points at the unit's size. The Meter was
not run on RAANDREE3, and should not be until question 4 is ruled, because a
resized unit invalidates any run made before it.

**Questions for software-architect.** None of them blocks steps 1 and 2;
question 4 blocks step 3. Answered by Amendment 3, rulings A14 to A17, under
*Rulings, 2026-10-07, second pass* below.

1. *Failure modes* says that where `turns` never advances, the 5-minute signal
   alone drives the backstop. Criterion 10 and the Outputs arm that signal only
   from the first turn boundary, which such a host never reaches. Built:
   criterion 10, with the 5-minute signal alone only where the clock is
   missing or unreadable, as the row above it says. Recommended: correct the
   row, unless the arming should change.
2. *Failure modes* says `Get-` reports a session above 60,000. Neither the
   Commands table nor any criterion carries it, so it is not built.
   Recommended: drop the clause, or amend `Get-` and add a criterion.
3. The re-baseline rule takes `w` as the maximum across the gated cells. One
   `w` for both tags would give `PostToolUse.CallLatency` a Budget set by
   SessionStart's much larger step, which its common path could never reach.
   Recommended: one `w` per tag, as each tag carries its own Budget line.
4. The frozen reference script is sized at about 4,000 nodes so that its own
   time is near 280 ms, the order of the calibration step. Measured through
   the launcher it is about 80 ms, and the VS Code spawn lost a run to it.
   Recommended: size the script so that its own time through the launcher is
   near the intended 280 ms on Prox1, about three to four times today's fixed
   block, with the hash pin moving in the same commit; no level exists yet, so
   nothing else is re-baselined. Then run step 3 again on both machines.

### Rulings, 2026-10-07, second pass

`software-architect` ruled on the four questions implementation returned while
building Amendment 2, and confirmed the six choices it made within the text, at
named-subset depth — purpose, inputs and outputs, failure modes, edge cases,
rollback, non-goals — because these are contained changes to a signed-off
concept: two sentences that contradict the record's own criteria, one
arithmetic rule of a Meter, and the choice of a test fixture. No new system, no
new persisted schema, and no new or changed public contract. No independent
review was commissioned, because no ruling introduces or alters an attack
surface; the reasoning is under *Independent review* at the end of this
section. Amendment 3 applies the rulings and marks every amended passage with
its tag.

Two probes on Prox1, 2026-10-07, are the evidence for A17. Own time is the
variant minus the no-op hook in the same replicate, through the real launchers
under both host spawns, 12 measured replicates after 2 warm-up, rotated order:

| Groups | Nodes | Bytes | VS Code own p50 / p95 / min | SDK own p50 / p95 / min |
|---|---|---|---|---|
| 24 (the script of Amendment 2) | 4,002 | 20,059 | 84 / 111 / 65 ms | 84 / 113 / 65 ms |
| 72 | 11,874 | 58,539 | 127 / 170 / 97 ms | 129 / 156 / 101 ms |
| 120 | 19,746 | 97,019 | 183 / 224 / 151 ms | 139 / 170 / 128 ms |

No-op launch p50: 773 ms (VS Code spawn), 1,005 ms (SDK spawn). The marginal
cost is about 1 ms per group of about 165 nodes in Windows PowerShell and
nearly flat between 72 and 120 groups in PowerShell 7, so about 0.006 ms per
node rather than the 0.07 ms Decision 0016 states for first-executed nodes.

The second probe, a fresh process per run, 5 measured after 2 warm-up, with
`Get-Item` and `Select-Object` pre-loaded as the launcher does, a one-entry
profile, a declared workspace, and `-SkipGitForSingleEntry`:

| Edition | Dot-source the reader | `Get-ContributorCalibration` | `Format-...Sentence` |
|---|---|---|---|
| Windows PowerShell 5.1 | 18 ms | 404 ms | 31 ms |
| PowerShell 7 | 20 ms | 264 ms | 17 ms |

About 95 per cent of the reader's cost is executing its 21 functions and 19
loops, not first-executing its 5,239 nodes. It runs 1.53 times slower in
Windows PowerShell than in PowerShell 7 on one machine, where straight-line
code runs 1.0 to 1.32 times slower: different kinds of work scale differently
even across editions, which is what A9's Assumption and the TBD-6 transfer
check are about.

| # | Question | Ruling |
|---|---|---|
| A14 | The frozen-`turns` Failure-modes row contradicts criterion 10 and the Outputs | **Correct the row; the arming does not change yet.** Where the clock is readable and `turns` never advances, neither leg fires and that host receives no backstop, which is what is built. TBD-7 becomes a per-host measurement with a defined consequence, and a **grace fallback is pre-authorized**: should TBD-7 find a host inside the promise whose `turns` never advances, the time leg is also armed by a clock still reading `turns = 0` in a session whose recorded `startedUtc` is more than 30 minutes old, built without a further architect round |
| A15 | The 60,000-character row says the condition is reported by `Get-` | **Drop the clause.** The state file is the record: `characters` at or above 60,000, with the unanswered compactions left in `compactions`. `Get-` reads the profile, is given no session identifier, and gains no session-state contract |
| A16 | The re-baseline rule takes one `w` across the gated cells | **One `w` per tag**, across that tag's gated cells and across both machines and both spawns, each cell at its lower run. Never one `w` for both tags |
| A17 | The frozen reference script is too small, and the wrong kind of work | **A reader-shaped frozen reference.** `tests/Fixtures/ReferenceHook/` holds a driver keeping A9's payload primitives, a **frozen copy** of the contributor-profile reader, and a frozen fixture; the driver runs one fixed calibration on that fixture. One composite hash pins all three, A9's straight-line block is removed, and the transfer check runs per tag with a defined outcome when it fails for `PostToolUse.CallLatency` |
| A18 | The six choices implementation made within the text | **All six confirmed**, four of them promoted from implementation detail to contract text, because they are correctness properties a later change could silently remove |

Reasons:

- **A14.** `Test-BackstopDue` fires the turn leg on `turns` above `lastTurn`
  and arms the time leg on a clock that is unreadable or reports at least one
  closed turn. A readable clock frozen at 0 satisfies neither, and `lastTurn`
  is seeded 0, so the row promised a backstop that cannot happen. The arming
  buys exactly one thing — no duplicate of the session-start sentence inside a
  long first turn — and removing it would spend that in every host, including
  the ones that never needed it, for a contingency that is still unmeasured.
  The record already accepts a turn-1 gap: the Purpose promises re-injection
  within one turn where PreCompact does not run. A host that never advances
  `turns` is outside that promise, which is the case worth closing, and TBD-7
  closes it cheaply because it already runs in increment 7.5. The remedy is
  therefore pre-authorized rather than built: a 30-minute grace, far longer
  than a normal first turn and far shorter than a session in which losing
  calibration matters, reading one more field with one more pattern from a file
  the common path already opens. Rejected: arming the time leg whenever `turns`
  reads 0, which makes the row true at the price of duplicating the
  session-start sentence in every host with a first turn over 5 minutes, routine
  agentic work here, and spending the very budget `Context.SessionBudget`
  protects; and leaving row and code as they were, which is how this question
  arose.
- **A15.** `Get-CopilotAtelierContributorProfile` resolves the profile, the
  registration, and the sentence for a workspace. It is never given a session
  identifier, so it cannot report this session's budget, and enumerating the
  per-session files would print other sessions' private hook state from a
  command whose output enters the model's context. Criterion 27 already
  requires the condition to be recorded, and the state file is where it is
  recorded. Rejected: amending `Get-` and adding a criterion, which enlarges a
  public API named under *Durable choices* for no consumer that exists; it
  stays available as additive work.
- **A16.** A Budget is a level of one requirement, and the two tags measure
  different code that regresses independently: the session-start step
  dot-sources the reader and parses a profile, while the common path runs one
  regex over a payload head and reads two small files. Pooling makes the
  smaller tag's level a function of the larger tag's step. On the Prox1 SDK
  spawn of 2026-10-07, in the unit then in force, the lower-run p95 values were
  6.21, 2.43, and 1.65; one `w` gives every gated cell Budget 11.0, so a common
  path three times slower than today would still pass, while one `w` per tag
  gives 11.0 and 3.0. Within a tag the pooling is sound, because a tag's gated
  cells share a code path and move together. Rejected: a Budget per cell or per
  spawn, more sensitive but turning two levels into four or eight, quadrupling
  what a launcher change re-baselines and changing a requirement structure the
  measured spread does not demand.
- **A17.** A9 sized the reference from Decision 0016's 0.07 ms per
  first-executed node. The first probe falsifies that figure for straight-line
  code by an order of magnitude, so the block lands at 84 ms rather than 280 ms
  and cannot be grown into range: 200 or more groups and about 175 KB in
  Windows PowerShell, and PowerShell 7 nearly flat between 72 and 120 groups.
  The second probe explains it: about 95 per cent of the reader's cost is
  executing functions and loops, and the two kinds of work scale differently
  even between editions on one machine. A9's Assumption is therefore not merely
  unverified for a straight-line reference; the only evidence points against it.
  The unit was also too small — 76 to 89 ms against a launch of 775 to
  1,019 ms, inside the launch's own jitter, which cost one of two VS Code runs
  its entire ratio on 2026-10-07. A reader-shaped reference removes both
  defects at once: the same kind of work by construction, and an own time of
  about 400 ms through the VS Code spawn and 280 ms through the SDK spawn. The
  copy must be frozen and must carry no drift test, because a reference that
  called the shipped reader would move numerator and denominator together and
  detect nothing. The consequence is stated rather than hidden: with the
  reference near the subject, `SessionStart.AddedLatency` becomes a
  relative-regression gate and its absolute stop line stays the guard against a
  regression that moves both, which is the trade A9 made when it put the
  machine's speed outside this record's scope. `PostToolUse.CallLatency` is the
  honest residue: its common path is different and smaller work, its ratio
  against the new reference would be about 0.27 and 0.42 in the two spawns from
  the 2026-10-07 figures, and a 1.5-times spread between two spawns on one
  machine warns that the unit may not cancel machine speed there, so the rule
  now says what happens when the check fails instead of discovering it mid-run.
  Rejected: keeping the 4,000-node script, which lost a run in two and is the
  wrong kind of work; growing it, impractical per the probe and still the wrong
  kind, with a 175 KB fixture nobody can review; and a synthetic workload of
  functions, parameter binding, and loops sized to 280 to 400 ms, closer in kind
  but an opinion that would be re-argued at every reader change and would have
  to be tuned by measurement, where a frozen copy gets the property by
  construction. The synthetic workload stays the fallback if the frozen copy
  ever becomes a maintenance problem.
- **A18.** `lastInjectionUtc` names the injection, and its only use is elapsed
  time since one; seeding it from a resumed session's start, hours old, would
  make the time leg due on the first tool call and duplicate the sentence
  SessionStart had just emitted, while for a new session the two differ by
  milliseconds. A due re-send that finds nothing to send must still be
  recorded, or the standing condition makes every later tool call pay the
  inject path's profile read for a contributor who has opted out; advancing the
  state is bounded and self-correcting, because an opt-in later in the session
  is picked up by the next turn or the next 5 minutes. The calibration step
  must run outside the lock, because it may run to its 3-second cap while
  `Write-CompactionCheckpoint.ps1` waits only 5 seconds for the same lock, and
  the two properties that make that safe are now contract: the locked decision
  never upgrades a backstop into a compaction re-send, so no suffix can lie,
  and the call records the compaction count read before the step, so a
  compaction counted meanwhile is answered by the next call. Check-then-send at
  a bound matches the wording of the Budget and overshoots by one worst-case
  sentence, 13,178 against 12,000, which is 10 per cent of a bound whose
  rationale is written in units of 3,000 tokens; pre-checking would suppress a
  re-send the contributor is entitled to in order to defend that 10 per cent,
  and the `Fail` line was ambiguous about it and is rewritten. Reading the state
  file and the clock with one anchored pattern per field saves about 100 ms of
  module load on the hot path, the very requirement two of these questions are
  about, and each read fails closed in the sense its own file carries: an
  unmatched or malformed state file reads as unreadable, so no backstop fires
  and nothing is written, while a session clock whose `turns` cannot be read
  counts as missing and leaves the 5-minute signal alone, as the Failure-modes
  row for a missing or unreadable clock already states. The clock's `workspace`
  value cannot forge `turns`, because a quote inside it is JSON-escaped and
  breaks the anchor.

**Independent review.** None was commissioned. A14 changes no shipped file in
this amendment, and its pre-authorized fallback reads one more field from a file
the common path already opens, whose forgery causes extra re-sends already
classified in the Failure modes as a bounded degradation. A15 removes an output
claim. A16 is Meter arithmetic. A17 is a test fixture that never ships, reading
only its own fixture through an explicit `-Location`. A18 confirms behaviour the
`security-reviewer` pass of 2026-10-07 already approved, in the shape it
approved. Should the grace fallback be built, the engineer re-runs the
`agent-security-review` checklist over the changed hook path before committing.

### Amendment 3 implemented, 2026-10-07 on Prox1

`software-engineer` built A17 and A18 test-first and ran the Prox1 half of step
7.3 under the new reference. A14 and A15 changed no code, A16 no helper, and
the grace fallback is not built: TBD-7 has found no host that needs it.

**A17.** `tests/Fixtures/ReferenceHook/` replaces
`tests/Fixtures/Invoke-ReferenceHook.ps1`: the driver, a copy of the shipped
reader as committed in `23a861a` with only a header paragraph added, and the
fixture, the same profile text and declaration as the Meter's `[one entry]`
cell. `Get-CalibrationMeterReferenceHash` hashes the folder: per file, in
ordinal order of its relative path, the path, the length of its LF text, and
the text, each ended by a NUL character. The pin is
`30fb3229afc003e248371b378883b2164a8ed00338c9f7647b40acfab2d29c79`, the same in
both editions. Fifteen new tests went red first: the pin, line-ending
independence, a changed driver, reader copy, fixture profile, or declaration
inside its dot folder, a renamed file, an added file, the folder's contents, and
the driver's exit codes in both editions: `0` from a staged copy, `1` in place
and with the profile removed. The build copies only the five customization
folders, so the copy cannot ship. The Meter stages the folder, launches the
driver as `ReferenceHook/Invoke-ReferenceHook.ps1` through the SessionStart
launchers, and adds a `Spread` column to each reproduced row for step 8.

**A18.** Criterion 10's suite already proved the turn-0 arming, the stale-write
answer, and both bounds. Two tests joined it, each green in both editions and
each shown to fail against a deliberately broken hook before the hook was
restored: a resumed session whose recorded start is three hours old makes no
re-send on its first tool call, failing when the seed takes the session start;
and a due backstop after an opt-out emits nothing, advances `lastTurn` and
`lastInjectionUtc`, and leaves `characters` alone, failing when the record is
skipped for an empty sentence. Both suites passed in both editions, 254 tests.

**Step 7.3 on Prox1, 2026-10-07 15:30 UTC.** Two runs, 20 replicates after 2
warm-up replicates each, on an idle machine. No replicate lost the unit. Step
milliseconds over the no-op hook, p50 then p95, ranges over the two runs:

| Cell | VS Code spawn | SDK spawn |
|---|---|---|
| No-op launch, absolute p50 | 772 to 773 | 1,002 to 1,007 |
| Frozen reference, the unit (Past) | 433 to 435; 472 | 348 to 362; 373 to 383 |
| SessionStart, one entry, added | 449 to 455; 460 to 479 | 358; 384 to 389 |
| SessionStart, no profile, added | 184 to 191; 211 to 216 | 166 to 171; 185 to 223 |
| PostToolUse, common path | 112 to 115; 150 to 151 | 119 to 127; 137 to 157 |
| PostToolUse, inject path | 561 to 565; 591 to 596 | 485 to 486; 500 to 508 |
| Push guard, benign tool | 101 to 111; 129 to 133 | 94 to 100; 120 |

Gated ratios, p95 over the two runs, with the lower run and the spread of
step 8:

| Gated cell | VS Code spawn | SDK spawn |
|---|---|---|
| SessionStart, one entry | 1.08 to 1.13, lower 1.08, spread 1.05 | 1.12 to 1.16, lower 1.12, spread 1.04 |
| SessionStart, no profile | 0.49 to 0.49, lower 0.49, spread 1.00 | 0.53 to 0.61, lower 0.53, spread 1.15 |
| PostToolUse, common path | 0.32 to 0.32, lower 0.32, spread 1.00 | 0.38 to 0.44, lower 0.38, spread 1.16 |

Reported ratios, p95: two entries 1.32 to 1.44, inject path 1.34 to 1.48, push
guard 0.29 to 0.36. Both stop lines are clear in every run: the SessionStart
step reaches at most 479 ms against 1,000, and the common path at most 157 ms
against 400. The widest spread is 1.16, well inside the 1.75 factor. On Prox1
alone the rule would give `SessionStart.AddedLatency` w 1.12, Budget 2.0, Fail
4.0, and `PostToolUse.CallLatency` w 0.38, Budget 0.75, Fail 1.5. These are not
levels: each tag's `w` is taken across both machines, and the transfer check
needs RAANDREE3.

Across the two editions on this machine, which is not the TBD-6 check, the
reference's VS Code-to-SDK ratio of its p50 own time is 1.22. The one-entry step's is 1.26, 1.03 times
apart, and the no-profile step's 1.11, 1.10 times apart; the common path's is
0.92, 1.33 times apart. The reader-shaped unit tracks the session-start step
across editions as A17 intended, and the common path is the different kind of
work A17 expected it to be. Should the same hold across machines, the
`PostToolUse.CallLatency` outcome of step 5 applies: no ratio Budget, the
400 ms stop line as its gate.

### Step 7.3 on RAANDREE3, 2026-10-08

The owner ran the Meter on RAANDREE3 at the pinned reference `30fb3229…`. The
first invocation, at 08:29 UTC, completed both runs. A second invocation, at
08:56 UTC, stopped in its first SDK pass when one launch of
`SessionStart, two entries` exited `-2146232797`. The console's table dropped
every column after `Fail`, so the milliseconds of the first invocation are
lost: the reference's own time, every step, and the stop-line check.

Gated ratios, p95 over the two runs of the first invocation, with the lower
run and the spread of step 8:

| Gated cell | VS Code spawn | SDK spawn |
|---|---|---|
| SessionStart, one entry | 0.94 to 0.96, lower 0.94, spread 1.02 | 1.15 to 1.16, lower 1.15, spread 1.01 |
| SessionStart, no profile | 0.39 to 0.41, lower 0.39, spread 1.05 | 0.56 to 0.60, lower 0.56, spread 1.07 |
| PostToolUse, common path | 0.27 to 0.29, lower 0.27, spread 1.07 | 0.40 to 0.42, lower 0.40, spread 1.05 |

Reported ratios, p95: two entries 1.16 to 1.51, inject path 1.39 to 1.56, push
guard 0.31 to 0.40.

**The rule on these ratios, not yet levels.** Across both machines and spawns,
`SessionStart.AddedLatency` takes w 1.15, from RAANDREE3's SDK spawn with one
entry, so Budget 2.25 and Fail 4.5; `PostToolUse.CallLatency` takes w 0.40,
from the same spawn, so Budget 0.75 and Fail 1.5. The highest p95 of any run is
1.16 and 0.44, within both Budgets, and the widest spread, 1.16, stays below
the 1.75 factor. Because the reference and the step run in the same replicate,
the transfer check's `s` over `r` equals, up to the choice of statistic, the
cell's RAANDREE3 ratio over its Prox1 ratio. From each cell's p50 averaged over
its two runs: the one-entry step is 1.01 times apart through the SDK spawn and
1.21 times through VS Code's, the common path 1.03 and 1.15 times. All four are
within 1.3, so both tags pass: the PostToolUse gap seen across editions under
*Amendment 3 implemented* did not carry across machines. These become levels
only from a RAANDREE3 pair with its milliseconds, because step 1 publishes the
reference's own time per machine and spawn and the stop lines read step
milliseconds; this pair then stands as its reproduction check.

**The crash.** `-2146232797` is `0x80131623`, the exit code of .NET's
`Environment.FailFast`; an unhandled exception in a script exits `0xE0434352`
instead, as an experiment on Prox1 showed for both. No script of this
repository calls `FailFast` or runs script code on a thread without a runspace.
The launcher passes the inner process's exit code on, so either PowerShell 7
process of that launch may have failed. The two-entry cell is the only one that
runs git. On Prox1, 400 launches through the SDK spawn, alternating the
two-entry cell with the one-entry cell as a control, with PowerShell 7.6.6 and
git 2.53.0, produced no failure, beside some 350 two-entry SDK launches in
earlier Meter runs; RAANDREE3 failed once in at most 66. Something specific to
RAANDREE3 is involved, its PowerShell 7 build, its git, or its environment, and
which one is unknown until its Application event log or a captured standard
error shows the message `FailFast` writes. A crashed SessionStart hook costs its
whole context, the Memory Bank probe and the session clock as well as the
calibration sentence, so this is a reliability finding although the cell is
reported, not gated.

**The Meter, hardened.** Choices for `software-architect` to confirm:

- A launch that exits non-zero is recorded with its exit code and standard
  error, warned about at once, and run once more in the same position with a
  fresh session; a second failure in a row stops the Meter. A crashed process
  measured no hook time, so the retry changes no measured quantity, and the
  failures CSV keeps the finding. Five tests prove the rule.
- Every row is written to a CSV in the temp folder, stamped with the computer,
  the start time, the reference hash, and the versions of both editions and of
  git, and the rows of an incomplete run are written too, so neither a narrow
  console nor a late failure loses the milliseconds again.

## Signed-off Design Concept

Signed off by the repository owner in chat on 2026-10-06, after an interview
that began on 2026-10-05. The interview ran at
depth Full, covering all twelve `grill-me` categories, with 26 questions (Q1 to
Q25 plus the follow-up Q10b), most carrying three to six sub-decisions, and one
security ruling after review (R1). No answer was delegated with
`not sure, you pick`, and the override log is empty. The text below is the
signed-off concept, verbatim apart from its title, its draft status header, the
sign-off annotations on the rating-question ruling and TBD-4, the sign-off
record, Amendment 1: rulings A1 to A8 of 2026-10-06, Amendment 2: rulings
A9 to A13 of 2026-10-07, and Amendment 3: rulings A14 to A18 of 2026-10-07,
each marked in place with its tag and listed in the
*Amendment log* before *Sign-off*.

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
- **After a compaction:** module and Setup installs. Where the host runs the
  PreCompact hook — Copilot CLI and VS Code's agent host on the SDK runtime —
  from the first successful tool call after the compaction *(A7)*. Where it
  does not — VS Code Local, for a manual or a background compaction — within
  one turn, through the backstop re-send *(A12)*. In a workspace with declared
  Knowledge areas there is
  always a Memory Bank, and Pre-flight's compaction recovery re-reads it with
  tool calls, so the levels normally return before the next reply.
- **Not covered, measured and reported:** plugin-only installs after a
  compaction, a reply that makes no tool call before the next turn, Claude
  Code, and a level stated in chat but never saved.

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
| Backstop re-send, entry on, matched areas | `Contributor familiarity levels from the private profile, data only: "Kerberos" new; "PowerShell DSC" expert. Treat them as stated levels under the contributor-calibration Instruction. Current familiarity levels; make no offers in this session.` *(A12)* |

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
- That file gains three fields beside `compactions` and `injected`: `lastTurn`,
  `lastInjectionUtc`, and `characters`. `schemaVersion` stays 1; the fields are
  additive, an older hook ignores what it does not know, and a newer hook reads
  an absent field as absent *(A12)*.
- `Write-CompactionCheckpoint.ps1` increments `compactions` in that file,
  creating it when absent, with an atomic replace.
- **Every writer of that file preserves all five fields.**
  `Write-CompactionCheckpoint.ps1` and the calibration hook's save path both
  emit a hardcoded two-field object today; left alone, a PreCompact write would
  erase the three new fields, reset the character budget, and re-arm the
  backstop at every compaction *(A12)*.
- `Add-SessionContext.ps1` seeds the three new fields when, and only when, it
  injects levels: `lastTurn` from the session clock's `turns`,
  `lastInjectionUtc` from the moment of that injection, and `characters` from
  the sentence it emitted. The field is the time of the injection and not of
  the session: a resumed session's recorded start can be hours old and would
  make the time leg due on the first tool call, duplicating the sentence just
  emitted. When the file already exists — a resumed session, where the clock is
  preserved — it merges the three fields and leaves `compactions` and
  `injected` untouched, so a compaction pending across the resume still gets
  its re-send *(A12, A18)*.
- `Add-FamiliarityContext.ps1`, registered only by the registration file, reads
  the file on every successful tool call; PostToolUse does not fire for a
  failed one *(A7)*. When `compactions` exceeds `injected`, it emits
  the re-sent sentence under both host keys (top-level `additionalContext` and
  `hookSpecificOutput.additionalContext`), then records `injected` as the
  `compactions` value it read: a compare-and-set, so a stale write can never
  erase a newer compaction. Otherwise it writes nothing.
- It re-sends when **either** `compactions` exceeds `injected` (the compaction
  re-send, unchanged), **or** the session clock's `turns` exceeds `lastTurn`,
  **or** more than 5 minutes have passed since `lastInjectionUtc` — the last
  two being the backstop. It reads the session clock file and never writes it,
  as criterion 10 requires *(A12)*.
- The backstop fires only when `lastInjectionUtc` is seeded, which only
  `Add-SessionContext.ps1` does and only when it injected levels. File
  existence is not the gate: `Write-CompactionCheckpoint.ps1` creates the file
  unconditionally, without any profile or declaration check *(A12)*.
- The time leg is armed only from the first turn boundary onward, so a first
  tool call more than 5 minutes into turn 1 cannot duplicate the SessionStart
  sentence. The turn leg is already safe at turn 1, because SessionStart writes
  `turns = 0` and only the Stop hook advances it *(A12)*.
- **The common path writes nothing and takes no lock.** The calibration step
  runs before the lock is taken, because it may run to its 3-second cap while
  `Write-CompactionCheckpoint.ps1` waits only 5 seconds for the same lock; the
  lock covers the re-read, the decision, and the write only. The inject path
  then takes the lock, re-reads the state, re-decides, writes, and only then
  emits; a failed or timed-out write emits nothing on that call. Without that
  order a 5-second lock timeout would leave a standing backstop condition
  unrecorded, re-firing on every later call while `characters` never advanced.
  The decision taken under the lock never becomes a compaction re-send that the
  decision before the step was not, so no suffix can claim a compaction that
  did not drive it, and the call records the compaction count it read **before**
  the step, so a compaction counted during the step is answered by the next call
  rather than swallowed. `characters` accumulates as a monotonic maximum under
  the same compare-and-set as the existing counters, so parallel tool calls
  cannot undercount it *(A12, A18)*.
- A re-send that falls due and then finds nothing to send — the entry opted out,
  the profile unreadable, or no declared area matched — records the state as
  though it had injected, adding no characters, and emits nothing. Without that
  record the condition would stand and every later tool call in the session
  would pay the inject path's profile read for a contributor who is receiving
  nothing. An opt-in later in the same session is picked up by the next turn or
  the next 5 minutes *(A12, A18)*.
- The state file and the session clock are read with one pattern per field,
  anchored to the field name, rather than with `ConvertFrom-Json`, whose module
  load cost the armed common path about 100 ms. Each read fails closed in the
  sense its own file carries: an unmatched or malformed state file reads as
  unreadable, so no backstop fires and nothing is written, while a session
  clock whose `turns` cannot be read counts as missing, which leaves the
  5-minute signal alone, as the Failure modes already state *(A12, A18)*.
- A backstop re-send is suppressed once `characters` reaches 12,000. A
  compaction re-send is never suppressed below 60,000 and counts toward
  `characters`; above 60,000 the hook emits nothing of either kind. Both bounds
  are tested before the send, so the re-send that reaches a bound still goes
  out and the overshoot is one sentence, at most 1,178 characters. Nothing is
  emitted about the condition and no command reports it: the state file is its
  record, `characters` at or above the bound with the unanswered compactions
  left in `compactions` *(A12, A15, A18)*.
- Both re-sends carry the matched levels only, without the unrated count, and
  both recheck the profile on every injection, so an opt-out or deletion takes
  effect at once even in a session that loaded the registration earlier. The
  compaction re-send ends with the fixed suffix `Re-sent after a compaction;
  make no offers in this session.` and the backstop re-send with `Current
  familiarity levels; make no offers in this session.`, 59 characters each, so
  no re-send repeats the interview, save, or unreadable-profile offers and the
  worst case stays at the measured 1,178 *(A12)*.
- It never emits `decision`, never exits `2`, and every path exits `0` except a
  launcher that cannot resolve the script, which exits `1` as lifecycle hooks
  do.
- Parallel tool calls may inject the sentence twice; that is accepted.
- **Grace fallback, built only if TBD-7 finds a host inside the promise whose
  `turns` never advances.** In that case the time leg is armed either by a clock
  reporting at least one closed turn, as above, or by a clock still reporting
  `turns = 0` in a session whose recorded `startedUtc` is more than 30 minutes
  old. `startedUtc` is read with one more anchored pattern from the clock file
  the common path already opens, so no file access is added. The grace is
  deliberately much longer than the 5-minute leg: a first turn shorter than 30
  minutes, the normal case in every host, keeps today's behaviour and cannot
  duplicate the session-start sentence. Where TBD-7 finds no such host, the
  fallback is not built and the delivery matrix records the per-host `turns`
  values that decided it *(A14)*.

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
Meter: Persistence cases in the private eval kit, at least 6 per Position;
       K = 3; pinned gpt-5.5 judge; compared arms run together. Every case
       carries a provenance field: real-derived, with the stated level moved
       out of the message and into the profile sentence and nothing else
       changed; or synthetic-reviewed, authored and reviewed by the owner,
       with the gap it fills recorded. A real-derived case identifies its
       source only by an opaque local digest, never by a history name, a
       path, a session identifier, or message text, and passes the existing
       redaction step before it becomes a case. At least 3 real-derived per
       Position, and at least one case per Familiarity level per Position. A
       case shared with the Phase 1 set counts once there and once here; the
       two sets stay separate. The kit lives outside every git working tree,
       under the refusal criteria 4 and 24 impose on the profile. (A13)
Past [Phase 1]: 0 % <- Decision 0027, CAL-09 (levels are session-scoped)
Goal [Phase 2 release, each Position]: 100 % pass^3 <- Interview Q1, 2026-10-05
Fail: below 90 % of samples <- Interview Q1
Limitation: Three whole histories, 2,706 user messages, yield at most 3
       usable real restatements, all at `new`; Phase 2 removes the need to
       restate, so the population shrinks rather than grows. A set fed partly
       by authored cases is weaker evidence than one fed entirely by observed
       behaviour. Accepted with A13. (A13)
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
       frozen reference scripts, under [Host spawn] and [Profile: one entry,
       none, two entries]. In each replicate the added time is the time with
       declared areas minus the time without a declaration, and the unit is
       the same replicate's frozen reference script time minus that
       replicate's no-op hook time, both through the same launcher and
       spawn. (A9)
Meter: tests/Fixtures/Measure-CalibrationLatency.ps1, gaining two cells —
       the frozen reference script, and the PostToolUse inject path: 2
       warm-up replicates, then 20 measured replicates, each running the
       baseline, every subject, the no-op hook, the frozen reference script,
       the inject path, and the push guard back to back in rotated order
       through the host's exact spawn, process start included;
       nearest-rank p95; on Prox1 and RAANDREE3; recorded in Decision record
       0028. A value at or below Budget meets it, a value above Fail fails,
       and a verdict above Budget or Fail counts only when a second Meter run
       reproduces it. The hook's full wall-clock time, the no-op launch, the
       frozen reference script's own time, and the push guard are reported in
       milliseconds per machine and spawn, not used as levels. (A9)
Past: withdrawn (A10). The launch-unit readings of 2026-10-06 on Prox1 and
       RAANDREE3 stay under Confirmation as the evidence for A9 and bind
       nothing. The first run under this Meter sets Past.
Budget [one entry, none]: set by the re-baseline rule, from this tag's own w
       (A9, A16)
Fail [one entry, none]: 2 x Budget (A9)
Stop line: the calibration step's own p95 above 1,000 ms on either machine
       means the design, not the unit, is the problem; return to
       software-architect rather than re-baselining. Measured worst under the
       old unit: about 812 ms. (A9)
Report, not gate: [two entries], where the identity rule runs git (A2); the
       absolute milliseconds of every cell (A11)
Rationale: Paid once per chat, only where a workspace declares Knowledge
       areas, by contributors who accept one launch per tool call (Q20). The
       unit is cold script execution, the same kind of work as the measured
       cost, so machine speed, shell edition and load cancel to first order.
       The launcher's own cost belongs to Decision 0016.
Assumption: The frozen reference is the calibration step's own kind of work by
       construction (A17), so for this tag the transfer check is a sanity test
       rather than a leap of faith; A9's original assumption, that a
       straight-line block scales the way the step does, was falsified by
       measurement on 2026-10-07 and is withdrawn. The re-baseline rule still
       checks transfer directly (TBD-6). (A9, A17)
Risk: Changing any file of the frozen reference changes every ratio in this
       record. One composite hash pins the driver, the frozen reader copy, and
       the fixture; a change re-baselines both latency tags in the same commit.
       The frozen reader copy carries no drift test against the shipped reader,
       and adding one would destroy the unit. (A9, A17)
Authority: Repository owner

Tag: PostToolUse.CallLatency
Type: Resource Requirement
Scale: p95 over paired replicates of the calibration PostToolUse hook's own
       script time, in frozen reference scripts, under [Host spawn]. In each
       replicate the script time is the hook's time minus that replicate's
       no-op hook time, and the unit is the same replicate's frozen reference
       script time minus that replicate's no-op hook time, both through the
       same launcher and spawn. Measured on the common path, with the
       backstop trigger evaluated and nothing injected. (A9, A12)
Meter: As SessionStart.AddedLatency.
Past: withdrawn (A10); the 2026-10-06 launch-unit readings stay as evidence.
Budget: set by the re-baseline rule, from this tag's own w; `not set (unit
       does not transfer)` when the transfer check fails for this tag, which
       then gates it on its absolute stop line alone (A9, A16, A17)
Fail: 2 x Budget, or none while no Budget is set (A9, A17)
Stop line: the hook's own script p95 above 400 ms on either machine returns
       to software-architect. Measured worst under the old unit: about
       290 ms, in the noisiest SDK run. (A9)
Report, not gate: the hook's full wall-clock time per machine and spawn,
       beside the push guard's on the same machine (A11); the inject path —
       a call on which the hook re-reads the declaration and the profile and
       emits a sentence — as its own cell, in the same unit and in
       milliseconds, because A12 moves that work from once per compaction to
       once per turn (A12)
Rationale: The common path reads the payload head, runs one regex, reads the
       per-session state file, and reads the session clock file, so it costs
       barely more than a no-op launch. Fallback A applies only when this
       requirement reaches Fail on Prox1 or RAANDREE3 under the unit in force
       (A3, as re-expressed by A9); it has not been reached under any unit.
Assumption: Only machines with a profile that is on pay it (Q20). The frozen
       reference is the session-start step's kind of work, not this tag's: the
       common path is smaller and different, so transfer is not given by
       construction and the check decides per tag whether this tag carries a
       ratio Budget at all (A17).
Authority: Repository owner

Tag: Context.SentenceSize
Type: Resource Requirement
Scale: Characters of the calibration sentence at [Position: session start,
       re-sent after a compaction, re-sent by the backstop]. (A12)
Meter: Pester fixtures for the worst case (16 names of 48 characters at
       familiar) and a typical case (5 areas), at every Position.
Past: 0; existing context 615 of 4,096 <- measured 2026-10-05
Past [worst, fixed template]: 1,118 at session start, 1,178 re-sent
       <- tests/ContributorProfileReader.Tests.ps1, 2026-10-06
Past [worst, backstop]: 1,178, the backstop suffix being 59 characters, the
       same length as the compaction suffix (A12)
Budget [worst, any Position]: 1,200 <- Ruling A4, extended to the backstop
       Position by A12
Budget [typical]: 300 <- Interview Q9, Q18

Tag: Context.SessionBudget
Type: Resource Requirement
Gist: Backstop re-sends never become the context pressure they mitigate, and
      compaction re-sends, which are exempt from that bound, stay under a
      second and far higher ceiling.
Scale: Characters of calibration text injected into one session's context,
       all Positions together.
Meter: A Pester fixture driving a session past each bound with the worst-case
       profile, asserting that backstop re-sends stop at the first, that
       compaction re-sends continue past it, and that nothing of either kind
       is emitted past the second.
Past: 1,118 at most <- Phase 2 before A12, one sentence per session plus one
       per compaction
Budget [backstop re-sends]: 12,000 characters for all Positions together,
       enforced by the hook itself. The bound is tested before the send, so
       the re-send that reaches it still goes out and the session receives at
       most 12,000 plus one worst-case sentence, 13,178 characters (A12, A18)
Budget [ceiling, every Position]: 60,000 characters, tested the same way, so
       at most 61,178. Above it the hook emits nothing of either kind; the
       record of the condition is the state file itself, `characters` at or
       above 60,000 with the unanswered compactions left in `compactions`, and
       no command reports it (A12, A15, A18)
Fail: a backstop re-send issued when `characters` already stood at or above
       12,000, a compaction re-send suppressed while `characters` stood below
       60,000, or any injection issued when `characters` already stood at or
       above 60,000 (A12, A18)
Rationale: 12,000 characters is about 3,000 tokens: 5 per cent of the
       ~60,000-token base prompt this record measured, 1.5 per cent of a
       200,000-token window. At the typical 300-character sentence it allows
       about 39 re-sends; at the 1,178-character worst case, about 10. The
       exemption needs its own ceiling because compaction re-sends are
       unbounded in principle: the record documents a real session with 99
       background compactions over 3 h 42 min, which at the worst-case
       sentence would reach about 116,000 characters. In practice the existing
       compare-and-set collapses every compaction since the last injection
       into a single re-send, so reaching 60,000 needs a tool call between
       compactions almost every time. Above that the session is already
       outside the design's envelope.
Authority: Repository owner

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

### The frozen reference (A9, resized by A17)

`tests/Fixtures/ReferenceHook/`, beside the Meter, never shipped. It holds
three things, and the Meter stages the whole folder into each scratch home's
`hooks/scripts` and launches the driver through the same launcher and spawn as
the measured hooks:

1. `Invoke-ReferenceHook.ps1`, the driver. It reads standard input exactly as
   the no-op hook does, then parses that payload with `ConvertFrom-Json`,
   matches one regular expression against it, and tests one file path — the
   same primitives the shipped hooks use, kept from A9. It then dot-sources the
   frozen reader copy and runs one fixed calibration on the frozen fixture:
   `Get-ContributorCalibration` with the fixture workspace, the fixture
   location passed explicitly through `-Location`, `-SkipGitForSingleEntry`,
   and `-TimeoutMilliseconds 3000`, followed by
   `Format-ContributorCalibrationSentence`. It writes nothing and emits
   nothing; it exits `0` only when that calibration returns state `levels` and
   a non-empty sentence, and exits `1` otherwise, so a fixture that stops
   producing levels fails the Meter instead of silently shrinking the unit. The
   fixture is read only after the Meter has staged the folder outside any git
   working tree: run in place inside the repository, the reader refuses the
   profile as `inside-repository`, so the driver exits `1` there by design.
   `-Location` is passed so the unit never resolves `~/.copilot`, never depends
   on the cell's scratch home, and never reads a contributor's real profile;
   `-SkipGitForSingleEntry` keeps git, whose cost is a machine property rather
   than script work, out of the unit.
2. `ContributorProfileReader.ps1`, a **frozen copy** of the shipped
   `skills/contributor-profile/scripts/ContributorProfileReader.ps1`, taken in
   the commit that introduces the reference and changed only together with a
   re-baseline. **No drift test binds it to the shipped reader, and adding one
   would destroy the unit**: the copy is the yardstick and the shipped reader
   is the subject, so a regression in the shipped reader must move the
   numerator while the denominator stands still. Its header says so, and the
   Meter is its only consumer.
3. The frozen fixture: a workspace folder whose `.memory-bank/projectbrief.md`
   declares a fixed `## Knowledge areas` section, and a
   `contributor/profile.json` holding one entry, on, rating those areas — the
   same shape as the `[one entry]` cell it is the unit for, and single-entry so
   that `-SkipGitForSingleEntry` keeps git out.

Why a reader-shaped reference and not A9's straight-line block: measurement on
2026-10-07 falsified both of that block's premises, and both probes are
recorded under *Rulings, 2026-10-07, second pass*. Its own time through the
launcher is 84 ms at p50 in both spawns, not the ~280 ms A9 sized it for, and
it cannot be grown into that range — the marginal cost is about 1 ms per group
of ~165 nodes in Windows PowerShell and nearly flat in PowerShell 7 between 72
and 120 groups, so ~280 ms would need 200 or more groups and about 175 KB.
Decision 0016's figure of 0.07 ms per first-executed node, which A9 used to
size the block, does not describe straight-line code: the measured marginal
cost is about 0.006 ms per node. A unit of 84 ms also sits inside the launch's
own jitter: one replicate in twenty lost it on 2026-10-07, and the Meter
reports such a run as `unit unmeasurable`, so one of two VS Code runs produced
no ratio at all.

The reader's cost has a different shape: about 95 per cent of it is executing
functions and loops rather than first-executing nodes, and it runs 1.53 times
slower in Windows PowerShell than in PowerShell 7 on one machine, where
straight-line code runs 1.0 to 1.32 times slower. A unit whose work is a
different kind from the measured step's is what A9's Assumption forbids, so the
reference is made the same kind by construction. Its own time is about 400 ms
through the VS Code spawn and 280 ms through the SDK spawn, far above launch
jitter and in the band A9 intended.

The consequence is stated rather than hidden. For `SessionStart.AddedLatency`
the ratio is near 1.0 by construction, so its Budget is a relative-regression
gate — the shipped step may not exceed the frozen step by more than the
re-baseline factor — and the absolute stop line stays the guard against a
regression that moves both, which is the trade A9 made when it put machine
speed outside this record's scope. `PostToolUse.CallLatency`'s common path is
different and smaller work, so its transfer is not given by construction and is
decided per tag by the transfer check (TBD-6).

**Pinning.** `Get-CalibrationMeterBudget` pins one SHA-256 over the whole
reference: the LF text of every file under `tests/Fixtures/ReferenceHook/`,
hashed in ascending ordinal order of relative path, each entry covering the
relative path and the file's text. `Get-CalibrationMeterReferenceHash` computes
it from the folder, `Measure-CalibrationLatency.ps1` refuses to run when it
differs from the pin, and `tests/CalibrationMeter.Tests.ps1` asserts the pin. A
change to any file of the reference — driver, reader copy, or fixture — is a
change to the unit and re-baselines both latency tags in the same commit
(criterion 26).

### The re-baseline rule (A9)

Applied once, by the engineer, in the first Meter run under the new unit, on
both machines and both spawns. It is deliberately mechanical so that it needs
no further architect round:

1. Record the frozen reference script's own time in milliseconds per machine
   and spawn as a new Past line. It is the unit's calibration and must be
   published, not buried in a ratio.
2. Compute one `w` **per tag**, never one for both. For a tag, `w` is the
   maximum, across that tag's **gated cells only** and across both machines and
   both spawns, of each cell's **lower** of its two runs. Gated means
   `[one entry]` and `[none]` for `SessionStart.AddedLatency`, and the
   common-path cell for `PostToolUse.CallLatency`. The `[two entries]` cell,
   the inject-path cell, the push guard, and every absolute-millisecond figure
   are reported and never enter `w`. Taking the lower of the two runs is what
   "reproduced" means in this record: a level counts only when both runs reach
   it. One `w` for both tags would set the common path's Budget from the
   session-start step, which is several times larger: on the Prox1 SDK spawn of
   2026-10-07, in the unit then in force, it would have given every gated cell
   Budget 11.0 against 3.0 for the common path on its own, so a common path
   three times slower than today would still have passed. Within a tag the
   pooling is sound, because a tag's gated cells share a code path and move
   together *(A16)*.
3. `Budget` = the smallest multiple of 0.25 that is at least `1.75 x w`.
   `Fail` = `2 x Budget`.
4. The 1.75 factor must **exceed** the Meter's own run-to-run spread, because
   `w` is taken from the lower run while the Budget must still hold on the
   higher one. The widest pair in the 2026-10-06 runs moved 0.43 to 0.71, a
   factor of 1.65; typical pairs moved by 1.1 to 1.3. Any factor at or below
   1.65 would fail the noisier run by construction.
5. **Unit transfer check (TBD-6), per tag.** Let `r` be the frozen reference's
   RAANDREE3 time divided by its Prox1 time, per spawn, and `s` the same ratio
   for the step of the gated cell that set that tag's `w`. When `r` and `s`
   differ by more than 1.3 times in either direction, the unit has not
   cancelled machine speed for that tag. For `SessionStart.AddedLatency`, whose
   reference is the same kind of work by construction, a failure means the unit
   itself is wrong: record both numbers and return to `software-architect`
   without setting a Budget. For `PostToolUse.CallLatency`, whose common path
   is different and smaller work, a failure sets no ratio Budget for that tag
   in this release: record both numbers, leave `Budget` and `Fail` as
   `not set (unit does not transfer)`, gate the tag on its absolute stop line
   alone, keep TBD-6 open for it, and carry the better unit as named follow-up
   work rather than blocking the release on the cheapest path in the design,
   whose absolute cost is already measured and small *(A9, A17)*.
6. **Stop lines.** Above the absolute stop line in either tag, return to
   software-architect instead of re-baselining. A re-baseline that only ever
   moves the line to wherever the code already sits is not a Meter.
7. Record the computed Budget, Fail, and the run that produced them in the
   Confirmation, together with the reference script's hash.
8. Record the Meter's own run-to-run spread for each gated cell, as the higher
   run's p95 divided by the lower run's. The 1.75 factor was chosen against a
   spread of 1.65 measured under a unit this reference replaces: a materially
   smaller spread makes a tighter factor available to a later amendment, and a
   larger one would mean the factor no longer exceeds the spread, which step 4
   requires *(A17)*.

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
| A9, the latency unit and the frozen reference script | **Fully reversible.** A Meter and a test fixture; nothing ships. Reverting means re-running the Meter under the old unit. The frozen script's bytes are the only thing that must not drift silently, and a test pins them |
| A10, withdrawing the two verdicts | **Fully reversible.** A record change; criterion 20 re-opens and is decided by the next run |
| A11, restating the Consequences | **Fully reversible.** Documentation of measured fact. The rejected one-process launcher stays available as separate work against Decision 0016 |
| A12, the backstop re-send | **Reversible in code, with one durable edge.** The trigger, the bound, and the suffix are a hook change, revertible in one commit. The three new fields in `session-<key>.familiarity.json` are the durable part: the file is private, per-session, recreated every session, and read only by these hooks, so an older hook reading a newer file ignores unknown fields and a newer hook reading an older file sees them absent and treats the session as freshly started. No migration, no user-visible artefact |
| A13, eval case provenance | **Fully reversible.** The eval kit is private and versioned; cases can be re-mined or replaced. The `provenance` field makes a later purge of synthetic cases a filter rather than an archaeology exercise |
| A14, correcting the frozen-`turns` row and pre-authorizing the grace fallback | **Fully reversible.** A record correction now. The fallback, if TBD-7 calls for it, is one condition and one anchored pattern in `Add-FamiliarityContext.ps1`, revertible in one commit; `startedUtc` is already in the session clock, so no schema moves |
| A15, dropping the `Get-` clause for the 60,000 ceiling | **Fully reversible.** No public command changes; adding the report later is additive and would need a session selector, a criterion, and a test |
| A16, one `w` per tag | **Fully reversible.** Meter arithmetic applied once at the re-baseline; `Get-CalibrationMeterRebaseline` already computes `w` from the array it is given, so the rule changes which arrays it is given |
| A17, the reader-shaped frozen reference | **Fully reversible.** A test fixture and a Meter change; nothing ships, and reverting means re-running the Meter under the old reference. The frozen reader copy is a yardstick, not a maintained copy: it is never loaded by the product, reads only its own fixture through an explicit `-Location`, and carries no drift test by design |
| A18, the six implementation choices confirmed | **Reversible in code.** Each is a condition or an ordering inside the PostToolUse and SessionStart hooks, revertible in one commit; none changes the state file's five fields, the profile schema, or a public contract |

Amendment 2 changes no schema, public command, persistence format, or
dependency decision: the five public command names, the profile schema 1, and
the registration contract are untouched *(A9 to A13)*. Amendment 3 changes none
of them either, and changes no shipped file at all unless TBD-7 calls for the
grace fallback *(A14 to A18)*.

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
7. **Amendment 2 (A9 to A13):** what implementation builds or measures next,
   in this order, because each step's result feeds the next.
   1. **A9 — build the unit.** Add `tests/Fixtures/Invoke-ReferenceHook.ps1`,
      hash-pin it, and add its cell and the inject-path cell to
      `Measure-CalibrationLatency.ps1` in the rotated order beside the no-op
      hook. Add the absolute-milliseconds reporting for every cell.
   2. **A12 — build the backstop,** test-first, in this order because the first
      two items are defects an independent review found in the draft: make
      every state-file writer preserve all five fields; move the injection
      behind a successful locked state write; then the three fields, the
      SessionStart seeding and resume merge, the dual trigger with the time leg
      armed from the first turn boundary, the seeded-`lastInjectionUtc` gate,
      the 12,000 and 60,000 bounds, and the 59-character backstop suffix. Do
      this before the re-baseline, because it changes the PostToolUse common
      path that step 3 measures.
   3. **A9, A10, A16, A17 — build the new reference, then re-baseline.**
      Replace `tests/Fixtures/Invoke-ReferenceHook.ps1` with the
      `tests/Fixtures/ReferenceHook/` reference of A17, move the pin to the
      composite hash, stage the folder in `Initialize-MeterHome`, and keep the
      launcher substitution pointing at the driver. Then run the amended Meter
      twice on Prox1 and twice on RAANDREE3. Apply the re-baseline rule
      exactly: publish the reference's own milliseconds, take one `w` per tag
      from that tag's gated cells across both machines and spawns as each
      cell's lower run, run the transfer check per tag, compute Budget and Fail
      per tag, record the run-to-run spread, and check both stop lines. Record
      everything in the Confirmation. Return to `software-architect` only if
      the `SessionStart.AddedLatency` transfer check fails, a stop line is
      crossed, or a run reports `unit unmeasurable`.
   4. **A11 — restate the Consequences and the Purpose** with the amended text,
      and open a separate Decision record proposing the one-process `windows`
      launcher against Decision 0016, with `tests/HookLauncher.Tests.ps1` and
      the push guard's exit-code contract as its gate. Do not implement it in
      this release.
   5. **A12 — re-measure delivery.** Extend the `Calibration.Delivery` matrix
      with the VS Code Local backstop cell, answer TBD-7, and perform the
      manual compaction check in VS Code Local that criterion 22 now requires.
   6. **A13 — rebuild the persistence set.** Record the eval kit's location and
      prove the working-tree refusal (TBD-8), add `provenance` with an opaque
      digest to every case, derive 3 cases per Position from the real
      restatements through the existing redaction step, author the synthetic
      top-up for `familiar` and `expert`, submit the synthetic cases to the
      owner for review, and re-run the eval.
   7. **Close out.** Criteria 10, 14, 20, 21, 22, and 26 to 29 all move
      together; none of them is done until the re-baseline and the eval are
      recorded here.
8. **Amendment 3 (A14 to A18):** the record corrections of A14, A15, and A18
   land with the Amendment 3 edit itself and need no code. Where criterion 10's
   suite does not already prove an A18 clause — the seeding moment, the
   opted-out re-send that records and emits nothing, the compaction counted
   during the step — the test joins it in the same commit as the edit. A16 and
   A17 are prerequisites of step 7.3 and are built before the re-baseline run.
   A14's grace fallback is built only if step 7.5's TBD-7 measurement finds a
   host that needs it, with its own test in both editions and criterion 30 as
   its gate.

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
| Session clock file missing or unreadable at a PostToolUse call | The turn signal is unavailable; the 5-minute signal alone drives the backstop; no error, nothing written *(A12)* |
| `turns` never advances in a host whose clock is readable | Neither signal fires: the turn leg needs a closed turn, and the time leg is armed only by a clock reporting at least one, so that host receives no backstop and the Purpose's "within one turn" does not hold there. Whether such a host exists inside the promise is TBD-7, measured per host in the delivery matrix; finding one builds the grace fallback in the Outputs *(A12, A14)* |
| A session reaches the 12,000-character bound | Backstop re-sends stop for the rest of the session; compaction re-sends continue; nothing is reported to the model *(A12)* |
| A session reaches the 60,000-character ceiling | No injection of either kind for the rest of the session. The record of the condition is the state file: `characters` at or above 60,000, with the unanswered compactions left in `compactions`. No command reports it, because the per-session state is hook-private and no command is given a session identifier *(A12, A15)* |
| The state write fails or the lock times out on an inject path | Nothing is emitted on that call; the backstop re-evaluates on the next one, so no condition is lost and none re-fires unrecorded *(A12)* |
| A resumed session meets an existing state file | The three new fields are merged, `compactions` and `injected` are left alone, and a compaction pending across the resume still gets its re-send *(A12)* |
| A compaction in a session where SessionStart injected nothing | `Write-CompactionCheckpoint.ps1` still creates the state file, but `lastInjectionUtc` is unseeded, so no backstop fires and no profile is read *(A12)* |
| An agent with file tools writes the session clock | A high `turns`, or an old `startedUtc` where the grace fallback is built, makes backstop re-sends fire more often, bounded by the 12,000-character budget; a frozen `turns` disables the turn leg only, leaving the 5-minute leg wherever it is armed. Both are degradations, not escalations *(A12, A14)* |

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

**R1 revisited under A12,** because R1's reasoning was partly frequency-based
and A12 changes the frequency. The accepted Low risk is unchanged in reach: the
sentence names only Knowledge areas present in **both** the workspace's
`projectbrief.md` and the contributor's private profile, so a hostile workspace
still learns nothing it did not already name, and repetition cannot widen a set
the contributor owns. What A12 changes is **salience**: a guessed name now
appears up to about 10 times in a worst-case session and about 39 in a typical
one, late in context, instead of once plus once per compaction. The strict
area-name grammar — no quotes, backticks, `; = < > * _`, or control characters
— keeps every repetition inside the quoted, data-only framing, and the
offer-suppressing suffix is carried at every Position by criterion 14, so the
increase is quantitative rather than a new capability. The risk stays Low on
that basis, now stated in terms of salience rather than of a single injection
*(A12)*.

The lethal trifecta stays broken at leg 3. The hook layer gains exactly one
additional **read** of a local file whose path is derived through the same
sanitiser as every other session-keyed path: no network call, no new tool, no
repository code executed, no new traversal surface. An agent with file tools
that writes the session clock can force more re-sends or freeze the turn leg;
both are bounded degradations under `Context.SessionBudget`, not escalations,
and neither moves private data outward *(A12)*.

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
10. PreCompact increments `compactions` in the calibration state file; the
    first PostToolUse after it emits the re-sent sentence under both host keys
    and records `injected` by compare-and-set. A backstop re-send is emitted on
    the first successful tool call after the session clock's `turns` advances,
    or after 5 minutes since `lastInjectionUtc` once the clock reports at least
    one closed turn, or after 5 minutes when the clock is missing or
    unreadable, carrying the backstop suffix and never the compaction suffix; a
    readable clock whose `turns` still reads 0 arms neither leg, proved by a
    test *(A12, A14)*.
    Every writer of the state file preserves all five fields, proved by a test
    in which a PreCompact write follows a backstop injection and leaves
    `lastTurn`, `lastInjectionUtc` and `characters` intact. SessionStart seeds
    the three new fields only when it injects, and merges rather than resets
    them when the file already exists; an unseeded `lastInjectionUtc`, not an
    absent file, is what stops the backstop, proved by a test in which
    PreCompact creates the file in a session that injected nothing. The common
    path writes nothing and takes no lock; the inject path takes the lock,
    re-reads, re-decides, writes, and only then emits, and a failed or
    timed-out write emits nothing on that call. `characters` accumulates as a
    monotonic maximum under compare-and-set. Backstop re-sends stop at 12,000
    characters while compaction re-sends continue, and nothing of either kind
    is emitted above 60,000. Other calls emit nothing; a test that interleaves
    a stale PostToolUse write with a newer PreCompact never loses the newer
    compaction; no calibration hook rewrites the session clock file; neither
    hook emits `decision` or exits `2` *(A12)*.
    `lastInjectionUtc` is seeded from the moment of the injection, proved by a
    test in which a resumed session whose recorded start is hours old makes no
    re-send on its first tool call. The calibration step runs outside the lock,
    and a compaction counted during it is answered by the next call, not by the
    call in flight. A due re-send that yields no sentence records the state as
    though it had injected and emits nothing, proved by a test in which an
    opted-out entry leaves `lastTurn` and `lastInjectionUtc` advanced and
    `characters` unchanged. Both bounds are tested before the send, so a
    session receives at most the bound plus one sentence *(A14, A18)*.
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
    reply saves nothing; **every** re-sent sentence, at the compaction Position
    and at the backstop Position alike, carries no unrated count and suppresses
    every offer for the rest of the session *(A12)*.
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
20. The latency levels hold on Prox1 and RAANDREE3 per the Meter as amended:
    the frozen reference as the unit, 20 paired replicates in rotated order,
    inclusive thresholds, and a verdict above Budget or Fail reproduced in a
    second run. The re-baseline rule is applied once, per tag, and each tag's
    `w`, Budget, Fail, the reference's composite hash, its own milliseconds per
    machine and spawn, and the run-to-run spread are recorded in Decision
    record 0028. No run reports `unit unmeasurable`. The unit transfer check
    passes for `SessionStart.AddedLatency`; where it fails for
    `PostToolUse.CallLatency`, that tag carries no ratio Budget, is gated on
    its absolute stop line, and the failing numbers are recorded. The
    two-entry cell, the inject path, the push guard, and every cell's absolute
    milliseconds are reported *(A9, A10, A11, A16, A17)*.
21. Eval: `Calibration.Persistence` 100 % pass^3 at each Position, over a set
    of at least 6 cases per Position with at least 3 `real-derived` and at
    least one case per Familiarity level, every case carrying its provenance;
    Phase 1 51 of 51 with a sentence present, counted over its own set; the
    offer and safety groups meet the same gates (TBD-4, resolved at sign-off)
    *(A13)*.
22. `Calibration.Delivery`: every cell inside the promise delivers the
    sentence, and the reported cells are measured and recorded. The SDK runtime
    probe shows the PostToolUse `additionalContext` reaching the model and the
    `sessionStart` `hook.end` event carrying the sentence. One manual
    compaction in Copilot CLI shows the PreCompact-driven re-injection; one
    manual compaction in VS Code Local shows the backstop re-injection within
    one turn, with no PreCompact having run *(A12)*.
23. The Glossary defines Contributor profile; the hooks README, README, and
    CHANGELOG describe the change; Decision record 0028 is accepted and indexed.
24. A test runs every writer against a temporary git repository and proves that
    no Familiarity level lands under a git working tree.
25. Every script that derives the session clock path (SessionStart, Stop,
    PreCompact, PostToolUse, and the elapsed reader) derives the same path for
    one shared fixture set.
26. Every file of the frozen reference — the driver, the frozen reader copy,
    and the fixture — is covered by one pinned composite hash; a change to any
    of them fails `tests/CalibrationMeter.Tests.ps1`, and the Meter refuses to
    run until both latency tags are re-baselined in the same commit. The frozen
    reader copy is bound by no drift test to the shipped reader; its header
    records why, and the Meter is its only consumer *(A9, A17)*.
27. `Context.SessionBudget` holds: a fixture driving a session past 12,000
    characters proves that backstop re-sends stop and compaction re-sends do
    not, and a fixture driving it past 60,000 proves that neither kind is
    emitted and that the condition is recorded *(A12)*.
28. No persistence eval case records a history name, a path, a session
    identifier, or source message text: `provenance` on a `real-derived` case
    carries only an opaque local digest, and every derived case passes the
    existing redaction step. The eval kit's location is recorded in this record
    and lies outside every git working tree, proved by the same working-tree
    refusal criteria 4 and 24 apply to the profile *(A13)*.
29. The reported cells are produced and recorded: the inject path's own time in
    the new unit and in milliseconds, per machine and spawn, beside the common
    path's *(A12, A11)*.
30. The delivery matrix records, per host inside the promise, whether the
    session clock's `turns` advances between turns, with the observed value.
    Where a host's clock is readable and its `turns` never advances, the grace
    fallback is built and proved in both editions by a test in which a clock
    frozen at `turns = 0` arms the time leg once the recorded `startedUtc` is
    more than 30 minutes old and does not arm it before; where no such host is
    found, the fallback is absent and the matrix records the per-host values
    that decided it *(A14)*.

## Open questions

| ID | Question | Owner | Effect |
|---|---|---|---|
| TBD-1 | Does the first SessionStart text survive a compaction in VS Code Local and the SDK host? | software-engineer, spike before increment 2 | Only how often PostToolUse is the sole carrier |
| TBD-2 | What OneDrive names a conflict copy | software-engineer, observed once on two machines | None; only `profile.json` is read |
| TBD-3 | Exact wording of the Instruction, Pre-flight, and Prompt sentences within the caps | software-engineer, measured by the eval | Wording only |
| TBD-4 | Gates for the offer and safety eval groups | Resolved at sign-off: equal to `Calibration.Persistence` | Measurement only |
| TBD-5 | Closed: **no.** The reader's cold cost does not scale with the launch cost across machines. A9 retires the launch unit | — | Closed by the RAANDREE3 run |
| TBD-6 | Does the frozen reference script's cold cost scale across machines and spawns the same way the calibration step's does? | software-engineer, the re-baseline run, step 5 of the rule | Whether the new unit cancels machine speed; if not, back to software-architect |
| TBD-7 | Does `turns` advance in every host inside the promise? Measured per host, with the observed value recorded | software-engineer, measured in the delivery matrix | Whether the backstop fires at all in that host. A host whose clock is readable and whose `turns` never advances receives no backstop today; finding one builds the grace fallback *(A14)*. Measured so far: the SDK-runtime agent host advanced `turns` to 2 between turns on 2026-10-07; VS Code Local is unmeasured |
| TBD-8 | Where does the private eval kit live, and does it satisfy the working-tree refusal? | software-engineer, recorded before the persistence set is rebuilt | Whether chat excerpts can reach a repository |

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

Amendment 2, 2026-10-07: rulings A9 to A13, answering the five results that
implementation returned in the second round, with twelve findings from an
independent review of the draft folded in. The reasons are under
*Rulings, 2026-10-07* in the Confirmation.

| Ruling | Passages amended |
|---|---|
| A9 | `SessionStart.AddedLatency` and `PostToolUse.CallLatency`: Scale, Meter, Past, Budget, Fail, Stop line, Rationale, Assumption, Risk; the frozen reference script and the re-baseline rule; Delivery increments; criterion 20; new criterion 26; Open questions: TBD-5 closed, TBD-6 added |
| A10 | `SessionStart.AddedLatency` and `PostToolUse.CallLatency`: Past withdrawn; criterion 20; the fallback A condition under `PostToolUse.CallLatency` |
| A11 | Consequences; `SessionStart.AddedLatency` and `PostToolUse.CallLatency`: Report, not gate; new criterion 29; the one-process launcher recommended to Decision 0016 |
| A12 | Purpose; Consequences; Outputs: PostToolUse re-injection and the sentence table; `Context.SentenceSize`: Scale, Past, Budget; new `Context.SessionBudget`; Security: R1 revisited; Failure modes; criteria 10, 14 and 22; new criteria 27 and 29; Open questions: TBD-7 added |
| A13 | `Calibration.Persistence`: Meter, Limitation; criterion 21; new criterion 28; Open questions: TBD-8 added |
| A9 to A13 | Durable choices and their reversibility; Delivery increments: the build order for implementation |

Amendment 3, 2026-10-07: rulings A14 to A18, answering the four questions
implementation returned while building Amendment 2 and confirming the six
choices it made within the text. A17 withdraws A9's sizing of the frozen
reference on measurement that falsified both of its premises. The repository
owner answered the six decisions the architect round put to them with the
recommended answers, and delegated none of them with `not sure, you pick`. No
independent review was commissioned, because no ruling introduces or alters an
attack surface. The reasons are under *Rulings, 2026-10-07, second pass* in the
Confirmation.

| Ruling | Passages amended |
|---|---|
| A14 | Failure modes: the frozen-`turns` row and the writable-clock row; Outputs: the conditional grace fallback; criterion 10; new criterion 30; Open questions: TBD-7 |
| A15 | Failure modes: the 60,000 row; Outputs: the bounds bullet; `Context.SessionBudget`: Budget, Fail |
| A16 | The re-baseline rule: step 2; `SessionStart.AddedLatency` and `PostToolUse.CallLatency`: Budget; criterion 20 |
| A17 | The frozen reference script, replaced by the frozen reference; the re-baseline rule: steps 5 and new 8; `SessionStart.AddedLatency`: Assumption, Risk; `PostToolUse.CallLatency`: Budget, Fail, Assumption; criteria 20 and 26; Delivery increments 7.3 |
| A18 | Outputs: seeding, the lock ordering, the due re-send that yields nothing, the field-pattern reads, the bounds; `Context.SessionBudget`: Budget, Fail; criterion 10 |
| A14 to A18 | Durable choices and their reversibility; Delivery increments: new item 8 |

## Sign-off

- [x] The user read this document end to end.
- [x] The user accepted every section, including the ruling on rating and save
  questions and the TBD-4 gates.
- [x] The user typed `SIGNED OFF` in chat on 2026-10-06.

Amendment 1:

- [x] The user read the Amendment log and every passage it marks.
- [x] The user accepted rulings A1 to A8.
- [x] The user typed `SIGNED OFF` in chat on 2026-10-06.

Amendment 2:

- [x] The repository owner read the amendment end to end.
- [x] The repository owner accepted rulings A9 to A13, choosing
  "Accept all four (Recommended)" for the four decisions behind them.
- [x] The repository owner signed it off in chat on 2026-10-07, relayed through
  `software-engineer`, which dispatched `software-architect` to record it.

Amendment 3:

- [x] The repository owner read the summary relayed in chat: each ruling, the
  six decisions with their reasons, alternatives, and undo cost, and the two
  engineer additions folded into A17 and A18.
- [x] The repository owner accepted rulings A14 to A18 and answered the six
  decisions the architect round put to them with the recommended answers.
- [x] The repository owner signed it off in chat on 2026-10-07, relayed through
  `software-engineer`, which dispatched `software-architect` to record it.
