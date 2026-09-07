import { createServer } from 'node:http'
import { createReadStream, existsSync, readFileSync } from 'node:fs'
import { createRequire } from 'node:module'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

import { DocumentRejection, loadDocument, loadDocumentSync } from './document.mjs'
import { buildIconSprite } from './icons.mjs'
import { PathRejection } from './paths.mjs'
import { createRenderer } from './render.mjs'
import {
  BodyRejection,
  MAX_BODY_BYTES,
  SESSION_COOKIE_NAME,
  checkFetchMetadata,
  checkHost,
  checkSession,
  constantTimeEqual,
  createSecret,
  guardMutation,
  isLoopbackAddress,
  readJsonBody
} from './security.mjs'
import { StoreRejection, classifyComment, classifyVerdict, createStore } from './store.mjs'

const here = dirname(fileURLToPath(import.meta.url))
const require = createRequire(import.meta.url)

export const DEFAULT_TTL_SECONDS = 1800
export const MAX_TTL_SECONDS = 14400
const DOCUMENT_ID_PATTERN = /^[0-9a-f]{16}$/

const CONTENT_SECURITY_POLICY = [
  "default-src 'none'",
  "script-src 'self'",
  // Mermaid injects a <style> element into the SVG it generates. Scripts stay
  // strict, so this does not yield execution.
  "style-src 'self' 'unsafe-inline'",
  "img-src 'self'",
  "font-src 'self'",
  "connect-src 'self'",
  "base-uri 'none'",
  "form-action 'none'",
  "frame-ancestors 'none'"
].join('; ')

function vendorFile (specifier) {
  try {
    return require.resolve(specifier)
  } catch {
    return null
  }
}

function buildStaticMap () {
  const map = new Map([
    ['/app.css', { path: join(here, '..', 'assets', 'app.css'), type: 'text/css; charset=utf-8' }],
    ['/app.mjs', { path: join(here, '..', 'assets', 'app.mjs'), type: 'text/javascript; charset=utf-8' }],
    ['/brand.png', { path: join(here, '..', '..', '..', 'assets', 'CA-glyph-on-light.png'), type: 'image/png' }]
  ])

  const mermaid = vendorFile('mermaid/dist/mermaid.min.js')
  const purify = vendorFile('dompurify/dist/purify.min.js')

  if (mermaid) {
    map.set('/vendor/mermaid.min.js', { path: mermaid, type: 'text/javascript; charset=utf-8' })
  }

  if (purify) {
    map.set('/vendor/purify.min.js', { path: purify, type: 'text/javascript; charset=utf-8' })
  }

  for (const [route, entry] of [...map]) {
    if (!existsSync(entry.path)) {
      map.delete(route)
    }
  }

  return map
}

function securityHeaders (extra = {}) {
  return {
    'content-security-policy': CONTENT_SECURITY_POLICY,
    'x-content-type-options': 'nosniff',
    'referrer-policy': 'no-referrer',
    'cross-origin-resource-policy': 'same-origin',
    'cross-origin-opener-policy': 'same-origin',
    'cache-control': 'no-store',
    ...extra
  }
}

function sendJson (response, status, payload) {
  const body = JSON.stringify(payload)
  response.writeHead(status, securityHeaders({
    'content-type': 'application/json; charset=utf-8',
    'content-length': Buffer.byteLength(body)
  }))
  response.end(body)
}

function sendText (response, status, contentType, body) {
  response.writeHead(status, securityHeaders({
    'content-type': contentType,
    'content-length': Buffer.byteLength(body)
  }))
  response.end(body)
}

