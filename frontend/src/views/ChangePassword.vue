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

/** 首次登录是被强制过来的，改完才让走；主动进来的改完可以返回 */
const forced = computed(() => !!profile?.mustChangePassword)

// 前端只做基本校验，真正的规则以后端为准
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
    setTimeout(() => router.replace('/todo'), 1200)
  } catch (e) {
    error.value = e.message || '修改失败'
  } finally {
    busy.value = false
  }
}
</script>

<template>
  <div class="page">
    <header class="appbar">
      <button v-if="!forced" class="iconbtn" type="button" @click="router.back()">‹</button>
      <h1>修改密码<span class="sub">{{ profile?.name || '' }}</span></h1>
    </header>

    <div v-if="forced" class="notice warn" style="margin: 12px 14px">
      为了账号安全，请先把初始密码改成你自己的密码，改完就能正常使用。
    </div>

    <div v-if="done" class="notice ok" style="margin: 12px 14px">
      密码已修改成功，正在进入系统…
    </div>

    <template v-else>
      <section class="card m14">
        <div v-if="error" class="notice err" style="margin-bottom: 12px">{{ error }}</div>

        <div class="form-row">
          <label>原密码 <span class="req">*</span></label>
          <input v-model="oldPassword" type="password" placeholder="管理员给你的初始密码" />
        </div>

        <div class="form-row">
          <label>新密码 <span class="req">*</span></label>
          <input v-model="newPassword" type="password" placeholder="至少 8 位，含字母和数字" />
        </div>

        <div class="form-row">
          <label>再输一次 <span class="req">*</span></label>
          <input v-model="confirmPassword" type="password" placeholder="重复新密码" />
        </div>

        <p class="muted" style="margin-top: 4px">
          建议用一句只有你自己记得住的话 + 数字，别用工号后六位或生日。
        </p>
      </section>

      <div class="m14">
        <button class="btn-primary btn-block" type="button" :disabled="!canSubmit" @click="submit">
          {{ busy ? '提交中…' : '确认修改' }}
        </button>
      </div>
    </template>
  </div>
</template>
