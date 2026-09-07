import { existsSync, readdirSync } from 'node:fs'
import { join } from 'node:path'
import { spawnSync } from 'node:child_process'
import { fileURLToPath } from 'node:url'

const root = fileURLToPath(new URL('../', import.meta.url))
const pending = ['src', 'assets', 'browser', 'test', 'scripts'].map((directory) => join(root, directory))
let checked = 0

while (pending.length > 0) {
  const directory = pending.pop()
  if (!existsSync(directory)) continue

  for (const entry of readdirSync(directory, { withFileTypes: true })) {
    const path = join(directory, entry.name)
    if (entry.isDirectory()) {
      pending.push(path)
    } else if (entry.isFile() && entry.name.endsWith('.mjs')) {
      const result = spawnSync(process.execPath, ['--check', path], { stdio: 'inherit' })
      if (result.error) throw result.error
      if (result.status !== 0) process.exit(result.status ?? 1)
      checked += 1
    }
  }
}

console.log(`Syntax checks passed for ${checked} JavaScript files.`)
