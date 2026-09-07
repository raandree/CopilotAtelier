import { resolve } from 'node:path'

import { DocumentRejection } from './document.mjs'
import { PathRejection, directoryOf, resolveRoot } from './paths.mjs'
import { DEFAULT_TTL_SECONDS, MAX_TTL_SECONDS, createReviewServer } from './server.mjs'
import { StoreRejection } from './store.mjs'

const USAGE = `
Local plan review — render a Design Concept, collect anchored comments, and
record a verdict against one revision. Feedback only; sign-off stays in chat.

  node src/cli.mjs --document <file.md> [options]

  --document <path>   Markdown file to open. Repeat for several documents.
                      Only these files are ever readable.
  --root <dir>        Containment root. Default: the first document's folder.
  --state <dir>       Feedback store. Default: <root>/.copilot-atelier/plan-review
  --port <number>     Loopback port. Default: 0 (an unused port).
  --ttl <seconds>     Bounded lifetime, 1..${MAX_TTL_SECONDS}. Default: ${DEFAULT_TTL_SECONDS}.
  --help              Show this text.
`.trimStart()

export function parseArguments (argv) {
  const options = { documents: [], root: null, state: null, port: 0, ttlSeconds: DEFAULT_TTL_SECONDS, help: false }

  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index]
    const value = argv[index + 1]

    switch (argument) {
      case '--help':
      case '-h':
        options.help = true
        break
      case '--document':
        requireValue(argument, value)
        options.documents.push(resolve(value))
        index += 1
        break
      case '--root':
        requireValue(argument, value)
        options.root = resolve(value)
        index += 1
        break
      case '--state':
        requireValue(argument, value)
        options.state = resolve(value)
        index += 1
        break
      case '--port':
        requireValue(argument, value)
        options.port = Number(value)
        index += 1
        break
      case '--ttl':
        requireValue(argument, value)
        options.ttlSeconds = Number(value)
        index += 1
        break
      default:
        throw new Error(`unknown argument: ${argument}`)
    }
  }

  return options
}

function requireValue (argument, value) {
  if (value === undefined || value.startsWith('--')) {
    throw new Error(`${argument} requires a value`)
  }
}

export async function main (argv = process.argv.slice(2)) {
  let options

  try {
    options = parseArguments(argv)
  } catch (error) {
    process.stderr.write(`${error.message}\n\n${USAGE}`)
    return 2
  }

  if (options.help || options.documents.length === 0) {
    process.stdout.write(USAGE)
    return options.help ? 0 : 2
  }

  const root = resolveRoot(options.root ?? directoryOf(options.documents[0]))
  const stateRoot = options.state ?? resolve(root, '.copilot-atelier', 'plan-review')

  let server

  try {
    server = createReviewServer({
      documents: options.documents.map((path) => ({ root, path })),
      stateRoot,
      port: Number.isFinite(options.port) ? options.port : 0,
      ttlSeconds: options.ttlSeconds
    })

    // A failed bind is the most common start-up failure, so it has to reach the
    // same diagnostic as a refused path rather than an unhandled rejection.
    await server.listen()
  } catch (error) {
    if (error instanceof PathRejection || error instanceof StoreRejection || error instanceof DocumentRejection) {
      process.stderr.write(`refused to start: ${error.message} (${error.reason})\n`)
      return 1
    }

    const detail = error.code ? `${error.message} (${error.code})` : error.message
    process.stderr.write(`refused to start: ${detail}\n`)
    return 1
  }

  const stop = () => { server.close() }
  process.on('SIGINT', stop)
  process.on('SIGTERM', stop)

  process.stdout.write([
    '',
    'Plan review is running.',
    '',
    `  URL          ${server.url}`,
    `  Documents    ${server.documents.map((entry) => entry.name).join(', ')}`,
    `  Root         ${root}`,
    `  State        ${stateRoot}`,
    `  Expires      ${server.expiresAt.toISOString()} (${server.ttlSeconds}s)`,
    `  Process id   ${process.pid}`,
    '',
    'The URL carries a per-launch session key. Anything recorded in the browser is',
    'review feedback, not sign-off, and never starts implementation.',
    '',
    'To stop it: press Ctrl+C, use the "Stop server" button in the page, or run',
    `  Stop-Process -Id ${process.pid}`,
    ''
  ].join('\n'))

  await server.stopped
  process.stdout.write('Plan review stopped.\n')

  return 0
}

if (import.meta.url === `file://${process.argv[1]}` || process.argv[1]?.endsWith('cli.mjs')) {
  main().then((code) => {
    process.exitCode = code
  }).catch((error) => {
    process.stderr.write(`refused to start: ${error.message}\n`)
    process.exitCode = 1
  })
}
