import { expect, test } from '@playwright/test'
import { copyFileSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

import { createReviewServer } from '../src/server.mjs'

const here = dirname(fileURLToPath(import.meta.url))
const fixtureSource = join(here, 'fixtures', 'review-fixture.md')
const screenshotDirectory = join(here, 'screenshots')

mkdirSync(screenshotDirectory, { recursive: true })

let server
let workspace
let documentPath

test.beforeEach(async () => {
  workspace = mkdtempSync(join(tmpdir(), 'plan-review-browser-'))
  documentPath = join(workspace, 'concept.md')
  copyFileSync(fixtureSource, documentPath)

  server = createReviewServer({
    documents: [{ root: workspace, path: documentPath }],
    stateRoot: join(workspace, '.state'),
    ttlSeconds: 300
  })

  await server.listen()
})

test.afterEach(async () => {
  await server.close()
})

async function openReview (page) {
  const problems = []

  page.on('console', (message) => {
    if (message.type() === 'error') {
      problems.push(`console: ${message.text()}`)
    }
  })
  page.on('pageerror', (error) => problems.push(`pageerror: ${error.message}`))

  await page.goto(server.url)
  await expect(page.locator('#doc-title')).toHaveText('Renderer fixture — plan review browser checks')

  return problems
}

test('renders the document, its outline and a real diagram', async ({ page }, testInfo) => {
  const problems = await openReview(page)

  await expect(page.locator('#outline-list li')).toHaveCount(5)
  await expect(page.locator('#section-scope table')).toBeVisible()

  const diagram = page.locator('#section-diagram .pr-diagram').first()
  await expect(diagram).toHaveAttribute('data-rendered', 'true')
  await expect(diagram.locator('svg')).toBeVisible()
  await expect(diagram.locator('svg')).not.toBeEmpty()

  await expect(page.locator('#verdict-status-text')).toHaveText('Pending review')

  const shot = join(screenshotDirectory, `${testInfo.project.name}-document.png`)
  await page.screenshot({ path: shot, fullPage: false })

  expect(problems).toEqual([])
})

test('renders unsafe Markdown inertly', async ({ page }) => {
  const problems = await openReview(page)

  await expect(page.locator('#section-unsafe-input')).toBeVisible()
  await expect(page.locator('#section-unsafe-input img')).toHaveCount(0)
  await expect(page.locator('#section-unsafe-input script')).toHaveCount(0)
  await expect(page.locator('#section-unsafe-input')).toContainText('image not loaded')
  await expect(page.locator('#section-unsafe-input a[href^="javascript:"]')).toHaveCount(0)

  expect(await page.evaluate(() => window.__planReviewInjected)).toBeUndefined()
  expect(problems).toEqual([])
})

test('adds a comment anchored to its section', async ({ page }, testInfo) => {
  const problems = await openReview(page)

  const section = page.locator('#section-scope')
  await section.getByRole('button', { name: 'Comment' }).click()
  await section.locator('textarea').fill('Tighten the second sentence.')
  await section.getByRole('button', { name: 'Add comment' }).click()

  const comment = section.locator('.comment').first()
  await expect(comment).toContainText('Tighten the second sentence.')
  await expect(comment.locator('.comment-state')).toHaveText('Current')

  const shot = join(screenshotDirectory, `${testInfo.project.name}-comment.png`)
  await page.screenshot({ path: shot, fullPage: false })

  expect(problems).toEqual([])
})

test('records a request for changes and then an approval', async ({ page }, testInfo) => {
  const problems = await openReview(page)

  await page.getByRole('button', { name: 'Request changes' }).click()
  await page.locator('#verdict-note').fill('Quantify the freshness requirement.')
  await page.getByRole('button', { name: 'Record' }).click()
  await expect(page.locator('#verdict-status-text')).toContainText('Changes requested')

  await page.getByRole('button', { name: 'Approve' }).click()
  await expect(page.locator('#verdict-dialog-body')).toContainText('not sign-off')
  await page.getByRole('button', { name: 'Record' }).click()
  await expect(page.locator('#verdict-status-text')).toContainText('Approved (feedback)')

  const shot = join(screenshotDirectory, `${testInfo.project.name}-approved.png`)
  await page.screenshot({ path: shot, fullPage: false })

  expect(problems).toEqual([])
})

test('invalidates an approval once the document changes on disk', async ({ page }, testInfo) => {
  const problems = await openReview(page)

  await page.getByRole('button', { name: 'Approve' }).click()
  await page.getByRole('button', { name: 'Record' }).click()
  await expect(page.locator('#verdict-status-text')).toContainText('Approved (feedback)')

  writeFileSync(documentPath, `${readFileSync(documentPath, 'utf8')}\n## Added after approval\n\nNew text.\n`, 'utf8')

  await page.getByRole('button', { name: 'Reload' }).click()
  await expect(page.locator('#verdict-status-text')).toContainText('invalidated by an edit')
  await expect(page.locator('#verdict-status')).toHaveClass(/status-stale/)
  await expect(page.locator('#section-added-after-approval')).toBeVisible()
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth)
  expect(overflow, 'the stale verdict must fit the viewport').toBeLessThanOrEqual(1)

  const shot = join(screenshotDirectory, `${testInfo.project.name}-stale.png`)
  await page.screenshot({ path: shot, fullPage: false })

  expect(problems).toEqual([])
})

