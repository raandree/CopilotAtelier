import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import { mkdirSync, mkdtempSync, realpathSync, rmSync, symlinkSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { it } from 'node:test'
import { fileURLToPath } from 'node:url'

it('runs filesystem suites through a linked temporary directory', (context) => {
  const workspace = realpathSync.native(mkdtempSync(join(tmpdir(), 'plan-review-temp-alias-')))
  context.after(() => rmSync(workspace, { recursive: true, force: true }))

  const target = join(workspace, 'target')
  const alias = join(workspace, 'alias')
  mkdirSync(target)
  symlinkSync(target, alias, 'junction')

  const testFiles = [
    'document.test.mjs',
    'paths.test.mjs',
    'store-capacity.test.mjs',
    'store-integrity.test.mjs',
    'store.test.mjs'
  ].map((name) => `test/unit/${name}`)

  const environment = { ...process.env, TMPDIR: alias, TMP: alias, TEMP: alias }
  delete environment.NODE_TEST_CONTEXT

  const result = spawnSync(process.execPath, ['--test', '--test-reporter=tap', ...testFiles], {
    cwd: fileURLToPath(new URL('../..', import.meta.url)),
    env: environment,
    encoding: 'utf8',
    timeout: 60000
  })

  assert.ifError(result.error)
  assert.match(result.stdout, /^# tests [1-9][0-9]*$/m, result.stderr)
  assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`)
})
