<script setup>
import { ref, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { api } from '../api'
import { toastMessage, toast } from '../ui'

const router = useRouter()
const loading = ref(true)
const keyword = ref('')
const list = ref([])

async function load() {
  loading.value = true
  try {
    list.value = await api.patients(keyword.value || null, 50)
  } catch (e) {
    toast(e.message)
  } finally {
    loading.value = false
  }
}

function open(p) {
  router.push(`/patient/${p.id}`)
}

onMounted(load)
</script>

<template>
  <div class="page">
    <header class="appbar">
      <div>
        <h1>我的患者</h1>
        <span class="sub">共 {{ list.length }} 人</span>
      </div>
    </header>

    <div class="m14" style="display: flex; gap: 8px">
      <input
        v-model="keyword"
        type="text"
        placeholder="搜索姓名 / 住院号 / 手机号"
        @keyup.enter="load"
      />
      <button class="btn-primary" type="button" @click="load">搜索</button>
    </div>

    <div v-if="loading" class="loading">加载中…</div>

    <template v-else>
      <article v-for="p in list" :key="p.id" class="task LATER" @click="open(p)">
        <div class="th">
          <span class="name">{{ p.name }}</span>
          <span class="muted">{{ p.genderText }} {{ p.age }}岁</span>
          <span v-if="p.overdueTasks > 0" class="chip red">{{ p.overdueTasks }} 条逾期</span>
          <span v-else-if="p.pendingTasks > 0" class="chip blue">{{ p.pendingTasks }} 条待办</span>
          <span v-else class="chip ok">已完成</span>
        </div>
        <div class="meta">
          病案号 {{ p.medicalRecordNo || '—' }} · 手机 {{ p.phoneMask }}
        </div>
      </article>

      <div v-if="!list.length" class="empty">
        <div class="ic">
          <svg viewBox="0 0 24 24" style="width:42px;height:42px;stroke:var(--text3);fill:none;stroke-width:1.3;stroke-linecap:round;stroke-linejoin:round">
            <path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2" /><circle cx="9" cy="7" r="4" /><path d="M23 21v-2a4 4 0 0 0-3-3.87" />
          </svg>
        </div>
        <div class="t">没有找到患者</div>
        <div class="d">换一个关键词试试，或确认是否是你的主管患者</div>
      </div>
    </template>
  </div>

  <div v-if="toastMessage" class="toast">{{ toastMessage }}</div>
</template>
