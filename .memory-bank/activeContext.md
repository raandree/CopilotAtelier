---
status: current
last-verified: 2026-11-16
owner: software-engineer
source: current task evidence
---

# Active context

## Current focus

**Brief 19, the publish step (2026-11-14 to 2026-11-16), is done:** the stack is merged as #59 (`10fd024`), #60 (`a71f63f`), #61
(`f3f41ec`), #62 (`deca98d`), #63 (`ce189c5`), #64 (`5edc716`) and #65 (`bd28133`), each green on Ubuntu, macOS and Windows; `main`'s CI published each as
a preview. #62's first run failed one relay row off Windows, a fixture that never mapped the folder holding a file (not a verifier defect); a
test-only fix rode in its squash, and that row now runs on both platform branches everywhere. `~/.copilot` is redeployed from `bd28133`
(`hooks.json` `ed05f232…cb14`, 277 files equal). Records: the handoff folder's `LEDGER.md` and `reports/19-publish-stack.report.md`.

**P5, the containment verifier and the ledger appender, is merged** (#40, `6.1.0-preview0012`;
record #41). `Test-RunContainment.ps1` measures, for the one identity it runs as, what the run can
write, reach, and read; `Invoke-LedgerAppender.ps1` is the pinned, append-only, hash-chained ledger
service. Nine reviews are in `docs/SECURITY-REVIEW.md`; the claims shrank where a reviewer showed
them too large (decision 0025). Not done: hook files outside the pinned one, a keyed chain, a second-account
test, and the verifier on POSIX; brief 14 bound `-Revalidate` to the profile's run id (#63). A contained profile
pins hashes and a `hooks.json` that registers only the guard (regenerate it after every deployment).

P2, per-command remote approval, is merged (#38, squash `1c1327e`,
`6.1.0-preview0011`) and live on this machine: a Grant marker the user types in their own
prompt (`[[allow-remote: git push, gh pr create]]`) lets the guard allow each named
operation once, until the next prompt or 15 minutes. The guard stays a hard block, and
`COPILOT_ATELIER_ALLOW_REMOTE` is gone. Decision 0016 holds the final gate, the live
acceptance of 2026-10-13, and the accepted residuals; the Desktop `LEDGER.md` the queue.

**Decision 0028 is merged and released** (#32 to #36 as `6.1.0-preview0005` to `0009`).
Criteria 1 to 20 and 22 to 30 are met; **criterion 21 is not met**, worded as A39 fixes
it, and TBD-2 is carried forward. M-04 (a `.familiarity` name collision) stays open. #34
to #36 (P7, P3, P8) are live on this machine, which carries `main`'s content (257 files
match, verified 2026-10-14); P8's base, its missing external eval, and its single review
are flagged assumptions. Prompt 06c (`docs/SECURITY-REVIEW.md`) fixed 2 Blockers and 7 Majors in
the eval kit; the Desktop `LEDGER.md` lists what is open. Prompts 03 and 08 pin the
Post-flight elapsed line to its own chat's clock (Decision 0024 lists the cases not
yet seen live); the longer reader line leaves the calibration sentence fewer
characters, so one test in `tests/ContributorProfileHooks.Tests.ps1` squeezes at 1,400.

## Previous focuses

- **Brief 18, the module path of every hook line (2026-11-14).** Merged as #65 (`bd28133`): every PowerShell hook line pins `PSModulePath`
  to its interpreter's `Modules` folder before any command; `HookContract` requires the pin; the eight planted-module controls passed on CI.
- **Brief 15, a CI retry for the Gallery bootstrap (2026-11-14).** Merged as #64 (`5edc716`): the
  `Package Module` job resolves its dependencies in a step of its own, up to three attempts; its first real run succeeded on attempt one.
- **Brief 14, a run id for `-Revalidate` (2026-11-14).** Merged as #63 (`ce189c5`): the profile names its
  run in `runId` (`schemaVersion` 2) and `LedgerRun` requires every validated record to carry it; verifier then `9e150ba8…5c65`.
- **Brief 12, the module folders in `WritableRoots` (2026-11-14).** Merged as #62 (`deca98d`), with brief 19's test-only relay-row fix:
  every place PowerShell loads modules from is measured, inside a declared root or not; verifier then `d7d2b02f…f869`.
- **Brief 17, C2 that fails closed (2026-11-14).** Merged as #61 (`f3f41ec`): C2 fails while any delegation
  tool is offered to the VS Code client, and `RuntimeVerified` needs every case of a bound receipt to pass, read exactly.
- **Brief 16, the Reddit quarantine (2026-11-14).** Merged as #60 (`a71f63f`): `quarantined-reader` is
  user-invocable and hidden from the subagent list, the agent only runs `reddit-read`, and SHA-256 pins hold seven reviewed places.
