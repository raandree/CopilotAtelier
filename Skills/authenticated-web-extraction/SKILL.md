---
name: authenticated-web-extraction
description: >-
  Extract data from sites that require login (LinkedIn, GitHub, Sessionize,
  Microsoft 365, X, Meetup, etc.) using a persistent Playwright + Microsoft Edge
  profile. Covers profile setup, interactive sign-in capture, session-cookie
  re-injection (works around Chromium dropping session-only auth cookies on
  shutdown), cookie-based auth detection, OAuth callback flags, and a generic
  task harness pattern. Use this when a user asks for data from an authenticated
  page and copy/pasting from the browser is too tedious or error-prone.
  USE FOR: scrape LinkedIn, scrape GitHub, scrape Sessionize, authenticated
  scraping, persistent browser profile, Playwright Edge profile, Playwright
  msedge channel, headless authenticated extraction, session cookie persistence,
  OAuth callback cookie, ASP.NET ApplicationCookie, li_at, user_session,
  AspNet ApplicationCookie, Sessionize cookie, LinkedIn profile extraction,
  GitHub profile extraction, sessionize speaker dashboard, login status check,
  cookie-based auth detection, launchPersistentContext, Edge tracking prevention
  third-party cookie OAuth, FedCm SSO, profile lock orphan msedge, CV resume
  data extraction from web.
  DO NOT USE FOR: posting or mutating user accounts (always extract → propose →
  user pastes manually), CAPTCHA-heavy targets, scraping at scale (rate limiting
  not implemented), Microsoft Graph API access (use Graph SDK / device-code flow
  via microsoft-todo-tasks skill), Outlook COM (use outlook-* skills).
---

# Authenticated Web Extraction (CareerAuthBrowser)

