---
status: current
last-verified: 2026-08-26
owner: software-engineer
source: current task evidence
---

# Active context

## Current focus

All twelve Custom agent files are now named after their `name` slug; the seven
display-name files were renamed with `git mv` and a filename-equals-name guard
enforces it from here. `software-architect` was added as the twelfth Custom
agent and the first phase of the release pipeline, closing the gap where no
agent owned the requirement while it was still text. Decision 0022 records why
that discipline had to become a persona instead of staying a Skill. PR 47
shipped in `345a25e` and the release provenance fix in `f7f302d`. Three change
sets remain in flight: the compaction checkpoint on `ai/precompact-checkpoint`,
the authoring schema refresh on `ai/authoring-instruction-description`, and the
`skill-creator` split stacked on that branch.

## Implemented — Custom agent file naming

- Seven files carried display names with spaces and `&` while declaring a
  kebab-case `name:`, which is the value a handoff, an `agents:` allow-list, and
  a Prompt `agent:` key resolve against. Two addresses for one agent.
- The guard asserts the file stem equals the declared `name` rather than that
  the stem is lowercase: a mismatched pair passes any casing check and is still
  unfindable by anyone who read the other spelling.
- Nothing about agent identity moved, so no handoff, allow-list, or Prompt
  target needed editing.

## Implemented — software-architect Custom agent

- `Agents/software-architect.agent.md`: 31 tools, handoffs to
  `software-engineer` and `security-reviewer`, `disable-model-invocation: true`.
- The gap was structural, not stylistic. `grill-me` is advisory content and the
  Software Engineer body is mode instruction, so the Skill loses inside that
  agent every time. The interview had to become a persona to win.
- The tool restriction is bounded and recorded as such. Every sanctioned
  validation path is gone — `runTests`, `codeInterpreter`, both task runners,
  notebook execution — but `edit/editFiles` and `execute/runInTerminal` stay,
  because Post-flight demands a Memory Bank write, a changelog entry, and a
  commit on every Substantive turn. The agent cannot close the Definition of
  Done on a code change; it is not stopped from typing one.
- Interview depth scales to blast radius, and the chosen depth and its reason
  are stated in the first reply where the user can override them.
- `projectbrief.md` ownership moved to the architect, with the Software
  Engineer and Technical Writer as co-curators. The Software Engineer gained a
  return handoff for a requirement gap local evidence cannot resolve.
- `tests/SoftwareArchitectAgent.Tests.ps1` asserts the withheld tools by name,
  because the SharedLifecycle fingerprint detects change but not correctness.

## Implemented — usage stats

- `Skills/copilot-usage-stats/SKILL.md` and the `/usage` Prompt on `Ctrl+K U`
  answer "how much has this project consumed" from `session_usage`.
- A hook was ruled out on evidence: no hook event carries usage, the transcript
  records `assistant.turn_end` as `{"turnId":"0"}`, and the local
  `session-store.db` has no `events` table and no token column.
- `input_tokens` already contains `cache_read_tokens`; the difference is the
  fresh share. `sessions.repository` is unnormalized, so scope with `ILIKE`
  over both `repository` and `cwd` or most of a project's history is dropped.
- Copilot bills usage, not requests, since 2026-06-01, so tokens convert to AI
  credits at 1 credit = $0.01. The `cost` column is a legacy request multiplier,
  not money. Billing cached input at the input rate inflates by ~10x.

## Implemented — skill-creator split

- Body 492 → 344 lines behind `references/authoring-patterns.md` and
  `references/scripts-and-evaluation.md`, both one level deep.
- The cut line is "only add context the model does not already have": what
  upstream already teaches moved out, what only this repository knows stayed.
- Settled whether an `instruction-creator` Skill is owed. It is not: creation is
  owned by `copilot-authoring` and verification by `agent-evals`.

## Implemented — authoring schema refresh (shipped in `39dd690`)