- **Brief 13, S-19 (2026-11-13).** Merged as #59 (`10fd024`):
  the ledger client counts the sink before it sends and believes only a later sequence; appender digest `f55e163b…0572`.

## Environment hazard — scripted bulk writes corrupt file content

Two bulk PowerShell read-modify-write passes over this working tree replaced
whole file contents with a monoalphabetic substitution cipher (`instructions`
→ `nnkteuotnonk`, `applyTo` → `aeelyTo`), 129 files each time. Both were caught
and restored from git; no corruption reached a commit. It is asynchronous: the
script's own byte-exact read-back passed and `git diff` showed it afterwards, so
a verify-after-write loop cannot detect it. Edit through the editor tooling and
treat any scripted bulk rewrite as unsafe; `git grep -l -e nnkteuotnon -e
aeelyTo` detects it.

## Blocked, not deferred

On 2026-09-08 ShellPilot and `Invoke-ShpBatch` are installed, and
`Test-ShpCiReadiness -NonInteractive` reports ready with the existing Copilot
backend. The wiki case used it with candidate-scoped read-only tools and no
browsing, terminal, user tools, or MCP. Its ten paired requests plus one setup
pilot made no Skill loads, writes, or shell calls. Waza and its native extension
are absent; the earlier Copilot CLI check also reported it unavailable.
No graded body comparison exists. The bundled matcher aggregates independent
reviewer verdicts, not investigative actions or candidate-authored PASS text.
Earlier route-selection and trigger-query sets remain unmeasured. ShellPilot's
`-SkillPath` reads a folded `>-` description as `>-`: give it one-line copies.

## Open findings

