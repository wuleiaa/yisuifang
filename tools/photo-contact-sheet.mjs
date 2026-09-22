/**
 * Render every downloaded candidate into one contact sheet image so a human
 * (or the model) can look at them all at once and pick the keepers.
 *
 * Usage: node tools/photo-contact-sheet.mjs
 */

import { createRequire } from 'node:module'
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import path from 'node:path'

const require = createRequire(import.meta.url)
const PLAYWRIGHT_CORE =
  'C:/Users/wulei/AppData/Roaming/npm/node_modules/.openclaw-GciWGhVN/node_modules/playwright-core'
const CHROMIUM = 'C:/Users/wulei/AppData/Local/ms-playwright/chromium-1237/chrome-win64/chrome.exe'

const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const dir = path.join(projectRoot, 'output', 'photo-candidates')
const list = JSON.parse(readFileSync(path.join(dir, 'index.json'), 'utf8')).filter((r) => r.ok)

const cards = list
  .map(
    (r) => `
  <figure>
    <img src="${path.basename(r.file)}" alt="${r.role}" />
    <figcaption>${r.role}</figcaption>
  </figure>`
  )
  .join('')

const html = `<!DOCTYPE html><html lang="zh-CN"><head><meta charset="utf-8" />
<style>
  body { margin: 0; padding: 22px; background: #f7f8f9; font-family: "Microsoft YaHei", sans-serif; }
  h1 { font-size: 20px; margin: 0 0 4px; color: #173d5c; }
  p.hint { margin: 0 0 18px; color: #6b7280; font-size: 13px; }
  .grid { display: grid; grid-template-columns: repeat(4, 1fr); gap: 14px; }
  figure { margin: 0; background: #fff; border: 1px solid #e8ebef; border-radius: 8px; overflow: hidden; }
  img { width: 100%; height: 150px; object-fit: cover; display: block; }
  figcaption { font-size: 12px; padding: 6px 8px; color: #374151; }
</style></head><body>
<h1>候选图片（Unsplash，免费商用）</h1>
<p class="hint">每张下面的名字是我给它预留的用途，请对照内容挑选。</p>
<div class="grid">${cards}</div>
</body></html>`

const sheetPath = path.join(dir, 'contact-sheet.html')
writeFileSync(sheetPath, html, 'utf8')

const { chromium } = require(PLAYWRIGHT_CORE)
const browser = await chromium.launch({ executablePath: CHROMIUM, args: ['--no-sandbox'] })
const page = await browser.newPage({ viewport: { width: 1280, height: 900 }, deviceScaleFactor: 1.5 })
await page.goto('file:///' + sheetPath.replace(/\\/g, '/'), { waitUntil: 'load' })
await page.waitForTimeout(1200)
mkdirSync(path.join(projectRoot, 'output', 'playwright'), { recursive: true })
const out = path.join(projectRoot, 'output', 'playwright', 'photo-contact-sheet.png')
await page.screenshot({ path: out, fullPage: true })
await browser.close()
console.log(`contact sheet: ${out}`)
