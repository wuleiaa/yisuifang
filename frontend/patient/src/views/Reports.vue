<script setup>
import { ref, onMounted } from 'vue'
import { api } from '../api'

const reports = ref([])
const loading = ref(true)
const error = ref('')
const openId = ref(null)

async function load() {
  loading.value = true
  error.value = ''
  try {
    reports.value = await api.reports()
  } catch (e) {
    error.value = e.message
  } finally {
    loading.value = false
  }
}

onMounted(load)
</script>

<template>
  <div class="page">
    <h1 class="h1">我的报告</h1>
    <p class="sub">这里只显示医生已经确认并发布的报告</p>

    <div v-if="error" class="notice err">{{ error }}</div>
    <div v-if="loading" class="empty">正在加载…</div>

    <div v-else-if="reports.length === 0" class="empty">
      暂时没有已发布的报告。<br />报告出来并经过医生确认后，这里就能看到。
    </div>

    <div v-for="r in reports" :key="r.reportId" class="card tap" @click="openId = openId === r.reportId ? null : r.reportId">
      <div class="row">
        <b style="font-size: 18px">{{ r.specimenSite || '病理报告' }}</b>
        <span class="chip" :class="r.riskLevel === 'HIGH' ? 'danger' : 'brand'">{{ r.riskText }}</span>
      </div>
      <div class="muted" style="margin-top: 6px">报告日期 {{ r.reportDate }}</div>

      <div v-if="openId === r.reportId" style="margin-top: 12px; border-top: 1px solid var(--line); padding-top: 12px">
        <div v-if="r.plainText" class="notice info">
          <b>医生解读：</b>{{ r.plainText }}
        </div>
        <p><span class="muted">病理结论：</span>{{ r.conclusion }}</p>
        <p v-if="r.advice"><span class="muted">复诊建议：</span>{{ r.advice }}</p>
        <p v-if="r.recheckMonths" class="muted">建议 {{ r.recheckMonths }} 个月内复查</p>
        <p class="muted" style="font-size: 14px">报告编号 {{ r.reportNo }}</p>
      </div>
      <div v-else class="muted" style="font-size: 14px">点击查看医生解读 ›</div>
    </div>
  </div>
</template>
