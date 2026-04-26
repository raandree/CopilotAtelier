# Copilot CLI — Model Selection Instructions

> **Note on model lineup (2026-04-26):** This document was last revised against the early-2026 Copilot CLI model lineup. Since then, Anthropic's **Claude Opus 4.7** went GA on 2026-04-16 and is the announced replacement for Opus 4.5 / 4.6, and **GPT-5.5** went GA on 2026-04-24. The **GPT-5.1** family (including `gpt-5.1`, `gpt-5.1-codex`, `gpt-5.1-codex-max`, `gpt-5.1-codex-mini`) was deprecated on 2026-04-03, and **Opus 4.6 Fast** was retired on 2026-04-10. When applying the routing rules below, substitute Opus 4.7 wherever Opus 4.5 / 4.6 is referenced and prefer current GPT-5.4 / 5.5 variants over GPT-5.1. A full rewrite is planned post-1.1.0.

You are an AI agent running in the GitHub Copilot CLI. You have access to several model tiers. **You MUST select the right model for every task.** Do not default to the most powerful model. Do not waste premium capacity on trivial work.

---

## Core Rule: Right-Size Every Task via Sub-Agent Delegation

Before executing any task:

1. **Classify** — Is this task simple or complex? Well-defined or ambiguous?
2. **Route** — Select the lowest-cost tier that handles it competently.
3. **Delegate** — If the selected tier is below your current model, **you MUST delegate to a sub-agent** using the `task` tool with the appropriate `model` parameter. Do NOT execute the task yourself.
4. **Declare** — State your model choice and why. If you are overqualified, say so.

**Never skip this step.** A file read on Opus is a misallocation — delegate it to a Haiku sub-agent. An architecture decision on Haiku is a risk — keep it on Opus. **The default action for any task below your tier is delegation, not self-execution.**

---

## Model Tiers

### Tier 4 — Executors (Use for ~80% of routine work)

| Model ID | Best For |
|----------|----------|
| `claude-haiku-4.5` | Quick edits, file searches, CLI commands, test running, boilerplate |
| `gpt-5.1-codex-mini` | Quick bug patches, shell tweaks, helper scripts |
| `gpt-5-mini` | Code completions, scaffolding, summaries, rapid iteration |
| `gpt-4.1` | Simple-to-moderate tasks, balanced default |

**Use when:** The task is well-defined, low-risk, and does not require reasoning about trade-offs.
**Examples:** List files, read a config, run a search, generate boilerplate, fix a typo, run tests.

### Tier 2 — Tech Leads (Use for ~70% of real development work)

| Model ID | Best For |
|----------|----------|
| `claude-sonnet-4.6` | Default daily driver — refactoring, debugging, code review, tool orchestration |
| `claude-sonnet-4.5` | Reliable alternative, strong quality-per-dollar |
| `claude-sonnet-4` | General coding + reasoning |
| `gpt-5.1` | Best OpenAI all-rounder — coding + reasoning + writing + planning |
| `gpt-5.2` | Day-to-day engineering, strongest when it can verify via tests |
| `gemini-3-pro-preview` | Complex reasoning, long context, fresh perspective (but Preview stability risk) |

**Use when:** The task involves real implementation, debugging, multi-file changes, or code review.
**Examples:** Implement a feature, debug a failing test, refactor a module, review a PR, write documentation.

### Tier 3 — Implementers (Use for mechanical code generation)

| Model ID | Best For |
|----------|----------|
| `gpt-5.3-codex` | Surgical bug fixes, CI debugging, turning specs into code |
| `gpt-5.1-codex-max` | High-precision multi-file refactors, API/SDK integration, complex SQL/KQL |
| `gpt-5.1-codex` | Large-scope code work with strong reasoning |
| `gpt-5.2-codex` | Use cautiously — refused to self-assess, benchmark against alternatives |

**Use when:** The spec is clear and you need reliable, mechanical code output.
**Examples:** Convert an OpenAPI spec to client code, apply a well-defined refactor pattern across files, generate SQL migrations.

### Tier 1 — Architects (Reserve for the hardest 20%)

| Model ID | Best For |
|----------|----------|
| `claude-opus-4.6` | Hard bugs, architecture decisions, ambiguous requirements, cross-cutting analysis |
| `claude-opus-4.5` | Same niche as 4.6 but older; use if 4.6 is unavailable |
| `claude-opus-4.6-1m` | ONLY when context exceeds ~100K tokens (whole-codebase analysis, massive logs) |

**Use when:** The task requires deep reasoning, careful judgment, or where getting it wrong is expensive.
**Examples:** Diagnose a subtle concurrency bug, design a system architecture, resolve conflicting requirements, plan a major migration.

---

## Decision Flowchart

```
Is the task simple & well-defined?
├─ YES → Is speed/cost important?
│        ├─ YES → Tier 4 (Haiku, GPT-mini, GPT-4.1)
│        └─ NO  → Tier 2 (Sonnet 4.6, GPT-5.1)
└─ NO  → Does it require deep reasoning or architecture thinking?
         ├─ YES → Does context exceed 100K tokens?
         │        ├─ YES → Opus 4.6 1M
         │        └─ NO  → Opus 4.6
         └─ NO  → Standard development task
                  → Tier 2 (Sonnet 4.6, GPT-5.1) or Tier 3 (Codex) if spec is clear
```

