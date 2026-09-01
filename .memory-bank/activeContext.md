---
status: current
last-verified: 2026-09-01
owner: software-engineer
source: current task evidence
---

# Active context

## Current focus

The `cycle: full` chain ran forever. A raw transcript showed fifteen complete
`software-engineer` ↔ `security-reviewer` round trips in one autopilot session,
30 MB against a ~600 KB norm. Three things lined up: the engineer's *Run
Security Review* handoff auto-submitted, the reviewer's *Fix Issues Found*
handoff auto-submitted back, and the only thing standing between them was
prose — "after two rounds, stop the cycle".

That cap could never fire. A handoff starts the receiving agent with fresh
context, so neither side can count the rounds it has run; a cap nobody can
count is a cap nobody enforces. The bound is now structural: *Fix Issues Found*
sets `send: false`. Forward legs still auto-submit, so a requested cycle still
reaches the reviewer unattended — only re-entering implementation costs a
deliberate click, and the human is the bound. The lesson generalises, so it is
in `systemPatterns.md` and in a test: any ring of `send: true` handoffs is
unbounded by construction, and no agent body can see the ring it is part of, so
`tests/DevelopmentCycle.Tests.ps1` walks the whole graph and fails on one. The
audit found no second ring — `software-architect` → `software-engineer` →
`security-reviewer` is the only other auto-submitting path, and the architect
has no inbound edge.

That corrected the cycle introduced three days earlier, which itself corrected
the switch introduced the same day. Step one removed the engineer's
auto-handover to `security-reviewer`: its "high-risk work" trigger list matched
almost every change here, so a risk-scaled rule behaved as an unconditional
dispatch. `review: on` / `auto` / `off` is now user-set and defaults to `off`.
Step two distinguished *automatic* from *unrequested* — consent at the entry
point covers the whole chain, so a cycle the user asked for may progress on its
own. `cycle: full` runs architect, engineer, security reviewer, technical
writer in order, off by default, and only the final stage closes out; four
stages would otherwise have written four changelog entries and four commits for
one change.

The rules sit in the four agent bodies, not a Skill — the recorded lesson that
an agent body is mode instruction while a Skill is advisory is exactly why
`grill-me` had to become the `software-architect` agent. State passes through
`.memory-bank/decisions/`, because a conversation does not survive a compaction
and a subagent never sees one. Progression is still a handoff, not an unattended
switch — a platform boundary, since VS Code hands the *user* to another agent.
The architect carries a trigger phrase book and a refusal list: "end-to-end"
means end-to-end tests, so it does not start a cycle.

`cycle: off` is the way out: it ends the chain at whichever stage holds the
work, and that stage closes out rather than stranding the changelog entry and
the commit. Both switches are now documented where a user looks — a table in
the root `README.md` and the expanded version in the agents README — and the
table leads with the default, because "how do I keep this with one agent" was
the question the first pass left unanswered.

Both changes are complete and green, but the *deployed* agents are copies under
the Canonical target, not links to this worktree. Nothing takes effect in a
chat session until `Install-CopilotAtelier` or `Setup-CopilotSettings.ps1`
redeploys.

## Previously: the first corporate overlay agent

`software-engineer-contoso` is the first corporate overlay agent. The first
attempt inherited nothing: modelled on `devops-training-writer`, it opened with
a Markdown link to `software-engineer.agent.md` and the words "read it as part
of your operating instructions". VS Code resolves referenced *instructions*
files into the prompt, which is what `chat.includeReferencedInstructions`
governs; an `.agent.md` is not one, so the link is inert and the overlay ran as
a bare fragment with the base contract missing and no diagnostic. The base body
is now inlined between `<!-- BEGIN INHERITED -->` markers and
`tests/AgentInheritance.Tests.ps1` compares it byte-for-byte against the base,
normalising line endings because git rewrites them on checkout.

Inlining is the right design here rather than a workaround: a rule the model
can route around is not a control, which is the standard this agent applies to
everything else. The containment lives in the frontmatter — the base agent's 45
tools drop to 36, removing `web/fetch`, `web/githubRepo`,
`web/githubTextSearch`, `openSimpleBrowser`, `github`, `useMcp`,
`vscode/installExtension`, `vscode/extensions`, and `codeInterpreter`, so the
lethal trifecta cannot close for want of an outbound channel. Prose then shuts
the three ways an agent rebuilds a removed capability: the terminal, the user,
and a handoff.

The non-obvious constraint is the subagent. `agents` narrows to
`security-reviewer` — whose review the overlay simultaneously makes mandatory
rather than risk-scaled — but that agent carries `web/fetch`, `github`, and
`useMcp` of its own, so delegating to it re-opens the channel the toolset just
closed. The rule that ships constrains the dispatch instead: repository paths,
symbol names, and the question, never pasted source, configuration, or data.
The file doubles as the copy-and-rename template for
`software-engineer-<company>`.

## Previously: every hook was dead

