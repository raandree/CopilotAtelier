# Interactive question UI convention

Shared convention for any skill, agent, or prompt that interviews the user. Keeps interaction friction low and answers structured.

## Rule

When the `vscode_askQuestions` tool (a.k.a. `vscode/askQuestions`) is available in the current session, render multi-choice or multi-select questions through it instead of plain markdown checkboxes. Markdown checkboxes are non-interactive — the user cannot click them and is forced to retype answers in prose.

## Guidelines

- One `vscode_askQuestions` call per tight cluster (1–4 related questions). Do not batch a whole category or workflow phase into one call.
- Use `options` with `multiSelect: true` for "pick all that apply"; `multiSelect: false` (default) for single-choice.
- Omit `options` entirely for genuinely freeform questions ("describe the goal in one sentence").
- Keep `allowFreeformInput` at its default (true) so the user can always override the options with a typed answer. Set to `false` only for strict gates (e.g. `SIGNED OFF` / `revise`).
- Fall back to markdown bullets/checkboxes when the tool is unavailable (CLI, headless eval, tool disabled).
- If the user cancels the question UI, restate the cluster in plain text in the next message rather than re-prompting with the UI.

## Anti-patterns

- Dumping 10+ questions in a single call. Cluster, do not batch.
- Forcing rigid options for an open-ended creative question.
- Using the UI for confirmations the user has already given in chat.
