/**
 * Patient H5 UI walkthrough (real browser, headless).
 *
 * Why this file exists: API tests prove the backend is right, but they cannot
 * catch a broken Vue template, a wrong field name in a view, or a button that
 * never becomes clickable. This script drives the actual page.
 *
 * It uses the locally installed playwright-core (bundled with another tool on
 * this machine) because installing @playwright/cli would need network access.
 * Chromium is already present under %LOCALAPPDATA%\ms-playwright.
 *
 * Usage:
 *   1) make sure backend (8080) and the patient dev server (5174) are running
 *   2) node tools/ui-check-patient.mjs
 *
 * Screenshots land in output/playwright/.
 */

import { createRequire } from 'node:module'
import { mkdirSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import path from 'node:path'

const require = createRequire(import.meta.url)

const PLAYWRIGHT_CORE =
  'C:/Users/wulei/AppData/Roaming/npm/node_modules/.openclaw-GciWGhVN/node_modules/playwright-core'
const CHROMIUM = 'C:/Users/wulei/AppData/Local/ms-playwright/chromium-1237/chrome-win64/chrome.exe'
const BASE = process.env.PATIENT_BASE_URL || 'http://127.0.0.1:5174'

const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const shotDir = path.join(projectRoot, 'output', 'playwright')
mkdirSync(shotDir, { recursive: true })

let pass = 0
let fail = 0

async function step(name, fn) {
  const t0 = Date.now()
  try {
    await fn()
    pass++
    console.log(`  PASS  ${name.padEnd(52)} ${String(Date.now() - t0).padStart(5)} ms`)
  } catch (e) {
    fail++
    console.log(`  FAIL  ${name.padEnd(52)} ${String(Date.now() - t0).padStart(5)} ms`)
    console.log(`        ${e.message}`)
  }
}

function assert(cond, msg) {
  if (!cond) throw new Error(msg)
}

const { chromium } = require(PLAYWRIGHT_CORE)

const browser = await chromium.launch({
  executablePath: CHROMIUM,
  args: ['--no-sandbox']
})

// iPhone-ish viewport: this app is meant for phones
const newContext = () => browser.newContext({
  viewport: { width: 390, height: 844 },
  deviceScaleFactor: 2,
  locale: 'zh-CN'
})

const jsErrors = []
const consoleErrors = []

/**
 * Each scenario gets a fresh page on purpose: the verification-code button
 * turns into a 60 second countdown, so reusing one page makes the next
 * "get code" click impossible. (Learned the hard way.)
 */
let page = null

async function useFreshPage() {
  const ctx = await newContext()
  page = await ctx.newPage()
  page.on('pageerror', (e) => jsErrors.push(e.message))
  page.on('console', (m) => {
    if (m.type() === 'error') consoleErrors.push(m.text())
  })
  return page
}

/** Wait for the API-driven content to actually render before asserting on it. */
async function waitForContent(selector) {
  await page.locator(selector).first().waitFor({ timeout: 15000 })
}

async function shot(name) {
  await page.screenshot({ path: path.join(shotDir, `${name}.png`), fullPage: true })
}

console.log(`\nPatient H5 UI walkthrough  (${BASE})`)

// --------------------------------------------------------------------------
await step('open login page', async () => {
  await useFreshPage()
  await page.goto(`${BASE}/#/login`, { waitUntil: 'networkidle' })
  const h1 = await page.locator('h1').first().innerText()
  assert(h1.includes('随访查询'), `unexpected heading: ${h1}`)
  await shot('patient-01-login')
})

await step('unknown phone shows an error, not a crash', async () => {
  await page.fill('input[type="tel"]', '13900000000')
  await page.getByRole('button', { name: /获取验证码/ }).click()
  await page.waitForTimeout(400)

  const notice = page.locator('.notice.info')
  await notice.waitFor({ timeout: 8000 })
  const text = await notice.innerText()
  const code = (text.match(/\d{6}/) || [])[0]
  assert(code, `no dev code on the page: ${text}`)

  await page.fill('input[maxlength="6"]', code)
  await page.locator('input[type="checkbox"]').check()
  await page.getByRole('button', { name: /^登录$/ }).click()

  const err = page.locator('.notice.err')
  await err.waitFor({ timeout: 8000 })
  const msg = await err.innerText()
  assert(msg.includes('未关联') || msg.includes('随访'), `unexpected error text: ${msg}`)
  await shot('patient-02-unknown-phone')
})

await step('login as demo patient 13800000003', async () => {
  await useFreshPage()
  await page.goto(`${BASE}/#/login`, { waitUntil: 'networkidle' })
  await page.fill('input[type="tel"]', '13800000003')
  await page.getByRole('button', { name: /获取验证码/ }).click()

  const notice = page.locator('.notice.info')
  await notice.waitFor({ timeout: 8000 })
  const code = ((await notice.innerText()).match(/\d{6}/) || [])[0]
  assert(code, 'dev code not found')

  await page.fill('input[maxlength="6"]', code)
  await page.locator('input[type="checkbox"]').check()
  await page.getByRole('button', { name: /^登录$/ }).click()

  await page.waitForURL(/#\/timeline/, { timeout: 15000 })
  // The heading is rendered before the timeline request comes back, so wait
  // for real content first instead of asserting on the first paint.
  await waitForContent('.stat b')
  await page.waitForFunction(() => document.querySelector('.band .txt b')?.innerText.includes('陈芳'), null, {
    timeout: 10000
  })
  const bandVisible = await page.locator('.band img').isVisible()
  assert(bandVisible, 'greeting photo band is not rendered')
  await shot('patient-03-timeline')
})

await step('timeline lists follow-up items with status chips', async () => {
  const cards = page.locator('.card.tap')
  await waitForContent('.card.tap')
  const count = await cards.count()
  assert(count >= 1, `no follow-up card rendered (count=${count})`)

  const chips = page.locator('.stat b')
  const stats = await chips.allInnerTexts()
  assert(stats.length === 3, `expected 3 summary numbers, got ${stats.length}`)
})

await step('open a task and render the questionnaire from the API', async () => {
  await page.locator('.card.tap').first().click()
  await page.waitForURL(/#\/task\//, { timeout: 10000 })
  await waitForContent('.opt')

  const options = await page.locator('.opt').count()
  assert(options >= 4, `questionnaire options not rendered (count=${options})`)
  await shot('patient-04-questionnaire')
})

await step('required questions block an empty submit', async () => {
  await page.getByRole('button', { name: /提交问卷/ }).click()
  const err = page.locator('.notice.err')
  await err.waitFor({ timeout: 5000 })
  const msg = await err.innerText()
  assert(msg.includes('必答'), `expected a validation message, got: ${msg}`)
})

await step('fill and submit the questionnaire', async () => {
  // The seeded questionnaire has three single-choice questions; click the
  // first option of each by its exact label (deterministic beats clever).
  for (const label of ['没有', '正常饮食', '按时吃']) {
    await page.getByRole('button', { name: label, exact: true }).click()
  }
  await page.getByRole('button', { name: /提交问卷/ }).click()

  const ok = page.locator('.notice.info')
  await ok.waitFor({ timeout: 10000 })
  const msg = await ok.innerText()
  assert(msg.includes('已提交') || msg.includes('感谢'), `unexpected submit result: ${msg}`)
  await shot('patient-05-questionnaire-done')
})

await step('reports tab shows the published report and doctor interpretation', async () => {
  await page.goto(`${BASE}/#/reports`, { waitUntil: 'networkidle' })
  const card = page.locator('.card.tap').first()
  await waitForContent('.card.tap')

  const title = await card.locator('b').first().innerText()
  assert(title.includes('结肠息肉') || title.includes('病理'), `unexpected report title: ${title}`)

  await card.click()
  const interpretation = page.locator('.notice.info')
  await interpretation.waitFor({ timeout: 5000 })
  const text = await interpretation.innerText()
  assert(text.includes('医生解读'), `doctor interpretation missing: ${text}`)
  await shot('patient-06-report-detail')
})

await step('profile page shows masked phone only', async () => {
  await page.goto(`${BASE}/#/me`, { waitUntil: 'networkidle' })
  await page.waitForFunction(() => document.body.innerText.includes('病案号'), null, { timeout: 10000 })
  const body = await page.locator('.card').first().innerText()
  assert(body.includes('138****0003'), `phone is not masked: ${body}`)
  assert(!/13800000003/.test(body), 'raw phone number leaked to the page')
  await shot('patient-07-me')
})

await step('no uncaught javascript errors during the walkthrough', async () => {
  // One console 400 is expected: the walkthrough deliberately tries an unknown
  // phone number first. Uncaught JS exceptions are never acceptable.
  const unexpected = consoleErrors.filter((t) => !/Failed to load resource/.test(t))
  assert(jsErrors.length === 0, `uncaught js errors: ${jsErrors.join(' | ')}`)
  assert(unexpected.length === 0, `unexpected console errors: ${unexpected.join(' | ')}`)
})

await browser.close()

console.log('\nSummary')
console.log(`  steps : ${pass} passed, ${fail} failed`)
console.log(`  shots : ${shotDir}`)
console.log(fail > 0 ? '\n  RESULT: FAILED' : '\n  RESULT: ALL GREEN')
process.exit(fail > 0 ? 1 : 0)
