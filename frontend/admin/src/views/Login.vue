<script setup>
import { ref, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { api, setSession, getToken } from '../api'

const router = useRouter()
const staffNo = ref('')
const password = ref('')
const loading = ref(false)
const error = ref('')

onMounted(() => {
  staffNo.value = localStorage.getItem('admin_last_staff_no') || ''
  if (getToken()) router.replace({ name: 'accounts' })
})

async function submit() {
  error.value = ''
  if (!staffNo.value.trim() || !password.value) {
    error.value = '请输入工号和密码'
    return
  }
  loading.value = true
  try {
    const data = await api.login(staffNo.value.trim(), password.value)
    // 能登录不等于能管理：这里再确认一次是不是管理员
    if (!data.profile?.admin) {
      error.value = '该账号不是管理员，无法进入管理后台。医护日常随访请使用随访工作台。'
      return
    }
    setSession(data.token, data.profile)
    localStorage.setItem('admin_last_staff_no', staffNo.value.trim())
    // 被要求先改密的人直接送到改密页，否则进去也是到处报错
    router.replace({ name: data.profile?.mustChangePassword ? 'changePassword' : 'accounts' })
  } catch (e) {
    error.value = e.message || '登录失败'
  } finally {
    loading.value = false
  }
}
</script>

<template>
  <div class="login-page">
    <div class="login-visual">
      <img src="/photos/hospital-reception.jpg" alt="" />
      <div class="txt">
        <div class="cn">随访管理后台</div>
        <div class="en">Follow-up Administration</div>
        <div class="org">XX 市第一人民医院 · 消化内科</div>
      </div>
    </div>

    <div class="login-form">
      <form class="login-box" @submit.prevent="submit">
        <h1>管理员登录</h1>
        <div class="sub">管理医护账号、角色与登录记录</div>

        <div v-if="error" class="notice err">{{ error }}</div>

        <label>管理员工号</label>
        <input v-model="staffNo" type="text" placeholder="如 A0001" autocomplete="username" />

        <label>密码</label>
        <input v-model="password" type="password" placeholder="请输入密码" autocomplete="current-password" />

        <button class="btn" type="submit" :disabled="loading">
          {{ loading ? '登录中…' : '登 录' }}
        </button>

        <div class="foot">
          管理账号由系统管理员创建<br />
          普通医护请使用随访工作台登录
        </div>
      </form>
    </div>
  </div>
</template>
