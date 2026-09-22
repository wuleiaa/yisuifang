<script setup>
import { ref, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { api, getProfile, clearSession } from '../api'
import { toastMessage, toast } from '../ui'

const router = useRouter()
const profile = ref(getProfile())
const cryptoOk = ref(null)

async function checkCrypto() {
  try {
    const r = await api.cryptoCheck()
    cryptoOk.value = r
  } catch (e) {
    toast(e.message)
  }
}

function logout() {
  clearSession()
  sessionStorage.removeItem('followup_must_change_pwd')
  router.replace('/login')
}

onMounted(() => {
  profile.value = getProfile()
})
</script>

<template>
  <div class="page">
    <header class="appbar"><h1>我的</h1></header>

    <section class="card m14">
      <div style="font-size: 18px; font-weight: 600">
        {{ profile?.name || '—' }}
        <span class="chip blue" v-if="profile?.manager" style="margin-left: 6px">科室管理者</span>
      </div>
      <div class="muted mt8">
        工号 {{ profile?.staffNo }} · {{ profile?.deptName }}
      </div>
    </section>

    <!-- 账号安全：改密码的入口。
         之前只做了"被强制跳转"那条路，忘了在界面上留个入口，
         结果平时想改密码找不到地方。 -->
    <section class="card m14">
      <div
        class="row-between"
        style="cursor: pointer; padding: 4px 0"
        @click="router.push('/change-password')"
      >
        <div>
          <div style="font-size: 15px">修改密码</div>
          <div class="muted mt8">建议每半年更换一次，保护患者数据</div>
        </div>
        <span style="color: var(--text3); font-size: 20px">›</span>
      </div>
    </section>

    <section class="card m14">
      <div style="font-size: 15px; font-weight: 600; margin-bottom: 12px">安全自检</div>
      <div class="kv"><span class="k">账号</span><span class="v">{{ profile?.staffNo }}</span></div>
      <div class="kv"><span class="k">角色</span><span class="v">{{ profile?.manager ? '科室管理者（可看全科）' : '普通医护（仅看自己主管患者）' }}</span></div>
      <div class="kv">
        <span class="k">加密子系统</span>
        <span class="v">
          <template v-if="cryptoOk">
            <span class="chip" :class="cryptoOk.ok ? 'ok' : 'red'">{{ cryptoOk.message }}</span>
            <br /><span class="muted">脱敏示例 {{ cryptoOk.masked }} · 哈希长度 {{ cryptoOk.hashLength }}</span>
          </template>
          <template v-else>
            <button class="btn-ghost" type="button" @click="checkCrypto">点击自检</button>
          </template>
        </span>
      </div>
    </section>

    <div class="m14">
      <button class="btn-ghost btn-block" type="button" @click="logout">退出登录</button>
    </div>

    <div class="muted" style="text-align: center; margin: 24px 20px 40px; line-height: 2">
      数据仅用于本院随访，不会提供给第三方<br />
      查看完整联系方式会被记入审计日志
    </div>
  </div>

  <div v-if="toastMessage" class="toast">{{ toastMessage }}</div>
</template>
