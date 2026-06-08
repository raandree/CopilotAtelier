---
name: social-signal-sweep
description: >-
  Recency-bounded sweep of what people publicly say about a topic over the last
  N days (default 30) across GitHub, Hacker News, Reddit, and Stack Overflow,
  plus YouTube and X via browser. Produces a lead sheet (platform, date, signal,
  link, what-to-verify) to seed deeper research. Strictly leads-only: social
  chatter is never citable evidence and must be verified before use. No engine,
  keys, or cookies; uses web fetch, the GitHub tools, and the simple browser.
  USE FOR: last 30 days, last N days, what are people saying about X, recent
  discussion, recency sweep, social signal, community sentiment, Reddit search,
  Hacker News search, GitHub activity last month, Stack Overflow recent
  questions, lead generation for research, find leads.
  DO NOT USE FOR: citable evidence or facts (use research-analyst VERIFY +
  citation-integrity), verifying a claim (use citation-integrity), authenticated
  or private scraping (use authenticated-web-extraction), exporting mail or
  calendar (use the outlook-* skills).
---

# Social Signal Sweep

Survey what people are publicly saying about a topic over a bounded recent window
(default 30 days) across community platforms, and return a **lead sheet** that a
deeper investigation can act on. The output is a list of *places to look*, not a
set of facts. Pair it with the `research-analyst` agent: this skill feeds its
SOURCE phase; the agent's VERIFY phase decides what, if anything, is true.

## Prime directive: leads, not evidence

**Everything this skill returns is tier-8 (social / forums / chatbots) — a lead,
never citable evidence.** A post with 5,000 upvotes is still one anonymous
assertion. Engagement measures attention, not accuracy. Do not state a sweep
result as fact, do not let it raise a claim above `Weak` confidence on its own,
and do not paste a social link as a citation. Every lead carries a "what to
verify" so the next step is always to trace it to a primary source.

This is the opposite contract from a consumer "what's trending" tool. The value
here is *discovery* — surfacing angles, contested points, version numbers, and
named primary sources you would otherwise miss — handed to a discipline that
treats all of it as unproven until verified.

## When to use

- Scoping a new investigation and you need to know what angles, complaints, and
  claims are circulating before committing to a research question.
- Tracking reaction to a recent release, incident, CVE, paper, or announcement.
- Finding *named primary sources* (a maintainer's commit, a vendor advisory, a
  paper) that social posts point at — then leaving the social post behind.

## When not to use

- You need a fact you can cite → go straight to `research-analyst` VERIFY and
  `citation-integrity`.
- You need to verify one specific claim → use `citation-integrity`.
- The data is behind a login → use `authenticated-web-extraction`.

## Inputs

| Input | Default | Notes |
|---|---|---|
| Topic | required | Exact entity/string. Disambiguate collisions (see Edge cases). |
| Window `N` days | 30 | Any integer. `--days=7` weekly, `--days=90` quarterly. |
| Platforms | GitHub, HN, Reddit, Stack Overflow | Add the browser tier on demand. |

## Workflow

1. **Pre-flight the topic.** Run the keyword-trap check (Edge cases) before any
   fetch. A doomed query wastes a sweep; reframing costs one sentence.
2. **Compute the cutoff.** Derive the epoch and ISO date for `N` days ago
   (see Time-bounding).
3. **Sweep each platform** with its recipe below. Prefer `web/fetch` against the
   public JSON endpoints; fall back to `openSimpleBrowser` only when blocked.
4. **Dedup and cluster.** Collapse cross-posts and the same story told on three
   platforms into one lead; a multi-platform cluster is a stronger lead than any
   single post.
5. **Emit the lead sheet** (format below). Every row gets a "what to verify".
6. **Hand off.** Route the sheet into `research-analyst` SOURCE → VERIFY, or hand
   individual citable-looking leads to `citation-integrity`.

## Platform recipes

> Public access patterns drift (Reddit lockdowns, X API changes). Treat each
> endpoint as the current no-auth path and fall back to the browser when a fetch
> returns 403/429. Never fabricate results to fill a gap — a blocked platform is
> a documented gap, not an empty row.

### GitHub — highest reliability (native tools)

The only tier where the *existence* of an artefact (commit, release, advisory) is
itself near-primary; the discussion around it is still a lead.

- Issues/PRs in the window: search with `created:>=YYYY-MM-DD` or
  `updated:>=YYYY-MM-DD` via the GitHub search tools (`githubTextSearch`).
- Releases and release notes: read them with the `githubRepo` tool.
- Repo trajectory: recent activity via `pushed:>=YYYY-MM-DD`; star movement as a
  coarse attention signal.
- Use `github` for issue/PR/discussion bodies and comments.

### Hacker News — Algolia API (free, no auth)

Best date-bounding of any platform. Fetch JSON:

```text
https://hn.algolia.com/api/v1/search_by_date?query=<topic>&tags=story&numericFilters=created_at_i>=<epoch>
```

