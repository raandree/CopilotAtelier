# Security reviews

Independent security and quality reviews of changes to Copilot Atelier, newest
first. Each entry records the scope, the verdict, every finding with its
severity and resolution, and the risks that remain.

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
