---
name: subagent-dispatch
description: >-
  Protocol for delegating work to subagents: picking the model per role,
  writing a dispatch prompt that carries the task instead of the session
  history, handing artifacts over as files, keeping a durable ledger that
  survives context compaction, handling the four report statuses, and capping
  the fix loop before it turns into churn.
  USE FOR: dispatch a subagent, delegate to a subagent, subagent prompt, which
  model for a subagent, subagent model selection, subagent context, subagent
  report, task brief, review package, subagent ledger, resume after compaction,
  parallel subagents, fix loop, re-review, the agent said it was done, verify a
  subagent's work, runSubagent, controller context.
  DO NOT USE FOR: the review rubric itself (use code-review-and-quality),
  authoring a Custom agent definition or a Skill (use skill-creator), measuring
  whether a Customization works (use agent-evals), monitoring a long-running
  process (use long-running-job-monitor).
compatibility: >-
  Requires a harness that can dispatch subagents and select their model
  explicitly, such as the VS Code Copilot chat agent surface or the GitHub
  Copilot CLI. Ledger and artifact handover assume a writable working tree.
---

# Subagent Dispatch

A subagent is a fresh context you construct deliberately. It never inherits the
conversation — you decide exactly what it sees, what it returns, and which model
runs it. Get that construction wrong and delegation costs more than doing the
work yourself: the controller context fills with pasted history, the subagent
optimises for the wrong thing, and nobody can tell afterwards what actually
shipped.

## When to use

- Delegating an implementation task, a review, a search, or an investigation.
- Deciding which model a delegated task should run on.
- A delegated task came back and the result needs verifying before it counts.
- A long session risks compaction and the record of completed work must survive.
- A review-and-fix cycle has run several rounds without converging.

## Pick the model explicitly

Always name the model in the dispatch. An omitted model inherits the controller's
model — usually the most capable and most expensive one available — which
silently defeats every economy below.

| Task | Model tier |
|---|---|
| Transcription: the brief already contains the exact code or text to produce | Cheapest |
| Mechanical: one or two files, complete specification, no design judgement | Cheap |
| Integration: several files, pattern matching, coordination between components | Standard |
| Design, architecture, or a broad final review | Most capable |
| Review | Scaled to the diff's size, risk, and subtlety — not to the controller's default |
| A fix round after repeated failure | At least one tier above the model that got stuck |

Turn count beats token price. The cheapest models routinely take two to three
times the turns on multi-step work, and wall-clock plus context cost scale with
turns — so the cheap model is often the expensive choice. Use a mid tier as the
floor for reviewers and for any subagent working from prose rather than from
exact content.

## Write a dispatch that carries the task, not the session

A dispatch prompt describes one task. It is not a status update, a recap, or a
transcript. Pasting "state after the last three tasks" into every later dispatch
is the most common way a delegation loop becomes unaffordable — the pasted text
stays resident in the controller's context and is re-read on every subsequent
turn.

A dispatch contains exactly:

1. One line placing the task in the wider work.
2. The path to the task brief, introduced as the authoritative requirements.
3. Interfaces and decisions from earlier work that the brief cannot know —
   exact names, signatures, and types the subagent must match.
4. Your resolution of any ambiguity you already spotted in the brief.
5. The report path and the report contract.

Exact values — numbers, magic strings, signatures, test cases — belong in the
brief and appear nowhere else, so there is one source of truth. Never make a
subagent read a whole plan or specification to find its own task.

## Hand artifacts over as files

Everything pasted into a dispatch, and everything a subagent prints back, stays
in the controller context for the rest of the session. Write large inputs and
outputs to uniquely named files and pass paths.

- Give a reviewer its diff as a file — commit list, stat summary, and the diff
  with context in one artifact it opens with a single read.
- Have the implementer write its full report to a file and return only status,
  what changed, a one-line test summary, and concerns.
- Name the report after the brief so the pair is obvious months later.

## Never pre-judge a reviewer

Do not tell a reviewer what not to flag. If a dispatch you are writing contains
"do not flag", "don't treat X as a defect", "at most Minor", or "this was
deliberate", stop — you are pre-empting a finding to spare yourself a fix round.
Let the finding be raised and adjudicate it afterwards, on the record.

