---
name: mcp-builder
description: >-
  Design, scaffold, and ship Model Context Protocol (MCP) servers that
  expose an API or local capability as well-named tools an LLM can call.
  Four-phase workflow (research → implement → review → evaluate), TypeScript
  vs Python SDK choice, stdio vs streamable-HTTP transport, tool naming and
  description discipline, Zod / Pydantic schemas, pagination, actionable
  error messages, MCP Inspector testing, and a 10-question realistic-task
  eval rubric. Windows / VS Code Copilot stdio gotchas included.
  USE FOR: build MCP server, write MCP server, Model Context Protocol,
  MCP tool design, MCP transport, MCP Inspector, FastMCP, MCP TypeScript
  SDK, MCP stdio, MCP streamable HTTP, register tool with MCP, MCP tool
  schema, MCP pagination, MCP error messages, MCP eval, wrap an API as
  MCP, mcp.tool, server.registerTool, Zod schema, Pydantic schema.
  DO NOT USE FOR: configuring MCP servers in `.vscode/settings.json`,
  writing REST/GraphQL APIs, writing MCP clients.
---

# MCP Server Builder

Produce a Model Context Protocol (MCP) server that an LLM in VS Code Copilot, Claude Desktop, or the `gh copilot` CLI can drive end-to-end. Quality is measured by whether the agent can complete realistic tasks, not by raw endpoint coverage.

## When to Use

- Wrapping an internal REST API, CLI, or database so an LLM can use it.
- Exposing a local capability (file system area, Git repo, scheduled job) to an agent in a controlled way.
- Auditing or refactoring an existing MCP server that the agent misuses (wrong tool, wrong arguments, missed pagination).

## Phase 1 — Research and plan

1. **Read the MCP spec.** Start at `https://modelcontextprotocol.io/sitemap.xml`, then fetch the markdown of the specific page (append `.md` to the URL). Focus on: transports (stdio / streamable HTTP), tool / resource / prompt definitions, error semantics.
2. **Load SDK docs.** For TypeScript: `https://raw.githubusercontent.com/modelcontextprotocol/typescript-sdk/main/README.md`. For Python (FastMCP): `https://raw.githubusercontent.com/modelcontextprotocol/python-sdk/main/README.md`. Read the README before writing code; do not infer from cURL shapes.
3. **Pick a language.**
   - TypeScript by default — best SDK ergonomics, broad runtime support, easy single-file distribution.
   - Python when the target service already has a mature Python SDK or you need pandas / numpy.
4. **Pick a transport.**
   - **stdio** for local servers launched per-session by the host (VS Code Copilot, Claude Desktop, `gh copilot`). One process per chat. Zero auth surface.
   - **streamable HTTP** for remote / multi-tenant servers. Use stateless JSON (simpler to scale) unless you genuinely need server-sent events.
5. **List the operations.** Walk the target API's docs and write down every operation worth exposing. Prefer comprehensive coverage over a few "smart" workflow tools — agents recombine primitives well.

## Phase 2 — Implement

### Tool-naming discipline

- Verb-first, prefixed by the service: `github_create_issue`, `azure_list_resource_groups`, `outlook_send_mail`. Consistency lets the agent guess adjacent tools.
- One tool = one operation. Do not multiplex ("create_or_update") unless the underlying API does.
- Tool names should pair: `list_*` returns ids + summaries; `get_*` returns the full record by id. Agents follow that pattern automatically.

### Descriptions are documentation for the LLM

Every tool needs: a one-line purpose, the input contract, the output contract, and edge-case behaviour ("returns empty array if none found", "throws if name already exists"). The agent reads this as the *only* spec.

### Schemas

- **TypeScript:** Zod schemas registered via `server.registerTool`. Add `.describe()` on every field; the description ships to the LLM.
- **Python:** Pydantic models with `Field(..., description=...)`. Use `@mcp.tool` and let FastMCP derive the schema.
- Always declare an **output schema** (`outputSchema` in TS, return-type annotation in Python). Structured output lets the agent chain tools without re-parsing prose.
- Include realistic examples in field descriptions: `description="ISO date, e.g. 2026-05-19"`. Examples beat prose for schema-following.

### Pagination and result shape

- Every `list_*` tool MUST accept `limit` and `cursor` (or `page` + `page_size`). Do not return unbounded arrays; agents will dump the entire dataset into context.
- Default `limit` to 25-50. Include `next_cursor` in the response when more results exist.
- For large fields (full document bodies, blobs), return a reference (id, URL) and offer a separate `get_*_content` tool. Agents fetch on demand.

### Error messages

Every error returned to the agent must say *what to do next*. "401 Unauthorized" is useless. "401 Unauthorized: token expired — call `refresh_token` and retry" lets the agent recover without human help. Include actionable suggestions in every thrown error.

### Annotations (TypeScript)

Set the tool annotation hints when applicable:

- `readOnlyHint: true` for `get_*` / `list_*` / `search_*`.
- `destructiveHint: true` for `delete_*` / `drop_*` / anything irreversible.
- `idempotentHint: true` for upserts that produce the same outcome on repeated calls.
- `openWorldHint: true` when the tool reaches external mutable state.

Hosts (VS Code, Claude Desktop) use these to gate confirmations.

## Phase 3 — Review and test

