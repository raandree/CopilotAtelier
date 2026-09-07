import assert from 'node:assert/strict'
import { copyFileSync, mkdirSync, mkdtempSync, rmSync, rmdirSync, writeFileSync } from 'node:fs'
import { request as httpRequest } from 'node:http'
import { tmpdir } from 'node:os'
import { dirname, join } from 'node:path'
import { setTimeout as delay } from 'node:timers/promises'
import { fileURLToPath } from 'node:url'
import { describe, it } from 'node:test'

import { SESSION_COOKIE_PREFIX } from '../../src/security.mjs'
import { createReviewServer } from '../../src/server.mjs'

const here = dirname(fileURLToPath(import.meta.url))
const shippedAssets = join(here, '..', '..', 'assets')

const documentBody = [
  '# Sample concept',
  '',
  'Preamble text.',
  '',
  '## Scope',
  '',
  'In scope.',
  ''
].join('\n')

function makeWorkspace () {
  const root = mkdtempSync(join(tmpdir(), 'plan-review-boundary-'))
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

async function bootstrapCookie (server) {
  const bootstrap = await fetch(`${server.origin}/?s=${server.sessionKey}`, { redirect: 'manual' })
  return bootstrap.headers.getSetCookie()[0].split(';')[0]
}

async function openSession (server) {
  const cookie = await bootstrapCookie(server)
  const payload = await (await fetch(`${server.origin}/api/session`, { headers: { cookie } })).json()

  return { cookie, csrfToken: payload.csrfToken, documentId: payload.documents[0].id }
}

function rawRequest ({ host, port, path, method = 'GET', headers = {}, body = '' }) {
  return new Promise((resolve, reject) => {
    const request = httpRequest({ host, port, path, method, headers, setHost: false }, (response) => {
      const chunks = []
      response.on('data', (chunk) => chunks.push(chunk))
      response.on('end', () => resolve({
        status: response.statusCode,
        text: Buffer.concat(chunks).toString('utf8')
      }))
    })

    request.on('error', reject)
    request.end(body)
  })
}

describe('per-server session isolation', () => {
  it('gives each launch its own cookie namespace so two servers coexist in one browser', async () => {
    const first = await launch()
    const second = await launch()

    const firstCookie = await bootstrapCookie(first.server)
    const secondCookie = await bootstrapCookie(second.server)
    const firstName = firstCookie.split('=')[0]
    const secondName = secondCookie.split('=')[0]

    assert.ok(firstName.startsWith(SESSION_COOKIE_PREFIX))
    assert.notEqual(firstName, secondName, 'a second launch must not overwrite the first cookie')

    // A browser on 127.0.0.1 sends every cookie it holds for the host, because
    // cookies are not port scoped.
    const both = `${firstCookie}; ${secondCookie}`

    assert.equal((await fetch(`${first.server.origin}/api/session`, { headers: { cookie: both } })).status, 200)
    assert.equal((await fetch(`${second.server.origin}/api/session`, { headers: { cookie: both } })).status, 200)

    assert.equal(
      (await fetch(`${first.server.origin}/api/session`, { headers: { cookie: secondCookie } })).status,
      401,
      'another launch cookie must not authorize this server'
    )

    await first.server.close()
    await second.server.close()
  })
})

describe('loopback authority', () => {
  it('uses the bracketed IPv6 authority when bound to ::1', async () => {
    let fixture
    try {
      fixture = await launch({ host: '::1' })
    } catch (error) {
      if (error.code === 'EADDRNOTAVAIL' || error.code === 'EAFNOSUPPORT') {
        return
      }

      throw error
    }

    const port = fixture.server.address.port

    assert.equal(fixture.server.origin, `http://[::1]:${port}`)
    assert.match(fixture.server.url, /^http:\/\/\[::1\]:\d+\/\?s=[0-9a-f]{64}$/)

    const session = await openSession(fixture.server)
    assert.match(session.documentId, /^[0-9a-f]{16}$/)

    const rebound = await rawRequest({
      host: '::1',
      port,
      path: '/api/session',
      headers: { host: `127.0.0.1:${port}`, cookie: session.cookie }
    })

    assert.equal(rebound.status, 403, 'an authority the server does not own must be refused')
    assert.equal(JSON.parse(rebound.text).reason, 'host')

    await fixture.server.close()
  })
})

describe('application asset isolation', () => {
  function makeAssetRoot ({ omit = [] } = {}) {
    const assetRoot = mkdtempSync(join(tmpdir(), 'plan-review-assets-'))

    for (const name of ['app.html', 'app.css', 'app.mjs']) {
      if (!omit.includes(name)) {
        copyFileSync(join(shippedAssets, name), join(assetRoot, name))
      }
    }

    return assetRoot
  }

  it('serves an application asset from the launch snapshot after it changes on disk', async () => {
    const assetRoot = makeAssetRoot()
    const fixture = await launch({ assetRoot })
    const cookie = await bootstrapCookie(fixture.server)

    const before = await fetch(`${fixture.server.origin}/app.css`, { headers: { cookie } })
    const originalCss = await before.text()
    assert.equal(before.status, 200)

    rmSync(join(assetRoot, 'app.css'))
    writeFileSync(join(assetRoot, 'app.mjs'), 'throw new Error("swapped")', 'utf8')

    const after = await fetch(`${fixture.server.origin}/app.css`, { headers: { cookie } })
    assert.equal(after.status, 200)
    assert.equal(await after.text(), originalCss)

    const script = await fetch(`${fixture.server.origin}/app.mjs`, { headers: { cookie } })
    assert.equal(script.status, 200)
    assert.ok(!(await script.text()).includes('swapped'))

    assert.equal((await fetch(`${fixture.server.origin}/api/session`, { headers: { cookie } })).status, 200)

    await fixture.server.close()
  })

  it('starts without an absent asset and answers 404 rather than hanging', async () => {
    const assetRoot = makeAssetRoot({ omit: ['app.css'] })
    const fixture = await launch({ assetRoot })
    const cookie = await bootstrapCookie(fixture.server)

    const missing = await fetch(`${fixture.server.origin}/app.css`, { headers: { cookie } })
    assert.equal(missing.status, 404)

    assert.equal((await fetch(`${fixture.server.origin}/`, { headers: { cookie } })).status, 200)
    assert.equal((await fetch(`${fixture.server.origin}/api/session`, { headers: { cookie } })).status, 200)

    await fixture.server.close()
  })

  it('reports an unreadable shell instead of crashing the server', async () => {
    const assetRoot = makeAssetRoot({ omit: ['app.html'] })
    const fixture = await launch({ assetRoot })
    const cookie = await bootstrapCookie(fixture.server)

    const shell = await fetch(`${fixture.server.origin}/`, { headers: { cookie } })
    assert.equal(shell.status, 503)

    assert.equal((await fetch(`${fixture.server.origin}/api/session`, { headers: { cookie } })).status, 200)

    await fixture.server.close()
  })
})

describe('source revision at the serialized mutation', () => {
  it('reports stale when the source changes while the mutation waits for the store lock', async () => {
    const fixture = await launch()
    const { cookie, csrfToken, documentId } = await openSession(fixture.server)
    const document = await (await fetch(`${fixture.server.origin}/api/document/${documentId}`, {
      headers: { cookie }
    })).json()

    mkdirSync(fixture.stateRoot, { recursive: true })
    const lockPath = join(fixture.stateRoot, `${documentId}.lock`)
    mkdirSync(lockPath)
    const ownerPath = join(lockPath, 'owner.json')
    writeFileSync(
      ownerPath,
      JSON.stringify({ pid: process.pid, token: 'e'.repeat(16), createdAt: new Date().toISOString() }),
      'utf8'
    )

    const pending = fetch(`${fixture.server.origin}/api/document/${documentId}/verdict`, {
      method: 'POST',
      headers: {
        cookie,
        origin: fixture.server.origin,
        'content-type': 'application/json',
        'x-csrf-token': csrfToken
      },
      body: JSON.stringify({ verdict: 'approved', documentHash: document.revision.hash })
    })

    // The pre-lock revision check has already passed by now; the request is
    // queued behind the lock this test holds.
    await delay(250)
    writeFileSync(fixture.documentPath, `${documentBody}\n## Added while the lock was held\n\nNew text.\n`, 'utf8')
    rmSync(ownerPath)
    rmdirSync(lockPath)

    const response = await pending
    const payload = await response.json()

    assert.equal(response.status, 409)
    assert.equal(payload.state, 'stale')

    const reloaded = await (await fetch(`${fixture.server.origin}/api/document/${documentId}`, {
      headers: { cookie }
    })).json()

    assert.equal(reloaded.verdict.state, 'none', 'no approval may be recorded for the superseded revision')

    await fixture.server.close()
  })

  it('reports the revision the mutation actually committed against', async () => {
    const fixture = await launch()
    const { cookie, csrfToken, documentId } = await openSession(fixture.server)
    const document = await (await fetch(`${fixture.server.origin}/api/document/${documentId}`, {
      headers: { cookie }
    })).json()

    const response = await fetch(`${fixture.server.origin}/api/document/${documentId}/verdict`, {
      method: 'POST',
      headers: {
        cookie,
        origin: fixture.server.origin,
        'content-type': 'application/json',
        'x-csrf-token': csrfToken
      },
      body: JSON.stringify({ verdict: 'approved', documentHash: document.revision.hash })
    })
    const payload = await response.json()

    assert.equal(response.status, 201)
    assert.equal(payload.state, 'recorded')
    assert.equal(payload.revision, document.revision.hash)
    assert.equal(payload.approvalAuthority, 'chat-sign-off-required')

    await fixture.server.close()
  })
})
