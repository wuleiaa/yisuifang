/**
 * Admin console UI walkthrough (real browser).
 *
 * Covers what the department actually asked for:
 *   - a normal doctor cannot get into the admin console
 *   - an admin can log in, search accounts, and create one
 *   - the initial password is shown once, in the UI
 *   - reset password / disable account work from the UI
 *
 * Usage:
 *   1) backend (8080) and the admin dev server (5175) running
 *   2) node tools/ui-check-admin.mjs
 */

import { createRequire } from 'node:module'
import { mkdirSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import path from 'node:path'

const require = createRequire(import.meta.url)
const PLAYWRIGHT_CORE =
  'C:/Users/wulei/AppData/Roaming/npm/node_modules/.openclaw-GciWGhVN/node_modules/playwright-core'
const CHROMIUM = 'C:/Users/wulei/AppData/Local/ms-playwright/chromium-1237/chrome-win64/chrome.exe'
const BASE = process.env.ADMIN_BASE_URL || 'http://127.0.0.1:5175'
const ADMIN_NO = process.env.ADMIN_NO || 'A0001'
const ADMIN_PWD = process.env.ADMIN_PWD || 'Followup@2026'

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
    console.log(`  PASS  ${name.padEnd(50)} ${String(Date.now() - t0).padStart(5)} ms`)
  } catch (e) {
    fail++
    console.log(`  FAIL  ${name.padEnd(50)} ${String(Date.now() - t0).padStart(5)} ms`)
    console.log(`        ${e.message}`)
  }
}

function assert(cond, msg) {
  if (!cond) throw new Error(msg)
}

const { chromium } = require(PLAYWRIGHT_CORE)
const browser = await chromium.launch({ executablePath: CHROMIUM, args: ['--no-sandbox'] })
const jsErrors = []

async function freshPage() {
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 }, locale: 'zh-CN' })
  const p = await ctx.newPage()
  p.on('pageerror', (e) => jsErrors.push(e.message))
  return p
}

let page = await freshPage()
async function shot(name) {
  await page.screenshot({ path: path.join(shotDir, `${name}.png`), fullPage: false })
}

async function login(p, no, pwd) {
  await p.goto(`${BASE}/#/login`, { waitUntil: 'networkidle' })
  await p.fill('input[placeholder="如 A0001"]', no)
  await p.fill('input[type="password"]', pwd)
  await p.locator('button[type="submit"]').click()
}

const testNo = 'T8' + new Date().toTimeString().slice(0, 8).replace(/:/g, '')

console.log(`\nAdmin console UI walkthrough  (${BASE})`)

await step('login page renders with hospital photo', async () => {
  await page.goto(`${BASE}/#/login`, { waitUntil: 'networkidle' })
  const title = await page.locator('.login-visual .cn').innerText()
  assert(title.includes('随访管理后台'), `unexpected title: ${title}`)
  assert(await page.locator('.login-visual img').isVisible(), 'hero photo missing')
  await shot('admin-01-login')
})

await step('a plain doctor is refused with a clear message', async () => {
  await login(page, 'D0231', 'Followup@2026')
  const err = page.locator('.notice.err')
  await err.waitFor({ timeout: 10000 })
  const msg = await err.innerText()
  assert(msg.includes('不是管理员') || msg.includes('管理权限'), `unexpected message: ${msg}`)
  assert(page.url().includes('#/login'), 'a non-admin was allowed into the console')
  await shot('admin-02-not-admin')
})