1. **Static checks.** TypeScript: `npm run build` must succeed under `--strict`. Python: `python -m py_compile server.py` and `ruff check`.
2. **MCP Inspector.** Launch with `npx @modelcontextprotocol/inspector node ./build/server.js` (TS) or `npx @modelcontextprotocol/inspector python -m server` (Py). Click through every tool with realistic inputs. The inspector exposes the exact JSON the agent will see — if it looks wrong here, it will be wrong in production.
3. **stdio sanity check on Windows.** Launch the server from the same working directory the host will use. Path-related bugs (relative `require`, `__dirname` vs. cwd) only surface here.

## Phase 4 — Evaluate with realistic tasks

Write 10 evaluation questions before declaring done. Each must be:

- **Read-only.** No state mutation.
- **Independent.** Question N does not depend on question N-1.
- **Realistic.** Something a real user would ask, with concrete details (names, dates, ids).
- **Multi-step.** Solvable only by chaining two or more tool calls.
- **Verifiable.** One canonical answer that can be string-compared.
- **Stable.** The answer won't change next week.

Store questions and expected answers in `evals/eval.xml` (or `evals.json`):

```xml
<evaluation>
  <qa_pair>
    <question>Find the most recent issue in the "copilot-extensions" GitHub org labeled "good first issue" that's still open. What's its title?</question>
    <answer>...</answer>
  </qa_pair>
</evaluation>
```

Run the eval by handing the question + the MCP server to a clean agent session. Failures reveal exactly which tools are mis-described, mis-named, or missing.

## Tool security

An MCP server is an attack surface: its tools run with whatever credentials you hand them, and their return values flow straight into an LLM's context. Design for the case where the model driving them has already been prompt-injected. For a full agentic-system review, load the [`agent-security-review`](../agent-security-review/SKILL.md) skill.

- **Don't build the lethal trifecta into one server.** The trifecta is (1) access to private data + (2) exposure to untrusted content + (3) an outbound network channel. A single server that reads private data, ingests untrusted content (fetched pages, issues, emails), *and* can make arbitrary outbound calls lets an injected instruction exfiltrate — no server bug required. Split these across servers, or remove one leg (e.g. no arbitrary `http_get`; pin egress to the API you wrap).
- **Least privilege, scoped credentials.** Give each server the narrowest, shortest-lived token that covers its tools. No god-mode PATs, no org-wide OAuth scopes, no ambient cloud credentials. A `list_issues` server does not need `repo:write`.
- **Every tool return value is untrusted.** Tool output is an injection vector: a fetched page, a file, or an issue body can carry `# SYSTEM: …` instructions aimed at the agent. Validate and segregate return values; never present them as trusted instructions. Prefer structured output the host renders as data over prose the model treats as directives.
- **Egress allow-listing.** Default-deny outbound from the server process; permit only the hosts the wrapped API needs. This is the cheapest way to break trifecta leg 3.
- **An audited connector ≠ audited data.** Vetting the server's code says nothing about the trustworthiness of the data it returns. That data still crosses a trust boundary and must be treated as hostile.
- **Confused-deputy risk.** The server holds privileged credentials and acts on the model's behalf; if the model is steered by untrusted input, the server becomes a confused deputy executing the attacker's intent with your privileges. Add per-tool authorization, set `destructiveHint` and human-in-the-loop gates on irreversible tools, and scope tokens so a hijacked call can do only limited damage.

## Project layout (TypeScript)

```
my-mcp-server/
├── src/
│   ├── server.ts          # registerTool calls only; no business logic
│   ├── tools/             # one file per tool, exports name + schema + handler
│   ├── api/               # HTTP client, auth, retry, pagination
│   └── schemas.ts         # shared Zod schemas
├── evals/
│   └── eval.xml
├── package.json
└── tsconfig.json          # "strict": true, "target": "ES2022"
```

## Project layout (Python / FastMCP)

```
my_mcp_server/
├── server.py              # @mcp.tool registrations only
├── tools/                 # one module per domain
├── api/                   # httpx client, pagination helpers
├── evals/
│   └── eval.xml
├── pyproject.toml
└── README.md
```

## Windows / VS Code Copilot gotchas

- **VS Code launches stdio servers with cwd = workspace folder.** Resolve all paths relative to the script (`path.join(import.meta.dirname, ...)` in TS, `Path(__file__).parent` in Python), not cwd.
- **Long-running background work blocks stdio.** Never `await` more than a few seconds inside a tool handler. Stream progress via separate `progress` notifications if available, or break the operation into smaller tools.
- **Stderr is the log channel.** stdout is the JSON-RPC channel; any `console.log` / `print` to stdout corrupts the protocol. Use `console.error` / `print(file=sys.stderr)` or a structured logger writing to a file.
- **The `azure-mcp` skill family is the local reference.** Existing patterns in this workspace (`mcp_azure_*` tools) follow Microsoft's MCP guidelines closely — mirror their tool naming for any Azure-adjacent server.

## Common pitfalls

- **One mega-tool that takes a free-form prompt.** Defeats the point. The agent already has a model.
- **Returning prose instead of structured data.** Forces the agent to re-parse. Use `outputSchema` / typed returns.
- **Silent pagination.** Returning 10,000 rows blows the context window. Always page.
- **"Helpful" extra fields in every response.** Bloats every call. Return what was asked for.
- **No examples in descriptions.** Schemas without examples produce malformed calls.
- **Forgetting the `destructiveHint`.** The host can't gate the confirmation prompt without it.
- **Inferring an SDK from another language.** Always read the README for *your* language.
