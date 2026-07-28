---
status: accepted
date: 2026-07-28
last-verified: 2026-07-28
owner: software-engineer
source: VS Code 1.130 MCP and agent plugin docs
---

# Keep MCP server curation out of the deployed library

## Context and problem statement

Every Custom agent declares the `useMcp` tool, and the library ships
`mcp-builder` for authoring servers and `agent-security-review` for auditing
tool wiring, but no MCP server is configured anywhere. Adding a curated
`mcp.json` to the deployed Customization set was considered so that agents
arrive with working external tools.

An MCP server is executable code with credentials and network reach. Server
selection depends on the machine, the tenant, and the task, and a shared
default would push identical tool access to every workstation that syncs the
library.

## Decision outcome

Do not deploy MCP server definitions. MCP stays a per-machine, per-tenant
concern configured by the user in workspace or user settings.

The library keeps its MCP responsibilities on the two sides it can carry
safely and portably: `mcp-builder` for building servers, and
`agent-security-review` for reviewing wiring against the lethal trifecta and
the OWASP Top 10 for LLM Applications.

## Consequences

- The Setup script never grants tool access the user did not choose.
- No credential or endpoint is distributed through OneDrive.
- Agents that need external tools require a manual, reviewed MCP setup step.
- If a future server is genuinely machine-independent and credential-free, this
  decision must be revisited with an agent-security review rather than
  quietly extended.

## Confirmation

`Setup-CopilotSettings.ps1` deploys only `Agents`, `Instructions`, `Skills`,
`Prompts`, and `Hooks`, and writes no MCP setting. `projectbrief.md` records
MCP server curation under scope boundaries.
