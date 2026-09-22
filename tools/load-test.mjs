/**
 * API load test (read-only).
 *
 * 为什么只读：压测脚本要能反复跑。写操作（领取任务、提交回访）会把演示数据消耗掉，
 * 也会掩盖真正的性能问题——写入正确性另有专门的并发测试。
 *
 * 验收标准（第 10 轮）：并发 20、P95 < 300 ms、失败率 0%。
 *
 * 用法：
 *   node tools/load-test.mjs                          # 默认 20 并发 / 30 秒
 *   node tools/load-test.mjs --concurrency 50 --duration 60
 *   node tools/load-test.mjs --scenario login         # 只压登录
 *   node tools/load-test.mjs --base http://127.0.0.1:8080
 */

const args = process.argv.slice(2)
function arg(name, def) {
  const i = args.indexOf(`--${name}`)
  return i >= 0 && args[i + 1] ? args[i + 1] : def
}

const BASE = arg('base', 'http://127.0.0.1:8080')
const CONCURRENCY = Number(arg('concurrency', 20))
const DURATION_S = Number(arg('duration', 30))
const WARMUP_S = Number(arg('warmup', 5))
const SCENARIO = arg('scenario', 'mixed')
const P95_LIMIT = Number(arg('p95', 300))

const STAFF = [
  { staffNo: 'D0231', password: 'Followup@2026' },
  { staffNo: 'N0455', password: 'Followup@2026' },
  { staffNo: 'N0001', password: 'Followup@2026' }
]
const ADMIN = { staffNo: 'A0001', password: 'Followup@2026' }
const PATIENT_PHONE = '13800000003'

// ---------------------------------------------------------------- HTTP

async function call(path, { token, method = 'GET', body } = {}) {
  const headers = { Accept: 'application/json' }
  if (token) headers.Authorization = `Bearer ${token}`
  if (body) headers['Content-Type'] = 'application/json; charset=utf-8'

  const t0 = performance.now()
  let status = 0
  let apiCode = null
  let ok = false
  try {
    const res = await fetch(BASE + path, {
      method,
      headers,
      body: body ? JSON.stringify(body) : undefined
    })
    status = res.status
    const text = await res.text()
    let json = null
    try {
      json = JSON.parse(text)
    } catch {
      /* 非 JSON，保留原文长度用于排查 */
    }
    apiCode = json?.code ?? null
    ok = res.ok && (apiCode === 0 || apiCode === null)
  } catch (e) {
    status = -1
  }
  const ms = performance.now() - t0
  return { ms, status, apiCode, ok }
}

async function login(staffNo, password) {
  const res = await fetch(BASE + '/api/auth/login', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=utf-8' },
    body: JSON.stringify({ staffNo, password })
  })
  if (!res.ok) return null
  const json = await res.json()
  return json?.code === 0 ? json.data.token : null
}

async function patientLogin() {
  const codeRes = await fetch(BASE + '/api/portal/auth/code', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=utf-8' },
    body: JSON.stringify({ phone: PATIENT_PHONE })
  })
  const codeJson = await codeRes.json()
  const code = codeJson?.data?.devCode
  if (!code) return null
  const loginRes = await fetch(BASE + '/api/portal/auth/login', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=utf-8' },
    body: JSON.stringify({ phone: PATIENT_PHONE, code })
  })
  const loginJson = await loginRes.json()
  return loginJson?.data?.token || null
}

// ---------------------------------------------------------------- 场景

