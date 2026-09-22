<script setup>
import { ref, onMounted } from 'vue'
import { api } from '../api'

const list = ref([])
const roles = ref([])
const loading = ref(false)
const error = ref('')
const keyword = ref('')
const roleCode = ref('')
const status = ref('')

// 新建账号
const showCreate = ref(false)
const creating = ref(false)
const form = ref({ staffNo: '', name: '', roleCode: 'NURSE', title: '', gender: 1, phone: '' })

// 一次性密码展示（新建成功 / 重置成功共用）
const issue = ref(null) // { title, staffNo, name, password, message }

async function load() {
  loading.value = true
  error.value = ''
  try {
    const res = await api.staff({
      keyword: keyword.value.trim() || undefined,
      roleCode: roleCode.value || undefined,
      status: status.value || undefined
    })
    list.value = res.items || []
  } catch (e) {
    error.value = e.message
  } finally {
    loading.value = false
  }
}

function reset() {
  keyword.value = ''
  roleCode.value = ''
  status.value = ''
  load()
}

function openCreate() {
  form.value = { staffNo: '', name: '', roleCode: 'NURSE', title: '', gender: 1, phone: '' }
  error.value = ''
  showCreate.value = true
}

async function submitCreate() {
  creating.value = true
  error.value = ''
  try {
    const res = await api.createStaff({
      staffNo: form.value.staffNo.trim(),
      name: form.value.name.trim(),
      roleCode: form.value.roleCode,
      title: form.value.title.trim() || null,
      gender: Number(form.value.gender),
      phone: form.value.phone.trim()
    })
    showCreate.value = false
    issue.value = {
      title: '账号创建成功',
      staffNo: res.staffNo,
      name: res.name,
      password: res.initialPassword,
      message: res.message
    }
    load()
  } catch (e) {
    error.value = e.message
  } finally {
    creating.value = false
  }
}

async function doReset(row) {
  // 二次确认带上工号与姓名：万一传错了行，操作人在这一步就能看出来
  if (!confirm(`确定要重置这个账号的密码吗？\n\n工号：${row.staffNo}\n姓名：${row.name}\n\n旧密码会立即失效，且原密码无法查看。`)) return
  error.value = ''
  try {
    const res = await api.resetPassword(row.staffId)
    issue.value = {
      title: '密码已重置',
      staffNo: res.staffNo,
      name: res.name,
      password: res.tempPassword,
      message: res.message
    }
    load()
  } catch (e) {
    error.value = e.message
  }
}

async function toggleStatus(row) {
  const next = row.accountStatus === 'ACTIVE' ? 'DISABLED' : 'ACTIVE'
  const word = next === 'DISABLED' ? '停用' : '启用'
  if (!confirm(`确定${word} ${row.name}（${row.staffNo}）的账号？`)) return
  error.value = ''
  try {
    await api.setStatus(row.staffId, next)
    load()
  } catch (e) {
    error.value = e.message
  }
}

function statusTag(s) {
  if (s === 'ACTIVE') return { cls: 'ok', text: '正常' }
  if (s === 'DISABLED') return { cls: 'danger', text: '已停用' }
  return { cls: '', text: '未开通' }
}

/** 角色码 → 中文名（roles 接口返回的是 DOCTOR / NURSE 这类编码） */
function roleText(codes) {
  if (!codes) return '未分配'
  return String(codes)
    .split(',')
    .map((c) => roles.value.find((r) => r.code === c)?.name || c)
    .join('、')
}

onMounted(async () => {
  try {
    roles.value = await api.roles()
  } catch (e) {
    error.value = e.message
  }
  load()
})
</script>

