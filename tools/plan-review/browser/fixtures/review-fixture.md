# Renderer fixture — plan review browser checks

Intro before the first heading, so the preamble section has content.

## Scope

This section carries an anchored comment during the browser run.

Text with `inline code`, **bold**, and a [link](https://example.com/spec).

| Column | Meaning |
|---|---|
| One | First |
| Two | Second |

## Diagram

```mermaid
flowchart TD
  A[Open document] --> B{Revision current?}
  B -- yes --> C[Record feedback]
  B -- no --> D[Invalidate approval]
  C --> E([Stored locally])
  D --> E
```

## Unsafe input

<script>window.__planReviewInjected = true;</script>

<img src=x onerror="window.__planReviewInjected = true">

[javascript link](javascript:window.__planReviewInjected = true)

![remote image](https://example.invalid/tracker.png)

```mermaid
flowchart TD
  X["<img src=y onerror='window.__planReviewInjected = true'>"] --> Y
```

## Removable

This whole section is deleted during the browser run to prove that a comment on
it becomes unanchored rather than moving to different content.