export function createReviewServer ({
  documents = [],
  stateRoot,
  host = '127.0.0.1',
  port = 0,
  ttlSeconds = DEFAULT_TTL_SECONDS,
  maxDocumentBytes
} = {}) {
  if (!isLoopbackAddress(host)) {
    throw new Error(`the review server must bind to a loopback address, not "${host}"`)
  }

  if (!Number.isFinite(ttlSeconds) || ttlSeconds <= 0 || ttlSeconds > MAX_TTL_SECONDS) {
    throw new Error(`server lifetime must be between 1 and ${MAX_TTL_SECONDS} seconds`)
  }

  const store = createStore({ stateRoot })
  const renderer = createRenderer()
  const staticMap = buildStaticMap()
  const iconSprite = buildIconSprite()

  const sessionSecret = createSecret()
  const csrfToken = createSecret()
  const serverId = createSecret(8)
  const startedAt = new Date()

  // Authorization happens here, at launch. Nothing a request carries can widen
  // this set, because the wire protocol never names a path.
  const registry = new Map()

  for (const descriptor of documents) {
    const loaded = descriptorIdentity(descriptor, maxDocumentBytes)
    registry.set(loaded.id, loaded)
  }

  const sockets = new Set()
  let resolveStopped
  const stopped = new Promise((resolve) => { resolveStopped = resolve })
  let closing = false

  const httpServer = createServer(handleRequest)

  httpServer.on('connection', (socket) => {
    sockets.add(socket)
    socket.on('close', () => sockets.delete(socket))
  })

  const expiresAt = new Date(startedAt.getTime() + ttlSeconds * 1000)
  let ttlTimer = null

  function authority () {
    const address = httpServer.address()
    return `127.0.0.1:${address.port}`
  }

  function allowedAuthorities () {
    const address = httpServer.address()
    return [`127.0.0.1:${address.port}`, `localhost:${address.port}`]
  }

  function allowedOrigins () {
    return allowedAuthorities().map((value) => `http://${value}`)
  }

  function guardContext () {
    return {
      authorities: allowedAuthorities(),
      origins: allowedOrigins(),
      sessionSecret,
      csrfToken
    }
  }

  async function handleRequest (request, response) {
    try {
      await route(request, response)
    } catch (error) {
      if (!response.headersSent) {
        sendJson(response, 500, { error: 'internal error', reason: 'internal' })
      } else {
        response.end()
      }

      process.emitWarning(`plan-review request failed: ${error.message}`)
    }
  }

  async function route (request, response) {
    const url = new URL(request.url, `http://${authority()}`)
    const path = url.pathname

    const hostCheck = checkHost(request.headers, allowedAuthorities())

    if (!hostCheck.ok) {
      return sendJson(response, 403, { error: 'rejected', reason: hostCheck.reason })
    }

    const fetchCheck = checkFetchMetadata(request.headers)

    if (!fetchCheck.ok) {
      return sendJson(response, 403, { error: 'rejected', reason: fetchCheck.reason })
    }

    if (request.method === 'GET' && path === '/') {
      return serveShell(request, response, url)
    }

    if (request.method === 'GET' && path === '/icons.svg') {
      if (!checkSession(request.headers, sessionSecret).ok) {
        return sendJson(response, 401, { error: 'no session', reason: 'session' })
      }

      return sendText(response, 200, 'image/svg+xml; charset=utf-8', iconSprite)
    }

    if (request.method === 'GET' && staticMap.has(path)) {
      if (!checkSession(request.headers, sessionSecret).ok) {
        return sendJson(response, 401, { error: 'no session', reason: 'session' })
      }

      return serveStatic(response, staticMap.get(path))
    }

    if (request.method === 'GET' && path === '/api/session') {
      if (!checkSession(request.headers, sessionSecret).ok) {
        return sendJson(response, 401, { error: 'no session', reason: 'session' })
      }

      return sendJson(response, 200, {
        csrfToken,
        serverId,
        startedAt: startedAt.toISOString(),
        expiresAt: expiresAt.toISOString(),
        ttlSeconds,
        approvalAuthority: 'chat-sign-off-required',
        documents: [...registry.values()].map((entry) => ({
          id: entry.id,
          name: entry.name,
          title: entry.title
        }))
      })
    }

    const documentMatch = /^\/api\/document\/([^/]+)(?:\/(comment|verdict))?$/.exec(path)

    if (documentMatch) {
      return routeDocument(request, response, documentMatch[1], documentMatch[2])
    }

    if (request.method === 'POST' && path === '/api/shutdown') {
      const guard = guardMutation(request.headers, guardContext())

      if (!guard.ok) {
        return sendJson(response, 403, { error: 'rejected', reason: guard.reason })
      }

      sendJson(response, 202, { state: 'stopping' })
      setTimeout(() => { close() }, 25).unref()
      return undefined
    }

    return sendJson(response, 404, { error: 'not found', reason: 'unknown-route' })
  }

  function serveShell (request, response, url) {
    const bootstrap = url.searchParams.get('s')

    if (bootstrap !== null) {
      if (!constantTimeEqual(bootstrap, sessionSecret)) {
        return sendText(response, 401, 'text/plain; charset=utf-8', 'Invalid session key.\n')
      }

      response.writeHead(302, securityHeaders({
        location: '/',
        'set-cookie': `${SESSION_COOKIE_NAME}=${sessionSecret}; HttpOnly; SameSite=Strict; Path=/; Max-Age=${ttlSeconds}`
      }))
      return response.end()
    }

    if (!checkSession(request.headers, sessionSecret).ok) {
      return sendText(
        response,
        401,
        'text/html; charset=utf-8',
        '<!doctype html><meta charset="utf-8"><title>Plan review</title>' +
        '<p>No review session. Open the URL printed by the launcher, which carries the per-launch session key.</p>'
      )
    }

    const shell = readFileSync(join(here, '..', 'assets', 'app.html'), 'utf8')
    return sendText(response, 200, 'text/html; charset=utf-8', shell)
  }

  function serveStatic (response, entry) {
    response.writeHead(200, securityHeaders({ 'content-type': entry.type }))
    createReadStream(entry.path).pipe(response)
  }

  async function routeDocument (request, response, documentId, action) {
    if (!DOCUMENT_ID_PATTERN.test(documentId)) {
      return sendJson(response, 400, { error: 'bad document identifier', reason: 'invalid-document-id' })
    }

    const entry = registry.get(documentId)

    if (!entry) {
      return sendJson(response, 404, { error: 'not an opened document', reason: 'unknown-document' })
    }

    if (request.method === 'GET' && action === undefined) {
      if (!checkSession(request.headers, sessionSecret).ok) {
        return sendJson(response, 401, { error: 'no session', reason: 'session' })
      }

      return serveDocument(response, entry)
    }

    if (request.method !== 'POST' || action === undefined) {
      return sendJson(response, 405, { error: 'method not allowed', reason: 'method' })
    }

    const guard = guardMutation(request.headers, guardContext())

    if (!guard.ok) {
      return sendJson(response, 403, { error: 'rejected', reason: guard.reason })
    }

    let body
    try {
      body = await readJsonBody(request, request.headers, { limit: MAX_BODY_BYTES })
    } catch (error) {
      if (error instanceof BodyRejection) {
        return sendJson(
          response,
          error.reason === 'too-large' ? 413 : 400,
          { error: error.message, reason: error.reason }
        )
      }

      throw error
    }

    let document
    try {
      document = await loadDocument({ root: entry.root, path: entry.path, maxBytes: maxDocumentBytes })
    } catch (error) {
      return sendUnavailable(response, error)
    }

    if (body.documentHash !== document.revision.hash) {
      return sendJson(response, 409, {
        error: 'the document changed since this view was rendered',
        reason: 'stale',
        state: 'stale',
        revision: document.revision.hash
      })
    }

    try {
      if (action === 'comment') {
        const section = document.sections.find((candidate) => candidate.key === body.sectionKey)

        if (!section) {
          return sendJson(response, 409, {
            error: 'that section is no longer present',
            reason: 'unknown-section',
            state: 'unknown-section'
          })
        }

        const result = await store.addComment(documentId, {
          sectionKey: section.key,
          sectionHash: section.hash,
          headingText: section.heading,
          ambiguousHeading: document.sections.filter((candidate) => candidate.heading === section.heading).length > 1,
          documentHash: document.revision.hash,
          body: body.body
        })

        return sendJson(response, 201, result)
      }

      const result = await store.setVerdict(documentId, {
        verdict: body.verdict,
        documentHash: document.revision.hash,
        note: body.note
      })

      return sendJson(response, 201, {
        ...result,
        // Said on every response so a caller cannot read this as sign-off.
        approvalAuthority: 'chat-sign-off-required'
      })
    } catch (error) {
      if (error instanceof StoreRejection) {
        return sendJson(response, error.reason === 'comment-limit' ? 409 : 400, {
          error: error.message,
          reason: error.reason
        })
      }

      throw error
    }
  }

  function sendUnavailable (response, error) {
    if (error instanceof PathRejection || error instanceof DocumentRejection) {
      return sendJson(response, 410, {
        error: 'the document is no longer readable',
        reason: error.reason,
        state: 'unavailable'
      })
    }

    throw error
  }

  async function serveDocument (response, entry) {
    let document
    try {
      document = await loadDocument({ root: entry.root, path: entry.path, maxBytes: maxDocumentBytes })
    } catch (error) {
      return sendUnavailable(response, error)
    }

    const record = await store.read(entry.id)
    const comments = record.comments.map((comment) => classifyComment(comment, document.sections))

    const sections = document.sections.map((section) => {
      const rendered = renderer.render(section.body)

      return {
        key: section.key,
        heading: section.heading,
        level: section.level,
        hash: section.hash,
        html: rendered.html,
        diagrams: rendered.diagrams
      }
    })

    return sendJson(response, 200, {
      id: document.id,
      name: document.name,
      title: document.title,
      revision: document.revision,
      sections,
      comments,
      orphanedComments: comments.filter((comment) => comment.state === 'orphaned').length,
      verdict: classifyVerdict(record.verdict, document.revision.hash),
      approvalAuthority: 'chat-sign-off-required',
      storeRecovered: record.recovered === true
    })
  }

  function close () {
    if (closing) {
      return stopped
    }

    closing = true

    if (ttlTimer) {
      clearTimeout(ttlTimer)
    }

    httpServer.close(() => resolveStopped())

    for (const socket of sockets) {
      socket.destroy()
    }

    return stopped
  }

  return {
    stopped,
    sessionKey: sessionSecret,
    serverId,
    expiresAt,
    ttlSeconds,
    documents: [...registry.values()].map((entry) => ({ id: entry.id, name: entry.name })),

    get address () {
      return httpServer.address()
    },

    get origin () {
      return `http://127.0.0.1:${httpServer.address().port}`
    },

    get url () {
      return `http://127.0.0.1:${httpServer.address().port}/?s=${sessionSecret}`
    },

    listen () {
      return new Promise((resolve, reject) => {
        httpServer.once('error', reject)
        httpServer.listen(port, host, () => {
          ttlTimer = setTimeout(() => { close() }, ttlSeconds * 1000)
          resolve()
        })
      })
    },

    close
  }
}

function descriptorIdentity (descriptor, maxBytes) {
  const document = loadDocumentSync({ root: descriptor.root, path: descriptor.path, maxBytes })

  return {
    id: document.id,
    root: document.root,
    path: document.path,
    name: document.name,
    title: document.title
  }
}
