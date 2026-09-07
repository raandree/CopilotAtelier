const state = {
  csrfToken: null,
  documentId: null,
  documentName: null,
  revision: null,
  sections: [],
  focusIndex: 0,
  // Every document load takes a ticket. A response that comes back after the
  // selection moved on is discarded rather than rendered under the new choice.
  generation: 0
}

const element = {
  sprite: document.getElementById('icon-sprite'),
  title: document.getElementById('doc-title'),
  name: document.getElementById('doc-name'),
  revision: document.getElementById('doc-revision'),
  status: document.getElementById('verdict-status'),
  statusText: document.getElementById('verdict-status-text'),
  outlineDetails: document.getElementById('outline-details'),
  outline: document.getElementById('outline-list'),
  sections: document.getElementById('sections'),
  banner: document.getElementById('banner'),
  orphaned: document.getElementById('orphaned'),
  orphanedList: document.getElementById('orphaned-list'),
  staleDrafts: document.getElementById('stale-drafts'),
  staleDraftsList: document.getElementById('stale-drafts-list'),
  staleDraftsDiscardAll: document.getElementById('stale-drafts-discard-all'),
  dialog: document.getElementById('verdict-dialog'),
  dialogBody: document.getElementById('verdict-dialog-body'),
  dialogNote: document.getElementById('verdict-note'),
  dialogConfirm: document.getElementById('verdict-confirm'),
  dialogCancel: document.getElementById('verdict-cancel')
}

const DRAFT_PREFIX = 'plan-review-draft:'
const NOTE_PREFIX = 'plan-review-note:'

function draftKey (documentId, revision, sectionKey) {
  return `${DRAFT_PREFIX}${documentId}:${revision}:${sectionKey}`
}

function noteKey (documentId) {
  return `${NOTE_PREFIX}${documentId}`
}

function storageKeys () {
  try {
    return Object.keys(sessionStorage)
  } catch {
    return []
  }
}

function storageGet (key) {
  try {
    return sessionStorage.getItem(key)
  } catch {
    return null
  }
}

function storageSet (key, value) {
  try {
    sessionStorage.setItem(key, value)
    return true
  } catch {
    return false
  }
}

function storageRemove (key) {
  try {
    sessionStorage.removeItem(key)
  } catch {
    // Nothing to remove when the tab denies storage.
  }
}

const VERDICT_LABEL = {
  approved: 'Approved (feedback)',
  'changes-requested': 'Changes requested'
}

const COMMENT_STATE_LABEL = {
  current: 'Current',
  revised: 'Section revised',
  orphaned: 'Unanchored'
}

function showBanner (message) {
  element.banner.textContent = message
  element.banner.hidden = false
}

function clearBanner () {
  element.banner.hidden = true
  element.banner.textContent = ''
}

function icon (slot) {
  const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg')
  svg.setAttribute('class', 'icon')
  svg.setAttribute('aria-hidden', 'true')
  const use = document.createElementNS('http://www.w3.org/2000/svg', 'use')
  use.setAttribute('href', `#icon-${slot}`)
  svg.append(use)
  return svg
}

async function api (path, options = {}) {
  let response
  try {
    response = await fetch(path, {
      credentials: 'same-origin',
      ...options,
      headers: {
        ...(options.body ? { 'content-type': 'application/json' } : {}),
        ...(state.csrfToken ? { 'x-csrf-token': state.csrfToken } : {}),
        ...options.headers
      }
    })
  } catch {
    showBanner('The connection is unavailable. Pending text is retained; retry when the server is reachable.')
    return { status: 0, ok: false, payload: { reason: 'connection unavailable' } }
  }

  const payload = response.status === 204 ? {} : await response.json().catch(() => ({}))

  return { status: response.status, ok: response.ok, payload }
}

async function loadSprite () {
  const response = await fetch('/icons.svg', { credentials: 'same-origin' })
  const text = await response.text()
  const parsed = new DOMParser().parseFromString(text, 'image/svg+xml')

  if (parsed.documentElement.nodeName !== 'parsererror') {
    element.sprite.append(document.importNode(parsed.documentElement, true))
  }
}