test('unanchors a comment whose section was removed', async ({ page }, testInfo) => {
  const problems = await openReview(page)

  const section = page.locator('#section-removable')
  await section.getByRole('button', { name: 'Comment' }).click()
  await section.locator('textarea').fill('This section is about to disappear.')
  await section.getByRole('button', { name: 'Add comment' }).click()
  await expect(section.locator('.comment')).toHaveCount(1)

  const trimmed = readFileSync(documentPath, 'utf8').split('## Removable')[0]
  writeFileSync(documentPath, trimmed, 'utf8')

  await page.getByRole('button', { name: 'Reload' }).click()
  await expect(page.locator('#orphaned')).toBeVisible()
  await expect(page.locator('#orphaned-list .comment')).toHaveCount(1)
  await expect(page.locator('#orphaned-list .comment-state')).toHaveText('Unanchored')
  await expect(page.locator('#section-removable')).toHaveCount(0)

  const shot = join(screenshotDirectory, `${testInfo.project.name}-orphaned.png`)
  await page.screenshot({ path: shot, fullPage: false })

  expect(problems).toEqual([])
})

test('marks a comment as revised when its section changes', async ({ page }) => {
  const problems = await openReview(page)

  const section = page.locator('#section-scope')
  await section.getByRole('button', { name: 'Comment' }).click()
  await section.locator('textarea').fill('Anchored before the edit.')
  await section.getByRole('button', { name: 'Add comment' }).click()
  await expect(section.locator('.comment')).toHaveCount(1)

  writeFileSync(
    documentPath,
    readFileSync(documentPath, 'utf8').replace('This section carries', 'This section now carries'),
    'utf8'
  )

  await page.getByRole('button', { name: 'Reload' }).click()
  await expect(page.locator('#section-scope .comment-state')).toHaveText('Section revised')

  expect(problems).toEqual([])
})

test('keeps the session and the feedback across a reload', async ({ page }) => {
  const problems = await openReview(page)

  const section = page.locator('#section-scope')
  await section.getByRole('button', { name: 'Comment' }).click()
  await section.locator('textarea').fill('Survives a browser reload.')
  await section.getByRole('button', { name: 'Add comment' }).click()
  await expect(section.locator('.comment')).toHaveCount(1)

  await page.reload()
  await expect(page.locator('#doc-title')).toHaveText('Renderer fixture — plan review browser checks')
  await expect(page.locator('#section-scope .comment')).toContainText('Survives a browser reload.')

  expect(problems).toEqual([])
})