Equally, do not add open-ended directives ("check everything", "run whatever
tests seem useful") without a concrete reason. They inflate cost and dilute
attention without improving the review.

## Keep a ledger

Conversation memory does not survive compaction. A controller that loses its
place re-dispatches work that is already complete — the most expensive failure
in this whole workflow, and one the controller cannot detect from its own
context.

Maintain a plain file recording, per task: completion with the commit range,
each fix round with what was addressed and what stayed open, deferred minor
findings, and any explicit ruling you made. After compaction, trust the ledger
and the version history over your own recollection.

The ledger is task-execution scope and is disposable once the work merges. It is
not the Memory Bank, which holds durable project knowledge across sessions.

## Handle the report honestly

A subagent's own success claim is not evidence. Verify against the working tree
or version history before the task counts as done — an agent reporting "done"
with no diff has produced nothing.

| Report | Action |
|---|---|
| Done | Verify the diff, then review it |
| Done, with concerns | Read the concerns first. Correctness or scope concerns are resolved before review; observations are noted and the work proceeds |
| Needs context | Supply what was missing and re-dispatch on the same model |
| Blocked | Diagnose before retrying: missing context, insufficient capability, a task too large, or a defect in the plan itself |

Never re-dispatch a blocked task unchanged. If the subagent says it is stuck,
something has to change — the context, the model, the task size, or the plan.

## Cap the fix loop

One fix round is one fix dispatch plus one scoped re-review of the fix only.
Cap it at five rounds per task.

- Rounds one to three go back to the same subagent where the harness allows it;
  its context still holds the task and its own reasoning.
- Rounds four and five go to a fresh subagent on a higher tier, carrying the
  brief, the report, and the open findings. A loop that survives three attempts
  usually means the original cannot see its own mistake.
- The re-review is scoped to the fix diff. New problems found in untouched code
  are recorded, not folded into the loop.

At the cap, stop dispatching and adjudicate each open finding yourself. Park a
contestable or non-load-bearing finding with a written ruling. Stop and escalate
to the user when a finding is real and load-bearing — later work would build on
it, or it exposes a defect in the plan. Every adjudication is a ledger entry; a
silent discard is not an option.

Never fix findings in the controller session. Controller fixes pollute the
context you need for coordination and skip review entirely.

## Anti-rationalization table

| Rationalization | Reality |
|---|---|
| "The model does not matter, the default is fine." | The default is usually the most expensive model available. Naming the tier is one line. |
| "The subagent needs the background to understand." | It needs its task, its interfaces, and its constraints. Session history is cost, not context. |
| "I'll just fix it myself, dispatching is overhead." | A controller fix skips review and burns the context you need to keep coordinating. |
| "It reported success, that is good enough." | A report is a claim. The diff is the evidence. |
| "One more round will converge." | Past the cap, rounds do not converge — the failure is structural. Adjudicate and route. |
| "The finding is obviously wrong, I'll drop it." | Adjudicate at the cap, in writing. Silent discards leave no trail and no defence. |
| "Keeping a ledger is bookkeeping overhead." | The ledger is what survives compaction. Without it a controller re-runs finished work. |

## Red flags

- A dispatch prompt containing prior-task summaries or conversation history.
- A dispatch with no model named.
- A reviewer dispatched without a diff, or told in advance what not to flag.
- A task marked complete on the subagent's word, with no diff inspected.
- A fourth fix round with no escalation in model or approach.
- Several tasks complete and nothing written down outside the conversation.
- The controller editing code that a subagent was dispatched to produce.

When a red flag fires, stop and reconstruct the dispatch rather than pushing the
current one through.

## Verification

A delegated task is done when:

- The model was named explicitly and matched the task tier.
- The subagent's claim was verified against the diff, not accepted on report.
- Every Blocker and Major finding is fixed, or parked with a written ruling.
- The ledger records completion, the commit range, and any parked finding.
- The change clears the shared Post-flight Definition of Done gate.

State the evidence: what the subagent changed, which check proved it, and what
remains parked.
