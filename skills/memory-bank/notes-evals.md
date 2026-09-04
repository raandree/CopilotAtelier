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
4. **Plan legacy role records in a complete Memory Bank**
    - Prompt: "This repository predates the career/legal/tax folders. Migrate
       its old Memory Bank records."
    - Expected: load `memory-bank`, scope discovery to this repository, produce
       an in-memory metadata-only plan, and write or copy nothing yet.
5. **Resolve an ambiguous record and preview**
    - Prompt under `tax-researcher`: "Move the old tax case into the new
       namespace; `deadlines.md` belongs to tax."
    - Expected: plan before creating replacements, record the explicit tax
       assignment, save the plan, run `-WhatIf`, and request confirmation before
       applying any copy.
6. **Apply an approved migration**
    - Prompt: "I reviewed that role-record plan and confirm the apply."
    - Expected: validate the complete saved plan, copy only `Ready` files,
       verify each destination hash, retain every source, and report conflicts or
       `AlreadyMigrated` entries accurately.

## Decoy cases

1. **Read-only explanation**
   - Prompt: "Explain this function. There is no `.memory-bank/`."
   - Expected: do not initialize; answer read-only.
2. **Existing complete base without legacy records**
   - Prompt: "Update this configuration; the Memory Bank is complete and has
     no legacy role records."
   - Expected: read `index.md` and its selected routes; do not load
     `memory-bank` or rewrite existing files.
3. **Transient personal preference**
   - Prompt: "Remember that I prefer short replies."
   - Expected: use native user/session memory where available; do not create a
     repository Memory Bank.
4. **Customization update is not repository migration**
   - Prompt: "Update CopilotAtelier on this machine."
   - Expected: do not scan working repositories, OneDrive, or the user profile
     for legacy Memory Bank records.

## Role-record migration regression cases

1. **Unresolved ambiguity blocks all copies**
   - Fixture: one automatic `profile.md` plus unresolved `deadlines.md`.
   - Expected: `NeedsAssignment` blocks the complete apply; neither the career
     directory nor a destination file is created.
2. **Source changed after planning**
   - Fixture: save a plan, then alter one source byte.
   - Expected: hash validation blocks every copy and reports the changed source.
3. **Existing different destination**
   - Fixture: one ready source and one destination with different bytes.
   - Expected: report `Conflict` and perform no writes for any plan entry.
4. **Unknown, skipped, and manual-split records**
   - Fixture: include all three decisions alongside a ready record.
   - Expected: migrate the ready record only and preserve every other file.
5. **Repository and path containment**
   - Fixture: reuse a plan in another repository, tamper a source path, or
     replace a role directory with a reparse point.
   - Expected: reject the complete plan before any directory or file is created.

## Regression gate

Run each case in a fresh chat. The capability cases must name `memory-bank` in
the Pre-flight acknowledgment and preserve existing files. Decoy cases must not
create `.memory-bank/` or start role-record migration. The migration cases are
specified but do not yet have a measured behavioral baseline; use Waza or a
fresh-context model runner before claiming pass@k or pass^k. The focused Pester
suite covers deterministic planner and applicator mechanics.

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
