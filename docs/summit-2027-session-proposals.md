# PowerShell Summit 2027 session proposals

Submission-ready copy for two sessions at the PowerShell Summit 2027. Every
field below maps directly onto a Sessionize field. Paste and submit; the
commentary sections are marked as preparation aids and are not part of the
submission.

## Deadline and submission facts

| Item | Value |
|---|---|
| Event | PowerShell Summit 2027 |
| Dates | 5–8 April 2027 |
| Venue | Sheraton Lake Buena Vista, Orlando, Florida |
| Submission portal | <https://sessionize.com/pshsummit27> |
| Call opened | 1 July 2026 |
| **Call closes** | **31 August 2026, 23:59 EDT (1 September 03:59 UTC)** |
| Proposal limit | 10 per submitter |
| Delivery | In person, in Orlando, in English. No remote option. |

Required fields per proposal: session title, abstract of roughly 150–300 words,
three to five learning objectives, target audience level, session format, and a
speaker biography. The biography is used in round two only.

Session formats and honoraria:

| Format | Honorarium |
|---|---|
| 25-minute Fast-Focus | $250 |
| 45-minute Breakout | $500 |
| 90-minute Deep Dive | $1,000 |
| 4-hour Hands-On Lab | $2,000 |

Sunday-to-Wednesday lodging can be taken in place of the honorarium for a
speaker with either two 45-minute sessions or one 90-minute session. The choice
is declared on acceptance and cannot be reversed.

## How reviewers will read this

Round one is **blind**. Submissions are anonymized and judged on the words
alone, without the speaker's name, employer, or track record. Round two
compares the surviving proposals and curates a balanced program.

Three consequences shaped the copy below:

- No credential appeals, no "trust me", no reliance on recognizability. The
  two-year first-person arc appears because it is the *provenance of the
  material*, not because it is a qualification.
- The project is never named. A blind reviewer gains nothing from an unfamiliar
  project name, and the abstract has to stand on the problem it solves.
- No product tour. The library is the evidence and the demonstration surface;
  the sessions are about the decisions, the mechanics, and the failures.

The counts in the Proposal 1 abstract (13 agents, 16 instruction files, 46
skills, 3 hooks) are current as of 31 August 2026. Re-check them against the
repository immediately before pasting.

---

## Proposal 1 — the anatomy session

### Title

> Five Ways to Tell Copilot What to Do — and Only One of Them Is Enforceable

Alternates, if a plainer title is preferred:

- Agents, Instructions, Skills, Prompts, and Hooks: Which One Do You Actually
  Need?
- The Anatomy of an AI Customization: What Loads, What Binds, What Silently
  Does Nothing

### Format and level

- **Format**: 90-minute Deep Dive.
- **Target audience**: Intermediate.
- **Why 90 minutes**: five artifact types, each with its own frontmatter,
  loading moment, authority, and failure mode, plus live diagnosis and
  packaging. At 45 minutes two of the five get cut and the failure gallery —
  the part attendees cannot get from documentation — goes first. A genuinely
  scoped 45-minute variant is in the appendix, and it drops content rather than
  compressing it.

### Abstract

> A rule an AI coding agent can decide to ignore is not a control; it is a
> preference. The distinction stays invisible until it matters — you want an
> agent that never runs `git push`, and no amount of careful wording in an
> instruction file will give you one.
>
> There are five ways to steer that agent — a custom agent, an instruction file,
> a skill, a prompt file, and a lifecycle hook — and exactly one of them is
> enforceable. In the folder they look interchangeable. They are not. Each loads
> at a different moment, carries different authority, and fails in its own
> silent way.
>
> This session dissects all five for people who ship PowerShell. What each
> frontmatter actually controls. Which of them the model may decline and which
> it never gets a vote on. How an `applyTo` glob scopes a rule to `**/*.ps1` but
> leaves your `build.yaml` uncovered. Why a skill's description, not its body,
> decides whether it ever loads. How a PowerShell hook script blocks a command
> by exit code, outside the model's judgment entirely.
>
> The failure gallery is where the time goes, because every entry is silent.
> Hook commands whose `$` tokens are eaten by the host shell before PowerShell
> ever parses them. One settings key that replaces the hook location map instead
> of extending it. A skill missing frontmatter that never registers.
>
> Demonstrated throughout on a real open-source library — 13 agents, 16
> instruction files, 46 skills, 3 hooks — shipped as a PowerShell Gallery module
> and installed in one command. It is the residue of two years spent moving from
> writing every line of PowerShell and C# by hand to having an agent write
> nearly all of it.

### Learning objectives

1. Choose the correct customization type for a given rule using one test: must
   this hold regardless of what the model decides?
2. Scope a coding standard with an `applyTo` glob so it reaches every `.ps1`,
   `.psm1`, and `.psd1` that needs it and nothing that does not.
3. Write the frontmatter that actually controls behavior — tool allow-lists,
   model priority arrays, subagent eligibility, and handoffs.
4. Prove that an agent, instruction, skill, prompt, or hook is genuinely loaded,
   using the chat customizations editor, the agent debug log, and the hooks
   output channel.
5. Package a customization library as a PowerShell module so it installs on the
   next machine in one command instead of being copied by hand.

### Outline — preparation aid, not submitted

