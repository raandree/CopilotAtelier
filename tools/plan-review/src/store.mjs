import { randomBytes } from 'node:crypto'
import { mkdirSync, rmSync, statSync } from 'node:fs'
import { mkdir, readFile, rename, unlink, writeFile } from 'node:fs/promises'
import { join, parse, resolve } from 'node:path'
import { setTimeout as delay } from 'node:timers/promises'

import { assertNoReparsePoint, isInsideDecisionFolder } from './paths.mjs'

export const STORE_SCHEMA = 1

export const STORE_LIMITS = {
  maxComments: 200,
  maxCommentLength: 4000,
  maxNoteLength: 2000,
  maxSectionKeyLength: 128
}

export const VERDICT_VALUES = new Set(['approved', 'changes-requested'])

const DOCUMENT_ID_PATTERN = /^[0-9a-f]{16}$/
const LOCK_TIMEOUT_MS = 5000
const LOCK_STALE_MS = 30000

export class StoreRejection extends Error {
  constructor (message, reason) {
    super(message)
    this.name = 'StoreRejection'
    this.reason = reason
  }
}

function assertDocumentId (documentId) {
  if (typeof documentId !== 'string' || !DOCUMENT_ID_PATTERN.test(documentId)) {
    throw new StoreRejection('document identifier is not an opaque token', 'invalid-document-id')
  }
}

function emptyRecord (documentId, recovered = false) {
  return {
    schema: STORE_SCHEMA,
    documentId,
    // The HTTP surface collects feedback. It never becomes sign-off, and this
    // field is written so a reader of the raw file cannot mistake it for one.
    approvalAuthority: 'chat-sign-off-required',
    comments: [],
    verdict: null,
    recovered
  }
}

async function acquireLock (lockPath) {
  const deadline = Date.now() + LOCK_TIMEOUT_MS

  for (;;) {
    try {
      mkdirSync(lockPath)
      return
    } catch (error) {
      if (error.code !== 'EEXIST') {
        throw new StoreRejection(`cannot acquire store lock: ${error.code ?? error.message}`, 'lock-failed')
      }

      let age = 0
      try {
        age = Date.now() - statSync(lockPath).mtimeMs
      } catch {
        continue
      }

      if (age > LOCK_STALE_MS) {
        try {
          rmSync(lockPath, { recursive: true, force: true })
        } catch {
          // Another process won the cleanup race; retry the acquire.
        }
        continue
      }

      if (Date.now() > deadline) {
        throw new StoreRejection('timed out waiting for the store lock', 'lock-timeout')
      }

      await delay(15)
    }
  }
}

function releaseLock (lockPath) {
  try {
    rmSync(lockPath, { recursive: true, force: true })
  } catch {
    // A missing lock is the desired end state.
  }
}

