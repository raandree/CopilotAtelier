---
status: accepted
date: 2026-07-24
last-verified: 2026-08-13
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
across the real-task baseline.

Then run `Invoke-MemoryBankRouteSelectionEval.ps1` in `Prepare` and `Grade`
modes with at least three fresh-context repetitions. Require every case to pass
pass^k before claiming natural-language Memory Bank route reliability. This
second gate does not cover durable-write or Decision-record selection, latency,
or routed-versus-full task quality.
