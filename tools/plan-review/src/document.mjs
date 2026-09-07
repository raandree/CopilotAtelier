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

const ATX_OPENING = /^ {0,3}(#{1,6})(?=[ \t]|$)/
const ATX_CLOSING = /(^|[ \t])#+[ \t]*$/
const FENCE = /^ {0,3}((?:`{3,})|(?:~{3,}))(.*)$/
const SETEXT_UNDERLINE = /^ {0,3}(=+|-+)[ \t]*$/
const LIST_OR_QUOTE = /^ {0,3}(?:[-*+]|\d{1,9}[.)])(?:[ \t]|$)|^ {0,3}>/
const THEMATIC_BREAK = /^ {0,3}(?:(?:\*[ \t]*){3,}|(?:-[ \t]*){3,}|(?:_[ \t]*){3,})$/

// The optional closing run of hashes is a closing sequence only when whitespace
// precedes it, so `## Budget#` keeps its hash and `## Budget ##` does not.
function parseAtxHeading (line) {
  const opening = ATX_OPENING.exec(line)

  if (!opening) {
    return null
  }

  let rest = line.slice(opening[0].length)
  const closing = ATX_CLOSING.exec(rest)

  if (closing) {
    rest = rest.slice(0, closing.index + closing[1].length)
  }

  return { level: opening[1].length, text: rest.trim() }
}

// A setext heading's content is the open paragraph above the underline, so a
// line only counts when the renderer would also read it as paragraph text.
function isParagraphLine (line, open) {
  if (line.trim().length === 0 || LIST_OR_QUOTE.test(line)) {
    return false
  }

  return open ? true : !/^ {4,}/.test(line) && !THEMATIC_BREAK.test(line)
}

/**
 * Split a document at the headings the renderer produces — ATX indented by up
 * to three spaces, and setext — into sections with stable keys. The key is the
 * heading slug plus an occurrence ordinal, allocated against every key the
 * document has already issued: an ordinal alone collides whenever a numbered
 * heading meets a duplicated one (`Risks`, `Risks`, `Risks 2`), and two
 * sections sharing a key anchor a comment to the wrong heading.
 */
export function splitSections (markdown) {
  const lines = String(markdown ?? '').split(/\r?\n/)
  const sections = []
  const seen = new Map()
  const used = new Set()

  const allocateKey = (slug) => {
    let occurrence = (seen.get(slug) ?? 0) + 1
    let key = occurrence === 1 ? slug : `${slug}-${occurrence}`

    while (used.has(key)) {
      occurrence += 1
      key = `${slug}-${occurrence}`
    }

    seen.set(slug, occurrence)
    used.add(key)

    return key
  }

  let current = { key: 'preamble', heading: null, level: 0, lines: [], startLine: 1 }
  let fence = null
  let paragraph = []
  let paragraphStart = 0

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

  const startSection = (heading, level, sectionLines, startLine) => {
    const isEmptyPreamble = sections.length === 0 &&
      current.heading === null &&
      current.lines.join('').trim().length === 0

    if (!isEmptyPreamble) {
      if (current.heading === null) {
        // The preamble keeps its key, so a heading slugging to it takes another.
        used.add(current.key)
      }

      push()
    }

    current = {
      key: allocateKey(slugifyHeading(heading)),
      heading,
      level,
      lines: sectionLines,
      startLine
    }
  }

  for (let index = 0; index < lines.length; index += 1) {
    const line = lines[index]
    // CommonMark: an opening fence is closed only by at least as many of the
    // same character with nothing but whitespace after it. A shorter inner
    // fence stays inside the block and cannot expose a heading.
    const fenceMatch = FENCE.exec(line)
    const marker = fenceMatch?.[1]
    const info = fenceMatch?.[2] ?? ''

    if (fence !== null) {
      if (marker && marker[0] === fence.char && marker.length >= fence.length && info.trim().length === 0) {
        fence = null
      }

      paragraph = []
      current.lines.push(line)
      continue
    }

    if (marker && !(marker[0] === '`' && info.includes('`'))) {
      fence = { char: marker[0], length: marker.length }
      paragraph = []
      current.lines.push(line)
      continue
    }

    const atx = parseAtxHeading(line)

    if (atx) {
      paragraph = []
      startSection(atx.text, atx.level, [line], index + 1)
      continue
    }

    const setext = paragraph.length > 0 ? SETEXT_UNDERLINE.exec(line) : null

    if (setext) {
      current.lines.length -= paragraph.length
      const heading = paragraph.join('\n').trim()

      startSection(heading, setext[1].startsWith('=') ? 1 : 2, [...paragraph, line], paragraphStart + 1)
      paragraph = []
      continue
    }

    current.lines.push(line)

    if (!isParagraphLine(line, paragraph.length > 0)) {
      paragraph = []
      continue
    }

    if (paragraph.length === 0) {
      paragraphStart = index
    }

    paragraph.push(line)
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

function documentFromBytes (contained, bytes, maxBytes, verifyHeadings) {
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

  // Supplied by the caller that has the Markdown parser, because this module
  // stays dependency-free for the repository gate.
  if (verifyHeadings) {
    verifyHeadings(markdown, sections)
  }

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

export async function loadDocument ({ root, path, maxBytes = DEFAULT_MAX_DOCUMENT_BYTES, verifyHeadings = null }) {
  const contained = resolveDocumentPath({ root, path, maxBytes })
  return documentFromBytes(contained, await readFile(contained.path), maxBytes, verifyHeadings)
}

export function loadDocumentSync ({ root, path, maxBytes = DEFAULT_MAX_DOCUMENT_BYTES, verifyHeadings = null }) {
  const contained = resolveDocumentPath({ root, path, maxBytes })
  return documentFromBytes(contained, readFileSync(contained.path), maxBytes, verifyHeadings)
}
