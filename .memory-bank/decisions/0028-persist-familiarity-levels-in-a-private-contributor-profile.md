---
status: accepted
date: 2026-10-06
last-verified: 2026-10-06
owner: software-architect
source: software-architect Design Concept interview 2026-10-05 to 2026-10-06 and sign-off 2026-10-06; Decision record 0027; hook host references (VS Code, GitHub, Claude Code), fetched during the interview
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
  tool call after the PreCompact hook advanced a counter. Its hook file exists
  only while the machine's profile has an active entry with levels.
- A new `contributor-profile` Skill and five
  `*-CopilotAtelierContributorProfile` commands share one implementation for
  the interview, saving, opt-out, deletion, export, import, and diagnosis.

The architect first recommended a Skill reader that the agent runs on
compaction recovery. The contributor chose the deterministic hook path instead
and accepted its per-call cost on machines with an active profile. An
independent review found 2 Blockers and 5 Majors in the first draft; all are
fixed or ruled, as recorded below.

## Consequences

- On a machine with an active profile, every tool call in a session started
  while the registration exists costs about 0.6 s (VS Code) or 0.85 s (SDK
  host) more. Machines without a profile pay nothing.
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

Pending implementation by `software-engineer`. The signed-off Acceptance
criteria 1 to 25 below are the contract; the spike TBD-1 runs before increment
2. Implementation records its evidence here: the eval results against
`Calibration.Persistence` and `Calibration.PhaseOneGuard`, the
`Calibration.Delivery` matrix, and the latency Meter on Prox1 and RAANDREE3.

## Signed-off Design Concept

Signed off by the repository owner in chat on 2026-10-06, after an interview
that began on 2026-10-05. The interview ran at
depth Full, covering all twelve `grill-me` categories, with 26 questions (Q1 to
Q25 plus the follow-up Q10b), most carrying three to six sub-decisions, and one
security ruling after review (R1). No answer was delegated with
`not sure, you pick`, and the override log is empty. The text below is the
signed-off concept, verbatim apart from its title, its draft status header, the
sign-off annotations on the rating-question ruling and TBD-4, and the sign-off
record.

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
- **After a compaction:** module and Setup installs, from the first tool call
  after the compaction. In a workspace with declared Knowledge areas there is
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
9. `Uninstall-CopilotAtelier` removes an unchanged registration file; the
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
| Several people on one shared lab account | Each imports their own entry | The right entry is selected; another person's levels never block theirs |
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

No free-text field exists: no notes, no language, no nationality. Any unknown
property, wrong type, unknown level, other schema version, exceeded cap,
case-only duplicate area name, or name that breaks the area-name rule rejects
the whole file.

**Area-name rule (Q16)**, identical in the profile and in `projectbrief.md`: 1 to
48 characters after trimming and Unicode NFC normalization; letters of any
script, digits, single spaces, and `. + # / & ( ) -`; starts with a letter or a
digit. Matching is case-insensitive (invariant culture) and exact; `DSC` and
`PowerShell DSC` are different areas.

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
  the file on every tool call. When `compactions` exceeds `injected`, it emits
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
   creates or deletes the file; it records the file's SHA-256 and completes the
   record afterwards. The next writer, `Get-`, or Uninstall reconciles a pending
   record against the observed file.
2. A file is deleted only when all three hold: it sits at the fixed path, the
   record says this writer created it, and its current SHA-256 equals both the
   recorded hash and the shipped template's hash.
3. A file at the fixed path without a record is never overwritten or deleted,
   even when its bytes match the template; the writer reports it.
4. `Uninstall-CopilotAtelier` takes the same lock and reconciles the registration
   before it removes any file. When the registration cannot be reconciled (a
   modified file, a foreign file, or a held lock), Uninstall stops before
   removing anything and names the file, because removing the Owned script would
   leave a hook that warns on every tool call. It reads only the record, never
   levels.
5. No release payload may ship `hooks/contributor-profile.json`.

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
removes it under the deletion rule above.

Known limit: a plugin-only install has no `~/.copilot/hooks/scripts`, so the
registration cannot resolve the script. Plugin-only users get SessionStart
levels but no re-injection after a compaction.

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
| `Get-CopilotAtelierContributorProfile [-WorkspacePath] [-ShowAliases]` | Location, synced or this machine only, selected entry and why, levels, the exact sentence for the workspace, possible conflict copies, an orphaned or pending registration; aliases masked (`r***@contoso.com`) unless `-ShowAliases` |
| `Set-CopilotAtelierContributorProfile` | `-KnowledgeArea`/`-Level`, `-State On\|Off`, `-AddAlias`/`-RemoveAlias`, `-Default`; manages the registration file |
| `Export-CopilotAtelierContributorProfile -Path [-Contributor]` | Writes a schema-1 file; refuses a destination inside a git working tree |
| `Import-CopilotAtelierContributorProfile -Path` | Strict validation, then merge; `-WhatIf` previews |
| `Remove-CopilotAtelierContributorProfile [-Contributor] [-RegistrationOnly]` | Deletes an entry, the file, or only an orphaned registration; `ConfirmImpact = 'High'`; removes a registration only under the deletion rule |

