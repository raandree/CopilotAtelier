# Active context

## Current work focus

Adopted the **Non-Impacting Turn (NIT) post-flight exemption**. A turn is now
classified in hindsight at post-flight: **substantive** (a file changed, a
durable decision emerged, the user asked to record, a bug/root-cause was found,
or a git tag was cut) runs the full post-flight; **non-impacting** (pure Q&A,
read-only investigation, self-documenting git commits/merges) skips
verification, CHANGELOG, progress, the local commit, and the promptHistory
append, emitting only `POST-FLIGHT: n/a — non-impacting turn (<reason>)`.
Ambiguity biases to substantive.

## What changed this session

- [postflight.instructions.md](../Instructions/postflight.instructions.md): new
  "Classify the turn first" + "Non-impacting turn" + "Substantive turn"
  structure; the promptHistory append is now owned by post-flight; misclassifying
  substantive-as-non-impacting is a stated violation.
- [preflight.instructions.md](../Instructions/preflight.instructions.md): step 5
  no longer appends promptHistory (moved to post-flight, gated on substantive).
- All 7 agents with an "Every interaction → append to promptHistory.md" write
  trigger softened to "Every substantive interaction …"; the Software Engineer
  and Technical Troubleshooter CORE MANDATE lines softened likewise.
- [AGENTS.md](../AGENTS.md): pre-flight item 5 and the post-flight intro updated
  to match.
- Created `.memory-bank/promptHistory.md` as a substantive-turn log.
- systemPatterns Decision 11 records the policy; CHANGELOG `[Unreleased]` entry added.

## Verification

- markdownlint-cli2 clean across all changed files.
- Pre-flight WORK (probe + read Memory Bank) is unchanged and still mandatory;
  only the pre-flight banner rule (substantive emit / trivial may skip) is retained.

## Next step

Re-run [Setup-CopilotSettings.ps1](../Setup-CopilotSettings.ps1) to propagate the
updated Instructions/Agents to `~/OneDrive/CopilotAtelier` and the `.copilot`
junctions. Local commit made on an `ai/` branch; not pushed. Applying the same
NIT framing to `Reference/definition-of-done.md` was declined this round.
