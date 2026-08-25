# Authoring patterns

Structural patterns, freedom calibration, and iteration technique for SKILL.md bodies. This material is largely the Agent Skills open standard and Anthropic's [skill authoring best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices) adapted to this repository. Read it when choosing a structure for a new skill, calibrating how prescriptive an instruction should be, or planning an iteration loop.

## Contents

- Degrees of freedom, and when to explain the why
- Favor procedures over declarations
- Pattern catalogue (patterns 2 to 8)
- Claude-A / Claude-B iteration
- Testing across model tiers
- Anti-patterns

## Degrees of freedom

Match the level of specificity in your instructions to the task's fragility. Most skills mix all three; calibrate each part independently.

| Freedom | When to use | Pattern |
|---|---|---|
| **High** | Multiple approaches valid; decisions depend on context | Prose checklist: "Analyse the code structure, check for edge cases, suggest improvements." |
| **Medium** | A preferred pattern exists; some variation acceptable | Pseudocode or script with parameters: `generate_report(data, format="markdown")`. |
| **Low** | Operations are fragile; consistency critical; specific sequence required | Exact command: `python scripts/migrate.py --verify --backup`. "Do not modify the command." |

The analogy: a narrow bridge with cliffs on both sides needs guardrails (low freedom); an open field needs only a general direction (high freedom). Database migrations are bridges; code reviews are fields.

### Explain the why on flexible instructions

Where the instruction is high or medium freedom, reasoning beats directive: "Do X because Y tends to cause Z" outperforms "ALWAYS do X, NEVER do Y". An agent that understands the purpose makes better context-dependent decisions. This is not in tension with the prohibitions in *Behavioural enforcement* in [`SKILL.md`](../SKILL.md) — those exist for discipline failures on fragile, low-freedom steps, where there is nothing to reason about and the only job is closing a shortcut. Classify the failure first against *Match the form to the failure*, then pick the register.

### Favor procedures over declarations

Teach the agent *how to approach* a class of problems, not *what to produce* for one instance. "Read the schema from `references/schema.yaml`, join on the `_id` convention, apply the user's filters as WHERE clauses" generalises; "join `orders` to `customers` on `customer_id` and sum `amount`" does not. Specific details still belong in a skill — output templates, constraints like "never output PII", tool-specific commands — but the *approach* must generalise.

## Pattern catalogue

Reach for these before inventing structure. Not every skill needs all of them. Pattern 1, the Gotchas section, stays in [`SKILL.md`](../SKILL.md) because it is the highest-value content in most skills and the agent must read it before hitting the situation.

### Pattern 2 — High-level guide + references

SKILL.md gives quick-start. Each domain or advanced topic lives in `references/<topic>.md`. Use when the skill covers one tool with multiple sub-areas (e.g. `pdf-processing` with `forms.md`, `tables.md`, `merging.md`).

### Pattern 3 — Domain-organised references

SKILL.md is a navigation map; references are split by domain (`finance.md`, `sales.md`, `product.md`). Use when the skill spans multiple independent data sets or topics where any one task only needs one.

### Pattern 4 — Conditional workflow

SKILL.md describes a decision tree; each branch points to a reference or script. Use when the workflow forks early on input type ("creating new doc → follow A; editing existing → follow B").

### Pattern 5 — Workflow checklist

For complex multi-step tasks, provide a copyable checklist the agent tracks across the conversation. Most valuable when steps have dependencies or validation gates.

```markdown
Task Progress:
- [ ] Step 1: Analyse the form (run `scripts/analyze_form.py`)
- [ ] Step 2: Create field mapping (edit `fields.json`)
- [ ] Step 3: Validate mapping (run `scripts/validate_fields.py`)
- [ ] Step 4: Fill the form
- [ ] Step 5: Verify output
```

### Pattern 6 — Feedback loop

`run → validate → fix → repeat`. Document the validator (script or rubric), the loop, and the exit condition. This pattern dramatically improves output quality on quality-critical tasks (form filling, XML edits, document generation). A reference document can serve as the validator: instruct the agent to check its work against it before finalising.

### Pattern 7 — Output template

When output must take a specific shape, provide a template rather than describing the format in prose — agents pattern-match against concrete structures far more reliably. Short templates live inline; long or conditionally-needed ones go in `assets/` and load on demand.

### Pattern 8 — Examples (input → output pairs)

When output quality depends on style, include two or three input/output pairs in SKILL.md. Examples beat descriptions when the user wants a specific shape.

## Claude-A / Claude-B iteration

Use two instances when refining a skill:

- **A** — helps you author and refine. Sees the SKILL.md, asks "is this too verbose?", suggests reorganisations, splits references.
- **B** — uses the skill on real tasks in a fresh chat, with no authoring context. Reveals where the agent actually struggles, ignores files, or misses connections.

Observe B's behaviour and bring concrete observations back to A: "When B asked for a regional sales report, it forgot to filter test accounts even though the skill mentions this rule. Make the rule more prominent." This loop catches problems no static review finds, because the failure mode is "what an LLM actually does with this skill", not "what a human thinks the skill says".

### Test across model tiers

Run the skill on the weakest and strongest models it will realistically meet — Haiku, Sonnet, and Opus. Instructions that a stronger model infers from context, a weaker one needs stated. A skill that only works on the top tier is under-specified, not elegant; a skill that a weak model follows correctly will not confuse a strong one. Where the tiers diverge, the divergence names the implicit assumption to write down.

For comparing two versions, try **blind comparison**: present both outputs to a judge without revealing which came from which version, and let it score organisation, formatting, and polish on its own rubric. Two outputs can pass identical assertions and still differ sharply in quality.

## Anti-patterns

- **Description written as self-description.** "This skill converts files." Frame it as an instruction: "Use this skill when...".
- **Description tuned to verbatim failed queries.** Overfitting. Name the category those queries represent instead.
- **Body holds the trigger.** Invisible to the selector. Move triggers into the description.
- **Skill generated from the model's general knowledge.** Produces generic procedure. Ground it in project artifacts.
- **Time-sensitive info in main content.** "After August 2025, use the new API." Will be wrong. Put legacy guidance in a `<details><summary>Old patterns</summary>` block.
- **Inconsistent terminology.** Pick one term ("API endpoint" or "URL", not both) and use it throughout.
- **Offering too many options.** "You can use pypdf, pdfplumber, PyMuPDF, or pdf2image." Pick a default; mention alternatives only as escape hatches with a clear "use X instead when Y".
- **Deeply nested references.** SKILL.md → `advanced.md` → `details.md` → `more.md`. Flatten.
- **Reference pointer with no load condition.** "See `references/` for details." State when to read it.
- **SKILL.md tries to be a tutorial.** It is reference material for an LLM that already knows the domain. Cut introductions ("PDFs are a common file format...").
- **Folder name mismatches `name:`.** The CLI silently ignores the skill.
