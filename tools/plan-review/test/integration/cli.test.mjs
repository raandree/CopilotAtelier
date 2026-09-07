import assert from 'node:assert/strict'
import { spawn } from 'node:child_process'
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs'
import { createServer } from 'node:http'
import { tmpdir } from 'node:os'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { after, before, describe, it } from 'node:test'

const cli = join(dirname(fileURLToPath(import.meta.url)), '..', '..', 'src', 'cli.mjs')

function runCli (args) {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [cli, ...args], { stdio: ['ignore', 'pipe', 'pipe'] })
    let stdout = ''
    let stderr = ''

    child.stdout.on('data', (chunk) => { stdout += chunk })
    child.stderr.on('data', (chunk) => { stderr += chunk })
    child.on('error', reject)
    child.on('close', (code) => resolve({ code, stdout, stderr }))
  })
}

describe('cli start-up failures', () => {
  let occupied
  let port
  let documentPath
  let workspace

  before(async () => {
    workspace = mkdtempSync(join(tmpdir(), 'plan-review-cli-'))
    documentPath = join(workspace, 'concept.md')
    writeFileSync(documentPath, '# Concept\n\nBody.\n', 'utf8')

    occupied = createServer(() => {})
    await new Promise((resolve) => occupied.listen(0, '127.0.0.1', resolve))
    port = occupied.address().port
  })

  after(async () => {
    await new Promise((resolve) => occupied.close(resolve))
    rmSync(workspace, { recursive: true, force: true })
  })

  it('reports an occupied port through its own error path', async () => {
    const result = await runCli(['--document', documentPath, '--port', String(port)])

    assert.equal(result.code, 1)
    assert.match(result.stderr, /^refused to start: /)
    assert.match(result.stderr, /EADDRINUSE/)
    assert.ok(!/at .*node:net/.test(result.stderr), 'a Node-internal stack trace reached the user')
  })

  it('reports an unusable port number through its own error path', async () => {
    const result = await runCli(['--document', documentPath, '--port', '70000'])

    assert.equal(result.code, 1)
    assert.match(result.stderr, /^refused to start: /)
  })

  it('refuses an unreadable document without a stack trace', async () => {
    const result = await runCli(['--document', join(tmpdir(), 'plan-review-missing-concept.md')])

    assert.equal(result.code, 1)
    assert.match(result.stderr, /^refused to start: /)
  })

  it('names the reason when a document cannot be split into anchorable sections', async () => {
    const nested = join(workspace, 'nested.md')
    writeFileSync(nested, '# Purpose\n\nBody.\n\n> ## Quoted risk\n>\n> Quoted body.\n', 'utf8')

    const result = await runCli(['--document', nested])

    assert.equal(result.code, 1)
    assert.match(result.stderr, /^refused to start: /)
    assert.match(result.stderr, /heading-structure/)
  })
})
