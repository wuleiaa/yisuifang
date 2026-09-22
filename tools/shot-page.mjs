/**
 * Screenshot a local HTML page (usually a design proposal in prototype/).
 *
 * Usage: node tools/shot-page.mjs prototype/style-v2.html style-v2-full.png [width]
 */

import { createRequire } from 'node:module'
import { mkdirSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import path from 'node:path'

const require = createRequire(import.meta.url)
const PLAYWRIGHT_CORE =
  'C:/Users/wulei/AppData/Roaming/npm/node_modules/.openclaw-GciWGhVN/node_modules/playwright-core'
const CHROMIUM = 'C:/Users/wulei/AppData/Local/ms-playwright/chromium-1237/chrome-win64/chrome.exe'

const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const rel = process.argv[2]
const outName = process.argv[3] || 'page.png'
const width = Number(process.argv[4] || 1560)

if (!rel) {
  console.error('usage: node tools/shot-page.mjs <relative-html> [out.png] [width]')
  process.exit(1)
}

const target = path.join(projectRoot, rel)
const outDir = path.join(projectRoot, 'output', 'playwright')
mkdirSync(outDir, { recursive: true })
const out = path.join(outDir, outName)

const { chromium } = require(PLAYWRIGHT_CORE)
const browser = await chromium.launch({ executablePath: CHROMIUM, args: ['--no-sandbox'] })
const page = await browser.newPage({ viewport: { width, height: 1000 }, deviceScaleFactor: 1.4 })
await page.goto('file:///' + target.replace(/\\/g, '/'), { waitUntil: 'load' })
await page.waitForTimeout(1500)
await page.screenshot({ path: out, fullPage: true })
await browser.close()
console.log(out)