The host substitutes `$` tokens in a hook command string
before the child process parses it, so `$b = if ($env:PLUGIN_ROOT) { ... }`
arrived as `= if () { ... }` and PowerShell refused it with `An expression was
expected after '('`. The only symptom was a *Warning from Session Start hook*
balloon, so the never-push block, the Memory Bank probe, and the compaction
checkpoint were all absent while looking installed. Every command in
`com.github.copilot/hooks/hooks.json` is now written without a single `$`, and
resolution probes `PLUGIN_ROOT`, then `~/.copilot/hooks`, then the plugin's
`~/.vscode*/agent-plugins/*/*/CopilotAtelier`. The corrected file was copied
into the canonical target, and both deployed hooks were run end to end.

## Still open from the 1.0 migration

The plugin package moved to Agent Plugins 1.0, and the package is now the
primary layout rather than a second view of the module payload. `plugin.json`
declares the canonical `$schema`, the legacy `agents` and `skills` path fields
are gone, `Skills/` is root `skills/`, and all four Copilot-specific component
types live under `com.github.copilot/{agents,rules,commands,hooks}`. The module
deployment is preserved by translation: the installer maps deployed name to
source path, so `~/.copilot/{agents,instructions,skills,prompts,hooks}` is
unchanged. Decision 0023 records the trade-off it accepts — cross-type relative
links are now correct in the package view and wrong in the deployed view.

Unverified and deliberately so: no documentation states whether
`.instructions.md` and `.prompt.md` register from `com.github.copilot/rules`
and `com.github.copilot/commands`. The bet is one-sided, since the module path
delivers both regardless. Confirming it needs one empirical test — install from
source and check whether the instructions and prompts appear.

## Environment hazard — scripted bulk writes corrupt file content

Two bulk PowerShell read-modify-write passes over this working tree replaced
whole file contents with a monoalphabetic substitution cipher (`instructions`
→ `nnkteuotnonk`, `applyTo` → `aeelyTo`), 129 files each time. Both were caught
and fully restored from git; no corruption reached a commit.

- It is asynchronous. The script's own byte-exact read-back verification passed
  for all 175 files, and `git diff` showed the corruption afterwards, so the
  rewrite lands after the write returns. A verify-after-write loop cannot
  detect it.
- A single-file scripted write was clean, so it correlates with volume.
- Every `replace_string_in_file` edit was clean, across roughly forty files.

Until the cause is found, edit files through the editor tooling, and treat any
scripted bulk rewrite of this tree as unsafe. `git grep -l -e nnkteuotnon -e\naeelyTo` detects it in one pass.

## Blocked, not deferred

The ShellPilot module and `Invoke-ShpBatch` are absent on this machine, so
`-Mode Execute` is unavailable for both eval harnesses. That blocks the two
measurement items outright rather than by choice of priority:

- The 75 prepared route-selection prompts cannot be answered, so no
  pass@k or pass^k result exists yet.
- The seven authored trigger-query sets cannot be swept, so `german-tax-research`
  and the other 37 baselined Skills stay unmeasured for discovery.

Both need ShellPilot plus a paid model backend, and a sweep costs money, so the
run needs an explicit go-ahead rather than an assumption.

## Open findings

- No trigger-query set was authored for `german-tax-research`. Adding one would
  flip its coverage test from skipped to enforced while the sweep that gives it
  meaning cannot run, growing the "authored but never measured" debt the seven
  existing sets already represent. Author it with the sweep, not before.
- The development cycle ships unmeasured for the same reason: the tests prove
  its structure, not that four live stages actually hand over correctly.

## Carried forward from the route-selection eval

- `Invoke-MemoryBankRouteSelectionEval.ps1` has offline `Prepare` and `Grade`
  modes, and `MemoryBankRouteSelection.Tests.ps1` covers prompt isolation, label
  leakage, fallback, strict shape, reliability aggregation, and failure
  accounting.
- The first stage infers routes and fallback only; the deterministic resolver
  still receives human labels for `durableWrite`, role files, and Decision
  records.
- Context-window cost, latency, and answer quality under routed versus full
  loading remain unmeasured. Safety is gameable on its own \u2014 a reply naming
  every route never misses \u2014 and no precision floor is set, so `Passed = True`
  at low precision is not yet a failing build.

## Carried forward from earlier focuses

- `WindowsAccessControl` slots 1 and 2 use the older ink-variant reading of
  dark/light, so two sets in one shared library disagree on "dark mode". That
  repository is not in this workspace.
- The `brand-logo-system` integration step was measured on one project only.
- The `skill-creator` description edit remains unproven: train reached 100 %
  while validation fell, which is the overfitting signal.

## Next step

Redeploy. The deployed `security-reviewer.agent.md` still carries `send: true`
on the fail leg, so the loop is live in every chat session until
`Install-CopilotAtelier` or `Setup-CopilotSettings.ps1` runs. Then get a
decision on the paid sweeps. With a go-ahead: install ShellPilot, answer the 75
route-selection prompts against one pinned model in fresh contexts, grade them,
sweep the seven trigger-query sets, and author `german-tax-research`'s set in
the same pass. Without one, the unblocked work is splitting the nine
over-budget Skill bodies, starting with `german-legal-research` at 780 lines.
