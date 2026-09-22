<script setup>
import { ref, onMounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { api } from '../api'

const route = useRoute()
const router = useRouter()

const task = ref(null)
const questions = ref([])
const answers = ref({})
const loading = ref(true)
const error = ref('')
const busy = ref(false)
const done = ref(false)

async function load() {
  loading.value = true
  error.value = ''
  try {
    task.value = await api.task(route.params.id)
    const q = await api.questionnaire()
    questions.value = q.questions || []
  } catch (e) {
    error.value = e.message
  } finally {
    loading.value = false
  }
}

function pick(seq, value) {
  answers.value = { ...answers.value, [`q${seq}`]: value }
}

async function submit() {
  const missing = questions.value.filter((q) => q.required && !answers.value[`q${q.seqNo}`])
  if (missing.length) {
    error.value = `还有 ${missing.length} 道必答题没有填`
    return
  }
  error.value = ''
  busy.value = true
  try {
    await api.submitQuestionnaire(route.params.id, answers.value)
    done.value = true
  } catch (e) {
    error.value = e.message
  } finally {
    busy.value = false
  }
}

onMounted(load)
</script>

<template>
  <div class="page">
    <button class="btn ghost" style="width: 110px; min-height: 42px; font-size: 16px; margin-bottom: 12px" @click="router.back()">
      ‹ 返回
    </button>

    <div v-if="error" class="notice err">{{ error }}</div>

    <div v-if="loading" class="empty">正在加载…</div>

    <template v-else-if="task">
      <h1 class="h1">{{ task.title }}</h1>
      <p class="sub">{{ task.dueDate }} · {{ task.taskTypeText }}</p>

      <div class="card">
        <div class="row">
          <span class="muted">当前状态</span>
          <span class="chip" :class="task.status === 'DONE' ? 'ok' : 'brand'">{{ task.statusText }}</span>
        </div>
        <div v-if="task.pathwayLabel" class="row" style="margin-top: 8px">
          <span class="muted">随访路径</span>
          <span>{{ task.pathwayLabel }}</span>
        </div>
        <div v-if="task.conclusion" class="row" style="margin-top: 8px">
          <span class="muted">回访结论</span>
          <span style="text-align: right">{{ task.conclusion }}</span>
        </div>
      </div>

      <div v-if="done" class="notice info">问卷已提交，感谢您的配合。医生会查看您填写的内容。</div>

      <div v-else class="card">
        <b style="font-size: 18px">术后恢复情况问卷</b>
        <p class="muted" style="margin-top: 4px">花一分钟填一下，帮助医生了解您的恢复情况</p>

        <div v-for="q in questions" :key="q.seqNo" style="margin-top: 16px">
          <div style="margin-bottom: 8px">
            {{ q.seqNo }}. {{ q.title }}
            <span v-if="q.required" style="color: var(--danger)">*</span>
          </div>
          <template v-if="q.options.length">
            <button
              v-for="opt in q.options"
              :key="opt"
              class="opt"
              :class="{ on: answers[`q${q.seqNo}`] === opt }"
              @click="pick(q.seqNo, opt)"
            >
              {{ opt }}
            </button>
          </template>
          <textarea
            v-else
            rows="3"
            :value="answers[`q${q.seqNo}`] || ''"
            placeholder="请填写（可不填）"
            @input="pick(q.seqNo, $event.target.value)"
          />
        </div>

        <button class="btn" style="margin-top: 16px" :disabled="busy" @click="submit">
          {{ busy ? '提交中…' : '提交问卷' }}
        </button>
      </div>
    </template>
  </div>
</template>
