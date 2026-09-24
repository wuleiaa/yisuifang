<script setup>
import { ref, onMounted } from 'vue'
import { useRouter, useRoute } from 'vue-router'
import { api, setSession, clearSession } from '../api'
import { syncReminders, bindNotificationTap } from '../notifications'

const router = useRouter()
const route = useRoute()

const staffNo = ref('')
const password = ref('')
const loading = ref(false)
const error = ref('')

/**
 * 登录方式：
 *   staff — 医护登录，进入随访工作台
 *   admin — 管理员登录，进入管理后台（能建账号、重置密码）
 * 两者是同一套工号密码体系，区别只在"这个账号有没有管理权限"。
 */
const mode = ref('staff')

/**
 * 管理后台地址。
 *   线上：管理后台与医护端同一个域名、同一个端口，挂在 /admin/ 下面，
 *         所以这里必须用相对路径 /admin/ —— 写死 127.0.0.1 会让每个人的浏览器
 *         都跳回自己电脑（而且跨源还拿不到刚存下的登录态）。
 *   本地开发：管理后台跑在 5175 端口，用 vite 的 DEV 标记区分。
 * 需要临时指向别处时，构建前设 VITE_ADMIN_URL 覆盖。
 */
const adminUrl = import.meta.env.VITE_ADMIN_URL
  || (import.meta.env.DEV ? 'http://127.0.0.1:5175' : '/admin/')

// 开发便利：记住上次工号（不记密码）
onMounted(() => {
  staffNo.value = localStorage.getItem('followup_last_staff_no') || ''
})

async function submit() {
  error.value = ''
  if (!staffNo.value.trim()) {
    error.value = '请输入工号'
    return
  }
  if (!password.value) {
    error.value = '请输入密码'
    return
  }

  loading.value = true
  try {
    const data = await api.login(staffNo.value.trim(), password.value)
    clearSession()
    setSession(data.token, data.profile)
    localStorage.setItem('followup_last_staff_no', staffNo.value.trim())
    if (data.profile?.mustChangePassword) {
      sessionStorage.setItem('followup_must_change_pwd', '1')
    }
    if (mode.value === 'admin') {
      // 能登录 ≠ 能管理：必须确认这个账号确实有管理权限
      if (!data.profile?.admin) {
        clearSession()
        error.value = '该账号没有管理权限。如需管理账号，请联系系统管理员开通。'
        return
      }
      window.location.href = adminUrl
      return
    }
    // 登录成功后立刻同步一次提醒排程（安卓壳里才真正做事）
    bindNotificationTap()
    syncReminders().catch(() => {})
    router.replace(route.query.redirect || '/todo')
  } catch (e) {
    error.value = e.message || '登录失败'
  } finally {
    loading.value = false
  }
}
</script>

<template>
  <div class="login">
    <div class="login-hero">
      <img src="/photos/hospital-building.jpg" alt="" />
      <div class="hero-txt">
        <div class="cn">随访工作台</div>
        <div class="en">Follow-up Workstation</div>
        <div class="org">XX 市第一人民医院 · 消化内科</div>
      </div>
    </div>

    <div class="login-body">
      <form class="card" @submit.prevent="submit">
        <div class="seg">
          <button type="button" :class="{ on: mode === 'staff' }" @click="mode = 'staff'; error = ''">
            医护登录
          </button>
          <button type="button" :class="{ on: mode === 'admin' }" @click="mode = 'admin'; error = ''">
            管理员登录
          </button>
        </div>

        <div class="mode-hint">
          {{ mode === 'admin' ? '管理员可新建医护账号、重置密码、查看登录记录' : '日常随访工作：待办、回访、患者信息' }}
        </div>

        <label class="label">工号</label>
        <div class="field">
          <svg viewBox="0 0 24 24"><path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2" /><circle cx="12" cy="7" r="4" /></svg>
          <input
            v-model="staffNo"
            type="text"
            :placeholder="mode === 'admin' ? '如 A0001' : '请输入工号'"
            autocomplete="username"
          />
        </div>
        <label class="label">密码</label>
        <div class="field">
          <svg viewBox="0 0 24 24"><rect x="4" y="11" width="16" height="9" rx="2" /><path d="M8 11V7a4 4 0 0 1 8 0v4" /></svg>
          <input v-model="password" type="password" placeholder="请输入密码" autocomplete="current-password" />
        </div>

        <div v-if="error" class="err">{{ error }}</div>

        <button class="submit" type="submit" :disabled="loading">
          {{ loading ? '登录中…' : (mode === 'admin' ? '进入管理后台' : '登 录') }}
        </button>
      </form>

      <div class="foot">
        账号由管理员创建，不支持自助注册<br />
        登录即表示同意《数据安全与隐私保护规定》
      </div>
    </div>
  </div>
</template>