await step('admin logs in and lands on account management', async () => {
  page = await freshPage()
  await login(page, ADMIN_NO, ADMIN_PWD)
  await page.waitForURL(/#\/accounts/, { timeout: 15000 })
  await page.locator('table tbody tr').first().waitFor({ timeout: 15000 })
  await shot('admin-03-accounts')
})

await step('account list shows the demo staff', async () => {
  const text = await page.locator('table').innerText()
  for (const no of ['D0231', 'N0455', 'N0001', 'A0001']) {
    assert(text.includes(no), `staff ${no} missing from the table`)
  }
})

await step('search by staff number filters the table', async () => {
  await page.fill('input[placeholder="查账号：输入工号 / 姓名 / 手机号"]', 'D0231')
  await page.keyboard.press('Enter')
  await page.waitForTimeout(600)
  const rows = await page.locator('table tbody tr').count()
  assert(rows === 1, `expected 1 row, got ${rows}`)
  await page.locator('.toolbar button', { hasText: '清空条件' }).click()
  await page.waitForTimeout(600)
})

let created = false

await step('create a nurse account and see the one-time password', async () => {
  await page.locator('button', { hasText: '新建账号' }).click()
  await page.locator('.dialog').waitFor({ timeout: 8000 })
  await page.fill('.dialog input[placeholder="如 D0232"]', testNo)
  await page.fill('.dialog input[placeholder="如 王医生"]', 'UI Test Nurse')
  await page.locator('.dialog select').first().selectOption('NURSE')
  await page.locator('.dialog button', { hasText: '创建账号' }).click()

  await page.locator('.onetime').waitFor({ timeout: 15000 })
  const pw = (await page.locator('.onetime .pw').innerText()).trim()
  assert(pw.length >= 8, `one-time password looks wrong: "${pw}"`)
  assert((await page.locator('.onetime').innerText()).includes(testNo), 'staff number not shown')
  created = true
  await shot('admin-04-created')
})

await step('reset password from the table shows a new one-time password', async () => {
  await page.locator('.onetime').first().waitFor({ timeout: 8000 })
  const first = (await page.locator('.onetime .pw').innerText()).trim()
  // the close button sits below the panel, not inside it
  await page.locator('button', { hasText: '我已抄下' }).click()

  page.once('dialog', (d) => d.accept())
  const row = page.locator('table tbody tr', { hasText: testNo }).first()
  await row.locator('button', { hasText: '重置密码' }).click()

  await page.locator('.onetime').waitFor({ timeout: 15000 })
  const second = (await page.locator('.onetime .pw').innerText()).trim()
  assert(second !== first, 'the reset password equals the original one')
  await shot('admin-05-reset')
})

await step('disable the test account from the table', async () => {
  await page.locator('button', { hasText: '我已抄下' }).click()
  page.once('dialog', (d) => d.accept())
  const row = page.locator('table tbody tr', { hasText: testNo }).first()
  await row.locator('button', { hasText: '停用' }).click()
  await page.waitForTimeout(1200)

  const rowText = await page.locator('table tbody tr', { hasText: testNo }).first().innerText()
  assert(rowText.includes('已停用'), `account not disabled: ${rowText}`)
  await shot('admin-06-disabled')
})

await step('overview page shows numbers', async () => {
  await page.locator('.nav button', { hasText: '概览' }).click()
  await page.waitForURL(/#\/overview/, { timeout: 10000 })
  await page.locator('.stat').first().waitFor({ timeout: 10000 })
  const stats = await page.locator('.stat').count()
  assert(stats >= 6, `expected at least 6 stats, got ${stats}`)
  await shot('admin-07-overview')
})

await step('login records page lists attempts', async () => {
  await page.locator('.nav button', { hasText: '登录记录' }).click()
  await page.waitForURL(/#\/logins/, { timeout: 10000 })
  await page.locator('table tbody tr').first().waitFor({ timeout: 10000 })
  const text = await page.locator('table').innerText()
  assert(text.includes('成功') || text.includes('失败'), 'no login rows rendered')
  await shot('admin-08-logins')
})

await step('no uncaught javascript errors during the walkthrough', async () => {
  assert(jsErrors.length === 0, `js errors: ${jsErrors.join(' | ')}`)
  assert(created, 'the account creation step did not complete')
})

await browser.close()

console.log('\nSummary')
console.log(`  steps : ${pass} passed, ${fail} failed`)
console.log(`  shots : ${shotDir}`)
console.log(fail > 0 ? '\n  RESULT: FAILED' : '\n  RESULT: ALL GREEN')
process.exit(fail > 0 ? 1 : 0)