test('switches only between explicitly opened documents', async ({ page }) => {
  const otherPath = join(workspace, 'second-concept.md')
  writeFileSync(otherPath, '# Second review fixture\n\nSeparate document content.\n', 'utf8')
  await server.close()
  server = createReviewServer({
    documents: [{ root: workspace, path: documentPath }, { root: workspace, path: otherPath }],
    stateRoot: join(workspace, '.state'),
    ttlSeconds: 300
  })
  await server.listen()
  const problems = await openReview(page)

  await page.getByLabel('Opened document').selectOption({ label: 'Second review fixture' })
  await expect(page.locator('#doc-title')).toHaveText('Second review fixture')
  await expect(page.locator('#sections')).toContainText('Separate document content.')
  await expect(page.locator('#document-select option')).toHaveCount(2)
  expect(problems).toEqual([])
})

test('preserves an unsent comment across a reload', async ({ page }) => {
  await openReview(page)
  const section = page.locator('#section-scope')
  await section.getByRole('button', { name: 'Comment', exact: true }).click()
  await section.locator('textarea').fill('Pending feedback survives a reload.')

  await page.reload()
  await expect(section.locator('textarea')).toBeVisible()
  await expect(section.locator('textarea')).toHaveValue('Pending feedback survives a reload.')
  await section.getByRole('button', { name: 'Add comment', exact: true }).click()
  await expect(section.locator('.comment')).toContainText('Pending feedback survives a reload.')
})

test('restores comment submission after a temporary connection failure', async ({ page }) => {
  const pageErrors = []
  page.on('pageerror', (error) => pageErrors.push(error.message))
  await openReview(page)
  const section = page.locator('#section-scope')
  await section.getByRole('button', { name: 'Comment', exact: true }).click()
  await section.locator('textarea').fill('Retry this feedback after reconnecting.')
  await page.route('**/api/document/*/comment', (route) => route.abort('internetdisconnected'))

  await section.getByRole('button', { name: 'Add comment', exact: true }).click()
  await expect(section.getByRole('button', { name: 'Add comment', exact: true })).toBeEnabled()
  await expect(section.locator('textarea')).toHaveValue('Retry this feedback after reconnecting.')
  await expect(page.locator('#banner')).toContainText('connection')
  await page.unroute('**/api/document/*/comment')
  await section.getByRole('button', { name: 'Add comment', exact: true }).click()
  await expect(section.locator('.comment')).toContainText('Retry this feedback after reconnecting.')
  expect(pageErrors).toEqual([])
})

test('keeps an open verdict dialog bound to its original revision', async ({ page }) => {
  await openReview(page)
  await page.getByRole('button', { name: 'Approve', exact: true }).click()
  writeFileSync(documentPath, `${readFileSync(documentPath, 'utf8')}\nNew unreviewed material.\n`, 'utf8')
  await page.evaluate(() => window.dispatchEvent(new Event('focus')))
  await expect(page.locator('#sections')).toContainText('New unreviewed material.')

  const verdictResponse = page.waitForResponse((response) => response.url().endsWith('/verdict'))
  await page.getByRole('button', { name: 'Record', exact: true }).click()
  expect((await verdictResponse).status()).toBe(409)
  await expect(page.locator('#verdict-status-text')).toHaveText('Pending review')
})

test('supports keyboard navigation between sections', async ({ page }) => {
  const problems = await openReview(page)

  await page.locator('#document').click({ position: { x: 5, y: 5 } })
  await page.keyboard.press('j')
  await expect(page.locator('#section-scope')).toBeFocused()
  await page.keyboard.press('c')
  await expect(page.locator('#section-scope textarea')).toBeVisible()

  expect(problems).toEqual([])
})

