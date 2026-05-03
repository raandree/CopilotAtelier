// Generic extraction harness.
// Usage:  node scripts/extract.mjs <taskName> [--headless] [extra args...]
// Loads tasks/<taskName>.mjs which must export `default async ({ context, page, args, outDir })`.
// Output is written by the task itself into ../extracted/.
import { chromium } from 'playwright';
import { fileURLToPath, pathToFileURL } from 'node:url';
import path from 'node:path';
import fs from 'node:fs';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, '..');
const PROFILE_DIR = path.join(ROOT, 'profile');
const TASKS_DIR = path.join(ROOT, 'tasks');
const OUT_DIR = path.join(ROOT, 'extracted');
const AUTH_STATE_DIR = path.join(ROOT, 'auth-state');

const rawArgs = process.argv.slice(2);
if (rawArgs.length === 0) {
  console.error('Usage: node scripts/extract.mjs <taskName> [--headless] [extra args...]');
  console.error('Available tasks:');
  if (fs.existsSync(TASKS_DIR)) {
    for (const f of fs.readdirSync(TASKS_DIR).filter(n => n.endsWith('.mjs'))) {
      console.error('  - ' + f.replace(/\.mjs$/, ''));
    }
  }
  process.exit(2);
}

const taskName = rawArgs[0];
const headless = rawArgs.includes('--headless');
const taskArgs = rawArgs.slice(1).filter(a => a !== '--headless');

const taskPath = path.join(TASKS_DIR, `${taskName}.mjs`);
if (!fs.existsSync(taskPath)) {
  console.error(`Task not found: ${taskPath}`);
  process.exit(2);
}

fs.mkdirSync(OUT_DIR, { recursive: true });

const context = await chromium.launchPersistentContext(PROFILE_DIR, {
  channel: 'msedge',
  headless,
  viewport: headless ? { width: 1440, height: 900 } : null,
  ignoreDefaultArgs: ['--enable-automation'],
  args: [
    '--disable-blink-features=AutomationControlled',
    '--disable-features=TrackingPrevention,ThirdPartyStoragePartitioning,PrivacySandboxAdsAPIs,FedCm',
    '--disable-site-isolation-trials',
    headless ? '' : '--start-maximized'
  ].filter(Boolean)
});

// Re-inject any saved auth-state cookies (covers session-scoped cookies that
// Chromium dropped on shutdown — e.g. Sessionize's auth cookie after OAuth).
if (fs.existsSync(AUTH_STATE_DIR)) {
  for (const f of fs.readdirSync(AUTH_STATE_DIR)) {
    if (!f.endsWith('.json')) continue;
    try {
      const cs = JSON.parse(fs.readFileSync(path.join(AUTH_STATE_DIR, f), 'utf8'));
      if (Array.isArray(cs) && cs.length > 0) {
        await context.addCookies(cs);
      }
    } catch (err) {
      console.warn(`Failed to re-inject ${f}: ${err.message}`);
    }
  }
}

const page = context.pages()[0] ?? await context.newPage();

let exitCode = 0;
try {
  const mod = await import(pathToFileURL(taskPath).href);
  if (typeof mod.default !== 'function') {
    throw new Error(`Task ${taskName} must export a default async function.`);
  }
  await mod.default({ context, page, args: taskArgs, outDir: OUT_DIR });
} catch (err) {
  console.error(`Task '${taskName}' failed:`, err);
  exitCode = 1;
} finally {
  await context.close();
  process.exit(exitCode);
}
