<script setup>
import { computed, onMounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { getProfile, getToken } from './api'
import { syncReminders, bindNotificationTap } from './notifications'

const route = useRoute()
const router = useRouter()

// 登录页不显示底部导航
const showTab = computed(() => !route.meta.plain)
const profile = computed(() => getProfile())

// 图标统一用细线 SVG，不用 emoji（正式系统里 emoji 观感不合适）
const tabs = [
  {
    key: 'todo',
    path: '/todo',
    label: '待办',
    d: 'M9 11l3 3L22 4M21 12v7a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11'
  },
  {
    key: 'patients',
    path: '/patients',
    label: '患者',
    d: 'M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2M9 3a4 4 0 1 1 0 8 4 4 0 0 1 0-8M23 21v-2a4 4 0 0 0-3-3.87'
  },
  { key: 'me', path: '/me', label: '我的', d: 'M12 4a4 4 0 1 1 0 8 4 4 0 0 1 0-8M6 21v-1a6 6 0 0 1 12 0v1' }
]

const currentTab = computed(() => route.name)

function go(path) {
  router.push(path)
}

/**
 * 打开 App 时同步一次提醒排程（C12）。
 *
 * 本地通知由手机自己排，所以"每次打开同步一次"就是刷新排程的时机：
 * 刚完成的随访任务不会再提醒，新到期的会补上。
 * 在浏览器里 syncReminders() 是空操作，不会报错也不会打扰。
 */
onMounted(() => {
  if (!getToken()) return
  bindNotificationTap()
  syncReminders().catch(() => {})
})
</script>

<template>
  <div class="app-shell">
    <router-view v-slot="{ Component }">
      <component :is="Component" />
    </router-view>

    <nav v-if="showTab" class="tabbar">
      <button
        v-for="t in tabs"
        :key="t.key"
        class="tab"
        :class="{ on: currentTab === t.key || (currentTab === 'task' && t.key === 'todo') || (currentTab === 'patient' && t.key === 'patients') }"
        type="button"
        @click="go(t.path)"
      >
        <span class="ti">
          <svg viewBox="0 0 24 24"><path :d="t.d" /></svg>
        </span>
        <span>{{ t.label }}</span>
      </button>
    </nav>
  </div>
</template>