Persistent Playwright + Microsoft Edge profile for pulling data out of sites that require login. Tool lives at `%LOCALAPPDATA%\CareerAuthBrowser\` on the user's workstation; this skill documents how to operate and extend it.

## When to Use

- User asks to extract their LinkedIn profile, GitHub repos, Sessionize sessions, Meetup events, etc.
- Copy/paste from the browser would be slow, lossy, or error-prone.
- A site uses interactive SSO (Microsoft, Google, GitHub OAuth) that pure-API tooling can't handle without app registration.

## Architecture

| Path | Role |
| --- | --- |
| `%LOCALAPPDATA%\CareerAuthBrowser\scripts\open.mjs` | Visible Edge window for interactive logins. Auto-snapshots cookies for tracked domains every 5s and on close. |
| `%LOCALAPPDATA%\CareerAuthBrowser\scripts\extract.mjs` | Generic harness. Re-injects saved cookies, runs `tasks/<name>.mjs`, then closes. Supports `--headless`. |
| `%LOCALAPPDATA%\CareerAuthBrowser\tasks\` | One ESM file per extraction. Default-export `async ({ context, page, args, outDir }) => {…}`. |
| `%LOCALAPPDATA%\CareerAuthBrowser\auth-state\` | Per-domain cookie JSON. Survives close so session-only cookies keep working. **Never commit.** |
| `%LOCALAPPDATA%\CareerAuthBrowser\profile\` | Edge user-data dir (cookies, localStorage, IndexedDB). **Never commit.** |
| `%LOCALAPPDATA%\CareerAuthBrowser\extracted\` | Default output for tasks. |

Canonical sources of `package.json`, `scripts/*.mjs`, and the generic tasks (`check-logins`, `dump-cookies`) are bundled under `bootstrap/` next to this file. See [Bootstrap from Scratch](#bootstrap-from-scratch).

## Bootstrap from Scratch

If `%LOCALAPPDATA%\CareerAuthBrowser\` does not exist (new machine, wiped profile, etc.), recreate it from the bundled `bootstrap/` folder:

```pwsh
$dst = "$env:LOCALAPPDATA\CareerAuthBrowser"
$src = '<path-to-this-skill>\bootstrap'
New-Item -ItemType Directory -Path $dst, "$dst\scripts", "$dst\tasks" -Force | Out-Null
Copy-Item "$src\package.json"            "$dst\package.json"            -Force
Copy-Item "$src\scripts\open.mjs"        "$dst\scripts\open.mjs"        -Force
Copy-Item "$src\scripts\extract.mjs"     "$dst\scripts\extract.mjs"     -Force
Copy-Item "$src\tasks\check-logins.mjs"  "$dst\tasks\check-logins.mjs"  -Force
Copy-Item "$src\tasks\dump-cookies.mjs"  "$dst\tasks\dump-cookies.mjs"  -Force
cd $dst; npm install
```

`npm install` pulls Playwright (msedge channel reuses the system Edge install — no Chromium download needed). The user-data-dir, auth-state, and extracted output folders are created lazily on first run.

## Standard Workflow

1. **Check auth.** Run `check-logins` first — never assume the profile is still signed in.

   ```pwsh
   cd "$env:LOCALAPPDATA\CareerAuthBrowser"; node scripts/extract.mjs check-logins --headless
   Get-Content "$env:LOCALAPPDATA\CareerAuthBrowser\extracted\login-status.md"
   ```

2. **If `not signed in`**, open the visible window for the user to sign in:

   ```pwsh
   cd "$env:LOCALAPPDATA\CareerAuthBrowser"; node scripts/open.mjs '<login URL>'
   ```

   Tell the user: "Sign in until you see the dashboard, then close the window." `open.mjs` snapshots cookies every 5 seconds, so the user does not need to wait after the dashboard renders. Re-run `check-logins` to confirm before continuing.

3. **Run the extraction task headlessly.** Read its output from `extracted/`.

4. **Copy/transform the output** into the user's workspace (typically `Input/`).

## Critical Gotchas

### Cookie names per site

Auth detection must use cookies, not DOM selectors. LinkedIn's markup changes between A/B variants and breaks selector-based checks.

| Site | Auth cookie | Domain |
| --- | --- | --- |
| LinkedIn | `li_at` | `https://www.linkedin.com` |
| GitHub | `user_session` | `https://github.com` |
| Sessionize | `.AspNet.ApplicationCookie` | `https://sessionize.com` |
| X | `auth_token` | `https://x.com` |
| Meetup | `MEETUP_MEMBER` | `https://www.meetup.com` |

**Sessionize cookie name is `.AspNet.ApplicationCookie`, not `.AspNet.Cookies` or `.AspNetCore.Cookies`.** Sessionize runs ASP.NET (Identity / OWIN), not ASP.NET Core. Verify with `tasks/dump-cookies.mjs` if a new site behaves unexpectedly.

### Session cookies vanish on Chromium shutdown

Sessionize (and many ASP.NET Identity sites) sets its auth cookie with no `expires` attribute, making it session-scoped. Chromium discards session cookies when the persistent context closes — even though the user-data-dir is preserved. The fix is implemented in `open.mjs` and `extract.mjs`:

1. While the browser is open, periodically read `context.cookies(domain)` and write to `auth-state/<host>.json`.
2. Promote any cookie with `expires === -1` (session) to `now + 365 days`.
3. On every subsequent `extract.mjs` run, call `context.addCookies(...)` from `auth-state/*.json` before navigating.

Do not remove this logic. Without it, Sessionize logs out on every restart even though LinkedIn and GitHub keep working.

### Edge / Chromium flags required for OAuth callbacks

Edge's tracking prevention blocks the third-party cookie set by `sessionize.com/signin-microsoft` after a Microsoft OAuth round-trip. Always launch with:

```js
ignoreDefaultArgs: ['--enable-automation'],
args: [
  '--disable-blink-features=AutomationControlled',
  '--disable-features=TrackingPrevention,ThirdPartyStoragePartitioning,PrivacySandboxAdsAPIs,FedCm',
  '--disable-site-isolation-trials',
  // visible only:
  '--start-maximized'
]
```

`AutomationControlled` removal also reduces extra captchas on LinkedIn.

### Profile-lock orphan processes

If `open.mjs` hangs immediately after launch with no visible window, orphan `msedge.exe` processes are holding the user-data-dir lock. Detect:

```pwsh
Get-Process msedge -ErrorAction SilentlyContinue | Format-Table Id, StartTime, MainWindowTitle
Test-Path "$env:LOCALAPPDATA\CareerAuthBrowser\profile\SingletonLock"
```

Fix: `Stop-Process -Name msedge -Force`. `open.mjs` has built-in detection that reports this and exits cleanly.

### Never mutate user profiles automatically

Default rule for any extraction agent: **extract → propose changes → user pastes manually.** Do not click "Save" on LinkedIn About edits, do not push commits to GitHub repos found via the profile, do not RSVP to Meetup events. Ask before any mutation.

## Adding a New Task

```js
// tasks/<name>.mjs
import fs from 'node:fs';
import path from 'node:path';

export default async function run({ context, page, args, outDir }) {
  await page.goto('https://example.com/protected', { waitUntil: 'domcontentloaded' });

  // Detect logged-out state up front — saves debugging time.
  if (page.url().includes('/login')) {
    throw new Error('Not signed in. Run: node scripts/open.mjs https://example.com/login');
  }

  const data = await page.evaluate(() => {
    // ... DOM scraping in page context ...
    return { /* ... */ };
  });

  const outFile = path.join(outDir, '<name>.json');
  fs.writeFileSync(outFile, JSON.stringify(data, null, 2), 'utf8');
  console.log(`Wrote ${outFile}`);
}
```

Run with: `node scripts/extract.mjs <name> --headless`.

Pass extra args after the task name; they arrive as `args` in the task signature.

## Existing Tasks

- `check-logins` — auth status report → `extracted/login-status.md`. Run before every extraction.
- `dump-cookies` — JSON dump of all cookies grouped by domain. Use to discover unknown auth cookie names.
- `linkedin-probe` — confirms LinkedIn identity is signed in.
- `sessionize-probe` — confirms Sessionize speaker dashboard renders.

## Failure Modes & Diagnosis

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| `check-logins` shows site as "not signed in" right after sign-in | Cookie name in `tasks/check-logins.mjs` is wrong | Run `dump-cookies`, find the auth-like cookie, update `TARGETS` |
| Site logs out between runs but in-session works | Session-scoped cookie not captured | Confirm `auth-state/<host>.json` exists and contains the auth cookie with a future `expires`; verify the snapshot timer in `open.mjs` is running |
| OAuth completes but `/app/...` redirects to `/login` mid-session | Third-party cookie blocked | Confirm Edge launch flags include `TrackingPrevention,ThirdPartyStoragePartitioning,FedCm` |
| `open.mjs` exits or hangs with no window | Profile lock from orphan `msedge.exe` | `Stop-Process -Name msedge -Force` |
| Task throws "Target page, context or browser has been closed" | Task continued after `context.close()`; usually a missing `await` | Audit `await` chain in the task |

## Companion Prompt

VS Code prompt that wires this skill into a chat workflow: `%APPDATA%\Code\User\prompts\auth-extract.prompt.md`.
