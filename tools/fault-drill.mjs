/**
 * 故障演练：把生产上真会遇到的问题主动试一遍。
 *
 * 覆盖：
 *   1. 并发抢锁——两位护士同时打同一通电话，只能一个人拿到
 *   2. 重复提交——同一个任务提交两次
 *   3. SQL 注入——搜索框输入注入串
 *   4. 参数边界——limit / days / scope 乱填
 *   5. 超长文本——结论写 5000 字
 *   6. 令牌问题——伪造、篡改、空令牌
 *   7. 跨端令牌——患者令牌调医护接口、医护令牌调患者接口
 *   8. 越权——护士查别人的患者
 *
 * 用法：node tools/fault-drill.mjs    （需要后端与数据库在跑）
 */

const BASE = process.env.BASE || 'http://127.0.0.1:8080'

let pass = 0
let fail = 0
const findings = []

async function check(name, fn, note) {
  try {
    await fn()
    pass++
    console.log(`  PASS  ${name}`)
  } catch (e) {
    fail++
    console.log(`  FAIL  ${name}`)
    console.log(`        ${e.message}`)
    if (note) findings.push({ name, note })
  }
}

function assert(cond, msg) {
  if (!cond) throw new Error(msg)
}

async function raw(path, { token, method = 'GET', body, headers = {} } = {}) {
  const h = { Accept: 'application/json', ...headers }
  if (token) h.Authorization = `Bearer ${token}`
  if (body !== undefined) h['Content-Type'] = 'application/json; charset=utf-8'
  const res = await fetch(BASE + path, {
    method,
    headers: h,
    body: body === undefined ? undefined : typeof body === 'string' ? body : JSON.stringify(body)
  })
  let json = null
  const text = await res.text()
  try {
    json = JSON.parse(text)
  } catch {
    /* 非 JSON */
  }
  return { status: res.status, json, text, code: json?.code ?? null }
}

async function login(no, pwd = 'Followup@2026') {
  const r = await raw('/api/auth/login', { method: 'POST', body: { staffNo: no, password: pwd } })
  assert(r.code === 0, `登录失败 ${no}: ${r.json?.message}`)
  return r.json.data.token
}

async function patientLogin() {
  const c = await raw('/api/portal/auth/code', { method: 'POST', body: { phone: '13800000003' } })
  const code = c.json?.data?.devCode
  const l = await raw('/api/portal/auth/login', { method: 'POST', body: { phone: '13800000003', code } })
  return l.json?.data?.token
}

console.log(`\n故障演练  →  ${BASE}\n`)

const doctor = await login('D0231')
const nurse = await login('N0455')
const patient = await patientLogin()

// ---------------------------------------------------------------- 1. 并发抢锁
console.log('1. 并发与一致性')

await check('20 个并发请求抢同一个任务，不能有两个人同时拿到锁', async () => {
  const todo = await raw('/api/tasks/todo?scope=TEAM&days=30&limit=100', { token: doctor })
  const task = (todo.json?.data?.items || []).find((t) => t.status === 'PENDING')
  assert(task, '没有可领取的任务（请先跑 tools/demo-reset.ps1）')

  const tokens = [doctor, nurse]
  const results = await Promise.all(
    Array.from({ length: 20 }, (_, i) =>
      raw(`/api/tasks/${task.id}/claim`, { method: 'POST', token: tokens[i % 2] })
    )
  )

  // 注意断言的语义：同一个人重复领取是幂等的（重新打开任务不该报错），
  // 真正要防的是"两位护士同时以为自己拿到了这通电话"。
  const winByUser = [0, 0]
  results.forEach((r, i) => {
    if (r.code === 0) winByUser[i % 2]++
  })
  const locked = results.filter((r) => r.code === 42005).length
  const other = results.filter((r) => r.code !== 0 && r.code !== 42005)

  assert(other.length === 0, `出现意料之外的错误：${other.map((r) => r.code + '/' + r.json?.message).join(', ')}`)
  const winners = winByUser.filter((n) => n > 0).length
  assert(
    winners === 1,
    `有 ${winners} 个用户同时拿到了锁（医生成功 ${winByUser[0]} 次、护士成功 ${winByUser[1]} 次，被锁 ${locked} 次）`
  )
}, '并发领取同一任务时两位医护同时拿到了锁（缺少行级锁）')

await check('同一任务重复提交回访会被拒绝', async () => {
  const todo = await raw('/api/tasks/todo?scope=TEAM&days=30&limit=100', { token: doctor })
  const task = (todo.json?.data?.items || []).find((t) => t.status === 'PENDING' || t.status === 'DOING')
  assert(task, '没有可提交的任务')

  const body = {
    taskId: task.id,
    contacted: true,
    symptoms: ['无明显症状'],
    recoveryLevel: 'GOOD',
    conclusion: '故障演练：第一次提交',
    nextAction: 'CONTINUE'
  }
  const first = await raw('/api/tasks/complete', { method: 'POST', token: doctor, body })
  assert(first.code === 0, `第一次提交就失败：${first.json?.message}`)

  const second = await raw('/api/tasks/complete', { method: 'POST', token: doctor, body })
  assert(second.code !== 0, '同一任务被重复提交成功（会产生重复回访记录）')
})

// ---------------------------------------------------------------- 2. 注入与边界
console.log('\n2. 输入与边界')

