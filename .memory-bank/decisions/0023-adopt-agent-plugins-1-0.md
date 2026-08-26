---
status: accepted
date: 2026-08-26
last-verified: 2026-08-26
owner: software-engineer
source: Agent Plugins 1.0 specification and VS Code agent plugin documentation
---

# Adopt Agent Plugins 1.0 as the primary layout

## Context and problem statement

`plugin.json` declared no `$schema`, so it loaded in the legacy Copilot format
where the `agents` and `skills` fields override the default component paths.
That was the only reason a capitalised `Skills/` folder was ever discovered.

Agent Plugins 1.0 changes two things that matter here. The manifest schema is
closed and component locations are fixed: skills are read from a lowercase
`./skills` at the package root, `agents` and `skills` are no longer manifest
fields, and an unknown top-level field is *reported and ignored* rather than
rejected. Declaring the schema without moving the folder would therefore have
kept loading the package while contributing zero skills, with no error.

Custom agents, hooks, slash commands, and rules are not portable component
types. Copilot clients read them from the `com.github.copilot` reverse-domain
extension namespace.

The complication is that this repository has two distribution paths that
disagree about layout. The plugin package *is* the repository root, while
`Install-CopilotAtelier` deploys to `~/.copilot/{agents,instructions,skills,`
`prompts,hooks}`. Those five deployed directories are siblings, so a relative
link between two Customization types only resolves if the source directories
are siblings with the same names.

## Decision outcome

Treat the Agent Plugins 1.0 package as the primary layout and let the module
deployment map onto it, rather than the other way round.

- `Skills/` → `skills/`. Required by the format, and the one rename that also
  fixes a latent defect: the deployed folder is `~/.copilot/skills`, so every
  case-only mismatch was already broken on a case-sensitive filesystem.
- Every Copilot-specific component moves into the client-extension namespace
  under the names the format gives them: `Agents/` → `com.github.copilot/agents/`,
  `Instructions/` → `com.github.copilot/rules/`, `Prompts/` →
  `com.github.copilot/commands/`, and `Hooks/` → `com.github.copilot/hooks/`
  with the mandated `hooks.json` filename.
- `Install-CopilotAtelier` carries an explicit deployed-name → source-path map,
  so `~/.copilot/{agents,instructions,skills,prompts,hooks}` is unchanged. The
  deployment contract is preserved by translation, not by layout.
- `keybindings/` stays at the root. It is not a plugin component type at all.

The `rules/` and `commands/` file formats are not documented by VS Code or the
Copilot CLI, so whether `.instructions.md` and `.prompt.md` register from a
plugin install is unverified. The downside is bounded and one-sided: if a
client rejects them, those components simply do not load *from the plugin*,
while the module path continues to deliver them to the same deployed
locations. There is no state in which this is worse than not moving them.

Rejected: renaming the deployed directories to match the namespace. That would
require pinning `chat.instructionsFilesLocations`, and this repository already
learned that a `chat.*FilesLocations` setting *replaces* the default location
map rather than extending it — the same trap that silently disabled every hook
location once already.

## Consequences

- Cross-type relative links are now correct in the package and repository view
  and wrong in the deployed view, because `rules` and `commands` are deployed
  as `instructions` and `prompts`. That direction was chosen deliberately: the
  package is what a human browses on github.com and what a plugin install
  materialises. Nothing functional rests on these links — both lifecycle
  Instructions declare `applyTo: "**"` and load regardless — and links into the
  repository-only `reference/` were already dead in the deployed tree, so this
  is a widening of an accepted condition rather than a new class of defect.
- Hook commands must resolve two roots. A plugin is installed outside the
  workspace so a relative path cannot work, and the same file also ships to
  `~/.copilot/hooks`; each command resolves `$env:PLUGIN_ROOT` when a plugin
  host sets it and falls back to the user profile otherwise.
- Canonical target directories are lowercase. A case-insensitive filesystem
  reuses the directory the installer rebuilds, but a case-sensitive one would
  keep the capitalised copy forever, so the installer sweeps the legacy names
  with a case-sensitive comparison.
- Case-only link text (`Skills/` in prose and markdown links) still points at
  the old spelling in many Customization bodies. It resolves on Windows and
  macOS and 404s on github.com, and is tracked as follow-up rather than fixed
  in this change.

## Confirmation

`./build.ps1 -Tasks build, test` runs 876 passing tests. The two failures are
pre-existing and local-only: `Test-MemoryBankHealth` reports missing `status`
and `last-verified` metadata in the gitignored `.memory-bank/promptHistory.md`,
a file this change never touched and that CI never has.

`tests/PluginManifest.Tests.ps1` replaced the guard that refused to let the
schema be declared while the folder was capitalised with positive assertions:
the canonical `$schema` value, a closed-field check that catches a stale
`agents` or `skills` path field, case-sensitive discovery of root `skills/`,
the namespace location for agents, the `hooks.json` location, and both root
branches in every hook command.
