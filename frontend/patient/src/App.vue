<script setup>
import { computed } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { getToken, clearSession } from './api'

const route = useRoute()
const router = useRouter()

const showTab = computed(() => getToken() && !route.meta.public)

function go(name) {
  router.push({ name })
}

function logout() {
  clearSession()
  router.replace({ name: 'login' })
}

defineExpose({ logout })
</script>

<template>
  <div class="app">
    <router-view v-slot="{ Component }">
      <component :is="Component" @logout="logout" />
    </router-view>

    <nav v-if="showTab" class="tabbar">
      <button :class="{ on: route.name === 'timeline' || route.name === 'task' }" @click="go('timeline')">
        <span class="ic">
          <svg viewBox="0 0 24 24"><rect x="3" y="4.5" width="18" height="17" rx="2" /><path d="M16 2.5v4M8 2.5v4M3 11h18" /></svg>
        </span>
        <span>随访安排</span>
      </button>
      <button :class="{ on: route.name === 'reports' }" @click="go('reports')">
        <span class="ic">
          <svg viewBox="0 0 24 24"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z" /><path d="M14 2v6h6M9 15h6M9 18h4" /></svg>
        </span>
        <span>我的报告</span>
      </button>
      <button :class="{ on: route.name === 'me' }" @click="go('me')">
        <span class="ic">
          <svg viewBox="0 0 24 24"><circle cx="12" cy="8" r="4" /><path d="M6 21v-1a6 6 0 0 1 12 0v1" /></svg>
        </span>
        <span>我的</span>
      </button>
    </nav>
  </div>
</template>
