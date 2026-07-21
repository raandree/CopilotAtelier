# Active context

## Current work focus

Established `.memory-bank/glossary.md` as the project's Glossary and
authoritative source for the Ubiquitous Language. Its 20 rows define the core
Customization, distribution, process, and handoff concepts used by Copilot
Atelier.

## What changed this session

- Added the required `Term | Means | Don't say` table with 20 unique Canonical
  term entries.
- Defined the four Customization types, the Canonical target and Discovery link
  model, the Setup script, Pre-flight, Post-flight, turn classification, both
  handoff forms, Acceptance criteria, and the Definition of Done.
- Limited all 40 forbidden phrases to domain-qualified wording so legitimate
  uses of general technical words remain valid.
- Preserved literal filenames, paths, commands, external API fields, and quoted
  historical text exactly as written.
- Marked the Glossary active in `projectbrief.md` and recorded vocabulary
  governance as system-pattern Decision 12.

## Verification

- The structural gate reports 20 unique rows, exactly three populated columns,
  ASCII content, and a final LF.
- The forbidden-phrase audit reports zero matches outside the Glossary across
  151 tracked or unignored text artifacts.
- VS Code reports no diagnostics for the Glossary.
- `git diff --check` reports no whitespace errors.
- `markdownlint-cli2` could not run because this host has no global executable,
  Node runtime, `npm`, or `npx`; VS Code diagnostics are the available Markdown
  rendering check.

## Next step

Use the Glossary on every future change. Propose a new row before naming a domain
concept that the current 20 rows do not cover, and audit each new forbidden
phrase for existing drift before adding it.
