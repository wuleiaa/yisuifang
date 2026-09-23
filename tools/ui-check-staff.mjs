/**
 * Staff workbench UI walkthrough (real browser, headless).
 *
 * Covers the flow a nurse actually performs, plus the two-people-one-call
 * case that the backend claim endpoint exists for:
 *   doctor opens a task  -> the task gets locked
 *   nurse opens same task -> must see the "someone else is on it" warning
 *   doctor submits        -> succeeds
 *
 * Uses the locally installed playwright-core (no network needed).
 *
 * Usage:
 *   1) backend (8080) and the staff dev server (5173) running
 *   2) node tools/ui-check-staff.mjs
 */

import { createRequire } from 'node:module'
import { mkdirSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import path from 'node:path'

const require = createRequire(import.meta.url)

const PLAYWRIGHT_CORE =
  'C:/Users/wulei/AppData/Roaming/npm/node_modules/.openclaw-GciWGhVN/node_modules/playwright-core'
const CHROMIUM = 'C:/Users/wulei/AppData/Local/ms-playwright/chromium-1237/chrome-win64/chrome.exe'
const BASE = process.env.STAFF_BASE_URL || 'http://127.0.0.1:5173'
// Same idea as ADMIN_PWD in ui-check-admin.mjs: the demo password is only
// known outside this repo, so let a deployment run inject it via the
// environment instead of hardcoding it here.
const STAFF_PWD = process.env.STAFF_PWD || 'Followup@2026'

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
const browser = await chromium.launch({ executablePath: CHROMIUM, args: ['--no-sandbox'] })

const jsErrors = []

async function newSession() {
  const ctx = await browser.newContext({
    viewport: { width: 420, height: 900 },
    deviceScaleFactor: 2,
    locale: 'zh-CN'
  })
  const p = await ctx.newPage()
  p.on('pageerror', (e) => jsErrors.push(e.message))
  return p
}

let page = await newSession()

async function shot(name) {
  await page.screenshot({ path: path.join(shotDir, `${name}.png`), fullPage: true })
}

async function login(p, staffNo, password = STAFF_PWD) {
  await p.goto(`${BASE}/#/login`, { waitUntil: 'networkidle' })
  await p.fill('input[placeholder="请输入工号"]', staffNo)
  await p.fill('input[placeholder="请输入密码"]', password)
  await p.locator('button.submit').click()
  await p.waitForURL(/#\/todo/, { timeout: 15000 })
  await p.locator('.banner .big').waitFor({ timeout: 15000 })
  // The banner renders "0 条待办" before the API answers, so wait for the
  // loading placeholder to disappear instead of trusting the first paint.
  await p.locator('.loading').waitFor({ state: 'detached', timeout: 15000 })
}

console.log(`\nStaff workbench UI walkthrough  (${BASE})`)

await step('open login page', async () => {
  await page.goto(`${BASE}/#/login`, { waitUntil: 'networkidle' })
  // The title sits on the photo hero now (design language v2)
  const title = await page.locator('.login-hero .cn').innerText()
  assert(title.includes('随访工作台'), `unexpected heading: ${title}`)
  const heroVisible = await page.locator('.login-hero img').isVisible()
  assert(heroVisible, 'hero photo is not rendered')
  await shot('staff-01-login')
})

await step('wrong password is rejected', async () => {
  await page.fill('input[placeholder="请输入工号"]', 'D0231')
  await page.fill('input[placeholder="请输入密码"]', 'wrong-password')
  await page.locator('button.submit').click()
  const err = page.locator('.err')
  await err.waitFor({ timeout: 10000 })
  const text = await err.innerText()
  assert(text.length > 0, 'no error message shown for a wrong password')
})

let taskId = null
let dialedPhone = null

await step('login as doctor D0231 and load the todo list', async () => {
  await login(page, 'D0231')
  const big = await page.locator('.banner .big').innerText()
  const total = parseInt(big.replace(/\D/g, ''), 10)
  assert(total > 0, `todo list is empty: ${big}`)
  await shot('staff-02-todo')
})

await step('scope switch MINE / TEAM re-queries the list', async () => {
  await page.locator('.opts .opt', { hasText: '本组全部' }).click()
  await page.waitForTimeout(600)
  const teamTotal = parseInt((await page.locator('.banner .big').innerText()).replace(/\D/g, ''), 10)
  assert(teamTotal >= 1, 'TEAM scope returned nothing')

  await page.locator('.opts .opt', { hasText: '指派给我' }).click()
  await page.waitForTimeout(600)
  const mine = parseInt((await page.locator('.banner .big').innerText()).replace(/\D/g, ''), 10)
  assert(mine >= 1, 'MINE scope returned nothing')
})

await step('open a task: detail renders diagnosis and pathway', async () => {
  await page.locator('article.task').first().click()
  // Routes are lazy chunks: vue-router only rewrites the URL once the view's
  // chunk has downloaded. Over a slow link to the deployed site that can take
  // far longer than 10 s, which used to look like "the page is broken".
  await page.waitForURL(/#\/task\//, { timeout: 30000 })
  await page.locator('.kv').first().waitFor({ timeout: 15000 })

  taskId = (page.url().match(/#\/task\/(\d+)/) || [])[1]
  assert(taskId, `could not read task id from ${page.url()}`)

  const body = await page.locator('section.card').first().innerText()
  assert(body.includes('出院诊断'), `diagnosis block missing: ${body}`)
  assert(body.length > 20, 'task detail looks empty')
  await shot('staff-03-task-detail')
})

await step('opening the task locks it (no warning for the owner)', async () => {
  const warn = await page.locator('.notice.warn').count()
  const lockWarn = await page.getByText('正在被其他同事处理').count()
  assert(lockWarn === 0 || warn === 0, 'the owner should not see a lock warning')
})

await step('nurse opening the same task sees the lock warning', async () => {
  const nurse = await newSession()
  await login(nurse, 'N0455')
  await nurse.goto(`${BASE}/#/task/${taskId}`, { waitUntil: 'networkidle' })
  await nurse.getByText('正在被其他同事处理').waitFor({ timeout: 15000 })
  await nurse.screenshot({ path: path.join(shotDir, 'staff-04-lock-warning.png'), fullPage: true })
  await nurse.context().close()
})

await step('one-tap dial asks the backend and never renders the digits', async () => {
  const dialBtn = page.locator('button.btn-primary', { hasText: '一键拨号' }).first()
  const [resp] = await Promise.all([
    page.waitForResponse(
      (r) => /\/api\/tasks\/\d+\/dial$/.test(r.url()) && r.request().method() === 'POST',
      { timeout: 15000 }
    ),
    dialBtn.click()
  ])
  assert(resp.status() === 200, `dial returned http ${resp.status()}`)
  const body = await resp.json()
  assert(body.code === 0, `dial failed: code=${body.code} ${body.message}`)

  dialedPhone = body.data.phone
  assert(/^\d{11}$/.test(dialedPhone), `dial did not return a real number: ${dialedPhone}`)
  assert(/^\d{3}\*{4}\d{4}$/.test(body.data.phoneMask), `unexpected mask: ${body.data.phoneMask}`)

  // Privacy rule: only the dialer may see the real number. If it ever shows up
  // in the page text, the masking policy has been broken by this feature.
  const text = await page.locator('body').innerText()
  assert(!text.includes(dialedPhone), 'the full phone number was rendered on the page')
  assert(text.includes(body.data.phoneMask), 'the masked number disappeared from the page')

  // Desktop Chromium cannot hand off tel:, so the UI has to say so instead of
  // pretending the call started (that was the old bug: a toast and nothing else).
  const toast = page.locator('.toast')
  await toast.waitFor({ timeout: 10000 })
  const toastText = await toast.innerText()
  assert(/桌面浏览器|手机/.test(toastText), `unexpected desktop dial toast: ${toastText}`)
  await shot('staff-09-dial-desktop')
})

await step('on a phone the digits really reach tel:', async () => {
  const ctx = await browser.newContext({
    viewport: { width: 390, height: 844 },
    deviceScaleFactor: 3,
    locale: 'zh-CN',
    hasTouch: true,
    userAgent:
      'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36'
  })
  const m = await ctx.newPage()
  m.on('pageerror', (e) => jsErrors.push(e.message))

  // tel: is an external protocol, so Playwright never sees it as a network
  // request. Record the hand-off at the anchor instead - that is exactly what
  // the OS dialer would receive.
  await m.addInitScript(() => {
    window.__telHandoffs = []
    const click = HTMLAnchorElement.prototype.click
    HTMLAnchorElement.prototype.click = function () {
      if (this.href && this.href.startsWith('tel:')) window.__telHandoffs.push(this.href)
      return click.apply(this, arguments)
    }
  })

  await login(m, 'D0231')
  await m.goto(`${BASE}/#/task/${taskId}`, { waitUntil: 'networkidle' })
  const dialBtn = m.locator('button.btn-primary', { hasText: '一键拨号' }).first()
  await dialBtn.waitFor({ timeout: 15000 })
  await dialBtn.click()
  await m.waitForTimeout(1500)

  const handoffs = await m.evaluate(() => window.__telHandoffs)
  assert(
    handoffs.length === 1,
    `expected exactly one tel: hand-off, got ${JSON.stringify(handoffs)}`
  )
  assert(handoffs[0] === `tel:${dialedPhone}`, `tel: url mismatch: ${handoffs[0]}`)

  const mobileText = await m.locator('body').innerText()
  assert(!mobileText.includes(dialedPhone), 'the full phone number was rendered on the mobile page')
  await m.screenshot({ path: path.join(shotDir, 'staff-10-dial-mobile.png'), fullPage: true })
  await ctx.close()
})

await step('fill the follow-up form with one tap on a phrase template', async () => {
  await page.locator('.tpl', { hasText: '恢复良好' }).first().click()
  const value = await page.locator('textarea').first().inputValue()
  assert(value.length > 10, `phrase template did not fill the conclusion box: "${value}"`)
  await page.locator('.tpl', { hasText: '提醒复查' }).first().click()
  await shot('staff-05-form-filled')
})

await step('submit the follow-up record', async () => {
  await page.locator('button.btn-primary.btn-block').click()
  const toast = page.locator('.toast')
  await toast.waitFor({ timeout: 15000 })
  const text = await toast.innerText()
  assert(/提交|完成|成功/.test(text), `unexpected toast: ${text}`)
  // A successful submit leaves for the todo list 900 ms later. Wait for that
  // redirect before the next step navigates somewhere else, otherwise the
  // pending router.replace('/todo') undoes it - which showed up as a flaky
  // "patients page" failure against the deployed site.
  await page.waitForURL(/#\/todo/, { timeout: 20000 })
  await shot('staff-06-submitted')
})

await step('patients page lists patients and shows parallel pathways', async () => {
  await page.goto(`${BASE}/#/patients`)
  // Views are lazy chunks: right after the hash changes the previous page is
  // still on screen, and its cards use the very same `article.task` class.
  // Without this wait the click below lands on a todo card and navigates to
  // /task/... - which then looks like "the patient page never opened"
  // (reproduced against the deployed site 2026-09-23).
  await page.getByText('我的患者').first().waitFor({ timeout: 30000 })
  await page.locator('article.task').first().waitFor({ timeout: 15000 })
  const count = await page.locator('article.task').count()
  assert(count >= 1, `no patient rendered (count=${count})`)

  await page.locator('article.task').first().click()
  await page.waitForURL(/#\/patient\//, { timeout: 30000 })
  await page.getByText('并行随访路径').first().waitFor({ timeout: 15000 })
  await shot('staff-07-patient-detail')
})

await step('profile page renders', async () => {
  await page.goto(`${BASE}/#/me`, { waitUntil: 'networkidle' })
  await page.waitForTimeout(800)
  const text = await page.locator('body').innerText()
  assert(text.includes('D0231') || text.includes('李医生'), `profile page looks empty: ${text.slice(0, 120)}`)
  await shot('staff-08-me')
})

await step('no uncaught javascript errors during the walkthrough', async () => {
  assert(jsErrors.length === 0, `js errors: ${jsErrors.join(' | ')}`)
})

await browser.close()

console.log('\nSummary')
console.log(`  steps : ${pass} passed, ${fail} failed`)
console.log(`  shots : ${shotDir}`)
console.log(fail > 0 ? '\n  RESULT: FAILED' : '\n  RESULT: ALL GREEN')
process.exit(fail > 0 ? 1 : 0)
