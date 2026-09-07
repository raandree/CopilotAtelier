import MarkdownIt from 'markdown-it'

import { DocumentRejection } from './document.mjs'

const HEADING_TAG = /^h([1-6])$/

function describeHeading (heading) {
  return `level ${heading.level} at line ${heading.line}`
}

/**
 * The Markdown parser decides what the reader sees, so a section is only a
 * trustworthy anchor while the dependency-free splitter agrees with it. A
 * document whose heading structure differs is refused at the boundary instead
 * of being served with feedback attached to a combined or shifted section.
 */
export function createHeadingVerifier () {
  const parser = new MarkdownIt({ html: false, linkify: false, typographer: false, breaks: false })

  function parsedHeadings (source) {
    const tokens = parser.parse(String(source ?? ''), {})
    const headings = []

    for (let index = 0; index < tokens.length; index += 1) {
      const token = tokens[index]

      if (token.type !== 'heading_open') {
        continue
      }

      const tag = HEADING_TAG.exec(token.tag ?? '')

      if (!tag) {
        throw new DocumentRejection(`unsupported heading tag: ${token.tag}`, 'heading-structure')
      }

      // A nested token sits inside a blockquote or a list item, which the
      // splitter does not model and cannot anchor a comment to.
      if (token.level !== 0) {
        throw new DocumentRejection(
          `heading inside a blockquote or list item at line ${token.map[0] + 1} is not supported`,
          'heading-structure'
        )
      }

      const inline = tokens[index + 1]

      headings.push({
        level: Number(tag[1]),
        line: token.map[0] + 1,
        text: (inline?.type === 'inline' ? inline.content : '').trim()
      })
    }

    return headings
  }

  return function verifyHeadings (markdown, sections) {
    const parsed = parsedHeadings(markdown)
    const split = sections
      .filter((section) => section.heading !== null)
      .map((section) => ({ level: section.level, line: section.startLine, text: section.heading }))

    if (parsed.length !== split.length) {
      throw new DocumentRejection(
        `heading structure is ambiguous: the document renders ${parsed.length} headings but splits into ${split.length}`,
        'heading-structure'
      )
    }

    for (let index = 0; index < parsed.length; index += 1) {
      const rendered = parsed[index]
      const section = split[index]

      if (rendered.level !== section.level || rendered.line !== section.line || rendered.text !== section.text) {
        throw new DocumentRejection(
          `heading ${index + 1} is ambiguous: rendered as ${describeHeading(rendered)}, ` +
          `split as ${describeHeading(section)}`,
          'heading-structure'
        )
      }
    }
  }
}