test('lays out without overlapping controls', async ({ page }, testInfo) => {
  await openReview(page)

  const boxes = await page.locator('.bar-actions .button').evaluateAll((nodes) =>
    nodes.map((node) => node.getBoundingClientRect().toJSON())
  )

  for (let outer = 0; outer < boxes.length; outer += 1) {
    for (let inner = outer + 1; inner < boxes.length; inner += 1) {
      const a = boxes[outer]
      const b = boxes[inner]
      const overlaps = a.left < b.right && b.left < a.right && a.top < b.bottom && b.top < a.bottom

      expect(overlaps, `buttons ${outer} and ${inner} overlap`).toBe(false)
    }
  }

  const horizontalOverflow = await page.evaluate(
    () => document.documentElement.scrollWidth - document.documentElement.clientWidth
  )
  expect(horizontalOverflow).toBeLessThanOrEqual(1)

  await page.screenshot({
    path: join(screenshotDirectory, `${testInfo.project.name}-layout-full.png`),
    fullPage: true
  })
})

test('stops the server from the page', async ({ page }) => {
  await openReview(page)

  await page.getByRole('button', { name: 'Stop server' }).click()
  await expect(page.locator('#banner')).toContainText('asked to stop')

  await server.stopped
  expect(server.address).toBeNull()
})

test('keeps two review servers usable in one browser', async ({ page }) => {
  const otherWorkspace = mkdtempSync(join(tmpdir(), 'plan-review-second-'))
  const otherPath = join(otherWorkspace, 'other.md')
  writeFileSync(otherPath, '# Second concept\n\n## Scope\n\nSeparate server content.\n', 'utf8')

  const second = createReviewServer({
    documents: [{ root: otherWorkspace, path: otherPath }],
    stateRoot: join(otherWorkspace, '.state'),
    ttlSeconds: 300
  })
  await second.listen()

  try {
    const problems = await openReview(page)

    const otherPage = await page.context().newPage()
    await otherPage.goto(second.url)
    await expect(otherPage.locator('#doc-title')).toHaveText('Second concept')

    // The second launch must not have overwritten the first launch's cookie.
    await page.reload()
    await expect(page.locator('#doc-title')).toHaveText('Renderer fixture — plan review browser checks')

    const first = page.locator('#section-scope')
    await first.getByRole('button', { name: 'Comment', exact: true }).click()
    await first.locator('textarea').fill('Recorded on the first server.')
    await first.getByRole('button', { name: 'Add comment', exact: true }).click()
    await expect(first.locator('.comment')).toHaveCount(1)

    const other = otherPage.locator('#section-scope')
    await other.getByRole('button', { name: 'Comment', exact: true }).click()
    await other.locator('textarea').fill('Recorded on the second server.')
    await other.getByRole('button', { name: 'Add comment', exact: true }).click()
    await expect(other.locator('.comment')).toHaveCount(1)
    await expect(other.locator('.comment')).toContainText('Recorded on the second server.')

    await otherPage.close()
    expect(problems).toEqual([])
  } finally {
    await second.close()
  }
})

test('surfaces a draft written on an earlier revision instead of hiding it', async ({ page }) => {
  const problems = await openReview(page)

  const section = page.locator('#section-removable')
  await section.getByRole('button', { name: 'Comment', exact: true }).click()
  await section.locator('textarea').fill('Written before the document changed.')

  const trimmed = readFileSync(documentPath, 'utf8').split('## Removable')[0]
  writeFileSync(documentPath, trimmed, 'utf8')

  await page.getByRole('button', { name: 'Reload' }).click()
  await expect(page.locator('#section-removable')).toHaveCount(0)

  const drafts = page.locator('#stale-drafts')
  await expect(drafts).toBeVisible()
  await expect(drafts.locator('.stale-draft')).toHaveCount(1)
  await expect(drafts.locator('.stale-draft')).toContainText('Written before the document changed.')
  await expect(drafts.locator('.stale-draft')).toContainText('removable')

  // The text must never be re-attached to a section it was not written on.
  const scope = page.locator('#section-scope')
  await scope.getByRole('button', { name: 'Comment', exact: true }).click()
  await expect(scope.locator('textarea')).toHaveValue('')

  await drafts.locator('.stale-draft').getByRole('button', { name: 'Discard' }).click()
  await expect(drafts).toBeHidden()

  expect(problems).toEqual([])
})

