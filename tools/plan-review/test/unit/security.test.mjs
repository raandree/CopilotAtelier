import assert from 'node:assert/strict'
import { Readable } from 'node:stream'
import { describe, it } from 'node:test'

import {
  BodyRejection,
  CSRF_HEADER_NAME,
  MAX_BODY_BYTES,
  SESSION_COOKIE_PREFIX,
  checkCsrf,
  checkFetchMetadata,
  checkHost,
  checkOrigin,
  checkSession,
  constantTimeEqual,
  createSecret,
  formatAuthority,
  guardMutation,
  isLoopbackAddress,
  parseCookies,
  readJsonBody,
  sessionCookieName
} from '../../src/security.mjs'

const cookieName = sessionCookieName('0123456789abcdef')

const context = {
  authorities: ['127.0.0.1:4711', 'localhost:4711'],
  origins: ['http://127.0.0.1:4711', 'http://localhost:4711'],
  sessionSecret: 'a'.repeat(64),
  csrfToken: 'b'.repeat(64),
  cookieName
}

function goodHeaders (overrides = {}) {
  return {
    host: '127.0.0.1:4711',
    origin: 'http://127.0.0.1:4711',
    'sec-fetch-site': 'same-origin',
    'content-type': 'application/json',
    cookie: `${cookieName}=${context.sessionSecret}`,
    [CSRF_HEADER_NAME]: context.csrfToken,
    ...overrides
  }
}

describe('sessionCookieName', () => {
  it('namespaces the cookie per launch', () => {
    assert.equal(sessionCookieName('0123456789abcdef'), `${SESSION_COOKIE_PREFIX}0123456789abcdef`)
    assert.notEqual(sessionCookieName('0123456789abcdef'), sessionCookieName('fedcba9876543210'))
  })

  it('refuses an identifier that is not a hexadecimal token', () => {
    assert.throws(() => sessionCookieName('not hex'), /hexadecimal/)
  })
})

describe('formatAuthority', () => {
  it('brackets an IPv6 host and leaves IPv4 alone', () => {
    assert.equal(formatAuthority('::1', 4711), '[::1]:4711')
    assert.equal(formatAuthority('127.0.0.1', 4711), '127.0.0.1:4711')
  })
})

describe('createSecret', () => {
  it('produces a long, unpredictable hex token', () => {
    const first = createSecret()
    const second = createSecret()

    assert.match(first, /^[0-9a-f]{64}$/)
    assert.notEqual(first, second)
  })
})

describe('constantTimeEqual', () => {
  it('matches equal strings and refuses unequal ones', () => {
    assert.equal(constantTimeEqual('abc', 'abc'), true)
    assert.equal(constantTimeEqual('abc', 'abd'), false)
    assert.equal(constantTimeEqual('abc', 'abcd'), false)
    assert.equal(constantTimeEqual('abc', undefined), false)
  })
})

describe('parseCookies', () => {
  it('parses a well formed cookie header', () => {
    assert.equal(parseCookies('a=1; b=2').b, '2')
  })

  it('returns an empty map for a missing header', () => {
    assert.deepEqual(Object.keys(parseCookies(undefined)), [])
  })

  it('ignores a malformed pair instead of throwing', () => {
    const cookies = parseCookies('novalue; a=1')

    assert.deepEqual(Object.keys(cookies), ['a'])
    assert.equal(cookies.a, '1')
  })

  it('returns a prototype-free map so a cookie cannot shadow Object members', () => {
    assert.equal(Object.getPrototypeOf(parseCookies('a=1')), null)
  })
})

describe('checkHost', () => {
  it('accepts the bound loopback authority', () => {
    assert.equal(checkHost(goodHeaders(), context.authorities).ok, true)
  })

  it('rejects a rebound external host header', () => {
    const result = checkHost(goodHeaders({ host: 'evil.example.com' }), context.authorities)

    assert.equal(result.ok, false)
    assert.equal(result.reason, 'host')
  })

  it('rejects the right host on the wrong port', () => {
    assert.equal(checkHost(goodHeaders({ host: '127.0.0.1:9999' }), context.authorities).ok, false)
  })

  it('rejects a missing host header', () => {
    assert.equal(checkHost({}, context.authorities).ok, false)
  })
})

describe('checkOrigin', () => {
  it('accepts the exact server origin', () => {
    assert.equal(checkOrigin(goodHeaders(), context.origins).ok, true)
  })

  it('rejects a cross-site origin', () => {
    const result = checkOrigin(goodHeaders({ origin: 'https://evil.example.com' }), context.origins)

    assert.equal(result.ok, false)
    assert.equal(result.reason, 'origin')
  })

  it('rejects an origin that only prefixes the allowed one', () => {
    assert.equal(
      checkOrigin(goodHeaders({ origin: 'http://127.0.0.1:4711.evil.example.com' }), context.origins).ok,
      false
    )
  })

  it('rejects the null origin', () => {
    assert.equal(checkOrigin(goodHeaders({ origin: 'null' }), context.origins).ok, false)
  })

  it('rejects a mutation with no origin header at all', () => {
    const headers = goodHeaders()
    delete headers.origin

    assert.equal(checkOrigin(headers, context.origins).ok, false)
  })
})

