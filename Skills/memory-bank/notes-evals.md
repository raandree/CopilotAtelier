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
