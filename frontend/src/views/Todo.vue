<script setup>
import { ref, computed, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { api, getProfile } from '../api'
import { toastMessage, fmtDate } from '../ui'

const router = useRouter()
const loading = ref(true)
const data = ref(null)
const scope = ref('MINE')
const profile = ref(getProfile())

const today = new Date()
const todayText = `${today.getFullYear()}年${today.getMonth() + 1}月${today.getDate()}日`

const groups = computed(() => {
  const items = data.value?.items || []
  return {
    overdue: items.filter((t) => t.urgency === 'OVERDUE'),
    today: items.filter((t) => t.urgency === 'TODAY'),
    later: items.filter((t) => t.urgency === 'LATER')
  }
})

async function load() {
  loading.value = true
  try {
    data.value = await api.todo(scope.value, 7, 100)
  } catch (e) {
    toastMessage.value = e.message
  } finally {
    loading.value = false
  }
}

function switchScope(s) {
  scope.value = s
  load()
}

function openTask(t) {
  router.push(`/task/${t.id}`)
}

onMounted(load)
</script>

<template>
  <div class="page">
    <header class="appbar">
      <div>
        <h1>待办</h1>
        <span class="sub">{{ profile?.name || '医护' }} · {{ profile?.deptName || '' }}</span>
      </div>
      <button class="iconbtn" type="button" title="刷新" @click="load">
        <svg viewBox="0 0 24 24" style="width:18px;height:18px;stroke:currentColor;fill:none;stroke-width:1.6;stroke-linecap:round;stroke-linejoin:round">
          <path d="M21 12a9 9 0 1 1-3-6.7" /><path d="M21 4v5h-5" />
        </svg>
      </button>
    </header>

    <div class="banner">
      <div class="date">{{ todayText }}</div>
      <div class="big">{{ data?.total ?? 0 }} <small>条待办</small></div>
      <div class="row">
        <span>逾期 <b>{{ data?.overdue ?? 0 }}</b></span>
        <span>今日 <b>{{ data?.today ?? 0 }}</b></span>
        <span>本周 <b>{{ data?.later ?? 0 }}</b></span>
      </div>
    </div>

    <div class="opts" style="margin: 14px 14px 6px">
      <div class="opt" :class="{ on: scope === 'MINE' }" @click="switchScope('MINE')">指派给我</div>
      <div class="opt" :class="{ on: scope === 'TEAM' }" @click="switchScope('TEAM')">本组全部</div>
    </div>

    <div v-if="loading" class="loading">加载中…</div>

    <template v-else>
      <template v-if="data?.total">
        <template v-if="groups.overdue.length">
          <div class="sect red"><span>已逾期（{{ groups.overdue.length }}）</span></div>
          <article
            v-for="t in groups.overdue"
            :key="t.id"
            class="task OVERDUE"
            @click="openTask(t)"
          >
            <div class="th">
              <span class="name">{{ t.patientName }}</span>
              <span class="chip teal" v-if="t.pathwayLabel">{{ t.pathwayLabel }}</span>
              <span class="chip red">逾期 {{ t.overdueDays }} 天</span>
              <span class="chip warn" v-if="t.mandatory">不可忽略</span>
            </div>
            <div class="title">{{ t.title }}</div>
            <div class="meta">
              {{ t.genderText }} {{ t.age }}岁 · 住院号 {{ t.inpatientNo }}
              <template v-if="t.procedureName"><br />{{ t.procedureName }}</template>
            </div>
            <div class="foot">
              <span class="time">应完成 {{ fmtDate(t.dueDate) }}</span>
              <button class="btn-primary" type="button" @click.stop="openTask(t)">立即回访</button>
            </div>
          </article>
        </template>

        <template v-if="groups.today.length">
          <div class="sect"><span>今天（{{ groups.today.length }}）</span></div>
          <article
            v-for="t in groups.today"
            :key="t.id"
            class="task TODAY"
            @click="openTask(t)"
          >
            <div class="th">
              <span class="name">{{ t.patientName }}</span>
              <span class="chip teal" v-if="t.pathwayLabel">{{ t.pathwayLabel }}</span>
              <span class="chip blue">今日</span>
            </div>
            <div class="title">{{ t.title }}</div>
            <div class="meta">{{ t.genderText }} {{ t.age }}岁 · 住院号 {{ t.inpatientNo }}</div>
            <div class="foot">
              <span class="time">应完成 {{ fmtDate(t.dueDate) }}</span>
              <button class="btn-primary" type="button" @click.stop="openTask(t)">开始</button>
            </div>
          </article>
        </template>

        <template v-if="groups.later.length">
          <div class="sect"><span>本周及以后（{{ groups.later.length }}）</span></div>
          <article
            v-for="t in groups.later"
            :key="t.id"
            class="task LATER"
            @click="openTask(t)"
          >
            <div class="th">
              <span class="name">{{ t.patientName }}</span>
              <span class="chip gray">{{ fmtDate(t.dueDate) }}</span>
            </div>
            <div class="title">{{ t.title }}</div>
            <div class="meta">{{ t.pathwayLabel || '' }}</div>
          </article>
        </template>
      </template>

      <div v-else class="empty">
        <div class="ic">
          <svg viewBox="0 0 24 24" style="width:44px;height:44px;stroke:var(--ok);fill:none;stroke-width:1.3;stroke-linecap:round;stroke-linejoin:round">
            <circle cx="12" cy="12" r="9" /><path d="M8 12.5l2.6 2.6L16 9.5" />
          </svg>
        </div>
        <div class="t">当前没有待办任务</div>
        <div class="d">所有随访都已完成，辛苦了</div>
      </div>
    </template>
  </div>

  <div v-if="toastMessage" class="toast">{{ toastMessage }}</div>
</template>
