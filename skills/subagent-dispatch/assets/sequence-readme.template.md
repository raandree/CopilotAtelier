# {{sequence-name: name of the sequence}} handoff sequence

{{summary: two or three sentences on what the briefs achieve together, where they run, and who runs them}}

## Order

| # | Brief | Scope | Agent | Model tier | Review | Depends on | Needs you for |
| --- | --- | --- | --- | --- | --- | --- | --- |
| {{nn}} | [{{title}}]({{nn}}-{{slug}}.prompt.md) | {{scope: one line}} | `{{agent}}` | {{model-tier: Cheapest, Cheap, Standard, or Most capable}} | {{review: on or off}} | {{depends-on: row numbers, or none}} | {{needs-you-for: decisions that are yours, or none}} |

`Depends on` names the rows a brief needs. A brief starts only when each of them
is `Done`, is `Done with concerns` that you accepted, or has a ruling that lets
it proceed without it. Every earlier row is not a dependency unless it is listed.

## How to run

- Open a brief in the editor and run it in a new chat with the agent named in its
  row: one fresh chat per brief.
- Start a brief only when the rule above holds for its `Depends on` rows.
- The model tier is a recommendation; no brief pins a model.
- `review: on` asks the agent for one independent review of its finished diff.
  Change it to `review: off` to skip that review.

## Branch

{{branch: the integration branch every brief commits to, who creates it, and the branch that holds the current record when the default branch publishes on every push; say that nothing leaves the machine before the publish brief}}

## Source material

{{source-material: the folders, files, and bundles the briefs read, each with the brief that reads it; or none}}
Keep each until the last brief that reads it has run. Name them relative to this
folder: an absolute path stops working when the folder moves to another machine.

## Other machines

{{other-machines: which briefs run on another machine, how the repository state travels (a bundle and its SHA-256), and what comes back; or none}}

## Shared rules

- Read the repository's Memory Bank index and follow its routes before editing.
- Treat a brief's evidence as verified on its date only. Re-check it before
  editing and report a mismatch under Evidence corrections instead of forcing the
  change.
- Do only this brief's scope; never start the next one.
- Outside the publish brief, never push, open or merge a pull request, delete a
  remote branch, deploy, or change a repository setting. In the publish brief,
  get approval for each action and hand the user each command in its own fenced
  code block in the final reply.
- Test-first: a new or changed behavior gets a test that fails for the expected
  reason before the change and passes after it.
- Never weaken a test, baseline, or threshold to get a green result.
- Never put a local account name or user-profile path in a tracked file.
- Ask when a decision is not settled here: one question, the recommended answer
  first, and a `not sure, you pick` option, except for spending and for
  destructive or security-relevant actions.
- When a brief's facts change before it runs, append a dated `Update` section to
  it that takes precedence.
- {{project-rules: rules this repository adds, such as commit trailers and how to run its tests}}

## Report contract

- Write the full report to `reports/NN-<slug>.report.md` from the Skill's report
  template: status (`Done`, `Done with concerns`, `Needs context`, or `Blocked`),
  commits, changed files, validation commands with results, evidence corrections,
  open findings, rulings, and anything that changes a later brief's assumptions.
- Update the brief's own row in [LEDGER.md](LEDGER.md) and add every decision to
  its Rulings table, marked with who decided it.
- Reply in chat with the status, the commits, a one-line test summary, and
  concerns only.

## Decisions waiting for you

- {{decisions: the brief number and the decision that is yours, or none}}
