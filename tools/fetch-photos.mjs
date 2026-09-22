/**
 * Find freely-licensed professional photos for the UI.
 *
 * Why this way: the hospital system needs real photography (hospital halls,
 * consultation scenes, clinical detail), not AI-generated images. Downloading
 * whatever a search engine returns is a copyright trap, so this script only
 * keeps original image URLs hosted on Pexels / Unsplash CDNs — both are free
 * for commercial use without attribution.
 *
 * Usage:  node tools/fetch-photos.mjs [outfile.json]
 */

import { writeFileSync } from 'node:fs'

const UA =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'

// Only these hosts: permissive licences, and both CDNs are reachable here.
const ALLOWED_HOSTS = ['images.pexels.com', 'images.unsplash.com', 'cdn.pixabay.com']

const QUERIES = [
  'site:pexels.com/photo hospital building exterior',
  'site:pexels.com/photo hospital corridor',
  'site:pexels.com/photo doctor patient consultation',
  'site:pexels.com/photo nurse talking to patient',
  'site:pexels.com/photo medical team doctors meeting',
  'site:pexels.com/photo stethoscope medical record desk',
  'site:pexels.com/photo hospital reception waiting room',
  'site:pexels.com/photo doctor smiling elderly patient',
  'site:pexels.com/photo surgical team operating room',
  'site:pexels.com/photo doctor writing prescription'
]

async function bingImages(query, first = 1) {
  const url =
    'https://www.bing.com/images/search?q=' +
    encodeURIComponent(query) +
    `&first=${first}&count=35&qft=+filterui:photo-photo&form=IRFLTR`
  const res = await fetch(url, {
    headers: { 'User-Agent': UA, 'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8' }
  })
  return res.text()
}

/**
 * Bing web search -> pexels.com/photo/<slug>-<id>/ links.
 * The trailing number IS the image id, and the CDN URL can be built from it:
 *   https://images.pexels.com/photos/<id>/pexels-photo-<id>.jpeg
 */
async function bingWeb(query, first = 1) {
  const url =
    'https://www.bing.com/search?q=' + encodeURIComponent(query) + `&first=${first}&count=30`
  const res = await fetch(url, {
    headers: { 'User-Agent': UA, 'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8' }
  })
  return res.text()
}

function extractPexelsIds(html) {
  const ids = new Set()
  // Bing wraps every result link: /ck/a?...&u=a1<base64url of the real URL>
  const decoded = []
  const reU = /[?&]u=a1([A-Za-z0-9_\-]+)/g
  let mu
  while ((mu = reU.exec(html)) !== null) {
    try {
      let b = mu[1].replace(/-/g, '+').replace(/_/g, '/')
      while (b.length % 4) b += '='
      decoded.push(Buffer.from(b, 'base64').toString('utf8'))
    } catch {
      /* ignore malformed */
    }
  }
  const pool = decoded.length ? decoded.join('\n') + '\n' + html : html

  const re = /pexels\.com\/photo\/[a-z0-9\-%]*?(\d{4,8})\/?["'\\&\s]/gi
  let m
  while ((m = re.exec(pool)) !== null) ids.add(m[1])
  // also catch bare /photo/<slug>-<id> without trailing quote
  const re2 = /pexels\.com\/photo\/[a-z0-9\-%]*?(\d{4,8})(?:\/|$)/gi
  while ((m = re2.exec(pool)) !== null) ids.add(m[1])
  return [...ids]
}

/** Bing wraps each result as m="{...json...}" containing "murl":"..." */
function extractImageUrls(html) {
  const out = []
  const patterns = [/"murl":"(https?:\\?\/\\?\/[^"]+?)"/g, /&quot;murl&quot;:&quot;(https?:[^&]+?)&quot;/g]
  for (const re of patterns) {
    let m
    while ((m = re.exec(html)) !== null) {
      out.push(m[1].replace(/\\\//g, '/'))
    }
  }
  return out
}

function hostOf(u) {
  try {
    return new URL(u).host
  } catch {
    return ''
  }
}

const found = new Map()
const allHosts = {}

for (const q of QUERIES) {
  try {
    const html = await bingWeb(q)
    const urls = extractImageUrls(html)
    for (const u of urls) {
      const h = hostOf(u) || '(bad)'
      allHosts[h] = (allHosts[h] || 0) + 1
    }

    const ids = extractPexelsIds(html)
    let kept = 0
    for (const id of ids) {
      const url = `https://images.pexels.com/photos/${id}/pexels-photo-${id}.jpeg?auto=compress&cs=tinysrgb&w=1600`
      const key = `pexels-${id}`
      if (found.has(key)) continue
      found.set(key, { key, id, url, host: 'images.pexels.com', query: q })
      kept++
    }
    console.log(`${String(kept).padStart(2)} ids / ${String(ids.length).padStart(3)} seen   ${q}`)
  } catch (e) {
    console.log(`  0 ids                ${q}   (${e.message})`)
  }
  await new Promise((r) => setTimeout(r, 700))
}

const list = [...found.values()]
const outFile = process.argv[2] || 'output/photo-candidates.json'
writeFileSync(outFile, JSON.stringify(list, null, 2), 'utf8')

console.log(`\ntotal candidates: ${list.length}`)
const byHost = {}
for (const c of list) byHost[c.host] = (byHost[c.host] || 0) + 1
console.log(byHost)
const topHosts = Object.entries(allHosts).sort((a, b) => b[1] - a[1]).slice(0, 15)
console.log('\nhosts seen in raw results:')
for (const [h, n] of topHosts) console.log(`  ${String(n).padStart(4)}  ${h}`)
console.log(`written to ${outFile}`)
