import { createHash } from 'node:crypto'
import { readFileSync } from 'node:fs'
import { readFile } from 'node:fs/promises'
import { basename, extname } from 'node:path'

import { resolveContainedPath } from './paths.mjs'

export const DEFAULT_MAX_DOCUMENT_BYTES = 1024 * 1024

const SUPPORTED_EXTENSION = new Set(['.md', '.markdown'])

export class DocumentRejection extends Error {
  constructor (message, reason) {
    super(message)
    this.name = 'DocumentRejection'
    this.reason = reason
  }
}

export function hashContent (text) {
  return createHash('sha256').update(text, 'utf8').digest('hex')
}

export function documentIdFor (realPath) {
  const canonical = process.platform === 'win32' ? realPath.toLowerCase() : realPath
  return createHash('sha256').update(canonical, 'utf8').digest('hex').slice(0, 16)
}

export function slugifyHeading (text) {
  const slug = String(text ?? '')
    .normalize('NFKD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/`|\*|_|~/g, '')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')

  return slug.length > 0 ? slug.slice(0, 64) : 'section'
}

/**
 * Split a document at ATX headings into sections with stable keys. The key is
 * the heading slug plus an occurrence ordinal, so a duplicated heading does not
 * collide and a comment never silently lands on a different section.
 */
export function splitSections (markdown) {
  const lines = String(markdown ?? '').split(/\r?\n/)
  const sections = []
  const seen = new Map()

  let current = { key: 'preamble', heading: null, level: 0, lines: [], startLine: 1 }
  let fence = null

  const push = () => {
    const body = current.lines.join('\n')

    sections.push({
      key: current.key,
      heading: current.heading,
      level: current.level,
      body,
      hash: hashContent(body),
      startLine: current.startLine
    })
  }

  for (let index = 0; index < lines.length; index += 1) {
    const line = lines[index]
    const fenceMatch = /^\s{0,3}(`{3,}|~{3,})/.exec(line)

    if (fenceMatch) {
      if (fence === null) {
        fence = fenceMatch[1][0].repeat(3)
      } else if (fenceMatch[1].startsWith(fence)) {
        fence = null
      }

      current.lines.push(line)
      continue
    }

    const headingMatch = fence === null ? /^(#{1,6})\s+(.*?)\s*#*\s*$/.exec(line) : null

    if (!headingMatch) {
      current.lines.push(line)
      continue
    }

    const isEmptyPreamble = sections.length === 0 &&
      current.heading === null &&
      current.lines.join('').trim().length === 0

    if (!isEmptyPreamble) {
      push()
    }

    const heading = headingMatch[2].trim()
    const slug = slugifyHeading(heading)
    const occurrence = (seen.get(slug) ?? 0) + 1
    seen.set(slug, occurrence)

    current = {
      key: occurrence === 1 ? slug : `${slug}-${occurrence}`,
      heading,
      level: headingMatch[1].length,
      lines: [line],
      startLine: index + 1
    }
  }

  push()

  return sections
}

function titleOf (sections, fallback) {
  const heading = sections.find((section) => section.heading)
  return heading ? heading.heading : fallback
}

/**
 * Read one authorized document. The path is re-checked on every load, so a link
 * or a replacement swapped in after launch is rejected at read time too.
 */
function resolveDocumentPath ({ root, path, maxBytes }) {
  if (!SUPPORTED_EXTENSION.has(extname(path).toLowerCase())) {
    throw new DocumentRejection(`unsupported document type: ${extname(path) || '(none)'}`, 'unsupported-type')
  }

  if (!Number.isSafeInteger(maxBytes) || maxBytes < 1) {
    throw new DocumentRejection('document size bound must be a positive integer', 'invalid-limit')
  }

  const contained = resolveContainedPath(root, path)

  if (contained.size > maxBytes) {
    throw new DocumentRejection(`document exceeds ${maxBytes} bytes`, 'too-large')
  }

  return contained
}

function documentFromBytes (contained, bytes, maxBytes) {
  if (bytes.byteLength > maxBytes) {
    throw new DocumentRejection(`document exceeds ${maxBytes} bytes`, 'too-large')
  }

  if (bytes.includes(0)) {
    throw new DocumentRejection('document contains binary content', 'unsupported-type')
  }

  let markdown
  try {
    markdown = new TextDecoder('utf-8', { fatal: true }).decode(bytes)
  } catch {
    throw new DocumentRejection('document must contain valid UTF-8', 'unsupported-type')
  }
  const sections = splitSections(markdown)

  return {
    id: documentIdFor(contained.path),
    path: contained.path,
    root: contained.root,
    name: basename(contained.path),
    title: titleOf(sections, basename(contained.path)),
    markdown,
    sections,
    revision: {
      hash: hashContent(bytes),
      size: bytes.byteLength,
      mtimeMs: contained.mtimeMs,
      readAt: new Date().toISOString()
    }
  }
}

export async function loadDocument ({ root, path, maxBytes = DEFAULT_MAX_DOCUMENT_BYTES }) {
  const contained = resolveDocumentPath({ root, path, maxBytes })
  return documentFromBytes(contained, await readFile(contained.path), maxBytes)
}

export function loadDocumentSync ({ root, path, maxBytes = DEFAULT_MAX_DOCUMENT_BYTES }) {
  const contained = resolveDocumentPath({ root, path, maxBytes })
  return documentFromBytes(contained, readFileSync(contained.path), maxBytes)
}
