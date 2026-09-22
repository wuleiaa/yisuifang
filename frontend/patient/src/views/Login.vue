<script setup>
import { ref, computed } from 'vue'
import { useRouter } from 'vue-router'
import { api, setSession } from '../api'

const router = useRouter()

const phone = ref('')
const code = ref('')
const devCode = ref('')
const seconds = ref(0)
const sending = ref(false)
const busy = ref(false)
const error = ref('')
const agreed = ref(false)

const phoneOk = computed(() => /^1[3-9]\d{9}$/.test(phone.value.trim()))
const canSend = computed(() => phoneOk.value && seconds.value === 0 && !sending.value)
const canLogin = computed(() => phoneOk.value && code.value.trim().length >= 4 && agreed.value && !busy.value)

let timer = null

async function sendCode() {
  error.value = ''
  sending.value = true
  try {
    const res = await api.sendCode(phone.value.trim())
    devCode.value = res.devCode || ''
    seconds.value = 60
    timer = setInterval(() => {
      seconds.value -= 1
      if (seconds.value <= 0) clearInterval(timer)
    }, 1000)
  } catch (e) {
    error.value = e.message
  } finally {
    sending.value = false
  }
}

async function login() {
  error.value = ''
  busy.value = true
  try {
    const res = await api.login(phone.value.trim(), code.value.trim())
    setSession(res.token, res.profile)
    router.replace({ name: 'timeline' })
  } catch (e) {
    error.value = e.message
  } finally {
    busy.value = false
  }
}
</script>

<template>
  <div class="page">
    <h1 class="h1">随访查询</h1>
    <p class="sub">查看您的复查安排与检查报告</p>

    <div v-if="error" class="notice err">{{ error }}</div>

    <div class="card">
      <div class="field">
        <label>手机号</label>
        <input
          v-model="phone"
          type="tel"
          inputmode="numeric"
          maxlength="11"
          placeholder="请输入住院时留的手机号"
        />
      </div>

      <div class="field">
        <label>验证码</label>
        <div style="display: flex; gap: 10px">
          <input v-model="code" inputmode="numeric" maxlength="6" placeholder="6 位数字" />
          <button
            class="btn ghost"
            style="width: 150px; min-height: 52px; font-size: 16px"
            :disabled="!canSend"
            @click="sendCode"
          >
            {{ seconds > 0 ? `${seconds} 秒后重发` : '获取验证码' }}
          </button>
        </div>
      </div>

      <div v-if="devCode" class="notice info">
        开发模式：验证码是 <b>{{ devCode }}</b>（正式环境会通过短信发送）
      </div>

      <label class="row" style="justify-content: flex-start; margin: 4px 0 14px">
        <input
          type="checkbox"
          v-model="agreed"
          style="width: 22px; min-height: 22px; margin-right: 8px"
        />
        <span class="muted">我已阅读并同意《患者信息查询知情同意》</span>
      </label>

      <button class="btn" :disabled="!canLogin" @click="login">
        {{ busy ? '登录中…' : '登录' }}
      </button>
    </div>

    <p class="muted" style="text-align: center; font-size: 14px">
      手机号查不到时，请联系科室工作人员核对住院登记信息
    </p>
  </div>
</template>
