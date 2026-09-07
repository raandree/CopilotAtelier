import assert from 'node:assert/strict'
import { describe, it } from 'node:test'

import { createRenderer } from '../../src/render.mjs'

const renderer = createRenderer()

describe('createRenderer', () => {
  it('renders ordinary Markdown structure', () => {
    const result = renderer.render('## Scope\n\n- one\n- two\n')

    assert.match(result.html, /<h2/)
    assert.match(result.html, /<li>one<\/li>/)
  })

  it('renders a table', () => {
    const result = renderer.render('| a | b |\n|---|---|\n| 1 | 2 |\n')

    assert.match(result.html, /<table>/)
  })

  it('escapes raw HTML instead of parsing it', () => {
    const result = renderer.render('<b>bold</b>\n')

    assert.ok(!result.html.includes('<b>'))
    assert.match(result.html, /&lt;b&gt;/)
  })

  it('does not emit a script element for an inline script', () => {
    const result = renderer.render('<script>alert(1)</script>\n')

    assert.ok(!/<script/i.test(result.html))
  })

  it('drops an event handler attribute', () => {
    const result = renderer.render('<img src=x onerror="alert(1)">\n')

    assert.ok(!/<img/i.test(result.html))
    assert.match(result.html, /&lt;img/)
  })

  it('strips a javascript: link target', () => {
    const result = renderer.render('[click](javascript:alert(1))\n')

    assert.ok(!/href="javascript:/i.test(result.html))
    assert.ok(!/<a /i.test(result.html))
  })

  it('strips a data: link target', () => {
    const result = renderer.render('[click](data:text/html;base64,PHNjcmlwdD4=)\n')

    assert.ok(!/href="data:/i.test(result.html))
    assert.ok(!/<a /i.test(result.html))
  })

  it('keeps an http link but marks it as untrusted', () => {
    const result = renderer.render('[docs](https://example.com/a)\n')

    assert.match(result.html, /href="https:\/\/example\.com\/a"/)
    assert.match(result.html, /rel="noopener noreferrer nofollow"/)
  })

  it('refuses to load a remote image', () => {
    const result = renderer.render('![alt text](https://example.com/a.png)\n')

    assert.ok(!/<img/i.test(result.html))
    assert.match(result.html, /image not loaded/i)
    assert.match(result.html, /alt text/)
  })

  it('turns a mermaid fence into inert diagram source rather than markup', () => {
    const result = renderer.render('```mermaid\nflowchart TD\n  A --> B\n```\n')

    assert.equal(result.diagrams, 1)
    assert.match(result.html, /class="pr-diagram"/)
    assert.match(result.html, /flowchart TD/)
    assert.ok(!/<svg/i.test(result.html))
  })

  it('escapes hostile content inside a mermaid fence', () => {
    const result = renderer.render('```mermaid\nflowchart TD\n  A["<img src=x onerror=alert(1)>"] --> B\n```\n')

    assert.ok(!/<img/i.test(result.html))
    assert.match(result.html, /&lt;img src=x onerror=alert\(1\)&gt;/)
  })

  it('renders an ordinary code fence without treating it as a diagram', () => {
    const result = renderer.render('```powershell\nGet-ChildItem\n```\n')

    assert.equal(result.diagrams, 0)
    assert.match(result.html, /<code/)
  })

  it('is deterministic for the same input', () => {
    const first = renderer.render('# A\n\ntext\n')
    const second = renderer.render('# A\n\ntext\n')

    assert.equal(first.html, second.html)
  })
})
