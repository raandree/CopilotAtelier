import assert from 'node:assert/strict'
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { afterEach, beforeEach, describe, it } from 'node:test'

import { loadDocument } from '../../src/document.mjs'
import { createReviewServer } from '../../src/server.mjs'

describe('document input boundary', () => {
  let workspace
  let documentPath

  beforeEach(() => {
    workspace = mkdtempSync(join(tmpdir(), 'plan-review-document-input-'))
    documentPath = join(workspace, 'concept.md')
  })

  afterEach(() => rmSync(workspace, { recursive: true, force: true }))

  function openServer (maxDocumentBytes) {
    return createReviewServer({
      documents: [{ root: workspace, path: documentPath }],
      stateRoot: join(workspace, 'feedback'),
      maxDocumentBytes
    })
  }

  it('rejects oversized document input at launch', () => {
    writeFileSync(documentPath, '# Oversized input')
    assert.throws(() => openServer(4), { reason: 'too-large' })
  })

  it('rejects unsupported document extensions at launch', () => {
    documentPath = join(workspace, 'concept.txt')
    writeFileSync(documentPath, '# Not a Markdown file')
    assert.throws(() => openServer(), { reason: 'unsupported-type' })
  })

  it('rejects binary document input at launch', () => {
    writeFileSync(documentPath, Buffer.from([35, 32, 0]))
    assert.throws(() => openServer(), { reason: 'unsupported-type' })
  })

  it('rejects invalid UTF-8 instead of hashing replacement characters', async () => {
    writeFileSync(documentPath, Buffer.from([35, 32, 0xff]))
    await assert.rejects(loadDocument({ root: workspace, path: documentPath }), { reason: 'unsupported-type' })
  })
})
