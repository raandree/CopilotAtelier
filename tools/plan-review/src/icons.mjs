import * as lucide from 'lucide'

/**
 * Tool-button icons, taken from the Lucide set rather than drawn by hand. The
 * sprite is generated at start-up so the server serves one small SVG instead of
 * the whole icon package.
 */
export const ICON_NAME = Object.freeze({
  document: 'FileText',
  outline: 'ListTree',
  comment: 'MessageSquarePlus',
  approve: 'CircleCheck',
  changes: 'CircleAlert',
  stale: 'TriangleAlert',
  reload: 'RefreshCw',
  shutdown: 'Power',
  dismiss: 'X',
  submit: 'Send',
  pending: 'Clock',
  diagram: 'Workflow'
})

function renderNode ([tag, attributes, children = []]) {
  const serialized = Object.entries(attributes)
    .filter(([name]) => name !== 'xmlns')
    .map(([name, value]) => `${name}="${String(value).replace(/"/g, '&quot;')}"`)
    .join(' ')

  const inner = children.map(renderNode).join('')

  return inner.length > 0 ? `<${tag} ${serialized}>${inner}</${tag}>` : `<${tag} ${serialized}/>`
}

export function buildIconSprite () {
  const symbols = Object.entries(ICON_NAME).map(([slot, exportName]) => {
    const icon = lucide[exportName]

    if (!icon) {
      throw new Error(`icon "${exportName}" is not present in the installed Lucide package`)
    }

    const [, , children] = icon
    const body = children.map(renderNode).join('')

    return `<symbol id="icon-${slot}" viewBox="0 0 24 24" fill="none" stroke="currentColor" ` +
      `stroke-width="2" stroke-linecap="round" stroke-linejoin="round">${body}</symbol>`
  })

  return '<svg xmlns="http://www.w3.org/2000/svg" style="display:none">' +
    `${symbols.join('')}</svg>`
}
