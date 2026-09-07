import assert from 'node:assert/strict'
import { mkdtempSync, readFileSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { describe, it } from 'node:test'

import {
  MAX_STORE_BYTES,
  STORE_LIMITS,
  STORE_SCHEMA,
  StoreRejection,
  createStore
} from '../../src/store.mjs'

const documentId = 'a1b2c3d4e5f60718'
const sectionHash = 'b'.repeat(64)
const documentHash = 'c'.repeat(64)
// One BMP character costs three UTF-8 bytes but only one unit of the length
// bound, so a legal comment can be three times the size the bound suggests.
const wideBody = '\u6f22'.repeat(STORE_LIMITS.maxCommentLength)

function makeStore () {
  const stateRoot = mkdtempSync(join(tmpdir(), 'plan-review-capacity-'))
  return { stateRoot, store: createStore({ stateRoot }) }
}

function storeFile (stateRoot) {
  return join(stateRoot, `${documentId}.json`)
}

function storedComment (index, body) {
  return {
    id: index.toString(16).padStart(12, '0'),
    sectionKey: 'scope',
    sectionHash,
    headingText: 'Scope',
    ambiguousHeading: false,
    documentHash,
    body,
    createdAt: '2026-01-01T00:00:00.000Z'
  }
}

function serialize (record) {
  return `${JSON.stringify(record, null, 2)}\n`
}

/** The widest legal record that still fits under the read bound. */
function recordAtCapacity () {
  const record = {
    schema: STORE_SCHEMA,
    documentId,
    approvalAuthority: 'chat-sign-off-required',
    comments: [],
    verdict: null
  }

  for (let index = 0; index < STORE_LIMITS.maxComments; index += 1) {
    record.comments.push(storedComment(index, wideBody))

    if (Buffer.byteLength(serialize(record), 'utf8') > MAX_STORE_BYTES) {
      record.comments.pop()
      break
    }
  }

  return record
}

function commentInput (overrides = {}) {
  return {
    sectionKey: 'scope',
    sectionHash,
    headingText: 'Scope',
    documentHash,
    body: 'Narrow this section.',
    ...overrides
  }
}

describe('store write capacity', () => {
  it('runs out of bytes before it runs out of comment slots', () => {
    assert.ok(
      recordAtCapacity().comments.length < STORE_LIMITS.maxComments,
      'the count bound alone cannot keep a multibyte store under the read bound'
    )
  })

  it('refuses a write whose serialized payload would exceed the read bound', async () => {
    const { store, stateRoot } = makeStore()
    const seeded = serialize(recordAtCapacity())
    writeFileSync(storeFile(stateRoot), seeded, 'utf8')

    const before = await store.read(documentId)
    assert.notEqual(before.unreadable, true, 'the seeded store must be readable')

    await assert.rejects(
      () => store.addComment(documentId, commentInput({ body: wideBody })),
      (error) => error instanceof StoreRejection && error.reason === 'store-capacity'
    )

    assert.equal(
      readFileSync(storeFile(stateRoot), 'utf8'),
      seeded,
      'a refused write must leave the stored feedback byte-identical'
    )

    const after = await store.read(documentId)
    assert.notEqual(after.unreadable, true, 'the store must stay readable after a refused write')
    assert.equal(after.comments.length, before.comments.length)
  })

  it('still accepts a comment that fits inside the bound', async () => {
    const { store, stateRoot } = makeStore()
    const record = recordAtCapacity()
    writeFileSync(storeFile(stateRoot), serialize(record), 'utf8')

    await assert.rejects(
      () => store.addComment(documentId, commentInput({ body: wideBody })),
      (error) => error instanceof StoreRejection && error.reason === 'store-capacity'
    )

    const result = await store.addComment(documentId, commentInput())

    assert.equal(result.state, 'recorded')
    assert.equal((await store.read(documentId)).comments.length, record.comments.length + 1)
  })
})

describe('store hash schema', () => {
  const malformed = ['deadbeef', 'B'.repeat(64), 'g'.repeat(64), 'a'.repeat(63), 'a'.repeat(65)]

  it('refuses to write a comment section hash that is not a SHA-256 value', async () => {
    const { store } = makeStore()

    for (const value of malformed) {
      await assert.rejects(
        () => store.addComment(documentId, commentInput({ sectionHash: value })),
        (error) => error instanceof StoreRejection && error.reason === 'invalid-section-hash',
        `section hash ${value} must be refused`
      )
    }
  })

  it('refuses to write a comment document hash that is not a SHA-256 value', async () => {
    const { store } = makeStore()

    for (const value of malformed) {
      await assert.rejects(
        () => store.addComment(documentId, commentInput({ documentHash: value })),
        (error) => error instanceof StoreRejection && error.reason === 'invalid-document-hash',
        `document hash ${value} must be refused`
      )
    }
  })

  it('refuses a verdict whose document hash is not a SHA-256 value', async () => {
    const { store } = makeStore()

    await assert.rejects(
      () => store.setVerdict(documentId, { verdict: 'approved', documentHash: 'hash-one' }),
      (error) => error instanceof StoreRejection && error.reason === 'invalid-document-hash'
    )

    await assert.rejects(
      () => store.setVerdict(documentId, { verdict: 'approved', documentHash: '' }),
      (error) => error instanceof StoreRejection && error.reason === 'missing-document-hash'
    )
  })

  it('records a comment that carries no anchor hash at all', async () => {
    const { store } = makeStore()

    const result = await store.addComment(documentId, commentInput({ sectionHash: '', documentHash: '' }))

    assert.equal(result.state, 'recorded')

    const record = await store.read(documentId)
    assert.notEqual(record.unreadable, true, 'an unanchored comment must stay readable')
    assert.equal(record.comments[0].sectionHash, '')
  })

  it('reports a stored comment hash that is not a SHA-256 value as unreadable', async () => {
    const { store, stateRoot } = makeStore()
    const record = {
      schema: STORE_SCHEMA,
      documentId,
      approvalAuthority: 'chat-sign-off-required',
      comments: [storedComment(1, 'Narrow this.')],
      verdict: null
    }
    record.comments[0].sectionHash = 'deadbeef'
    writeFileSync(storeFile(stateRoot), serialize(record), 'utf8')

    const read = await store.read(documentId)

    assert.equal(read.unreadable, true)
    assert.equal(read.unreadableReason, 'store-comment-invalid')
  })

  it('reports a stored verdict hash that is not a SHA-256 value as unreadable', async () => {
    const { store, stateRoot } = makeStore()
    const record = {
      schema: STORE_SCHEMA,
      documentId,
      approvalAuthority: 'chat-sign-off-required',
      comments: [],
      verdict: {
        verdict: 'approved',
        documentHash: 'hash-one',
        note: null,
        authority: 'local-http-feedback',
        castAt: '2026-01-01T00:00:00.000Z'
      }
    }
    writeFileSync(storeFile(stateRoot), serialize(record), 'utf8')

    const read = await store.read(documentId)

    assert.equal(read.unreadable, true)
    assert.equal(read.unreadableReason, 'store-verdict-invalid')
  })
})