function buildScenario(session, userIdx) {
  const staffToken = session.tokens[userIdx % session.tokens.length]
  const ops = []

  if (SCENARIO === 'mixed' || SCENARIO === 'todo') {
    ops.push(
      { name: 'GET /api/tasks/todo', w: 34, path: '/api/tasks/todo?scope=MINE&days=7&limit=100', token: staffToken },
      { name: 'GET /api/tasks/{id}', w: 14, path: () => `/api/tasks/${pick(session.taskIds)}`, token: staffToken },
      { name: 'GET /api/patients', w: 12, path: '/api/patients?limit=50', token: staffToken },
      { name: 'GET /api/patients/{id}', w: 8, path: () => `/api/patients/${pick(session.patientIds)}`, token: staffToken }
    )
  }
  if (SCENARIO === 'mixed' || SCENARIO === 'portal') {
    ops.push(
      { name: 'GET /api/portal/timeline', w: 12, path: '/api/portal/timeline', token: session.patientToken },
      { name: 'GET /api/portal/reports', w: 6, path: '/api/portal/reports', token: session.patientToken }
    )
  }
  if (SCENARIO === 'mixed' || SCENARIO === 'admin') {
    ops.push(
      { name: 'GET /api/admin/staff', w: 8, path: '/api/admin/staff', token: session.adminToken },
      { name: 'GET /api/admin/overview', w: 4, path: '/api/admin/overview', token: session.adminToken }
    )
  }
  if (SCENARIO === 'login') {
    ops.push({ name: 'POST /api/auth/login', w: 1, login: true })
  }
  return ops
}

function pick(list) {
  return list[Math.floor(Math.random() * list.length)]
}

function weighted(ops) {
  const total = ops.reduce((s, o) => s + o.w, 0)
  let r = Math.random() * total
  for (const o of ops) {
    r -= o.w
    if (r <= 0) return o
  }
  return ops[ops.length - 1]
}

// ---------------------------------------------------------------- 采样

const stats = new Map()
const global = { total: 0, errors: 0, byStatus: {} }

function record(name, r) {
  global.total++
  if (!r.ok) {
    global.errors++
    const key = r.status === -1 ? 'network' : `${r.status}/code=${r.apiCode}`
    global.byStatus[key] = (global.byStatus[key] || 0) + 1
  }
  let s = stats.get(name)
  if (!s) {
    s = { name, n: 0, err: 0, lat: [] }
    stats.set(name, s)
  }
  s.n++
  if (!r.ok) s.err++
  s.lat.push(r.ms)
}

function pct(arr, p) {
  if (!arr.length) return 0
  const a = [...arr].sort((x, y) => x - y)
  return a[Math.min(a.length - 1, Math.floor(a.length * p))]
}

// ---------------------------------------------------------------- 主流程

console.log(`\nLoad test  →  ${BASE}`)
console.log(`scenario=${SCENARIO}  concurrency=${CONCURRENCY}  duration=${DURATION_S}s  warmup=${WARMUP_S}s\n`)

// 准备会话：把 id 列表先抓出来，避免压测时才发现没有任务可查
const session = { tokens: [], taskIds: [], patientIds: [], patientToken: null, adminToken: null }

for (const s of STAFF) {
  const t = await login(s.staffNo, s.password)
  if (t) session.tokens.push(t)
}
session.adminToken = await login(ADMIN.staffNo, ADMIN.password)
session.patientToken = await patientLogin()

if (!session.tokens.length) {
  console.error('无法登录，压测终止。请确认后端已启动、演示数据已就绪。')
  process.exit(1)
}

{
  const r = await fetch(BASE + '/api/tasks/todo?scope=MINE&days=30&limit=100', {
    headers: { Authorization: `Bearer ${session.tokens[0]}` }
  })
  const j = await r.json()
  session.taskIds = (j?.data?.items || []).map((i) => i.id)
  const r2 = await fetch(BASE + '/api/patients?limit=50', {
    headers: { Authorization: `Bearer ${session.tokens[0]}` }
  })
  const j2 = await r2.json()
  session.patientIds = (j2?.data || []).map((i) => i.id)
}

if (!session.taskIds.length || !session.patientIds.length) {
  console.error('演示数据不完整（没有任务或患者），请先运行 tools/demo-reset.ps1')
  process.exit(1)
}