- **Residual (2026-11-14, brief 18, #65):** `HookContract` reads a pinned line only up to the pin and for a later
  `PSModulePath`, so six hand edits after it pass (R18-09; keep the `-Command` text as shipped); VS Code's outer 5.1 finds `powershell` through
  a module when `PATH` lacks it; the host's environment, a writable `$PSHOME`, bare `powershell` and `pwsh` stay open; CI green on all three systems.
- **Residual (2026-11-14, brief 14, #63):** by design, a sink-and-head writer still forges a run's ledger (the chain is not
  keyed), a reused run id is not told apart, and only the operator's own `-Revalidate` binds against a controller passing another run's evidence.
- **Residual (2026-11-14, brief 12, #62):** a Pass of `WritableRoots` describes the state at the check
  (brief 18 closed R12-02 and R12-08 for the hook lines); the rename of `Documents` through the profile folder, the registry and `USERPROFILE`
  re-point, `WRITE_DAC` and `WRITE_OWNER` on a place, and modules inside a place are not judged; POSIX green on CI since the relay-row fix.
- **Residual (2026-11-14, brief 16, #60):** RR03-01 to RR03-04 are fixed; by instruction only, a caller without an explicit
  `agents:` list (VS Code's built-in Agent), or an agent-host agent holding `agent` while `infer: false` is unverified, can still run `quarantined-reader`
  by name, and its file tool reaches `auth-state/`. Owner's follow-ups (handoff `backlog.md`): a hook that denies that call, a session-start note without
  the Memory Bank line for the reader, and option 2 (encrypt `auth-state/`).
- **Residual (2026-11-14, brief 17, #61):** a receipt edited together with its `Observation` still passes every test that
  runs without the runtimes (consistency, not provenance: only a run at its version refutes it); the allow-lists bound `software-engineer` only.
- **Minor (2026-11-13, review R11-01):** at least 26 exception texts of the containment verifier (20 into its evidence), the event
  names of hooks.json and the grants root still pass unrelayed; briefs 11 and 12 closed the hook check's and `WritableRoots`' texts.
- **Low (2026-11-12, review R04-14):** six private SHA-256 hex helpers in `source/` and the copied SDK lookup in two runtime suites
  could share one helper each; deferred by the owner.
- **Medium (2026-11-12):** VS Code Local chats are not probed for the hook input of Skill and file tools: their tool names, payload,
  and `matcher` handling are unverified (Copilot Chat 0.74.0 shows no matcher handling near its hook code).
- **High:** `software-engineer-contoso` claims no egress while retaining an
  unrestricted terminal and mandating a generic `security-reviewer` delegate
  with web, GitHub, MCP, and terminal tools. In agent-host sessions the host
  drops `agents:`, so its delegation can reach any agent, and open agents can
  read its session through `get_session_context` (decision 0026). Eleven older
  agents likewise combine workspace and private-data access, untrusted web
  content, arbitrary execution, and broad MCP access. Prose is not enforced
  containment, especially on native Windows without terminal sandboxing;
  replace copied omnibus tool lists with role-specific least-privilege surfaces.
- **Major:** `career-coach` (35,672 chars), `research-analyst` (43,376),
  `security-reviewer` (43,772), and `technical-writer` (35,018) exceed GitHub's
  30,000-character Custom agent prompt limit. The new test prevents growth; the
  separate Session handoff owns the refactor below the limit.
- **Major:** every profile omits `target` but declares a VS Code model-priority
  array and mostly VS Code-qualified tool IDs. Copilot CLI documents one model
  string plus CLI tool names; product-specific profiles or a shared compatible
  subset remain open.
- **Medium:** Security Reviewer and Technical Writer delegate research to the
  full `research-analyst` profile, and twelve agents expose `browser` while only
  Software Engineer carries an explicit ephemeral-loopback,
  shared-authentication, and user-confirmation contract.
- **Medium:** no executed agent behavioral eval set exists; the semantic tests
  catch structural regressions only. Under Windows PowerShell 5.1,
  `Get-FileHash` is unresolvable inside a script invoked from a Pester `It`,
  which the untouched `MemoryBankRoleMigration` suite reproduces — a harness
  anomaly, not a code defect.
- **Low:** three test files parse agent frontmatter with independent regular
  expressions; one shared `powershell-yaml` parser plus malformed nested
  fixtures would reduce false greens. The deployment review's M1-M5 and L1-L6
  are approved on the verified scope; macOS and live cloud sync stay disclosed.

## Carried forward

`Invoke-MemoryBankRouteSelectionEval.ps1` has offline `Prepare` and `Grade`
modes covering prompt isolation, label leakage, fallback, strict shape,
reliability aggregation, and failure accounting. The first stage infers routes
and fallback only; the resolver still receives human labels. Context cost,
latency, and answer quality under routed versus full loading remain unmeasured,
and no precision floor is set. `WindowsAccessControl` slots 1 and 2 use the
older ink-variant reading of dark/light; `brand-logo-system` integration was
measured on one project only; and the `skill-creator` description edit remains
unproven — train reached 100 % while validation fell.

## Next step

1. P2 is merged and already live here. Optional: one short live re-check of the shipped
   guard (`E94968A0…`) in a new chat; the acceptance of 2026-10-13 ran on the earlier
   `B6DFAD99…` (a push without a marker is denied; with `[[allow-remote: git push]]` one
   push runs). P5 removed the last mentions of `COPILOT_ATELIER_ALLOW_REMOTE` from the
   controller agent (the security lint names the rule `ObsoleteRemoteOverride`).
2. The owner checks in a new chat that a prepared `git push` ends with a code block and no
   dialog (P3); agents cannot push, and refreshing `~/.copilot` is the owner's.
3. The owner's queue is `C:\Users\install\Desktop\CopilotAtelier-handoffs` (start with `00-README.md`). Brief 19 published the stack
   (#59 to #65). Left to the owner: re-pin any containment profile on another machine (verifier `32558cf0…2842`, appender `f55e163b…0572`,
   `hooks.json` `ed05f232…cb14`, asset `e553312e…1eec`; `schemaVersion` 2, a new `runId` each run), the live checks in a new chat, Prox1's
   machine `PSModulePath` and `PATH`, and deleting the merged `ai/*` branches and `ai/stack-preview` on GitHub. From briefs 03 and 16: delete
   any leftover `extracted\all-cookies.json`, copy the changed Reddit files into `CareerAuthBrowser`, delete `auth-extract.prompt.md` or keep
   `reddit-read` out of it, and check `reddit-read` and the reader's own chat live. Then close #49 and route R11-01 and the other P5
   follow-ups (`docs/SECURITY-REVIEW.md`). `ai/travel-photo-diary-skill` exists only on the other machine.
4. A further eval run needs a new amendment, TBD-11 closed with source and date,
   the owner's term file, and a freeze digest recorded outside the kit
   (`docs/SECURITY-REVIEW.md`, *Before the next freeze*; A34, A38); none is authorized.
5. Recommended to the owner, not required: update PowerShell 7 on RAANDREE3 from
   7.6.1, and delete the empty scratch folder on Prox1 (its profile entry,
   registration, and files were removed on 2026-10-08). Never set the
   summarization threshold below about 1.3 times the base prompt (*Compactions*).
   Optional: report upstream that the GitHub hooks reference describes the exit-2
   stdout merge without its `hookSpecificOutput` condition.

Still open from earlier work (Open work in `progress.md`): the live agent-host
`#web/fetch` check and the duplicate Instruction loading in Copilot SDK chats.
