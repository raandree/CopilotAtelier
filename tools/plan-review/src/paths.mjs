import { lstatSync, realpathSync, statSync } from 'node:fs'
import { isAbsolute, parse, resolve, sep } from 'node:path'

export class PathRejection extends Error {
  constructor (message, reason) {
    super(message)
    this.name = 'PathRejection'
    this.reason = reason
  }
}

// Windows path comparison is case-insensitive; comparing raw strings there
// turns a realpath casing fix into a false "outside the root" rejection.
const foldCase = process.platform === 'win32'

function fold (value) {
  return foldCase ? value.toLowerCase() : value
}

export function isContained (rootPath, candidatePath) {
  if (!rootPath || !candidatePath) {
    return false
  }

  const trimmed = rootPath.endsWith(sep) ? rootPath.slice(0, -sep.length) : rootPath
  const normalizedRoot = fold(trimmed)
  const normalizedCandidate = fold(candidatePath)

  if (normalizedRoot === normalizedCandidate) {
    return true
  }

  return normalizedCandidate.startsWith(normalizedRoot + sep)
}

function realpathOrThrow (target, what) {
  try {
    return realpathSync.native(target)
  } catch (error) {
    if (error.code === 'ENOENT') {
      throw new PathRejection(`${what} does not exist: ${target}`, 'not-found')
    }

    throw new PathRejection(`${what} cannot be resolved: ${error.code ?? error.message}`, 'unresolvable')
  }
}

/**
 * Reject a reparse point anywhere between the root and the leaf. A link in the
 * middle of the chain redirects a read just as effectively as one at either end.
 */
export function assertNoReparsePoint (rootRealPath, leafPath, { allowMissing = false } = {}) {
  if (!isContained(rootRealPath, leafPath)) {
    throw new PathRejection(`path escapes the declared root: ${leafPath}`, 'outside-root')
  }

  const remainder = leafPath.slice(rootRealPath.length).split(sep).filter(Boolean)
  let current = rootRealPath

  for (const segment of remainder) {
    current = resolve(current, segment)

    let entry
    try {
      entry = lstatSync(current)
    } catch (error) {
      if (error.code === 'ENOENT' && allowMissing) {
        break
      }
      if (error.code === 'ENOENT') {
        throw new PathRejection(`path component does not exist: ${current}`, 'not-found')
      }

      throw new PathRejection(`path component cannot be inspected: ${error.code ?? error.message}`, 'unresolvable')
    }

    if (entry.isSymbolicLink()) {
      throw new PathRejection(`reparse point in path: ${current}`, 'reparse-point')
    }
  }
}

function assertPlainPath (candidate) {
  if (typeof candidate !== 'string' || candidate.length === 0) {
    throw new PathRejection('path must be a non-empty string', 'invalid-path')
  }

  if (candidate.includes('\u0000')) {
    throw new PathRejection('path contains a NUL byte', 'invalid-path')
  }
}

export function resolveRoot (rootPath) {
  assertPlainPath(rootPath)

  const absolute = isAbsolute(rootPath) ? rootPath : resolve(rootPath)
  const real = realpathOrThrow(absolute, 'root')

  if (!statSync(real).isDirectory()) {
    throw new PathRejection(`root is not a directory: ${real}`, 'not-a-directory')
  }

  return real
}

/**
 * Resolve a candidate file inside a declared root. The returned path is the
 * real path, so every later read uses the checked identity rather than the
 * caller's string.
 */
export function resolveContainedPath (rootPath, candidatePath) {
  assertPlainPath(candidatePath)

  const root = resolveRoot(rootPath)
  const absolute = isAbsolute(candidatePath) ? candidatePath : resolve(root, candidatePath)

  // Lexical containment first: a traversal that resolves outside the root is
  // rejected before the filesystem is touched at the escaped location.
  const lexical = resolve(absolute)

  if (!isContained(root, lexical)) {
    throw new PathRejection(`path escapes the declared root: ${lexical}`, 'outside-root')
  }

  assertNoReparsePoint(root, lexical)

  const real = realpathOrThrow(lexical, 'path')

  if (!isContained(root, real)) {
    throw new PathRejection(`resolved path escapes the declared root: ${real}`, 'outside-root')
  }

  const entry = statSync(real)

  if (!entry.isFile()) {
    throw new PathRejection(`path is not a regular file: ${real}`, 'not-a-file')
  }

  return { root, path: real, size: entry.size, mtimeMs: entry.mtimeMs }
}

export function isInsideDecisionFolder (candidatePath) {
  const segments = resolve(candidatePath).split(sep).map((segment) => segment.toLowerCase())

  for (let index = 0; index < segments.length - 1; index += 1) {
    if (segments[index] === '.memory-bank' && segments[index + 1] === 'decisions') {
      return true
    }
  }

  return false
}

export function directoryOf (filePath) {
  return parse(resolve(filePath)).dir
}
