# PowerShell Summit 2027 session proposals

Submission-ready copy for two sessions at the PowerShell Summit 2027, plus an
optional third. Every field below maps directly onto a Sessionize field. Paste
and submit; the commentary sections are marked as preparation aids and are not
part of the submission.

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

The counts in the abstracts (13 agents, 16 instruction files, 46 skills, 13
prompts, 3 hooks) are current as of 31 August 2026. Re-check them against the
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

> You can steer an AI coding agent five different ways: a custom agent, an
> instruction file, a skill, a prompt file, or a lifecycle hook. They look
> interchangeable. They are not. Each loads at a different moment, carries
> different authority, and fails in its own silent way. Choose wrong and you
> ship a file that looks installed and does nothing.
>
> This session dissects all five: what each frontmatter actually controls, when
> the client loads it, whether the model can decline to follow it, and how to
> prove it is live rather than merely present. You leave with one decision test
> that covers most cases. If a rule must hold regardless of what the model
> decides, it is a hook. If it is a judgment call, it is an instruction. If it
> must bind an entire session, it is an agent.
>
> We spend real time in the failure gallery, because every entry is silent. Hook
> commands whose `$` tokens are consumed by the host shell before PowerShell
> ever parses them. One settings key that replaces the hook location map instead
> of extending it, silently disabling every workspace hook. A Markdown link
> between two agent files that inherits nothing. A skill missing frontmatter
> that never registers.
>
> Everything is demonstrated on a real open-source library — 13 agents, 16
> instruction files, 46 skills, 13 prompts, and 3 hooks — shipped as a
> PowerShell module and as a plugin installed from a Git URL, running in VS Code
> and the Copilot CLI. The library and its failure list are the residue of two
> years spent moving from writing every line of PowerShell and C# by hand to
> having an agent write nearly all of it.

### Learning objectives

1. Choose the correct customization type for a given rule using one test: must
   this hold regardless of what the model decides?
2. Read and write the frontmatter that actually controls behavior — tool
   allow-lists, model priority arrays, `applyTo` globs, subagent eligibility,
   and handoffs.
3. Prove that an agent, instruction, skill, prompt, or hook is genuinely loaded,
   using the chat customizations editor, the agent debug log, and the hooks
   output channel.
4. Diagnose the silent failure modes that let a correct-looking customization do
   nothing at all.
5. Package a customization library so it installs on another machine, and in
   another client, from a module or a Git URL instead of being copied by hand.

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
> writes almost all of it, and the bottleneck is no longer typing — it is trust:
> knowing what changed, why it changed, whether it is right, and what the agent
> quietly forgot. This session is the distilled result of that transition: the
> practices that survived contact with real work, the ones that were abandoned,
> and the failures that only appear at volume.
>
> Four things carried the weight. A per-turn contract — a mandatory discovery
> step before the first tool call, and a close-out gate before the final answer
> — with an explicit exemption so a plain question pays no ceremony tax.
> Durable memory: a version-controlled project knowledge base with a routing
> table, so an agent reads the three files a task needs instead of all of them,
> with a build gate holding the average context reduction above 50 percent.
> Deterministic guardrails: a rule that must always hold lives in a hook that
> blocks by exit code, never in prose the model can route around. And evidence
> over assertion — an agent will report success; only the diff, the tests, and
> the build say so. Every one of those gates is a Pester test that fails CI.
>
> The counter-lessons matter as much. An automatic security review whose trigger
> list matched nearly every change turned a risk-scaled rule into an
> unconditional tax. Context compaction silently bypasses any end-of-turn gate.
> Two scripted bulk edits corrupted 129 files each, passed their own
> verification, and were caught only by git.
>
> Expect specifics: what to enforce mechanically, what to measure, where
> multi-agent workflows pay off, and where they are only cost.

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

## Optional third proposal — 25-minute Fast-Focus

Submit this only if two accepted sessions are wanted; a 25-minute session
qualifies for speaker benefits only alongside a second accepted session. It is
a standalone idea rather than a compression of Proposal 1, which the call for
papers explicitly warns against.

### Title

> Silent by Default: Proving Your AI Customizations Actually Load

### Format and level

- **Format**: 25-minute Fast-Focus.
- **Target audience**: Intermediate.

### Abstract

> An agent customization that fails does not throw. It loads as nothing, and the
> agent carries on sounding confident. Every one of our lifecycle hooks was dead
> for a month behind a single warning balloon: the host shell consumed the `$`
> tokens in each hook command before PowerShell ever parsed them, so the
> never-push guardrail, the memory probe, and the compaction checkpoint were all
> absent while looking installed.
>
> That is one instance of a general problem. A skill without frontmatter never
> registers. One settings key replaces the hook location map instead of
> extending it, disabling every workspace hook with no diagnostic. A Markdown
> link between two agent files inherits nothing.
>
> This is a single-idea talk with a single takeaway: a five-minute verification
> pass you run after every change to an agent, instruction, skill, prompt, or
> hook, using the chat customizations editor, the agent debug log, and the hooks
> output channel. You will leave able to answer, with evidence rather than
> hope, which of your own customizations are actually running.

### Learning objectives

1. Recognize the four silent failure modes that make a customization load as
   nothing.
2. Run a repeatable verification pass that proves each customization type is
   live.
3. Write hook commands that survive host-shell substitution on Windows.

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

- [ ] Re-count agents, instructions, skills, prompts, and hooks; update the
      numbers in the Proposal 1 abstract.
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
