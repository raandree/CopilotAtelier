import assert from 'node:assert/strict'
import { mkdtempSync, writeFileSync } from 'node:fs'
import { request as httpRequest } from 'node:http'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { after, before, describe, it } from 'node:test'

import { MAX_BODY_BYTES } from '../../src/security.mjs'
import { createReviewServer } from '../../src/server.mjs'

/**
 * `fetch` refuses to set a Host header, so DNS-rebinding style cases have to go
 * through the raw client.
 */
function rawRequest ({ port, path, method = 'POST', headers = {}, body = '' }) {
  return new Promise((resolve, reject) => {
    const request = httpRequest(
      { host: '127.0.0.1', port, path, method, headers, setHost: false },
      (response) => {
        const chunks = []
        response.on('data', (chunk) => chunks.push(chunk))
        response.on('end', () => resolve({
          status: response.statusCode,
          text: Buffer.concat(chunks).toString('utf8')
        }))
      }
    )

    request.on('error', reject)
    request.end(body)
  })
}

const documentBody = [
  '# Sample concept',
  '',
  'Preamble text.',
  '',
  '## Scope',
  '',
  'In scope.',
  '',
  '```mermaid',
  'flowchart TD',
  '  A --> B',
  '```',
  '',
  '## Rollback',
  '',
  'Delete the folder.',
  ''
].join('\n')

function makeWorkspace () {
  const root = mkdtempSync(join(tmpdir(), 'plan-review-server-'))
  const documentPath = join(root, 'concept.md')
  writeFileSync(documentPath, documentBody, 'utf8')
  const stateRoot = join(root, '.state')

  return { root, documentPath, stateRoot }
}

async function launch (overrides = {}) {
  const workspace = makeWorkspace()
  const server = createReviewServer({
    documents: [{ root: workspace.root, path: workspace.documentPath }],
    stateRoot: workspace.stateRoot,
    ttlSeconds: 120,
    ...overrides
  })

  await server.listen()

  return { ...workspace, server }
}

