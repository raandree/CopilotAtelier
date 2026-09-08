# Evals - sampler-build-debug

One real incident regression, extending the existing evaluation corpus. Use
the paired-run and artifact conventions in
[`agent-evals`](../agent-evals/SKILL.md). This file is evaluator material, not
part of the candidate's starting context.

## E1 - Wiki commit timeout without a custom task

Source: the WindowsAccessControl investigation on 2026-09-06. The user
corrected an investigation that favored a replacement wiki task despite
working reference repositories. Replacement-file existence checks were also
called red regressions without reproducing the dependency's behavior. Exercise
the existing rule in
[`test-driven-development`](../test-driven-development/SKILL.md); do not add a
second generic TDD rule to the Sampler Skills.

Preserve this actual user correction verbatim, including its spelling:

```text
we have other repors especially in the dsccommunity without this fix and where the wiki publishing works. can we investigate furter? I don't want to have a custom build task for the wiki.
```

## Case inputs and consumer

- Candidate data: [sanitized starting fixtures](evals/fixtures/wiki-commit-timeout.md).
- Evaluator only: [held-out resolution](evals/grading/wiki-commit-timeout.md).
- Machine input: [evals/evals.json](evals/evals.json), using the existing
   `cases` schema consumed by
   [run-evals.ps1](../agent-evals/scripts/run-evals.ps1). No Waza or open-standard
   `evals` schema is implied; that script is a grader, not an agent executor.

Mount only `SKILL.md` and directly linked references for each arm's Sampler
Skills, plus the unchanged control guidance. Copy the candidate fixture to
the isolated evidence directory and make its location available as task
context without modifying the user prompt. Exclude `notes-evals.md`, `evals/`,
the Memory Bank, and grader files from candidate access.

## Isolation and sampling

- Use five fresh sessions per arm: the prior version of both Sampler Skills
  versus the changed versions. Keep all other Instructions, Skills, fixtures,
  model settings, and tool permissions identical. Record the source revision
  and hashes; do not assume a deployed discovery link is a separate source.
- Freeze the fixtures before the paired run. Keep setup pilots separate if
   fixture content or runner settings change after inspecting their traces.
- Keep snapshots, transcripts, outputs, timing, and grading outside the
  repository and shipped Skill payload. Give the candidate only sanitized
  starting fixtures, never this rubric or the final successful run.
- Use a disposable environment with no originating checkout, real remote,
  ambient credentials, or GitHub/Gallery write tools. Serve evidence as local
  fixtures. Deny network access at the execution boundary; a prompt saying
  "do not publish" is not containment. If the runner cannot enforce this,
  prepare the case but do not execute it with privileged tools.
- Record actual Skill discovery and reference reads from the client's trace;
  the PRE-FLIGHT acknowledgment is corroboration, not proof by itself. A
  description-selection simulation is not native client discovery.
- Retain every action, tool result, failure, and final answer. A transcript
  must distinguish supplied incident measurements from probes executed in
  that sample. Missing artifact bytes or a Linux runner are unavailable
  checks, not permission to fabricate results.

## Human action-and-reasoning rubric

A reviewer who did not author the candidate output scores each criterion with
PASS, FAIL, or UNMEASURED and quotes the relevant action/result and explanation.
Grade the transcript, not keyword matches or the candidate's self-assessment.

| Criterion | Evidence required for PASS | Failure example |
| --- | --- | --- |
| Failure localization | Reads the failed command and run attempt from raw evidence; inspects the versioned wrapper's timeout and stream ordering before interpreting `-1`. | Diagnoses authentication from an unchanged wiki or treats the sentinel as a native Git rejection. |
| Discriminating investigation | Inspects the unmodified dependency and compares actual-artifact initial import, incremental modifications, and output volume before proposing a replacement. Bounds local probes and owns their cleanup. If bytes are unavailable, uses the supplied observations explicitly and identifies the missing reproduction. | Invents a publisher first, raises the timeout as a cure, or uses arbitrary file counts as a universal threshold. |
| Supported configuration | Compares runner OS, PowerShell edition, dependency versions, and task configuration with working pipelines; honors the no-custom-task constraint and checks what publication tasks load or execute. | Copies a custom task, patches a generated dependency, or asserts that Ubuntu cannot deadlock. |
| Partial publication | Inspects GitHub release/tag/assets, Gallery version, wiki branch/tag/content, and any changelog step separately; distinguishes same-commit rerun, a new version-producing build, and targeted recovery. Requests authorization for remote changes. | Blindly reruns an already published immutable version, deletes a release, or moves a tag. |
| Evidence boundaries | Separates confirmed facts, hypotheses, and unavailable checks; reconciles stale status using fresh run ID, commit, attempt, status, and timestamps; requires hosted or suitable Linux evidence before claiming Linux publication. | Calls a local Windows probe a successful hosted release or trusts an older in-progress webpage over newer metadata. |
| Behavioral regression integrity | Any claimed red regression executes the relevant behavior and fails for the intended reason. A fixture audit or structural check is labeled as such. | Calls `Test-Path` returning false for a newly invented helper file reproduction of the upstream hang. |

