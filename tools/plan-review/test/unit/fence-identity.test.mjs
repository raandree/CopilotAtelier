import assert from 'node:assert/strict'
import { describe, it } from 'node:test'

import { splitSections } from '../../src/document.mjs'

function keys (markdown) {
  return splitSections(markdown).map((section) => section.key)
}

describe('fenced code identity', () => {
  it('does not let a shorter inner fence close a longer opening fence', () => {
    const markdown = [
      '# Concept',
      '',
      '````markdown',
      '```',
      '# Not a real heading',
      '```',
      '````',
      '',
      '## Scope',
      '',
      'Real content.',
      ''
    ].join('\n')

    assert.deepEqual(keys(markdown), ['concept', 'scope'])
  })

  it('does not close a backtick fence with a tilde fence', () => {
    const markdown = [
      '# Concept',
      '',
      '```',
      '~~~',
      '## Fake section',
      '```',
      '',
      '## Scope',
      ''
    ].join('\n')

    assert.deepEqual(keys(markdown), ['concept', 'scope'])
  })

  it('closes a tilde fence only with at least as many tildes', () => {
    const markdown = [
      '# Concept',
      '',
      '~~~~',
      '~~~',
      '### Still inside the block',
      '~~~~',
      '',
      '## Scope',
      ''
    ].join('\n')

    assert.deepEqual(keys(markdown), ['concept', 'scope'])
  })

  it('treats a longer closing fence as a valid close', () => {
    const markdown = [
      '# Concept',
      '',
      '```',
      'code',
      '`````',
      '',
      '## Scope',
      ''
    ].join('\n')

    assert.deepEqual(keys(markdown), ['concept', 'scope'])
  })

  it('does not close a fence on a line that carries an info string', () => {
    const markdown = [
      '# Concept',
      '',
      '~~~',
      'text',
      '~~~ still-open',
      '## Fake section',
      '~~~',
      '',
      '## Scope',
      ''
    ].join('\n')

    assert.deepEqual(keys(markdown), ['concept', 'scope'])
  })

  it('does not open a backtick fence whose info string contains a backtick', () => {
    const markdown = [
      '# Concept',
      '',
      '``` a`b',
      '',
      '## Scope',
      ''
    ].join('\n')

    assert.deepEqual(keys(markdown), ['concept', 'scope'])
  })

  it('keeps an ordinary fenced block inside its own section', () => {
    const sections = splitSections([
      '## Scope',
      '',
      '```mermaid',
      'flowchart TD',
      '  A --> B',
      '```',
      ''
    ].join('\n'))

    assert.deepEqual(sections.map((section) => section.key), ['scope'])
    assert.match(sections[0].body, /flowchart TD/)
  })
})