describe('createReviewServer', () => {
  let fixture
  let cookie
  let csrfToken
  let documentId

  before(async () => {
    fixture = await launch()

    const bootstrap = await fetch(`${fixture.server.origin}/?s=${fixture.server.sessionKey}`, {
      redirect: 'manual'
    })

    assert.equal(bootstrap.status, 302)
    cookie = bootstrap.headers.getSetCookie()[0].split(';')[0]

    const session = await fetch(`${fixture.server.origin}/api/session`, { headers: { cookie } })
    const payload = await session.json()

    csrfToken = payload.csrfToken
    documentId = payload.documents[0].id
  })

  after(async () => {
    await fixture.server.close()
  })

  function mutate (path, body, headerOverrides = {}) {
    return fetch(`${fixture.server.origin}${path}`, {
      method: 'POST',
      redirect: 'manual',
      headers: {
        cookie,
        origin: fixture.server.origin,
        'content-type': 'application/json',
        'x-csrf-token': csrfToken,
        ...headerOverrides
      },
      body: JSON.stringify(body)
    })
  }

  it('binds to loopback only', () => {
    assert.equal(fixture.server.address.address, '127.0.0.1')
  })

  it('refuses the application shell without a session', async () => {
    const response = await fetch(`${fixture.server.origin}/`, { redirect: 'manual' })

    assert.equal(response.status, 401)
  })

  it('refuses a bootstrap key that does not match', async () => {
    const response = await fetch(`${fixture.server.origin}/?s=${'0'.repeat(64)}`, { redirect: 'manual' })

    assert.equal(response.status, 401)
    assert.deepEqual(response.headers.getSetCookie(), [])
  })

  it('serves the application shell with a strict content security policy', async () => {
    const response = await fetch(`${fixture.server.origin}/`, { headers: { cookie } })
    const policy = response.headers.get('content-security-policy')

    assert.equal(response.status, 200)
    assert.match(policy, /default-src 'none'/)
    assert.match(policy, /script-src 'self'/)
    assert.match(policy, /connect-src 'self'/)
    assert.match(policy, /frame-ancestors 'none'/)
    assert.ok(!policy.includes("script-src 'self' 'unsafe-inline'"))
    assert.ok(!policy.includes('unsafe-eval'))
    assert.equal(response.headers.get('x-content-type-options'), 'nosniff')
    assert.equal(response.headers.get('referrer-policy'), 'no-referrer')
  })

  it('marks the session cookie HttpOnly, SameSite=Strict and path scoped', async () => {
    const bootstrap = await fetch(`${fixture.server.origin}/?s=${fixture.server.sessionKey}`, {
      redirect: 'manual'
    })
    const header = bootstrap.headers.getSetCookie()[0]

    assert.match(header, /HttpOnly/i)
    assert.match(header, /SameSite=Strict/i)
    assert.match(header, /Path=\//)
  })

  it('reports the opened documents without leaking their paths', async () => {
    const response = await fetch(`${fixture.server.origin}/api/session`, { headers: { cookie } })
    const payload = await response.json()

    assert.equal(payload.documents.length, 1)
    assert.match(payload.documents[0].id, /^[0-9a-f]{16}$/)
    assert.equal(payload.approvalAuthority, 'chat-sign-off-required')
    assert.ok(!JSON.stringify(payload).includes(fixture.root))
  })

  it('renders the document with sections, diagrams and a revision hash', async () => {
    const response = await fetch(`${fixture.server.origin}/api/document/${documentId}`, {
      headers: { cookie }
    })
    const payload = await response.json()

    assert.equal(response.status, 200)
    assert.match(payload.revision.hash, /^[0-9a-f]{64}$/)
    assert.deepEqual(payload.sections.map((section) => section.key), ['sample-concept', 'scope', 'rollback'])
    assert.match(payload.sections[1].html, /class="pr-diagram"/)
    assert.equal(payload.verdict.state, 'none')
  })

  it('refuses an unknown document identifier', async () => {
    const response = await fetch(`${fixture.server.origin}/api/document/${'f'.repeat(16)}`, {
      headers: { cookie }
    })

    assert.equal(response.status, 404)
  })

  it('refuses a traversal attempt in the document identifier', async () => {
    for (const candidate of ['..%2f..%2fetc%2fpasswd', '../../package.json', 'C%3A%5Cwindows%5Cwin.ini']) {
      const response = await fetch(`${fixture.server.origin}/api/document/${candidate}`, {
        headers: { cookie }
      })

      assert.ok(response.status === 400 || response.status === 404, `expected rejection for ${candidate}`)
      assert.ok(!(await response.text()).includes('BEGIN'))
    }
  })

  it('has no generic static handler reachable from the vendor route', async () => {
    for (const candidate of ['/vendor/../src/server.mjs', '/vendor/..%2Fsrc%2Fserver.mjs', '/vendor/anything.js']) {
      const response = await fetch(`${fixture.server.origin}${candidate}`, { headers: { cookie } })

      assert.equal(response.status, 404, `expected 404 for ${candidate}`)
    }
  })

  it('serves only the allow-listed vendor assets', async () => {
    const response = await fetch(`${fixture.server.origin}/vendor/mermaid.min.js`, { headers: { cookie } })

    assert.equal(response.status, 200)
    assert.match(response.headers.get('content-type'), /javascript/)
  })

  it('records a comment bound to the section and document hash', async () => {
    const document = await (await fetch(`${fixture.server.origin}/api/document/${documentId}`, {
      headers: { cookie }
    })).json()
    const scope = document.sections.find((section) => section.key === 'scope')

    const response = await mutate(`/api/document/${documentId}/comment`, {
      sectionKey: scope.key,
      sectionHash: scope.hash,
      headingText: scope.heading,
      documentHash: document.revision.hash,
      body: 'Narrow this section.'
    })
    const payload = await response.json()

    assert.equal(response.status, 201)
    assert.equal(payload.state, 'recorded')
  })

  it('rejects a comment cast against a revision that is no longer current', async () => {
    const response = await mutate(`/api/document/${documentId}/comment`, {
      sectionKey: 'scope',
      sectionHash: 'whatever',
      documentHash: 'a'.repeat(64),
      body: 'Written against an old revision.'
    })

    assert.equal(response.status, 409)
    assert.equal((await response.json()).state, 'stale')
  })

  it('rejects a comment on a section that does not exist', async () => {
    const document = await (await fetch(`${fixture.server.origin}/api/document/${documentId}`, {
      headers: { cookie }
    })).json()

    const response = await mutate(`/api/document/${documentId}/comment`, {
      sectionKey: 'no-such-section',
      sectionHash: 'x',
      documentHash: document.revision.hash,
      body: 'Nowhere.'
    })

    assert.equal(response.status, 409)
    assert.equal((await response.json()).state, 'unknown-section')
  })

  it('rejects a mutation without the CSRF token', async () => {
    const response = await fetch(`${fixture.server.origin}/api/document/${documentId}/comment`, {
      method: 'POST',
      headers: { cookie, origin: fixture.server.origin, 'content-type': 'application/json' },
      body: JSON.stringify({ sectionKey: 'scope', documentHash: 'x', body: 'no token' })
    })

    assert.equal(response.status, 403)
    assert.equal((await response.json()).reason, 'csrf')
  })

  it('rejects a mutation from a foreign origin', async () => {
    const response = await mutate(
      `/api/document/${documentId}/comment`,
      { sectionKey: 'scope', documentHash: 'x', body: 'cross site' },
      { origin: 'https://evil.example.com' }
    )

    assert.equal(response.status, 403)
    assert.equal((await response.json()).reason, 'origin')
  })

  it('rejects a mutation with a rebound Host header', async () => {
    const response = await rawRequest({
      port: fixture.server.address.port,
      path: `/api/document/${documentId}/comment`,
      headers: {
        host: 'attacker.example.com',
        cookie,
        origin: fixture.server.origin,
        'content-type': 'application/json',
        'x-csrf-token': csrfToken
      },
      body: JSON.stringify({ sectionKey: 'scope', documentHash: 'x', body: 'dns rebinding' })
    })

    assert.equal(response.status, 403)
    assert.equal(JSON.parse(response.text).reason, 'host')
  })

  it('rejects a mutation without a session cookie', async () => {
    const response = await fetch(`${fixture.server.origin}/api/document/${documentId}/comment`, {
      method: 'POST',
      headers: {
        origin: fixture.server.origin,
        'content-type': 'application/json',
        'x-csrf-token': csrfToken
      },
      body: JSON.stringify({ sectionKey: 'scope', documentHash: 'x', body: 'no cookie' })
    })

    assert.equal(response.status, 403)
    assert.equal((await response.json()).reason, 'session')
  })

  it('rejects an oversized body', async () => {
    const response = await mutate(`/api/document/${documentId}/comment`, {
      sectionKey: 'scope',
      documentHash: 'x',
      body: 'x'.repeat(MAX_BODY_BYTES + 1024)
    })

    assert.equal(response.status, 413)
  })

  it('exposes no shell, fetch or write endpoint', async () => {
    for (const path of ['/api/exec', '/api/fetch', '/api/files', '/api/open', '/api/decision']) {
      const response = await mutate(path, { any: 'thing' })

      assert.equal(response.status, 404, `expected 404 for ${path}`)
    }
  })

  it('records a verdict and reports it as feedback rather than sign-off', async () => {
    const document = await (await fetch(`${fixture.server.origin}/api/document/${documentId}`, {
      headers: { cookie }
    })).json()

    const response = await mutate(`/api/document/${documentId}/verdict`, {
      verdict: 'approved',
      documentHash: document.revision.hash,
      note: 'Reads well.'
    })
    const payload = await response.json()

    assert.equal(response.status, 201)
    assert.equal(payload.verdict.authority, 'local-http-feedback')

    const reloaded = await (await fetch(`${fixture.server.origin}/api/document/${documentId}`, {
      headers: { cookie }
    })).json()

    assert.equal(reloaded.verdict.state, 'current')
    assert.equal(reloaded.approvalAuthority, 'chat-sign-off-required')
  })

  it('invalidates the approval once the document changes on disk', async () => {
    writeFileSync(fixture.documentPath, `${documentBody}\n## Added later\n\nNew content.\n`, 'utf8')

    const reloaded = await (await fetch(`${fixture.server.origin}/api/document/${documentId}`, {
      headers: { cookie }
    })).json()

    assert.equal(reloaded.verdict.state, 'stale')
    assert.equal(reloaded.verdict.verdict, 'approved')
    assert.deepEqual(reloaded.sections.map((section) => section.key).slice(-1), ['added-later'])
  })

  it('keeps a comment whose section changed anchored to that section as revised', async () => {
    writeFileSync(
      fixture.documentPath,
      documentBody.replace('In scope.', 'In scope, materially revised.'),
      'utf8'
    )

    const reloaded = await (await fetch(`${fixture.server.origin}/api/document/${documentId}`, {
      headers: { cookie }
    })).json()
    const comment = reloaded.comments.find((candidate) => candidate.sectionKey === 'scope')

    assert.equal(comment.state, 'revised')
    assert.equal(comment.anchorKey, 'scope')
  })

  it('orphans a comment whose section was removed instead of reattaching it', async () => {
    writeFileSync(fixture.documentPath, '# Sample concept\n\nEverything else was deleted.\n', 'utf8')

    const reloaded = await (await fetch(`${fixture.server.origin}/api/document/${documentId}`, {
      headers: { cookie }
    })).json()
    const comment = reloaded.comments.find((candidate) => candidate.sectionKey === 'scope')

    assert.equal(comment.state, 'orphaned')
    assert.equal(comment.anchorKey, null)
    assert.equal(reloaded.orphanedComments, 1)

    writeFileSync(fixture.documentPath, documentBody, 'utf8')
  })

  it('reports a document that disappeared instead of failing opaquely', async () => {
    const gone = await launch()
    const goneId = (await (await fetch(`${gone.server.origin}/api/session`, {
      headers: { cookie: await bootstrapCookie(gone.server) }
    })).json()).documents[0].id

    const { rmSync } = await import('node:fs')
    rmSync(gone.documentPath)

    const response = await fetch(`${gone.server.origin}/api/document/${goneId}`, {
      headers: { cookie: await bootstrapCookie(gone.server) }
    })

    assert.equal(response.status, 410)
    assert.equal((await response.json()).state, 'unavailable')

    await gone.server.close()
  })
})

async function bootstrapCookie (server) {
  const bootstrap = await fetch(`${server.origin}/?s=${server.sessionKey}`, { redirect: 'manual' })
  return bootstrap.headers.getSetCookie()[0].split(';')[0]
}

describe('server session isolation', () => {
  it('refuses a session cookie minted by a previous server launch', async () => {
    const first = await launch()
    const firstCookie = await bootstrapCookie(first.server)
    await first.server.close()

    const second = await launch({ stateRoot: first.stateRoot })
    const response = await fetch(`${second.server.origin}/api/session`, { headers: { cookie: firstCookie } })

    assert.equal(response.status, 401)

    await second.server.close()
  })

  it('does not resurrect an old session from persisted feedback', async () => {
    const first = await launch()
    const firstCookie = await bootstrapCookie(first.server)
    const firstSession = await (await fetch(`${first.server.origin}/api/session`, {
      headers: { cookie: firstCookie }
    })).json()

    await fetch(`${first.server.origin}/api/document/${firstSession.documents[0].id}/verdict`, {
      method: 'POST',
      headers: {
        cookie: firstCookie,
        origin: first.server.origin,
        'content-type': 'application/json',
        'x-csrf-token': firstSession.csrfToken
      },
      body: JSON.stringify({ verdict: 'approved', documentHash: 'a'.repeat(64) })
    })
    await first.server.close()

    const second = await launch({ stateRoot: first.stateRoot })
    const replay = await fetch(`${second.server.origin}/api/session`, {
      headers: { cookie: firstCookie, 'x-csrf-token': firstSession.csrfToken }
    })

    assert.equal(replay.status, 401)

    await second.server.close()
  })
})

describe('server lifecycle', () => {
  it('stops on the explicit shutdown endpoint', async () => {
    const fixture = await launch()
    const origin = fixture.server.origin
    const cookie = await bootstrapCookie(fixture.server)
    const session = await (await fetch(`${origin}/api/session`, { headers: { cookie } })).json()

    const response = await fetch(`${origin}/api/shutdown`, {
      method: 'POST',
      headers: {
        cookie,
        origin,
        'content-type': 'application/json',
        'x-csrf-token': session.csrfToken
      },
      body: '{}'
    })

    assert.equal(response.status, 202)
    await fixture.server.stopped

    await assert.rejects(() => fetch(`${origin}/api/session`, { headers: { cookie } }))
  })

  it('expires on its own after the bounded lifetime', async () => {
    const fixture = await launch({ ttlSeconds: 1 })
    const origin = fixture.server.origin

    await fixture.server.stopped

    await assert.rejects(() => fetch(`${origin}/api/session`))
  })

  it('refuses a non-loopback bind address', () => {
    assert.throws(
      () => createReviewServer({ documents: [], stateRoot: tmpdir(), host: '0.0.0.0' }),
      /loopback/i
    )
  })

  it('refuses a lifetime beyond the hard maximum', () => {
    assert.throws(
      () => createReviewServer({ documents: [], stateRoot: tmpdir(), ttlSeconds: 999999 }),
      /lifetime/i
    )
  })
})
