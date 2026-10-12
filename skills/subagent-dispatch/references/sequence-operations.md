# Sequence operations

Situations a user-run sequence meets after the first brief. [`SKILL.md`](../SKILL.md)
holds the rules every run follows; this file holds the procedure for each
situation.

## Contents

- [Other machines](#other-machines)
- [Delegated decisions](#delegated-decisions)
- [Remote and irreversible steps](#remote-and-irreversible-steps)
- [Controller runs](#controller-runs)
- [Source material and moved folders](#source-material-and-moved-folders)

## Other machines

When a brief runs on a machine other than the development machine, copy the whole
sequence folder there and carry the repository state as a verified bundle.

- Bundle the integration branch with its complete history and every tag the
  version calculation needs. Record the bundle's SHA-256 in the brief and in the
  ledger.
- On arrival, compare the hash, run `git bundle verify`, and clone from the
  bundle or fetch it into an existing clone before the brief starts.
- Take back one bundle per repository the run changed, and record each hash.
  Copy the ledger and the report back before the next brief starts.
- Before you sync, check by ancestry that local work is contained in what came
  back: `git merge-base --is-ancestor <local-tip> <returned-tip>`. A divergence
  stops for a ruling; never rebase the returned commits.
- The user may push from the other machine while the brief runs. An ancestry
  check then shows a fast-forward, not a conflict. Give the next brief a dated
  `Update` that names the steps already done.

## Delegated decisions

A user's delegation, such as "decide everything overnight" or "I am away", is
itself a ruling, and it states its limits: the kinds of decision it covers and
the kinds it does not.

- Every decision made under it is a ruling decided by `agent under delegation`,
  flagged for the user's review.
- At the review, walk through the flagged rulings one at a time and offer to
  accept them all. Record each answer as a new ruling decided by `user` that
  names the ruling it reviews; the original rows stay.
- A delegated answer never authorizes a remote, destructive, or security-relevant
  action: state the consequence and ask for an explicit answer.

## Remote and irreversible steps

- Collect every step that mutates the remote (a push, a pull request, a merge, a
  release, a tag, a deployment, a repository setting) in a final publish brief,
  with approval per action. A declined approval skips that action only.
- Where a hook or rule forbids agents to mutate the remote, even with approval,
  hand the user each command in its own fenced code block. Put it in the final
  reply of the turn, never inside the text of a question and never before a
  question in the same turn: a command written before a mid-turn question is not
  shown, and the question asks only whether it ran. Then verify the result
  read-only.
- The guard matches command text, not intent. It blocked a `--help` call, and a
  shell command that quoted a blocked command while appending a ledger row. Write
  ledger and report rows with the file-editing tool, and never reshape a command
  to pass the guard.
- Simulate an irreversible step in a throwaway clone first: the merge, a
  throwaway tag, the version the release tooling will choose, and the changelog
  update. State each prediction before the user acts, and compare it afterward.
- When the default branch publishes on every push, records of the work wait on a
  local branch and the default branch's copy of them goes stale. The README and
  the publish brief name the branch that holds the current record, and say what
  happens to it.

## Controller runs

A controller that runs user-run briefs through background subagents applies the
same row rule.

- Each subagent writes its own row and report, as its brief says. The controller
  verifies the row, the diff, and the report before the next dispatch, and
  forwards evidence corrections in it. The commit messages count as part of the
  diff.
- Tool output can mask a string that looks like a secret as `******`. Read the
  bytes before you report a defect in such a line.

## Source material and moved folders

- Source material outlives its sequence. A folder that a later brief reads cannot
  be deleted until that brief has run, so the README names which brief reads each
  one.
- Moving a folder to another machine moves its briefs' absolute paths with it.
  Name folders relative to the sequence folder. When a path a brief names does
  not exist, ask the user where it moved instead of searching for it, read the
  brief's files from the place the user gives, and list the correction under
  Evidence corrections.
- When a task leaves the sequence mid-run, because the user hands it to another
  prompt, record a ruling and re-home every dependency that waited on it. A brief
  that keeps waiting on a task no brief owns never starts.
