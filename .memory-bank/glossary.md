# Glossary

This file defines the Ubiquitous Language for Copilot Atelier. Use the canonical
term for each concept in source code, tests, comments, documentation, logs,
commit messages, and chat replies. Literal filenames, paths, commands, external
API fields, and quoted historical text retain their exact spelling.

| Term | Means | Don't say |
|---|---|---|
| Glossary | The Memory Bank file that defines the project's Canonical terms and forbidden synonyms. | terminology registry, vocabulary registry |
| Canonical term | The approved name for a domain concept in the Ubiquitous Language. | preferred synonym, official wording |
| Ubiquitous Language | The shared domain vocabulary used consistently by people, code, tests, documentation, and commits. | shared naming convention, terminology policy |
| Customization | A Custom agent, Instruction, Skill, or Prompt distributed by Copilot Atelier. | Copilot plugin, Copilot add-on |
| Custom agent | A role-specific AI definition stored in `Agents/*.agent.md`. | Copilot bot, agent persona |
| Instruction | An auto-applied rule stored in `Instructions/*.instructions.md`. | instruction policy file, instruction ruleset |
| Skill | An on-demand bounded workflow stored in `Skills/<name>/SKILL.md`. | Copilot helper package, skill add-on |
| Prompt | A reusable task template stored in `Prompts/*.prompt.md`. | prompt macro, canned prompt command |
| Memory Bank | The version-controlled project knowledge in `.memory-bank/`. | project-memory store, context database |
| Canonical target | The single selected customization tree populated by the Setup script. | secondary customization target, customization mirror |
| Discovery link | A path under `~/.copilot/` that exposes a Canonical target subdirectory to Copilot clients. | Copilot shortcut, discovery redirect folder |
| Setup script | `Setup-CopilotSettings.ps1`, which configures clients and populates the Canonical target. | Copilot installer, setup bootstrapper |
| Pre-flight | The mandatory discovery phase before the first tool call or substantive answer. | optional precheck, warm-up phase |
| Post-flight | The mandatory classification and closure phase before the final answer. | optional cleanup, wrap-up phase |
| Substantive turn | A turn that changes a file, records a durable decision or event, discovers a defect, or creates a tag. | write-required turn, impacting interaction |
| Non-impacting turn | A turn that has no substantive trigger and therefore uses the documented Post-flight exemption. | trivial interaction, no-op interaction |
| Agent-to-agent handoff | An in-session transfer from one Custom agent to another through an agent handoff control. | same-session agent switch, Custom agent toggle |
| Session handoff | A cross-session continuation document stored under `.memory-bank/session/`. | context dump, continuation note |
| Acceptance criteria | Task-specific behavior or outcomes required for a change to satisfy its request. | task Definition of Done, feature completion list |
| Definition of Done | The project-wide quality bar that every change must satisfy in addition to its Acceptance criteria. | global acceptance criteria, project completion checklist |
