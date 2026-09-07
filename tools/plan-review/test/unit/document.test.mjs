import assert from 'node:assert/strict'
import { mkdtempSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { describe, it } from 'node:test'

import {
  DocumentRejection,
  documentIdFor,
  hashContent,
  loadDocument,
  slugifyHeading,
  splitSections
} from '../../src/document.mjs'

const sample = [
  'Intro paragraph before any heading.',
  '',
  '# Purpose',
  '',
  'Ship a thing.',
  '',
  '## Scope',
  '',
  'In scope.',
  '',
  '## Scope',
  '',
  'A duplicate heading on purpose.',
  ''
].join('\n')

describe('slugifyHeading', () => {
  it('produces a stable ascii slug', () => {
    assert.equal(slugifyHeading('Design options and recommendation'), 'design-options-and-recommendation')
  })

  it('collapses punctuation instead of dropping the heading', () => {
    assert.equal(slugifyHeading('Rollback / migration!'), 'rollback-migration')
  })

  it('falls back to a placeholder for a symbol-only heading', () => {
    assert.equal(slugifyHeading('***'), 'section')
  })
})

describe('splitSections', () => {
  it('captures the preamble before the first heading', () => {
    const sections = splitSections(sample)

    assert.equal(sections[0].key, 'preamble')
    assert.equal(sections[0].level, 0)
    assert.match(sections[0].body, /Intro paragraph/)
  })

  it('disambiguates duplicate headings with an occurrence ordinal', () => {
    const keys = splitSections(sample).map((section) => section.key)

    assert.deepEqual(keys, ['preamble', 'purpose', 'scope', 'scope-2'])
  })

  it('hashes section bodies so an edit is detectable', () => {
    const before = splitSections(sample)
    const after = splitSections(sample.replace('In scope.', 'In scope, revised.'))

    const beforeScope = before.find((section) => section.key === 'scope')
    const afterScope = after.find((section) => section.key === 'scope')

    assert.equal(beforeScope.key, afterScope.key)
    assert.notEqual(beforeScope.hash, afterScope.hash)
  })

  it('ignores headings inside fenced code blocks', () => {
    const withFence = [
      '# Real',
      '',
      '```text',
      '# Not a heading',
      '```',
      ''
    ].join('\n')

    assert.deepEqual(splitSections(withFence).map((section) => section.key), ['real'])
  })

  it('returns a single preamble section for a document with no headings', () => {
    const sections = splitSections('Just prose.\n')

    assert.equal(sections.length, 1)
    assert.equal(sections[0].key, 'preamble')
  })
})

describe('hashContent', () => {
  it('is stable and sensitive', () => {
    assert.equal(hashContent('a'), hashContent('a'))
    assert.notEqual(hashContent('a'), hashContent('b'))
    assert.match(hashContent('a'), /^[0-9a-f]{64}$/)
  })
})

describe('documentIdFor', () => {
  it('is an opaque, path-free identifier', () => {
    const id = documentIdFor('C:\\repo\\docs\\concept.md')

    assert.match(id, /^[0-9a-f]{16}$/)
    assert.ok(!id.includes('concept'))
  })
})

describe('loadDocument', () => {
  it('reports a revision hash, size and section list', async () => {
    const root = mkdtempSync(join(tmpdir(), 'plan-review-doc-'))
    const file = join(root, 'concept.md')
    writeFileSync(file, sample, 'utf8')

    const document = await loadDocument({ root, path: file })

    assert.equal(document.revision.hash, hashContent(sample))
    assert.equal(document.revision.size, Buffer.byteLength(sample, 'utf8'))
    assert.equal(document.title, 'Purpose')
    assert.equal(document.sections.length, 4)
    assert.equal(document.id, documentIdFor(document.path))
  })

  it('refuses a document larger than the byte bound', async () => {
    const root = mkdtempSync(join(tmpdir(), 'plan-review-doc-'))
    const file = join(root, 'big.md')
    writeFileSync(file, 'x'.repeat(4096), 'utf8')

    await assert.rejects(
      () => loadDocument({ root, path: file, maxBytes: 1024 }),
      (error) => error instanceof DocumentRejection && error.reason === 'too-large'
    )
  })

  it('refuses a document that is not Markdown', async () => {
    const root = mkdtempSync(join(tmpdir(), 'plan-review-doc-'))
    const file = join(root, 'concept.exe')
    writeFileSync(file, 'MZ', 'utf8')

    await assert.rejects(
      () => loadDocument({ root, path: file }),
      (error) => error instanceof DocumentRejection && error.reason === 'unsupported-type'
    )
  })

  it('re-reads the file so a mutation between loads changes the revision', async () => {
    const root = mkdtempSync(join(tmpdir(), 'plan-review-doc-'))
    const file = join(root, 'concept.md')
    writeFileSync(file, sample, 'utf8')

    const first = await loadDocument({ root, path: file })
    writeFileSync(file, `${sample}\n## Added\n\nMore.\n`, 'utf8')
    const second = await loadDocument({ root, path: file })

    assert.notEqual(first.revision.hash, second.revision.hash)
    assert.equal(first.id, second.id)
  })
})
