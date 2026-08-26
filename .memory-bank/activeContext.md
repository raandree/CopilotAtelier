---
status: current
last-verified: 2026-08-26
owner: software-engineer
source: current task evidence
---

# Active context

## Current focus

The plugin package moved to Agent Plugins 1.0. `plugin.json` declares the
canonical `$schema`, the legacy `agents` and `skills` path fields are gone,
`Skills/` is now root `skills/`, and agents and hooks moved to
`com.github.copilot/{agents,hooks}` with the mandated `hooks.json` filename.
`Instructions/` and `Prompts/` were only lowercased — the `rules` and
`commands` namespace formats are undocumented, and moving them would break
every cross-type relative link in the deployed tree. Decision 0023 records the
split and the one bounded cost it accepts.

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

## Implemented — Instruction frontmatter and authoring conformance

- `Instructions/copilot-authoring.instructions.md` was re-verified against
  current VS Code and agentskills.io documentation in `39dd690`: Prompt `agent`
  is optional, Instructions also activate by semantic match on `description`,
  Agents gained `target`, `mcp-servers`, and `handoffs.model`, and the hook
  stdout contract now joins the exit codes. Two portability traps: a
  Claude-format `matcher` is parsed then ignored, and tool input keys are
  camelCase here where Claude uses snake_case.
- That semantic-match fact is what made the missing `description` a defect
  rather than a cosmetic gap. Twelve of sixteen files had none, so their only
  route in was a path match. All twelve now declare one, `description` moved to
  *required here* in the schema, and `CustomizationFrontmatter.Tests.ps1`
  enforces it — red on 12 of 16 cases at the previous commit.
- Held the same twelve against the rules: removed five `## Summary Checklist`
  and three `## Best Practices Summary` sections that restated the body, four
  introductory explanations the Strict tier forbids, two trailing link farms,
  and 78 decorative marks. 355 lines.
- Kept `csharp`'s `## Additional Resources` against the option chosen, because
  it holds that file's only authoritative external links and the rules ask for
  linking in place of explaining. Bare URLs converted to proper links.
- `applyTo` narrowing was limited to patterns fully subsumed by a sibling, so
  no file's match set changed. `powershell-execution-safety` still claims
  `**/*.yml`; narrowing that changes coverage and belongs in its own change.
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