function sanitize (html) {
  return window.DOMPurify.sanitize(html, {
    ALLOWED_TAGS: [
      'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'p', 'blockquote', 'pre', 'code',
      'em', 'strong', 'del', 'sub', 'sup', 'ul', 'ol', 'li', 'hr', 'br', 'a',
      'span', 'div', 'table', 'thead', 'tbody', 'tr', 'th', 'td'
    ],
    ALLOWED_ATTR: ['href', 'title', 'class', 'rel', 'target', 'align', 'id', 'data-diagram'],
    ADD_URI_SAFE_ATTR: ['rel', 'target', 'class', 'id', 'title', 'align', 'data-diagram'],
    ALLOWED_URI_REGEXP: /^(?:https?:|mailto:|#)/i,
    ALLOW_DATA_ATTR: false
  })
}

function renderOutline (sections) {
  element.outline.replaceChildren()

  sections.forEach((section, index) => {
    const item = document.createElement('li')
    item.dataset.level = String(Math.max(section.level, 2))

    const link = document.createElement('a')
    link.href = `#section-${section.key}`
    link.textContent = section.heading ?? 'Preamble'
    link.addEventListener('click', () => { state.focusIndex = index })

    item.append(link)
    element.outline.append(item)
  })
}

function renderComment (comment) {
  const item = document.createElement('li')
  item.className = 'comment'
  item.dataset.state = comment.state
  item.dataset.commentId = comment.id

  const head = document.createElement('div')
  head.className = 'comment-head'

  const badge = document.createElement('span')
  badge.className = 'comment-state'
  badge.textContent = COMMENT_STATE_LABEL[comment.state] ?? comment.state
  head.append(badge)

  const when = document.createElement('span')
  when.textContent = new Date(comment.createdAt).toLocaleString()
  head.append(when)

  if (comment.state === 'orphaned' && comment.headingText) {
    const origin = document.createElement('span')
    origin.textContent = `written on “${comment.headingText}”`
    head.append(origin)
  }

  const body = document.createElement('p')
  body.className = 'comment-body'
  body.textContent = comment.body

  item.append(head, body)
  return item
}

function renderComposer (section) {
  const composer = document.createElement('div')
  composer.className = 'composer'
  composer.hidden = true
  const documentId = state.documentId
  const documentHash = state.revision
  const key = draftKey(documentId, documentHash, section.key)

  const label = document.createElement('label')
  label.className = 'hint'
  label.setAttribute('for', `composer-${section.key}`)
  label.textContent = `Comment on “${section.heading ?? 'Preamble'}”`

  const input = document.createElement('textarea')
  input.id = `composer-${section.key}`
  input.rows = 3
  input.maxLength = 4000
  input.value = storageGet(key)?.slice(0, input.maxLength) ?? ''
  composer.hidden = input.value.length === 0

  function saveDraft () {
    if (input.value.length === 0) {
      storageRemove(key)
      return
    }

    if (!storageSet(key, input.value.slice(0, input.maxLength))) {
      showBanner('This draft could not be saved in the tab. Keep the page open until it is submitted.')
    }
  }

  input.addEventListener('input', saveDraft)

  const actions = document.createElement('div')
  actions.className = 'composer-actions'

  const submit = document.createElement('button')
  submit.type = 'button'
  submit.className = 'button'
  submit.dataset.action = 'submit-comment'
  submit.append(icon('submit'), Object.assign(document.createElement('span'), { textContent: 'Add comment' }))

  const cancel = document.createElement('button')
  cancel.type = 'button'
  cancel.className = 'button button-quiet'
  cancel.dataset.action = 'cancel-comment'
  cancel.append(icon('dismiss'), Object.assign(document.createElement('span'), { textContent: 'Cancel' }))

  actions.append(submit, cancel)
  composer.append(label, input, actions)

  submit.addEventListener('click', async () => {
    const body = input.value.trim()

    if (body.length === 0) {
      return
    }

    submit.disabled = true
    const result = await api(`/api/document/${documentId}/comment`, {
      method: 'POST',
      body: JSON.stringify({
        sectionKey: section.key,
        sectionHash: section.hash,
        headingText: section.heading,
        documentHash,
        body
      })
    })
    submit.disabled = false

    if (result.status === 201) {
      input.value = ''
      saveDraft()
      composer.hidden = true
      await loadDocument()

      if (result.payload.state === 'superseded') {
        showBanner('The comment was recorded, but the document changed while it was being written. Read the current revision.')
      }

      return
    }

    if (result.status === 409) {
      showBanner(result.payload.state === 'unknown-section'
        ? 'That section is no longer in the document. The comment was not recorded.'
        : 'The document changed on disk. Reload before commenting again.')
      return
    }

    showBanner(`The comment was not recorded (${result.payload.reason ?? result.status}).`)
  })

  cancel.addEventListener('click', () => {
    composer.hidden = true
  })

  return composer
}

function renderSection (section, comments) {
  const article = document.createElement('section')
  article.className = 'section'
  article.id = `section-${section.key}`
  article.tabIndex = -1
  article.dataset.sectionKey = section.key

  const body = document.createElement('div')
  body.className = 'section-body'
  body.innerHTML = sanitize(section.html)

  const tools = document.createElement('div')
  tools.className = 'section-tools'

  const commentButton = document.createElement('button')
  commentButton.type = 'button'
  commentButton.className = 'button button-quiet'
  commentButton.dataset.action = 'open-composer'
  commentButton.title = `Add a comment anchored to “${section.heading ?? 'Preamble'}” (c)`
  commentButton.setAttribute('aria-keyshortcuts', 'c')
  commentButton.append(icon('comment'), Object.assign(document.createElement('span'), { textContent: 'Comment' }))

  tools.append(commentButton)

  const composer = renderComposer(section)

  commentButton.addEventListener('click', () => {
    composer.hidden = !composer.hidden

    if (!composer.hidden) {
      composer.querySelector('textarea').focus()
    }
  })

  const list = document.createElement('ul')
  list.className = 'comment-list'

  for (const comment of comments) {
    list.append(renderComment(comment))
  }

  article.append(body, tools, composer, list)
  return article
}

async function renderDiagrams (root) {
  const diagrams = [...root.querySelectorAll('.pr-diagram')]

  if (diagrams.length === 0 || !window.mermaid) {
    return
  }

  for (const [index, container] of diagrams.entries()) {
    const source = container.querySelector('.pr-diagram-source')?.textContent ?? ''

    try {
      const { svg } = await window.mermaid.render(`pr-mermaid-${Date.now()}-${index}`, source)
      const holder = document.createElement('div')
      holder.className = 'pr-diagram-figure'
      holder.innerHTML = window.DOMPurify.sanitize(svg, {
        USE_PROFILES: { svg: true, svgFilters: true }
      })
      container.append(holder)
      container.dataset.rendered = 'true'
    } catch {
      container.dataset.rendered = 'false'
    }
  }
}

function renderStatus (verdict) {
  const classes = ['status']
  let text

  if (verdict.state === 'none') {
    classes.push('status-pending')
    text = 'Pending review'
  } else if (verdict.state === 'stale') {
    classes.push('status-stale')
    text = `${VERDICT_LABEL[verdict.verdict]} on an earlier revision (${verdict.castOn.slice(0, 7)}) — invalidated by an edit`
  } else {
    classes.push(verdict.verdict === 'approved' ? 'status-approved' : 'status-changes')
    text = `${VERDICT_LABEL[verdict.verdict]} · revision ${verdict.castOn.slice(0, 7)}`
  }

  element.status.className = classes.join(' ')
  element.statusText.textContent = text

  const slot = verdict.state === 'stale'
    ? 'stale'
    : verdict.state === 'none' ? 'pending' : verdict.verdict === 'approved' ? 'approve' : 'changes'

  element.status.querySelector('use').setAttribute('href', `#icon-${slot}`)
}

/**
 * A draft written on content that has since changed is never re-attached: the
 * remark was about text that is no longer there. It is listed with the section
 * and revision it was written on, and only the reviewer decides its fate.
 */
function collectStaleDrafts (documentId, revision, sectionKeys) {
  const drafts = []

  for (const key of storageKeys()) {
    if (!key.startsWith(DRAFT_PREFIX)) {
      continue
    }

    const [id, draftRevision, ...rest] = key.slice(DRAFT_PREFIX.length).split(':')
    const sectionKey = rest.join(':')

    if (id !== documentId || (draftRevision === revision && sectionKeys.has(sectionKey))) {
      continue
    }

    const body = storageGet(key)

    if (typeof body !== 'string' || body.trim().length === 0) {
      storageRemove(key)
      continue
    }

    drafts.push({ key, revision: draftRevision, sectionKey, body })
  }

  return drafts
}

function renderStaleDrafts (documentId, revision, sections) {
  const sectionKeys = new Set(sections.map((section) => section.key))
  const drafts = collectStaleDrafts(documentId, revision, sectionKeys)

  element.staleDrafts.hidden = drafts.length === 0
  element.staleDraftsList.replaceChildren(...drafts.map((draft) => {
    const item = document.createElement('li')
    item.className = 'stale-draft'
    item.dataset.draftKey = draft.key

    const head = document.createElement('div')
    head.className = 'comment-head'
    head.append(
      Object.assign(document.createElement('span'), {
        className: 'comment-state',
        textContent: 'Unsent'
      }),
      Object.assign(document.createElement('span'), {
        textContent: `section “${draft.sectionKey}”`
      }),
      Object.assign(document.createElement('span'), {
        textContent: `revision ${draft.revision.slice(0, 7)}`
      }),
      Object.assign(document.createElement('span'), {
        textContent: state.documentName ?? ''
      })
    )

    const body = document.createElement('p')
    body.className = 'comment-body'
    body.textContent = draft.body

    const discard = document.createElement('button')
    discard.type = 'button'
    discard.className = 'button button-quiet'
    discard.dataset.action = 'discard-draft'
    discard.append(icon('dismiss'), Object.assign(document.createElement('span'), { textContent: 'Discard' }))
    discard.addEventListener('click', () => {
      storageRemove(draft.key)
      renderStaleDrafts(documentId, revision, sections)
    })

    item.append(head, body, discard)
    return item
  }))

  element.staleDraftsDiscardAll.onclick = () => {
    for (const draft of drafts) {
      storageRemove(draft.key)
    }

    renderStaleDrafts(documentId, revision, sections)
  }
}

async function loadDocument () {
  const documentId = state.documentId
  const generation = state.generation + 1
  state.generation = generation

  const result = await api(`/api/document/${documentId}`)

  // A response that lost its race must not render: it would put one document's
  // content under another document's actions.
  if (generation !== state.generation || documentId !== state.documentId) {
    return
  }

  if (result.status === 410) {
    showBanner('The document is no longer readable. It may have been moved, deleted or replaced by a link.')
    return
  }

  if (!result.ok) {
    showBanner(`The document could not be loaded (${result.status}).`)
    return
  }

  clearBanner()

  const payload = result.payload
  state.revision = payload.revision.hash
  state.sections = payload.sections
  state.documentName = payload.name

  element.title.textContent = payload.title
  element.name.textContent = payload.name
  element.revision.textContent = payload.revision.hash.slice(0, 7)
  document.title = `${payload.title} — plan review`

  renderOutline(payload.sections)
  renderStatus(payload.verdict)

  const byKey = new Map()

  for (const comment of payload.comments) {
    if (comment.state === 'orphaned') {
      continue
    }

    const bucket = byKey.get(comment.anchorKey) ?? []
    bucket.push(comment)
    byKey.set(comment.anchorKey, bucket)
  }

  element.sections.replaceChildren(
    ...payload.sections.map((section) => renderSection(section, byKey.get(section.key) ?? []))
  )

  const orphaned = payload.comments.filter((comment) => comment.state === 'orphaned')
  element.orphaned.hidden = orphaned.length === 0
  element.orphanedList.replaceChildren(...orphaned.map(renderComment))

  renderStaleDrafts(documentId, payload.revision.hash, payload.sections)

  if (payload.storeUnreadable) {
    showBanner(
      `Stored feedback for this document cannot be read (${payload.storeUnreadableReason}). ` +
      'The file was left untouched; nothing new can be recorded until it is repaired or moved aside.'
    )
  }

  await renderDiagrams(element.sections)
}

function openVerdictDialog (verdict) {
  // The verdict buttons are wired before the first load, so a load that failed
  // leaves no revision to record against. The pending note stays in storage.
  if (!state.revision) {
    showBanner('No revision is loaded. Reload the document before recording a verdict.')
    return
  }

  element.dialogBody.textContent = verdict === 'approved'
    ? `Records approval feedback against revision ${state.revision.slice(0, 7)}. This is review input, not sign-off, and it does not start implementation.`
    : `Records a request for changes against revision ${state.revision.slice(0, 7)}.`

  element.dialogConfirm.dataset.verdict = verdict
  element.dialogConfirm.dataset.documentId = state.documentId
  element.dialogConfirm.dataset.documentHash = state.revision
  // A note survives a refusal: the text is the reviewer's, not the server's.
  element.dialogNote.value = storageGet(noteKey(state.documentId)) ?? ''
  element.dialog.showModal()
  element.dialogNote.focus()
}

async function submitVerdict () {
  const verdict = element.dialogConfirm.dataset.verdict
  const documentId = element.dialogConfirm.dataset.documentId
  const documentHash = element.dialogConfirm.dataset.documentHash

  element.dialogConfirm.disabled = true
  const result = await api(`/api/document/${documentId}/verdict`, {
    method: 'POST',
    body: JSON.stringify({
      verdict,
      documentHash,
      note: element.dialogNote.value
    })
  })
  element.dialogConfirm.disabled = false

  if (result.status === 409) {
    element.dialog.close()
    await loadDocument()
    showBanner('The document changed on disk. The note is kept; review the current revision before recording a verdict.')
    return
  }

  if (result.status !== 201) {
    showBanner(`The verdict was not recorded (${result.payload.reason ?? result.status}).`)
    return
  }

  storageRemove(noteKey(documentId))
  element.dialog.close()
  await loadDocument()

  if (result.payload.state === 'superseded') {
    showBanner('The verdict was recorded, but the document changed while it was being recorded. It does not apply to the current revision.')
  }
}

function focusSection (delta) {
  const articles = [...element.sections.querySelectorAll('.section')]

  if (articles.length === 0) {
    return
  }

  state.focusIndex = Math.min(Math.max(state.focusIndex + delta, 0), articles.length - 1)
  const target = articles[state.focusIndex]
  target.focus()
  target.scrollIntoView({ block: 'start', behavior: 'smooth' })
}

function currentSectionElement () {
  const articles = [...element.sections.querySelectorAll('.section')]
  return articles[state.focusIndex] ?? articles[0]
}

function installKeyboard () {
  document.addEventListener('keydown', (event) => {
    const tag = event.target.tagName

    if (tag === 'TEXTAREA' || tag === 'INPUT' || tag === 'SELECT' || event.metaKey || event.ctrlKey || event.altKey) {
      return
    }

    if (event.key === 'j') {
      event.preventDefault()
      focusSection(1)
    } else if (event.key === 'k') {
      event.preventDefault()
      focusSection(-1)
    } else if (event.key === 'c') {
      event.preventDefault()
      currentSectionElement()?.querySelector('[data-action="open-composer"]')?.click()
    } else if (event.key === 'r') {
      event.preventDefault()
      loadDocument()
    }
  })
}

function syncOutlineDisclosure () {
  // On a narrow viewport the outline would push the document below the fold,
  // so it starts collapsed there and open where there is room beside the text.
  const compact = window.matchMedia('(max-width: 60rem)')

  element.outlineDetails.open = !compact.matches
  compact.addEventListener('change', (event) => { element.outlineDetails.open = !event.matches })
}

async function shutdown () {
  await api('/api/shutdown', { method: 'POST', body: '{}' }).catch(() => ({}))
  showBanner('The review server was asked to stop. This page is now read-only until it is launched again.')
}

async function start () {
  await loadSprite()

  if (window.mermaid) {
    window.mermaid.initialize({
      startOnLoad: false,
      securityLevel: 'strict',
      htmlLabels: false,
      theme: 'neutral',
      flowchart: { htmlLabels: false }
    })
  }

  const session = await api('/api/session')

  if (session.status === 401) {
    showBanner('This review session is not valid. Open the URL printed by the launcher again.')
    return
  }

  state.csrfToken = session.payload.csrfToken

  if (!session.payload.documents?.length) {
    showBanner('The server was started without an opened document.')
    return
  }

  state.documentId = session.payload.documents[0].id

  const documentSelect = document.getElementById('document-select')
  for (const document of session.payload.documents) {
    documentSelect.add(new Option(document.title, document.id))
  }
  documentSelect.hidden = session.payload.documents.length < 2
  documentSelect.addEventListener('change', async () => {
    state.documentId = documentSelect.value
    state.focusIndex = 0
    await loadDocument()
  })

  document.getElementById('action-approve').addEventListener('click', () => openVerdictDialog('approved'))
  document.getElementById('action-changes').addEventListener('click', () => openVerdictDialog('changes-requested'))
  document.getElementById('action-reload').addEventListener('click', () => loadDocument())
  document.getElementById('action-shutdown').addEventListener('click', () => shutdown())
  element.dialogConfirm.addEventListener('click', () => submitVerdict())
  element.dialogCancel.addEventListener('click', () => element.dialog.close())
  element.dialogNote.addEventListener('input', () => {
    const documentId = element.dialogConfirm.dataset.documentId

    if (documentId) {
      storageSet(noteKey(documentId), element.dialogNote.value)
    }
  })

  syncOutlineDisclosure()
  installKeyboard()

  await loadDocument()

  window.addEventListener('focus', () => { loadDocument() })
}

start().catch((error) => {
  showBanner(`The review surface failed to start: ${error.message}`)
})
