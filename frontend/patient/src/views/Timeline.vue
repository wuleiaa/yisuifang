<script setup>
import { ref, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { api } from '../api'

const router = useRouter()
const data = ref(null)
const loading = ref(true)
const error = ref('')

function chipClass(item) {
  if (item.status === 'DONE') return 'ok'
  if (item.overdueDays > 0) return 'danger'
  return 'brand'
}

async function load() {
  loading.value = true
  error.value = ''
  try {
    data.value = await api.timeline()
  } catch (e) {
    error.value = e.message
  } finally {
    loading.value = false
  }
}

function open(taskId) {
  router.push({ name: 'task', params: { id: taskId } })
}

onMounted(load)
</script>

<template>
  <div>
    <!-- 顶部问候照片带：患者端除登录页外唯一使用摄影的位置 -->
    <div class="band">
      <img src="/photos/handshake-care.jpg" alt="" />
      <div class="txt">
        <b>您好{{ data?.profile?.name ? `，${data.profile.name}` : '' }}</b>
        <div>这是科室为您安排的复查时间表</div>
      </div>
    </div>

    <div class="page">
      <div v-if="error" class="notice err">{{ error }}</div>

    <div v-if="data" class="stat">
      <div><b>{{ data.doneCount }}</b><span>已完成</span></div>
      <div><b>{{ data.pendingCount }}</b><span>待进行</span></div>
      <div><b>{{ data.overdueCount }}</b><span>已过期</span></div>
    </div>

    <div v-if="loading" class="empty">正在加载…</div>

    <div v-else-if="data && data.items.length === 0" class="empty">
      暂时没有随访安排。<br />如果刚出院，科室会在 1–2 个工作日内为您安排。
    </div>

    <div
      v-for="item in data?.items || []"
      :key="item.taskId"
      class="card tap"
      @click="open(item.taskId)"
    >
      <div class="row">
        <b style="font-size: 18px">{{ item.title }}</b>
        <span class="chip" :class="chipClass(item)">{{ item.statusText }}</span>
      </div>
      <div class="muted" style="margin-top: 6px">
        {{ item.dueDate }} · {{ item.taskTypeText }}
        <span v-if="item.mandatory" class="chip warn" style="margin-left: 6px">重要</span>
      </div>
      <div v-if="item.pathwayLabel" class="muted" style="font-size: 14px">
        {{ item.pathwayLabel }}
      </div>
      <div v-if="item.overdueDays > 0" class="muted" style="color: var(--danger); font-size: 14px">
        已过期 {{ item.overdueDays }} 天，请尽快联系科室
      </div>
      <div v-if="item.conclusion" class="muted" style="font-size: 14px; margin-top: 6px">
        回访结论：{{ item.conclusion }}
      </div>
      </div>
    </div>
  </div>
</template>
