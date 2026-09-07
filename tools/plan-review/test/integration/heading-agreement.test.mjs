import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { describe, it } from 'node:test'

import MarkdownIt from 'markdown-it'

import { splitSections } from '../../src/document.mjs'
import { createHeadingVerifier } from '../../src/headings.mjs'

const verifyHeadings = createHeadingVerifier()
const parser = new MarkdownIt({ html: false, linkify: false, typographer: false, breaks: false })

/**
 * The parser's own tokens are the oracle: a heading the reader sees must have a
 * section a comment can anchor to, otherwise feedback lands on unrelated text.
 * Reading tokens rather than rendered HTML keeps the check independent of the
 * production sanitizer's markup.
 */
function parsedHeadings (markdown) {
  const tokens = parser.parse(markdown, {})
  const headings = []

  for (let index = 0; index < tokens.length; index += 1) {
    if (tokens[index].type === 'heading_open') {
      headings.push({
        level: Number(tokens[index].tag.slice(1)),
        line: tokens[index].map[0] + 1,
        text: tokens[index + 1].content.trim()
      })
    }
  }

  return headings
}

function splitHeadings (markdown) {
  return splitSections(markdown)
    .filter((section) => section.heading !== null)
    .map((section) => ({ level: section.level, line: section.startLine, text: section.heading }))
}

const fixture = {
  'mixed heading forms': [
    '# Alpha',
    '',
    'Alpha body.',
    '',
    '   ## Indented heading',
    '',
    'Indented body.',
    '',
    'Setext heading',
    '======',
    '',
    'Setext body.',
    '',
    'Second level setext',
    '---',
    '',
    'More.',
    ''
  ].join('\n'),
  'frontmatter block': [
    '---',
    'title: Concept',
    '---',
    '',
    '# Purpose',
    '',
    'Body.',
    ''
  ].join('\n'),
  'fenced code that looks like headings': [
    '# Real',
    '',
    '```text',
    '# Not a heading',
    'Not setext',
    '=====',
    '```',
    '',
    '## After the fence',
    '',
    'Body.',
    ''
  ].join('\n'),
  'thematic breaks and lists': [
    '# Alpha',
    '',
    'Body.',
    '',
    '---',
    '',
    '- item',
    '---',
    '',
    '## Beta',
    ''
  ].join('\n'),
  'duplicate headings across forms': [
    'Risks',
    '-----',
    '',
    'First.',
    '',
    '## Risks',
    '',
    'Second.',
    ''
  ].join('\n'),
  'closing sequences and literal hashes': [
    '# Budget#',
    '',
    'Body.',
    '',
    '## Budget ###',
    '',
    'More.',
    '',
    '### Budget ## revised',
    '',
    'Even more.',
    '',
    '#\tTabbed',
    '',
    'Tail.',
    ''
  ].join('\n'),
  'sequences that are not headings': [
    '# Real',
    '',
    '#NoSeparator',
    '',
    '####### Seven hashes',
    '',
    '    # Indented four spaces',
    ''
  ].join('\n'),
  'nested fences and info strings': [
    '# Real',
    '',
    '````markdown',
    '# Not a heading',
    '',
    '```text',
    'inner',
    '```',
    '````',
    '',
    '## After the outer fence',
    '',
    '```text',
    '# Still not a heading',
    '```js',
    '# Nor this',
    '```',
    '',
    '### After the inner fence',
    ''
  ].join('\n')
}

const sample = readFileSync(
  join(dirname(fileURLToPath(import.meta.url)), '..', '..', 'samples', 'design-concept-sample.md'),
  'utf8'
)

describe('section identity agrees with the parser', () => {
  for (const [name, markdown] of Object.entries(fixture)) {
    it(`matches every parsed heading for ${name}`, () => {
      assert.deepEqual(splitHeadings(markdown), parsedHeadings(markdown))
    })

    it(`accepts ${name} at the document boundary`, () => {
      assert.doesNotThrow(() => verifyHeadings(markdown, splitSections(markdown)))
    })
  }

  it('matches every parsed heading in the shipped sample', () => {
    assert.deepEqual(splitHeadings(sample), parsedHeadings(sample))
  })

  it('accepts the shipped sample at the document boundary', () => {
    assert.doesNotThrow(() => verifyHeadings(sample, splitSections(sample)))
  })
})
