import assert from 'node:assert/strict'
import { describe, it } from 'node:test'

import { splitSections } from '../../src/document.mjs'
import { classifyComment } from '../../src/store.mjs'

describe('duplicate section identity', () => {
  const original = splitSections('## Risks\nFirst concern.\n## Risks\nSecond concern.\n')

  it('does not attach a removed duplicate section comment to its remaining sibling', () => {
    const comment = {
      sectionKey: original[0].key,
      sectionHash: original[0].hash,
      headingText: original[0].heading,
      ambiguousHeading: true,
      body: 'Feedback on the first concern.'
    }
    const remaining = splitSections('## Risks\nSecond concern.\n')

    assert.equal(classifyComment(comment, remaining).state, 'orphaned')
    assert.equal(classifyComment(comment, remaining).anchorKey, null)
  })

  it('preserves a duplicate anchor only when its exact section content survives', () => {
    const comment = {
      sectionKey: original[1].key,
      sectionHash: original[1].hash,
      headingText: original[1].heading,
      ambiguousHeading: true,
      body: 'Feedback on the second concern.'
    }
    const remaining = splitSections('## Risks\nSecond concern.\n')
    const result = classifyComment(comment, remaining)

    assert.equal(result.state, 'current')
    assert.equal(result.anchorKey, remaining[0].key)
  })

  it('does not reanchor indistinguishable duplicate content', () => {
    const duplicate = splitSections('## Risks\nSame concern.\n## Risks\nSame concern.')
    const comment = {
      sectionKey: duplicate[0].key,
      sectionHash: duplicate[0].hash,
      headingText: duplicate[0].heading,
      ambiguousHeading: true
    }

    assert.equal(classifyComment(comment, duplicate).state, 'orphaned')
  })
})
