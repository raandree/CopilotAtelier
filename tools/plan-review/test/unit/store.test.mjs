import assert from 'node:assert/strict'
import { mkdtempSync, readFileSync, readdirSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { describe, it } from 'node:test'

import { splitSections } from '../../src/document.mjs'
import {
  STORE_LIMITS,
  StoreRejection,
  classifyComment,
  classifyVerdict,
  createStore
} from '../../src/store.mjs'

const documentId = 'a1b2c3d4e5f60718'
// The store writes and reads only real SHA-256 digests, so a stand-in hash in a
// test has to have that shape too.
const revisionHash = 'd'.repeat(64)

function makeStore () {
  const stateRoot = mkdtempSync(join(tmpdir(), 'plan-review-store-'))
  return { stateRoot, store: createStore({ stateRoot }) }
}

const sections = splitSections('# Purpose\n\nShip a thing.\n\n## Scope\n\nIn scope.\n')

function sectionByKey (key) {
  return sections.find((section) => section.key === key)
}

describe('createStore', () => {
  it('starts empty and declares that approval authority lives elsewhere', async () => {
    const { store } = makeStore()

    const record = await store.read(documentId)

    assert.deepEqual(record.comments, [])
    assert.equal(record.verdict, null)
    assert.equal(record.approvalAuthority, 'chat-sign-off-required')
  })

  it('refuses a state root inside the Decision record folder', () => {
    const base = mkdtempSync(join(tmpdir(), 'plan-review-state-'))
    const stateRoot = join(base, '.memory-bank', 'decisions', 'plan-review')

    assert.throws(
      () => createStore({ stateRoot }),
      (error) => error instanceof StoreRejection && error.reason === 'decision-root'
    )
  })

  it('refuses a document identifier that is not an opaque token', async () => {
    const { store } = makeStore()

    await assert.rejects(
      () => store.read('../escape'),
      (error) => error instanceof StoreRejection && error.reason === 'invalid-document-id'
    )
  })
})

describe('addComment', () => {
  it('persists a comment bound to a section hash and a document hash', async () => {
    const { store, stateRoot } = makeStore()
    const scope = sectionByKey('scope')

    const result = await store.addComment(documentId, {
      sectionKey: scope.key,
      sectionHash: scope.hash,
      headingText: scope.heading,
      documentHash: revisionHash,
      body: 'Narrow this.'
    })

    assert.equal(result.state, 'recorded')
    assert.match(result.comment.id, /^[0-9a-f]{12}$/)

    const record = await store.read(documentId)
    assert.equal(record.comments.length, 1)
    assert.equal(record.comments[0].sectionHash, scope.hash)
    assert.equal(record.comments[0].documentHash, revisionHash)

    const written = readdirSync(stateRoot).filter((name) => name.endsWith('.json'))
    assert.equal(written.length, 1)
    assert.equal(JSON.parse(readFileSync(join(stateRoot, written[0]), 'utf8')).schema, 1)
  })

  it('stores comment text verbatim without interpreting markup', async () => {
    const { store } = makeStore()
    const scope = sectionByKey('scope')
    const hostile = '<img src=x onerror=alert(1)> [x](javascript:alert(1))'

    await store.addComment(documentId, {
      sectionKey: scope.key,
      sectionHash: scope.hash,
      headingText: scope.heading,
      documentHash: revisionHash,
      body: hostile
    })

    const record = await store.read(documentId)
    assert.equal(record.comments[0].body, hostile)
  })

  it('rejects a comment body over the length bound', async () => {
    const { store } = makeStore()
    const scope = sectionByKey('scope')

    await assert.rejects(
      () => store.addComment(documentId, {
        sectionKey: scope.key,
        sectionHash: scope.hash,
        headingText: scope.heading,
        documentHash: revisionHash,
        body: 'x'.repeat(STORE_LIMITS.maxCommentLength + 1)
      }),
      (error) => error instanceof StoreRejection && error.reason === 'comment-too-long'
    )
  })

  it('rejects an empty comment body', async () => {
    const { store } = makeStore()
    const scope = sectionByKey('scope')

    await assert.rejects(
      () => store.addComment(documentId, {
        sectionKey: scope.key,
        sectionHash: scope.hash,
        headingText: scope.heading,
        documentHash: revisionHash,
        body: '   '
      }),
      (error) => error instanceof StoreRejection && error.reason === 'comment-empty'
    )
  })

  it('caps the number of comments per document', async () => {
    const { store } = makeStore()
    const scope = sectionByKey('scope')

    for (let index = 0; index < STORE_LIMITS.maxComments; index += 1) {
      await store.addComment(documentId, {
        sectionKey: scope.key,
        sectionHash: scope.hash,
        headingText: scope.heading,
        documentHash: revisionHash,
        body: `comment ${index}`
      })
    }

    await assert.rejects(
      () => store.addComment(documentId, {
        sectionKey: scope.key,
        sectionHash: scope.hash,
        headingText: scope.heading,
        documentHash: revisionHash,
        body: 'one too many'
      }),
      (error) => error instanceof StoreRejection && error.reason === 'comment-limit'
    )
  })

  it('serialises concurrent writes without losing a comment', async () => {
    const { store } = makeStore()
    const scope = sectionByKey('scope')

    await Promise.all(
      Array.from({ length: 12 }, (_ignored, index) => store.addComment(documentId, {
        sectionKey: scope.key,
        sectionHash: scope.hash,
        headingText: scope.heading,
        documentHash: revisionHash,
        body: `concurrent ${index}`
      }))
    )

    const record = await store.read(documentId)
    assert.equal(record.comments.length, 12)
  })

  it('does not leave a temporary file behind', async () => {
    const { store, stateRoot } = makeStore()
    const scope = sectionByKey('scope')

    await store.addComment(documentId, {
      sectionKey: scope.key,
      sectionHash: scope.hash,
      headingText: scope.heading,
      documentHash: revisionHash,
      body: 'Narrow this.'
    })

    assert.deepEqual(readdirSync(stateRoot).filter((name) => name.includes('.tmp')), [])
  })

  it('reports a corrupt store file instead of emptying it', async () => {
    const { store, stateRoot } = makeStore()
    writeFileSync(join(stateRoot, `${documentId}.json`), '{ not json', 'utf8')

    const record = await store.read(documentId)

    assert.equal(record.unreadable, true)
    assert.equal(record.unreadableReason, 'store-malformed')
    assert.equal(readFileSync(join(stateRoot, `${documentId}.json`), 'utf8'), '{ not json')
  })
})

describe('setVerdict', () => {
  it('records a verdict against the document hash it was cast on', async () => {
    const { store } = makeStore()

    await store.setVerdict(documentId, {
      verdict: 'approved',
      documentHash: revisionHash,
      note: 'Looks right.'
    })

    const record = await store.read(documentId)
    assert.equal(record.verdict.verdict, 'approved')
    assert.equal(record.verdict.documentHash, revisionHash)
    assert.equal(record.verdict.authority, 'local-http-feedback')
  })

  it('refuses an unsupported verdict value', async () => {
    const { store } = makeStore()

    await assert.rejects(
      () => store.setVerdict(documentId, { verdict: 'signed-off', documentHash: revisionHash }),
      (error) => error instanceof StoreRejection && error.reason === 'invalid-verdict'
    )
  })

  it('replaces an earlier verdict rather than accumulating verdicts', async () => {
    const { store } = makeStore()

    await store.setVerdict(documentId, { verdict: 'approved', documentHash: revisionHash })
    await store.setVerdict(documentId, { verdict: 'changes-requested', documentHash: revisionHash })

    const record = await store.read(documentId)
    assert.equal(record.verdict.verdict, 'changes-requested')
  })
})

describe('classifyComment', () => {
  it('reports a comment on unchanged content as current', () => {
    const scope = sectionByKey('scope')
    const comment = { sectionKey: scope.key, sectionHash: scope.hash }

    assert.equal(classifyComment(comment, sections).state, 'current')
  })

  it('reports a comment whose section changed as revised, without moving it', () => {
    const scope = sectionByKey('scope')
    const comment = { sectionKey: scope.key, sectionHash: 'stale-hash' }

    const classified = classifyComment(comment, sections)
    assert.equal(classified.state, 'revised')
    assert.equal(classified.sectionKey, scope.key)
  })

  it('reports a comment whose section is gone as orphaned and unanchored', () => {
    const comment = { sectionKey: 'removed-section', sectionHash: 'anything' }

    const classified = classifyComment(comment, sections)
    assert.equal(classified.state, 'orphaned')
    assert.equal(classified.anchorKey, null)
  })

  it('does not reattach an orphaned comment to a like-named section', () => {
    const renamed = splitSections('# Purpose\n\nShip a thing.\n\n## Boundaries\n\nIn scope.\n')
    const scope = sectionByKey('scope')
    const comment = { sectionKey: scope.key, sectionHash: scope.hash }

    const classified = classifyComment(comment, renamed)
    assert.equal(classified.state, 'orphaned')
    assert.equal(classified.anchorKey, null)
  })
})

describe('classifyVerdict', () => {
  it('reports no verdict as none', () => {
    assert.equal(classifyVerdict(null, 'hash-one').state, 'none')
  })

  it('reports a verdict on the current revision as current', () => {
    const verdict = { verdict: 'approved', documentHash: 'hash-one' }
    assert.equal(classifyVerdict(verdict, 'hash-one').state, 'current')
  })

  it('invalidates a verdict once the document changes', () => {
    const verdict = { verdict: 'approved', documentHash: 'hash-one' }
    const classified = classifyVerdict(verdict, 'hash-two')

    assert.equal(classified.state, 'stale')
    assert.equal(classified.verdict, 'approved')
    assert.equal(classified.castOn, 'hash-one')
  })
})
