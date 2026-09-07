import createDomPurify from 'dompurify'
import { JSDOM } from 'jsdom'
import MarkdownIt from 'markdown-it'

export const ALLOWED_TAGS = [
  'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
  'p', 'blockquote', 'pre', 'code', 'em', 'strong', 'del', 'sub', 'sup',
  'ul', 'ol', 'li', 'hr', 'br', 'a', 'span', 'div',
  'table', 'thead', 'tbody', 'tr', 'th', 'td'
]

export const ALLOWED_ATTR = ['href', 'title', 'class', 'rel', 'target', 'align', 'id']

// Only these schemes survive sanitization. Everything else, including
// javascript:, data: and vbscript:, is removed rather than rewritten.
const SAFE_URI = /^(?:https?:|mailto:|#)/i

function escapeHtml (text) {
  return String(text)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;')
}

/**
 * Markdown rendering for untrusted document bytes. Raw HTML is disabled at the
 * parser, so sanitization is defence in depth rather than the only control.
 */
export function createRenderer () {
  const markdown = new MarkdownIt({
    html: false,
    linkify: false,
    typographer: false,
    breaks: false
  })

  let diagramCount = 0

  const defaultFence = markdown.renderer.rules.fence

  markdown.renderer.rules.fence = (tokens, index, options, env, self) => {
    const token = tokens[index]
    const info = (token.info || '').trim().split(/\s+/)[0].toLowerCase()

    if (info !== 'mermaid') {
      return defaultFence(tokens, index, options, env, self)
    }

    diagramCount += 1

    // The diagram source stays text. The browser reads it with textContent and
    // hands it to Mermaid in strict mode; it is never inserted as markup here.
    return `<div class="pr-diagram" data-diagram="${diagramCount}">` +
      `<pre class="pr-diagram-source">${escapeHtml(token.content)}</pre>` +
      '</div>\n'
  }

  // An image would be an implicit external load, which the trust boundary
  // forbids. Render the alternative text instead of fetching anything.
  markdown.renderer.rules.image = (tokens, index) => {
    const alt = tokens[index].content || tokens[index].attrGet('alt') || ''
    return `<span class="pr-image-blocked">[image not loaded: ${escapeHtml(alt)}]</span>`
  }

  const defaultLinkOpen = markdown.renderer.rules.link_open ??
    ((tokens, index, options, env, self) => self.renderToken(tokens, index, options))

  markdown.renderer.rules.link_open = (tokens, index, options, env, self) => {
    const href = tokens[index].attrGet('href') ?? ''

    if (!SAFE_URI.test(href)) {
      tokens[index].attrSet('href', '#')
      tokens[index].attrJoin('class', 'pr-link-blocked')
    }

    tokens[index].attrSet('rel', 'noopener noreferrer nofollow')
    tokens[index].attrSet('target', '_blank')

    return defaultLinkOpen(tokens, index, options, env, self)
  }

  const window = new JSDOM('').window
  const purify = createDomPurify(window)

  purify.addHook('afterSanitizeAttributes', (node) => {
    if (node.tagName === 'A' && node.hasAttribute('target')) {
      node.setAttribute('rel', 'noopener noreferrer nofollow')
    }
  })

  return {
    render (source) {
      diagramCount = 0

      const raw = markdown.render(String(source ?? ''))
      const html = purify.sanitize(raw, {
        ALLOWED_TAGS,
        ALLOWED_ATTR: [...ALLOWED_ATTR, 'data-diagram'],
        ALLOWED_URI_REGEXP: SAFE_URI,
        // A custom URI regexp makes DOMPurify apply it to every attribute that
        // is not declared URI-safe, which silently drops these non-URI ones.
        ADD_URI_SAFE_ATTR: ['rel', 'target', 'class', 'id', 'title', 'align', 'data-diagram'],
        FORBID_TAGS: ['img', 'svg', 'math', 'style', 'script', 'iframe', 'object', 'embed', 'form', 'input'],
        FORBID_ATTR: ['style', 'srcset', 'formaction', 'xlink:href'],
        ALLOW_DATA_ATTR: false,
        ALLOW_ARIA_ATTR: false,
        KEEP_CONTENT: true
      })

      return { html, diagrams: diagramCount }
    }
  }
}