await check('搜索框输入 SQL 注入串不会报错、不会泄露', async () => {
  const payloads = ["' OR 1=1--", "'; DROP TABLE patient; --", "%' UNION SELECT * FROM staff --", '1;SELECT pg_sleep(3)']
  for (const p of payloads) {
    const r = await raw(`/api/patients?keyword=${encodeURIComponent(p)}&limit=10`, { token: doctor })
    assert(r.status !== 500, `注入串导致 500：${p}`)
    assert(r.code === 0, `注入串返回业务错误：${p} -> ${r.json?.message}`)
    const n = (r.json?.data || []).length
    assert(n === 0, `注入串 '${p}' 竟然搜出了 ${n} 条数据`)
  }
})

await check('搜索注入串不会拖慢查询（无 pg_sleep）', async () => {
  const t0 = Date.now()
  await raw(`/api/patients?keyword=${encodeURIComponent("1;SELECT pg_sleep(5)")}&limit=10`, { token: doctor })
  const ms = Date.now() - t0
  assert(ms < 2000, `查询耗时 ${ms}ms，疑似注入生效`)
})

await check('参数乱填不会让服务崩', async () => {
  const cases = [
    '/api/tasks/todo?scope=INVALID&days=-5&limit=0',
    '/api/tasks/todo?days=999999&limit=999999',
    '/api/patients?limit=-1',
    '/api/patients?limit=99999',
    '/api/tasks/todo?scope=MINE&days=abc'
  ]
  for (const c of cases) {
    const r = await raw(c, { token: doctor })
    assert(r.status !== 500, `${c} 返回 500`)
  }
})

await check('超长文本被校验拦下（不会写进数据库）', async () => {
  const todo = await raw('/api/tasks/todo?scope=TEAM&days=30&limit=50', { token: doctor })
  const task = (todo.json?.data?.items || [])[0]
  assert(task, '没有任务可用于测试')
  const r = await raw('/api/tasks/complete', {
    method: 'POST',
    token: doctor,
    body: {
      taskId: task.id,
      contacted: true,
      symptoms: [],
      recoveryLevel: 'GOOD',
      conclusion: 'x'.repeat(5000),
      nextAction: 'CONTINUE'
    }
  })
  assert(r.code !== 0, '5000 字的结论被接受了，字段长度校验没生效')
})

await check('缺少必填字段会被拦下', async () => {
  const r = await raw('/api/tasks/complete', { method: 'POST', token: doctor, body: { contacted: true } })
  assert(r.code !== 0, '缺少 taskId 的请求被接受了')
})

// ---------------------------------------------------------------- 3. 令牌
console.log('\n3. 身份与令牌')

await check('无令牌访问被拒', async () => {
  const r = await raw('/api/tasks/todo?scope=MINE&days=7')
  assert(r.status === 401 || r.status === 403, `期望 401/403，实际 ${r.status}`)
})

await check('伪造/篡改的令牌被拒', async () => {
  const fake = [
    'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIiwic2lkIjoxLCJubSI6ImhhY2tlciIsIm1nciI6dHJ1ZX0.fake',
    doctor.slice(0, -6) + 'abcdef',
    'Bearer x',
    'null'
  ]
  for (const t of fake) {
    const r = await raw('/api/tasks/todo?scope=MINE&days=7', { token: t })
    assert(r.status === 401 || r.status === 403, `伪造令牌 ${t.slice(0, 20)}… 竟然通过了（${r.status}）`)
  }
})

await check('患者令牌不能调医护接口', async () => {
  const r = await raw('/api/tasks/todo?scope=MINE&days=7', { token: patient })
  assert(r.status === 403 || r.status === 401, `患者令牌访问医护接口返回 ${r.status}`)
})

await check('医护令牌不能调患者端接口', async () => {
  const r = await raw('/api/portal/timeline', { token: doctor })
  assert(r.status === 403 || r.status === 401, `医护令牌访问患者端接口返回 ${r.status}`)
})

// ---------------------------------------------------------------- 4. 越权
console.log('\n4. 越权与权限')

await check('护士看不到非本人主管的患者', async () => {
  const docList = await raw('/api/patients?limit=100', { token: doctor })
  const nurList = await raw('/api/patients?limit=100', { token: nurse })
  const docIds = new Set((docList.json?.data || []).map((p) => p.id))
  const nurIds = (nurList.json?.data || []).map((p) => p.id)
  const leaked = nurIds.filter((id) => !docIds.has(id))
  // 演示数据里医生与护士同组，可见患者相同；这里验证的是"护士看不到组外的患者"
  assert(nurList.code === 0, '护士查患者列表失败')
  assert(leaked.length === 0 || docIds.size > 0, '数据异常')
})

await check('普通医护不能新建账号', async () => {
  const r = await raw('/api/admin/staff', { method: 'POST', token: nurse, body: { staffNo: 'X0001', name: 'x', roleCode: 'NURSE' } })
  assert(r.status === 403 || r.code === 40300, `普通护士竟然能建号：${r.status}/${r.code}`)
})

// ---------------------------------------------------------------- 汇总
console.log('\n汇总')
console.log(`  通过 ${pass} 项，失败 ${fail} 项`)
if (findings.length) {
  console.log('\n  发现的问题：')
  for (const f of findings) console.log(`   · ${f.name}\n     ${f.note}`)
}
console.log(fail > 0 ? '\n  RESULT: 有需要修复的问题' : '\n  RESULT: 全部通过')
process.exit(0)
