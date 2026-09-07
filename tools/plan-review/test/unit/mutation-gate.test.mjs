import assert from 'node:assert/strict'
import { describe, it } from 'node:test'

import { CSRF_HEADER_NAME, guardMutation, sessionCookieName } from '../../src/security.mjs'

// The cookie is named per launch, so the gate is exercised through the same
// name the server derives rather than a fixed constant.
const cookieName = sessionCookieName('a1b2c3d4')

const context = {
  authorities: ['127.0.0.1:8080'],
  origins: ['http://127.0.0.1:8080'],
  sessionSecret: 'a'.repeat(64),
  csrfToken: 'b'.repeat(64),
  cookieName
}

function headers (overrides = {}) {
  const complete = {
    host: '127.0.0.1:8080',
    origin: 'http://127.0.0.1:8080',
    'sec-fetch-site': 'same-origin',
    'content-type': 'application/json',
    cookie: `${cookieName}=${context.sessionSecret}`,
    [CSRF_HEADER_NAME]: context.csrfToken
  }

  for (const [name, value] of Object.entries(overrides)) {
    if (value === undefined) {
      delete complete[name]
    } else {
      complete[name] = value
    }
  }

  return complete
}

/*
  Each case violates exactly one gate, so dropping any single check from
  guardMutation turns a rejection into an acceptance and fails here. This is the
  behavioural half of the repository gate; it needs no installed dependency.
*/
const violation = [
  { gate: 'host', reason: 'host', overrides: { host: 'plan-review.example:8080' } },
  { gate: 'host (absent)', reason: 'host', overrides: { host: undefined } },
  { gate: 'origin', reason: 'origin', overrides: { origin: 'http://evil.example' } },
  { gate: 'origin (absent)', reason: 'origin', overrides: { origin: undefined } },
  { gate: 'fetch metadata', reason: 'fetch-site', overrides: { 'sec-fetch-site': 'cross-site' } },
  { gate: 'content type', reason: 'content-type', overrides: { 'content-type': 'text/plain' } },
  { gate: 'content type (absent)', reason: 'content-type', overrides: { 'content-type': undefined } },
  { gate: 'session', reason: 'session', overrides: { cookie: `${cookieName}=${'c'.repeat(64)}` } },
  { gate: 'session (absent)', reason: 'session', overrides: { cookie: undefined } },
  {
    gate: 'session (another launch)',
    reason: 'session',
    overrides: { cookie: `${sessionCookieName('99887766')}=${'a'.repeat(64)}` }
  },
  { gate: 'csrf', reason: 'csrf', overrides: { [CSRF_HEADER_NAME]: 'c'.repeat(64) } },
  { gate: 'csrf (absent)', reason: 'csrf', overrides: { [CSRF_HEADER_NAME]: undefined } }
]

describe('guardMutation', () => {
  it('admits a request that clears every gate', () => {
    assert.deepEqual(guardMutation(headers(), context), { ok: true, reason: null })
  })

  it('admits a request without Sec-Fetch-Site, which not every client sends', () => {
    assert.equal(guardMutation(headers({ 'sec-fetch-site': undefined }), context).ok, true)
  })

  for (const { gate, reason, overrides } of violation) {
    it(`refuses a mutation that fails the ${gate} gate`, () => {
      const result = guardMutation(headers(overrides), context)

      assert.equal(result.ok, false)
      assert.equal(result.reason, reason)
    })
  }

  it('refuses a request with no headers at all', () => {
    assert.equal(guardMutation({}, context).ok, false)
  })
})