describe('checkFetchMetadata', () => {
  it('accepts same-origin', () => {
    assert.equal(checkFetchMetadata(goodHeaders()).ok, true)
  })

  it('rejects cross-site', () => {
    const result = checkFetchMetadata(goodHeaders({ 'sec-fetch-site': 'cross-site' }))

    assert.equal(result.ok, false)
    assert.equal(result.reason, 'fetch-site')
  })

  it('tolerates a client that does not send the header', () => {
    const headers = goodHeaders()
    delete headers['sec-fetch-site']

    assert.equal(checkFetchMetadata(headers).ok, true)
  })
})

describe('checkSession', () => {
  it('accepts the current session secret', () => {
    assert.equal(checkSession(goodHeaders(), context.sessionSecret, cookieName).ok, true)
  })

  it('rejects a secret minted by a previous server launch', () => {
    const previousLaunchSecret = 'c'.repeat(64)
    const headers = goodHeaders({ cookie: `${cookieName}=${previousLaunchSecret}` })

    const result = checkSession(headers, context.sessionSecret, cookieName)

    assert.equal(result.ok, false)
    assert.equal(result.reason, 'session')
  })

  it('ignores a cookie minted by another concurrent server', () => {
    const other = sessionCookieName('fedcba9876543210')
    const headers = goodHeaders({ cookie: `${other}=${context.sessionSecret}` })

    assert.equal(checkSession(headers, context.sessionSecret, cookieName).ok, false)
  })

  it('rejects a missing cookie', () => {
    const headers = goodHeaders()
    delete headers.cookie

    assert.equal(checkSession(headers, context.sessionSecret, cookieName).ok, false)
  })
})

describe('checkCsrf', () => {
  it('accepts the matching double-submit token', () => {
    assert.equal(checkCsrf(goodHeaders(), context.csrfToken).ok, true)
  })

  it('rejects a request that carries only the cookie', () => {
    const headers = goodHeaders()
    delete headers[CSRF_HEADER_NAME]

    const result = checkCsrf(headers, context.csrfToken)

    assert.equal(result.ok, false)
    assert.equal(result.reason, 'csrf')
  })

  it('rejects a forged token', () => {
    assert.equal(checkCsrf(goodHeaders({ [CSRF_HEADER_NAME]: 'd'.repeat(64) }), context.csrfToken).ok, false)
  })
})

describe('guardMutation', () => {
  it('accepts a same-origin request with a session and a token', () => {
    assert.equal(guardMutation(goodHeaders(), context).ok, true)
  })

  it('names the first failing gate', () => {
    assert.equal(guardMutation(goodHeaders({ host: 'evil.example.com' }), context).reason, 'host')
    assert.equal(guardMutation(goodHeaders({ origin: 'https://evil.example.com' }), context).reason, 'origin')
  })

  it('rejects a non-JSON content type', () => {
    const result = guardMutation(goodHeaders({ 'content-type': 'text/plain' }), context)

    assert.equal(result.ok, false)
    assert.equal(result.reason, 'content-type')
  })

  it('accepts a JSON content type that carries a charset', () => {
    assert.equal(guardMutation(goodHeaders({ 'content-type': 'application/json; charset=utf-8' }), context).ok, true)
  })
})

describe('isLoopbackAddress', () => {
  it('accepts loopback literals only', () => {
    assert.equal(isLoopbackAddress('127.0.0.1'), true)
    assert.equal(isLoopbackAddress('::1'), true)
    assert.equal(isLoopbackAddress('0.0.0.0'), false)
    assert.equal(isLoopbackAddress('::'), false)
    assert.equal(isLoopbackAddress('192.168.1.10'), false)
    assert.equal(isLoopbackAddress(''), false)
  })
})

describe('readJsonBody', () => {
  function streamOf (text) {
    const stream = Readable.from([Buffer.from(text, 'utf8')])
    return stream
  }

  it('parses a bounded JSON object', async () => {
    const parsed = await readJsonBody(streamOf('{"a":1}'), { 'content-length': '7' })

    assert.deepEqual(parsed, { a: 1 })
  })

  it('rejects a declared length over the bound before reading', async () => {
    await assert.rejects(
      () => readJsonBody(streamOf('{}'), { 'content-length': String(MAX_BODY_BYTES + 1) }),
      (error) => error instanceof BodyRejection && error.reason === 'too-large'
    )
  })

  it('rejects a body that exceeds the bound while streaming', async () => {
    const oversized = `{"a":"${'x'.repeat(MAX_BODY_BYTES + 16)}"}`

    await assert.rejects(
      () => readJsonBody(streamOf(oversized), {}),
      (error) => error instanceof BodyRejection && error.reason === 'too-large'
    )
  })

  it('rejects malformed JSON', async () => {
    await assert.rejects(
      () => readJsonBody(streamOf('{nope'), {}),
      (error) => error instanceof BodyRejection && error.reason === 'invalid-json'
    )
  })

  it('rejects a JSON array or scalar where an object is required', async () => {
    await assert.rejects(
      () => readJsonBody(streamOf('[1,2]'), {}),
      (error) => error instanceof BodyRejection && error.reason === 'not-an-object'
    )
  })

  it('rejects a prototype pollution attempt', async () => {
    await assert.rejects(
      () => readJsonBody(streamOf('{"__proto__":{"polluted":true}}'), {}),
      (error) => error instanceof BodyRejection && error.reason === 'forbidden-key'
    )
  })
})
