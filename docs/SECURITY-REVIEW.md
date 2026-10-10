# Security reviews

Independent security and quality reviews of changes to Copilot Atelier, newest
first. Each entry records the scope, the verdict, every finding with its
severity and resolution, and the risks that remain.

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
