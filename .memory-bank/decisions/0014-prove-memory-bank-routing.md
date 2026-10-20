---
status: accepted
date: 2026-07-24
last-verified: 2026-10-20
owner: software-engineer
source: .memory-bank/index.md
supersedes: full-base-only-loading
---

# Prove Memory Bank routing before migration

## Context and problem statement

The complete Memory Bank read reached 566 lines and approximately 10.7k tokens,
but context cost alone does not prove that selective loading improves latency or
task quality.

## Decision outcome

Use the Memory Bank index as the sole unconditional read and load relevant
files by task route. Fail open on ambiguity or conflict, retain
`loading-mode: full` as rollback, and require independently audited,
provenance-labeled non-inferiority evals before routed loading becomes
authoritative. Full mode includes every extracted Decision record.

## Consequences

- Routine tasks receive substantially less unrelated context.
- A route can add file reads and therefore must be measured for both quality
  and resolution time.
- Critical process and security rules remain deterministic Instructions, not
  routed project memory.

## Confirmation

Run `tests/MemoryBankRouting.Tests.ps1`; require zero independently labeled
critical-file misses, zero routine prompt-history loads, a complete Full-read
fallback, and at least 50 percent average version-controlled context reduction
across the real-task baseline. Since 2026-10-20 that average leaves out the
cases whose only route is `general`, by the owner's ruling: they load the index
alone, so each one raised the average whatever the other routes selected. The
average over every case is reported beside it.

The same test keeps the case set honest in two ways. Every Memory Bank route in
the index, as the evaluator's own parser reads it, needs at least one real case
or an entry on a coverage baseline that states a reason and may only shrink; a
fixture case never counts as coverage, and a case that expects the Full-read
fallback exercises no route. A case names `roleFiles` exactly when it routes to
`role`, and `RoleFileFailures` stays zero: the `role` row names no file, so a
hollow `role` case would otherwise resolve to the index only and pass. The
Full-read fallback keeps a case's role files, because the active Custom agent
reads them in every loading mode. Since 2026-10-20 two owner-labelled cases
cover `general` and `role`, the last uncovered routes, and the baseline is empty.

Then run `Invoke-MemoryBankRouteSelectionEval.ps1` in `Prepare` and `Grade`
modes with at least three fresh-context repetitions. A reply is safe when it
misses no labelled route, matching the critical-file-miss criterion above, so a
superset is scored as cost rather than failure. Require every case to pass
pass^k on that safety criterion, and read `PrecisionPercent` with it, because a
reply naming every route is safe by construction. This second gate does not
cover durable-write or Decision-record selection, latency, or routed-versus-full
task quality, and it sets no precision floor until a measured baseline exists.