Swap `tags=comment` for discussion. Each hit gives `points`, `num_comments`,
`created_at_i`, and `objectID` → `https://news.ycombinator.com/item?id=<objectID>`.

### Reddit — public JSON (rate-limited)

```text
https://www.reddit.com/search.json?q=<topic>&sort=new&t=month&limit=50
https://www.reddit.com/r/<subreddit>/search.json?q=<topic>&restrict_sr=1&sort=top&t=month
```

Returns `created_utc`, `score`, `num_comments`, `permalink`. **Reddit frequently
returns 403/429 to non-browser requests.** Set a descriptive User-Agent if the
fetch tool allows; otherwise fall back to `openSimpleBrowser` on the equivalent
`old.reddit.com/search` URL and scan visually. Expand to category-peer subreddits,
not just the brand subreddit, or you miss cross-product discussion.

### Stack Overflow / Stack Exchange — public API (throttled)

```text
https://api.stackexchange.com/2.3/search/advanced?fromdate=<epoch>&order=desc&sort=creation&q=<topic>&site=stackoverflow&filter=withbody
```

Returns `score`, `answer_count`, `creation_date`, `link`. Switch `site=` for other
Stack Exchange networks (`serverfault`, `superuser`, `dba`).

### Browser-only tier — lower confidence (YouTube, X)

No stable no-auth JSON. Use `openSimpleBrowser`, scan manually, mark every lead
"manual confirmation only":

- YouTube, sorted by upload date:
  `https://www.youtube.com/results?search_query=<topic>&sp=CAI%253D`
- X/Twitter: no reliable public no-auth API. Prefer a general web-search fetch for
  reactions; do not depend on third-party mirrors. This is the weakest tier — keep
  it optional.

## Output: the lead sheet

```markdown
# Social Signal Sweep: <topic> — last <N> days (as of <UTC date>)

**Scope:** <platforms swept> · **Cutoff:** <ISO date> · **Tier:** 8 (leads only)

| # | Platform | Date (UTC) | Signal | Gist | Link | What to verify |
|---|---|---|---|---|---|---|
| 1 | HN | 2026-05-30 | 412 pts, 233 cmt | Claims v17 broke replication | <url> | Reproduce against v17 release notes |
| 2 | GitHub | 2026-06-02 | issue, 18 👍 | Maintainer confirms regression | <url> | Read the linked commit/PR diff |
| 3 | Reddit | 2026-06-01 | 1.2k up | "Everyone is switching to X" | <url> | Find named adopters; treat as anecdote |

## Gaps and caveats

- <platform> returned <403/429/zero> — not swept / thin coverage.
- Topic disambiguation applied: <note>.

## Suggested next steps

- Tier-1 leads to verify first: <#, #>.
- Hand to `research-analyst` SOURCE; route citable-looking leads to `citation-integrity`.
```

Keep "Signal" as the platform-native engagement number (upvotes, points,
comments, 👍). Never present it as evidence weight.

## Time-bounding

Compute the cutoff once, reuse for every platform. HN and Stack Exchange want
Unix epoch seconds; GitHub wants an ISO date:

```powershell
$cutoff = [DateTimeOffset]::UtcNow.AddDays(-30)
$cutoff.ToUnixTimeSeconds()        # epoch for HN / Stack Exchange numericFilters / fromdate
$cutoff.ToString('yyyy-MM-dd')     # ISO date for GitHub created:/updated:/pushed: qualifiers
```

For Reddit, prefer the `t=` bucket (`hour`/`day`/`week`/`month`/`year`) and then
filter the returned `created_utc` against `$cutoff` for sub-bucket precision.

## Edge cases

- **Keyword-trap topics** (reframe *before* sweeping):
  - Demographic-shopping phrasing ("gift for a 42-year-old man") — real posts use
    relationship + hobby + budget, not the literal phrase. Ask for those first.
  - Bare numbers that collide ("42", "the 100") — strip the number unless it is
    load-bearing (`GPT-4` keep; `40-year-old` drop).
  - Tutorial phrasing ("how to use Docker") — people post "my Docker setup", not
    the tutorial title. Reframe to discussion vocabulary.
  - Generic single nouns ("sneakers", "coffee") — ask for the specific facet.
- **Ambiguous entity** (same name, different thing) — add a qualifying term and
  note the disambiguation in the sheet's caveats.
- **Blocked platform** (403/429) — fall back to the browser, else record the gap.
  Do not invent rows.
- **Zero results** — report it honestly; widen the window or add synonyms. A thin
  sweep is itself a finding, not a failure.

## Relationship to other building blocks

- **`research-analyst`** — this skill is its tier-8 lead generator in the SOURCE
  phase. Leads stay `Weak`/`Speculation` until VERIFY triangulates them against
  higher-tier sources.
- **`citation-integrity`** — when a lead points at a concrete source (a paper,
  advisory, commit), hand that source to `citation-integrity` before any claim
  built on it is graded `Established`/`Probable`.
- **`authenticated-web-extraction`** — use it instead whenever a platform requires
  login; this skill is public-data-only by design.
