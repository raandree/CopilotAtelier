---
description: "Brief {{nn}}: {{summary: one sentence that stays true after any Update section}}"
agent: {{agent: custom agent name}}
---

# {{nn}} - {{title: short title}}

review: {{review: on or off}}

Brief {{nn}} of {{total: number of briefs}}. Read [00-README.md](00-README.md)
first; its shared rules, report contract, and ledger apply.

## Preconditions

Stop with status `Blocked` when one fails.

- Own row: read ledger row {{nn}}. Continue existing work only while the row is
  not `Done`; when it is `Done`, stop with a report instead of repeating the work.
- Dependency rows: {{depends-on: the row numbers this brief needs, or none}}. Each
  is `Done`, `Done with concerns` that the user accepted, or covered by a ruling
  that lets this brief proceed without it. Before building on a row another run
  wrote, check that every commit it names is on `{{integration-branch: branch}}`
  and that its report file exists:

  ```powershell
  git cat-file -e '<sha>^{commit}'
  git merge-base --is-ancestor <sha> {{integration-branch}}
  Test-Path -LiteralPath 'reports/<NN>-<slug>.report.md'
  ```

  A mismatch stops this brief for a ruling. Never correct the ledger yourself.
- {{repository-state: the repository path, the branch, a clean tree, and the commit this brief starts from}}

## Evidence

Verified on {{date: YYYY-MM-DD}} by {{how-verified: how it was checked}}. Re-check
each item before relying on it; report a mismatch under Evidence corrections in
the report instead of forcing the change.

- {{fact: a fact, with the file, commit, or command that shows it}}

## Ask first

{{ask-first: the one decision to ask the user before starting, with the recommended answer first, or none; for spending and for destructive or security-relevant actions, ask for an explicit yes or no and offer no 'not sure, you pick' option}}

## Tasks

{{tasks: what to do, in order, as concrete requirements with exact files, commands, and messages; mark a fact you cannot supply needs input}}

## Validation

- {{validation: the exact commands and what a pass looks like}}

## Finish

- Commit `{{commit-message: type(scope): summary}}` with the trailers the README
  names.
- Write the report to `reports/{{nn}}-{{slug}}.report.md` from the report
  template.
- Update ledger row {{nn}} only, and add every decision you made to Rulings,
  marked with who decided it.
- Reply in chat with the status, the commits, a one-line test summary, and
  concerns only.
