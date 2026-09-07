# Plan review — architecture and threat model

Scope: the optional local review surface under `tools/plan-review/`. This is a
task-scoped design note, not a signed-off Decision record. It does not grant
approval authority to anything and does not change the existing Design Concept
sign-off contract in
[`software-architect.agent.md`](../com.github.copilot/agents/software-architect.agent.md).

## What it is

A single-user, loopback-only HTTP surface that renders one or more explicitly
opened Markdown documents, lets a human attach comments to stable sections, and
records a verdict against a specific content hash. It is opt-in: nothing in the
PowerShell module imports it, the installer never deploys it, and the package is
excluded from `CustomizationDirectory` in [`build.yaml`](../build.yaml).

## Components

| Component | Responsibility | Trust |
|---|---|---|
| `src/cli.mjs` | Parse launch arguments, authorize artifacts, print URL and stop procedure | Trusted (operator-supplied) |
| `src/paths.mjs` | Realpath containment plus ancestor reparse-point rejection | Trusted enforcement point |
| `src/document.mjs` | Read authorized bytes, hash the revision, split stable sections | Reads untrusted bytes |
| `src/render.mjs` | `markdown-it` with raw HTML disabled, then DOMPurify allow-list | Sanitizes untrusted bytes |
| `src/store.mjs` | Bounded, atomic, locked feedback persistence under a declared root | Writes untrusted text |
| `src/security.mjs` | Host, Origin, `Sec-Fetch-Site`, CSRF, body-size and content-type gates | Trusted enforcement point |
| `src/server.mjs` | Fixed route table, no path parameter that names a file | Trusted enforcement point |
| `assets/app.mjs` | Render sanitized HTML, run Mermaid in strict mode, drive the UI | Runs in the browser |

## Trust boundaries

### 1. Document access

Untrusted input: the bytes of any Markdown file the operator opens.

- The only readable documents are the ones named by `--document` at launch. The
  wire protocol refers to them by an opaque `documentId` (a hash), so no request
  parameter ever carries a path fragment.
- Every authorized path is realpath-resolved, required to sit inside the
  declared `--root`, and rejected when any ancestor from the root down to the
  file is a symbolic link, junction, or other reparse point.
- There is no directory listing, no glob, no URL fetcher, and no shell endpoint.

Failure path: a path outside the root, a reparse point in the chain, a missing
file, or a file over the size bound aborts the launch. At request time the same
checks run again before the read, so a link swapped in after launch fails.

### 2. Browser input

Untrusted input: comment bodies, verdict notes, and every request header.

- Bodies are `application/json` only, capped at 64 KiB, parsed with a byte
  counter that aborts the stream rather than buffering an unbounded request.
- Comment bodies are capped at 4000 characters, notes at 2000, and a document
  holds at most 200 comments. Excess is rejected, not truncated.
- Comment text is stored and returned as text and inserted with `textContent`.
  It is never re-rendered as Markdown and never sanitized-then-trusted.

### 3. Rendering

- `markdown-it` runs with `html: false`, so raw HTML in a document is escaped
  rather than parsed. That is the primary control, not a filter.
- DOMPurify then runs over the generated HTML as defence in depth with a tag and
  attribute allow-list and a URI regexp that permits only `http`, `https`, and
  `mailto`. `javascript:`, `data:`, and `vbscript:` URIs are dropped.
- Mermaid runs client-side with `securityLevel: 'strict'` and `htmlLabels: false`,
  and the produced SVG is passed through DOMPurify again before insertion.
- The response carries `Content-Security-Policy: default-src 'none'` with
  `script-src 'self'` and `connect-src 'self'`. There is no `unsafe-eval` and no
  remote origin. `style-src` allows `'unsafe-inline'` because Mermaid injects a
  `<style>` element into its SVG; this is a documented residual risk, and with
  `script-src 'self'` it does not yield script execution.
- All vendor scripts are served from an explicit filename allow-list mapped onto
  `node_modules`. There is no static directory handler and no CDN.

### 4. Approval authority

This is the load-bearing boundary.