`-Contributor` accepts an `id` or an alias and must resolve to exactly one entry;
anything else fails before any write.

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
Scale: Added milliseconds at p95 for the session-start hook under [Host spawn].
Meter: 10 warm runs through the host's exact spawn, process start included,
       on Prox1 and RAANDREE3; recorded in Decision record 0028.
Past [VS Code spawn, Prox1]: p95 334 ms total <- measured 2026-10-05
Past [SDK spawn, Prox1]: p95 512 ms total <- measured 2026-10-05
Budget: +100 ms <- Interview Q18
Fail: +250 ms <- Interview Q18

Tag: PostToolUse.CallLatency
Type: Resource Requirement
Scale: Milliseconds at p95 for one non-injecting tool-call hook under [Host spawn].
Meter: As SessionStart.AddedLatency.
Past [proxy: push guard, benign tool, VS Code spawn, Prox1]: p95 576 ms <- measured 2026-10-05
Past [proxy, SDK spawn, Prox1]: p95 846 ms <- measured 2026-10-05
Budget [VS Code spawn]: 600 ms; [SDK spawn]: 900 ms <- Interview Q18
Fail: above 1,000 ms <- Interview Q18
Assumption: Only machines with a profile that is on pay it (Q20).

Tag: Context.SentenceSize
Type: Resource Requirement
Scale: Characters of the calibration sentence.
Meter: Pester fixtures for the worst case (16 names of 48 characters) and a
       typical case (5 areas).
Past: 0; existing context 615 of 4,096 <- measured 2026-10-05
Budget [worst]: 1,100; [typical]: 300 <- Interview Q9, Q18

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
profile that is on. A remains the fallback if B1 misses its latency budget.

### Location (Q4)

Following the hooks link (chosen) needs no installer change and survives a
custom `-TargetPath`. A fixed `~/.copilot/contributor` linked by the installer
would add a sixth Discovery link to create, verify, remove, and reconcile.

### Durable choices and their reversibility

| Choice | Reversibility |
|---|---|
| Schema 1 fields (including `id` and global alias uniqueness) and the area-name rule | Loosening later is safe; tightening breaks existing files |
| Location under `contributor/` | Movable only with a migration step |
| Five public command names | Public API; renaming needs deprecation aliases |
| `## Knowledge areas` in `projectbrief.md` | Moving it later touches every project's Memory Bank |
| Registration file name, reserved in payloads | Changing it needs a migration of existing registrations |

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
| Crash between the registration record and the file | The pending record is reconciled by the next writer, `Get-`, or Uninstall |
| Foreign or modified registration file | Never overwritten or deleted; reported; Uninstall stops before removing anything |
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
  control characters fail.
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
- The registration file is a fixed template at a fixed path, deleted only when
  the record, the recorded hash, and the shipped template's hash all agree; a
  record can never redirect a deletion.
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
  an orphaned registration, the registration under the deletion rule.
- `Uninstall-CopilotAtelier` keeps the profile as personal content, reconciles
  and removes an unchanged registration first, and stops before removing
  anything when it cannot. Open chats must be restarted afterwards, as for every
  shipped hook.
- A release rollback leaves profile files unused and harmless; an unknown
  schema version degrades to familiar.

## Acceptance criteria

1. The hook, the Skill script, and all five commands resolve the same profile
   path for one fixture set, following the location rule.
2. Every schema violation in a shared fixture set (at least one per rule) yields
   no levels and exactly one reason code in every entry point; a valid fixture
   yields identical levels in every entry point.
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
    least one area and matches the shipped template byte for byte. Its record
    is written as pending before the file changes and reconciled after a
    simulated crash at each step. A file is deleted only when the fixed path,
    the record, the recorded hash, and the template's hash all agree; a foreign
    or modified file is reported and never touched.
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
    write.
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
20. The latency budgets hold on Prox1 and RAANDREE3 per the Meter, recorded in
    Decision record 0028.
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

## Sign-off

- [x] The user read this document end to end.
- [x] The user accepted every section, including the ruling on rating and save
  questions and the TBD-4 gates.
- [x] The user typed `SIGNED OFF` in chat on 2026-10-06.
