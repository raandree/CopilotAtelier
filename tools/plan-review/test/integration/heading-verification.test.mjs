import assert from 'node:assert/strict'
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, rmdirSync, writeFileSync } from 'node:fs'
import { createRequire, syncBuiltinESMExports } from 'node:module'
import { tmpdir } from 'node:os'
import { join, resolve } from 'node:path'
import { after, describe, it } from 'node:test'

import { hashContent } from '../../src/document.mjs'
import { createReviewServer } from '../../src/server.mjs'

const CLEAN = ['# Purpose', '', 'Body.', '', '## Risks', '', 'Risk body.', ''].join('\n')

const NESTED_BLOCKQUOTE = ['# Purpose', '', 'Body.', '', '> ## Quoted risk', '>', '> Quoted body.', ''].join('\n')

const NESTED_LIST = ['# Purpose', '', 'Body.', '', '- # Heading in a list item', '', 'Body.', ''].join('\n')

const AMBIGUOUS_RULE = [
  '# Purpose',
  '',
  '| Quality | Meter |',
  '|---|---|',
  '| Freshness | Status file |',
  '---',
  '',
  'Body.',
  ''
].join('\n')

const unsupported = {
  'a blockquote': NESTED_BLOCKQUOTE,
  'a list item': NESTED_LIST,
  'an ambiguous rule after a table': AMBIGUOUS_RULE
}

const disposable = []

function workspace (markdown) {
  const root = mkdtempSync(join(tmpdir(), 'plan-review-headings-'))
  disposable.push(root)

  const documentPath = join(root, 'concept.md')
  writeFileSync(documentPath, markdown, 'utf8')

  return { root, documentPath, stateRoot: join(root, '.state') }
}

async function launch (markdown) {
  const fixture = workspace(markdown)
  const server = createReviewServer({
    documents: [{ root: fixture.root, path: fixture.documentPath }],
    stateRoot: fixture.stateRoot,
    ttlSeconds: 120
  })

  await server.listen()

  const bootstrap = await fetch(`${server.origin}/?s=${server.sessionKey}`, {
    redirect: 'manual',
    signal: AbortSignal.timeout(5000)
  })
  const cookie = bootstrap.headers.getSetCookie()[0].split(';')[0]

  const session = await fetch(`${server.origin}/api/session`, {
    headers: { cookie },
    signal: AbortSignal.timeout(5000)
  })
  const payload = await session.json()

  return { ...fixture, server, cookie, csrfToken: payload.csrfToken, documentId: payload.documents[0].id }
}

function mutate (context, action, body) {
  return fetch(`${context.server.origin}/api/document/${context.documentId}/${action}`, {
    method: 'POST',
    redirect: 'manual',
    headers: {
      cookie: context.cookie,
      origin: context.server.origin,
      'content-type': 'application/json',
      'x-csrf-token': context.csrfToken
    },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(10000)
  })
}

function currentHash (context) {
  return hashContent(readFileSync(context.documentPath))
}

function storeRecordExists (context) {
  return existsSync(join(context.stateRoot, `${context.documentId}.json`))
}

async function within (promise, timeoutMs, message) {
  let timer
  const expiry = new Promise((_, reject) => {
    timer = setTimeout(() => reject(new Error(message)), timeoutMs)
  })

  try {
    return await Promise.race([promise, expiry])
  } finally {
    clearTimeout(timer)
  }
}