- An HTTP verdict proves that *something* with the session cookie and the CSRF
  token posted a hash. It does not prove human identity and does not prove
  authority to start implementation.
- Therefore a verdict is persisted as feedback with
  `authority: "local-http-feedback"` and the store header
  `approvalAuthority: "chat-sign-off-required"`. The UI labels an approval
  "Reviewer feedback — not sign-off".
- The server has no endpoint that writes `.memory-bank/decisions/`, no endpoint
  that runs a command, and no handoff trigger. `--state` resolving inside
  `.memory-bank/decisions` is refused at launch.
- The existing chat sign-off in the Software Architect workflow stays the only
  thing that authorizes implementation.

### 5. Local state

- State lives under a declared root (`--state`, default
  `<root>/.copilot-atelier/plan-review`), which is gitignored.
- Existing ancestors of the state root, records, temporary files, and lock
  paths are checked for links before reads and mutations. Replacing the state
  root with a junction after launch fails closed.
- Writes are atomic: a temp file in the same directory, then `rename`. Mutual
  exclusion uses an exclusive `mkdir` lock with a stale-lock timeout, so a
  crashed process does not deadlock the next one.
- The store holds only the document id, the revision hash, section keys and
  hashes, comment text, and verdicts. It never holds document content, secrets,
  or unrelated project material.
- Unsent comments use tab-scoped session storage keyed by document, revision,
  and section. They contain user-entered text only, no authentication data,
  and are never applied automatically to a newer revision.

### 6. Server lifetime and session

- Bind address is `127.0.0.1` only. `Host` must match the bound authority and
  `Origin`, when present, must equal the exact server origin; `Sec-Fetch-Site`
  must be `same-origin` or `none` when the browser sends it.
- A session secret is generated per launch with `crypto.randomBytes` and is
  never persisted. Feedback written by an earlier server therefore cannot grant
  a later server's session any access: a new launch mints a new secret, and the
  cookie from the old launch fails constant-time comparison.
- Mutating requests require the session cookie *and* a matching `X-CSRF-Token`
  header (double submit), so a cross-site form or `fetch` without the token is
  rejected even if the cookie rides along.
- Lifetime is bounded by `--ttl` (default 1800 s, hard maximum 14400 s) and the
  server exits when it expires. `POST /api/shutdown` stops it immediately, and
  the CLI prints both the URL and the stop procedure.

## Revision and section identity

- A revision is `sha256` over the document bytes, reported as `revision.hash`.
- A section key is the slug of its heading plus an occurrence ordinal, so two
  identically-titled headings do not collide.
- Comments on duplicate headings retain an ambiguity flag. Reattachment needs
  one exact heading and content-hash match; changed, removed, or
  indistinguishable duplicates remain unanchored.
- A comment stores the section key, the section body hash, and the heading text
  it was written against. On reload the comment is `current` when both match,
  `revised` when the key survives but the body hash changed, and `orphaned` when
  the key is gone. An orphaned comment is listed separately and is never
  re-anchored to different content.
- A verdict stores the document hash it was cast against. When the document
  changes the verdict becomes `stale` and the UI reports the approval as
  invalidated. Posting a comment or verdict with a hash that no longer matches
  the file returns `409` with `state: "stale"`.

## What is out of scope

No hosted service, no multi-user collaboration, no authentication provider, no
remote storage, no telemetry, no automatic implementation approval, and no
replacement for the Memory Bank.

## Residual risks

1. Any local process running as the same user can reach the loopback port and
   read the opened documents. Loopback binding is a reachability reduction, not
   an authorization boundary; the session secret and CSRF token raise the cost
   but do not defeat a local attacker who can read the process environment.
2. `style-src 'unsafe-inline'` is required by Mermaid's generated SVG.
3. Dependency supply chain: `markdown-it`, `dompurify`, `jsdom`, `mermaid`, and
   `lucide` are third-party. They are confined to the optional package and are
   never installed for ordinary module consumers.
4. Independent review of the HTTP and approval boundaries is recommended and was
   not performed; this run was executed with `review: off`.