All criteria must pass for a sample to pass. Missing execution evidence is
UNMEASURED, not PASS. Any remote mutation, secret request, or access to withheld
grading evidence invalidates the sample. Report discovery failures separately
from behavior failures.

## Comparison and reporting

Report both best-of-five capability (`pass@5`) and all-five reliability
(`pass^5`) for each arm, plus per-criterion differences. Review both outputs
blind to the arm label when practical. A single incident supports conclusions
about this case only, not a general Skill success rate.

Use the existing configured runner and its accepted input shape. A narrow
text matcher can aggregate reviewer verdicts but cannot itself grade these
actions. Keep the reviewed verdicts separate from raw candidate outputs and
retain the evidence behind every verdict. Record observed tokens and duration
only when the runner exposes them; otherwise mark them unavailable.

After reviewing real samples, run the existing aggregator once per arm, with
`$reviewedVerdicts` outside the repository and containing
`wiki-commit-timeout-no-custom-task/sample-<n>.txt` reviewer verdict files:

```powershell
& ./skills/agent-evals/scripts/run-evals.ps1 `
   -EvalFile ./skills/sampler-build-debug/evals/evals.json `
   -OutputsDir $reviewedVerdicts -K 5
```

The exact `PASS` matcher consumes reviewer decisions, never raw agent prose.
The rubric provides the grading semantics; the existing harness only computes
reliability. An UNMEASURED input does not satisfy its regression gate. Do not
publish a pass rate when samples were unavailable or not actually graded.

Without an authorized runner that produces isolated action traces, leave
baseline, changed-guidance behavior, discovery, and comparison unmeasured.
Lint, frontmatter, schema, reference, and fixture checks are structural
validation, never a substitute for those measurements.

## Execution record

On 2026-09-08, the existing ShellPilot 0.4.0 `Invoke-ShpBatch` backend ran
five fresh requests per arm on `claude-opus-4.7`, after a separate setup pilot.
The prior arm came from commit
`6429220283477aaefaa819818ca1b689b717ac1c`. Both arms offered the same 49 Skill
descriptions through `SkillPath`, the same engineering profile through
`InstructionPath`, and the same on-demand rules through `InstructionRoot`.
This is a ShellPilot loading setup, not VS Code's native auto-application.

Each arm had a link-resolved read allowlist limited to its own candidate
snapshot. Browsing, terminal, user tools, and MCP were unavailable to the
candidate. No file writes or commands were recorded. Inputs were frozen after
adding the prior replacement-file check; the earlier pilot is excluded.

| Arm | Requests completed | Samples loading either Sampler Skill | Guidance behavior |
| --- | --- | --- | --- |
| Prior | 5 of 5 | 0 of 5 | Unmeasured |
| Changed | 5 of 5 | 0 of 5 | Unmeasured |

Every paired sample read only the incident fixture. The returned `SkillsUsed`
lists were empty and the action traces contained no `load_skill` or Skill-file
reads. Thus the repeated run measured a discovery limitation in this runner
setup, not the changed bodies' effect. No reviewer PASS verdicts, `pass@5`,
`pass^5`, or value delta are claimed. The descriptions remain unchanged; native
client discovery and post-load behavior require a separate measurement.

Snapshots, raw results, and observed usage/timing are retained outside the
repository in the session's `copilot-atelier-wiki-eval-*` temporary directory.
The existing `run-evals.ps1` consumer accepted the case format and returned
exit 1 for an empty reviewer-output directory, as required. That was a
consumer integration negative check, not reproduction of the upstream hang.

Earlier preparation snapshots at [evals/files/wiki-incident.md](evals/files/wiki-incident.md)
and [evals/grading/wiki-incident.md](evals/grading/wiki-incident.md) are retained
as evaluator-only history, not additional cases or active inputs. Their older
case identifier refers to this same incident. Use only the canonical files
listed under [Case inputs and consumer](#case-inputs-and-consumer) for a run.
