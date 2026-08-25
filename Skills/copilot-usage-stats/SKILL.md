---
name: copilot-usage-stats
description: >-
  Report how many tokens, API calls, and how much wall time a project has
  consumed in Copilot, broken down by model, session, day, or surface, from the
  session store's usage rows. Carries the repository-scoped join, the verified
  fact that `input_tokens` already contains `cache_read_tokens`, the
  unpopulated `cost` column, and why the local store cannot answer at all.
  USE FOR: how many tokens has this project used, token consumption per
  repository or branch, usage for a day or a date range, which model burned the
  most context, cache-hit ratio, API call counts, per-session totals, what this
  repo cost me, comparing VS Code chat against Copilot CLI usage.
  DO NOT USE FOR: advice on lowering spend or token-reduction tips (use
  chronicle cost-tips), standups and session search (use chronicle), measuring
  whether a Customization triggers or works (use agent-evals), Copilot
  subscription or premium-request billing questions.
compatibility: >-
  Requires the `copilot_sessionStoreSql` tool with
  `github.copilot.chat.localIndex.enabled` enabled, plus cloud sync
  (`chat.sessionSync.enabled`). The local SQLite store records no token data,
  so a local-only setup cannot answer any question in this Skill.
---

# Copilot usage stats

Answer "how much has this project consumed" from the Copilot session store.
Reporting only — recommendations for spending less belong to `chronicle`.

## Where the numbers live

| Source | Tokens? | Notes |
|---|---|---|
| `session_usage` (cloud) | Yes | Aggregate per session per model. The default source. |
| `events` (cloud) | Yes | One row per API call: `usage_input_tokens`, `usage_cache_read_tokens`, `usage_output_tokens`, `usage_model`, `usage_cost`, `usage_duration`. Use for per-call sequences. |
| Local `session-store.db` | **No** | Tables are `sessions`, `turns`, `session_files`, `session_refs`, `checkpoints`. No `events`, no usage columns. |
| Hook payloads | **No** | No event carries usage or model. Do not try to build this from a hook. |
| Transcript JSONL | **No** | `assistant.turn_end` is `{"turnId":"0"}`. No usage record. |

Token data only exists cloud-side. If the tool reports `source: local`, say so
and stop rather than substituting turn counts for tokens.

Cloud is DuckDB: use `now() - INTERVAL '7 days'` and `ILIKE`, never
`datetime('now', ...)`.

## Step 1 — Scope the project correctly

`sessions.repository` is **not normalized**. The same repository appears under
several forms, and `cwd` is empty for VS Code chat rows but populated for CLI
rows. Measured on one repository:

| `repository` | `cwd` | `agent_name` |
|---|---|---|
| `https://github.com/owner/repo.git` | *(empty)* | `VS Code Chat` |
| `https://github.com/owner/repo` | *(empty)* | `VS Code Chat` |
| `owner/repo` | `D:\Git\repo` | `Copilot CLI` |

An equality filter on `repository` therefore silently drops most of the
project. Always match the bare repository name against both columns:

```sql
WHERE s.repository ILIKE '%RepoName%' OR s.cwd ILIKE '%RepoName%'
```

Confirm the scope before reporting totals — run the grouping above once and
show the user which rows were folded together.

## Step 2 — The default query

```sql
SELECT u.usage_model,
       count(DISTINCT u.session_id)                    AS sessions,
       sum(u.api_call_count)                           AS api_calls,
       sum(u.input_tokens)                             AS input_total,
       sum(u.input_tokens) - sum(u.cache_read_tokens)  AS input_fresh,
       sum(u.cache_read_tokens)                        AS cache_read,
       sum(u.output_tokens)                            AS output,
       max(u.last_used_at)                             AS last_used
FROM session_usage u
JOIN sessions s ON s.session_id = u.session_id
WHERE s.repository ILIKE '%RepoName%' OR s.cwd ILIKE '%RepoName%'
GROUP BY u.usage_model
ORDER BY input_total DESC
```

## Step 3 — Read the numbers correctly

**`input_tokens` already includes `cache_read_tokens`.** Verified against a
per-call sequence: each call's `cache_read` equals the previous call's `input`
minus a few tokens.

| call | input | cache_read | output |
|---|---|---|---|
| 1 | 89,097 | 0 | 79 |
| 2 | 89,754 | 89,094 | 626 |
| 3 | 90,950 | 89,751 | 407 |

So the two must never be added. Report `input_tokens` as the total context
billed and `input_tokens - cache_read_tokens` as the fresh, uncached share.
Reporting an 88 M "input" figure without that split is the single most
misleading thing this Skill can do — most of it is one conversation re-read.

Other traps:

- **`cost` is usually `0`.** It is not populated for subscription-billed
  requests, so it is not a spend figure. Report it only when non-zero, and name
  it as provider-reported rather than as an invoice.
- **The current session is missing.** Sync lags, so today's session usually has
  no rows yet. State the `max(last_used_at)` you actually saw.
- **`duration` is per model per session in milliseconds**, not wall time for
  the session.
- Small `gpt-4o-mini` and `claude-haiku` rows are background helper calls
  (title generation, summarisation), not work the user drove. Keep them in the
  table but do not let them lead the summary.

## Step 4 — Report

Lead with one sentence answering the question that was asked, then the
per-model table, then caveats. Split by `agent_name` whenever more than one
surface appears — `VS Code Chat` and `Copilot CLI` have different cost shapes
and mixing them hides both.

## Variants

Per day:

```sql
SELECT date_trunc('day', u.last_used_at) AS day,
       sum(u.input_tokens) AS input_total,
       sum(u.output_tokens) AS output
FROM session_usage u JOIN sessions s ON s.session_id = u.session_id
WHERE (s.repository ILIKE '%RepoName%' OR s.cwd ILIKE '%RepoName%')
  AND u.last_used_at >= now() - INTERVAL '30 days'
GROUP BY day ORDER BY day
```

Heaviest sessions, with their summaries:

```sql
SELECT s.summary, s.branch, u.usage_model,
       u.input_tokens, u.cache_read_tokens, u.output_tokens
FROM session_usage u JOIN sessions s ON s.session_id = u.session_id
WHERE s.repository ILIKE '%RepoName%' OR s.cwd ILIKE '%RepoName%'
ORDER BY u.input_tokens DESC LIMIT 10
```

Per-call growth inside one session, to show context accretion:

```sql
SELECT event_index, usage_model, usage_input_tokens, usage_cache_read_tokens,
       usage_output_tokens
FROM events
WHERE session_id = '<id>' AND usage_input_tokens IS NOT NULL
ORDER BY event_index
```

Across all projects, ranked:

```sql
SELECT coalesce(nullif(s.repository, ''), s.cwd) AS project,
       sum(u.input_tokens) AS input_total, sum(u.output_tokens) AS output
FROM session_usage u JOIN sessions s ON s.session_id = u.session_id
GROUP BY project ORDER BY input_total DESC LIMIT 20
```

Note that the last one inherits the normalization problem: one repository can
occupy several rows. Fold them by name before presenting a ranking.

## See also

- [`Prompts/usage.prompt.md`](../../Prompts/usage.prompt.md) — the `/usage`
  slash command and its keybinding
- `chronicle` — standups, session search, and cost-reduction advice
