<script setup>
import { ref, onMounted } from 'vue'
import { api } from '../api'

const data = ref(null)
const error = ref('')

onMounted(async () => {
  try {
    data.value = await api.overview()
  } catch (e) {
    error.value = e.message
  }
})
</script>

<template>
  <div class="page-head">
    <div>
      <h1>概览</h1>
      <div class="sub">科室随访与账号的整体情况</div>
    </div>
  </div>

  <div v-if="error" class="notice err">{{ error }}</div>

  <div v-if="data" class="stats">
    <div class="stat"><b>{{ data.staffTotal }}</b><span>在册人员</span></div>
    <div class="stat"><b>{{ data.doctorCount }}</b><span>主管医生</span></div>
    <div class="stat"><b>{{ data.nurseCount }}</b><span>主管护士</span></div>
    <div class="stat"><b>{{ data.managerCount }}</b><span>管理者</span></div>
    <div class="stat warn"><b>{{ data.pendingTask }}</b><span>待随访任务</span></div>
    <div class="stat danger"><b>{{ data.overdueTask }}</b><span>已逾期任务</span></div>
    <div class="stat"><b>{{ data.todayLogin }}</b><span>今日登录次数</span></div>
    <div class="stat warn"><b>{{ data.disabledCount }}</b><span>已停用账号</span></div>
  </div>

  <div class="card" style="margin-top: 16px">
    <div style="font-weight: 600; margin-bottom: 10px">说明</div>
    <ul style="margin: 0; padding-left: 18px; color: var(--ink-2)">
      <li>科室管理者只能看到并管理本科室人员；系统管理员可管理全院账号。</li>
      <li>账号停用后无法登录，但历史随访记录与任务不受影响。</li>
      <li>所有账号操作（新建、重置密码、停用启用）都会写入审计日志。</li>
    </ul>
  </div>
</template>