describe('heading agreement at the document boundary', () => {
  after(() => {
    for (const root of disposable.splice(0)) {
      rmSync(root, { recursive: true, force: true })
    }
  })

  it('refuses to authorize a document whose headings sit inside a blockquote', () => {
    const fixture = workspace(NESTED_BLOCKQUOTE)

    assert.throws(
      () => createReviewServer({
        documents: [{ root: fixture.root, path: fixture.documentPath }],
        stateRoot: fixture.stateRoot,
        ttlSeconds: 120
      }),
      (error) => error.name === 'DocumentRejection' && error.reason === 'heading-structure'
    )
  })

  for (const [name, markdown] of Object.entries(unsupported)) {
    it(`refuses a subsequent read once a heading moves into ${name}`, async () => {
      const context = await launch(CLEAN)

      try {
        writeFileSync(context.documentPath, markdown, 'utf8')

        const response = await fetch(`${context.server.origin}/api/document/${context.documentId}`, {
          headers: { cookie: context.cookie },
          signal: AbortSignal.timeout(5000)
        })

        assert.equal(response.status, 410)
        assert.equal((await response.json()).reason, 'heading-structure')
      } finally {
        await context.server.close()
      }
    })

    it(`refuses a comment without writing state once a heading moves into ${name}`, async () => {
      const context = await launch(CLEAN)

      try {
        writeFileSync(context.documentPath, markdown, 'utf8')

        // The hash is the one the mutated file really has, so the stale check
        // cannot be what refuses the write.
        const response = await mutate(context, 'comment', {
          sectionKey: 'purpose',
          documentHash: currentHash(context),
          body: 'Feedback that must not be recorded.'
        })

        assert.equal(response.status, 410)
        assert.equal((await response.json()).reason, 'heading-structure')
        assert.equal(storeRecordExists(context), false, 'a refused document must not produce a store record')
      } finally {
        await context.server.close()
      }
    })

    it(`refuses a verdict without writing state once a heading moves into ${name}`, async () => {
      const context = await launch(CLEAN)

      try {
        writeFileSync(context.documentPath, markdown, 'utf8')

        const response = await mutate(context, 'verdict', {
          verdict: 'approved',
          documentHash: currentHash(context),
          note: 'Approval that must not be recorded.'
        })

        assert.equal(response.status, 410)
        assert.equal((await response.json()).reason, 'heading-structure')
        assert.equal(storeRecordExists(context), false, 'a refused document must not produce a store record')
      } finally {
        await context.server.close()
      }
    })
  }

  it('refuses a comment whose document became unsupported while the mutation waited for the lock', async () => {
    const context = await launch(CLEAN)
    const held = join(context.stateRoot, `${context.documentId}.lock`)
    const heldPath = resolve(held)
    const fs = createRequire(import.meta.url)('node:fs')
    const originalMkdirSync = fs.mkdirSync

    let observeAcquisition
    const acquisitionAttempted = new Promise((settle) => { observeAcquisition = settle })

    try {
      mkdirSync(context.stateRoot, { recursive: true })
      mkdirSync(held)
      writeFileSync(
        join(held, 'owner.json'),
        JSON.stringify({ pid: process.pid, token: 'f'.repeat(16), createdAt: new Date().toISOString() }),
        'utf8'
      )

      fs.mkdirSync = function (target, options) {
        if (typeof target === 'string' && resolve(target) === heldPath) {
          observeAcquisition()
        }

        return originalMkdirSync.call(this, target, options)
      }
      syncBuiltinESMExports()

      const pending = mutate(context, 'comment', {
        sectionKey: 'risks',
        documentHash: hashContent(CLEAN),
        body: 'Feedback that must not survive the swap.'
      })
      // The readiness guard below can fail before this is awaited.
      pending.catch(() => {})

      // Readiness is the queued request reaching for the lock this test holds,
      // which it can only do once the pre-lock read has accepted the clean
      // document. Elapsed time would let a slow schedule pass this test on the
      // pre-lock refusal instead of the in-lock one it exists to protect.
      await within(acquisitionAttempted, 5000, 'the queued mutation never reached for the held lock')

      writeFileSync(context.documentPath, NESTED_BLOCKQUOTE, 'utf8')
      rmSync(join(held, 'owner.json'))
      rmdirSync(held)

      const response = await pending

      assert.equal(response.status, 410, 'an unsupported document must not be answered as an internal error')
      assert.equal((await response.json()).reason, 'heading-structure')
      assert.equal(storeRecordExists(context), false, 'the queued comment must not reach the store')
    } finally {
      fs.mkdirSync = originalMkdirSync
      syncBuiltinESMExports()
      await context.server.close()
    }
  })

  it('records a comment against a document whose headings the parser agrees with', async () => {
    const context = await launch(CLEAN)

    try {
      const response = await mutate(context, 'comment', {
        sectionKey: 'risks',
        documentHash: hashContent(CLEAN),
        body: 'Feedback that must be recorded.'
      })

      assert.equal(response.status, 201)
      assert.equal(storeRecordExists(context), true)
    } finally {
      await context.server.close()
    }
  })
})
