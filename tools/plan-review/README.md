# plan-review

Optional local review surface for a Design Concept. Renders Markdown and Mermaid,
anchors comments to stable sections, and records a verdict against one document
revision.

**Not part of the CopilotAtelier PowerShell module.** `Install-CopilotAtelier`
never deploys it, the built module does not carry it, and nothing in `source/`
references it. Install its dependencies only if you want the feature.

```powershell
npm install
node src/cli.mjs --document samples/design-concept-sample.md --ttl 900
```

A verdict recorded here is review feedback, not sign-off. See
[`docs/plan-review.md`](../../docs/plan-review.md) for setup, trust boundaries,
storage, shutdown, and rollback, and
[`docs/plan-review-threat-model.md`](../../docs/plan-review-threat-model.md) for
the trust analysis.

## Layout

| Path | What it is |
|---|---|
| `src/` | Server, containment, document identity, store, renderer, CLI |
| `assets/` | The browser shell, stylesheet, and client script |
| `samples/` | A demonstration Design Concept — describes no planned work |
| `test/unit/` | Dependency-free suite; runs in the repository gate |
| `test/integration/` | Renderer and HTTP suite; needs `npm install` |
| `browser/` | Playwright checks against installed Microsoft Edge |
