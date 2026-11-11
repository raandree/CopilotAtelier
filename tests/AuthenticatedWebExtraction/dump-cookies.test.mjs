import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import dumpAllCookies from '../../skills/authenticated-web-extraction/bootstrap/tasks/dump-cookies.mjs';

test('lists cookie names and expiry dates but never a cookie value', async () => {
  const outDir = fs.mkdtempSync(path.join(os.tmpdir(), 'dump-cookies-'));
  const secret = 'secret-session-value';
  const context = {
    cookies: async () => [
      { name: 'reddit_session', value: secret, domain: '.reddit.com', path: '/', expires: 1900000000, httpOnly: true, secure: true, sameSite: 'None' },
      { name: 'session_tracker', value: `${secret}-2`, domain: 'www.reddit.com', path: '/', expires: -1, httpOnly: false, secure: true, sameSite: 'Lax' }
    ]
  };

  const lines = [];
  const realLog = console.log;
  console.log = (...parts) => lines.push(parts.join(' '));
  try {
    await dumpAllCookies({ context, outDir });
  } finally {
    console.log = realLog;
  }

  const written = fs.readFileSync(path.join(outDir, 'all-cookies.json'), 'utf8');
  assert.doesNotMatch(written, new RegExp(secret));
  assert.doesNotMatch(lines.join('\n'), new RegExp(secret));
  const listed = JSON.parse(written);
  assert.deepEqual(listed.map(cookie => cookie.name).sort(), ['reddit_session', 'session_tracker']);
  for (const cookie of listed) {
    assert.equal(Object.hasOwn(cookie, 'value'), false);
    assert.ok(cookie.domain && 'expires' in cookie, 'names and expiry stay available for diagnosis');
  }
});