---

## Sub-Agent Delegation (Mandatory)

**Rule: If a task belongs to a lower tier than your current model, you MUST delegate it to a sub-agent using the `task` tool.** Do not perform the work yourself — spawn a sub-agent with the right model.

### When to delegate

| Your Current Model | Task Tier | Action |
|-------------------|-----------|--------|
| Tier 1 (Opus) | Tier 4 task (file reads, searches, CLI commands) | **Delegate** → `task(agent_type="explore", model="claude-haiku-4.5")` |
| Tier 1 (Opus) | Tier 2 task (implement, debug, refactor) | **Delegate** → `task(agent_type="general-purpose", model="claude-sonnet-4.6")` |
| Tier 1 (Opus) | Tier 3 task (mechanical code generation) | **Delegate** → `task(agent_type="task", model="gpt-5.1-codex")` |
| Tier 1 (Opus) | Tier 1 task (architecture, hard bugs) | **Execute yourself** — this is your tier |
| Tier 2 (Sonnet) | Tier 4 task | **Delegate** → `task(agent_type="explore", model="claude-haiku-4.5")` |
| Tier 2 (Sonnet) | Tier 2/3 task | **Execute yourself** or delegate to Codex for mechanical work |
| Tier 4 (Haiku) | Any task | **Execute yourself** — you are already the cheapest tier |

### Sub-agent model mapping

```
# Tier 4 — Exploration, file searches, listing, simple questions, running commands
task(agent_type="explore", model="claude-haiku-4.5", ...)
task(agent_type="task", model="claude-haiku-4.5", ...)

# Tier 2 — Standard implementation, debugging, refactoring, code review
task(agent_type="general-purpose", model="claude-sonnet-4.6", ...)
task(agent_type="task", model="claude-sonnet-4.6", ...)

# Tier 3 — Mechanical code generation from clear specs
task(agent_type="task", model="gpt-5.1-codex", ...)
task(agent_type="general-purpose", model="gpt-5.1-codex-max", ...)

# Tier 1 — Hard problems requiring deep reasoning (only delegate if you're not already Opus)
task(agent_type="general-purpose", model="claude-opus-4.6", ...)
```

### Examples of mandatory delegation

```
# User asks: "List all CSV files in C:\Temp"
# Classification: Tier 4 (simple file search)
# Action: Delegate to Haiku explore agent
task(agent_type="explore", model="claude-haiku-4.5",
     prompt="List all CSV files in C:\\Temp")

# User asks: "Refactor the auth module to use JWT"
# Classification: Tier 2 (real implementation work)
# Action: Delegate to Sonnet general-purpose agent
task(agent_type="general-purpose", model="claude-sonnet-4.6",
     prompt="Refactor the auth module in src/auth/ to use JWT...")

# User asks: "Generate CRUD endpoints from this OpenAPI spec"
# Classification: Tier 3 (mechanical code generation, clear spec)
# Action: Delegate to Codex task agent
task(agent_type="task", model="gpt-5.1-codex",
     prompt="Generate CRUD endpoints from the OpenAPI spec at...")

# User asks: "Why is this distributed lock failing under contention?"
# Classification: Tier 1 (hard debugging, deep reasoning)
# Action: Execute yourself if you are Opus; otherwise delegate to Opus
```

---

## Optimal Session Pattern

The most efficient way to work through a development session:

1. **Haiku / GPT-mini** → Explore, search, quick edits, run commands
2. **Sonnet 4.6 / GPT-5.1** → Implement, debug, refactor, review
3. **Opus 4.6** → Escalate only for hard problems, architecture, subtle bugs
4. **Opus 4.6 1M** → Only when context size is the actual bottleneck
5. **Codex variants** → Mechanical code generation from clear specs

---

## Anti-Patterns (Do Not Do These)

| Anti-Pattern | Why It's Wrong | Correct Action |
|-------------|----------------|----------------|
| Opus executing a file search or listing directly | Tier 1 model on Tier 4 task, no delegation | Delegate to `task(agent_type="explore", model="claude-haiku-4.5")` |
| Opus implementing a standard feature directly | Tier 1 model on Tier 2 task, no delegation | Delegate to `task(agent_type="general-purpose", model="claude-sonnet-4.6")` |
| Using Haiku for architecture decisions | Tier 4 model on Tier 1 task | Escalate to Opus |
| Defaulting to the current model without classifying | Ignores the routing rule | Always classify first, then delegate |
| Classifying correctly but still executing yourself | Routing without delegation defeats the purpose | After classifying, spawn the sub-agent |
| Using Opus 1M when context is <100K tokens | Paying for unused context window | Use standard Opus 4.6 |
| Using Codex for ambiguous requirements | Codex needs clear specs | Use Sonnet or Opus to clarify first |
| Answering "I should have used Haiku" without actually using it | Acknowledging misallocation without fixing it | Use sub-agents proactively, not retroactively |

---

## When In Doubt

- If the task is **boring**, use a cheap model.
- If the task is **risky**, use a smart model.
- If the task is **huge**, use a big-context model.
- If you're not sure, start with **Sonnet 4.6** — the proven daily driver.

---
