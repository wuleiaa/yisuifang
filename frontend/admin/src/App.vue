<script setup>
import { computed } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { profileRef, clearSession } from './api'

const route = useRoute()
const router = useRouter()

const isLogin = computed(() => route.meta.public)
// 直接引用响应式的 ref：登录成功后侧边栏会立刻显示本人姓名
const profile = computed(() => profileRef.value)

const nav = [
  { name: 'overview', label: '概览', d: 'M3 13h8V3H3zM13 21h8v-8h-8zM13 3v6h8V3zM3 21h8v-4H3z' },
  { name: 'quality', label: '质控看板', d: 'M4 19h16M7 16V9M12 16V5M17 16v-4' },
  { name: 'accounts', label: '账号管理', d: 'M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2M9 3a4 4 0 1 1 0 8 4 4 0 0 1 0-8M23 21v-2a4 4 0 0 0-3-3.87' },
  { name: 'logins', label: '登录记录', d: 'M12 8v4l3 2M12 3a9 9 0 1 0 9 9' },
  { name: 'changePassword', label: '修改密码', d: 'M12 15v2M6 11V8a6 6 0 0 1 12 0v3M5 11h14v10H5z' }
]

function logout() {
  clearSession()
  router.replace({ name: 'login' })
}
</script>

<template>
  <router-view v-if="isLogin" />

  <div v-else class="shell">
    <aside class="side">
      <div class="brand">
        <svg viewBox="0 0 24 24"><path d="M12 3v18M3 12h18" /></svg>
        <div>
          <div class="bn">随访管理后台</div>
          <div class="bs">Follow-up Admin</div>
        </div>
      </div>

      <nav class="nav">
        <button
          v-for="n in nav"
          :key="n.name"
          :class="{ on: route.name === n.name }"
          @click="router.push({ name: n.name })"
        >
          <svg viewBox="0 0 24 24"><path :d="n.d" /></svg>
          <span>{{ n.label }}</span>
        </button>
      </nav>

      <div class="side-foot">
        <div class="who">{{ profile?.name || '管理员' }}</div>
        <div class="who-sub">{{ profile?.deptName || '' }} · {{ profile?.staffNo || '' }}</div>
        <button class="logout" @click="logout">退出登录</button>
      </div>
    </aside>

    <main class="main">
      <router-view />
    </main>
  </div>
</template>