export function createStore ({ stateRoot }) {
  if (typeof stateRoot !== 'string' || stateRoot.length === 0) {
    throw new StoreRejection('state root must be a non-empty path', 'invalid-state-root')
  }

  const root = resolve(stateRoot)

  if (isInsideDecisionFolder(root)) {
    throw new StoreRejection('state root may not sit inside .memory-bank/decisions', 'decision-root')
  }

  function guardPath (path) {
    assertNoReparsePoint(parse(root).root, path, { allowMissing: true })
  }

  guardPath(root)
  const filePathFor = (documentId) => join(root, `${documentId}.json`)

  async function ensureRoot () {
    guardPath(root)
    await mkdir(root, { recursive: true })
    guardPath(root)
  }

  async function readRaw (documentId) {
    assertDocumentId(documentId)
    guardPath(filePathFor(documentId))

    let text
    try {
      text = await readFile(filePathFor(documentId), 'utf8')
    } catch (error) {
      if (error.code === 'ENOENT') {
        return emptyRecord(documentId)
      }

      throw new StoreRejection(`cannot read store: ${error.code ?? error.message}`, 'read-failed')
    }

    let parsed
    try {
      parsed = JSON.parse(text)
    } catch {
      return emptyRecord(documentId, true)
    }

    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed) || parsed.schema !== STORE_SCHEMA) {
      return emptyRecord(documentId, true)
    }

    return {
      ...emptyRecord(documentId),
      comments: Array.isArray(parsed.comments) ? parsed.comments : [],
      verdict: parsed.verdict ?? null
    }
  }

  async function writeAtomic (documentId, record) {
    await ensureRoot()

    const target = filePathFor(documentId)
    const temporary = `${target}.${randomBytes(6).toString('hex')}.tmp`
    const payload = JSON.stringify({ ...record, recovered: undefined }, null, 2)

    guardPath(target)
    guardPath(temporary)
    await writeFile(temporary, `${payload}\n`, { encoding: 'utf8', mode: 0o600 })

    try {
      guardPath(target)
      await rename(temporary, target)
    } catch (error) {
      await unlink(temporary).catch(() => {})
      throw new StoreRejection(`cannot write store: ${error.code ?? error.message}`, 'write-failed')
    }
  }

  async function mutate (documentId, mutator) {
    assertDocumentId(documentId)
    await ensureRoot()

    const lockPath = join(root, `${documentId}.lock`)
    guardPath(lockPath)
    await acquireLock(lockPath)

    try {
      const record = await readRaw(documentId)
      const result = await mutator(record)
      await writeAtomic(documentId, record)
      return result
    } finally {
      guardPath(lockPath)
      releaseLock(lockPath)
    }
  }

  return {
    stateRoot: root,

    async read (documentId) {
      return readRaw(documentId)
    },

    async addComment (documentId, input) {
      const body = typeof input?.body === 'string' ? input.body.trim() : ''

      if (body.length === 0) {
        throw new StoreRejection('comment body is empty', 'comment-empty')
      }

      if (body.length > STORE_LIMITS.maxCommentLength) {
        throw new StoreRejection('comment body exceeds the length bound', 'comment-too-long')
      }

      if (typeof input?.sectionKey !== 'string' ||
        input.sectionKey.length === 0 ||
        input.sectionKey.length > STORE_LIMITS.maxSectionKeyLength) {
        throw new StoreRejection('section key is missing or over the length bound', 'invalid-section-key')
      }

      return mutate(documentId, (record) => {
        if (record.comments.length >= STORE_LIMITS.maxComments) {
          throw new StoreRejection('comment limit reached for this document', 'comment-limit')
        }

        const comment = {
          id: randomBytes(6).toString('hex'),
          sectionKey: input.sectionKey,
          sectionHash: String(input.sectionHash ?? ''),
          headingText: typeof input.headingText === 'string' ? input.headingText.slice(0, 200) : null,
          ambiguousHeading: input.ambiguousHeading === true,
          documentHash: String(input.documentHash ?? ''),
          body,
          createdAt: new Date().toISOString()
        }

        record.comments.push(comment)
        return { state: 'recorded', comment }
      })
    },

    async removeComment (documentId, commentId) {
      return mutate(documentId, (record) => {
        const before = record.comments.length
        record.comments = record.comments.filter((comment) => comment.id !== commentId)
        return { state: record.comments.length < before ? 'removed' : 'missing' }
      })
    },

    async setVerdict (documentId, input) {
      if (!VERDICT_VALUES.has(input?.verdict)) {
        throw new StoreRejection('verdict must be approved or changes-requested', 'invalid-verdict')
      }

      const note = typeof input.note === 'string' ? input.note.trim() : ''

      if (note.length > STORE_LIMITS.maxNoteLength) {
        throw new StoreRejection('verdict note exceeds the length bound', 'note-too-long')
      }

      if (typeof input.documentHash !== 'string' || input.documentHash.length === 0) {
        throw new StoreRejection('verdict must name the document revision it was cast on', 'missing-document-hash')
      }

      return mutate(documentId, (record) => {
        record.verdict = {
          verdict: input.verdict,
          documentHash: input.documentHash,
          note: note.length > 0 ? note : null,
          // Never "human sign-off": the transport cannot prove who pressed it.
          authority: 'local-http-feedback',
          castAt: new Date().toISOString()
        }

        return { state: 'recorded', verdict: record.verdict }
      })
    }
  }
}

/**
 * Decide how a stored comment relates to the document as it stands now. An
 * orphaned comment stays unanchored on purpose: re-attaching it by heading text
 * would silently move a review remark onto content it was never about.
 */
export function classifyComment (comment, sections) {
  let section = sections.find((candidate) => candidate.key === comment.sectionKey)
  const sameHeading = sections.filter((candidate) => candidate.heading === comment.headingText)

  if (comment.ambiguousHeading === true || sameHeading.length > 1) {
    const exact = sameHeading.filter((candidate) => candidate.hash === comment.sectionHash)
    section = exact.length === 1 ? exact[0] : null
  } else if (typeof comment.headingText === 'string' && section?.heading !== comment.headingText) {
    section = null
  }

  if (!section) {
    return { ...comment, state: 'orphaned', anchorKey: null, currentHeading: null }
  }

  return {
    ...comment,
    state: section.hash === comment.sectionHash ? 'current' : 'revised',
    anchorKey: section.key,
    currentHeading: section.heading
  }
}

export function classifyVerdict (verdict, documentHash) {
  if (!verdict) {
    return { state: 'none', verdict: null, castOn: null }
  }

  return {
    state: verdict.documentHash === documentHash ? 'current' : 'stale',
    verdict: verdict.verdict,
    note: verdict.note ?? null,
    authority: verdict.authority ?? 'local-http-feedback',
    castAt: verdict.castAt ?? null,
    castOn: verdict.documentHash ?? null
  }
}
