import { randomBytes } from 'node:crypto'
import { mkdirSync, readFileSync, rmdirSync, unlinkSync, writeFileSync } from 'node:fs'
import { mkdir, open, rename, unlink, writeFile } from 'node:fs/promises'
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

// Far below a size worth loading into memory from a file this process did not
// write. The count and length bounds alone do not keep a record under this:
// 4000 characters of multibyte text cost up to three times that in UTF-8, so
// the writer enforces this same bound against the serialized payload.
export const MAX_STORE_BYTES = 2 * 1024 * 1024

export const VERDICT_VALUES = new Set(['approved', 'changes-requested'])

export const FEEDBACK_AUTHORITY = 'local-http-feedback'

const DOCUMENT_ID_PATTERN = /^[0-9a-f]{16}$/
const COMMENT_ID_PATTERN = /^[0-9a-f]{12}$/
const SHA256_PATTERN = /^[0-9a-f]{64}$/
const DEFAULT_LOCK_TIMEOUT_MS = 5000
const LOCK_STALE_MS = 30000
const LOCK_OWNER_FILE = 'owner.json'
const COMMENT_FIELDS = new Set([
  'id', 'sectionKey', 'sectionHash', 'headingText', 'ambiguousHeading', 'documentHash', 'body', 'createdAt'
])
const VERDICT_FIELDS = new Set(['verdict', 'documentHash', 'note', 'authority', 'castAt'])

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

function emptyRecord (documentId) {
  return {
    schema: STORE_SCHEMA,
    documentId,
    // The HTTP surface collects feedback. It never becomes sign-off, and this
    // field is written so a reader of the raw file cannot mistake it for one.
    approvalAuthority: 'chat-sign-off-required',
    comments: [],
    verdict: null
  }
}

function isBoundedString (value, maximum, { allowEmpty = false } = {}) {
  return typeof value === 'string' && (allowEmpty || value.length > 0) && value.length <= maximum
}

function isIsoTimestamp (value) {
  return isBoundedString(value, 40) && Number.isFinite(Date.parse(value))
}

/**
 * A hash this store wrote is always a lowercase SHA-256 digest. The one
 * documented exception is a comment recorded with no anchor at all, which
 * carries an empty string, so an unanchored comment stays readable.
 */
function isStoredHash (value, { allowEmpty = false } = {}) {
  if (typeof value !== 'string') {
    return false
  }

  return (allowEmpty && value.length === 0) || SHA256_PATTERN.test(value)
}

function hasOnlyFields (value, allowed) {
  return Object.keys(value).every((key) => allowed.has(key))
}

function isValidComment (comment) {
  if (comment === null || typeof comment !== 'object' || Array.isArray(comment) ||
    !hasOnlyFields(comment, COMMENT_FIELDS)) {
    return false
  }

  return COMMENT_ID_PATTERN.test(comment.id ?? '') &&
    isBoundedString(comment.sectionKey, STORE_LIMITS.maxSectionKeyLength) &&
    isStoredHash(comment.sectionHash, { allowEmpty: true }) &&
    (comment.headingText === null || isBoundedString(comment.headingText, 200, { allowEmpty: true })) &&
    typeof comment.ambiguousHeading === 'boolean' &&
    isStoredHash(comment.documentHash, { allowEmpty: true }) &&
    isBoundedString(comment.body, STORE_LIMITS.maxCommentLength) &&
    isIsoTimestamp(comment.createdAt)
}

function isValidVerdict (verdict) {
  if (verdict === null || typeof verdict !== 'object' || Array.isArray(verdict) ||
    !hasOnlyFields(verdict, VERDICT_FIELDS)) {
    return false
  }

  return VERDICT_VALUES.has(verdict.verdict) &&
    isStoredHash(verdict.documentHash) &&
    (verdict.note === null || isBoundedString(verdict.note, STORE_LIMITS.maxNoteLength)) &&
    // A stored file cannot promote itself to sign-off by naming a better
    // authority, so only the value this store writes is accepted.
    verdict.authority === FEEDBACK_AUTHORITY &&
    isIsoTimestamp(verdict.castAt)
}

function validationFailure (parsed, documentId) {
  if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) {
    return 'store-malformed'
  }

  if (parsed.schema !== STORE_SCHEMA) {
    return 'store-schema'
  }

  if (parsed.documentId !== documentId) {
    return 'store-foreign-document'
  }

  if (!Array.isArray(parsed.comments) || parsed.comments.length > STORE_LIMITS.maxComments ||
    !parsed.comments.every(isValidComment)) {
    return 'store-comment-invalid'
  }

  if (parsed.verdict !== null && parsed.verdict !== undefined && !isValidVerdict(parsed.verdict)) {
    return 'store-verdict-invalid'
  }

  return null
}

