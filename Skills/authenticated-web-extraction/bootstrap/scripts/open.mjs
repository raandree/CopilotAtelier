// Opens the persistent Edge profile. Pass URLs as args; defaults to a starter set.
// Window stays open until you close it. All cookies/localStorage persist to ./profile.
//
// Auth cookies are also saved to ../auth-state/<domain>.json so that
// session-scoped cookies (which Chromium discards on shutdown) survive across runs.
import { chromium } from 'playwright';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import fs from 'node:fs';
import { execSync } from 'node:child_process';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, '..');
const PROFILE_DIR = path.join(ROOT, 'profile');
const AUTH_STATE_DIR = path.join(ROOT, 'auth-state');
fs.mkdirSync(AUTH_STATE_DIR, { recursive: true });

const DEFAULT_URLS = [
  'https://www.linkedin.com/feed/',
  'https://github.com/',
  'https://sessionize.com/app/speaker/'
];

const urls = process.argv.slice(2).length ? process.argv.slice(2) : DEFAULT_URLS;

// Detect orphan msedge processes that already hold the profile lock and refuse
// to launch — bail with a clear error rather than silently spawning a dud.
function checkProfileLock() {
  const lockFile = path.join(PROFILE_DIR, 'SingletonLock');
  // Chromium-style profiles also write Default/Cookies-journal files while open.
  if (fs.existsSync(lockFile)) {
    return 'SingletonLock exists in profile directory';
  }
  if (process.platform === 'win32') {
    try {
      const out = execSync('tasklist /FI "IMAGENAME eq msedge.exe" /FO CSV /NH', { encoding: 'utf8' });
      if (out.trim().toLowerCase().includes('msedge.exe')) {
        return 'msedge.exe processes are already running; close them or run scripts/cleanup.mjs';
      }
    } catch { /* tasklist not available – ignore */ }
  }
  return null;
}

const lockReason = checkProfileLock();
if (lockReason) {
  console.error(`ERROR: cannot launch — ${lockReason}.`);
  console.error('Run: powershell -Command "Get-Process msedge | Stop-Process -Force"');
  process.exit(2);
}

let context;
try {
  context = await chromium.launchPersistentContext(PROFILE_DIR, {
    channel: 'msedge',
    headless: false,
    viewport: null,
    // Reduce automation fingerprints so LinkedIn etc. don't throw extra captchas.
    ignoreDefaultArgs: ['--enable-automation'],
    args: [
      '--disable-blink-features=AutomationControlled',
      '--start-maximized',
      // Edge's tracking prevention blocks third-party cookies set during OAuth
      // callbacks (e.g. Sessionize -> Microsoft -> sessionize.com/signin-microsoft).
      // Disable the relevant features and partitioning so cross-site auth cookies
      // can be written by the OAuth callback handler.
      '--disable-features=TrackingPrevention,ThirdPartyStoragePartitioning,PrivacySandboxAdsAPIs,FedCm',
      '--disable-site-isolation-trials'
    ]
  });
} catch (err) {
  console.error('Failed to launch persistent context:', err.message);
  process.exit(1);
}

// Re-inject any previously saved auth state (covers session-scoped cookies).
for (const f of fs.readdirSync(AUTH_STATE_DIR)) {
  if (!f.endsWith('.json')) continue;
  try {
    const cs = JSON.parse(fs.readFileSync(path.join(AUTH_STATE_DIR, f), 'utf8'));
    if (Array.isArray(cs) && cs.length > 0) await context.addCookies(cs);
  } catch (err) {
    console.warn(`Failed to re-inject ${f}: ${err.message}`);
  }
}

console.log(`Profile: ${PROFILE_DIR}`);
console.log(`Opening ${urls.length} tab(s):`);
for (const u of urls) console.log(`  - ${u}`);

// Reuse the initial about:blank page for the first URL, then add tabs for the rest.
const pages = context.pages();
const first = pages[0] ?? await context.newPage();

// Log every top-level navigation so we can diagnose SSO redirect chains.
function attachNavLogger(page, label) {
  page.on('framenavigated', frame => {
    if (frame === page.mainFrame()) {
      const url = frame.url();
      if (url && url !== 'about:blank') console.log(`[${label}] ${url}`);
    }
  });
}

attachNavLogger(first, 'tab1');
await first.goto(urls[0], { waitUntil: 'domcontentloaded' }).catch(err => console.error(`  goto failed: ${err.message}`));
let i = 2;
for (const u of urls.slice(1)) {
  const p = await context.newPage();
  attachNavLogger(p, `tab${i++}`);
  await p.goto(u, { waitUntil: 'domcontentloaded' }).catch(err => console.error(`  goto failed for ${u}: ${err.message}`));
}

console.log('Window is open. Log in to any sites you need. Close the window when done.');

const trackedDomains = ['https://sessionize.com', 'https://github.com', 'https://www.linkedin.com', 'https://x.com', 'https://www.meetup.com'];

// Save cookies for a tracked domain whenever its set changes (catches the
// short-lived session cookies set during OAuth callbacks that Chromium would
// otherwise discard on shutdown).
async function saveCookieSnapshot() {
  for (const d of trackedDomains) {
    try {
      const cs = await context.cookies(d);
      if (cs.length === 0) continue;
      const host = new URL(d).hostname.replace(/^www\./, '');
      const file = path.join(AUTH_STATE_DIR, `${host}.json`);
      // Promote session cookies to year-long persistence (auth cookies that
      // arrive without an explicit expiry would otherwise vanish on close).
      const yearFromNow = Math.floor(Date.now() / 1000) + 365 * 24 * 3600;
      const persisted = cs.map(c => ({
        ...c,
        expires: c.expires === -1 ? yearFromNow : c.expires
      }));
      fs.writeFileSync(file, JSON.stringify(persisted, null, 2), 'utf8');
    } catch { /* ignore */ }
  }
}

// Initial snapshot, then snapshot on every top-level navigation.
await saveCookieSnapshot();
context.on('page', p => {
  p.on('framenavigated', f => {
    if (f === p.mainFrame()) saveCookieSnapshot().catch(() => {});
  });
});
for (const p of context.pages()) {
  p.on('framenavigated', f => {
    if (f === p.mainFrame()) saveCookieSnapshot().catch(() => {});
  });
}

// Periodic snapshot every 5s as a safety net.
const interval = setInterval(() => saveCookieSnapshot().catch(() => {}), 5000);

context.on('close', () => clearInterval(interval));

await new Promise(resolve => context.on('close', resolve));

// Final snapshot attempt (may be a no-op if context already torn down).
await saveCookieSnapshot().catch(() => {});

console.log('Profile closed. Auth state saved to:');
for (const f of fs.readdirSync(AUTH_STATE_DIR)) console.log(`  ${path.join(AUTH_STATE_DIR, f)}`);

