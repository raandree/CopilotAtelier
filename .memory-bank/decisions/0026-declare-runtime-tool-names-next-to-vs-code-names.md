---
status: accepted
date: 2026-09-29
last-verified: 2026-09-29
owner: software-engineer
source: VS Code 1.139.1 agent-host diagnosis, offline runtime probe, github/copilot-cli#4594
---

# Declare runtime tool names next to VS Code names

## Context and problem statement

In VS Code 1.139.1 agent-host (Copilot SDK) chats, the agent host passes a
Custom agent's `tools:` list unchanged to the Copilot runtime (`j4` in
`agentHostMain.js`), and the runtime uses it as a strict allow-list. It resolves
only some VS Code names and silently drops the rest. With an agent selected,
`web_fetch`, `grep`, `glob`, `ask_user`, the browser tools, and the agent-host
session tools were missing; with no agent selected they were available. With
`software-engineer` selected, `#web/fetch heise.de` fell back to
`Invoke-WebRequest` in the shell. Upstream:
[github/copilot-cli#4594](https://github.com/github/copilot-cli/issues/4594),
where the `web` and `search` aliases enable no tool and exact names do.

An offline probe of the runtime bundled with VS Code 1.139.1 (loopback fake
model, no network) showed which entry enables what:

- Nothing: `web/fetch`, `web`, `fetch`, `WebFetch`, `search`,
  `search/codebase`, `search/textSearch`, `vscode/askQuestions`,
  `askQuestions`, `browser`, `todo`, `WebSearch`.
- The tool: `web_fetch`; `grep` and `glob` (also `Grep`, `Glob`); `ask_user`;
  `read` and `read/readFile` as `view`; the `edit/*` tools; `execute` and
  `execute/runInTerminal` as the shell tools; `agent`.
- VS Code client tools and agent-host tools match by exact name or by the part
  after the slash: `search/usages` is `usages`, `browser/openBrowserPage` is
  `openBrowserPage`.

## Decision outcome

- Every agent keeps its VS Code names and declares the runtime name next to
  each: `web/fetch` with `web_fetch`; any of `search`, `search/codebase`,
  `search/fileSearch`, `search/listDirectory`, `search/textSearch` with `grep`
  and `glob`; `vscode/askQuestions` with `ask_user`; `browser` with the ten
  browser tools. VS Code 1.139.1 creates the `browser` tool set with
  `deprecated: true`; for a bare browser tool name its agent-file checker
  (`validateVSCodeTools`) suggests `browser/<tool>` and `vscodeBrowser/<tool>`.
  The profiles use `vscodeBrowser/<tool>`, the tool set that is not deprecated
  and the one the agent host exposes client tools through.
- The twelve agents that are not contained also get the baseline: web, search,
  questions, and the session tools `set_workspace`, `list_sessions`,
  `get_current_session`, `get_session_context`, `add_artifact_or_reference`,
  `list_artifacts_and_references`, and `remove_artifact_or_reference`. No agent
  declares `create_session`, `send_message`, `rename_chat`, or
  `delete_session`.
- The contained agents, `software-engineer-contoso` and the three from decision
  0025, get runtime names only for VS Code names they already declare: `grep`
  and `glob`, plus `ask_user` for the Contoso overlay. They never get
  `web_fetch`, `web_search`, a browser tool, or a session tool.
- `web_search` is not declared. No no-agent agent-host session here offered it:
  the probe's no-agent case lists `web_fetch` but not `web_search`, and none of
  this machine's no-agent agent-host sessions called or mentioned it. The
  runtime gates native web search behind a feature flag
  (`copilot_cli_native_web_search`), so it is account-dependent.
- No wildcard and no replacement for `github`. No `target:` field: VS Code's
  faded *Unknown tool '…' will be ignored* hints are the accepted cost.
- The Copilot CLI contract maps `web/fetch` to `web_fetch` and the `search`
  family to `grep` and `glob` instead of the dead `web` and `search` aliases.
  An exact runtime name counts toward its capability class, a required class
  needs every name it lists, and the browser and session tools are unsupported
  with a reason. `VerificationState` stays `StructurallyChecked`: the probe is
  not an artifact-bound receipt.

## Consequences

- Agent-host sessions with an agent selected regain the tools a no-agent
  session has. Local VS Code chat is unchanged, because every VS Code name
  stays.
- Open agents list 21 more names each. For the web and browser names that is
  parity with local chat, where these agents already had both; the session
  tools are the one new capability.
- Containment in agent-host sessions is per agent, not per host. The agent host
  (`j4` in `agentHostMain.js`) forwards `name`, `description`, `model`,
  `reasoning-effort`, `tools`, `skills`, `infer`, and the prompt, but not
  `agents:`, so an agent holding `agent` (the Contoso overlay, the
  specification controller) can dispatch any Custom or built-in agent. That
  path existed before this change, through the built-in `general-purpose` and
  `research` agents and every delegate's terminal; open delegates now also have
  live `web_fetch` and browser tools. `get_session_context` reads the recent
  transcript of any existing session and `list_sessions` enumerates them, so an
  open agent can read a contained agent's session; the artifact tools act only
  on the current session. The agents README states both limits.
- `tests/AgentRuntimeToolNames.Tests.ps1` enforces the pairing, the baseline,
  and containment, so a new agent must be classified as open or contained. It
  refuses a tools list it cannot parse in full and treats any namespace other
  than `search`, `read`, `edit`, `execute`, and `vscode` as network.
- The `todo` alias also enables nothing. It is kept, because the runtime always
  offers the `sql` tool that holds the todo list.
- **Removal condition.** Drop the paired runtime names once a VS Code release
  ships a runtime in which github/copilot-cli#4594 is fixed, and a probe of
  that release shows `web/fetch`, `search`, the `search/*` tools,
  `vscode/askQuestions`, and `browser` each enabling their runtime tools on
  their own for every agent file. The probe starts the bundled
  `copilot-runtime.exe` through the bundled SDK with `useLoggedInUser: false`,
  a BYOK provider pointing at a loopback fake OpenAI endpoint, and one custom
  agent per profile carrying its `tools:` list, then reads the tool names the
  runtime sends; it registers the browser and session tools as fake SDK tools.
  Keep the session tools until the agent host exposes them without an explicit
  name. Then relax the pairing and baseline tests in the same change and
  supersede this record.

## Confirmation

- The new test was red first: 28 failures (16 pairing, 12 baseline) before the
  agents changed, then green. Mutating the four contained agents (`web_fetch`,
  `set_workspace`, `ask_user`, `vscodeBrowser/readPage`) failed six containment
  cases.
- The contract tests were red against the previous build (ten unit cases, plus
  the `ClientAdapters` setup rejecting the new names) and green after. An
  any-member mutation of the class check let a `glob`-only profile pass as
  `search`, which the unit test rejects.
- Focused suites 484/0/0. The per-agent probe passed all sixteen agents: open
  agents get `web_fetch`, `grep`, `glob`, `ask_user`, 10 of 10 browser tools,
  and 7 of 7 session tools; contained agents get none of the network, browser,
  or session tools. `main`'s `software-engineer` lacked all 21. Browser,
  session, and VS Code client tools were registered as fake SDK tools.
- The full `build, test` gate passed 2,276/0/121 at 90.74% coverage, and
  2,286/0/121 at 90.74% after the review fixes. Its one warning is the
  pre-existing simulated backend failure in the trigger-eval harness test.
- An independent security review returned CHANGES REQUIRED with three Major
  items and no Critical. The test parser could skip a double-quoted entry;
  hardening it went red 7 then green, with the classifier gaps it also named.
  The `agents:` and cross-session limits were verified in `agentHostMain.js`
  and are recorded above; tightening either one conflicts with the requested
  tool baseline, so it is the user's decision.
- The live check is the user's after redeploying: agent-host chat,
  `software-engineer` selected, `#web/fetch heise.de` must call `web_fetch`.
