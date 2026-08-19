# Memory Bank eval cases

## Capability cases

1. **Missing base, durable edit**
   - Prompt: "Add input validation to this repository. It has no memory bank."
   - Expected: load `memory-bank`, create the seven required files plus local
     `promptHistory.md` before the first project edit, then continue.
2. **Incomplete base**
   - Prompt: "Implement the fix; `.memory-bank/` has only `projectbrief.md`."
   - Expected: preserve `projectbrief.md` byte-for-byte and create only the seven
     missing base files.
3. **Role extension**
   - Prompt under `legal-researcher`: "Start a new persistent tenancy case."
   - Expected: initialize the canonical base and only the legal case files
     required by that agent's schema.

## Decoy cases

1. **Read-only explanation**
   - Prompt: "Explain this function. There is no `.memory-bank/`."
   - Expected: do not initialize; answer read-only.
2. **Existing complete base**
   - Prompt: "Update this configuration; the Memory Bank is complete."
   - Expected: read `index.md` and its selected routes; do not load
     `memory-bank` or rewrite existing files.
3. **Transient personal preference**
   - Prompt: "Remember that I prefer short replies."
   - Expected: use native user/session memory where available; do not create a
     repository Memory Bank.

## Regression gate

Run each case in a fresh chat. The capability cases must name `memory-bank` in
the Pre-flight acknowledgment and preserve existing files. Decoy cases must not
create `.memory-bank/`.

## Route-selection evaluation

[`evals/routing-cases.json`](evals/routing-cases.json) contains 25 real,
provenance-labelled tasks. The two routing checks answer different questions:

- `Test-MemoryBankRouting.ps1` consumes the human labels and proves that the
   deterministic resolver selects required files, avoids routine history, and
   preserves the Full-read fallback and context-reduction floor.
- `Invoke-MemoryBankRouteSelectionEval.ps1` presents only the task and Memory
   Bank index to a fresh model. Prepare mode emits isolated prompts; Grade mode
   compares strict JSON replies with the hidden route labels and reports pass@k
   and pass^k.

Grading separates safety from cost. A reply is safe when it misses no labelled
route, so a superset loses no context and is not scored as a miss. Because a
reply naming every route is trivially safe, `PrecisionPercent` and
`ExtraRouteCount` carry the cost signal and have to be read with `Passed`.
No precision floor is set yet — there is no measured baseline to derive one
from, and inventing a threshold is the mistake the exact-set rule made.

The route-selection harness does not yet evaluate which relevant Decision
records the model chooses, total context-window cost, task latency, or answer
quality under routed versus full loading. Those remain separate eval stages.
