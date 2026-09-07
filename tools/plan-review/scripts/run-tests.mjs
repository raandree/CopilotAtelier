import { readdirSync } from 'node:fs'
import { join } from 'node:path'
import { spawnSync } from 'node:child_process'
import { fileURLToPath } from 'node:url'

const root = fileURLToPath(new URL('../test/', import.meta.url))
const scopes = process.argv.slice(2)
if (scopes.length === 0 || scopes.some((scope) => !['unit', 'integration'].includes(scope))) {
  throw new Error('Select unit, integration, or both test suites.')
}

const files = scopes.flatMap((scope) => readdirSync(join(root, scope), { withFileTypes: true })
  .filter((entry) => entry.isFile() && entry.name.endsWith('.test.mjs'))
  .map((entry) => join(root, scope, entry.name)))
if (files.length === 0) throw new Error('No test files were found.')

const result = spawnSync(process.execPath, ['--test', ...files.sort()], { stdio: 'inherit' })
if (result.error) throw result.error
process.exitCode = result.status ?? 1
