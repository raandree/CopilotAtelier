import assert from 'node:assert/strict'
import { existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { describe, it } from 'node:test'

import { MAX_STORE_BYTES, STORE_SCHEMA, StoreRejection, createStore } from '../../src/store.mjs'

const documentId = 'a1b2c3d4e5f60718'

function makeStore (options = {}) {
  const stateRoot = mkdtempSync(join(tmpdir(), 'plan-review-integrity-'))
  mkdirSync(stateRoot, { recursive: true })

  return { stateRoot, store: createStore({ stateRoot, ...options }) }
}

function storeFile (stateRoot) {
  return join(stateRoot, `${documentId}.json`)
}

function validComment (overrides = {}) {
  return {
    id: 'a1b2c3d4e5f6',
    sectionKey: 'scope',
    sectionHash: 'b'.repeat(64),
    headingText: 'Scope',
    ambiguousHeading: false,
    documentHash: 'c'.repeat(64),
    body: 'Narrow this section.',
    createdAt: new Date().toISOString(),
    ...overrides
  }
}

function validRecord (overrides = {}) {
  return {
    schema: STORE_SCHEMA,
    documentId,
    approvalAuthority: 'chat-sign-off-required',
    comments: [validComment()],
    verdict: null,
    ...overrides
  }
}

function commentInput () {
  return {
    sectionKey: 'scope',
    sectionHash: 'b'.repeat(64),
    headingText: 'Scope',
    documentHash: 'c'.repeat(64),
    body: 'Added after the store was already on disk.'
  }
}

async function assertRefusedAndPreserved (store, stateRoot, original, reason) {
  const record = await store.read(documentId)

  assert.equal(record.unreadable, true, 'an unreadable store must be reported, not silently emptied')
  assert.equal(record.unreadableReason, reason)
  assert.notEqual(record.recovered, true, 'an unreadable store must not present itself as recovered')

  await assert.rejects(
    () => store.addComment(documentId, commentInput()),
    (error) => error instanceof StoreRejection && error.reason === reason
  )

  await assert.rejects(
    () => store.setVerdict(documentId, { verdict: 'approved', documentHash: 'c'.repeat(64) }),
    (error) => error instanceof StoreRejection && error.reason === reason
  )

  assert.equal(
    readFileSync(storeFile(stateRoot), 'utf8'),
    original,
    'the original feedback bytes must survive a refused mutation'
  )
}

describe('store read bounds and strict validation', () => {
  it('refuses a store file beyond the read bound instead of emptying it', async () => {
    const { store, stateRoot } = makeStore()
    const oversize = `{"schema":1,"documentId":"${documentId}","padding":"${'x'.repeat(MAX_STORE_BYTES)}"}`
    writeFileSync(storeFile(stateRoot), oversize, 'utf8')

    await assertRefusedAndPreserved(store, stateRoot, oversize, 'store-too-large')
  })

  it('refuses a record that names a different document', async () => {
    const { store, stateRoot } = makeStore()
    const foreign = JSON.stringify(validRecord({ documentId: '0123456789abcdef' }), null, 2)
    writeFileSync(storeFile(stateRoot), foreign, 'utf8')

    await assertRefusedAndPreserved(store, stateRoot, foreign, 'store-foreign-document')
  })

  it('refuses a malformed comment rather than accepting arbitrary fields', async () => {
    const { store, stateRoot } = makeStore()
    const malformed = JSON.stringify(validRecord({
      comments: [validComment({ body: 42 })]
    }), null, 2)
    writeFileSync(storeFile(stateRoot), malformed, 'utf8')

    await assertRefusedAndPreserved(store, stateRoot, malformed, 'store-comment-invalid')
  })

  it('refuses a comment carrying an unknown field', async () => {
    const { store, stateRoot } = makeStore()
    const smuggled = JSON.stringify(validRecord({
      comments: [validComment({ approvedBy: 'someone' })]
    }), null, 2)
    writeFileSync(storeFile(stateRoot), smuggled, 'utf8')

    await assertRefusedAndPreserved(store, stateRoot, smuggled, 'store-comment-invalid')
  })

  it('refuses a stored verdict that claims an authority the transport cannot prove', async () => {
    const { store, stateRoot } = makeStore()
    const forged = JSON.stringify(validRecord({
      verdict: {
        verdict: 'approved',
        documentHash: 'c'.repeat(64),
        note: null,
        authority: 'human-sign-off',
        castAt: new Date().toISOString()
      }
    }), null, 2)
    writeFileSync(storeFile(stateRoot), forged, 'utf8')

    await assertRefusedAndPreserved(store, stateRoot, forged, 'store-verdict-invalid')
  })

  it('refuses an unsupported verdict value in a stored record', async () => {
    const { store, stateRoot } = makeStore()
    const invalid = JSON.stringify(validRecord({
      verdict: {
        verdict: 'signed-off',
        documentHash: 'c'.repeat(64),
        note: null,
        authority: 'local-http-feedback',
        castAt: new Date().toISOString()
      }
    }), null, 2)
    writeFileSync(storeFile(stateRoot), invalid, 'utf8')

    await assertRefusedAndPreserved(store, stateRoot, invalid, 'store-verdict-invalid')
  })

  it('preserves corrupt bytes when the next mutation arrives', async () => {
    const { store, stateRoot } = makeStore()
    const corrupt = '{ not json'
    writeFileSync(storeFile(stateRoot), corrupt, 'utf8')

    await assertRefusedAndPreserved(store, stateRoot, corrupt, 'store-malformed')
    assert.deepEqual(readdirSync(stateRoot).filter((name) => name.endsWith('.tmp')), [])
  })

  it('accepts a well-formed record written by an earlier launch', async () => {
    const { store, stateRoot } = makeStore()
    writeFileSync(storeFile(stateRoot), JSON.stringify(validRecord(), null, 2), 'utf8')

    const record = await store.read(documentId)

    assert.notEqual(record.unreadable, true)
    assert.equal(record.comments.length, 1)

    await store.addComment(documentId, commentInput())
    assert.equal((await store.read(documentId)).comments.length, 2)
  })
})

describe('store lock ownership', () => {
  function holdLock (stateRoot, owner) {
    const lockPath = join(stateRoot, `${documentId}.lock`)
    mkdirSync(lockPath, { recursive: true })
    const ownerPath = join(lockPath, 'owner.json')
    writeFileSync(ownerPath, JSON.stringify(owner), 'utf8')

    return { lockPath, ownerPath }
  }

  it('refuses to break a lock held by a live process, however old it is', async () => {
    const { store, stateRoot } = makeStore({ lockTimeoutMs: 200 })
    const lock = holdLock(stateRoot, {
      pid: process.pid,
      token: 'f'.repeat(16),
      createdAt: new Date(Date.now() - 600_000).toISOString()
    })

    await assert.rejects(
      () => store.addComment(documentId, commentInput()),
      (error) => error instanceof StoreRejection && error.reason === 'lock-timeout'
    )

    assert.ok(existsSync(lock.ownerPath), 'a live owner must not have its lock deleted')
    assert.ok(!existsSync(storeFile(stateRoot)), 'no feedback may be written without the lock')
  })

  it('reclaims a stale lock whose owner is gone', async () => {
    const { store, stateRoot } = makeStore({ lockTimeoutMs: 2000 })
    holdLock(stateRoot, {
      // A pid that cannot be running: process 0 is never a live user process.
      pid: 2 ** 31 - 1,
      token: 'a'.repeat(16),
      createdAt: new Date(Date.now() - 600_000).toISOString()
    })

    const result = await store.addComment(documentId, commentInput())

    assert.equal(result.state, 'recorded')
  })

  it('refuses to commit after losing ownership of the lock', async () => {
    const { store, stateRoot } = makeStore()

    await assert.rejects(
      () => store.addComment(documentId, commentInput(), {
        precondition: () => {
          const ownerPath = join(stateRoot, `${documentId}.lock`, 'owner.json')
          writeFileSync(ownerPath, JSON.stringify({ pid: process.pid, token: '0'.repeat(16) }), 'utf8')
        }
      }),
      (error) => error instanceof StoreRejection && error.reason === 'lock-lost'
    )

    assert.ok(!existsSync(storeFile(stateRoot)), 'a lost lock must not commit')
    assert.ok(
      existsSync(join(stateRoot, `${documentId}.lock`, 'owner.json')),
      'a lock owned by someone else must not be removed on release'
    )
  })

  it('runs a precondition inside the lock and refuses the mutation when it fails', async () => {
    const { store } = makeStore()

    await assert.rejects(
      () => store.setVerdict(documentId, { verdict: 'approved', documentHash: 'c'.repeat(64) }, {
        precondition: () => {
          throw new StoreRejection('the source changed while the mutation was queued', 'stale-source')
        }
      }),
      (error) => error instanceof StoreRejection && error.reason === 'stale-source'
    )
  })
})
