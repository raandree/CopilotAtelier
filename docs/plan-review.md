# Plan review — optional local review surface

A small, loopback-only web surface that renders a Design Concept, lets you
attach comments to stable sections, and records a verdict against one specific
revision of the document.

It is **optional**. Nothing in the CopilotAtelier PowerShell module needs it,
`Install-CopilotAtelier` never deploys it, and a Gallery install does not carry
it. The existing chat review of a Design Concept keeps working unchanged.

## What it is not

It does not sign anything off. A verdict recorded in the browser proves that
something holding the session cookie and the CSRF token posted a content hash —
it does not prove who did it or that they may authorize implementation. Feedback
is therefore stored with `authority: "local-http-feedback"` under a store header
of `approvalAuthority: "chat-sign-off-required"`, and the page says so above the
document. The
[Software Architect](../com.github.copilot/agents/software-architect.agent.md)
sign-off in chat stays the only thing that starts implementation.

There is no handoff trigger, no command endpoint, and no path that writes a
Decision record.

## Setup

Requires Node.js 20.11 or newer. Install the dependencies once, explicitly, in
the package folder:

```powershell
Push-Location tools/plan-review
npm install
Pop-Location
```

For the browser checks, Playwright drives the installed Microsoft Edge through
its `msedge` channel; no browser bundle is downloaded.

## Running it

```powershell
node tools/plan-review/src/cli.mjs --document tools/plan-review/samples/design-concept-sample.md --ttl 900
```

| Option | Meaning | Default |
|---|---|---|
| `--document <path>` | A Markdown file to open. Repeat for several. Only these files are ever readable. | required |
| `--root <dir>` | Containment root every document must sit inside. | the first document's folder |
| `--state <dir>` | Where feedback is stored. | `<root>/.copilot-atelier/plan-review` |
| `--port <number>` | Loopback port. | `0` (an unused port) |
| `--ttl <seconds>` | Bounded lifetime, 1 to 14400. | `1800` |

The launcher prints the URL, the expiry, and the process id. The URL carries a
per-launch session key; opening it sets an `HttpOnly`, `SameSite=Strict` cookie and
redirects to a key-free address. The cookie is named after the launch, so a
second review server opened in the same browser does not sign the first one out.
Binding to `::1` is supported and produces a bracketed `http://[::1]:<port>`
URL; any other address is refused.

The shipped sample under `tools/plan-review/samples/` is a demonstration fixture.
It describes no planned work and approving it approves nothing.

## Using it

- Select an opened document from the title-bar selector when several files
  were authorized at launch. It cannot open an additional filesystem path.
- **Comment** on a section anchors the remark to that section's key and content
  hash.
- **Approve** and **Request changes** record a verdict against the revision hash
  you are looking at. If the file changed underneath you, the request is refused
  with a stale response rather than silently applied to new content. That check
  runs again inside the serialized write, so an edit made while the request is
  queued cannot receive an approval for the old bytes.
  An open verdict dialog retains its original document and revision even if a
  background refresh loads newer content.
- **Reload** re-reads the file from disk.
- **Stop server** shuts the server down.
- The section outline is a disclosure. It starts open beside the document on a
  wide viewport and collapsed on a narrow one, so the document is readable
  without scrolling past a list of links.
- Keyboard: <kbd>j</kbd> / <kbd>k</kbd> move between sections, <kbd>c</kbd>
  opens the composer for the focused section, <kbd>r</kbd> reloads. The
  shortcuts are named in the button tooltips and announced to assistive
  technology rather than printed permanently on the page.

### Revision and section states

| State shown | Meaning |
|---|---|
| Pending review | No verdict has been recorded for this document |
| Approved (feedback) · revision `abc1234` | A verdict exists and matches the file on disk |
| Changes requested · revision `abc1234` | Likewise, for a change request |
| … invalidated by an edit | The document changed after the verdict; the verdict no longer applies |
| Comment badge *Current* | The section is byte-identical to when the comment was written |
| Comment badge *Section revised* | The section still exists but its content changed |
| Comment badge *Unanchored* | The section was removed; the comment is listed separately and never re-attached |

For duplicate headings, an anchor survives only when exactly one section has
the original heading and content hash. Ambiguous or changed duplicates remain
unanchored rather than attaching a comment to a different section. Section keys
are unique across the whole document, so a numbered heading such as `Risks 2`
can never share a key with the second `Risks`.

## Trust boundaries

The full analysis is in
[plan-review-threat-model.md](plan-review-threat-model.md). In short:

- **Loopback only.** The server refuses any non-loopback bind address. Loopback
  is a reachability reduction, not an authorization boundary.
- **Host and Origin.** Every request must carry a `Host` matching the bound
  authority; every mutation must carry the exact server `Origin`, a
  `Sec-Fetch-Site` of `same-origin` or `none` when the browser sends one, a JSON
  content type, the session cookie, and a matching `X-CSRF-Token`.
- **Explicit artifacts only.** Documents are authorized at launch and addressed
  on the wire by an opaque 16-character identifier. No request parameter names a
  path. There is no directory listing, URL fetcher, or shell endpoint.
- **Containment.** Every path is realpath-resolved, required to sit inside the
  declared root, and rejected if any ancestor from the root down is a symbolic
  link or junction. The check runs again at read time, not only at launch.