// 先按第一个虚拟用户生成一份，仅用于打印说明
const opsPreview = buildScenario(session, 0)
console.log(`endpoints: ${opsPreview.map((o) => o.name).join(', ')}`)
console.log(`ids: ${session.taskIds.length} tasks, ${session.patientIds.length} patients\n`)

let stopAt = 0

/** 一个虚拟用户：循环发请求直到时间到 */
async function virtualUser(idx) {
  // 每个虚拟用户用自己的身份令牌：真实场景里就是不同的人在用
  const ops = buildScenario(session, idx)
  while (performance.now() < stopAt) {
    const op = weighted(ops)
    if (op.login) {
      const s = pick(STAFF)
      const r = await call('/api/auth/login', { method: 'POST', body: s })
      record(op.name, r)
    } else {
      const path = typeof op.path === 'function' ? op.path() : op.path
      const r = await call(path, { token: op.token })
      record(op.name, r)
    }
  }
}

async function phase(seconds, label) {
  const start = performance.now()
  stopAt = start + seconds * 1000
  const users = Array.from({ length: CONCURRENCY }, (_, i) => virtualUser(i))
  await Promise.all(users)
  console.log(`${label} 用时 ${((performance.now() - start) / 1000).toFixed(1)}s，累计请求 ${global.total}`)
}

await phase(WARMUP_S, '预热')
// 预热数据不计入结果
for (const s of stats.values()) {
  s.n = 0
  s.err = 0
  s.lat = []
}
global.total = 0
global.errors = 0
global.byStatus = {}
console.log('')

const t0 = performance.now()
await phase(DURATION_S, '压测')
const elapsed = (performance.now() - t0) / 1000

// ---------------------------------------------------------------- 结果

console.log('\n按接口统计')
console.log('  ' + 'endpoint'.padEnd(30) + 'count'.padStart(7) + 'err'.padStart(6) + 'P50'.padStart(8) + 'P95'.padStart(8) + 'P99'.padStart(8) + 'max'.padStart(8))
const allLat = []
for (const s of [...stats.values()].sort((a, b) => b.n - a.n)) {
  allLat.push(...s.lat)
  console.log(
    '  ' +
      s.name.padEnd(30) +
      String(s.n).padStart(7) +
      String(s.err).padStart(6) +
      `${pct(s.lat, 0.5).toFixed(0)}ms`.padStart(8) +
      `${pct(s.lat, 0.95).toFixed(0)}ms`.padStart(8) +
      `${pct(s.lat, 0.99).toFixed(0)}ms`.padStart(8) +
      `${Math.max(...s.lat).toFixed(0)}ms`.padStart(8)
  )
}

const rps = (global.total / elapsed).toFixed(1)
const errRate = global.total ? (global.errors / global.total) * 100 : 0
const p95 = pct(allLat, 0.95)

console.log('\n汇总')
console.log(`  请求总数    ${global.total}`)
console.log(`  持续时间    ${elapsed.toFixed(1)} s`)
console.log(`  吞吐        ${rps} req/s`)
console.log(`  延迟        P50 ${pct(allLat, 0.5).toFixed(0)} ms · P95 ${p95.toFixed(0)} ms · P99 ${pct(allLat, 0.99).toFixed(0)} ms · max ${Math.max(...allLat).toFixed(0)} ms`)
console.log(`  失败        ${global.errors} (${errRate.toFixed(2)}%)`)
if (global.errors) {
  const detail = Object.entries(global.byStatus)
    .map(([k, v]) => `${k}×${v}`)
    .join(', ')
  console.log(`  失败构成    ${detail}`)
}

const pass = errRate === 0 && p95 <= P95_LIMIT
console.log('')
console.log(
  pass
    ? `  RESULT: PASS  (P95 ${p95.toFixed(0)}ms ≤ ${P95_LIMIT}ms，失败 0)`
    : `  RESULT: FAIL  (P95 ${p95.toFixed(0)}ms / 上限 ${P95_LIMIT}ms，失败 ${global.errors})`
)
process.exit(pass ? 0 : 1)