- `Instructions/copilot-authoring.instructions.md` re-verified against current
  VS Code and agentskills.io documentation: Prompt `agent` is optional,
  Instructions also activate by semantic match on `description`, Agents gained
  `target`, `mcp-servers`, and `handoffs.model`, and the hook stdout contract
  now joins the exit codes. House rules are labelled as such.
- Two portability traps: a Claude-format `matcher` is parsed then ignored, and
  tool input keys are camelCase here where Claude uses snake_case.
- The Instruction declares its own `description`; `applyTo` matches only files
  that already exist, so the "Instruction, Skill, or Hook?" question asked
  before anything is created could never reach it.
- Open and reported, not changed: `plugin.json` is the legacy Copilot format
  and its description claims hooks are outside the plugin format, which Agent
  Plugins 1.0 no longer makes true.

## Implemented — compaction checkpoint

- `Hooks/scripts/Write-CompactionCheckpoint.ps1` runs on `PreCompact` and writes
  `.memory-bank/session/compaction-<UTC>Z.md` with the trigger, transcript path,
  branch, commit, changed paths, and a resume protocol.
- `Instructions/preflight.instructions.md` gained a *Compaction recovery*
  section: distrust the summary, read the newest checkpoint, re-apply routes,
  re-read the driving Customizations from disk, verify the working tree.
- Decision 0021 records the split and what it cannot do; `.gitignore`,
  `.memory-bank/session/README.md`, and `Hooks/README.md` carry the artifact.

## Focused evidence

- `PreCompact` supports the common output format only. There is no
  `additionalContext` field, so no hook can inject text into the
  post-compaction context; the recovery half must be an Instruction, which is
  re-sent with every request. This is the constraint that shaped the design, not
  a simplification.
- `tests/Hooks.Tests.ps1` went red first for the right reason — missing script,
  missing event — then 48 of 48 pass. Coverage includes a payload that smuggles
  a newline and a forged list item into a file an agent reads back.
- The hook writes nothing when the workspace has no Memory Bank or the payload
  names no workspace. Guessing from the spawn directory would drop a checkpoint
  into an unrelated repository, which the unreadable-payload test would have
  done against this repo.
- Writing a literal level-two release header inside changelog prose breaks
  `Get-ChangelogData`; it parsed the example as a real section.
- `Instructions/copilot-authoring.instructions.md` carries unrelated in-progress
  frontmatter-schema work. It is deliberately excluded from the checkpoint
  commit and left in the working tree.

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

## Carried forward from the route-selection eval

- `Invoke-MemoryBankRouteSelectionEval.ps1` has offline `Prepare` and `Grade`
  modes, and `MemoryBankRouteSelection.Tests.ps1` covers prompt isolation, label
  leakage, fallback, strict shape, reliability aggregation, and failure
  accounting.
- The first stage infers routes and fallback only. The deterministic resolver
  still receives human labels for `durableWrite`, role files, and relevant
  Decision records.
- Total context-window cost, latency, and answer quality under routed versus
  full loading remain unmeasured.
- Safety is gameable on its own: a reply naming every route never misses. No
  precision floor is set, because no measured baseline exists to derive one
  from, so `Passed = True` at low precision is not yet a failing build.

## Carried forward from earlier focuses

- `WindowsAccessControl` slots 1 and 2 use the older ink-variant reading of
  dark/light, so two sets in one shared library disagree on "dark mode". That
  repository is not in this workspace.
- The `brand-logo-system` integration step was measured on one project only.
- The `skill-creator` description edit remains unproven: train reached 100 %
  while validation fell, which is the overfitting signal.

## Next step

Get a decision on running the paid sweeps. With a go-ahead: install ShellPilot,
answer the 75 route-selection prompts against one pinned model in fresh
contexts, grade them, then sweep the seven trigger-query sets and author
`german-tax-research`'s set in the same pass. Without one, the remaining
unblocked work is splitting the nine over-budget Skill bodies, starting with
`german-legal-research` at 780 lines.
