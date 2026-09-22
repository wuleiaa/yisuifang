<script setup>
import { ref, computed } from 'vue'
import { useRouter } from 'vue-router'
import { api, getProfile, markPasswordChanged } from '../api'

const router = useRouter()
const profile = getProfile()

const oldPassword = ref('')
const newPassword = ref('')
const confirmPassword = ref('')
const busy = ref(false)
const error = ref('')
const done = ref(false)

/** 被强制过来的（首次登录 / 管理员刚重置过密码）改完才让走 */
const forced = computed(() => !!profile?.mustChangePassword)

const canSubmit = computed(
  () =>
    oldPassword.value.length > 0 &&
    newPassword.value.length >= 8 &&
    newPassword.value === confirmPassword.value &&
    !busy.value
)

async function submit() {
  error.value = ''
  if (newPassword.value !== confirmPassword.value) {
    error.value = '两次输入的新密码不一致'
    return
  }
  busy.value = true
  try {
    await api.changePassword(oldPassword.value, newPassword.value)
    markPasswordChanged()
    done.value = true
    setTimeout(() => router.replace({ name: 'accounts' }), 1200)
  } catch (e) {
    error.value = e.message || '修改失败'
  } finally {
    busy.value = false
  }
}
</script>

<template>
  <div class="page">
    <div class="page-head">
      <div>
        <h2>修改密码</h2>
        <div class="sub">{{ profile?.name || '管理员' }} · {{ profile?.staffNo || '' }}</div>
      </div>
    </div>

    <div v-if="forced" class="notice info">
      为了账号安全，请先把初始密码改成你自己的密码，改完就能正常使用管理后台。
    </div>

    <div v-if="done" class="notice ok">密码已修改成功，正在进入系统…</div>

    <div v-else class="card" style="max-width: 460px">
      <div v-if="error" class="notice err">{{ error }}</div>

      <div style="margin-bottom: 12px">
        <label style="display: block; margin-bottom: 6px; font-size: 13px">原密码</label>
        <input v-model="oldPassword" type="password" placeholder="初始密码或你当前在用的密码" />
      </div>

      <div style="margin-bottom: 12px">
        <label style="display: block; margin-bottom: 6px; font-size: 13px">新密码</label>
        <input v-model="newPassword" type="password" placeholder="至少 8 位，含字母和数字" />
      </div>

      <div style="margin-bottom: 12px">
        <label style="display: block; margin-bottom: 6px; font-size: 13px">再输一次</label>
        <input v-model="confirmPassword" type="password" placeholder="重复新密码" />
      </div>

      <p style="color: var(--ink-3); font-size: 12.5px; margin: 4px 0 14px">
        建议用一句只有你自己记得住的话 + 数字，别用工号后六位或生日。
      </p>

      <button class="btn" :disabled="!canSubmit" @click="submit">
        {{ busy ? '提交中…' : '确认修改' }}
      </button>
    </div>
  </div>
</template>
