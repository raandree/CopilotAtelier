import assert from 'node:assert/strict'
import { mkdtempSync, mkdirSync, readdirSync, renameSync, rmSync, symlinkSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { afterEach, beforeEach, describe, it } from 'node:test'

import { createStore } from '../../src/store.mjs'

describe('feedback storage containment', () => {
  let workspace
  let stateRoot
  let outside
  const documentId = 'a'.repeat(16)
  const verdict = { verdict: 'changes-requested', documentHash: 'b'.repeat(64), note: 'Test feedback.' }

  beforeEach(() => {
    workspace = mkdtempSync(join(tmpdir(), 'plan-review-storage-'))
    stateRoot = join(workspace, 'feedback')
    outside = join(workspace, 'outside')
    mkdirSync(outside)
  })

  afterEach(() => rmSync(workspace, { recursive: true, force: true }))

  it('refuses a linked state root before creating feedback files', async () => {
    symlinkSync(outside, stateRoot, process.platform === 'win32' ? 'junction' : 'dir')

    await assert.rejects(async () => {
      const store = createStore({ stateRoot })
      await store.setVerdict(documentId, verdict)
    }, /reparse point/i)
    assert.deepEqual(readdirSync(outside), [])
  })

  it('refuses a root replaced by a link after the store was opened', async () => {
    const store = createStore({ stateRoot })
    await store.setVerdict(documentId, verdict)
    renameSync(stateRoot, join(workspace, 'saved-feedback'))
    symlinkSync(outside, stateRoot, process.platform === 'win32' ? 'junction' : 'dir')

    await assert.rejects(store.setVerdict(documentId, verdict), /reparse point/i)
    await assert.rejects(store.read(documentId), /reparse point/i)
    assert.deepEqual(readdirSync(outside), [])
  })
})
