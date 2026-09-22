/**
 * Try a batch of candidate photo URLs, keep the ones that actually download.
 *
 * Everything here is hosted on images.unsplash.com (Unsplash licence: free for
 * commercial use, no attribution required). Hosts that are blocked from this
 * network are reported instead of being silently skipped.
 */

import { mkdirSync, writeFileSync, statSync } from 'node:fs'
import path from 'node:path'

const UA =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'

const OUT = 'output/photo-candidates'
mkdirSync(OUT, { recursive: true })

// Unsplash image ids, grouped by the role they would play in the UI.
const CANDIDATES = [
  { role: 'hospital-reception', id: 'photo-1519494026892-80bbd2d6fd0d' },
  { role: 'hospital-corridor', id: 'photo-1538108149393-fbbd81895907' },
  { role: 'hospital-building', id: 'photo-1587351021759-3e566b6af7cc' },
  { role: 'hospital-building-2', id: 'photo-1516549655169-df83a0774514' },
  { role: 'doctor-patient', id: 'photo-1576091160399-112ba8d25d1d' },
  { role: 'doctor-patient-2', id: 'photo-1631217868264-e5b90bb7e133' },
  { role: 'doctor-portrait', id: 'photo-1612349317150-e413f6a5b16d' },
  { role: 'nurse-patient', id: 'photo-1584515933487-779824d29309' },
  { role: 'medical-team', id: 'photo-1631815589968-fdb09a223b1e' },
  { role: 'stethoscope', id: 'photo-1584982751601-97dcc096659c' },
  { role: 'medical-desk', id: 'photo-1504813184591-01572f98c85f' },
  { role: 'surgery-team', id: 'photo-1551190822-a9333d879b1f' },
  { role: 'waiting-room', id: 'photo-1629909613654-28e377c37b09' },
  { role: 'elderly-patient', id: 'photo-1559839734-2b71ea197ec2' },
  { role: 'handshake-care', id: 'photo-1576765608535-5f04d1e3f289' },
  { role: 'pharmacy', id: 'photo-1587854692152-cbe660dbde88' }
]

const results = []

for (const c of CANDIDATES) {
  const url = `https://images.unsplash.com/${c.id}?auto=format&fit=crop&w=1600&q=80`
  const file = path.join(OUT, `${c.role}.jpg`)
  try {
    const res = await fetch(url, { headers: { 'User-Agent': UA } })
    if (!res.ok) {
      results.push({ ...c, ok: false, status: res.status })
      console.log(`  ${String(res.status).padStart(3)}  ${c.role}`)
      continue
    }
    const buf = Buffer.from(await res.arrayBuffer())
    if (buf.length < 8000) {
      results.push({ ...c, ok: false, status: res.status, note: 'suspiciously small' })
      console.log(`  small ${c.role} (${buf.length} bytes)`)
      continue
    }
    writeFileSync(file, buf)
    results.push({ ...c, ok: true, bytes: buf.length, file })
    console.log(`  200  ${c.role.padEnd(20)} ${(buf.length / 1024).toFixed(0)} KB`)
  } catch (e) {
    results.push({ ...c, ok: false, note: e.message })
    console.log(`  ERR  ${c.role}  ${e.message}`)
  }
}

writeFileSync(path.join(OUT, 'index.json'), JSON.stringify(results, null, 2), 'utf8')
const ok = results.filter((r) => r.ok)
console.log(`\ndownloaded ${ok.length} / ${CANDIDATES.length}`)
