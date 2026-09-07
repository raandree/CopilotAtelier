import assert from 'node:assert/strict'
import { describe, it } from 'node:test'

import { splitSections } from '../../src/document.mjs'
import { classifyComment } from '../../src/store.mjs'

function keysOf (markdown) {
  return splitSections(markdown).map((section) => section.key)
}

function assertUnique (keys, message) {
  assert.equal(new Set(keys).size, keys.length, `${message}: ${keys.join(', ')}`)
}

function commentOn (section, overrides = {}) {
  return {
    sectionKey: section.key,
    sectionHash: section.hash,
    headingText: section.heading,
    ambiguousHeading: false,
    body: 'Feedback.',
    ...overrides
  }
}

describe('section key allocation', () => {
  it('never issues one key twice when a duplicate meets a numbered sibling', () => {
    const keys = keysOf('## Risks\n\nA\n\n## Risks\n\nB\n\n## Risks 2\n\nC\n')

    assert.equal(keys.length, 3)
    assertUnique(keys, 'a numbered heading must not take a duplicate ordinal key')
  })

  it('never issues one key twice when the numbered sibling comes first', () => {
    const keys = keysOf('## Risks 2\n\nC\n\n## Risks\n\nA\n\n## Risks\n\nB\n')

    assert.equal(keys.length, 3)
    assertUnique(keys, 'an ordinal key must not collide with an earlier heading')
  })

  it('keeps the preamble key clear of a heading that slugs to it', () => {
    const keys = keysOf('Opening text before any heading.\n\n## Preamble\n\nBody.\n')

    assert.equal(keys.length, 2)
    assertUnique(keys, 'a heading must not take the preamble key')
  })

  it('keeps unambiguous keys stable when an unrelated heading is inserted', () => {
    const before = keysOf('# Purpose\n\nP\n\n## Scope\n\nS\n')
    const after = keysOf('# Purpose\n\nP\n\n## Notes\n\nN\n\n## Scope\n\nS\n')

    assert.deepEqual(before, ['purpose', 'scope'])
    assert.ok(after.includes('purpose') && after.includes('scope'))
  })

  it('keeps every key unique as colliding headings are inserted and removed', () => {
    const documents = [
      '## Risks\n\nA\n',
      '## Risks\n\nA\n\n## Risks\n\nB\n',
      '## Risks\n\nA\n\n## Risks\n\nB\n\n## Risks 2\n\nC\n',
      '## Risks\n\nA\n\n## Risks 2\n\nC\n',
      '## Risks 2\n\nC\n',
      '## Risks 2\n\nC\n\n## Risks 2\n\nD\n\n## Risks\n\nA\n\n## Risks\n\nB\n'
    ]

    for (const markdown of documents) {
      assertUnique(keysOf(markdown), 'every revision must keep unique keys')
    }
  })
})

describe('section key allocation and comment classification', () => {
  it('anchors a numbered heading to its own content, not to a duplicate sibling', () => {
    const sections = splitSections('## Risks\n\nA\n\n## Risks\n\nB\n\n## Risks 2\n\nC\n')
    const numbered = sections[2]
    const classified = classifyComment(commentOn(numbered), sections)

    assert.equal(classified.state, 'current')
    assert.equal(classified.currentHeading, 'Risks 2')
    assert.equal(classified.anchorKey, numbered.key)
  })

  it('resolves an ambiguous anchor to exactly one section', () => {
    const sections = splitSections('## Risks 2\n\nC\n\n## Risks\n\nA\n\n## Risks\n\nB\n')
    const comment = commentOn(sections[2], { ambiguousHeading: true })
    const classified = classifyComment(comment, sections)

    assert.equal(classified.state, 'current')
    assert.equal(
      sections.filter((section) => section.key === classified.anchorKey).length,
      1,
      'an anchor key that matches more than one section highlights the wrong heading'
    )
    assert.equal(classified.currentHeading, 'Risks')
  })

  it('does not move feedback onto a different heading when a duplicate is removed', () => {
    const original = splitSections('## Risks\n\nA\n\n## Risks\n\nB\n\n## Risks 2\n\nC\n')
    const comment = commentOn(original[1], { ambiguousHeading: true })
    const reduced = splitSections('## Risks\n\nA\n\n## Risks 2\n\nC\n')
    const classified = classifyComment(comment, reduced)

    assert.equal(classified.state, 'orphaned')
    assert.equal(classified.anchorKey, null)
  })
})
