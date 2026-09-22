<script setup>
import { ref, onMounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { api } from '../api'
import { toastMessage, toast, fmtDate } from '../ui'

const route = useRoute()
const router = useRouter()
const loading = ref(true)
const detail = ref(null)

async function load() {
  loading.value = true
  try {
    detail.value = await api.patientDetail(route.params.id)
  } catch (e) {
    toast(e.message)
  } finally {
    loading.value = false
  }
}

function statusText(s) {
  return { PENDING: '待处理', DOING: '处理中', DONE: '已完成', SKIPPED: '已跳过', CANCELLED: '已取消' }[s] || s
}

function openTask(step) {
  if (step.status === 'DONE' || step.status === 'CANCELLED') return
  router.push(`/task/${step.taskId}`)
}

onMounted(load)
</script>

<template>
  <div class="page">
    <header class="appbar">
      <button class="iconbtn" type="button" @click="router.back()">‹</button>
      <h1>患者详情</h1>
    </header>

    <div v-if="loading" class="loading">加载中…</div>

    <template v-else-if="detail">
      <section class="card m14">
        <div style="font-size: 19px; font-weight: 600">
          {{ detail.name }}
          <span class="muted">{{ detail.genderText }} · {{ detail.age }}岁</span>
        </div>
        <div class="muted mt8">
          病案号 {{ detail.medicalRecordNo || '—' }} · 手机 {{ detail.phoneMask }}
        </div>
        <div class="kv mt12"><span class="k">联系地址</span><span class="v">{{ detail.address || '—' }}</span></div>
      </section>

      <div class="sect"><span>住院历史（{{ (detail.encounters || []).length }} 次）</span></div>
      <section class="card" style="margin: 0 14px">
        <div v-for="e in detail.encounters" :key="e.id" class="kv">
          <span class="k" style="width: 100px; flex: 0 0 100px">{{ fmtDate(e.dischargeDate) }}</span>
          <span class="v">
            住院号 {{ e.inpatientNo }}<br />
            <span class="muted">{{ fmtDate(e.admitDate) }} ~ {{ fmtDate(e.dischargeDate) }} · 共 {{ e.stayDays }} 天</span>
          </span>
        </div>
      </section>

      <div class="sect"><span>并行随访路径（{{ (detail.pathways || []).length }} 条）</span></div>

      <section v-for="w in detail.pathways" :key="w.planId" class="card" style="margin: 0 14px 12px">
        <div class="row-between" style="margin-bottom: 14px">
          <strong style="font-size: 14.5px">{{ w.label }}</strong>
          <span class="chip" :class="w.status === 'ACTIVE' ? 'blue' : 'gray'">
            {{ w.status === 'ACTIVE' ? '进行中' : '已结束' }}
          </span>
        </div>

        <div class="tl">
          <div
            v-for="(s, i) in w.steps"
            :key="s.taskId"
            class="row"
            :class="[s.status, s.overdueDays > 0 ? 'overdue' : '']"
            @click="openTask(s)"
          >
            <div class="dot"></div>
            <div v-if="i < w.steps.length - 1" class="line"></div>
            <div class="bd">
              <div class="t">{{ s.title }}</div>
              <div class="d">
                {{ fmtDate(s.dueDate) }} ·
                <span :style="{ color: s.overdueDays > 0 ? 'var(--danger)' : '' }">
                  {{ s.overdueDays > 0 ? `已逾期 ${s.overdueDays} 天` : statusText(s.status) }}
                </span>
                <span v-if="s.mandatory" class="chip warn" style="margin-left: 6px">不可忽略</span>
              </div>
            </div>
          </div>
        </div>
      </section>

      <div
        v-if="(detail.pathways || []).length > 1"
        class="notice info"
      >
        该患者同时进行 {{ detail.pathways.length }} 条随访路径。
        若两条任务的应完成时间相同，可合并为一次电话完成，系统会分别记录两条任务的执行痕迹。
      </div>
    </template>
  </div>

  <div v-if="toastMessage" class="toast">{{ toastMessage }}</div>
</template>
