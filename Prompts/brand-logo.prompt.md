---
agent: software-engineer
description: Start a project's logo and icon design — interview the user on how the mark should look, then build, render, and verify the full brand asset set.
---

# Start the Brand Logo Process

Follow the **brand-logo-system** skill (`Skills/brand-logo-system/SKILL.md`).
Deliver a verified asset set, not a mockup.

## Phase 1 — Ground before asking

Search the target repository for an existing mark before asking anything:
`Assets/`, `docs/`, `.github/`, README image links, `*.svg`, `*.png`.

- Mark found: extract its palette by pixel count, report the hex values, and ask
  only whether to keep, refine, or replace it. Do not ask what the repository
  already answers.
- No mark: continue.

## Phase 2 — Interview

Ask through `vscode_askQuestions` per `Reference/interactive-questions.md`. Two
clusters, not one batch. Skip anything the user already stated.

Cluster 1 — the mark:

| Question | Form |
|---|---|
| What should the symbol show? Name the object or idea. | freeform |
| Visual treatment | options: outline/line art, solid silhouette, monogram, emblem or badge, abstract geometric |
| Character | options: technical and precise, friendly and rounded, serious and institutional, playful |

Cluster 2 — the system:

| Question | Form |
|---|---|
| Colour source | options: reuse the project's existing colours, match a named product, describe a mood, no preference |
| Wordmark split (line 1 / line 2) and tagline | freeform |
| Delivery target | options: repository `docs/brand/`, shared Logos library, both |

## Phase 3 — Propose before building

Describe two or three concepts in one sentence each, render each as a 256 px PNG
proof, and show them. Ask which to develop. Do not build eleven assets from a
guess.

## Phase 4 — Build, render, verify

1. Author `glyph-color.svg` and `glyph-mono.svg` in a `0 0 100 100` viewBox. Add
   `glyph-favicon.svg` when the mark carries fine detail.
2. Write `brand.psd1` with palette, wordmark, tagline, and concept lines.
3. Run `Skills/brand-logo-system/scripts/Export-BrandLogoSet.ps1`.
4. Run the skill's measured gate: count, naming, slot parity, canvas size, corner
   alpha, painted bounds, centring, and ink coverage at 32 and 16 px.
5. Open the board and one composed slot and look at them.

## Rules

- Never invent an identity for a project that already has one.
- Never claim the mark survives favicon size without a 16 px render.
- Report what the render measured, not what the design intended.
- Do not modify a repository the user did not ask you to change. Keep the glyph
  fragments and definition beside the delivered assets instead.