function readOwner (ownerPath) {
  try {
    const owner = JSON.parse(readFileSync(ownerPath, 'utf8'))
    return owner !== null && typeof owner === 'object' ? owner : null
  } catch {
    return null
  }
}

function isProcessAlive (pid) {
  if (!Number.isInteger(pid) || pid <= 0) {
    // An owner that cannot be identified is treated as live rather than broken.
    return true
  }

  try {
    process.kill(pid, 0)
    return true
  } catch (error) {
    return error.code === 'EPERM'
  }
}

/**
 * Take the store lock. A lock held by a live process is waited on and then
 * refused; only a lock whose named owner is provably gone is reclaimed, and
 * that reclaim removes the two entries this module writes rather than deleting
 * a directory tree it does not own.
 */
async function acquireLock (lockPath, timeoutMs) {
  const ownerPath = join(lockPath, LOCK_OWNER_FILE)
  const token = randomBytes(8).toString('hex')
  const deadline = Date.now() + timeoutMs

  for (;;) {
    try {
      mkdirSync(lockPath)
    } catch (error) {
      if (error.code !== 'EEXIST') {
        throw new StoreRejection(`cannot acquire store lock: ${error.code ?? error.message}`, 'lock-failed')
      }

      const owner = readOwner(ownerPath)
      const age = owner?.createdAt ? Date.now() - Date.parse(owner.createdAt) : 0

      if (owner && age > LOCK_STALE_MS && !isProcessAlive(owner.pid)) {
        try {
          unlinkSync(ownerPath)
          rmdirSync(lockPath)
        } catch {
          // Someone else reclaimed it, or the lock holds state this module did
          // not write. Either way, fall through and wait.
        }
      }

      if (Date.now() > deadline) {
        throw new StoreRejection('timed out waiting for the store lock', 'lock-timeout')
      }

      await delay(15)
      continue
    }

    try {
      writeFileSync(
        ownerPath,
        JSON.stringify({ pid: process.pid, token, createdAt: new Date().toISOString() }),
        { encoding: 'utf8', mode: 0o600 }
      )
    } catch (error) {
      try {
        rmdirSync(lockPath)
      } catch {
        // The lock directory is left for the stale path to reclaim.
      }

      throw new StoreRejection(`cannot claim store lock: ${error.code ?? error.message}`, 'lock-failed')
    }

    return { lockPath, ownerPath, token }
  }
}

function holdsLock (lock) {
  return readOwner(lock.ownerPath)?.token === lock.token
}

function releaseLock (lock) {
  if (!holdsLock(lock)) {
    // The lock now belongs to someone else. Removing it would delete their
    // exclusion, so it is left exactly as found.
    return false
  }

  try {
    unlinkSync(lock.ownerPath)
    rmdirSync(lock.lockPath)
  } catch {
    // A missing lock is the desired end state.
  }

  return true
}