- **Rendering.** `markdown-it` runs with raw HTML disabled; DOMPurify then
  applies a tag, attribute, and URI allow-list. Images are not fetched — the
  alternative text is rendered instead. Mermaid runs client-side with
  `securityLevel: 'strict'` and its SVG is sanitized again before insertion.
  The response carries `Content-Security-Policy: default-src 'none'` with
  `script-src 'self'`.
- **Sessions do not survive a restart.** The session secret is generated per
  launch and never persisted, so a cookie from an earlier server is rejected by
  the next one even when the stored feedback is reused.
- **Bounded.** Request bodies cap at 64 KiB, comment bodies at 4000 characters,
  notes at 2000, comments at 200 per document, and documents at 1 MiB. The
  stored feedback file caps at 2 MiB on both the read and the write path,
  measured in UTF-8 bytes, so multibyte comments cannot produce a file the next
  read refuses; a write that would cross it is refused and the existing file is
  left unchanged. The
  same document checks run at launch and reload; binary and invalid UTF-8
  input are rejected. Revision hashes cover the original file bytes.
  The server exits when its lifetime expires.

## Where state lives

Feedback is written to `<state>/<documentId>.json` — by default under
`<root>/.copilot-atelier/plan-review`, which is gitignored. Writes are atomic
(temp file then rename) and serialized with an exclusive directory lock that
names its owning process. A lock whose owner is still running is waited on and
then refused; only a lock whose named owner is provably gone is reclaimed, and
the reclaim removes the two entries this tool writes rather than deleting a
directory tree it does not own. A mutation that loses its lock does not commit.

A record holds the document id, the revision hash, section keys and hashes,
comment text, and one verdict. It never holds document content, credentials, or
unrelated project material.

A store file that cannot be read within its bound, does not name this document,
or fails record validation is reported in the page and **left exactly as it is**.
The next comment or verdict is refused rather than overwriting somebody's
pending feedback. Recovery is a deliberate act: move or delete
`<state>/<documentId>.json` yourself, then reload. A stored `authority` value is
never trusted as sign-off; only the value this tool writes is accepted, and
every stored hash must be a lowercase SHA-256 digest.

A comment or verdict that would push the file past the 2 MiB bound is refused
with `store-capacity` and the existing file is untouched, so the store can never
write a record it would later refuse to read. Remove some feedback, or move the
file aside, to make room.

Unsent comments are saved in the browser tab's session storage, keyed by the
document, revision, and section. Reloading the same revision restores them;
closing the tab clears them. A draft written against a revision or a section
that is no longer current is **not** attached to the new content: it is listed
under *Unsent drafts from an earlier revision* with the section and revision it
was written on, and you discard it explicitly. A pending verdict note survives a
stale refusal and is offered again when the dialog is reopened. No session key
or CSRF token is stored with any of this. A temporary connection failure leaves
submission available for retry.

`--state` resolving inside `.memory-bank/decisions` is refused at launch.
State roots, records, temporary files, and locks reject linked ancestors,
including a state directory replaced by a junction after launch. These checks
do not provide containment against a hostile process running as the same user
that can race a filesystem check or read the launch-session key.

## Shutdown

Any of:

- press <kbd>Ctrl</kbd>+<kbd>C</kbd> in the launching terminal;
- press **Stop server** in the page;
- `Stop-Process -Id <the process id the launcher printed>`;
- wait for `--ttl` to expire.

The server closes its listener and destroys open sockets, so the port is free
immediately. Nothing survives except the feedback file.

## Rollback

Delete `tools/plan-review/node_modules` and the state folder. To remove the
feature entirely, delete `tools/plan-review/`, this document, the threat model,
and `tests/PlanReview.Tests.ps1`. Nothing else in the repository depends on it,
and no migration is required in either direction — the store format is version 1
and is only ever read by this tool.

## Testing

```powershell
Push-Location tools/plan-review
npm run test:unit               # no dependencies required
npm test                       # unit plus integration, needs npm install
npm run lint                   # native Node syntax checks
npm run test:browser           # Playwright against installed Edge
Pop-Location
```

`tests/PlanReview.Tests.ps1` runs in the ordinary repository gate. It checks the
package layout and the trust-boundary invariants, and it executes the
dependency-free half of the Node suite when `node` is on `PATH`, skipping it
cleanly when it is not. It never runs `npm install`.

## Unsupported

- Headings the section splitter cannot anchor: a heading inside a blockquote or
  a list item, and any document whose heading structure the Markdown parser
  reads differently from the splitter. A section is the anchor for every
  comment, so a disagreement would attach feedback to text the reader never saw.
  Such a document is refused rather than shown: the launcher exits with
  `heading-structure` and an open page reports it as no longer readable. This is
  a hard refusal, not a degraded read-only view. ATX headings indented by up to
  three spaces and setext headings (underlined with `=` or `-`) are supported.
- Multiple concurrent reviewers, accounts, or any authentication provider.
- Remote or shared storage, telemetry, and network access of any kind.
- Editing the document from the browser.
- Rendering anything other than Markdown, including HTML fragments and images.
- Proving who recorded a verdict, and therefore anything that would need that
  proof — automatic handoff, unattended implementation, or updating a Decision
  record.