<template>
  <div class="page-head">
    <div>
      <h1>账号管理</h1>
      <div class="sub">新建医护账号、查账号、重置密码、停用启用</div>
    </div>
    <button class="btn" @click="openCreate">
      <svg viewBox="0 0 24 24" style="width:16px;height:16px;stroke:currentColor;fill:none;stroke-width:1.8;stroke-linecap:round">
        <path d="M12 5v14M5 12h14" />
      </svg>
      新建账号
    </button>
  </div>

  <div v-if="error" class="notice err">{{ error }}</div>

  <div v-if="issue" class="card">
    <div class="onetime">
      <b>{{ issue.title }}</b> — {{ issue.name }}（{{ issue.staffNo }}）
      <div class="pw">{{ issue.password }}</div>
      <div class="warn">{{ issue.message }}</div>
    </div>
    <div style="margin-top: 12px">
      <button class="btn ghost sm" @click="issue = null">我已抄下，关闭</button>
    </div>
  </div>

  <div class="card">
    <div class="toolbar">
      <input
        v-model="keyword"
        class="grow"
        type="text"
        placeholder="查账号：输入工号 / 姓名 / 手机号"
        @keyup.enter="load"
      />
      <select v-model="roleCode" @change="load">
        <option value="">全部角色</option>
        <option v-for="r in roles" :key="r.code" :value="r.code">{{ r.name }}</option>
      </select>
      <select v-model="status" @change="load">
        <option value="">全部状态</option>
        <option value="ACTIVE">正常</option>
        <option value="DISABLED">已停用</option>
      </select>
      <button class="btn ghost" @click="load">查询</button>
      <button class="btn ghost" @click="reset">清空条件</button>
    </div>

    <div v-if="loading" class="empty">加载中…</div>

    <table v-else>
      <thead>
        <tr>
          <th style="width: 110px">工号</th>
          <th style="width: 100px">姓名</th>
          <th style="width: 130px">角色</th>
          <th style="width: 110px">职务</th>
          <th style="width: 100px">账号状态</th>
          <th>最近登录</th>
          <th style="width: 190px">操作</th>
        </tr>
      </thead>
      <tbody>
        <tr v-for="row in list" :key="row.staffId">
          <td>{{ row.staffNo }}</td>
          <td>{{ row.name }}</td>
          <td>
            <span class="tag brand">{{ roleText(row.roles) }}</span>
          </td>
          <td>{{ row.title || '—' }}</td>
          <td>
            <span class="tag" :class="statusTag(row.accountStatus).cls">
              {{ statusTag(row.accountStatus).text }}
            </span>
            <span v-if="row.mustChangePassword" class="tag warn" style="margin-left: 4px">待改密</span>
          </td>
          <td>
            <span v-if="row.lastLoginAt">{{ String(row.lastLoginAt).replace('T', ' ').slice(0, 16) }}</span>
            <span v-else style="color: var(--ink-3)">从未登录</span>
          </td>
          <td>
            <button class="btn ghost sm" @click="doReset(row)">重置密码</button>
            <button
              class="btn sm"
              :class="{ danger: row.accountStatus === 'ACTIVE' }"
              style="margin-left: 6px"
              @click="toggleStatus(row)"
            >
              {{ row.accountStatus === 'ACTIVE' ? '停用' : '启用' }}
            </button>
          </td>
        </tr>
      </tbody>
    </table>

    <div v-if="!loading && !list.length" class="empty">没有匹配的账号</div>
  </div>

  <div class="notice info" style="margin-top: 14px">
    <b>关于密码：</b>系统只保存不可逆的 BCrypt 哈希，<b>任何人也查不出原密码</b>（包括管理员）。
    新建账号或重置密码时，系统会生成一次性密码并在这里显示一次，请当场交给本人；
    本人首次登录后会被要求修改为自己的密码。
  </div>

  <!-- 新建账号 -->
  <div v-if="showCreate" class="mask" @click.self="showCreate = false">
    <div class="dialog">
      <h3>新建医护账号</h3>
      <div class="hint">创建成功后会显示一次性初始密码</div>

      <div class="row">
        <div>
          <label>工号 <span>*</span></label>
          <input v-model="form.staffNo" type="text" placeholder="如 D0232" />
        </div>
        <div>
          <label>姓名 <span>*</span></label>
          <input v-model="form.name" type="text" placeholder="如 王医生" />
        </div>
      </div>

      <label>角色 <span>*</span></label>
      <select v-model="form.roleCode">
        <option v-for="r in roles" :key="r.code" :value="r.code">{{ r.name }}（{{ r.code }}）</option>
      </select>

      <div class="row">
        <div>
          <label>职务</label>
          <input v-model="form.title" type="text" placeholder="如 主治医师" />
        </div>
        <div>
          <label>性别</label>
          <select v-model="form.gender">
            <option :value="1">男</option>
            <option :value="2">女</option>
          </select>
        </div>
      </div>

      <label>手机号（可不填）</label>
      <input v-model="form.phone" type="text" placeholder="11 位手机号" maxlength="11" />

      <div v-if="error" class="notice err" style="margin-top: 14px">{{ error }}</div>

      <div class="dialog-foot">
        <button class="btn ghost" @click="showCreate = false">取消</button>
        <button class="btn" :disabled="creating" @click="submitCreate">
          {{ creating ? '创建中…' : '创建账号' }}
        </button>
      </div>
    </div>
  </div>
</template>
