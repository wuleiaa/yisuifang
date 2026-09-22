<script setup>
import { ref, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { api, clearSession } from '../api'

const emit = defineEmits(['logout'])
const router = useRouter()

const me = ref(null)
const error = ref('')

onMounted(async () => {
  try {
    me.value = await api.me()
  } catch (e) {
    error.value = e.message
  }
})

function logout() {
  clearSession()
  emit('logout')
  router.replace({ name: 'login' })
}
</script>

<template>
  <div class="page">
    <h1 class="h1">我的</h1>
    <p class="sub">如果信息有误，请联系科室工作人员更正</p>

    <div v-if="error" class="notice err">{{ error }}</div>

    <div v-if="me" class="card">
      <div class="row">
        <span class="muted">姓名</span><span>{{ me.name }}</span>
      </div>
      <div class="row" style="margin-top: 10px">
        <span class="muted">性别 / 年龄</span><span>{{ me.genderText }} · {{ me.age }} 岁</span>
      </div>
      <div class="row" style="margin-top: 10px">
        <span class="muted">手机号</span><span>{{ me.phoneMask }}</span>
      </div>
      <div class="row" style="margin-top: 10px">
        <span class="muted">病案号</span><span>{{ me.medicalRecordNo }}</span>
      </div>
    </div>

    <div class="card">
      <p class="muted" style="margin: 0">
        您的信息仅用于本科室随访，不会提供给其他机构。
        如有疑问请拨打科室电话。
      </p>
    </div>

    <button class="btn ghost" @click="logout">退出登录</button>
  </div>
</template>
