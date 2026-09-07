import assert from 'node:assert/strict'
import { mkdtempSync, mkdirSync, writeFileSync, symlinkSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { describe, it } from 'node:test'

import { PathRejection, isContained, resolveContainedPath } from '../../src/paths.mjs'

function makeRoot () {
  return mkdtempSync(join(tmpdir(), 'plan-review-paths-'))
}

describe('resolveContainedPath', () => {
  it('accepts a regular file inside the declared root', () => {
    const root = makeRoot()
    const file = join(root, 'concept.md')
    writeFileSync(file, '# Concept\n')

    const resolved = resolveContainedPath(root, file)

    assert.ok(isContained(resolved.root, resolved.path))
    assert.equal(resolved.path.endsWith('concept.md'), true)
  })

  it('rejects a traversal escape from the declared root', () => {
    const root = makeRoot()
    const outside = join(root, '..', 'outside.md')
    writeFileSync(outside, '# Outside\n')

    assert.throws(
      () => resolveContainedPath(root, join(root, '..', 'outside.md')),
      (error) => error instanceof PathRejection && error.reason === 'outside-root'
    )
  })

  it('rejects an absolute path that merely shares a name prefix with the root', () => {
    const root = makeRoot()
    const sibling = `${root}-sibling`
    mkdirSync(sibling, { recursive: true })
    const file = join(sibling, 'concept.md')
    writeFileSync(file, '# Concept\n')

    assert.throws(
      () => resolveContainedPath(root, file),
      (error) => error instanceof PathRejection && error.reason === 'outside-root'
    )
  })

  it('rejects a missing file rather than inventing one', () => {
    const root = makeRoot()

    assert.throws(
      () => resolveContainedPath(root, join(root, 'nope.md')),
      (error) => error instanceof PathRejection && error.reason === 'not-found'
    )
  })

  it('rejects a directory where a file is required', () => {
    const root = makeRoot()
    mkdirSync(join(root, 'sub'))

    assert.throws(
      () => resolveContainedPath(root, join(root, 'sub')),
      (error) => error instanceof PathRejection && error.reason === 'not-a-file'
    )
  })

  it('rejects a symlinked file even when the link itself sits inside the root', function (t) {
    const root = makeRoot()
    const target = join(makeRoot(), 'target.md')
    writeFileSync(target, '# Target\n')
    const link = join(root, 'link.md')

    try {
      symlinkSync(target, link, 'file')
    } catch {
      t.skip('symlink creation requires elevation or developer mode')
      return
    }

    assert.throws(
      () => resolveContainedPath(root, link),
      (error) => error instanceof PathRejection &&
        (error.reason === 'reparse-point' || error.reason === 'outside-root')
    )
  })

  it('rejects a file whose ancestor directory is a link', function (t) {
    const root = makeRoot()
    const realDirectory = join(makeRoot(), 'real')
    mkdirSync(realDirectory, { recursive: true })
    writeFileSync(join(realDirectory, 'concept.md'), '# Concept\n')
    const linkedDirectory = join(root, 'linked')

    try {
      symlinkSync(realDirectory, linkedDirectory, 'junction')
    } catch {
      t.skip('junction creation requires elevation or developer mode')
      return
    }

    assert.throws(
      () => resolveContainedPath(root, join(linkedDirectory, 'concept.md')),
      (error) => error instanceof PathRejection &&
        (error.reason === 'reparse-point' || error.reason === 'outside-root')
    )
  })

  it('rejects a path containing a NUL byte', () => {
    const root = makeRoot()

    assert.throws(
      () => resolveContainedPath(root, join(root, 'a\u0000b.md')),
      (error) => error instanceof PathRejection
    )
  })
})

describe('isContained', () => {
  it('treats the root itself as contained', () => {
    assert.equal(isContained('C:\\a\\b', 'C:\\a\\b'), true)
  })

  it('refuses a sibling with a shared prefix', () => {
    assert.equal(isContained(join('a', 'b'), join('a', 'bc', 'd')), false)
  })
})