test('keeps a pending verdict note after a stale revision refusal', async ({ page }) => {
  const problems = await openReview(page)

  await page.getByRole('button', { name: 'Approve', exact: true }).click()
  await page.locator('#verdict-note').fill('Hold this note across the refusal.')

  writeFileSync(documentPath, `${readFileSync(documentPath, 'utf8')}\nEdited under the open dialog.\n`, 'utf8')

  const verdictResponse = page.waitForResponse((response) => response.url().endsWith('/verdict'))
  await page.getByRole('button', { name: 'Record', exact: true }).click()
  expect((await verdictResponse).status()).toBe(409)
  await expect(page.locator('#banner')).toContainText('changed')

  await page.getByRole('button', { name: 'Approve', exact: true }).click()
  await expect(page.locator('#verdict-note')).toHaveValue('Hold this note across the refusal.')

  // The refusal itself is the expected outcome, so the browser's log entry for
  // the 409 is not a defect.
  expect(problems.filter((problem) => !problem.includes('409'))).toEqual([])
})

test('never renders a slow response under a different selected document', async ({ page }) => {
  const otherPath = join(workspace, 'second-concept.md')
  writeFileSync(otherPath, '# Second review fixture\n\n## Scope\n\nSeparate document content.\n', 'utf8')
  await server.close()
  server = createReviewServer({
    documents: [{ root: workspace, path: documentPath }, { root: workspace, path: otherPath }],
    stateRoot: join(workspace, '.state'),
    ttlSeconds: 300
  })
  await server.listen()

  const first = server.documents[0].id
  const problems = await openReview(page)

  await page.route(`**/api/document/${first}`, async (route) => {
    await new Promise((resolve) => setTimeout(resolve, 1500))
    await route.continue()
  })

  await page.getByRole('button', { name: 'Reload' }).click()
  await page.getByLabel('Opened document').selectOption({ label: 'Second review fixture' })

  await expect(page.locator('#doc-title')).toHaveText('Second review fixture')
  await page.waitForTimeout(2500)
  await expect(page.locator('#doc-title')).toHaveText('Second review fixture')
  await expect(page.locator('#sections')).toContainText('Separate document content.')
  await expect(page.locator('#sections')).not.toContainText('This section carries')

  await page.unroute(`**/api/document/${first}`)
  expect(problems).toEqual([])
})

test('offers the outline as a disclosure and shows no permanent shortcut line', async ({ page }, testInfo) => {
  const problems = await openReview(page)

  await expect(page.locator('.outline kbd')).toHaveCount(0)

  const outline = page.locator('#outline-details')
  await expect(outline).toBeVisible()

  if (testInfo.project.name === 'mobile') {
    await expect(page.locator('#outline-list')).toBeHidden()
    // The document itself must be reachable without scrolling past an outline.
    const documentTop = await page.locator('#document').evaluate((node) => node.getBoundingClientRect().top)
    expect(documentTop).toBeLessThan(page.viewportSize().height)

    await outline.locator('summary').click()
    await expect(page.locator('#outline-list')).toBeVisible()
  } else {
    await expect(page.locator('#outline-list')).toBeVisible()
  }

  expect(problems).toEqual([])
})

test('explains a verdict action taken when no revision is loaded', async ({ page }) => {
  const problems = []

  page.on('console', (message) => {
    if (message.type() === 'error') {
      problems.push(`console: ${message.text()}`)
    }
  })
  page.on('pageerror', (error) => problems.push(`pageerror: ${error.message}`))

  rmSync(documentPath)
  await page.goto(server.url)
  await expect(page.locator('#banner')).toContainText('no longer readable')

  await page.getByRole('button', { name: 'Approve' }).click()
  await expect(page.locator('#verdict-dialog')).toBeHidden()
  await expect(page.locator('#banner')).toContainText('No revision is loaded')

  await page.getByRole('button', { name: 'Request changes' }).click()
  await expect(page.locator('#verdict-dialog')).toBeHidden()

  // The removed document answers 410 by design, which the browser logs as a
  // failed resource load; an application error would still show up here.
  expect(problems.filter((problem) => !problem.includes('Failed to load resource'))).toEqual([])
})
