// Probes which sites the persistent profile is currently logged into.
// Writes a status report to ../extracted/login-status.md
import fs from 'node:fs';
import path from 'node:path';

/** @type {Array<{name: string, url: string, signedInSelector: string, signedInText?: string}>} */
const TARGETS = [
  {
    name: 'LinkedIn',
    url: 'https://www.linkedin.com/feed/',
    // Detected via the li_at auth cookie rather than DOM selectors (LinkedIn's
    // markup changes frequently and varies between A/B variants).
    cookieDomain: 'https://www.linkedin.com',
    cookieName: 'li_at'
  },
  {
    name: 'GitHub',
    url: 'https://github.com/',
    cookieDomain: 'https://github.com',
    cookieName: 'user_session'
  },
  {
    name: 'Sessionize',
    url: 'https://sessionize.com/app/speaker/',
    // ASP.NET Identity auth cookie (set by Sessionize's OAuth callback handler).
    cookieDomain: 'https://sessionize.com',
    cookieName: '.AspNet.ApplicationCookie'
  },
  {
    name: 'X (Twitter)',
    url: 'https://x.com/home',
    cookieDomain: 'https://x.com',
    cookieName: 'auth_token'
  },
  {
    name: 'Meetup',
    url: 'https://www.meetup.com/',
    cookieDomain: 'https://www.meetup.com',
    cookieName: 'MEETUP_MEMBER'
  }
];

export default async function checkLogins({ context, outDir }) {
  const lines = [];
  const ts = new Date().toISOString();
  lines.push(`# Login status`);
  lines.push('');
  lines.push(`Generated: ${ts}`);
  lines.push('');
  lines.push('| Site | Status | Detail |');
  lines.push('| --- | --- | --- |');

  for (const t of TARGETS) {
    let status = 'unknown';
    let detail = '';
    try {
      const cookies = await context.cookies(t.cookieDomain);
      const c = cookies.find(x => x.name === t.cookieName);
      if (c) {
        const exp = c.expires === -1 ? 'session' : new Date(c.expires * 1000).toISOString();
        status = 'signed in';
        detail = `${t.cookieName} expires ${exp}`;
      } else {
        status = 'not signed in';
        detail = `no ${t.cookieName} cookie`;
      }
    } catch (err) {
      status = `error: ${err.message.split('\n')[0]}`;
    }
    lines.push(`| ${t.name} | ${status} | ${detail} |`);
    console.log(`${t.name.padEnd(14)} ${status.padEnd(14)} ${detail}`);
  }

  const outPath = path.join(outDir, 'login-status.md');
  fs.writeFileSync(outPath, lines.join('\n') + '\n', 'utf8');
  console.log(`\nWrote ${outPath}`);
}
