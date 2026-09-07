import { randomBytes, timingSafeEqual } from 'node:crypto'

export const SESSION_COOKIE_NAME = 'plan_review_session'
export const CSRF_HEADER_NAME = 'x-csrf-token'
export const MAX_BODY_BYTES = 65536

const FORBIDDEN_KEY = new Set(['__proto__', 'constructor', 'prototype'])

export class BodyRejection extends Error {
  constructor (message, reason) {
    super(message)
    this.name = 'BodyRejection'
    this.reason = reason
  }
}

const ok = { ok: true, reason: null }

function deny (reason) {
  return { ok: false, reason }
}

export function createSecret (bytes = 32) {
  return randomBytes(bytes).toString('hex')
}

export function constantTimeEqual (left, right) {
  if (typeof left !== 'string' || typeof right !== 'string') {
    return false
  }

  const leftBuffer = Buffer.from(left, 'utf8')
  const rightBuffer = Buffer.from(right, 'utf8')

  if (leftBuffer.length !== rightBuffer.length) {
    return false
  }

  return timingSafeEqual(leftBuffer, rightBuffer)
}

export function parseCookies (header) {
  const cookies = Object.create(null)

  if (typeof header !== 'string') {
    return cookies
  }

  for (const part of header.split(';')) {
    const separator = part.indexOf('=')

    if (separator <= 0) {
      continue
    }

    const name = part.slice(0, separator).trim()
    const value = part.slice(separator + 1).trim()

    if (name.length > 0 && !FORBIDDEN_KEY.has(name)) {
      cookies[name] = value
    }
  }

  return cookies
}

export function isLoopbackAddress (address) {
  return address === '127.0.0.1' || address === '::1'
}

export function checkHost (headers, authorities) {
  const host = headers?.host

  if (typeof host !== 'string' || !authorities.includes(host.toLowerCase())) {
    return deny('host')
  }

  return ok
}

export function checkOrigin (headers, origins) {
  const origin = headers?.origin

  if (typeof origin !== 'string' || !origins.includes(origin.toLowerCase())) {
    return deny('origin')
  }

  return ok
}

export function checkFetchMetadata (headers) {
  const site = headers?.['sec-fetch-site']

  if (site === undefined) {
    return ok
  }

  return site === 'same-origin' || site === 'none' ? ok : deny('fetch-site')
}

export function checkSession (headers, sessionSecret) {
  const presented = parseCookies(headers?.cookie)[SESSION_COOKIE_NAME]

  return constantTimeEqual(presented, sessionSecret) ? ok : deny('session')
}

export function checkCsrf (headers, csrfToken) {
  return constantTimeEqual(headers?.[CSRF_HEADER_NAME], csrfToken) ? ok : deny('csrf')
}

export function checkContentType (headers) {
  const value = headers?.['content-type']

  if (typeof value !== 'string') {
    return deny('content-type')
  }

  return value.split(';')[0].trim().toLowerCase() === 'application/json' ? ok : deny('content-type')
}

/**
 * Every gate a mutating request must clear, in the order that gives the most
 * useful rejection reason. Loopback binding is not one of them: it reduces
 * reachability and is not an authorization check.
 */
export function guardMutation (headers, context) {
  const gate = [
    () => checkHost(headers, context.authorities),
    () => checkOrigin(headers, context.origins),
    () => checkFetchMetadata(headers),
    () => checkContentType(headers),
    () => checkSession(headers, context.sessionSecret),
    () => checkCsrf(headers, context.csrfToken)
  ]

  for (const check of gate) {
    const result = check()

    if (!result.ok) {
      return result
    }
  }

  return ok
}

function assertNoForbiddenKey (value, depth = 0) {
  if (depth > 8 || value === null || typeof value !== 'object') {
    return
  }

  for (const key of Object.keys(value)) {
    if (FORBIDDEN_KEY.has(key)) {
      throw new BodyRejection(`forbidden property name: ${key}`, 'forbidden-key')
    }

    assertNoForbiddenKey(value[key], depth + 1)
  }
}

export async function readJsonBody (stream, headers = {}, { limit = MAX_BODY_BYTES } = {}) {
  const declared = Number(headers['content-length'])

  if (Number.isFinite(declared) && declared > limit) {
    throw new BodyRejection('declared body length exceeds the bound', 'too-large')
  }

  const chunks = []
  let total = 0

  for await (const chunk of stream) {
    total += chunk.length

    if (total > limit) {
      if (typeof stream.destroy === 'function') {
        stream.destroy()
      }

      throw new BodyRejection('body exceeds the bound', 'too-large')
    }

    chunks.push(chunk)
  }

  const text = Buffer.concat(chunks).toString('utf8')

  if (text.trim().length === 0) {
    throw new BodyRejection('body is empty', 'invalid-json')
  }

  // Scan the raw text as well: JSON.parse silently discards a literal
  // "__proto__" key, so the parsed object alone cannot prove it was absent.
  if (/"__proto__"\s*:/.test(text)) {
    throw new BodyRejection('forbidden property name: __proto__', 'forbidden-key')
  }

  let parsed
  try {
    parsed = JSON.parse(text)
  } catch {
    throw new BodyRejection('body is not valid JSON', 'invalid-json')
  }

  if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) {
    throw new BodyRejection('body must be a JSON object', 'not-an-object')
  }

  assertNoForbiddenKey(parsed)

  return parsed
}