export function createStore ({ stateRoot, lockTimeoutMs = DEFAULT_LOCK_TIMEOUT_MS }) {
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

  /**
   * Read the stored feedback with a hard byte bound and full record
   * validation. A file that fails either check is reported, never quietly
   * replaced with an empty record: the bytes on disk are somebody's pending
   * review and the next mutation must not overwrite them.
   */
  async function readRaw (documentId) {
    assertDocumentId(documentId)
    const path = filePathFor(documentId)
    guardPath(path)

    let handle
    try {
      handle = await open(path, 'r')
    } catch (error) {
      if (error.code === 'ENOENT') {
        return emptyRecord(documentId)
      }

      throw new StoreRejection(`cannot read store: ${error.code ?? error.message}`, 'read-failed')
    }

    let text
    try {
      const stat = await handle.stat()

      if (stat.size > MAX_STORE_BYTES) {
        return unreadableRecord(documentId, 'store-too-large')
      }

      const buffer = Buffer.alloc(Number(stat.size))
      const { bytesRead } = await handle.read(buffer, 0, buffer.length, 0)
      text = buffer.subarray(0, bytesRead).toString('utf8')
    } catch (error) {
      throw new StoreRejection(`cannot read store: ${error.code ?? error.message}`, 'read-failed')
    } finally {
      await handle.close()
    }

    let parsed
    try {
      parsed = JSON.parse(text)
    } catch {
      return unreadableRecord(documentId, 'store-malformed')
    }

    const failure = validationFailure(parsed, documentId)

    if (failure) {
      return unreadableRecord(documentId, failure)
    }

    return {
      ...emptyRecord(documentId),
      comments: parsed.comments,
      verdict: parsed.verdict ?? null
    }
  }

  function unreadableRecord (documentId, reason) {
    return { ...emptyRecord(documentId), unreadable: true, unreadableReason: reason }
  }

  async function writeAtomic (documentId, record) {
    await ensureRoot()

    const target = filePathFor(documentId)
    const temporary = `${target}.${randomBytes(6).toString('hex')}.tmp`
    const payload = JSON.stringify(
      { ...emptyRecord(documentId), comments: record.comments, verdict: record.verdict },
      null,
      2
    )

    guardPath(target)
    guardPath(temporary)

    const bytes = `${payload}\n`

    // The reader refuses anything over the bound, so a write that would cross
    // it produces a file the next read cannot use. Refuse here instead, before
    // the temporary file exists, and leave the stored feedback exactly as it is.
    if (Buffer.byteLength(bytes, 'utf8') > MAX_STORE_BYTES) {
      throw new StoreRejection(
        `stored feedback would exceed the ${MAX_STORE_BYTES} byte bound and was left unchanged`,
        'store-capacity'
      )
    }

    await writeFile(temporary, bytes, { encoding: 'utf8', mode: 0o600 })

    try {
      guardPath(target)
      await rename(temporary, target)
    } catch (error) {
      await unlink(temporary).catch(() => {})
      throw new StoreRejection(`cannot write store: ${error.code ?? error.message}`, 'write-failed')
    }
  }

  async function mutate (documentId, mutator, { precondition } = {}) {
    assertDocumentId(documentId)
    await ensureRoot()

    const lockPath = join(root, `${documentId}.lock`)
    guardPath(lockPath)
    const lock = await acquireLock(lockPath, lockTimeoutMs)

    try {
      const record = await readRaw(documentId)

      if (record.unreadable === true) {
        throw new StoreRejection(
          `stored feedback cannot be read and was left untouched (${record.unreadableReason})`,
          record.unreadableReason
        )
      }

      // Anything the caller must re-check against the world runs here, inside
      // the lock, so a change between the request and the commit cannot slip
      // through as an accepted mutation.
      if (precondition) {
        await precondition(record)
      }

      const result = await mutator(record)

      if (!holdsLock(lock)) {
        throw new StoreRejection('lost the store lock before committing', 'lock-lost')
      }

      await writeAtomic(documentId, record)
      return result
    } finally {
      guardPath(lockPath)
      releaseLock(lock)
    }
  }

  return {
    stateRoot: root,

    async read (documentId) {
      return readRaw(documentId)
    },

    async addComment (documentId, input, options = {}) {
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

      // Written and read under the same rule, so this store never commits a
      // record its own reader would refuse.
      const sectionHash = String(input.sectionHash ?? '')
      const documentHash = String(input.documentHash ?? '')

      if (!isStoredHash(sectionHash, { allowEmpty: true })) {
        throw new StoreRejection('section hash must be a SHA-256 value', 'invalid-section-hash')
      }

      if (!isStoredHash(documentHash, { allowEmpty: true })) {
        throw new StoreRejection('document hash must be a SHA-256 value', 'invalid-document-hash')
      }

      return mutate(documentId, (record) => {
        if (record.comments.length >= STORE_LIMITS.maxComments) {
          throw new StoreRejection('comment limit reached for this document', 'comment-limit')
        }

        const comment = {
          id: randomBytes(6).toString('hex'),
          sectionKey: input.sectionKey,
          sectionHash,
          headingText: typeof input.headingText === 'string' ? input.headingText.slice(0, 200) : null,
          ambiguousHeading: input.ambiguousHeading === true,
          documentHash,
          body,
          createdAt: new Date().toISOString()
        }

        record.comments.push(comment)
        return { state: 'recorded', comment }
      }, options)
    },

    async setVerdict (documentId, input, options = {}) {
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

      if (!isStoredHash(input.documentHash)) {
        throw new StoreRejection('document hash must be a SHA-256 value', 'invalid-document-hash')
      }

      return mutate(documentId, (record) => {
        record.verdict = {
          verdict: input.verdict,
          documentHash: input.documentHash,
          note: note.length > 0 ? note : null,
          // Never "human sign-off": the transport cannot prove who pressed it.
          authority: FEEDBACK_AUTHORITY,
          castAt: new Date().toISOString()
        }

        return { state: 'recorded', verdict: record.verdict }
      }, options)
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
    authority: verdict.authority ?? FEEDBACK_AUTHORITY,
    castAt: verdict.castAt ?? null,
    castOn: verdict.documentHash ?? null
  }
}