| Minutes | Segment |
|---|---|
| 0–8 | The problem: five file types, one folder, no error messages |
| 8–20 | Instructions — `applyTo`, re-sent every request, advisory authority |
| 20–34 | Skills — on-demand loading, the description as the trigger surface |
| 34–48 | Agents — mode instruction, tools, model priority arrays, handoffs |
| 48–56 | Prompts — user-invoked templates and where they differ |
| 56–70 | Hooks — the only enforceable layer; exit code 2; PowerShell scripts |
| 70–80 | The failure gallery, live |
| 80–88 | Packaging and distribution: module, plugin, both clients |
| 88–90 | The decision test on one slide, and questions |

---

## Proposal 2 — the process session

### Title

> The Agent Did the Typing. Here Is What Kept It Honest.

Alternates:

- Heavy AI-Assisted Development: Two Years of Guardrails, Memory, and Things
  That Silently Broke
- From Writing Every Line to Reviewing Every Line: The Process That Made It Work

### Format and level

- **Format**: 45-minute Breakout.
- **Target audience**: Advanced.
- **Stated assumption** (belongs in the submission notes): attendees already use
  an AI coding agent regularly. The session is about the engineering process
  around one, not about how to start using one.
- **Why 45 minutes**: this is a curated field report with four practices and
  three counter-lessons. It is well matched to a breakout and would pad at 90.

### Abstract

> Two years ago I wrote every line of PowerShell and C# myself. Today an agent
> writes almost all of it, and the bottleneck stopped being typing. It became
> trust: knowing what actually changed, whether the build is really green, and
> what the agent quietly forgot between one session and the next.
>
> This is a field report from a Sampler-built module developed that way, for
> people who ship modules, DSC configurations, and pipelines.
>
> Four things carried the weight. A per-turn contract: a discovery step before
> the agent's first tool call and a close-out gate before its last answer, with
> an exemption so a plain question costs nothing. Durable memory:
> version-controlled project knowledge with a routing table, so the agent reads
> the three files a task needs instead of the whole repository, with a build
> gate holding the average context reduction above 50 percent. Deterministic
> guardrails: a rule that must always hold lives in a PowerShell hook script
> that blocks by exit code, never in prose the model can reason its way around
> — that is what stops `git push` and `--no-verify`. And evidence over
> assertion: an agent reports success cheerfully, but only the diff, a detached
> Pester run, and the build say so. Every one of those gates is itself a Pester
> test that fails CI.
>
> The counter-lessons matter as much. An automatic review whose trigger list
> matched nearly every change became an unconditional tax rather than a
> risk-scaled one. Context compaction silently bypasses any end-of-turn gate.
> Two scripted bulk edits corrupted 129 files each, passed their own byte-exact
> verification, and were caught only by git.
>
> Expect specifics: what to enforce mechanically, what to measure, and where a
> multi-agent workflow pays for itself rather than just costing you minutes.

### Learning objectives

1. Define a per-turn contract for agent work — discovery before the first tool
   call, a definition of done before the final answer — and scope it so trivial
   turns are exempt.
2. Structure durable project memory so an agent loads only what a task needs,
   and measure the resulting context reduction as a build gate instead of
   assuming it.
3. Decide which rules belong in an enforceable hook and which belong in prose,
   and write the Pester tests that make either one fail CI.
4. Verify an agent's output against the diff, the tests, and the build rather
   than its own claim, including when a second agent adds value and when it is
   only latency and cost.
5. Recognize the failure modes that appear only at volume: compaction bypassing
   your gates, blast radius from scripted bulk edits, and evaluation results
   that overfit.

### Outline — preparation aid, not submitted

| Minutes | Segment |
|---|---|
| 0–5 | The two-year arc, and what the bottleneck became |
| 5–13 | The per-turn contract, and the exemption that keeps it affordable |
| 13–22 | Durable memory: routing, decision records, the 50 percent gate |
| 22–30 | Hooks versus prose: the never-push guardrail as the worked example |
| 30–37 | Evidence over assertion: Pester gates, and verifying a subagent |
| 37–43 | Three counter-lessons: over-triggered process, compaction, bulk edits |
| 43–45 | What to steal on Monday, and questions |

---

## Speaker biography — round two only

Not used in blind review. Fill in the bracketed parts; keep it to roughly 75
words, written in the third person.

> [Name] is a [role] at [organization] working on PowerShell automation,
> infrastructure as code, and DSC-based configuration management. Over the past
> two years the work moved from hand-written PowerShell and C# to an almost
> entirely AI-assisted process, which produced an open-source library of Copilot
> agents, instructions, skills, prompts, and lifecycle hooks distributed as a
> PowerShell module. [He/She/They] maintains [modules/projects] and speaks about
> automation, build pipelines, and the engineering discipline that AI-assisted
> development still requires.

## Pre-submission checklist

- [ ] Re-count agents, instruction files, skills, and hooks; update the numbers
      in the Proposal 1 abstract.
- [ ] Confirm each abstract is within 150–300 words after any edits.
- [ ] Remove every trace of identity from the abstracts and titles: no
      employer, no project name, no personal URL. First-person experience is
      fine.
- [ ] Decide honorarium versus Sunday-to-Wednesday lodging. Two 45-minute
      sessions or one 90-minute session qualify; the choice is irreversible on
      acceptance.
- [ ] If travel funding depends on an employer, start that conversation now.
- [ ] Secure any permissions needed to present the material and the
      demonstration repository.
- [ ] Submit before 23:59 EDT on 31 August 2026. Late submissions are not
      considered.

## See Also

- [PowerShell Summit 2027](https://powershellsummit.org/)
- [Call for papers on Sessionize](https://sessionize.com/pshsummit27)
- [Speaker information](https://www.powershellsummit.org/speakers/)
