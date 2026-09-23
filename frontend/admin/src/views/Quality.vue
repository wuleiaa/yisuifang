<script setup>
import { ref, computed, onMounted } from 'vue'
import { api } from '../api'

/**
 * 质控看板（C13）。
 *
 * 给护士长/科室管理者看：本月完成率、逾期、按责任人拆分、近 30 天异常事件。
 * 统计口径在页面底部写着，避免"这个数字怎么算的"来回问；
 * 后端对应 GET /api/admin/qc。
 */
const data = ref(null)
const loading = ref(true)
const error = ref('')

async function load() {
  loading.value = true
  error.value = ''
  try {
    data.value = await api.qc()
  } catch (e) {
    error.value = e.message
  } finally {
    loading.value = false
  }
}

function fmtTime(v) {
  if (!v) return '—'
  return String(v).replace('T', ' ').slice(5, 16)
}

const monthLabel = computed(() => {
  const m = data.value?.month || ''
  return m ? `${m.slice(0, 4)} 年 ${Number(m.slice(5, 7))} 月` : ''
})

onMounted(load)
</script>

<template>
  <div class="page-head">
    <div>
      <h1>质控看板</h1>
      <div class="sub">{{ monthLabel }} · 完成率按"应完成时间"统计，逾期任务计入分母</div>
    </div>
    <button class="btn ghost sm" :disabled="loading" @click="load">
      {{ loading ? '加载中…' : '刷新' }}
    </button>
  </div>

  <div v-if="error" class="notice err">{{ error }}</div>

  <template v-if="data">
    <div class="stats">
      <div class="stat">
        <b>{{ data.completionRate }}%</b>
        <span>本月完成率（{{ data.monthDone }} / {{ data.monthTotal }}）</span>
      </div>
      <div class="stat danger">
        <b>{{ data.overdueOpen }}</b>
        <span>当前逾期未完成</span>
      </div>
      <div class="stat warn">
        <b>{{ data.openTotal }}</b>
        <span>当前待办总数</span>
      </div>
      <div class="stat">
        <b>{{ data.pathologyAvgHours === null ? '—' : data.pathologyAvgHours + ' h' }}</b>
        <span>病理审核平均时长（近 30 天）</span>
      </div>
    </div>

    <div class="card">
      <div class="card-title">按责任人完成情况（本月）</div>
      <div v-if="!data.doctors || !data.doctors.length" class="empty">本月没有应完成的随访任务</div>
      <div v-for="d in data.doctors" :key="d.staffId" class="qc-row">
        <div class="qc-name">{{ d.name }}</div>
        <div class="qc-bar"><i :style="{ width: d.rate + '%' }" :class="{ low: d.rate < 80 }"></i></div>
        <div class="qc-num">
          {{ d.rate }}%<span class="muted">（{{ d.done }}/{{ d.total }}）</span>
        </div>
      </div>
    </div>

    <div class="card">
      <div class="card-title">异常事件（近 30 天）</div>
      <div v-if="!data.abnormalEvents || !data.abnormalEvents.length" class="empty">
        近 30 天没有异常事件
      </div>
      <div v-for="e in data.abnormalEvents" :key="e.recordId" class="qc-ev">
        <div class="qc-ev-hd">
          <b>{{ e.patientName }}</b>
          <span v-if="e.symptomText" class="tag danger">{{ e.symptomText }}</span>
          <span class="tag" :class="e.escalated ? 'ok' : 'warn'">
            {{ e.escalated ? '已上报医生' : '仅记录' }}
          </span>
          <span class="qc-time">{{ fmtTime(e.executedAt) }} · {{ e.executedByName || '—' }}</span>
        </div>
        <div class="qc-ev-msg">{{ e.conclusion || '（未填写结论）' }}</div>
        <div v-if="e.taskTitle" class="qc-time">对应任务：{{ e.taskTitle }}</div>
      </div>
    </div>

    <div class="card">
      <div class="card-title">统计口径</div>
      <ul class="qc-notes">
        <li>本月 = 任务的"应完成时间"落在本月的任务；逾期未完成也计入完成率的分母。</li>
        <li>完成率只看任务状态是否已完成，不区分电话回访或门诊复查。</li>
        <li>病理审核时长 = 近 30 天已审核报告的"录入 → 审核"平均小时数；无数据显示 —。</li>
        <li>异常事件 = 回访中勾选了危险症状（呕血、黑便、便血、发热、黄疸、剧烈腹痛）的记录。</li>
        <li>科室管理者只看本科室；系统管理员看全院。</li>
      </ul>
    </div>
  </template>
</template>
